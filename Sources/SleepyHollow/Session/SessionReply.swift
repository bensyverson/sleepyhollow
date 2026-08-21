import Foundation

/// What a session helper answers with — the reply half of the wire protocol.
///
/// Failures travel as ``SleepyError`` rather than as a dropped connection, so
/// a session failure teaches exactly as much as a one-shot failure does, and
/// maps onto the same exit code.
public enum SessionReply: Friendly {
    /// The operation's `Output`, JSON-encoded. The client decodes it as the
    /// operation type's own `Output` — the helper never needs to know which
    /// type that is.
    case output(Data)

    /// A control request was carried out.
    case acknowledged

    /// The request failed, with the reason and the next move intact.
    case failure(SleepyError)
}
