/// One session as the registry sees it: its name, what its helper wrote, and
/// what probing found.
///
/// This is the row `sleepy sessions list` renders and the value `prune`
/// filters on.
public struct SessionEntry: Friendly {
    /// The session's name.
    public let name: SessionName

    /// What the helper recorded when it started.
    public let record: SessionRecord

    /// What probing the process and the socket found, just now.
    public let liveness: SessionLiveness

    /// Creates an entry.
    public init(name: SessionName, record: SessionRecord, liveness: SessionLiveness) {
        self.name = name
        self.record = record
        self.liveness = liveness
    }
}
