import Foundation
import Testing
import TestSupport

/// `sleepy find` end to end: the exit code is the answer; matched/no match
/// text by default, a bare JSON boolean with --format json.
///
/// `.serialized`: see ``DomGoldenTests``'s discussion — bounds how many of
/// this suite's subprocess-spawning tests are ever in flight at once,
/// alongside the same concern in every other golden suite.
@Suite(.serialized)
struct FindGoldenTests {
    @Test func `a match exits 0 with a terse text body`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("static.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["find", url, "--text", "quick brown fox"])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput == "matched\n")
        }
    }

    @Test func `no match is a clean negative: exit 1`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("static.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["find", url, "--text", "nonexistent phrase"])
            #expect(result.exitCode == 1)
            #expect(result.standardOutput == "no match\n")
        }
    }

    @Test func `--format json emits a bare boolean`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("static.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["find", url, "--text", "quick brown fox", "--format", "json"])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput == "true")
        }
    }

    @Test func `--session with no such session is a teaching environment error`() async throws {
        let result = try await GoldenBinary.runOffPool(["find", "--session", "nope", "--text", "hello"])
        #expect(result.exitCode == 5)
        #expect(result.standardError.contains("session"))
    }
}
