import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `sleepy doctor` end to end, in both of the environments it exists to tell
/// apart: a healthy one, and one where WebKit's content process is denied.
///
/// The healthy run goes through ``FixtureServer/withRunning(fixturesDirectory:_:)``
/// even though `about:blank` needs no server — the `WebKitGate` cap it takes
/// is what keeps concurrent WebKit instances bounded (see project/gotchas.md).
///
/// `--budget 60000`: WebKit contention pushes golden subprocesses past the
/// 30-second default.
@Suite(.serialized)
struct DoctorGoldenTests {
    /// A throwaway registry root, short enough to leave room for a socket path.
    private static func makeRoot() throws -> URL {
        try SessionHelperProcess.makeRoot()
    }

    private static func environment(_ root: URL) -> [String: String] {
        [SessionRegistry.homeEnvironmentVariable: root.path]
    }

    private static func decode(_ run: CliInvocation) throws -> DoctorReport {
        try JSONDecoder().decode(DoctorReport.self, from: Data(run.standardOutput.utf8))
    }

    // MARK: - Healthy

    @Test
    func `a healthy environment reports every check ok and exits zero`() async throws {
        let root: URL = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try await FixtureServer.withRunning { _, _ in
            let run: CliInvocation = try await GoldenBinary.runOffPool(
                ["doctor", "--budget", "60000"],
                environment: Self.environment(root),
            )
            #expect(run.exitCode == 0)
            #expect(run.standardError.isEmpty)
            let report: DoctorReport = try Self.decode(run)
            #expect(report.status == .ok)
            #expect(report.checks.map(\.name) == [.binary, .webKit, .sessions, .temporaryDirectory])
            #expect(report.checks.allSatisfy { $0.status == .ok && $0.nextMove == nil })
        }
    }

    @Test
    func `the text format lists one line per check`() async throws {
        let root: URL = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try await FixtureServer.withRunning { _, _ in
            let run: CliInvocation = try await GoldenBinary.runOffPool(
                ["doctor", "--format", "text", "--budget", "60000"],
                environment: Self.environment(root),
            )
            #expect(run.exitCode == 0)
            let lines: [String] = run.standardOutput.split(separator: "\n").map(String.init)
            #expect(lines.count == 4)
            #expect(lines.allSatisfy { $0.hasPrefix("ok") })
            #expect(lines[1].contains("webkit"))
        }
    }

    // MARK: - Denied

    @Test
    func `a sandbox that blocks WebKit exits 5 naming the sandbox and the next move`() async throws {
        try #require(SandboxedBinary.isAvailable, "sandbox-exec is how this failure is reproduced")
        let root: URL = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let run: CliInvocation = try await SandboxedBinary.runDenyingWebContent(
            ["doctor", "--budget", "60000"],
            environment: Self.environment(root),
        )
        #expect(run.exitCode == ExitStatus.environment.rawValue)
        #expect(run.standardError.contains("WebKit could not start under this sandbox"))
        #expect(run.standardError.contains("dangerouslyDisableSandbox"))
        #expect(!run.standardError.contains("did not finish loading"))

        // The denial is pinned to WebKit: everything else in the environment
        // still checks out, which is what makes the diagnosis worth reading.
        let report: DoctorReport = try Self.decode(run)
        #expect(report.status == .failed)
        #expect(report.firstFailure?.name == .webKit)
        #expect(report.checks.filter { $0.name != .webKit }.allSatisfy { $0.status == .ok })
    }
}
