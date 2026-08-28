import Foundation

/// The synthesized-event mechanism the act primitives share: run one action
/// page-side, decode what the page reports, and turn a refusal into a
/// ``SleepyError`` that teaches the next move.
///
/// Honest about mechanism (vision doc §3): these are real DOM events
/// dispatched at the element — `pointerdown`/`mousedown`/`pointerup`/
/// `mouseup`/`click`, `input`/`change`, a cancellable `submit` — not OS-level
/// hit-testing. `isTrusted` is `false` and the page can see that; a page that
/// refuses untrusted events refuses these, which is the truth an agent needs
/// rather than a pretence.
///
/// Actions run in the tool's isolated ``InjectedScript/World``: the DOM is
/// shared across worlds, so the page's listeners receive every event, while
/// the page cannot have replaced the value setters this uses to write a field.
enum ActionScript {
    /// What the page reports back from one action.
    ///
    /// Either ``error`` names why nothing happened, or the remaining fields
    /// describe what did.
    struct Report: Friendly {
        /// The refusal code, when the action could not be performed.
        var error: String?
        /// Extra detail for the refusal — the invalid field, the parse error.
        var detail: String?
        /// The acted-on element's lowercased tag name.
        var tagName: String?
        /// The value the action settled on.
        var value: String?
        /// Whether the page started navigating as a result.
        var navigating: Bool?
        /// What a coordinate click's hit test found.
        var hit: HitElement?
    }

    /// Runs one action body and shapes the page's report into an outcome.
    ///
    /// - Parameter action: which primitive is running, for the messages.
    /// - Parameter target: what to act on; put in the body's scope as
    ///   `selector` or as `point`, whichever the target is.
    /// - Parameter body: the action's JavaScript, appended to ``helpers``.
    /// - Parameter arguments: extra named values the body needs.
    /// - Throws: ``SleepyError`` — ``SleepyError/Kind/negative`` when the page
    ///   cleanly cannot act (nothing matched, the control is disabled),
    ///   ``SleepyError/Kind/usage`` when the request was wrong (an unparseable
    ///   selector, a fill target that holds no value).
    @MainActor
    static func outcome(
        for action: ActionOutcome.Action,
        target: ActionTarget,
        body: String,
        arguments: [String: Any] = [:],
        on host: PageHost,
    ) async throws -> ActionOutcome {
        var named: [String: Any] = arguments
        switch target {
        case let .selector(selector):
            named["selector"] = selector
        case let .point(point):
            named["point"] = ["x": point.x, "y": point.y]
        }
        let text: String
        do {
            text = try await host.evaluate(helpers + "\n" + body, arguments: named, in: .isolated)
        } catch let error as SleepyError {
            throw error
        } catch {
            throw SleepyError(
                kind: .environment,
                message: "The page could not run the \(action.rawValue): \((error as NSError).localizedDescription)",
                nextMove: "Retry against a settled page — a frame that navigates mid-action cannot answer.",
            )
        }
        let report: Report = try decode(text, action: action)
        if let code = report.error {
            throw failure(code, action: action, target: target, report: report, arguments: named)
        }
        return ActionOutcome(
            action: action,
            selector: target.selector,
            tagName: report.tagName ?? "",
            value: report.value,
            startedNavigation: report.navigating ?? false,
            hit: report.hit,
        )
    }

    private static func decode(_ text: String, action: ActionOutcome.Action) throws -> Report {
        guard let report = try? JSONDecoder().decode(Report.self, from: Data(text.utf8)) else {
            throw SleepyError(
                kind: .environment,
                message: "The \(action.rawValue) result did not transport as JSON: \(text)",
                nextMove: "Retry; this indicates a WebKit transport fault, not a page fault.",
            )
        }
        return report
    }
}
