@testable import SleepyHollow
import Testing

/// Errors teach: every failure carries what happened, the next move, and the
/// exit status agents branch on.
struct SleepyErrorTests {
    @Test func `kinds map to the documented exit statuses`() {
        #expect(SleepyError(kind: .usage, message: "m").exitStatus == .usage)
        #expect(SleepyError(kind: .timeout, message: "m").exitStatus == .timeout)
        #expect(SleepyError(kind: .loadFailure, message: "m").exitStatus == .loadFailure)
        #expect(SleepyError(kind: .environment, message: "m").exitStatus == .environment)
    }

    @Test func `description carries the message and the next move`() {
        let error = SleepyError(
            kind: .environment,
            message: "No session named 'login-flow'.",
            nextMove: "`sleepy sessions list` shows open sessions.",
        )
        #expect(error.description.contains("No session named 'login-flow'."))
        #expect(error.description.contains("`sleepy sessions list` shows open sessions."))
    }
}
