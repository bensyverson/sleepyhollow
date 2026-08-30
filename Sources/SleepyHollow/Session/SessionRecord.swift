import Foundation

/// What a helper leaves in its session directory so any other invocation can
/// find it and judge whether it is still alive.
///
/// Written as `session.json` beside the Unix socket the moment the helper is
/// listening, and deleted with the directory when it exits cleanly. The
/// process id is the first half of the liveness probe (the socket is the
/// other half); the URL and start time are what `sleepy sessions list` shows.
public struct SessionRecord: Friendly {
    /// The helper process's id — probed with `kill(pid, 0)`.
    public let processID: Int32

    /// The URL the session opened with, when it was given one.
    public let url: URL?

    /// When the helper started listening.
    public let startedAt: Date

    /// Seconds of idle time after which the helper exits by itself.
    public let idleTimeout: TimeInterval

    /// The ceiling, in seconds, the helper applies to one operation — the
    /// `--budget` its `sleepy open` carried, or ``LoadOptions/defaultBudget``.
    ///
    /// Recorded so a client can bound its own wait against the *helper's*
    /// clock rather than against a number it made up: a session opened with
    /// `--budget 60000` may legitimately take a minute to answer, and a client
    /// that assumed 30 s would call that a timeout (job issue MN69b).
    public let budget: TimeInterval

    /// Creates a record.
    public init(
        processID: Int32,
        url: URL?,
        startedAt: Date,
        idleTimeout: TimeInterval,
        budget: TimeInterval = LoadOptions.defaultBudget,
    ) {
        self.processID = processID
        self.url = url
        self.startedAt = startedAt
        self.idleTimeout = idleTimeout
        self.budget = budget
    }

    /// How long the helper has been up, as of now.
    public var age: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }
}
