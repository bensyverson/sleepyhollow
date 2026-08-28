import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `sleepy open` invoked the way it is actually installed: a bare command name
/// found on `$PATH`, from a working directory that has nothing to do with the
/// binary.
///
/// The regression this guards: the launcher used to build the helper's path
/// from `CommandLine.arguments[0]`, which is just `sleepy` under a `$PATH`
/// lookup, and resolved it against the current directory — so `open` died with
/// "Couldn't start a session helper from '<cwd>/sleepy'". Nothing short of a
/// subprocess whose argv[0] really is `sleepy` can prove that fixed, which is
/// why this goes through `/usr/bin/env`: it performs the `$PATH` lookup and
/// execs with argv[0] set to the bare name, exactly as a shell does.
///
/// `--budget 60000` per the golden-suite gotcha, and the load runs inside
/// ``FixtureServer/withRunning(_:)`` so it stays under ``WebKitGate``.
@Suite(.serialized)
struct SessionLauncherPathGoldenTests {
    /// The `$PATH`-searching exec wrapper every shell effectively uses.
    private static let pathSearchingExec = URL(fileURLWithPath: "/usr/bin/env")

    /// Runs `sleepy <arguments>` as a bare command name, from `cwd`, with the
    /// built binary's directory prepended to `$PATH`.
    private static func sleepyViaPath(
        _ arguments: [String],
        cwd: URL,
        root: URL,
    ) async throws -> CliInvocation {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(with: Result { try runViaPath(arguments, cwd: cwd, root: root) })
            }
        }
    }

    private static func runViaPath(_ arguments: [String], cwd: URL, root: URL) throws -> CliInvocation {
        let process = Process()
        process.executableURL = pathSearchingExec
        process.arguments = ["sleepy"] + arguments
        process.currentDirectoryURL = cwd

        var environment: [String: String] = ProcessInfo.processInfo.environment
        let products: String = GoldenBinary.productsDirectory().path
        environment["PATH"] = ([products] + [environment["PATH"] ?? ""]).joined(separator: ":")
        environment[SessionRegistry.homeEnvironmentVariable] = root.path
        process.environment = environment

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        return CliInvocation(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            standardError: String(decoding: standardError.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        )
    }

    @Test func `open works as a bare PATH command from a foreign working directory`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let root = try SessionHelperProcess.makeRoot()
            defer { SessionHelperProcess.reap(root) }
            let name: SessionName = try #require(SessionName("golden-path"))
            let url = baseURL.appendingPathComponent(FixturePage.staticText.fileName).absoluteString

            // A cwd that holds no `sleepy`: the old resolution invented one here.
            let foreign = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let opened = try await Self.sleepyViaPath(
                ["open", url, "--name", name.rawValue, "--budget", "60000"],
                cwd: foreign,
                root: root,
            )

            #expect(
                !opened.standardError.contains("Couldn't start a session helper"),
                "the helper must be found from the running image, not the working directory: \(opened.standardError)",
            )
            #expect(opened.exitCode == 0, "\(opened.standardError)")
            #expect(opened.standardOutput.contains("\"httpStatus\""))

            let registry = SessionRegistry(root: root)
            #expect(registry.liveness(of: name) == .live)

            let closed = try await GoldenBinary.runOffPool(
                ["close", name.rawValue],
                environment: [SessionRegistry.homeEnvironmentVariable: root.path],
            )
            #expect(closed.exitCode == 0, "\(closed.standardError)")
        }
    }
}
