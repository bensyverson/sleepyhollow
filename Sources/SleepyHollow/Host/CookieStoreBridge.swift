import Foundation
import WebKit

/// The whole bridge to `WKHTTPCookieStore`, in two calls.
///
/// `WKHTTPCookieStore`'s reads and writes are completion-handler APIs with
/// *optional* handlers, so Swift generates no `async` overloads for them.
/// Both wrappers map to ``CookieRecord`` or take an already-built `HTTPCookie`
/// so nothing non-`Sendable` crosses a continuation.
///
/// It lives on its own because two owners need it: a ``PageHost`` reads and
/// writes its own store, and a ``HostGroup`` reads and writes the one store
/// all its members share.
enum CookieStoreBridge {
    /// Every cookie `store` currently holds.
    @MainActor
    static func allCookies(in store: WKHTTPCookieStore) async -> [CookieRecord] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[CookieRecord], Never>) in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies.map(CookieRecord.init))
            }
        }
    }

    /// Puts `cookie` in `store`, replacing any cookie in the same slot.
    @MainActor
    static func set(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    /// Pushes `records` into `store` and forces one round-trip after them.
    ///
    /// The read is not a check: it is what makes WebKit hand the cookies to
    /// its networking process before the first request goes out.
    @MainActor
    static func load(_ records: [CookieRecord], into store: WKHTTPCookieStore) async {
        for record in records {
            guard let cookie: HTTPCookie = record.httpCookie else { continue }
            await set(cookie, in: store)
        }
        _ = await allCookies(in: store)
    }
}
