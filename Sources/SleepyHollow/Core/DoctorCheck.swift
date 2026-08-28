/// One environment question `sleepy doctor` asks, and the answer it got.
///
/// The point of a check is that it teaches: a failure carries the same
/// message-plus-next-move shape every other failure in the tool has, so an
/// agent whose first call died reads *why* and *what to do* in one place. A
/// check that passes says what it found instead, because the fact that the
/// binary resolves to a particular path is itself worth reading.
public struct DoctorCheck: Friendly {
    /// Which question was asked. The raw values are the wire names, and the
    /// declaration order is the order `doctor` runs them in — cheapest and
    /// most fundamental first, so the first failure is usually the cause of
    /// the rest.
    public enum Kind: String, Friendly, CaseIterable {
        /// The running executable resolves, is executable, and is what a
        /// session helper would be spawned from.
        case binary
        /// WebKit's web content process can launch under the current sandbox.
        case webKit = "webkit"
        /// The sessions directory resolves, is writable, and leaves room for
        /// a session's Unix socket path.
        case sessions
        /// The temp directory is writable.
        case temporaryDirectory = "temp"
    }

    /// Whether the question was answered well.
    public enum Status: String, Friendly {
        /// The check passed.
        case ok
        /// The check failed, and ``DoctorCheck/nextMove`` says what to do.
        case failed
    }

    /// Which question this is.
    public let name: Kind

    /// How it was answered.
    public let status: Status

    /// What was found — the path, the measurement, or the failure's message.
    public let detail: String

    /// What to do about a failure; `nil` when the check passed.
    public let nextMove: String?

    /// Creates a check result.
    public init(name: Kind, status: Status, detail: String, nextMove: String? = nil) {
        self.name = name
        self.status = status
        self.detail = detail
        self.nextMove = nextMove
    }

    /// A check that passed, describing what it found.
    public static func passed(_ name: Kind, _ detail: String) -> DoctorCheck {
        DoctorCheck(name: name, status: .ok, detail: detail)
    }

    /// A check that failed, with the next move spelled out.
    public static func failed(_ name: Kind, _ detail: String, nextMove: String) -> DoctorCheck {
        DoctorCheck(name: name, status: .failed, detail: detail, nextMove: nextMove)
    }

    /// A check that failed with `error`'s own words.
    ///
    /// How a check reuses the teaching text the rest of the library already
    /// writes — ``WebContentProcessFailure/error(url:)``,
    /// ``SessionRegistry/socketPath(for:)`` — rather than restating it and
    /// letting the two drift.
    public static func failed(_ name: Kind, _ error: SleepyError) -> DoctorCheck {
        DoctorCheck(name: name, status: .failed, detail: error.message, nextMove: error.nextMove)
    }

    /// This check's failure as a thrown error, or `nil` when it passed.
    ///
    /// Always ``SleepyError/Kind/environment`` — exit 5 — whatever the
    /// underlying failure's own kind was: every question `doctor` asks is a
    /// question about the environment, and an agent branching on the exit
    /// code should not have to know which check failed to know that.
    public var error: SleepyError? {
        guard status == .failed else { return nil }
        return SleepyError(kind: .environment, message: detail, nextMove: nextMove)
    }
}
