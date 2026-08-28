/// Everything `sleepy doctor` found, in the order it looked.
///
/// The report is the verb's output *and* its verdict: ``status`` rolls the
/// checks up, ``error`` is the teaching failure the CLI throws so the first
/// thing that is wrong lands on standard error like every other failure in
/// the tool, and ``exitStatus`` is the code an agent branches on.
public struct DoctorReport: Friendly {
    /// The checks, in the order they ran.
    public let checks: [DoctorCheck]

    /// `failed` when any check failed, `ok` otherwise.
    ///
    /// Stored rather than computed so the JSON carries the verdict too: an
    /// agent reading the output should not have to fold over the array to
    /// learn whether its environment is sound.
    public let status: DoctorCheck.Status

    /// Creates a report over `checks`, deriving ``status`` from them.
    public init(checks: [DoctorCheck]) {
        self.checks = checks
        status = checks.contains { $0.status == .failed } ? .failed : .ok
    }

    /// The first check that failed — usually the cause of any that follow.
    public var firstFailure: DoctorCheck? {
        checks.first { $0.status == .failed }
    }

    /// The failure to throw, or `nil` when everything passed.
    public var error: SleepyError? {
        firstFailure?.error
    }

    /// The process exit code: 0 when every check passed, 5 otherwise.
    public var exitStatus: ExitStatus {
        error?.exitStatus ?? .success
    }

    /// The `--format text` rendering: one line per check — status, name,
    /// detail — with a failure's next move indented underneath it.
    ///
    /// No trailing newline; the caller adds one.
    public var text: String {
        var lines: [String] = []
        for check in checks {
            let status: String = Self.padded(check.status.rawValue, to: Self.statusWidth)
            let name: String = Self.padded(check.name.rawValue, to: Self.nameWidth)
            lines.append("\(status)\(name)\(check.detail)")
            if let nextMove = check.nextMove {
                lines.append(String(repeating: " ", count: Self.statusWidth + Self.nameWidth) + nextMove)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Column width for the status word, wide enough for `failed` plus a gap.
    private static let statusWidth: Int = 8

    /// Column width for the check's name, wide enough for `sessions` plus a gap.
    private static let nameWidth: Int = 10

    private static func padded(_ text: String, to width: Int) -> String {
        text + String(repeating: " ", count: max(1, width - text.count))
    }
}
