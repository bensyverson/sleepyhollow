import Foundation
import Testing
import TestSupport

/// `sleepy dom` end to end: HTML by default, a typed tree with --format json.
///
/// `.serialized`: each test shells out to a real `sleepy` subprocess, and
/// this codebase's golden runner (``GoldenBinary``) waits on it with a
/// blocking `Process.waitUntilExit()`. Enough of those in flight at once
/// across the golden suites starves Swift Testing's cooperative thread pool
/// — observed as every concurrent golden test's page load missing its 30s
/// budget, `LoadGoldenTests` included, past roughly two dozen simultaneous
/// subprocesses. Serializing this suite keeps its contribution to that
/// count bounded; the actual fix (an async-friendly ``GoldenBinary``) is
/// outside this family's owned files — see the report.
@Suite(.serialized)
struct DomGoldenTests {
    @Test func `default format is HTML and contains the literal markup`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("static.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["dom", url])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.hasPrefix("<!DOCTYPE html>"))
            #expect(result.standardOutput.contains("Sleepy Hollow static fixture"))
            #expect(result.standardError.isEmpty)
        }
    }

    @Test func `--format json emits a decodable tree`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("static.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["dom", url, "--format", "json"])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("\"kind\""))
            #expect(result.standardOutput.contains("\"tag\" : \"html\""))
        }
    }

    @Test func `an unsupported format is a teaching usage error`() async throws {
        let result = try await GoldenBinary.runOffPool(["dom", "http://127.0.0.1:1/", "--format", "text"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("dom"))
    }

    @Test func `--session with no such session is a teaching environment error`() async throws {
        let result = try await GoldenBinary.runOffPool(["dom", "--session", "nope"])
        #expect(result.exitCode == 5)
        #expect(result.standardError.contains("session"))
    }
}
