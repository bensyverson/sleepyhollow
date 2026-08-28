import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// One name for "which element": `--selector` everywhere, with `--element`
/// accepted as an alias so an agent that learned either spelling lands.
///
/// `--budget 60000` throughout: see ``CaptureGoldenTests`` — WebKit contention
/// across parallel golden subprocesses pushes loads past the 30-second default.
@Suite(.serialized)
struct SelectorAliasGoldenTests {
    /// Runs `sleepy` against a throwaway registry root.
    private static func sleepy(_ arguments: [String], root: URL) async throws -> CliInvocation {
        try await GoldenBinary.runOffPool(
            arguments,
            environment: [SessionRegistry.homeEnvironmentVariable: root.path],
        )
    }

    // MARK: - shot

    @Test func `shot --selector and shot --element crop the same element`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-tall.html").absoluteString
            let directory = Self.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }

            let canonical = directory.appendingPathComponent("canonical.png")
            let aliased = directory.appendingPathComponent("aliased.png")

            let first = try await GoldenBinary.runOffPool([
                "shot", url, "--selector", "#target", "--budget", "60000", "--out", canonical.path,
            ])
            #expect(first.exitCode == 0, "stderr: \(first.standardError)")

            let second = try await GoldenBinary.runOffPool([
                "shot", url, "--element", "#target", "--budget", "60000", "--out", aliased.path,
            ])
            #expect(second.exitCode == 0, "stderr: \(second.standardError)")

            #expect(try Data(contentsOf: canonical) == Data(contentsOf: aliased))
        }
    }

    @Test func `shot's help names --selector and says --element is the same flag`() async throws {
        let result = try await GoldenBinary.runOffPool(["shot", "--help"])
        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("--selector"))
        #expect(result.standardOutput.contains("--element"))
    }

    // MARK: - The act verbs

    @Test func `click, fill and submit accept --element in a live session`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let root = try SessionHelperProcess.makeRoot()
            defer { SessionHelperProcess.reap(root) }
            let name: SessionName = try #require(SessionName("golden-alias"))
            let url = baseURL.appendingPathComponent("act-events.html").absoluteString

            let opened = try await Self.sleepy(
                ["open", url, "--name", name.rawValue, "--budget", "60000"],
                root: root,
            )
            #expect(opened.exitCode == 0, "stderr: \(opened.standardError)")

            let clicked = try await Self.sleepy(
                ["click", "--session", name.rawValue, "--element", "#go"],
                root: root,
            )
            #expect(clicked.exitCode == 0, "stderr: \(clicked.standardError)")

            let filled = try await Self.sleepy(
                ["fill", "--session", name.rawValue, "--element", "#title", "--value", "Hello"],
                root: root,
            )
            #expect(filled.exitCode == 0, "stderr: \(filled.standardError)")

            let submitted = try await Self.sleepy(
                ["submit", "--session", name.rawValue, "--element", "#local"],
                root: root,
            )
            #expect(submitted.exitCode == 0, "stderr: \(submitted.standardError)")

            _ = try await Self.sleepy(["close", name.rawValue], root: root)
        }
    }

    @Test func `--element and --at still name two ways to click, so both is a usage error`() async throws {
        let result = try await GoldenBinary.runOffPool([
            "click", "--session", "whatever", "--element", "#go", "--at", "620,180",
        ])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--selector"))
    }

    // MARK: - Helpers

    private static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
