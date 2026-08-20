/// A failure that teaches: what happened, the next move, and the exit status
/// agents branch on.
///
/// Every failure path in the tool states the next move ("No session named
/// `login-flow` — `sleepy sessions list` shows two open sessions") rather
/// than dumping a stack trace.
public struct SleepyError: Error, Friendly, CustomStringConvertible {
    /// The failure's category, mapping onto ``ExitStatus``.
    public enum Kind: String, Friendly {
        /// The invocation itself was malformed.
        case usage
        /// The budget ran out before the condition was met.
        case timeout
        /// The page failed to load or navigate.
        case loadFailure
        /// The tool's environment is wrong: missing session, dead helper,
        /// bad jar.
        case environment
    }

    /// The failure's category.
    public let kind: Kind

    /// What happened.
    public let message: String

    /// What to do about it, when there is a next move to teach.
    public let nextMove: String?

    /// Creates an error.
    public init(kind: Kind, message: String, nextMove: String? = nil) {
        self.kind = kind
        self.message = message
        self.nextMove = nextMove
    }

    /// The exit status this failure maps to.
    public var exitStatus: ExitStatus {
        switch kind {
        case .usage: .usage
        case .timeout: .timeout
        case .loadFailure: .loadFailure
        case .environment: .environment
        }
    }

    /// The message, followed by the next move when present.
    public var description: String {
        if let nextMove {
            "\(message) \(nextMove)"
        } else {
            message
        }
    }
}
