import Foundation

public extension PageHost {
    /// The script-message name ``waitUntil(_:in:budget:)``'s page-side watch
    /// posts on — reserved, like ``consoleMessageName``, so a
    /// ``WaitCondition/message(_:)`` cannot mistake it for the page.
    static let waitUntilMessageName: String = "sleepyHollowWaitUntil"

    /// Waits, on a page that is already loaded, until the JavaScript
    /// `expression` is truthy — or throws once `budget` seconds pass.
    ///
    /// The load-time `--wait-for js:` for the moments after a load: an
    /// embedder that clicked, typed or evaluated something and must wait for
    /// the page to react.
    ///
    /// ```swift
    /// try await host.evaluate("document.querySelector('#go').click(); return null;", in: .page)
    /// try await host.waitUntil("document.querySelector('.result') !== null")
    /// ```
    ///
    /// **The page checks; the host never polls.** One evaluation starts
    /// ``PredicateWatch`` in the page, which re-evaluates `expression` on the
    /// page's own clock and posts once when it holds; the host awaits that
    /// one message against its own deadline. A host-side poll would run on
    /// the main actor, and an embedding that keeps the main actor busy would
    /// then time out on a page that was ready long before — measured
    /// (`project/2026-08-29-woodcase-harness-feedback.md`, finding 1). The page
    /// is held at foreground priority for the wait, since an idle windowless
    /// page is otherwise throttled until a call lifts it.
    ///
    /// A check that throws counts as "not yet", exactly as for
    /// `--wait-for js:`; the first such failure is what a timeout reports.
    /// A timeout leaves the host reusable — nothing is abandoned, the page
    /// simply stops checking soon after. On a hidden page, WebKit may slow a
    /// long chain of page timers to about once a second, so a wait can end
    /// up to a second after the condition first holds.
    ///
    /// - Parameter expression: a JavaScript expression, evaluated as
    ///   `!!(expression)`.
    /// - Parameter world: ``InjectedScript/World/page`` by default — a wait
    ///   is a question about the page's own state, and an isolated world
    ///   reads every page global as `undefined`, which would never come true.
    /// - Parameter budget: seconds to wait, or `nil` for the host's
    ///   ``budget``.
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/timeout`` naming
    ///   the expression, the budget and any failure the check threw;
    ///   ``EvaluationError/javaScript(message:)`` at once when `expression`
    ///   does not parse; `CancellationError` when the caller is cancelled.
    func waitUntil(
        _ expression: String,
        in world: InjectedScript.World = .page,
        budget: TimeInterval? = nil,
    ) async throws {
        let applied: TimeInterval = budget ?? self.budget
        let deadline: DispatchTime = .now() + applied
        let watch: String = UUID().uuidString
        // Subscribe before arming: the watch may post before the arming call
        // even returns.
        let pushes: AsyncStream<String> = messages(named: Self.waitUntilMessageName, in: world)
        let outcome: WatchOutcome = try await holdingForeground {
            let first: WaitEngine.Probe = try await evaluate(
                PredicateWatch.armingBody(
                    expression: expression,
                    messageName: Self.waitUntilMessageName,
                    watch: watch,
                    lifetime: applied,
                ),
                as: WaitEngine.Probe.self,
                in: world,
                budget: applied,
            )
            if first.truthy { return WatchOutcome(satisfied: true, failure: nil) }
            let later: WatchOutcome = await Self.awaitPush(on: pushes, for: watch, by: deadline)
            return WatchOutcome(satisfied: later.satisfied, failure: later.failure ?? first.failure)
        }
        if outcome.satisfied { return }
        try Task.checkCancellation()
        let reason: String = outcome.failure.map { " The check threw every time it ran: \($0)." } ?? ""
        throw SleepyError(
            kind: .timeout,
            message: "The page did not satisfy '\(expression)' within \(applied)s.\(reason)",
            nextMove: "Raise the budget, or fix the expression — it is evaluated in the "
                + "\(world == .page ? "page's own" : "isolated") world and must become truthy.",
        )
    }
}

extension PageHost {
    /// How a page-side watch ended, as far as the host heard.
    struct WatchOutcome: Friendly {
        /// Whether the page reported the condition holding.
        var satisfied: Bool
        /// The first failure the page's check reported, if any.
        var failure: String?
    }

    /// Waits for `watch`'s truthy push, or for `deadline` — the only clock
    /// the host keeps. Nothing here re-checks the page.
    static func awaitPush(
        on pushes: AsyncStream<String>,
        for watch: String,
        by deadline: DispatchTime,
    ) async -> WatchOutcome {
        await withTaskGroup(of: WatchOutcome?.self) { group in
            group.addTask {
                var failure: String?
                for await text in pushes {
                    guard let probe = try? JSONDecoder().decode(WaitEngine.Probe.self, from: Data(text.utf8)),
                          probe.watch == watch
                    else { continue }
                    if probe.truthy { return WatchOutcome(satisfied: true, failure: failure) }
                    failure = failure ?? probe.failure
                }
                return WatchOutcome(satisfied: false, failure: failure)
            }
            let remaining: UInt64 = WaitEngine.nanoseconds(.infinity, notPast: deadline)
            group.addTask {
                try? await Task.sleep(nanoseconds: remaining)
                return nil
            }
            // The deadline reports nil; the stream, once cancelled, reports
            // the failure it heard — so collect both before answering.
            var outcome = WatchOutcome(satisfied: false, failure: nil)
            while let next = await group.next() {
                guard let next else {
                    group.cancelAll()
                    continue
                }
                outcome = next
                group.cancelAll()
            }
            return outcome
        }
    }
}
