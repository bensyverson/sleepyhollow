/// The validated name of a persistent session.
///
/// Naming is the opt-in to state: a session name keys a helper process and a
/// directory under `~/.sleepyhollow/sessions/`, so construction validates via
/// the shared state-name rule and decoding an unsafe name fails.
public struct SessionName: RawRepresentable, Friendly, CustomStringConvertible {
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
