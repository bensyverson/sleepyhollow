import Foundation

/// `sleepy cookies`: read, or write then read, the page's live cookie store.
///
/// One operation for both directions on purpose. `get` and `set` differ only
/// in whether a cookie goes in first, and both answer with what the store
/// holds afterwards — so `set` is self-verifying, and there is exactly one
/// code path that reports a cookie.
///
/// Jars are *not* this operation's business: it works against whatever store
/// the host has, and the host writes that store back to its jar. Reading or
/// writing a jar with no page at all needs no operation — that is
/// ``JarStore`` and the CLI calling it directly.
public struct CookiesOperation: ExecutablePageOperation {
    /// This operation's typed result: the matching cookies in the live store.
    public typealias Output = [CookieRecord]

    /// The wire identifier.
    public static let kind: String = "cookies"

    /// A cookie to put in the store before reading it back; `nil` reads only.
    public var cookie: CookieRecord?

    /// When given, only cookies with this name are reported.
    public var name: String?

    /// Creates a read, optionally filtered by cookie name.
    public init(name: String? = nil) {
        cookie = nil
        self.name = name
    }

    /// Creates a write: `cookie` goes into the store, and the cookies now
    /// under its name come back.
    public init(set cookie: CookieRecord) {
        self.cookie = cookie
        name = cookie.name
    }

    /// Writes ``cookie`` when there is one, then reports the store's cookies,
    /// filtered by ``name`` when that is set.
    @MainActor
    public func execute(on host: PageHost) async throws -> [CookieRecord] {
        if let cookie {
            try await host.setCookie(cookie)
        }
        let all: [CookieRecord] = await host.currentCookies()
        guard let name else { return all.sorted(by: Self.byNameThenDomain) }
        return all.filter { $0.name == name }.sorted(by: Self.byNameThenDomain)
    }

    /// A stable order, so the same store reports the same bytes twice — the
    /// cookie store's own order is not guaranteed.
    private static func byNameThenDomain(_ first: CookieRecord, _ second: CookieRecord) -> Bool {
        (first.name, first.domain, first.path) < (second.name, second.domain, second.path)
    }
}
