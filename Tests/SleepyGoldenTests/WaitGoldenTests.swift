import Foundation
import Testing
import TestSupport

/// `sleepy load --wait-for` end to end: the flag an agent actually types,
/// through `LoadFlagOptions` into the host's load pipeline.
struct WaitGoldenTests {
    @Test func `--wait-for a late selector holds the load until it appears, exit 0`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("wait-late.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["load", url, "--wait-for", "#late"])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("200"))
            #expect(result.standardError.isEmpty)
        }
    }

    @Test func `--wait-for a selector that never matches exits 3 inside the budget`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("static.html").absoluteString
            let started = Date()
            let result = try await GoldenBinary.runOffPool(["load", url, "--wait-for", "#never-in-this-page", "--budget", "1000"])
            #expect(result.exitCode == 3)
            #expect(result.standardError.contains("#never-in-this-page"))
            #expect(Date().timeIntervalSince(started) < 10)
        }
    }

    @Test func `--wait-for a js predicate reads the page's own world`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("wait-late.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["load", url, "--wait-for", "js:window.sleepyReady === true"])
            #expect(result.exitCode == 0)
            #expect(result.standardError.isEmpty)
        }
    }

    @Test func `--wait-for idle settles a quiet page, exit 0`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("static.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["load", url, "--wait-for", "idle"])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("200"))
        }
    }
}
