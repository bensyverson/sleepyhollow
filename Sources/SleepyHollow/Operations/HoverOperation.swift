import CoreGraphics

/// The `--hover` step: put a real pointer over an element, so CSS `:hover`
/// matches and the page's `mouseover`/`mouseenter`/`mousemove` handlers run
/// with `isTrusted` true.
///
/// `:hover` follows the pointer's position, not a dispatched `mouseover`, so
/// no page-side event could produce it; the move comes from the host's
/// window through ``TrustedInput``. The element is scrolled into view and
/// the pointer goes to its center — refused when another element covers
/// that point, since the pointer would be over that one instead — and
/// afterwards the element must match `:hover`, or the hover is reported as
/// not having landed rather than as done.
///
/// The pointer stays where it was put, so a shot taken next shows the hover
/// state. Requires a live host: a ``PageHost/Hosting/windowless`` one has no
/// window and is refused.
public struct HoverOperation: ExecutablePageOperation {
    /// This operation's typed result.
    public typealias Output = ActionOutcome

    /// The wire identifier.
    public static let kind: String = "hover"

    /// The CSS selector whose first match the pointer moves over.
    public var selector: String

    /// Creates the operation.
    public init(selector: String) {
        self.selector = selector
    }

    /// Moves the pointer to the center of the first element matching
    /// ``selector``.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/negative`` when
    ///   nothing matches, the element has no box, something covers it, or it
    ///   does not match `:hover` once the pointer is there;
    ///   ``SleepyError/Kind/usage`` for an unparseable selector or a
    ///   windowless host.
    @MainActor
    public func execute(on host: PageHost) async throws -> ActionOutcome {
        let input = try TrustedInput(for: host, action: "hover")
        let arguments: [String: Any] = ["selector": selector, "hoverKey": ActionScript.hoverTargetKey]
        let located: ActionScript.Report = try await ActionScript.report(
            for: .hover,
            target: .selector(selector),
            body: ActionScript.hoverLocateBody,
            arguments: arguments,
            on: host,
        )
        try await input.movePointer(toViewport: CGPoint(x: located.x ?? 0, y: located.y ?? 0))
        let checked: ActionScript.Report = try await ActionScript.report(
            for: .hover,
            target: .selector(selector),
            body: ActionScript.hoverCheckBody,
            arguments: arguments,
            on: host,
        )
        return ActionOutcome(
            action: .hover,
            selector: selector,
            tagName: checked.tagName ?? located.tagName ?? "",
            startedNavigation: false,
        )
    }
}
