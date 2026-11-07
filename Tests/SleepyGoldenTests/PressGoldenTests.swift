import Foundation
import SleepyHollow
import Testing
import TestSupport

/// `sleepy press` and the `--focus`/`--type`/`--press` steps end to end:
/// real keystrokes in a session and in one shot, and the teaching refusals
/// (leaf `XerXuw`).
@Suite(.serialized)
struct PressGoldenTests {
    private static func sleepy(_ arguments: [String], root: URL) async throws -> CliInvocation {
        try await GoldenBinary.runOffPool(
            arguments,
            environment: [SessionRegistry.homeEnvironmentVariable: root.path],
        )
    }

    @Test func `press without --session teaches the session and the one-shot steps`() async throws {
        let result = try await GoldenBinary.runOffPool(["press", "Enter"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--session"))
        #expect(result.standardError.contains("--press"))
    }

    @Test func `press given a URL teaches the one-shot steps instead`() async throws {
        let result = try await GoldenBinary.runOffPool(["press", "http://example.com", "Enter"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--type"))
    }

    @Test func `an unknown key name is a usage error that names the right spelling`() async throws {
        let result = try await GoldenBinary.runOffPool(["press", "--session", "nobody", "enter"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("Enter"))
    }

    @Test func `a one-shot flow types, presses Enter, and reads the submitted page`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let page = baseURL.appendingPathComponent("press-keys.html").absoluteString
            let result = try await GoldenBinary.runOffPool([
                "eval", page,
                "--focus", "#name",
                "--type", "Hollow",
                "--press", "Enter",
                "--js", "return location.search;",
                "--budget", "60000",
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            // The submitted page is a fresh copy of the form; its URL holds
            // what was typed.
            #expect(result.standardOutput.contains("?name=Hollow"))
        }
    }

    @Test func `press runs in a live session, as trusted keys`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let root = try SessionHelperProcess.makeRoot()
            defer { SessionHelperProcess.reap(root) }
            let name: SessionName = try #require(SessionName("golden-press"))
            let url = baseURL.appendingPathComponent("press-keys.html").absoluteString

            #expect(try await Self.sleepy(
                ["open", url, "--name", name.rawValue, "--budget", "60000"],
                root: root,
            ).exitCode == 0)

            let pressed = try await Self.sleepy(
                ["press", "--session", name.rawValue, "--selector", "#name", "--text", "Hollow", "Tab"],
                root: root,
            )
            #expect(pressed.exitCode == 0, "stderr: \(pressed.standardError)")
            #expect(pressed.standardOutput.contains("\"action\" : \"press\""))
            #expect(pressed.standardOutput.contains("\"tagName\" : \"input\""))

            let read = try await Self.sleepy(
                [
                    "eval", "--session", name.rawValue, "--js",
                    "const f = window.keyFacts(); return [f.name, f.active, f.log.every((e) => e.isTrusted)].join('|');",
                ],
                root: root,
            )
            #expect(read.exitCode == 0)
            #expect(read.standardOutput.contains("Hollow|second|true"))

            _ = try await Self.sleepy(["close", name.rawValue], root: root)
        }
    }
}
