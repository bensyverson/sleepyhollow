import Foundation
import Testing
import TestSupport

/// `sleepy query` end to end: matched-element facts, and --exists/--count
/// carrying the assertion in the exit code.
///
/// `.serialized`: see ``DomGoldenTests``'s discussion — bounds how many of
/// this suite's subprocess-spawning tests are ever in flight at once,
/// alongside the same concern in every other golden suite.
@Suite(.serialized)
struct QueryGoldenTests {
    @Test func `default format is JSON facts, exit 0 regardless of match count`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("form.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["query", url, "--selector", "#publish"])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("\"tagName\" : \"button\""))
            #expect(result.standardOutput.contains("\"disabled\" : \"\""))
        }
    }

    @Test func `--format text renders one terse line per element`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("form.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["query", url, "--selector", "#publish", "--format", "text"])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("button \"Publish\" visible=true"))
        }
    }

    @Test func `--exists exits 0 when a match exists`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("form.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["query", url, "--selector", "#publish", "--exists"])
            #expect(result.exitCode == 0)
        }
    }

    @Test func `--exists exits 1 as a clean negative when nothing matches`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("form.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["query", url, "--selector", "#does-not-exist", "--exists"])
            #expect(result.exitCode == 1)
            #expect(result.standardOutput == "[\n\n]")
        }
    }

    @Test func `--count exits 0 when the count matches`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("dom-hidden.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["query", url, "--selector", "p", "--count", "5"])
            #expect(result.exitCode == 0)
        }
    }

    @Test func `--count exits 1 on a mismatch`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("dom-hidden.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["query", url, "--selector", "p", "--count", "1"])
            #expect(result.exitCode == 1)
        }
    }

    @Test func `--session with no such session is a teaching environment error`() async throws {
        let result = try await GoldenBinary.runOffPool(["query", "--session", "nope", "--selector", "p"])
        #expect(result.exitCode == 5)
        #expect(result.standardError.contains("session"))
    }
}
