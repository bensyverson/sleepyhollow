import Foundation
import SleepyHollow
import Testing

/// The whole point of the sandbox detection, end to end: the real binary,
/// under a real sandbox that denies WebKit its web content process.
///
/// `sandbox-exec` is the only way to reproduce the failure deliberately — the
/// signal is a launch denial, not anything the code can fake. The profile
/// denies exactly one thing (`com.apple.WebKit.WebContent`), so a pass proves
/// the message is tied to that denial and not to a generally crippled process.
/// `about:blank` keeps the test free of a fixture server: WebKit still needs a
/// content process to render nothing, and the denial lands before any
/// navigation begins.
@Suite("Sandbox denial, end to end")
struct SandboxDenialGoldenTests {
    /// Denies the WebKit content process and nothing else.
    private static let profile: String = """
    (version 1)
    (allow default)
    (deny mach-lookup (global-name "com.apple.WebKit.WebContent"))
    """

    @Test
    func `a denied web content process exits 4 with the sandbox message, not a timeout`() async throws {
        try #require(
            FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec"),
            "sandbox-exec is how this failure is reproduced",
        )
        let profileURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepy-deny-webcontent-\(UUID().uuidString).sb")
        try Self.profile.write(to: profileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: profileURL) }

        let run: CliInvocation = try await Self.runSandboxed(
            profile: profileURL,
            arguments: ["load", "about:blank", "--budget", "15000"],
        )
        #expect(run.exitCode == ExitStatus.loadFailure.rawValue)
        #expect(run.standardError.contains("WebKit could not start under this sandbox"))
        #expect(run.standardError.contains("dangerouslyDisableSandbox"))
        #expect(!run.standardError.contains("did not finish loading"))
    }

    /// Runs the built `sleepy` under `sandbox-exec` with `profile`.
    ///
    /// Mirrors ``GoldenBinary/runOffPool(_:environment:)`` — the blocking wait
    /// stays off the cooperative pool — but wraps the binary rather than
    /// running it directly, which ``GoldenBinary`` deliberately has no notion
    /// of.
    private static func runSandboxed(profile: URL, arguments: [String]) async throws -> CliInvocation {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(with: Result {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
                    process.arguments = ["-f", profile.path]
                        + [GoldenBinary.productsDirectory().appendingPathComponent("sleepy").path]
                        + arguments
                    let standardOutput = Pipe()
                    let standardError = Pipe()
                    process.standardOutput = standardOutput
                    process.standardError = standardError
                    try process.run()
                    process.waitUntilExit()
                    return CliInvocation(
                        exitCode: process.terminationStatus,
                        standardOutput: String(
                            decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                            as: UTF8.self,
                        ),
                        standardError: String(
                            decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
                            as: UTF8.self,
                        ),
                    )
                })
            }
        }
    }
}
