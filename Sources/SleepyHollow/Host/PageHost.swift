import AppKit
import Foundation
import WebKit

/// The headless `WKWebView` every verb executes against: one page, one load
/// pipeline, one host-side clock.
///
/// A host is built from ``LoadOptions`` and owns everything per-page — the web
/// view and its non-persistent data store, the fixed viewport, the named
/// theme, the dialog policy, the injected scripts, and the baseline console
/// capture. ``load(_:)`` navigates and settles inside a budget the *host*
/// keeps, never the page: a headless web view is free to throttle a hidden
/// page's timers, and it never runs `requestAnimationFrame` at all, so a
/// page-side deadline would lie.
///
/// Nothing hangs. A navigation that never finishes becomes a
/// ``SleepyError`` of kind ``SleepyError/Kind/timeout``; a navigation that
/// fails becomes ``SleepyError/Kind/loadFailure``. Because the host outlives
/// the throw, the page's last known state stays readable as ``facts`` — that
/// is the "last state attached" mechanism, kept out of the error so `Core`
/// need not know about pages.
///
/// ```swift
/// let host = PageHost()
/// let facts = try await host.load(url)   // finalURL, status, console errors, dialogs
/// let title = try await host.evaluate("return document.title;")
/// ```
@MainActor
public final class PageHost {
    /// The script-message name the baseline console capture posts on.
    ///
    /// Each message is JSON text: `{"kind": "console.error" | "uncaught" |
    /// "unhandledrejection", "text": "…"}`. The console verb subscribes with
    /// ``messages(named:in:)`` — in ``InjectedScript/World/page``, where the
    /// capture necessarily lives.
    public static let consoleMessageName: String = "sleepyHollowConsole"

    /// How a navigation ended. The failure itself is held in
    /// ``navigationFailure`` so the outcome stays `Sendable`.
    enum NavigationOutcome {
        /// The navigation reached its load event.
        case finished
        /// The navigation failed; see ``PageHost/navigationFailure``.
        case failed
        /// The host's budget ran out first.
        case timedOut
    }

    /// The options this host was built from.
    public let options: LoadOptions

    /// The live web view.
    ///
    /// Exposed deliberately: the capture, find and cookie families need
    /// `WKWebView`'s own APIs (`takeSnapshot`, `createPDF`, `find`,
    /// `WKHTTPCookieStore`), and a wrapper that only forwarded them would be
    /// an adapter holding no decision. Navigation belongs to ``load(_:)`` —
    /// loading through this property bypasses the budget and the facts.
    public let webView: WKWebView

    /// What the last load reported, kept current as dialogs arrive.
    ///
    /// After a ``SleepyError/Kind/timeout`` this is the page's last known
    /// state — read it from the same host that threw.
    public private(set) var facts: PageFacts = .init()

    /// The budget in seconds this host applies to a load: ``LoadOptions/budget``
    /// or ``LoadOptions/defaultBudget``.
    public var budget: TimeInterval {
        options.budget ?? LoadOptions.defaultBudget
    }

    /// One subscriber to a script-message name.
    struct MessageSink {
        /// Identifies the sink so termination removes exactly this one.
        let id: Int
        /// Where delivered messages go.
        let continuation: AsyncStream<String>.Continuation
    }

    let delegate: PageHostDelegate = .init()

    /// Continuations waiting on script messages, keyed by handler name.
    var messageSinks: [String: [MessageSink]] = [:]

    /// Handler names already registered, per world, so registering twice is a
    /// no-op rather than a WebKit exception.
    var registeredMessageNames: Set<String> = []

    /// Hands out sink identities.
    var nextMessageSinkID: Int = 0

    /// The settle phase for ``LoadOptions/wait``; `nil` when the load event
    /// alone is the condition.
    private let waiter: WaitEngine?

    private var isLoading = false
    private var pendingNavigation: CheckedContinuation<NavigationOutcome, Never>?
    private var navigationFailure: (any Error)?
    private var budgetTask: Task<Void, Never>?

