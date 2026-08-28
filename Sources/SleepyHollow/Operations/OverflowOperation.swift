import Foundation

/// `sleepy overflow`: what spills the viewport horizontally, and what
/// legitimately scrolls instead.
///
/// The computation is `window.sleepy.overflow()` from ``SleepyHelpers``. The
/// shortcut every agent writes first — `document.scrollWidth > clientWidth` —
/// silently passes on any page carrying `overflow-x: hidden`, and the loop
/// that avoids that flags every wide table inside its own scroller. This does
/// neither: it measures element geometry against the viewport, refuses to
/// descend into an `overflow-x: auto | scroll` ancestor, and reports those
/// ancestors separately.
///
/// The viewport is the load's own — pass `--size` to ask the question at a
/// different breakpoint.
public struct OverflowOperation: ExecutablePageOperation {
    /// This operation's typed result.
    public typealias Output = OverflowReport

    /// The wire identifier.
    public static let kind: String = "overflow"

    /// Creates the operation. It has no parameters: the viewport is the
    /// load's.
    public init() {}

    /// Measures the page against its viewport.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment``
    ///   when the page cannot run the computation.
    @MainActor
    public func execute(on host: PageHost) async throws -> OverflowReport {
        try await SleepyHelpers.call("overflow", options: [:], as: OverflowReport.self, on: host)
    }
}
