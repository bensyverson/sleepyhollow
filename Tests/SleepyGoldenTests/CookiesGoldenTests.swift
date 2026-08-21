import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `sleepy cookies get|set` end to end: against a named jar with no page at
/// all, and against a URL's live store.
///
/// `.serialized`: the same subprocess-contention concern as every other golden
/// suite — see ``DomGoldenTests``.
@Suite(.serialized)
struct CookiesGoldenTests {
    private func environment(_ root: URL) -> [String: String] {
        [SessionRegistry.homeEnvironmentVariable: root.path]
    }

    /// `--budget 60000`: WebKit contention pushes golden subprocesses past the
    /// 30s default (see project/gotchas.md).
    private let budget: [String] = ["--budget", "60000"]

    private func withRoot(_ body: (URL) async throws -> Void) async throws {
        let root: URL = try SessionHelperProcess.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }

    // MARK: - Against a jar, with no page

    @Test func `set writes a cookie into a jar the naming created`() async throws {
        try await withRoot { root in
            let written = try await GoldenBinary.runOffPool(
                ["cookies", "set", "--jar", "hand", "--name", "sid", "--value", "abc123", "--domain", "127.0.0.1"],
                environment: environment(root),
            )
            #expect(written.exitCode == 0)
            #expect(written.standardOutput.contains("sid=abc123"))

            let read = try await GoldenBinary.runOffPool(
                ["cookies", "get", "--jar", "hand"],
                environment: environment(root),
            )
            #expect(read.exitCode == 0)
            #expect(read.standardOutput.contains("sid=abc123"))
            #expect(read.standardOutput.contains("Domain=127.0.0.1"))
        }
    }

    @Test func `a hand-written jar authenticates a real load`() async throws {
        try await withRoot { root in
            try await FixtureServer.withRunning { _, baseURL in
                _ = try await GoldenBinary.runOffPool(
                    ["cookies", "set", "--jar", "hand", "--name", "sid", "--value", "abc123", "--domain", "127.0.0.1"],
                    environment: environment(root),
                )
                let reusing = try await GoldenBinary.runOffPool(
                    [
                        "query",
                        baseURL.appendingPathComponent("echo-cookie").absoluteString,
                        "--selector", "#sent",
                        "--jar", "hand",
                        "--format", "text",
                    ] + budget,
                    environment: environment(root),
                )
                #expect(reusing.exitCode == 0)
                #expect(reusing.standardOutput.contains("sid=abc123"))
            }
        }
    }

    @Test func `set replaces a cookie of the same name, domain and path`() async throws {
        try await withRoot { root in
            let arguments: [String] = ["cookies", "set", "--jar", "hand", "--name", "sid", "--domain", "127.0.0.1"]
            _ = try await GoldenBinary.runOffPool(arguments + ["--value", "first"], environment: environment(root))
            _ = try await GoldenBinary.runOffPool(arguments + ["--value", "second"], environment: environment(root))
            let read = try await GoldenBinary.runOffPool(
                ["cookies", "get", "--jar", "hand"],
                environment: environment(root),
            )
            #expect(read.standardOutput.contains("sid=second"))
            #expect(!read.standardOutput.contains("sid=first"))
        }
    }

    @Test func `get --name filters to one cookie`() async throws {
        try await withRoot { root in
            for name in ["sid", "csrf"] {
                _ = try await GoldenBinary.runOffPool(
                    ["cookies", "set", "--jar", "hand", "--name", name, "--value", "v", "--domain", "127.0.0.1"],
                    environment: environment(root),
                )
            }
            let read = try await GoldenBinary.runOffPool(
                ["cookies", "get", "--jar", "hand", "--name", "csrf", "--format", "json"],
                environment: environment(root),
            )
            #expect(read.standardOutput.contains("\"name\" : \"csrf\""))
            #expect(!read.standardOutput.contains("\"name\" : \"sid\""))
        }
    }

    @Test func `get on an unknown jar exits 5 and teaches list`() async throws {
        try await withRoot { root in
            let read = try await GoldenBinary.runOffPool(["cookies", "get", "--jar", "nope"], environment: environment(root))
            #expect(read.exitCode == 5)
            #expect(read.standardError.contains("sleepy jars list"))
        }
    }

    @Test func `naming neither a page nor a jar is a usage error that teaches both`() async throws {
        try await withRoot { root in
            let read = try await GoldenBinary.runOffPool(["cookies", "get"], environment: environment(root))
            #expect(read.exitCode == 2)
            #expect(read.standardError.contains("--jar"))
        }
    }

    @Test func `set with no page needs a domain to attach the cookie to`() async throws {
        try await withRoot { root in
            let written = try await GoldenBinary.runOffPool(
                ["cookies", "set", "--jar", "hand", "--name", "sid", "--value", "abc"],
                environment: environment(root),
            )
            #expect(written.exitCode == 2)
            #expect(written.standardError.contains("--domain"))
        }
    }

    // MARK: - Against a URL's live store

    @Test func `get against a URL reports what the page was served`() async throws {
        try await withRoot { root in
            try await FixtureServer.withRunning { _, baseURL in
                let read = try await GoldenBinary.runOffPool(
                    ["cookies", "get", baseURL.appendingPathComponent("cookie").absoluteString] + budget,
                    environment: environment(root),
                )
                #expect(read.exitCode == 0)
                #expect(read.standardOutput.contains("sleepy=hollow"))
            }
        }
    }

    @Test func `set against a URL with a jar persists into the jar`() async throws {
        try await withRoot { root in
            try await FixtureServer.withRunning { _, baseURL in
                let written = try await GoldenBinary.runOffPool(
                    [
                        "cookies", "set",
                        baseURL.appendingPathComponent("static.html").absoluteString,
                        "--jar", "live",
                        "--name", "sid", "--value", "from-page",
                    ] + budget,
                    environment: environment(root),
                )
                #expect(written.exitCode == 0)
                let read = try await GoldenBinary.runOffPool(
                    ["cookies", "get", "--jar", "live"],
                    environment: environment(root),
                )
                #expect(read.standardOutput.contains("sid=from-page"))
                #expect(read.standardOutput.contains("Domain=127.0.0.1"))
            }
        }
    }

    @Test func `--session with no such session is a teaching environment error`() async throws {
        let result = try await GoldenBinary.runOffPool(["cookies", "get", "--session", "nope"])
        #expect(result.exitCode == 5)
        #expect(result.standardError.contains("session"))
    }
}
