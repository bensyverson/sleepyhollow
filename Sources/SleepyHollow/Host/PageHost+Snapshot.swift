import AppKit
import Foundation
import WebKit

public extension PageHost {
    /// Rasterizes `configuration`'s rect of the page, inside a deadline.
    ///
    /// `WKWebView.takeSnapshot` waits for the content process to present a
    /// rendering update, and has no timeout of its own: a process that is
    /// stalled, or parked on synchronous work, leaves it unanswered for as
    /// long as that lasts. This is the same call with a deadline the host
    /// keeps. ``ShotOperation`` goes through it; so should an embedder that
    /// snapshots the ``webView`` itself.
    ///
    /// - Parameter configuration: what to snapshot; see
    ///   `WKSnapshotConfiguration`.
    /// - Parameter budget: seconds to wait for the image, or `nil` for the
    ///   host's ``callBudget``.
    /// - Returns: the snapshot, at the host's screen backing scale.
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/timeout`` when the
    ///   budget runs out first (the host is then ``abandonedCall``),
    ///   `CancellationError` when the caller is cancelled first, WebKit's own
    ///   error when the snapshot fails, and ``SleepyError/Kind/environment``
    ///   when WebKit answers with neither an image nor an error.
    func snapshot(_ configuration: WKSnapshotConfiguration, budget: TimeInterval? = nil) async throws -> NSImage {
        try await answer("snapshot", within: budget ?? callBudget) { answered in
            webView.takeSnapshot(with: configuration) { image, error in
                if let image {
                    answered(.success(image))
                } else {
                    answered(.failure(error ?? SleepyError(
                        kind: .environment,
                        message: "WebKit answered the snapshot with neither an image nor an error.",
                        nextMove: "Retry; if this persists, it is a seam bug against WKWebView.takeSnapshot.",
                    )))
                }
            }
        }
    }
}
