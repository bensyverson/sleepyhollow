import Foundation

/// The settle phase of ``PageHost/load(_:budget:)``: what happens between the
/// navigation's load event and the load returning.
///
/// One engine per host, built from ``LoadOptions/wait``. It contributes the
/// instrumentation the host installs before any navigation
/// (``SelectorWatch``, ``IdleWatch``) and then, once the navigation has
/// finished, waits for the condition inside the deadline the host hands it —
/// the same single budget the navigation just spent from.
///
/// **The host owns every clock here.** A condition already true when the load
/// event fires settles immediately; one that never becomes true ends as a
/// ``SleepyError/Kind/timeout`` naming the condition, never as a hang. Where
/// WebKit can push (a selector's `MutationObserver`), the push shortens the
/// latency; where it cannot (arbitrary JavaScript truthiness, network quiet),
/// the engine re-checks on its own cadence. Page-side timers are never a
/// deadline: a headless web view can throttle them, and `requestAnimationFrame`
/// never fires at all with no window to render into.
@MainActor
final class WaitEngine {
    /// One page-side answer to "is the condition met?".
    struct Probe: Friendly {
        /// Whether the condition held at the moment of the check.
        var truthy: Bool
        /// The JavaScript failure that stopped the check, if any.
        var failure: String?
    }

    /// The script-message name ``SelectorWatch`` posts a match on.
    static let messageName: String = "sleepyHollowWait"

    /// How often the host re-checks a selector itself. The observer normally
    /// wins this race; this only has to catch matches that produce no mutation
    /// record, so it is deliberately cheap.
    private static let selectorBackstopInterval: TimeInterval = 0.25

    /// How often a predicate is re-evaluated.
    private static let predicateInterval: TimeInterval = 0.05

    /// How often the page's activity is sampled while waiting for idle.
    private static let idleSampleInterval: TimeInterval = 0.1

    /// The condition being waited for.
    let condition: WaitCondition

    /// Matches pushed by ``SelectorWatch`` for the load in flight.
    private var matches: AsyncStream<String>?

