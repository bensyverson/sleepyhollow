import Foundation
import Testing
import TestSupport

/// `--no-js` end to end: the page as a browser with JavaScript off renders it,
/// through the verbs an agent checks progressive enhancement with — and a
/// teaching refusal, exit 2, from each verb that cannot answer without the
/// page's scripts.
///
/// `no-js.html` enhances itself with script and keeps its fallback, CSS 3D
/// included, inside `<noscript>`.
@Suite(.serialized)
struct NoJSGoldenTests {
    private static let fixture = "no-js.html"

    @Test func `query sees the noscript fallback, visible`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.fixture).absoluteString
            let result = try await GoldenBinary.runOffPool([
                "query", url, "--selector", "#fallback", "--no-js", "--format", "text", "--budget", "60000",
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(result.standardOutput.contains("visible=true"), "\(result.standardOutput)")
        }
    }

    @Test func `a shot draws the fallback and keeps its 3D caveat`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.fixture).absoluteString
            let out: URL = FileManager.default.temporaryDirectory
                .appendingPathComponent("sleepy-no-js-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--no-js", "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(FileManager.default.fileExists(atPath: out.path))
            #expect(result.standardError.contains("draws CSS 3D flat"), "\(result.standardError)")
            #expect(result.standardError.contains("div#tilt"), "\(result.standardError)")
        }
    }

    @Test func `eval in its default page world refuses and names the isolated world`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.fixture).absoluteString
            let result = try await GoldenBinary.runOffPool(["eval", url, "--js", "document.title", "--no-js"])
            #expect(result.exitCode == 2, "stderr: \(result.standardError)")
            #expect(result.standardError.contains("--world isolated"), "\(result.standardError)")
        }
    }

    @Test func `eval in the isolated world reads the unscripted page`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.fixture).absoluteString
            let result = try await GoldenBinary.runOffPool([
                "eval", url, "--js", "document.title", "--no-js", "--world", "isolated", "--budget", "60000",
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(result.standardOutput.contains("Server title"), "\(result.standardOutput)")
        }
    }

    @Test func `console refuses`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.fixture).absoluteString
            let result = try await GoldenBinary.runOffPool(["console", url, "--no-js"])
            #expect(result.exitCode == 2, "stderr: \(result.standardError)")
            #expect(result.standardError.contains("no console to read"), "\(result.standardError)")
        }
    }

    @Test func `a js: wait refuses before the budget is spent`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.fixture).absoluteString
            let result = try await GoldenBinary.runOffPool([
                "query", url, "--selector", "p", "--no-js", "--wait-for", "js:true", "--budget", "60000",
            ])
            #expect(result.exitCode == 2, "stderr: \(result.standardError)")
            #expect(result.standardError.contains("--wait-for js:true"), "\(result.standardError)")
        }
    }
}
