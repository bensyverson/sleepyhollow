/// The condition that ends a load's settle phase.
///
/// Waiting is a primitive of the tool, not a polling loop in the agent: the
/// agent states the condition, the host owns the clock, and exhausting the
/// budget is an exit code with the page's last state attached — never a hang.
///
/// Every condition but ``idle`` is settled by a *push* from the page — a
/// mutation observer, a page-side re-evaluation, or the page's own
/// `postMessage` — so a saturated host actor delays the answer by one hop
/// rather than losing it (see
/// `project/2026-08-29-woodcase-harness-feedback.md`, finding 1).
public enum WaitCondition: Friendly {
    /// A CSS selector that must match at least one element.
    case selector(String)
    /// A JavaScript expression that must evaluate truthy.
    case predicate(String)
    /// A script-message handler the page must post to at least once:
    /// `window.webkit.messageHandlers.<name>.postMessage(anything)`, in the
    /// page's own world. For a page that already knows when it is ready.
    case message(String)
    /// Network and script activity has gone quiet.
    case idle
    /// The navigation's load event alone.
    case load
}

public extension WaitCondition {
    /// Whether `name` can be a script-message handler ``message(_:)`` waits on.
    ///
    /// A handler is reached through a property access
    /// (`window.webkit.messageHandlers.<name>`), so the name has to be a plain
    /// JavaScript identifier: ASCII letters, digits, `_` or `$`, not starting
    /// with a digit. Anything else names a handler no page could post to, so
    /// it is refused where it is written rather than waited on for a budget.
    static func isValidMessageName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        for (index, scalar) in name.unicodeScalars.enumerated() {
            let isLetter: Bool = (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z")
            let isDigit: Bool = scalar >= "0" && scalar <= "9"
            let isSign: Bool = scalar == "_" || scalar == "$"
            guard isLetter || isSign || (isDigit && index > 0) else { return false }
        }
        return true
    }
}
