import Foundation

/// The load pipeline's action-step phase: the ordered one-shot
/// `--click`/`--fill`/`--submit` steps, executed after settle and before the
/// verb's read.
///
/// This is what makes `sleepy dom <url> --fill '#title=Hello' --click '#save'`
/// read the page the click produced. Steps run in flag order, each through
/// the same operation the session verbs use, and they share the load's single
/// budget — whatever navigating and settling spent, the steps do not get
/// again.
///
/// **A step that navigates is waited for.** A click on a submit button or a
/// link starts a navigation the verb's read would otherwise race; the page
/// itself says whether that happened (``ActionOutcome/startedNavigation``),
/// and this phase then waits for the new document to be complete before the
/// next step or the read.
extension PageHost {
    /// How long a step that reported a navigation is given to *start* one
    /// before the phase concludes nothing is coming.
    private static var navigationStartGrace: TimeInterval {
        0.5
    }

    /// How often the navigation is re-checked. Cheap: it is a property read
    /// plus, at most, one small page-side probe.
    private static var navigationPollInterval: TimeInterval {
        0.02
    }

    /// The isolated-world global a document is marked with, so a navigation
    /// is detectable even when the URL does not change.
    private static var documentMarkKey: String {
        "__sleepyStepMark"
    }

    /// Executes ``LoadOptions/steps`` in flag order, sharing the load's
    /// budget: `deadline` is the same ceiling navigation and settle drew on.
    ///
    /// - Throws: whatever the step's operation throws — most often
    ///   ``SleepyError/Kind/negative`` for a selector that matched nothing —
    ///   or ``SleepyError/Kind/timeout`` when the budget runs out before the
    ///   steps are done.
    func runActionSteps(by deadline: DispatchTime) async throws {
        guard !options.steps.isEmpty else { return }
        for (index, step) in options.steps.enumerated() {
            guard DispatchTime.now() < deadline else {
                throw stepTimeout(at: index, step: step, detail: "before it could run")
            }
            // Only a click or a submit can navigate, and the mark has to be
            // written before the step it detects — so a fill pays nothing.
            let mark: String? = Self.mayNavigate(step) ? await markDocument() : nil
            let outcome: ActionOutcome = try await perform(step)
            if outcome.startedNavigation {
                try await settleNavigation(after: step, at: index, mark: mark, by: deadline)
            }
        }
    }

    /// Whether this kind of step can start a navigation at all.
    private static func mayNavigate(_ step: ActionStep) -> Bool {
        switch step {
        case .click, .submit: true
        case .fill: false
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
        }
    }

    // MARK: - Navigation started by a step

    /// Waits for a step's navigation to land, so the next step and the verb's
    /// read see the new document rather than a torn-down one.
    private func settleNavigation(
        after step: ActionStep,
        at index: Int,
        mark: String?,
        by deadline: DispatchTime,
    ) async throws {
        let graceEnd = DispatchTime.now() + Self.navigationStartGrace
        while DispatchTime.now() < min(graceEnd, deadline) {
            if webView.isLoading { break }
            if let mark, await documentIsStillMarked(mark) == false { break }
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

    /// Tags the current document in the isolated world; the tag's absence
    /// afterwards is proof a *different* document is loaded, which is how a
    /// same-URL navigation is spotted.
    private func markDocument() async -> String? {
        let mark: String = UUID().uuidString
        let written: String? = try? await evaluate(
            "window[key] = mark; return true;",
            arguments: ["key": Self.documentMarkKey, "mark": mark],
        )
        return written == "true" ? mark : nil
    }

    /// Whether the marked document is still the one loaded. A page that
    /// cannot answer is a page that is being replaced.
    private func documentIsStillMarked(_ mark: String) async -> Bool {
        let answer: String? = try? await evaluate(
            "return window[key] === mark;",
            arguments: ["key": Self.documentMarkKey, "mark": mark],
        )
        return answer == "true"
    }

    private func documentIsComplete() async -> Bool {
        let state: String? = try? await evaluate("return document.readyState;", in: .page)
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
        }
    }
}
