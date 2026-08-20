/// The validated name of a persistent cookie jar.
///
/// Jars are named state independent of sessions: a jar name keys a file under
/// `~/.sleepyhollow/jars/`, so construction validates via the shared
/// state-name rule and decoding an unsafe name fails. Distinct from
/// ``SessionName`` on purpose — the types prevent handing a jar where a
/// session is expected.
public struct JarName: RawRepresentable, Friendly, CustomStringConvertible {
    /// The validated name text.
    public let rawValue: String

    /// Creates a name if `rawValue` passes the state-name rule; `nil` otherwise.
    public init?(rawValue: String) {
        guard StateNameRule.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// Shorthand for ``init(rawValue:)``.
    public init?(_ raw: String) {
        self.init(rawValue: raw)
    }

    /// The name text.
    public var description: String {
        rawValue
    }
}
