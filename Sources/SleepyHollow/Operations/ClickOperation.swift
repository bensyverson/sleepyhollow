/// `sleepy click`: press what a selector matches, or what renders at a
/// point, with the pointer/mouse/click sequence a page listens for.
///
/// Honest about mechanism — these are synthesized DOM events, not OS-level
/// hit-testing (see `ActionScript`). A disabled control is refused rather
/// than pretended at, and the outcome reports whether the click set the page
/// navigating.
///
/// **A point is hit-tested for real.** ``ActionTarget/point(_:)`` resolves
/// through `document.elementFromPoint` and then descends every open
/// `shadowRoot` at the same coordinates, so the button a component renders is
/// what gets clicked — the one thing a selector cannot reach, because CSS
/// does not cross a shadow boundary and an event dispatched at the host never
/// travels down into it.
public struct ClickOperation: ExecutablePageOperation {
    /// This operation's typed result.
    public typealias Output = ActionOutcome

    /// The wire identifier.
    public static let kind: String = "click"

    /// What gets clicked: a selector's first match, or whatever renders at a
    /// point in document CSS px.
    public var target: ActionTarget

    /// Creates the operation.
    public init(target: ActionTarget) {
        self.target = target
    }

    /// Creates a click on the first element a CSS selector matches.
    public init(selector: String) {
        self.init(target: .selector(selector))
    }

    /// Creates a click on whatever renders at a point in document CSS px.
    ///
    /// The point is scrolled into view before the hit test, so a coordinate
    /// read off a full-page capture works without the caller scrolling first.
    public init(point: DocumentPoint) {
        self.init(target: .point(point))
    }

    /// Clicks the target.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/negative`` when
    ///   nothing matches, the control is disabled, or nothing but the page
    ///   background is at the point, and ``SleepyError/Kind/usage`` when the
    ///   selector cannot be parsed.
    @MainActor
    public func execute(on host: PageHost) async throws -> ActionOutcome {
        try await ActionScript.outcome(
            for: .click,
            target: target,
            body: Self.body(for: target),
            on: host,
        )
    }

    private static func body(for target: ActionTarget) -> String {
        switch target {
        case .selector: ActionScript.clickBody
        case .point: ActionScript.pointClickBody
        }
    }
}
