/// The conformance bundle every SleepyHollow type adopts: value semantics that
/// can be serialized, compared, hashed, and sent across concurrency domains.
///
/// New types conform to ``Friendly`` even without current plans to serialize or
/// compare them — the session layer ships values over a socket, tests diff
/// them, and `Sendable` is required under strict concurrency anyway.
public typealias Friendly = Codable & Hashable & Sendable
