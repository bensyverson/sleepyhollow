/// The `--leave` step: take the pointer off the page, so nothing matches
/// `:hover`.
///
/// A click leaves the pointer where it clicked, and a hover where it was
/// put, as a user's mouse stays where it was last moved. That is right for a
/// caller driving the page — a hover-opened menu stays open for the next
/// click — and wrong for one capturing states, where a shot after a click
/// should not also show hover. This is the explicit, ordered step between
/// the two (Ben's ruling, 2026-11-06, `project/2026-11-06-trusted-click.md`):
/// `--click '#btn' --leave` captures the clicked state alone.
///
/// The move is real input from the host's window (``TrustedInput``), so the
/// element the pointer was over receives `pointerout`, `mouseout`,
/// `pointerleave` and `mouseleave` with `isTrusted` true — a menu that opens
/// on hover closes, as when a user's mouse leaves the window — and keyboard
/// focus is untouched. Requires a live host: a
/// ``PageHost/Hosting/windowless`` one has no window and is refused, never
/// answered with page-side events.
public struct LeaveOperation: ExecutablePageOperation {
    /// This operation's typed result.
    public typealias Output = ActionOutcome

    /// The wire identifier.
    public static let kind: String = "leave"

    /// Creates the operation.
    public init() {}

    /// Moves the pointer off the page and waits until the page has handled
    /// the move.
    ///
    /// - Returns: an outcome with no selector and an empty tag name — the
    ///   step names no element — that never starts a navigation.
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` for a
    ///   windowless host; ``SleepyError/Kind/environment`` when this WebKit
    ///   lacks the input SPI; ``SleepyError/Kind/timeout`` when the page does
    ///   not handle the move within the host's call budget.
    @MainActor
    public func execute(on host: PageHost) async throws -> ActionOutcome {
        let input = try TrustedInput(for: host, action: "pointer move off the page")
        try await input.parkPointer()
        return ActionOutcome(action: .leave, selector: nil, tagName: "", startedNavigation: false)
    }
}
