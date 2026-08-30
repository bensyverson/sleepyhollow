import Foundation

/// Moves a live page's viewport — the operation behind `sleepy resize`.
///
/// It is the one load option a session can honestly change after the fact.
/// Every other `--size`-shaped flag is refused on a `--session` invocation
/// because the page was already laid out when it arrived; a viewport is
/// different, because ``PageHost/resize(to:)`` relayouts the page that is
/// already there and the media queries re-evaluate with it. So checking a
/// second breakpoint costs a resize rather than a fresh session and a second
/// navigation — and whatever the page had been clicked or filled into
/// survives.
///
/// ```swift
/// let now: ViewportSize = try await client.run(ResizeOperation(size: ViewportSize(width: 390, height: 844)))
/// ```
public struct ResizeOperation: ExecutablePageOperation {
    /// The viewport the page now has.
    public typealias Output = ViewportSize

    /// The wire identifier.
    public static let kind: String = "resize"

    /// The viewport to move to, in points.
    public var size: ViewportSize

    /// Creates the operation.
    ///
    /// - Parameter size: the new viewport, in points.
    public init(size: ViewportSize) {
        self.size = size
    }

    /// Resizes the host and reports the viewport it now has.
    ///
    /// The report is read back from ``PageHost/viewport`` rather than echoed
    /// from ``size``, so the answer describes the page rather than the request.
    @MainActor
    public func execute(on host: PageHost) async throws -> ViewportSize {
        host.resize(to: size)
        return host.viewport
    }
}
