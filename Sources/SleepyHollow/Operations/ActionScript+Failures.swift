import Foundation

/// The act family's refusals: one page-side code in, one ``SleepyError`` out.
///
/// Kept apart from the seam that runs the script because this is a
/// vocabulary, not a mechanism — every code the bodies can return, mapped
/// onto the exit-status taxonomy and given a next move that names a real
/// command. A code with no case here is reported as a defect in the tool
/// rather than blamed on the page.
extension ActionScript {
    /// Maps a page-side refusal code onto the taxonomy in ``SleepyError``.
    static func failure(
        _ code: String,
        action: ActionOutcome.Action,
        target: ActionTarget,
        report: Report,
        arguments: [String: Any],
    ) -> SleepyError {
        let tag: String = report.tagName.map { "<\($0)>" } ?? "element"
        let named: String = target.description
        let opening: String = target.sentenceDescription
        switch code {
        case "no-hit":
            return SleepyError(
                kind: .negative,
                message: "Nothing but the page background is at \(named), so there was no click to make.",
                nextMove: "Measure the target first — a `sleepy shot --full-page` shows the page in the same "
                    + "document CSS px --at takes.",
            )
        case "off-page":
            return SleepyError(
                kind: .negative,
                message: "\(opening) is past the end of the document, so nothing could be scrolled into view there.",
                nextMove: "--at takes document CSS px from the page's top-left corner; a `sleepy shot --full-page` "
                    + "shows how far the page actually goes.",
            )
        case "no-match":
            return SleepyError(
                kind: .negative,
                message: "Nothing matches \(named), so there was no \(action.rawValue) to make.",
                nextMove: "Check the page first: `sleepy query <page> --selector \(named)`.",
            )
        case "invalid-selector":
            return SleepyError(
                kind: .usage,
                message: "\(opening) is not a CSS selector this page can match: \(report.detail ?? "")",
                nextMove: "Check the selector syntax.",
            )
        case "disabled":
            return SleepyError(
                kind: .negative,
                message: "\(opening) is a disabled \(tag); a real \(action.rawValue) can't reach it.",
                nextMove: enablementAdvice(for: target, action: action),
            )
        case "read-only":
            return SleepyError(
                kind: .negative,
                message: "\(opening) is read-only, so its value can't be filled.",
                nextMove: "Fill the control that unlocks it, or read the value you have with `sleepy query`.",
            )
        case "not-fillable":
            return SleepyError(
                kind: .usage,
                message: "\(opening) is a \(tag), which holds no value to fill.",
                nextMove: "--fill needs an <input>, <textarea>, <select>, or contenteditable element.",
            )
        case "no-option":
            let wanted: String = (arguments["value"] as? String) ?? ""
            return SleepyError(
                kind: .negative,
                message: "The <select> at \(named) has no option matching '\(wanted)'.",
                nextMove: "Pass an option's value or its visible label; `sleepy query --selector \(named) option` "
                    + "lists them.",
            )
        case "no-form":
            return SleepyError(
                kind: .usage,
                message: "\(opening) is a \(tag): not a form, and not inside one.",
                nextMove: "Give the form's own selector, or a control inside it.",
            )
        case "invalid-form":
            let field: String = report.detail.map { "'\($0)' " } ?? ""
            return SleepyError(
                kind: .negative,
                message: "The form for \(named) is invalid — \(field)fails its constraints, "
                    + "so the browser refused to submit it.",
                nextMove: "Fill the field first with --fill, or submit a form that validates.",
            )
        default:
            return SleepyError(
                kind: .environment,
                message: "The page refused the \(action.rawValue) at \(named): \(code).",
                nextMove: "Report this: the act family emitted a code the CLI does not know.",
            )
        }
    }

    /// How to wait for a disabled control to enable — a `js:` predicate when
    /// a selector named it, and the honest general advice when a point did,
    /// since a hit-tested element has no selector to write a predicate about.
    private static func enablementAdvice(for target: ActionTarget, action: ActionOutcome.Action) -> String {
        guard let selector = target.selector else {
            return "Act on whatever enables it first, then \(action.rawValue) the point again."
        }
        return "Wait for it to enable with --wait-for 'js:!document.querySelector(\"\(selector)\").disabled', "
            + "or act on whatever enables it first."
    }
}
