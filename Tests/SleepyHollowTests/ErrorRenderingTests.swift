@testable import SleepyCLIKit
import SleepyHollow
import Testing

/// Every failure path renders as next-move guidance, never a stack trace,
/// and exits with Core's documented status.
struct ErrorRenderingTests {
    @Test func `a SleepyError renders its message and next move to standard error`() {
        let error = SleepyError(
            kind: .environment,
            message: "No session named 'login-flow'.",
            nextMove: "`sleepy sessions list` shows open sessions.",
        )
        let rendered = ErrorRendering.render(sleepyError: error)
        #expect(rendered.text.contains("No session named 'login-flow'."))
        #expect(rendered.text.contains("`sleepy sessions list` shows open sessions."))
        #expect(rendered.toStandardError == true)
        #expect(rendered.exitCode == SleepyHollow.ExitStatus.environment.rawValue)
    }

    @Test func `every SleepyError kind exits with its documented status`() {
        let kinds: [(SleepyError.Kind, SleepyHollow.ExitStatus)] = [
            (.usage, .usage),
            (.timeout, .timeout),
            (.loadFailure, .loadFailure),
            (.environment, .environment),
        ]
        for (kind, status) in kinds {
            let rendered = ErrorRendering.render(sleepyError: SleepyError(kind: kind, message: "m"))
            #expect(rendered.exitCode == status.rawValue)
        }
    }

    @Test func `an argument-parsing failure renders no stack trace and exits usage`() {
        let rendered = ErrorRendering.renderParsingFailure(usage: "Usage: sleepy [--help]", commandName: "sleepy")
        #expect(!rendered.text.contains("Fatal error"))
        #expect(!rendered.text.contains(".swift:"))
        #expect(rendered.text.contains("sleepy --help"))
        #expect(rendered.text.contains("Usage: sleepy [--help]"))
        #expect(rendered.toStandardError == true)
        #expect(rendered.exitCode == SleepyHollow.ExitStatus.usage.rawValue)
    }

    @Test func `an argument-parsing failure exits 2, not ArgumentParser's own EX_USAGE`() {
        let rendered = ErrorRendering.renderParsingFailure(usage: "", commandName: "sleepy")
        #expect(rendered.exitCode == 2)
    }
}
