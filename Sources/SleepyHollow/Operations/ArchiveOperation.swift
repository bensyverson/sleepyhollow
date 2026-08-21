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

    /// Archives the currently loaded page.
    ///
    /// `createWebArchiveData` has no async overload in the SDK — only a
    /// `Result<Data, any Error>` completion handler — so this wraps it in a
    /// checked continuation rather than `try await`ing it directly.
    @MainActor
    public func execute(on host: PageHost) async throws -> Output {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            host.webView.createWebArchiveData { result in
                continuation.resume(with: result)
            }
        }
        return Output(archive: data)
    }
}