    /// The last JavaScript failure a predicate check reported, so an
    /// exhausted budget can say *why* nothing ever became true.
    private var lastFailure: String?

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
        case .idle:
            [IdleWatch.script]
        case .predicate, .load:
            []
        }
    }

    /// Subscribes to what the page will push, before the navigation starts.
    ///
    /// Called once per load: messages posted while the page is still loading
    /// are buffered by the stream, so a selector that matches mid-load settles
    /// the wait the moment the load event arrives.
    func startWatching(in host: PageHost) {
        guard case .selector = condition else { return }
        matches = host.messages(named: Self.messageName, in: .isolated)
    }

    /// Waits for the condition, or throws.
    ///
    /// - Throws: ``SleepyError/Kind/usage`` when the condition can never be
    ///   met as written (an invalid selector), or ``SleepyError/Kind/timeout``
    ///   when `deadline` passes first. The page is left alone in both cases —
    ///   the host's ``PageHost/facts`` and the live page stay readable, which
    ///   is what "last state attached" means.
    func settle(in host: PageHost, url: URL, by deadline: DispatchTime, budget: TimeInterval) async throws {
        defer { matches = nil }
        switch condition {
        case let .selector(selector):
            try await settleSelector(selector, in: host, url: url, by: deadline, budget: budget)
        case let .predicate(expression):
            try await settlePredicate(expression, in: host, url: url, by: deadline, budget: budget)
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

        var matched = false
        await withTaskGroup(of: Bool.self) { group in
            if let stream = matches {
                group.addTask {
                    for await _ in stream {
                        return true
                    }
                    return false
                }
            }
            group.addTask { [weak self] in
                while DispatchTime.now() < deadline {
                    try? await Task.sleep(nanoseconds: Self.nanoseconds(Self.selectorBackstopInterval))
                    guard let self, !Task.isCancelled else { return false }
                    if let probe = try? await probe(selector: selector, in: host), probe.truthy {
                        return true
                    }
                }
                return false
            }
            while let result = await group.next() {
                if result {
                    matched = true
                    break
                }
                if DispatchTime.now() >= deadline { break }
            }
            group.cancelAll()
        }
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

    private func probe(selector: String, in host: PageHost) async throws -> Probe {
        let text: String = try await host.evaluate(
            SelectorWatch.checkBody,
            arguments: ["sleepySelector": selector],
            in: .isolated,
        )
        return try Self.decode(Probe.self, from: text)
    }

    // MARK: - Predicate

    private func settlePredicate(
        _ expression: String,
        in host: PageHost,
        url: URL,
        by deadline: DispatchTime,
        budget: TimeInterval,
    ) async throws {
        lastFailure = nil
        while true {
            let probe: Probe = await (try? probe(expression: expression, in: host)) ?? Probe(truthy: false)
            if let failure = probe.failure { lastFailure = failure }
            if probe.truthy { return }
            guard DispatchTime.now() < deadline else { break }
            try? await Task.sleep(nanoseconds: Self.nanoseconds(Self.predicateInterval))
        }
        throw timeout(
            url: url,
            budget: budget,
            what: "did not satisfy --wait-for 'js:\(expression)'",
            detail: lastFailure.map { "The predicate threw every time it ran: \($0)." },
            nextMove: "Raise --budget, or fix the expression — it is evaluated in the page's own world and must become truthy.",
        )
    }

    private func probe(expression: String, in host: PageHost) async throws -> Probe {
        // The page's own world: a wait predicate is a statement about the
        // page's state, and an isolated world would read every page global as
        // `undefined` — a silently wrong answer rather than a slow one.
        let text: String = try await host.evaluate(
            """
            try {
              return { truthy: !!(\(expression)) };
            } catch (error) {
              return { truthy: false, failure: String(error) };
            }
            """,
            in: .page,
        )
        return try Self.decode(Probe.self, from: text)
    }

    // MARK: - Idle

    private func settleIdle(
        in host: PageHost,
        url: URL,
        by deadline: DispatchTime,
        budget: TimeInterval,
    ) async throws {
        var previous: IdleWatch.Sample?
        var quietSince = DispatchTime.now()
        var last = IdleWatch.Sample.unknown
        var samplesTaken = 0
        var quietResets = 0
        var failedSamples = 0
        while true {
            let sample: IdleWatch.Sample? = await sample(in: host)
            samplesTaken += 1
            if sample == nil { failedSamples += 1 }
            last = sample ?? last
            let current: IdleWatch.Sample = sample ?? IdleWatch.Sample.unknown
            if current.busy == 0, previous?.activity == current.activity {
                if DispatchTime.now() >= quietSince + IdleWatch.quietWindow { return }
            } else {
                if previous != nil { quietResets += 1 }
                quietSince = DispatchTime.now()
            }
            previous = current
            guard DispatchTime.now() < deadline else { break }
            try? await Task.sleep(nanoseconds: Self.nanoseconds(Self.idleSampleInterval))
        }
        throw timeout(
            url: url,
            budget: budget,
            what: "never went quiet for --wait-for idle",
            detail: "Its last sample had \(last.busy) request(s) or image(s) outstanding "
                + "(\(samplesTaken) samples, \(quietResets) quiet-window resets, "
                + "\(failedSamples) unreadable, final activity count \(last.activity)).",
            nextMove: "Raise --budget, or wait for a selector or 'js:<expression>' — a page that polls is never idle.",
        )
    }

    /// One activity reading; `nil` when the page could not be sampled (the
    /// caller decides what an unreadable page means — see `settleIdle`).
    private func sample(in host: PageHost) async -> IdleWatch.Sample? {
        guard
            let text: String = try? await host.evaluate(IdleWatch.sampleBody, in: .page),
            let sample: IdleWatch.Sample = try? Self.decode(IdleWatch.Sample.self, from: text)
        else {
            return nil
        }
        return sample
    }

    // MARK: - Shared

    private func timeout(
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

    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from text: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }
}
