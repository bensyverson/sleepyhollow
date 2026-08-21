import Foundation
import SleepyHollow

/// Renders a thrown error as terminal text and a process exit code —
/// never a stack trace, and for a `SleepyError` always the message plus
/// its next move.
public enum ErrorRendering {
    /// The result of rendering a failure: what to print, which stream it
    /// goes to, and the code to exit with.
    public struct Rendered: Friendly {
        /// The text to print, without a trailing newline.
        public let text: String

        /// `true` for standard error, `false` for standard output.
        public let toStandardError: Bool

        /// The process exit code.
        public let exitCode: Int32

        /// Creates a rendered failure.
        public init(text: String, toStandardError: Bool, exitCode: Int32) {
            self.text = text
            self.toStandardError = toStandardError
            self.exitCode = exitCode
        }
    }

    /// Renders a `SleepyError`: its message and next move, to standard
    /// error, exiting with the status its `SleepyError/kind` maps to.
    public static func render(sleepyError error: SleepyError) -> Rendered {
        Rendered(text: error.description, toStandardError: true, exitCode: error.exitStatus.rawValue)
    }

    /// Renders an argument-parsing failure that isn't a `SleepyError` — an
    /// unrecognized flag, a missing value, and the like.
    ///
    /// ArgumentParser's own formatted usage text is produced by internal
    /// types (`MessageInfo`, `CommandError`, `ParserError`) that aren't part
    /// of its public API, so this can't reuse it verbatim; it prints a
    /// generic teaching message plus the caller-supplied usage string
    /// instead. Every such failure exits with Core's `ExitStatus/usage`
    /// (2), regardless of ArgumentParser's own default (`EX_USAGE`, 64) —
    /// one exit code for every usage error, whatever produced it.
    public static func renderParsingFailure(usage: String, commandName: String) -> Rendered {
        Rendered(
            text: "\(commandName): didn't understand that invocation.\n\(usage)\nSee '\(commandName) --help' for more information.",
            toStandardError: true,
            exitCode: ExitStatus.usage.rawValue,
        )
    }
}
