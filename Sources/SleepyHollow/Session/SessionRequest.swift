/// What a client asks a session helper to do — the request half of the wire
/// protocol.
///
/// There are exactly two asks, and only one of them is about pages: everything
/// a verb wants is an ``OperationEnvelope``, which the helper decodes with its
/// ``OperationRegistry``. That is the whole point of the seam — adding a verb
/// never changes this type.
public enum SessionRequest: Friendly {
    /// Run this operation against the session's page and answer with its output.
    case operation(OperationEnvelope)

    /// Stop the helper: it answers ``SessionReply/acknowledged``, cleans its
    /// directory, and exits.
    case shutdown
}
