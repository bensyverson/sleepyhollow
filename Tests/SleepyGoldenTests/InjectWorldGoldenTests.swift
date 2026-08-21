import Foundation
import Testing
import TestSupport

/// `--inject-world` end to end: a user script really does reach the page's own
/// globals when asked to, and really cannot when it isn't.
///
/// `inject-order.html` is the honest witness — its *first* inline script copies
/// `window.__injectedMarker` into a paragraph, so what the page sees is what
/// the injected script actually put where the page could find it.
///
/// `.serialized` and `--budget 60000`: see ``CaptureGoldenTests`` — WebKit
/// contention across parallel golden subprocesses pushes loads past the
/// 30-second default.
@Suite(.serialized)
struct InjectWorldGoldenTests {
    /// The marker the injected script leaves on `window`.
    private static let marker: String = "seen-by-the-page"

    /// Writes the injecting script to a throwaway file.
    private func scriptFile() throws -> URL {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".js")
        try "window.__injectedMarker = '\(Self.marker)';".write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    @Test func `--inject-world page lets the page's own script see the marker`() async throws {
        let script: URL = try scriptFile()
        defer { try? FileManager.default.removeItem(at: script) }

        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "query", baseURL.appendingPathComponent("inject-order.html").absoluteString,
                "--selector", "#marker", "--format", "text",
                "--inject", script.path, "--inject-world", "page",
                "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains(Self.marker))
        }
    }

    @Test func `the isolated world is the default, and the page cannot see it`() async throws {
        let script: URL = try scriptFile()
        defer { try? FileManager.default.removeItem(at: script) }

        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "query", baseURL.appendingPathComponent("inject-order.html").absoluteString,
                "--selector", "#marker", "--format", "text",
                "--inject", script.path,
                "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(!result.standardOutput.contains(Self.marker))
            #expect(result.standardOutput.contains("undefined"))
        }
    }

    @Test func `--inject-world isolated is the default spelled out`() async throws {
        let script: URL = try scriptFile()
        defer { try? FileManager.default.removeItem(at: script) }

        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "query", baseURL.appendingPathComponent("inject-order.html").absoluteString,
                "--selector", "#marker", "--format", "text",
                "--inject", script.path, "--inject-world", "isolated",
                "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("undefined"))
        }
    }

    @Test func `a world this tool has no name for is a usage error that lists the two`() async throws {
        let result = try await GoldenBinary.runOffPool([
            "dom", "http://example.com/", "--inject-world", "martian",
        ])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("isolated"))
        #expect(result.standardError.contains("page"))
    }

    @Test func `--inject-world against a session is refused, naming sleepy open`() async throws {
        let result = try await GoldenBinary.runOffPool([
            "dom", "--session", "nope", "--inject-world", "page",
        ])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--inject-world"))
        #expect(result.standardError.contains("sleepy open"))
    }
}
