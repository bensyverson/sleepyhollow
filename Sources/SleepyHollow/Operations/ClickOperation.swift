/// `sleepy click`: press the first element a selector matches, with the
/// pointer/mouse/click sequence a page listens for.
///
/// Honest about mechanism — these are synthesized DOM events, not OS-level
/// hit-testing (see `ActionScript`). A disabled control is refused rather
/// than pretended at, and the outcome reports whether the click set the page
/// navigating.
public struct ClickOperation: ExecutablePageOperation {
    /// This operation's typed result.
    public typealias Output = ActionOutcome

    /// The wire identifier.
    public static let kind: String = "click"

    /// The CSS selector whose first match is clicked.
    public var selector: String

    /// Creates the operation.
    public init(selector: String) {
        self.selector = selector
    }

    /// Clicks the first element matching ``selector``.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/negative`` when
    ///   nothing matches or the control is disabled, and
    ///   ``SleepyError/Kind/usage`` when the selector cannot be parsed.
    @MainActor
    public func execute(on host: PageHost) async throws -> ActionOutcome {
        try await ActionScript.outcome(
            for: .click,
            selector: selector,
            body: ActionScript.clickBody,
            on: host,
        )
    }
}
