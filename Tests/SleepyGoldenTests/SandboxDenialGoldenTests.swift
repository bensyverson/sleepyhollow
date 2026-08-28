import Foundation
import SleepyHollow
import Testing

/// The whole point of the sandbox detection, end to end: the real binary,
/// under a real sandbox that denies WebKit its web content process.
///
/// The profile and the runner live in ``SandboxedBinary``, shared with
/// ``DoctorGoldenTests``. `about:blank` keeps the test free of a fixture
/// server: WebKit still needs a content process to render nothing, and the
/// denial lands before any navigation begins.
@Suite("Sandbox denial, end to end")
struct SandboxDenialGoldenTests {
    @Test
    func `a denied web content process exits 4 with the sandbox message, not a timeout`() async throws {
        try #require(SandboxedBinary.isAvailable, "sandbox-exec is how this failure is reproduced")

        let run: CliInvocation = try await SandboxedBinary.runDenyingWebContent(
            ["load", "about:blank", "--budget", "15000"],
        )
        #expect(run.exitCode == ExitStatus.loadFailure.rawValue)
        #expect(run.standardError.contains("WebKit could not start under this sandbox"))
        #expect(run.standardError.contains("dangerouslyDisableSandbox"))
        #expect(!run.standardError.contains("did not finish loading"))
    }
}
