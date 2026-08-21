import Foundation
import Testing
import TestSupport

/// `sleepy eval` end to end: JSON on stdout, the world flag, page failures as
/// teaching errors, and `false` as the clean-negative exit.
///
/// `.serialized` and `--budget 60000`: see ``CaptureGoldenTests`` — WebKit
/// contention across parallel golden subprocesses pushes loads past the
/// 30-second default.
@Suite(.serialized)
struct EvalGoldenTests {
    private func url(_ page: String, _ baseURL: URL) -> String {
        baseURL.appendingPathComponent(page).absoluteString
    }

    @Test func `a result is printed as JSON, exit 0`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "eval", url("static.html", baseURL), "--js", "return 1 + 1;", "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "2")
        }
    }

    @Test func `await and --args compose into one answer`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "eval", url("static.html", baseURL),
                "--js", "return await Promise.resolve(factor * 6);",
                "--args", #"{"factor": 7}"#,
                "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "42")
        }
    }

    @Test func `the isolated world is the default and --page-world opts out of it`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let page = url("eval-world.html", baseURL)
            let isolated = try await GoldenBinary.runOffPool([
                "eval", page, "--js", "return window.sleepyPageValue ?? null;", "--budget", "60000",
            ])
            #expect(isolated.exitCode == 0)
            #expect(isolated.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "null")

            let shared = try await GoldenBinary.runOffPool([
                "eval", page, "--js", "return window.sleepyPageValue ?? null;", "--page-world", "--budget", "60000",
            ])
            #expect(shared.exitCode == 0)
            #expect(shared.standardOutput.contains("page-world"))
        }
    }

    @Test func `--format text unwraps a string result`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "eval", url("static.html", baseURL),
                "--js", "return document.title;", "--format", "text", "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(!result.standardOutput.contains("\""))
        }
    }

    @Test func `a false result is a clean negative`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "eval", url("static.html", baseURL),
                "--js", "return document.querySelectorAll('h9').length > 0;", "--budget", "60000",
            ])
            #expect(result.exitCode == 1)
            #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "false")
        }
    }

    @Test func `a page error exits 2 with the page's own message, not a stack trace`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "eval", url("static.html", baseURL), "--js", "throw new Error('boom');", "--budget", "60000",
            ])
            #expect(result.exitCode == 2)
            #expect(result.standardError.contains("boom"))
            #expect(!result.standardError.contains("Error Domain="))
        }
    }

    @Test func `--js is required`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool(["eval", url("static.html", baseURL)])
            #expect(result.exitCode == 2)
        }
    }

    @Test func `--session teaches that sessions are pending`() async throws {
        let result = try await GoldenBinary.runOffPool(["eval", "--session", "nope", "--js", "return 1;"])
        #expect(result.exitCode == 5)
        #expect(result.standardError.contains("session"))
    }
}
