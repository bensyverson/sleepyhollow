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
    }

    /// Runs one action body and shapes the page's report into an outcome.
    ///
    /// - Parameter action: which primitive is running, for the messages.
    /// - Parameter selector: the element chooser, always passed to the body.
    /// - Parameter body: the action's JavaScript, appended to ``helpers``.
    /// - Parameter arguments: extra named values the body needs.
    /// - Throws: ``SleepyError`` — ``SleepyError/Kind/negative`` when the page
    ///   cleanly cannot act (nothing matched, the control is disabled),
    ///   ``SleepyError/Kind/usage`` when the request was wrong (an unparseable
    ///   selector, a fill target that holds no value).
    @MainActor
    static func outcome(
        for action: ActionOutcome.Action,
        selector: String,
        body: String,
        arguments: [String: Any] = [:],
        on host: PageHost,
    ) async throws -> ActionOutcome {
        var named: [String: Any] = arguments
        named["selector"] = selector
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
            throw failure(code, action: action, selector: selector, report: report, arguments: named)
        }
        return ActionOutcome(
            action: action,
            selector: selector,
            tagName: report.tagName ?? "",
            value: report.value,
            startedNavigation: report.navigating ?? false,
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

    /// Maps a page-side refusal code onto the taxonomy in ``SleepyError``.
    private static func failure(
        _ code: String,
        action: ActionOutcome.Action,
        selector: String,
        report: Report,
        arguments: [String: Any],
    ) -> SleepyError {
        let tag: String = report.tagName.map { "<\($0)>" } ?? "element"
        switch code {
        case "no-match":
            return SleepyError(
                kind: .negative,
                message: "Nothing matches '\(selector)', so there was no \(action.rawValue) to make.",
                nextMove: "Check the page first: `sleepy query <page> --selector '\(selector)'`.",
            )
        case "invalid-selector":
            return SleepyError(
                kind: .usage,
                message: "'\(selector)' is not a CSS selector this page can match: \(report.detail ?? "")",
                nextMove: "Check the selector syntax.",
            )
        case "disabled":
            return SleepyError(
                kind: .negative,
                message: "'\(selector)' is a disabled \(tag); a real \(action.rawValue) can't reach it.",
                nextMove: "Wait for it to enable with --wait-for 'js:!document.querySelector(\"\(selector)\").disabled', "
                    + "or act on whatever enables it first.",
            )
        case "read-only":
            return SleepyError(
                kind: .negative,
                message: "'\(selector)' is read-only, so its value can't be filled.",
                nextMove: "Fill the control that unlocks it, or read the value you have with `sleepy query`.",
            )
        case "not-fillable":
            return SleepyError(
                kind: .usage,
                message: "'\(selector)' is a \(tag), which holds no value to fill.",
                nextMove: "--fill needs an <input>, <textarea>, <select>, or contenteditable element.",
            )
        case "no-option":
            let wanted: String = (arguments["value"] as? String) ?? ""
            return SleepyError(
                kind: .negative,
                message: "The <select> at '\(selector)' has no option matching '\(wanted)'.",
                nextMove: "Pass an option's value or its visible label; `sleepy query --selector '\(selector) option'` "
                    + "lists them.",
            )
        case "no-form":
            return SleepyError(
                kind: .usage,
                message: "'\(selector)' is a \(tag): not a form, and not inside one.",
                nextMove: "Give the form's own selector, or a control inside it.",
            )
        case "invalid-form":
            let field: String = report.detail.map { "'\($0)' " } ?? ""
            return SleepyError(
                kind: .negative,
                message: "The form for '\(selector)' is invalid — \(field)fails its constraints, "
                    + "so the browser refused to submit it.",
                nextMove: "Fill the field first with --fill, or submit a form that validates.",
            )
        default:
            return SleepyError(
                kind: .environment,
                message: "The page refused the \(action.rawValue) at '\(selector)': \(code).",
                nextMove: "Report this: the act family emitted a code the CLI does not know.",
            )
        }
    }
}
