import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy doctor` — the verb to run when the first call failed and the
/// reason isn't obvious.
///
/// Every other verb reports what went wrong with *its* invocation. `doctor`
/// reports what is wrong with the environment underneath all of them: the
/// binary, WebKit's launch under the current sandbox, the sessions directory,
/// the temp directory — each with the same message-plus-next-move a failure
/// carries, so one command turns "it timed out" into "the sandbox denied
/// WebKit its content process, and here is how to run it anyway".
///
/// It answers even when it fails: the full report goes to standard output,
/// and only then does the first failure land on standard error and set the
/// exit code, so an agent gets the whole diagnosis and the headline both.
struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Diagnose the environment: the binary, WebKit's sandbox, the sessions directory, temp.",
        discussion: """
        Runs four checks in order — binary, webkit, sessions, temp — and reports each as ok or failed with a next move. The first failure is usually the cause of any that follow, so that is the one on stderr.

        `webkit` loads about:blank: WebKit needs its web content process to render even nothing, so a denial shows up here without a network or a server.

        `sessions` creates the sessions directory if it is missing — the same thing `sleepy open` does — and measures what a session's socket path would cost against the kernel's 103-byte limit.

        Examples:
          sleepy doctor
          sleepy doctor --format text

        Exit codes: 0 every check passed, 2 usage, 5 something in the environment is wrong.
        """,
    )

    @OptionGroup var format: FormatOption
    @OptionGroup var out: OutOption
    @OptionGroup var quiet: QuietOption

    @Option(name: .long, help: "Ceiling in milliseconds for the WebKit launch check. Default 10000.")
    var budget: Int?

    @MainActor
    mutating func run() async throws {
        let chosen: OutputFormat = try format.resolve(
            default: .json,
            supporting: [.json, .text],
            verb: "doctor",
        )
        let report: DoctorReport = try await Doctor.run(budget: resolveBudget())
        switch chosen {
        case .text:
            try out.sink.write(report.text + "\n")
        default:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try out.sink.write(encoder.encode(report))
        }
        if let error: SleepyError = report.error { throw error }
    }

    /// `--budget` in seconds, or ``Doctor/defaultBudget``.
    private func resolveBudget() throws -> TimeInterval {
        guard let budget else { return Doctor.defaultBudget }
        guard budget > 0 else {
            throw SleepyError(
                kind: .usage,
                message: "--budget must be a positive number of milliseconds; got \(budget).",
                nextMove: "Pass a budget like --budget 10000, or leave it out for the default.",
            )
        }
        return TimeInterval(budget) / 1000
    }
}
