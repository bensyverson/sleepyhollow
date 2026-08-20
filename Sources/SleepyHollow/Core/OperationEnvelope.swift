import Foundation

/// The wire form of a ``PageOperation``: its ``kind`` plus a JSON payload.
///
/// Envelopes are what the session client ships over the Unix socket; an
/// ``OperationRegistry`` on the far side turns them back into typed
/// operations.
public struct OperationEnvelope: Friendly {
    /// The operation type's stable identifier (``PageOperation/kind``).
    public let kind: String

    /// The operation value, JSON-encoded.
    public let payload: Data

    /// Wraps `operation` for transport.
    public init<O: PageOperation>(_ operation: O) throws {
        kind = O.kind
        payload = try JSONEncoder().encode(operation)
    }
}
