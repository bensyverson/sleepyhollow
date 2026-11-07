import Foundation

/// The load pipeline's action-step phase: the ordered one-shot
/// `--click`/`--fill`/`--submit`/`--focus`/`--hover`/`--type`/`--press`
/// steps, executed after the load event and before ``LoadOptions/wait``
/// gates the verb's read.
///
/// This is what makes `sleepy dom <url> --fill '#title=Hello' --click '#save'`
/// read the page the click produced. Steps run in flag order, each through
/// the same operation the session verbs use, and they share the load's single
/// budget — whatever navigating spent, the steps do not get again.
///
/// **A step auto-waits for its selector** (the wait-vs-steps ruling, vision
/// doc corrected 2026-08-20): a selector that matches nothing yet, or matches
/// an element not currently actionable, is retried until the deadline, so a
/// late-rendering form needs no flag to be acted on. A step that never
/// becomes actionable is a timeout, not a clean negative — it waited,
/// honestly, and ran out of budget.
///
/// **A step that navigates is waited for.** A click on a submit button or a
/// link starts a navigation the verb's read would otherwise race; the step
/// says whether that happened (``ActionOutcome/startedNavigation``), and this
/// phase then waits — on the navigation delegate's own signals, never on a
/// window of wall-clock time — for the navigation to commit or be dropped,
/// and a committed document to be complete, before the next step or the
/// read.
extension PageHost {
    /// How often a not-yet-actionable step is retried.
    private static var actionRetryInterval: TimeInterval {
        0.1
    }

    /// How often the navigation is re-checked. Cheap: it is a property read
    /// plus, at most, one small page-side probe.
    private static var navigationPollInterval: TimeInterval {
        0.02
    }

    /// Where the host's navigation-delegate counts stand: read before a step,
    /// compared after it.
    struct NavigationProgress: Friendly {
        /// Main-frame navigations WebKit has asked the host to decide.
        var requests: Int
        /// Main-frame documents committed.
        var commits: Int
        /// Main-frame navigations that ended without committing.
        var abandoned: Int

        /// Whether a navigation has committed or been dropped since `earlier`.
        func hasEnded(since earlier: NavigationProgress) -> Bool {
            commits > earlier.commits || abandoned > earlier.abandoned
        }
    }

    /// The host's navigation counts now, from the navigation delegate.
    var navigationProgress: NavigationProgress {
        NavigationProgress(
            requests: delegate.navigationRequests,
            commits: delegate.navigations.count,
            abandoned: delegate.abandonedNavigations,
        )
    }

    /// Executes ``LoadOptions/steps`` in flag order, sharing the load's
    /// budget: `deadline` is the same ceiling navigation drew on. Each step
    /// auto-waits for its selector to become actionable.
    ///
    /// - Throws: ``SleepyError/Kind/timeout`` when the budget runs out —
    ///   before a step, while it waited to become actionable, or while its
    ///   navigation settled — or ``SleepyError/Kind/usage`` at once for a
    ///   step that can never act (an unparseable selector, the wrong kind of
    ///   element).
    func runActionSteps(by deadline: DispatchTime) async throws {
        guard !options.steps.isEmpty else { return }
        for (index, step) in options.steps.enumerated() {
            guard DispatchTime.now() < deadline else {
                throw stepTimeout(at: index, step: step, detail: "before it could run")
            }
            // Read before the step, so a navigation that commits before the
            // step even returns is still counted as the step's.
            let before: NavigationProgress = navigationProgress
            let outcome: ActionOutcome = try await performWaiting(step, at: index, by: deadline)
            if outcome.startedNavigation, Self.mayNavigate(step) {
                try await settleNavigation(after: step, at: index, since: before, by: deadline)
            }
        }
    }

    /// Runs one step, retrying while the page answers "not yet" — no match,
    /// disabled, read-only — so a late element is acted on when it arrives.
    /// A `usage`-kind refusal (wrong element, bad selector) is final: waiting
    /// cannot turn a `<div>` into a form field.
    private func performWaiting(
        _ step: ActionStep,
        at index: Int,
        by deadline: DispatchTime,
    ) async throws -> ActionOutcome {
        while true {
            do {
                return try await perform(step)
            } catch let error as SleepyError where error.kind == .negative {
                guard DispatchTime.now() < deadline else {
                    throw stepTimeout(at: index, step: step, detail: "never became actionable: \(error.message)")
                }
                try? await Task.sleep(nanoseconds: UInt64(Self.actionRetryInterval * 1_000_000_000))
            }
        }
    }

    /// Whether this kind of step can start a navigation at all.
    private static func mayNavigate(_ step: ActionStep) -> Bool {
        switch step {
        case .click, .submit, .type, .press: true
        case .fill, .focus, .hover: false
        }
    }

    /// Runs one step through the operation the session verbs use, so a
    /// one-shot flag and a session verb can never drift apart.
    private func perform(_ step: ActionStep) async throws -> ActionOutcome {
        switch step {
        case let .click(selector):
            try await execute(ClickOperation(selector: selector))
        case let .fill(selector, value):
            try await execute(FillOperation(selector: selector, value: value))
        case let .submit(selector):
            try await execute(SubmitOperation(selector: selector))
        case let .focus(selector):
            try await execute(FocusOperation(selector: selector))
        case let .hover(selector):
            try await execute(HoverOperation(selector: selector))
        case let .type(text):
            try await execute(PressOperation(text: text))
        case let .press(chord):
            try await execute(PressOperation(keys: [chord]))
        }
    }

    // MARK: - Navigation started by a step

