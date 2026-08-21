import Foundation
import Testing
import TestSupport

/// `sleepy load` end to end: the base loading verb against real fixtures.
struct LoadGoldenTests {
    @Test func `load reports facts as JSON and exits 0`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("static.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["load", url])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("\"httpStatus\""))
            #expect(result.standardOutput.contains("200"))
            #expect(result.standardOutput.contains("static.html"))
            #expect(result.standardError.isEmpty)
        }
    }

    @Test func `a 404 still loads — status in the facts, exit 0`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("missing.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["load", url])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("404"))
        }
    }

    @Test func `an unreachable host exits 4 with teaching text`() async throws {
        let result = try await GoldenBinary.runOffPool(["load", "http://127.0.0.1:9/"])
        #expect(result.exitCode == 4)
        #expect(!result.standardError.isEmpty)
        #expect(result.standardOutput.isEmpty)
    }

    @Test func `--session with no such session is a teaching environment error`() async throws {
        let result = try await GoldenBinary.runOffPool(["load", "--session", "nope"])
        #expect(result.exitCode == 5)
        #expect(result.standardError.contains("session"))
    }
}