    /// Creates a headless host: a web view with a non-persistent data store,
    /// the options' viewport and theme, the console capture, and the options'
    /// injected scripts, all installed before any load.
    public init(options: LoadOptions = LoadOptions()) {
        self.options = options
        waiter = WaitEngine(condition: options.wait)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        webView = WKWebView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: CGFloat(options.size.width),
                height: CGFloat(options.size.height),
            ),
            configuration: configuration,
        )
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.appearance = NSAppearance(named: options.theme.appearanceName)
        delegate.host = self
        register(messageName: Self.consoleMessageName, in: .page)
        install(ConsoleCapture.script(messageName: Self.consoleMessageName))
        if let waiter {
            register(messageName: WaitEngine.messageName, in: .isolated)
            for script in waiter.scripts {
                install(script)
            }
        }
        for script in options.scripts {
            install(script)
        }
    }

    /// Navigates to `url` and settles, inside the host's ``budget``.
    ///
    /// Settling is the navigation's load event *and* ``LoadOptions/wait``:
    /// the load event alone for ``WaitCondition/load`` or no condition, and
    /// otherwise the wait engine's selector, predicate or idle phase running
    /// on after it. Both phases share the one budget — whatever navigating
    /// spends, waiting does not get again — so a loading verb inherits waiting
    /// by passing its ``LoadOptions`` through unchanged.
    ///
    /// - Returns: the load's ``PageFacts`` — also left in ``facts``.
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/timeout`` when the
    ///   budget runs out, whether navigating or waiting (the page's last state
    ///   stays in ``facts``, and the page itself is left alone so it stays
    ///   readable), ``SleepyError/Kind/loadFailure`` when the navigation
    ///   fails, ``SleepyError/Kind/environment`` when the options ask for
    ///   something this host does not yet implement, or
    ///   ``SleepyError/Kind/usage`` when a load is already in flight or the
    ///   wait condition can never be met as written.
    ///
    /// - Note: ``PageFacts/consoleErrorCount`` is `0` when a load times out.
    ///   Reading it needs a round-trip to a page that has just proved it will
    ///   not answer, and a tool that can hang is worse than one that reports a
    ///   zero it labels.
    @discardableResult
    public func load(_ url: URL) async throws -> PageFacts {
        // Set synchronously, before the first suspension: two `load` calls can
        // otherwise interleave on the main actor and the first navigation's
        // continuation is lost — which is a hang, the one thing forbidden.
        guard !isLoading else {
            throw SleepyError(
                kind: .usage,
                message: "This host is already loading a page.",
                nextMove: "Await the load in flight, or use one host per page.",
            )
        }
        isLoading = true
        defer { isLoading = false }
        try validateSupportedOptions()
        facts = PageFacts()
        navigationFailure = nil
        delegate.mainFrameStatus = nil

        // One deadline for the whole pipeline: whatever navigating spends, the
        // settle phase does not get again.
        let deadline = DispatchTime.now() + budget
        waiter?.startWatching(in: self)
        let outcome: NavigationOutcome = await navigate(to: url)
        facts.finalURL = webView.url
        switch outcome {
        case .finished:
            // WebKit refuses requests to its blocked ports (9, 25, …) by
            // finishing an about:blank navigation instead of failing — an
            // honest "finished" that is still not the page that was asked for.
            let landed: String? = webView.url?.absoluteString
            if url.absoluteString != "about:blank", landed == nil || landed == "about:blank" {
                throw SleepyError(
                    kind: .loadFailure,
                    message: "Could not load \(url.absoluteString): WebKit refused the request and settled on about:blank.",
                    nextMove: "Check the URL — WebKit refuses well-known service ports (9, 25, …) and unsupported schemes.",
                )
            }
            // Recorded before settling, so a wait that exhausts the budget
            // still leaves the page's status in ``facts``.
            facts.httpStatus = delegate.mainFrameStatus
            try await waiter?.settle(in: self, url: url, by: deadline, budget: budget)
            facts.consoleErrorCount = await consoleErrorCount()
            return facts
        case .failed:
            throw loadFailure(url: url, error: navigationFailure)
        case .timedOut:
            webView.stopLoading()
            throw timeout(url: url)
        }
    }

    // MARK: - Delegate callbacks

    /// Ends the pending navigation with `outcome`; later callbacks are ignored.
    func finishNavigation(_ outcome: NavigationOutcome, failure: (any Error)? = nil) {
        guard let continuation = pendingNavigation else { return }
        pendingNavigation = nil
        navigationFailure = failure
        continuation.resume(returning: outcome)
    }

    /// Records a dialog the policy answered.
    func record(_ dialog: DialogRecord) {
        facts.dialogs.append(dialog)
    }

    // MARK: - Navigation

    private func navigate(to url: URL) async -> NavigationOutcome {
        let outcome: NavigationOutcome = await withCheckedContinuation { continuation in
            pendingNavigation = continuation
            budgetTask = Task { @MainActor [weak self, budget] in
                try? await Task.sleep(nanoseconds: UInt64(max(0, budget) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finishNavigation(.timedOut)
            }
            webView.load(URLRequest(url: url))
        }
        budgetTask?.cancel()
        budgetTask = nil
        return outcome
    }

    private func consoleErrorCount() async -> Int {
        guard let text: String = try? await evaluate(ConsoleCapture.countExpression, in: .page) else {
            return 0
        }
        return Int(text) ?? 0
    }

    // MARK: - Failures

    private func timeout(url: URL) -> SleepyError {
        let reached: String = facts.finalURL.map { " Last known page: \($0.absoluteString)." } ?? ""
        return SleepyError(
            kind: .timeout,
            message: "\(url.absoluteString) did not finish loading within \(budget)s.\(reached)",
            nextMove: "Raise the budget, or state the condition you are waiting for with --wait-for.",
        )
    }

    private func loadFailure(url: URL, error: (any Error)?) -> SleepyError {
        let reason: String = (error as NSError?).map { "\($0.localizedDescription) (\($0.domain) \($0.code))" }
            ?? "the navigation failed without a reason."
        return SleepyError(
            kind: .loadFailure,
            message: "Could not load \(url.absoluteString): \(reason)",
            nextMove: "Check the URL and that its host is reachable from this machine.",
        )
    }

    /// Rejects options whose implementation belongs to a later leaf, naming it,
    /// rather than half-honouring them.
    private func validateSupportedOptions() throws {
        if let jar: JarName = options.jar {
            throw SleepyError(
                kind: .environment,
                message: "Cookie jar '\(jar)' was requested, but this host only has an in-memory store.",
                nextMove: "Jars land with leaf XDmfo; until then run without --jar.",
            )
        }
        if !options.steps.isEmpty {
            throw SleepyError(
                kind: .environment,
                message: "\(options.steps.count) action step(s) were requested, but this host cannot act yet.",
                nextMove: "Action steps land with leaf q6mlw; until then load without --click/--fill/--submit.",
            )
        }
    }
}
