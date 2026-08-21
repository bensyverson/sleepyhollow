import Foundation
import Testing
import TestSupport

/// `sleepy style` end to end: computed values for the first match, exit 1
/// as a clean negative when nothing matches.
///
/// `.serialized`: see ``DomGoldenTests``'s discussion — bounds how many of
/// this suite's subprocess-spawning tests are ever in flight at once,
/// alongside the same concern in every other golden suite.
@Suite(.serialized)
struct StyleGoldenTests {
    @Test func `default format is JSON computed values`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("theme.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["style", url, "--selector", "body", "--property", "display"])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("\"display\" : \"block\""))
            #expect(result.standardOutput.contains("\"matched\" : true"))
        }
    }

    @Test func `--format text renders one property colon value line each`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("theme.html").absoluteString
            let result = try await GoldenBinary.runOffPool([
                "style", url, "--selector", "body", "--property", "display", "--format", "text",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput == "display: block\n")
        }
    }

    @Test func `a selector matching nothing exits 1 as a clean negative`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("static.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["style", url, "--selector", "#nope", "--property", "display"])
            #expect(result.exitCode == 1)
            #expect(result.standardOutput.contains("\"matched\" : false"))
        }
    }

    @Test func `no --property is a teaching usage error`() async throws {
        let result = try await GoldenBinary.runOffPool(["style", "http://127.0.0.1:1/", "--selector", "body"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--property"))
    }

    @Test func `--session teaches that sessions are pending`() async throws {
        let result = try await GoldenBinary.runOffPool(["style", "--session", "nope", "--selector", "body", "--property", "display"])
        #expect(result.exitCode == 5)
        #expect(result.standardError.contains("session"))
    }
}
