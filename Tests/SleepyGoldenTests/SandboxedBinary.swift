import Foundation

/// Runs the built `sleepy` under `sandbox-exec`, so a suite can prove what the
/// tool says when the environment is against it.
///
/// `sandbox-exec` is the only way to reproduce a WebKit launch denial
/// deliberately — the signal is a launch denial, not anything the code can
/// fake. ``webContentDenialProfile`` denies exactly one thing, so a pass
/// proves the message is tied to that denial and not to a generally crippled
/// process.
///
/// Deliberately separate from ``GoldenBinary``, which runs the binary
/// directly and has no notion of wrapping it.
enum SandboxedBinary {
    /// Denies the WebKit content process and nothing else.
    static let webContentDenialProfile: String = """
    (version 1)
    (allow default)
    (deny mach-lookup (global-name "com.apple.WebKit.WebContent"))
    """

    /// Whether this machine can run the sandboxed cases at all.
    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: executablePath)
    }

    private static let executablePath: String = "/usr/bin/sandbox-exec"

    /// Runs `sleepy arguments` under ``webContentDenialProfile``.
    ///
    /// - Parameters:
    ///   - arguments: the `sleepy` argument vector.
    ///   - environment: variables overlaid on the parent environment — how a
    ///     test points the subprocess at a throwaway `SLEEPYHOLLOW_HOME`.
    static func runDenyingWebContent(
        _ arguments: [String],
        environment: [String: String] = [:],
    ) async throws -> CliInvocation {
        let profileURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepy-deny-webcontent-\(UUID().uuidString).sb")
        try webContentDenialProfile.write(to: profileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: profileURL) }
        return try await run(profile: profileURL, arguments: arguments, environment: environment)
    }

    /// Runs the built `sleepy` under `profile`, off the cooperative pool.
    ///
    /// Mirrors ``GoldenBinary/runOffPool(_:environment:standardInput:)`` — the
    /// blocking wait stays off the cooperative pool — but wraps the binary
    /// rather than running it directly.
    static func run(
        profile: URL,
        arguments: [String],
        environment: [String: String] = [:],
    ) async throws -> CliInvocation {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(with: Result {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executablePath)
                    process.arguments = ["-f", profile.path]
                        + [GoldenBinary.productsDirectory().appendingPathComponent("sleepy").path]
                        + arguments
                    if !environment.isEmpty {
                        process.environment = ProcessInfo.processInfo.environment
                            .merging(environment) { _, new in new }
                    }
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
