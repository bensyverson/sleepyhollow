/// The `--focus` step: focus an element as keyboard navigation would, so the
/// page shows the focus style a keyboard user sees.
///
/// The element's own `focus({ focusVisible: true })`, run in the tool's
/// isolated world. The `focus` event that results is trusted — focus moved
/// for real — and `focusVisible: true` makes `:focus-visible` match whatever
/// the pointer did before: a plain `focus()` after a click does not match it
/// in WebKit (measured 2026-11-06), because WebKit then assumes the pointer
/// is still driving. A pointer focus is already one `--click` away, so this
/// step gives the state that otherwise needs a Tab key and a known tab
/// order. It is also how `press --selector` puts focus where its keys go, as
/// Playwright's `locator.press` does.
///
/// An element that does not end up focused — a plain `<div>`, an inert
/// subtree — is refused, never reported focused.
public struct FocusOperation: ExecutablePageOperation {
    /// This operation's typed result.
    public typealias Output = ActionOutcome

    /// The wire identifier.
    public static let kind: String = "focus"

    /// The CSS selector whose first match is focused.
    public var selector: String

    /// Creates the operation.
    public init(selector: String) {
        self.selector = selector
    }

    /// Focuses the first element matching ``selector``.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/negative`` when
    ///   nothing matches or the control is disabled, and
    ///   ``SleepyError/Kind/usage`` when the selector cannot be parsed or the
    ///   element does not take focus.
    @MainActor
    public func execute(on host: PageHost) async throws -> ActionOutcome {
        try await ActionScript.outcome(
            for: .focus,
            target: .selector(selector),
            body: ActionScript.focusBody,
            on: host,
        )
    }
}
