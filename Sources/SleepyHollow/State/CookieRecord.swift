import Foundation

/// One cookie, as a jar stores it and as `sleepy cookies` reports it.
///
/// The tool's own cookie type rather than `HTTPCookie` because a jar is a
/// *file*: this is `Friendly`, so it encodes deterministically, ships over the
/// session socket, and compares in a test. ``httpCookie`` and ``init(_:)``
/// are the only places `HTTPCookie` is touched.
///
/// A cookie with no ``expiresAt`` is a session cookie. Jars keep those on
/// purpose — most authentication cookies are session cookies, and a jar exists
/// precisely so a minted login outlives the process that minted it.
public struct CookieRecord: Friendly {
    /// A cookie's cross-site policy, as far as Foundation models it: absent
    /// means the cookie declared none.
    public enum SameSite: String, Friendly {
        /// Sent on top-level navigations to the origin.
        case lax
        /// Sent only on same-site requests.
        case strict
    }

    /// The cookie's name.
    public var name: String

    /// The cookie's value, as stored — never percent-decoded.
    public var value: String

    /// The domain the cookie is scoped to (a leading `.` means subdomains).
    public var domain: String

    /// The path prefix the cookie is sent for.
    public var path: String

    /// When the cookie expires; `nil` for a session cookie.
    public var expiresAt: Date?

    /// Whether the cookie is only sent over TLS.
    public var isSecure: Bool

    /// Whether script is barred from reading the cookie.
    public var isHTTPOnly: Bool

    /// The cookie's `SameSite` policy, when it declared one.
    public var sameSite: SameSite?

    /// Creates a record.
    public init(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        expiresAt: Date? = nil,
        isSecure: Bool = false,
        isHTTPOnly: Bool = false,
        sameSite: SameSite? = nil,
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expiresAt = expiresAt
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
        self.sameSite = sameSite
    }

    /// Reads a record from a live `HTTPCookie`.
    public init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expiresAt = cookie.expiresDate
        isSecure = cookie.isSecure
        isHTTPOnly = cookie.isHTTPOnly
        switch cookie.sameSitePolicy {
        case HTTPCookieStringPolicy.sameSiteLax: sameSite = .lax
        case HTTPCookieStringPolicy.sameSiteStrict: sameSite = .strict
        default: sameSite = nil
        }
    }

    /// Whether this cookie identifies the same slot as `other` — name, domain
    /// and path, which is what the cookie protocol keys on. Setting a cookie
    /// replaces the record it matches rather than accumulating duplicates.
    public func occupiesSameSlot(as other: CookieRecord) -> Bool {
        name == other.name && domain == other.domain && path == other.path
    }

    /// Whether the cookie dies with the browsing session — it declared no
    /// expiry. Jars keep these anyway; see the type's discussion.
    public var isSessionCookie: Bool {
        expiresAt == nil
    }

    /// Whether the cookie has expired by `instant`. Session cookies never have.
    public func isExpired(at instant: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= instant
    }

    /// The cookie as `HTTPCookie`, or `nil` when the record is not one
    /// Foundation will accept (an empty name or domain, most often).
    ///
    /// - Note: Foundation caps a cookie's lifetime at about 400 days, as
    ///   Safari and Chrome do, so an ``expiresAt`` further out than that comes
    ///   back shortened. A jar may hold the longer date; the browser will not
    ///   honour it, and the tool does not pretend otherwise.
    public var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            HTTPCookiePropertyKey.name: name,
            HTTPCookiePropertyKey.value: value,
            HTTPCookiePropertyKey.domain: domain,
            HTTPCookiePropertyKey.path: path,
        ]
        if let expiresAt {
            properties[HTTPCookiePropertyKey.expires] = expiresAt
        }
        if isSecure {
            properties[HTTPCookiePropertyKey.secure] = "TRUE"
        }
        if isHTTPOnly {
            // Not a vended key: Foundation's own Set-Cookie parser stores the
            // flag under this name, and `isHTTPOnly` reads it straight back.
            properties[Self.httpOnlyKey] = "TRUE"
        }
        switch sameSite {
        case .lax: properties[HTTPCookiePropertyKey.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax.rawValue
        case .strict: properties[HTTPCookiePropertyKey.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict.rawValue
        case nil: break
        }
        return HTTPCookie(properties: properties)
    }

    /// The property key Foundation stores the `HttpOnly` flag under.
    private static let httpOnlyKey: HTTPCookiePropertyKey = .init("HttpOnly")

    /// One terse line carrying every attribute the cookie actually declares —
    /// the `--format text` rendering.
    public var terseLine: String {
        var parts = ["\(name)=\(value)"]
        parts.append("Domain=\(domain)")
        parts.append("Path=\(path)")
        if let expiresAt {
            parts.append("Expires=\(Self.iso8601(expiresAt))")
        }
        if isSecure { parts.append("Secure") }
        if isHTTPOnly { parts.append("HttpOnly") }
        if let sameSite { parts.append("SameSite=\(sameSite.rawValue)") }
        return parts.joined(separator: "; ")
    }

    /// `instant` as ISO 8601 in UTC, so the same cookie renders the same bytes
    /// on any machine in any locale.
    ///
    /// Built per call rather than cached: `ISO8601DateFormatter` is a mutable
    /// class and so not `Sendable`, and a jar's output is a handful of lines.
    static func iso8601(_ instant: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: instant)
    }
}
