import Foundation
import WebKit

/// `sleepy archive` — a `.webarchive` of the currently loaded page and its
/// subresources (`WKWebView.createWebArchiveData`).
///
/// *Need:* evidence. A bug report that carries the page as it was — assets
/// included — outlives the server state that produced it.
public struct ArchiveOperation: ExecutablePageOperation {
    /// The webarchive bytes a capture produced.
    public struct Output: Friendly {
        /// The encoded `.webarchive` (a binary property list).
        public let archive: Data

        /// Wraps encoded webarchive bytes.
        public init(archive: Data) {
            self.archive = archive
        }
    }

    /// The wire identifier.
    public static let kind: String = "archive"

    /// Creates an archive operation.
    public init() {}

    /// Archives the currently loaded page, inside the host's
    /// ``PageHost/callBudget``.
    ///
    /// `createWebArchiveData` has no async overload in the SDK — only a
    /// `Result<Data, any Error>` completion handler — and no timeout of its
    /// own: it waits on the content process, so a page parked on synchronous
    /// work, or a process that has stalled, would leave it unanswered for as
    /// long as that lasts. So it goes through the host's deadline — and under
    /// a foreground hold, because it takes no foreground activity of its own
    /// and would otherwise reach an idle page throttled to the background
    /// band.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/timeout`` when the
    ///   page does not answer within the call budget (the host is then
    ///   ``PageHost/abandonedCall``), and WebKit's own error when the archive
    ///   fails.
    @MainActor
    public func execute(on host: PageHost) async throws -> Output {
        let data: Data = try await host.holdingForeground {
            try await host.answer("the web archive", within: host.callBudget) { answered in
                host.webView.createWebArchiveData { result in answered(result) }
            }
        }
        return Output(archive: data)
    }
}