    /// Waits for a step's navigation to land, so the next step and the verb's
    /// read see the new document rather than a torn-down one.
    ///
    /// **Signals, not a window.** First, whether the host was asked to decide
    /// a navigation at all since `before` — ordered, by
    /// ``navigationStarted(sinceRequests:)``; a step that reported one the
    /// host never heard of (a link into another window) has nothing to wait
    /// for. Then until that navigation commits or WebKit drops it — a `204`,
    /// a cancelled response, an unsupported scheme all end in a provisional
    /// failure — and, once committed, until it finishes loading and parsing.
    /// Between the decision and the start, `isLoading` is still false and
    /// the old document still answers: measured 2026-11-06, a cross-site
    /// link leaves that gap open 60–80 ms while WebKit swaps web content
    /// processes on an idle Mac, longer on a loaded one. The half-second
    /// grace this replaced bet on that gap and read the old page when it
    /// lost (issue `7mWLWK`).
    private func settleNavigation(
        after step: ActionStep,
        at index: Int,
        since before: NavigationProgress,
        by deadline: DispatchTime,
    ) async throws {
        guard await navigationStarted(sinceRequests: before.requests) else { return }
        while navigationProgress.hasEnded(since: before) == false {
            guard DispatchTime.now() < deadline else {
                throw stepTimeout(at: index, step: step, detail: "started a navigation that never committed")
            }
            await pause()
        }
        while webView.isLoading {
            guard DispatchTime.now() < deadline else {
                throw stepTimeout(at: index, step: step, detail: "started a navigation that never finished")
            }
            await pause()
        }
        while await documentIsComplete() == false {
            guard DispatchTime.now() < deadline else {
                throw stepTimeout(at: index, step: step, detail: "navigated to a page that never finished parsing")
            }
            await pause()
        }
    }

    /// How many main-frame navigations WebKit has asked this host to decide
    /// — counted at the policy decision, the earliest point the host hears
    /// of one, before anything loads. Read it before an action and pass it to
    /// ``navigationStarted(sinceRequests:)`` after.
    var navigationRequestCount: Int {
        delegate.navigationRequests
    }

    /// Whether the page asked to navigate its main frame after the host read
    /// `count` from ``navigationRequestCount``, judged from the host's side.
    ///
    /// The act primitives' own answer comes from a page-side `submit`
    /// listener, and with the page's scripts off WebKit invokes no event
    /// listener at all — the isolated world's included (measured 2026-11-06:
    /// a form submitted by `requestSubmit()`, `submit()` and a button click
    /// all navigated, and a capture-phase listener heard none of them). So
    /// ``ActionScript`` asks this instead when ``LoadOptions/pageScripts`` is
    /// ``LoadOptions/PageScripts/disabled``, and ``PressOperation`` always
    /// does, since a key's default action runs in no listener either.
    ///
    /// **Ordered, not polled.** The web process asks the navigation delegate
    /// to decide a main-frame navigation before it loads anything, on the
    /// same connection the action's own answer comes back on. Measured
    /// 2026-11-06, a button click that submits, Enter in a form field and a
    /// keydown handler setting `location.href` all had their decision counted
    /// before the action returned — no wait at all. For a navigation WebKit
    /// defers to a zero-delay timer instead, the host then sets one more
    /// zero-delay timer in the isolated world and waits for it, so whatever
    /// the page scheduled first has asked by the time it answers (unmeasured:
    /// no fixture yet reaches that path). A loaded machine makes this slower,
    /// never wrong; the poll it replaced gave the start half a second and
    /// reported a real submission as none under load (issue `OI4gWa`).
    func navigationStarted(sinceRequests count: Int) async -> Bool {
        if navigationRequestCount > count { return true }
        // A page torn down mid-barrier is a page being replaced; the count
        // below says so either way, so the barrier's own failure is moot.
        _ = try? await evaluate(Self.orderingBarrier, in: .isolated)
        return navigationRequestCount > count
    }

    /// One zero-delay timer, awaited: everything the page scheduled before
    /// it has run by the time it answers.
    private static var orderingBarrier: String {
        "await new Promise((resolve) => setTimeout(resolve, 0)); return true;"
    }

    private func documentIsComplete() async -> Bool {
        // The isolated world: `readyState` is the shared document's, and the
        // page world is closed to the host when the page's scripts are off.
        let state: String? = try? await evaluate("return document.readyState;", in: .isolated)
        return state == "\"complete\""
    }

    private func pause() async {
        try? await Task.sleep(nanoseconds: UInt64(Self.navigationPollInterval * 1_000_000_000))
    }

    // MARK: - Failures

    private func stepTimeout(at index: Int, step: ActionStep, detail: String) -> SleepyError {
        SleepyError(
            kind: .timeout,
            message: "Step \(index + 1) of \(options.steps.count) (\(Self.describe(step))) \(detail) "
                + "within \(budget)s.",
            nextMove: "Raise --budget, or split the flow across a session with `sleepy open`.",
        )
    }

    /// The step as the agent spelled it on the command line.
    private static func describe(_ step: ActionStep) -> String {
        switch step {
        case let .click(selector):
            "--click '\(selector)'"
        case let .fill(selector, value):
            "--fill '\(selector)=\(value)'"
        case let .submit(selector):
            "--submit '\(selector)'"
        case let .focus(selector):
            "--focus '\(selector)'"
        case let .hover(selector):
            "--hover '\(selector)'"
        case let .type(text):
            "--type '\(text)'"
        case let .press(chord):
            "--press '\(chord.description)'"
        }
    }
}
