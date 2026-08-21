import WebKit

/// `sleepy find`: does the *rendered* page say this, the way ⌘F would?
///
/// Runs `WKWebView.find(_:configuration:)` — the engine's own find-in-page,
/// confirmed available since macOS 12 (this package's floor) by targeting
/// the SDK directly; `WKFindResult` exposes exactly one fact,
/// `matchFound`, so this operation's ``Output`` is that `Bool` and nothing
/// invented on top of it. A match also becomes the *selected* find result
/// in-page (WebKit's own side effect of searching); the operation does not
/// suppress or read that back — the contract is match-found-or-not, not a
/// count or a location.
public struct FindOperation: ExecutablePageOperation {
    /// This operation's typed result: whether the text was found.
    public typealias Output = Bool

    /// The wire identifier.
    public static let kind: String = "find"

    /// The text to search for, exactly as a user would type it into ⌘F.
    public var text: String

    /// Creates the operation.
    public init(text: String) {
        self.text = text
    }

    /// Searches the page's rendered content for ``text``.
    @MainActor
    public func execute(on host: PageHost) async throws -> Bool {
        let result = try await host.webView.find(text, configuration: WKFindConfiguration())
        return result.matchFound
    }
}
