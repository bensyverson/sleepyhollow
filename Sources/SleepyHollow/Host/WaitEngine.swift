import Foundation

/// The settle phase of ``PageHost/load(_:budget:)``: what happens between the
/// navigation's load event and the load returning.
///
/// One engine per host, built from ``LoadOptions/wait``. It contributes the
/// instrumentation the host installs before any navigation
/// (``SelectorWatch``, ``PredicateWatch``, ``IdleWatch``) and the
/// script-message handlers that instrumentation posts on, and then, once the
/// navigation has finished, waits for the condition inside the deadline the
/// host hands it — the same single budget the navigation just spent from.
///
/// **The host owns every clock, and the page does every check it can.** A
/// condition already true when the load event fires settles immediately; one
/// that never becomes true ends as a ``SleepyError/Kind/timeout`` naming the
/// condition, never as a hang. A selector, a predicate and a page-posted
/// message all reach the host as a *push*, because the host's own re-check
/// runs on the main actor and an embedding that saturates it never schedules
/// one — measured as a 10s timeout on a page ready at 200 ms
/// (`project/2026-08-29-woodcase-harness-feedback.md`, finding 1). What
/// remains host-side is a slow backstop for the pushes that cannot happen
/// (a selector matching with no mutation record; an expression that does not
/// parse) and ``WaitCondition/idle``, whose quiet window is deliberately the
/// host's to measure. Page-side timers are never a deadline: `setTimeout`
/// keeps wall time in this WebKit, but `requestAnimationFrame` never fires at
/// all with no window to render into.
@MainActor
final class WaitEngine {
    /// One page-side answer to "is the condition met?".
    struct Probe: Friendly {
        /// Whether the condition held at the moment of the check.
        var truthy: Bool
        /// The JavaScript failure that stopped the check, if any.
        var failure: String?
    }

    /// One script-message handler the host must register before it navigates.
    struct MessageRegistration: Friendly {
        /// The handler name the page posts to.
        var name: String
        /// The world the page's post comes from — instrumentation posts from
        /// the world its script runs in, and a page posts from its own.
        var world: InjectedScript.World
    }

    /// The script-message name ``SelectorWatch`` and ``PredicateWatch`` push on.
    static let messageName: String = "sleepyHollowWait"

    /// The handler names the tool's own instrumentation posts on, which a
    /// ``WaitCondition/message(_:)`` may not borrow: a post to one of these is
    /// instrumentation talking, not the page saying it is ready, and settling
    /// on it would be a plausible wrong answer.
    static let reservedMessageNames: Set<String> = [messageName, PageHost.consoleMessageName]

    /// Whether a page may be waited on for posts to `name`.
    static func isWaitableMessageName(_ name: String) -> Bool {
        WaitCondition.isValidMessageName(name) && !reservedMessageNames.contains(name)
    }

    /// How often the host re-checks a pushed condition itself. The page
    /// normally wins this race; the backstop only has to catch what produces
    /// no push, so it is deliberately cheap.
    ///
    /// A `var` so a test can push it past the whole run and prove the *page*
    /// settled the wait; nothing outside the engine changes it in production.
    var backstopInterval: TimeInterval = 0.25

    /// How many host-side checks have run for this engine — the evidence that
    /// a wait settled on the page's push rather than on the host asking again.
    var probeCount: Int = 0

    /// The condition being waited for.
    let condition: WaitCondition

    /// What the page pushes for the load in flight.
    private var pushes: AsyncStream<String>?

    /// The last JavaScript failure a predicate check reported, from either
    /// side, so an exhausted budget can say *why* nothing ever became true.
    var lastFailure: String?

    /// Creates the engine for a wait condition, or `nil` when the load event
    /// alone is the condition — `nil` and ``WaitCondition/load`` need no
    /// settle phase, so the host skips one entirely.
    init?(condition: WaitCondition?) {
        switch condition {
        case .none, .some(.load):
            return nil
        case let .some(other):
            self.condition = other
        }
    }

    /// The instrumentation the host must install before it navigates.
    var scripts: [InjectedScript] {
        switch condition {
        case let .selector(selector):
            [SelectorWatch.script(selector: selector, messageName: Self.messageName)]
        case let .predicate(expression):
            [PredicateWatch.script(expression: expression, messageName: Self.messageName)]
        case .idle:
            [IdleWatch.script]
        case .message, .load:
            []
        }
    }

