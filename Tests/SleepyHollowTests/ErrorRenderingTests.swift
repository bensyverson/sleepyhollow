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

    @Test func `an argument-parsing failure passes the parser's own diagnosis through`() {
        let diagnosis = """
        sleepy: Missing expected argument '--selector <selector>'
        Usage: sleepy query [<url>] --selector <selector>
          See 'sleepy query --help' for more information.
        """
        let rendered = ErrorRendering.renderParsingFailure(fullText: diagnosis, commandName: "sleepy")
        #expect(!rendered.text.contains("Fatal error"))
        #expect(!rendered.text.contains(".swift:"))
        #expect(rendered.text.contains("--selector"))
        #expect(rendered.text.contains("sleepy query --help"))
        #expect(rendered.toStandardError == true)
        #expect(rendered.exitCode == SleepyHollow.ExitStatus.usage.rawValue)
    }

    @Test func `a parser that says nothing still names both help screens`() {
        let rendered = ErrorRendering.renderParsingFailure(fullText: "   \n ", commandName: "sleepy")
        #expect(rendered.text.contains("sleepy --help"))
        #expect(rendered.text.contains("sleepy <verb> --help"))
    }

    // MARK: - A word where a verb belongs

    private static let verbs: [String] = ["load", "shot", "dom", "query", "ax", "open", "close"]

    @Test func `an unknown verb is named, and the verb list is pointed at`() {
        let rendered = ErrorRendering.renderUnknownVerb("frobnicate", knownVerbs: Self.verbs, commandName: "sleepy")
        #expect(rendered.text.contains("frobnicate"))
        #expect(rendered.text.contains("sleepy --help"))
        #expect(rendered.exitCode == SleepyHollow.ExitStatus.usage.rawValue)
        #expect(rendered.toStandardError == true)
    }

    @Test func `a wild guess gets no misleading suggestion`() {
        let rendered = ErrorRendering.renderUnknownVerb("frobnicate", knownVerbs: Self.verbs, commandName: "sleepy")
        #expect(!rendered.text.contains("Did you mean"))
    }

    @Test func `a one-letter slip is suggested`() {
        let rendered = ErrorRendering.renderUnknownVerb("dm", knownVerbs: Self.verbs, commandName: "sleepy")
        #expect(rendered.text.contains("Did you mean `sleepy dom`?"))
    }

    @Test func `a plural is suggested`() {
        #expect(ErrorRendering.nearestVerb(to: "shots", among: Self.verbs) == "shot")
    }

    @Test func `a prefix is suggested however short`() {
        #expect(ErrorRendering.nearestVerb(to: "q", among: Self.verbs) == "query")
    }

    @Test func `case is not a reason to fail`() {
        #expect(ErrorRendering.nearestVerb(to: "LOAD", among: Self.verbs) == "load")
    }

    @Test func `nothing close suggests nothing`() {
        #expect(ErrorRendering.nearestVerb(to: "screenshot", among: Self.verbs) == nil)
    }

    @Test func `an exact verb is its own nearest`() {
        #expect(ErrorRendering.nearestVerb(to: "ax", among: Self.verbs) == "ax")
    }

    @Test func `an argument-parsing failure exits 2, not ArgumentParser's own EX_USAGE`() {
        let rendered = ErrorRendering.renderParsingFailure(fullText: "", commandName: "sleepy")
        #expect(rendered.exitCode == 2)
    }
}
