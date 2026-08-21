import Foundation
import Testing
import TestSupport

/// The vision's promise that `load` "surfaces console errors on stderr for
/// one-shot loads", proved end to end.
///
/// The note is *additive*: stdout stays the same JSON facts byte for byte, so
/// a pipeline that parses stdout never sees it and an agent watching a
/// terminal cannot miss it.
///
/// `.serialized` and `--budget 60000`: see ``CaptureGoldenTests`` — WebKit
/// contention across parallel golden subprocesses pushes loads past the
/// 30-second default.
@Suite(.serialized)
struct LoadConsoleNoticeGoldenTests {
    @Test func `a page that logged errors says so on stderr`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "load", baseURL.appendingPathComponent("console-errors.html").absoluteString,
                "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardError.contains("console error"))
        }
    }

    @Test func `the note teaches the verb that shows the errors`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "load", baseURL.appendingPathComponent("console-errors.html").absoluteString,
                "--budget", "60000",
            ])
            #expect(result.standardError.contains("sleepy console"))
        }
    }

    @Test func `the note is one line, and stdout still carries the facts alone`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "load", baseURL.appendingPathComponent("console-errors.html").absoluteString,
                "--budget", "60000",
            ])
            let lines: [Substring] = result.standardError.split(separator: "\n")
            #expect(lines.count == 1)
            #expect(result.standardOutput.contains("\"consoleErrorCount\""))
            #expect(!result.standardOutput.contains("sleepy console"))
        }
    }

    @Test func `a quiet page says nothing on stderr`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "load", baseURL.appendingPathComponent("static.html").absoluteString,
                "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardError.isEmpty)
        }
    }

    @Test func `--out keeps the note on stderr, where a redirect can't swallow it`() async throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: destination) }

        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "load", baseURL.appendingPathComponent("console-errors.html").absoluteString,
                "--out", destination.path, "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardError.contains("console error"))
        }
    }
}
