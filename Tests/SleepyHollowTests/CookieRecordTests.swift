import Foundation
@testable import SleepyHollow
import Testing

/// The jar's wire type: what survives a round trip through `HTTPCookie`, and
/// what "expired" means.
@Suite("CookieRecord")
struct CookieRecordTests {
    private func record(
        name: String = "sid",
        value: String = "abc123",
        domain: String = "127.0.0.1",
        path: String = "/",
        expiresAt: Date? = nil,
        isSecure: Bool = false,
        isHTTPOnly: Bool = false,
        sameSite: CookieRecord.SameSite? = nil,
    ) -> CookieRecord {
        CookieRecord(
            name: name,
            value: value,
            domain: domain,
            path: path,
            expiresAt: expiresAt,
            isSecure: isSecure,
            isHTTPOnly: isHTTPOnly,
            sameSite: sameSite,
        )
    }

    @Test func `a session cookie round-trips through HTTPCookie`() throws {
        let original: CookieRecord = record()
        let cookie = try #require(original.httpCookie)
        let restored = CookieRecord(cookie)
        #expect(restored == original)
    }

    @Test func `an expiring, secure, http-only cookie round-trips`() throws {
        // Whole seconds: HTTPCookie serializes `expires` to second resolution,
        // so a fractional Date would not compare equal after the round trip.
        let expiry = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 3600).rounded())
        let original: CookieRecord = record(
            expiresAt: expiry,
            isSecure: true,
            isHTTPOnly: true,
            sameSite: .lax,
        )
        let cookie = try #require(original.httpCookie)
        #expect(cookie.isSecure)
        #expect(cookie.isHTTPOnly)
        let restored = CookieRecord(cookie)
        #expect(restored == original)
    }

    /// Foundation caps a cookie's lifetime at ~400 days, exactly as Safari and
    /// Chrome do. A jar may hold a longer expiry, but the browser it is poured
    /// into will shorten it — so the tool must not promise otherwise.
    @Test func `an expiry further out than the browser cap comes back clamped`() throws {
        let original: CookieRecord = record(expiresAt: Date(timeIntervalSince1970: 4_102_444_800))
        let cookie = try #require(original.httpCookie)
        let restored = CookieRecord(cookie)
        let expiry = try #require(restored.expiresAt)
        #expect(expiry < Date(timeIntervalSinceNow: 401 * 24 * 3600))
        #expect(expiry > Date())
    }

    @Test func `a cookie with no name makes no HTTPCookie`() {
        #expect(record(name: "").httpCookie == nil)
    }

    @Test func `expiry is measured against a given instant`() {
        let past: CookieRecord = record(expiresAt: Date(timeIntervalSince1970: 1000))
        #expect(past.isExpired(at: Date(timeIntervalSince1970: 2000)))
        #expect(!past.isExpired(at: Date(timeIntervalSince1970: 500)))
    }

    @Test func `a session cookie never expires and is labelled as one`() {
        let session: CookieRecord = record()
        #expect(session.isSessionCookie)
        #expect(!session.isExpired(at: Date(timeIntervalSince1970: 4_102_444_800)))
    }

    @Test func `the record encodes and decodes as JSON`() throws {
        let original: CookieRecord = record(expiresAt: Date(timeIntervalSince1970: 4_102_444_800))
        let data: Data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(CookieRecord.self, from: data) == original)
    }
}
