/// What the registry found when it probed a session: alive, or dead in one of
/// three distinguishable ways.
///
/// Both halves of the probe matter. A record whose process is gone is the
/// `kill -9` case; a live process whose socket refuses connections is a helper
/// that crashed its listener or has not finished starting. Naming them apart
/// is what lets an error teach the next move instead of saying "broken".
public enum SessionLiveness: String, Friendly {
    /// The helper's process is running and its socket accepts connections.
    case live
    /// Nothing on disk claims this name.
    case noRecord
    /// A record exists, but its process is gone — an orphan to prune.
    case deadProcess
    /// The process is alive, but nothing is listening on its socket.
    case unreachableSocket

    /// Whether work can be sent to this session.
    public var isLive: Bool {
        self == .live
    }

    /// Why the session cannot take work, in a sentence an error can carry.
    ///
    /// `nil` for ``live``, which needs no explanation.
    public var explanation: String? {
        switch self {
        case .live: nil
        case .noRecord: "nothing on disk claims that name"
        case .deadProcess: "its helper process is gone"
        case .unreachableSocket: "its helper is running but its socket isn't answering"
        }
    }
}
