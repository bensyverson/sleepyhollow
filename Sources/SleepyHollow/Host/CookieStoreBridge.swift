import Foundation
import WebKit

/// The whole bridge to `WKHTTPCookieStore`, in three calls, each inside a
/// deadline.
///
/// `WKHTTPCookieStore`'s reads and writes are completion-handler APIs with
/// *optional* handlers, so Swift generates no `async` overloads for them —
/// and a completion handler has no timeout of its own: a networking process
/// that stops answering would suspend a cookie read, a jar import or a jar
/// save for good. So every call goes through its owner's
/// ``DeadlineKeeper/answer(_:within:start:)`` at the owner's
/// ``DeadlineKeeper/callBudget``, and ends in a ``SleepyError/Kind/timeout``
/// instead.
///
/// It lives on its own because two owners need it: a ``PageHost`` reads and
/// writes its own store, and a ``HostGroup`` reads and writes the one store
/// all its members share. Both wrappers map to ``CookieRecord`` or take an
/// already-built `HTTPCookie`, so nothing non-`Sendable` crosses a
/// continuation.
enum CookieStoreBridge {
    /// Every cookie `store` currently holds.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/timeout`` when
    ///   the store does not answer within `owner`'s call budget.
    @MainActor
    static func allCookies(in store: some CookieStoreCalls, through owner: some DeadlineKeeper) async throws
        -> [CookieRecord]
    {
        try await owner.answer("the cookie store read", within: owner.callBudget) { answered in
            store.readAll { cookies in answered(.success(cookies.map(CookieRecord.init))) }
        }
    }

    /// Puts `cookie` in `store`, replacing any cookie in the same slot.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/timeout`` when
    ///   the store does not answer within `owner`'s call budget.
    @MainActor
    static func set(
        _ cookie: HTTPCookie,
        in store: some CookieStoreCalls,
        through owner: some DeadlineKeeper,
    ) async throws {
        try await owner.answer("the cookie store write", within: owner.callBudget) { answered in
            store.write(cookie) { answered(.success(())) }
        }
    }

    /// Pushes `records` into `store` and forces one round-trip after them.
    ///
    /// The read is not a check: it is what makes WebKit hand the cookies to
    /// its networking process before the first request goes out.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/timeout`` at the
    ///   first call the store does not answer within `owner`'s call budget.
    @MainActor
    static func load(
        _ records: [CookieRecord],
        into store: some CookieStoreCalls,
        through owner: some DeadlineKeeper,
    ) async throws {
        for record in records {
            guard let cookie: HTTPCookie = record.httpCookie else { continue }
            try await set(cookie, in: store, through: owner)
        }
        _ = try await allCookies(in: store, through: owner)
    }
}