    /// The script-message handlers the host must register before it navigates
    /// — each in the world the push comes from, since a handler registered in
    /// one world is invisible from the other.
    ///
    /// Empty for a ``WaitCondition/message(_:)`` whose name is not an
    /// identifier: nothing may be handed to WebKit that no page could post
    /// to, and ``settle(in:url:by:budget:)`` refuses it as a usage error.
    var messageRegistrations: [MessageRegistration] {
        switch condition {
        case .selector:
            [MessageRegistration(name: Self.messageName, world: .isolated)]
        case .predicate:
            [MessageRegistration(name: Self.messageName, world: .page)]
        case let .message(name):
            Self.isWaitableMessageName(name) ? [MessageRegistration(name: name, world: .page)] : []
        case .idle, .load:
            []
        }
    }

    /// Subscribes to what the page will push, before the navigation starts.
    ///
    /// Called once per load: messages posted while the page is still loading
    /// are buffered by the stream, so a condition that comes true mid-load
    /// settles the wait the moment the load event arrives.
    func startWatching(in host: PageHost) {
        for registration in messageRegistrations {
            pushes = host.messages(named: registration.name, in: registration.world)
        }
    }

    /// Waits for the condition, or throws.
    ///
    /// - Throws: ``SleepyError/Kind/usage`` when the condition can never be
    ///   met as written (an invalid selector, a handler name that is not an
    ///   identifier), or ``SleepyError/Kind/timeout`` when `deadline` passes
    ///   first. The page is left alone in both cases — the host's
    ///   ``PageHost/facts`` and the live page stay readable, which is what
    ///   "last state attached" means.
    func settle(in host: PageHost, url: URL, by deadline: DispatchTime, budget: TimeInterval) async throws {
        defer { pushes = nil }
        switch condition {
        case let .selector(selector):
            try await settleSelector(selector, in: host, url: url, by: deadline, budget: budget)
        case let .predicate(expression):
            try await settlePredicate(expression, in: host, url: url, by: deadline, budget: budget)
        case let .message(name):
            try await settleMessage(name, url: url, by: deadline, budget: budget)
        case .idle:
            try await settleIdle(in: host, url: url, by: deadline, budget: budget)
        case .load:
            break
        }
    }

    // MARK: - Selector

    private func settleSelector(
        _ selector: String,
        in host: PageHost,
        url: URL,
        by deadline: DispatchTime,
        budget: TimeInterval,
    ) async throws {
        // A check that cannot run at all (a frame torn down mid-load, say) is
        // not an answer: fall through to the race rather than throwing WebKit's
        // error out of `load`.
        let first: Probe = await (try? probe(selector: selector, in: host)) ?? Probe(truthy: false)
        if let failure = first.failure {
            throw SleepyError(
                kind: .usage,
                message: "'\(selector)' is not a selector this page can match: \(failure)",
                nextMove: "Give --wait-for a valid CSS selector, or 'js:<expression>' for anything else.",
            )
        }
        if first.truthy { return }

        let matched: Bool = await race(
            by: deadline,
            accepting: { _ in true },
            checking: { [weak self] in
                guard let self else { return false }
                let probe: Probe? = try? await probe(selector: selector, in: host)
                return probe?.truthy == true
            },
        )
        guard matched else {
            throw timeout(
                url: url,
                budget: budget,
                what: "did not match --wait-for '\(selector)'",
                detail: nil,
                nextMove: "Raise --budget, or check the selector against the page you get with --wait-for load.",
            )
        }
    }

    /// One host-side check of the selector, counted in ``probeCount``.
    private func probe(selector: String, in host: PageHost) async throws -> Probe {
        probeCount += 1
        let text: String = try await host.evaluate(
            SelectorWatch.checkBody,
            arguments: ["sleepySelector": selector],
            in: .isolated,
        )
        return try Self.decode(Probe.self, from: text)
    }

    // MARK: - Message

