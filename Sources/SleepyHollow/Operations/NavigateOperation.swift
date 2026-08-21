import Foundation

/// Navigates a page and reports the facts — the operation behind `sleepy load`.
///
/// It is the only operation with a `nil` shape: `sleepy load --session <n>`
/// with no URL asks a session what page it is *on*, and answering that needs
/// no navigation at all. With a URL it navigates and reports where the
/// navigation ended, which is how a live session moves between pages (the
/// vision doc, §5: "`sleepy load --session login <url>` to navigate it").
///
/// The navigation runs under the *host's* budget and wait condition — a
/// session's were fixed when it opened, which is why a `--session` invocation
/// refuses load-shaping flags rather than pretending to honour them.
///
/// ```swift
/// let facts: PageFacts = try await client.run(NavigateOperation(url: next))
/// ```
public struct NavigateOperation: ExecutablePageOperation {
    /// The facts this operation returns.
    public typealias Output = PageFacts

    /// The wire identifier.
    public static let kind: String = "navigate"

    /// Where to navigate; `nil` reports the page's current facts untouched.
    public var url: URL?

    /// Creates the operation.
    public init(url: URL?) {
        self.url = url
    }

    /// Navigates to ``url`` when there is one, and returns the page's facts.
    ///
    /// - Throws: whatever ``PageHost/load(_:)`` throws — a
    ///   ``SleepyError/Kind/loadFailure`` for a navigation that failed, a
    ///   ``SleepyError/Kind/timeout`` when the budget ran out.
    @MainActor
    public func execute(on host: PageHost) async throws -> PageFacts {
        guard let url else { return host.facts }
        return try await host.load(url)
    }
}
