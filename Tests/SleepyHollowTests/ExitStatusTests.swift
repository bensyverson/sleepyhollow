@testable import SleepyHollow
import Testing

/// The documented exit-code scheme: agents branch on these numbers, so they
/// are a public contract, not an implementation detail.
struct ExitStatusTests {
    @Test func `codes match the documented scheme`() {
        #expect(ExitStatus.success.rawValue == 0)
        #expect(ExitStatus.negative.rawValue == 1)
        #expect(ExitStatus.usage.rawValue == 2)
        #expect(ExitStatus.timeout.rawValue == 3)
        #expect(ExitStatus.loadFailure.rawValue == 4)
        #expect(ExitStatus.environment.rawValue == 5)
    }
}