    private func settleMessage(
        _ name: String,
        url: URL,
        by deadline: DispatchTime,
        budget: TimeInterval,
    ) async throws {
        guard WaitCondition.isValidMessageName(name) else {
            throw SleepyError(
                kind: .usage,
                message: "'\(name)' is not a script-message handler name a page can post to.",
                nextMove: "Name a plain identifier — letters, digits, '_' or '$', not starting with a digit — "
                    + "as in --wait-for message:appReady.",
            )
        }
        guard !Self.reservedMessageNames.contains(name) else {
            throw SleepyError(
                kind: .usage,
                message: "'\(name)' is the tool's own script-message handler, so a post to it is "
                    + "instrumentation rather than the page saying it is ready.",
                nextMove: "Wait on a handler of the page's own, as in --wait-for message:appReady.",
            )
        }
        // Nothing to check host-side: only the page knows, and it says so by
        // posting. The race carries the deadline alone.
        let posted: Bool = await race(by: deadline, accepting: { _ in true })
        guard posted else {
            throw timeout(
                url: url,
                budget: budget,
                what: "never posted to --wait-for 'message:\(name)'",
                detail: nil,
                nextMove: "Raise --budget, or have the page call "
                    + "window.webkit.messageHandlers.\(name).postMessage(...) when it is ready.",
            )
        }
    }

    // MARK: - Shared

    /// Races what the page pushes against a host-side re-check, ending at
    /// `deadline` either way.
    ///
    /// - Parameter accept: whether a pushed message ends the wait.
    /// - Parameter check: the backstop, run every ``backstopInterval``; `nil`
    ///   for a condition only the page can answer, which leaves the deadline
    ///   as the race's other half.
    /// - Returns: whether the condition held before `deadline`.
    func race(
        by deadline: DispatchTime,
        accepting accept: @escaping @Sendable (String) async -> Bool,
        checking check: (@Sendable () async -> Bool)? = nil,
    ) async -> Bool {
        let interval: TimeInterval = backstopInterval
        var settled = false
        await withTaskGroup(of: Bool.self) { group in
            if let stream = pushes {
                group.addTask {
                    for await text in stream {
                        if await accept(text) { return true }
                    }
                    return false
                }
            }
            if let check {
                group.addTask {
                    while DispatchTime.now() < deadline {
                        // Never sleep past the deadline: the backstop is the
                        // slow half of this race, and a settle phase that
                        // outlives its budget is the hang the whole engine
                        // exists to rule out.
                        try? await Task.sleep(nanoseconds: Self.nanoseconds(interval, notPast: deadline))
                        guard !Task.isCancelled, DispatchTime.now() < deadline else { return false }
                        if await check() { return true }
                    }
                    return false
                }
            } else {
                group.addTask {
                    try? await Task.sleep(nanoseconds: Self.nanoseconds(.infinity, notPast: deadline))
                    return false
                }
            }
            while let result = await group.next() {
                if result {
                    settled = true
                    break
                }
                if DispatchTime.now() >= deadline { break }
            }
            group.cancelAll()
        }
        return settled
    }

    /// The ``SleepyError/Kind/timeout`` a spent budget earns: what the page
    /// did not do, and whatever detail the last check gathered.
    func timeout(
        url: URL,
        budget: TimeInterval,
        what: String,
        detail: String?,
        nextMove: String,
    ) -> SleepyError {
        let extra: String = detail.map { " \($0)" } ?? ""
        return SleepyError(
            kind: .timeout,
            message: "\(url.absoluteString) loaded but \(what) within \(budget)s.\(extra)",
            nextMove: nextMove,
        )
    }

    /// `seconds` as nanoseconds, never negative.
    static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }

    /// `seconds` as nanoseconds, clamped to what is left before `deadline` —
    /// pass `.infinity` to sleep exactly until it.
    static func nanoseconds(_ seconds: TimeInterval, notPast deadline: DispatchTime) -> UInt64 {
        let now = DispatchTime.now()
        guard deadline > now else { return 0 }
        let remaining: UInt64 = deadline.uptimeNanoseconds - now.uptimeNanoseconds
        guard seconds.isFinite else { return remaining }
        return min(nanoseconds(seconds), remaining)
    }

    /// Decodes one page-side JSON answer.
    static func decode<Value: Decodable>(_ type: Value.Type, from text: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }
}
