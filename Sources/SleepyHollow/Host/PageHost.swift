import AppKit
import Foundation
import WebKit

/// The headless `WKWebView` every verb executes against: one page, one load
/// pipeline, one host-side clock.
///
/// A host is built from ``LoadOptions`` and owns everything per-page — the web
/// view and its non-persistent data store, the fixed viewport, the named
/// theme, the dialog policy, the injected scripts, and the baseline console
/// capture. ``load(_:budget:)`` navigates and settles inside a budget the *host*
/// keeps, never the page: a headless web view is free to throttle a hidden
/// page's timers, and it never runs `requestAnimationFrame` at all (unless an
/// operation opts into ``ensureOffscreenWindow()``), so a page-side deadline
/// would lie.
///
/// Nothing hangs, and nothing is reported as the wrong kind of failure. A
/// navigation that never finishes becomes a ``SleepyError`` of kind
/// ``SleepyError/Kind/timeout``; a navigation that fails becomes
/// ``SleepyError/Kind/loadFailure``; and a web content process that dies —
/// under a sandbox, one that never launched at all — becomes a
/// ``SleepyError/Kind/loadFailure`` naming the sandbox instead of a timeout
/// that would send the reader to raise a budget (see
/// ``WebContentProcessFailure``). Because the host outlives
/// the throw, the page's last known state stays readable as ``facts`` — that
/// is the "last state attached" mechanism, kept out of the error so `Core`
/// need not know about pages.
///
/// ```swift
/// let host = PageHost()
/// let facts = try await host.load(url)   // finalURL, status, console errors, dialogs
/// let title = try await host.evaluate("return document.title;")
/// ```
///
/// The host also stamps `NSAppearance(named: .aqua)` on the view to match
/// ``ColorTheme``'s default of ``ColorTheme/light``, so — unlike a raw
/// `WKWebView`, which inherits the Mac's own appearance — a page never
/// renders in Dark Mode unless a caller asks for ``ColorTheme/dark``.
@MainActor
public final class PageHost {
    /// The script-message name the console capture posts on.
    ///
    /// Each message is JSON text carrying `kind` (`console.<level>`,
    /// `uncaught`, or `unhandledrejection`), `level`, `origin`, `text`, and
    /// `timeMilliseconds` — see `ConsoleCapture`. Live subscription via
    /// ``messages(named:in:)`` (in ``InjectedScript/World/page``, where the
    /// capture necessarily lives) is a bonus; the capture also buffers
    /// page-side, which is what one-shot verbs read after the fact.
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
        /// The web content process stopped existing, so nothing the page could
        /// have said will ever arrive — see ``WebContentProcessFailure``.
        case contentProcessEnded(WebContentProcessFailure)
    }

    /// The options this host was built from.
    public let options: LoadOptions

    /// The live web view.
    ///
    /// Exposed deliberately: the capture, find and cookie families need
    /// `WKWebView`'s own APIs (`takeSnapshot`, `printOperation(with:)`, `find`,
    /// `WKHTTPCookieStore`), and a wrapper that only forwarded them would be
    /// an adapter holding no decision. Navigation belongs to ``load(_:budget:)`` —
    /// loading through this property bypasses the budget and the facts.
    public let webView: WKWebView

    /// What the last load reported, kept current as dialogs arrive.
    ///
    /// After a ``SleepyError/Kind/timeout`` this is the page's last known
    /// state — read it from the same host that threw.
    public private(set) var facts: PageFacts = .init()

    /// How the web content process ended during (or since) the last load, and
    /// `nil` while it is alive — which is every ordinary load, including one
    /// that times out.
    ///
    /// Public because it answers "can WebKit start here at all?" without
    /// reading an error message: load anything, and
    /// ``WebContentProcessFailure/neverLaunched`` means the environment, not
    /// the page, is what failed.
    public private(set) var contentProcessFailure: WebContentProcessFailure?

    /// The budget in seconds this host applies to a load that names none of
    /// its own: ``LoadOptions/budget`` or ``LoadOptions/defaultBudget``.
    ///
    /// A per-call override (``load(_:budget:)``) does not change it — it is
    /// the host's default, not a record of the last load.
    public var budget: TimeInterval {
        options.budget ?? LoadOptions.defaultBudget
    }

    /// The viewport this host renders at, in points.
    ///
    /// Initialised from ``LoadOptions/size`` and moved only by
    /// ``PageHost/resize(to:)``, which is what keeps it and the web view's
    /// frame the same fact. Read it rather than the web view's frame: a
    /// full-page capture grows the frame for the duration of one snapshot and
    /// puts it back, and during that window the frame is not the viewport.
    ///
    /// The setter is module-internal only because ``PageHost/resize(to:)``
    /// lives in its own file; nothing else in the library writes it.
    public internal(set) var viewport: ViewportSize

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
    let waiter: WaitEngine?

    /// Where ``LoadOptions/jar`` is read from and written back to. Never
    /// touched unless a jar was named — see ``PageHost/importJarIfNeeded()``.
    let jars: JarStore

    /// Whether this host has already pulled the jar into its cookie store.
    var hasImportedJar = false

    /// The window ``PageHost/ensureOffscreenWindow()`` parked ``webView`` in;
    /// `nil` until an operation asks for one.
    var offscreenWindow: OffscreenWindow?

    private var isLoading = false
    private var hasStartedNavigation = false
    private var pendingNavigation: CheckedContinuation<NavigationOutcome, Never>?
    private var navigationFailure: (any Error)?
    private var budgetTask: Task<Void, Never>?

    /// Creates a headless host: a web view with a non-persistent data store,
    /// the options' viewport and theme, the console capture, and the options'
    /// injected scripts, all installed before any load.
    ///
    /// The data store is non-persistent even when ``LoadOptions/jar`` names a
    /// jar: jar persistence is the host's own import/export around the load
    /// (see ``PageHost/saveJar()``), which is what keeps a bare invocation
    /// from writing anything at all.
    ///
    /// - Parameter options: the load's shape — viewport, theme, injected
    ///   scripts, waiting, and the rest of ``LoadOptions``.
    /// - Parameter jars: where a named jar is read and written; the default
    ///   store honours `SLEEPYHOLLOW_HOME`, and tests inject a throwaway root.
    public init(options: LoadOptions = LoadOptions(), jars: JarStore = JarStore()) {
        self.options = options
        self.jars = jars
        viewport = options.size
        waiter = WaitEngine(condition: options.wait)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        webView = WKWebView(frame: PageHost.frame(for: options.size), configuration: configuration)
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.appearance = NSAppearance(named: options.theme.appearanceName)
        delegate.host = self
        register(messageName: Self.consoleMessageName, in: .page)
        install(ConsoleCapture.script(messageName: Self.consoleMessageName))
        install(SleepyHelpers.script)
        if let waiter {
            // Each in the world its push comes from: a handler registered in
            // the isolated world is invisible to a page-world script, and to
            // the page itself.
            for registration in waiter.messageRegistrations {
                register(messageName: registration.name, in: registration.world)
            }
            for script in waiter.scripts {
                install(script)
            }
        }
        for script in options.scripts {
            install(script)
        }
    }

    /// Navigates to `url` and settles, inside `budget` seconds — or the
    /// host's own ``budget`` when none is given.
    ///
    /// The override exists because a budget is a property of the *call*, not
    /// of the browser: one embedder loads a local fixture in a second and a
    /// third-party page in thirty, and without this it would need a pool of
    /// hosts keyed by budget to say so (the first library embedding did, and
    /// asked — `project/2026-08-29-woodcase-harness-feedback.md`, finding 5).
    /// Whatever applies here bounds the *whole* pipeline — navigation, action
    /// steps and the settle phase share it — and it is the number a timeout
    /// names, so the reader raises the right one.
    ///
    /// Settling is the navigation's load event *and* ``LoadOptions/wait``:
    /// the load event alone for ``WaitCondition/load`` or no condition, and
    /// otherwise the wait engine's selector, predicate, message or idle phase running
    /// on after it. Both phases share the one budget — whatever navigating
    /// spends, waiting does not get again — so a loading verb inherits waiting
    /// by passing its ``LoadOptions`` through unchanged.
    ///
    /// When ``LoadOptions/jar`` names a jar, its cookies are imported before
    /// the first navigation and the store is written back afterwards — after
    /// settling and after the action steps, so a cookie the page sets late
    /// still lands. A load that throws saves too, quietly: a login that
    /// redirected and then timed out has still minted its cookie.
    ///
    /// - Parameter url: where to navigate.
    /// - Parameter budget: seconds this one load gets, or `nil` for the
    ///   host's ``budget``.
    /// - Returns: the load's ``PageFacts`` — also left in ``facts``.
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/timeout`` when the
    ///   budget runs out, whether navigating or waiting (the page's last state
    ///   stays in ``facts``, and the page itself is left alone so it stays
    ///   readable), ``SleepyError/Kind/loadFailure`` when the navigation fails
    ///   or the web content process ends (including
    ///   ``WebContentProcessFailure/neverLaunched``, the sandbox denial that
    ///   used to read as a timeout), ``SleepyError/Kind/environment`` when the options ask for
    ///   something this host does not yet implement, or
    ///   ``SleepyError/Kind/usage`` when a load is already in flight or the
    ///   wait condition can never be met as written.
    ///
    /// - Note: ``PageFacts/consoleErrorCount`` is `0` when a load times out.
    ///   Reading it needs a round-trip to a page that has just proved it will
    ///   not answer, and a tool that can hang is worse than one that reports a
    ///   zero it labels.
    @discardableResult
    public func load(_ url: URL, budget: TimeInterval? = nil) async throws -> PageFacts {
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
        let applied: TimeInterval = budget ?? self.budget
        try await importJarIfNeeded()
        do {
            let loaded: PageFacts = try await navigateAndSettle(url, within: applied)
            try await saveJar()
            return loaded
        } catch {
            await saveJarIgnoringFailure()
            throw error
        }
    }

    /// The load pipeline proper: navigate, settle, act, all inside `budget`.
    /// Split out of ``load(_:budget:)`` so the jar's import and export can
    /// bracket every exit.
    private func navigateAndSettle(_ url: URL, within budget: TimeInterval) async throws -> PageFacts {
        facts = PageFacts()
        navigationFailure = nil
        contentProcessFailure = nil
        hasStartedNavigation = false
        delegate.mainFrameStatus = nil

        // One deadline for the whole pipeline: whatever navigating spends, the
        // settle phase does not get again.
        let deadline = DispatchTime.now() + budget
        waiter?.startWatching(in: self)
        let outcome: NavigationOutcome = await navigate(to: url, within: budget)
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
            // Steps before the wait: the vision doc's ruling (corrected
            // 2026-08-20) makes ``LoadOptions/wait`` the final gate after the
            // steps, so it can name a condition the steps produce.
            try await runActionSteps(by: deadline)
            // A step may have navigated — even to the same URL; the facts must
            // describe the page the steps produced, the same one the verb's
            // read is about to see.
            if !options.steps.isEmpty {
                facts.finalURL = webView.url
                facts.httpStatus = delegate.mainFrameStatus
            }
            try await waiter?.settle(in: self, url: url, by: deadline, budget: budget)
            facts.consoleErrorCount = await consoleErrorCount()
            return facts
        case .failed:
            throw loadFailure(url: url, error: navigationFailure)
        case .timedOut:
            webView.stopLoading()
            throw timeout(url: url, budget: budget)
        case let .contentProcessEnded(failure):
            throw failure.error(url: url)
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

    /// Notes that WebKit has begun the navigation — its provisional load
    /// started, or the page committed.
    ///
    /// The only thing this records is that the web content process was alive
    /// and talking, which is what tells a dead process apart from one that
    /// never launched.
    func noteNavigationStarted() {
        hasStartedNavigation = true
    }

    /// Reports that the web content process has stopped existing, classified
    /// by how far the navigation had got.
    ///
    /// This is the seam WebKit's `webViewWebContentProcessDidTerminate(_:)`
    /// calls, and the one a test drives directly — the harness sandbox that
    /// produces the real signal cannot be relied on inside a test run.
    public func reportContentProcessTermination() {
        reportContentProcessTermination(hasStartedNavigation ? .crashedMidLoad : .neverLaunched)
    }

    /// Reports a named web content process ending, failing the navigation in
    /// flight with it.
    ///
    /// Nothing more can arrive from a process that is gone, so the load ends
    /// here rather than sitting out its budget and reporting a timeout it did
    /// not earn. With no navigation pending this only records `failure` in
    /// ``contentProcessFailure``.
    ///
    /// - Parameter failure: what the ending means — see
    ///   ``WebContentProcessFailure``.
    public func reportContentProcessTermination(_ failure: WebContentProcessFailure) {
        contentProcessFailure = failure
        finishNavigation(.contentProcessEnded(failure))
    }

    /// Records a dialog the policy answered.
    func record(_ dialog: DialogRecord) {
        facts.dialogs.append(dialog)
    }

    // MARK: - Navigation

    private func navigate(to url: URL, within budget: TimeInterval) async -> NavigationOutcome {
        let outcome: NavigationOutcome = await withCheckedContinuation { continuation in
            pendingNavigation = continuation
            budgetTask = Task { @MainActor [weak self] in
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

    private func timeout(url: URL, budget: TimeInterval) -> SleepyError {
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
}
