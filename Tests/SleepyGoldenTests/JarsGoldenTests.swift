import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `sleepy jars` end to end, plus the two claims that define jars: a jar
/// minted by one invocation authenticates a later unrelated one, and a bare
/// invocation writes nothing under `~/.sleepyhollow`.
///
/// `.serialized`: the same subprocess-contention concern as every other golden
/// suite — see ``DomGoldenTests``.
@Suite(.serialized)
struct JarsGoldenTests {
    /// A throwaway `SLEEPYHOLLOW_HOME` for one test's subprocesses.
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

    /// Mints a one-cookie jar without starting a browser.
    ///
    /// The management verbs are about the jar *file*, not about where its
    /// cookies came from, and a headless `WKWebView` per test is the suite's
    /// scarcest resource — every golden test that spawns one makes the
    /// wall-clock budgets in other suites tighter (see project/gotchas.md).
    /// Minting from a real page is proved once, by the flagship test.
    @discardableResult
    private func mint(_ jar: String, in root: URL) async throws -> CliInvocation {
        try await GoldenBinary.runOffPool(
            ["cookies", "set", "--jar", jar, "--name", "sleepy", "--value", "hollow", "--domain", "127.0.0.1"],
            environment: environment(root),
        )
    }

    // MARK: - The flagship

    @Test func `a jar minted by one invocation authenticates a later unrelated invocation`() async throws {
        try await withRoot { root in
            try await FixtureServer.withRunning { _, baseURL in
                let minting = try await GoldenBinary.runOffPool(
                    ["load", baseURL.appendingPathComponent("cookie").absoluteString, "--jar", "login"] + budget,
                    environment: environment(root),
                )
                #expect(minting.exitCode == 0)

                let reusing = try await GoldenBinary.runOffPool(
                    [
                        "query",
                        baseURL.appendingPathComponent("echo-cookie").absoluteString,
                        "--selector", "#sent",
                        "--jar", "login",
                        "--format", "text",
                    ] + budget,
                    environment: environment(root),
                )
                #expect(reusing.exitCode == 0)
                #expect(reusing.standardOutput.contains("sleepy=hollow"))
            }
        }
    }

    @Test func `a bare invocation writes nothing under the home directory`() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sj\(String(UInt32.random(in: 0 ..< UInt32.max), radix: 16))")
        defer { try? FileManager.default.removeItem(at: root) }
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool(
                ["load", baseURL.appendingPathComponent("cookie").absoluteString] + budget,
                environment: environment(root),
            )
            #expect(result.exitCode == 0)
            #expect(!FileManager.default.fileExists(atPath: root.path))
        }
    }

    // MARK: - list

    @Test func `list reports each jar with its cookie count`() async throws {
        try await withRoot { root in
            try await mint("login", in: root)
            let listed = try await GoldenBinary.runOffPool(["jars", "list"], environment: environment(root))
            #expect(listed.exitCode == 0)
            #expect(listed.standardOutput.contains("login"))
            #expect(listed.standardOutput.contains("1 cookie"))
        }
    }

    @Test func `list --format json reports the summaries structurally`() async throws {
        try await withRoot { root in
            try await mint("login", in: root)
            let listed = try await GoldenBinary.runOffPool(
                ["jars", "list", "--format", "json"],
                environment: environment(root),
            )
            #expect(listed.exitCode == 0)
            #expect(listed.standardOutput.contains("\"name\" : \"login\""))
            #expect(listed.standardOutput.contains("\"cookieCount\" : 1"))
        }
    }

    @Test func `list on an untouched home reports no jars and exits 0`() async throws {
        try await withRoot { root in
            let listed = try await GoldenBinary.runOffPool(["jars", "list"], environment: environment(root))
            #expect(listed.exitCode == 0)
            #expect(listed.standardOutput.isEmpty)
        }
    }

    @Test func `bare jars lists, so the management verb needs no subcommand`() async throws {
        try await withRoot { root in
            let listed = try await GoldenBinary.runOffPool(["jars"], environment: environment(root))
            #expect(listed.exitCode == 0)
        }
    }

    // MARK: - clear and rm

    @Test func `clear empties a jar's cookies and keeps the jar`() async throws {
        try await withRoot { root in
            try await mint("login", in: root)
            let cleared = try await GoldenBinary.runOffPool(["jars", "clear", "login"], environment: environment(root))
            #expect(cleared.exitCode == 0)
            let listed = try await GoldenBinary.runOffPool(["jars", "list"], environment: environment(root))
            #expect(listed.standardOutput.contains("login"))
            #expect(listed.standardOutput.contains("0 cookies"))
        }
    }

    @Test func `a cleared jar no longer authenticates`() async throws {
        try await withRoot { root in
            try await FixtureServer.withRunning { _, baseURL in
                try await mint("login", in: root)
                _ = try await GoldenBinary.runOffPool(["jars", "clear", "login"], environment: environment(root))
                let reusing = try await GoldenBinary.runOffPool(
                    [
                        "query",
                        baseURL.appendingPathComponent("echo-cookie").absoluteString,
                        "--selector", "#sent",
                        "--jar", "login",
                        "--format", "text",
                    ] + budget,
                    environment: environment(root),
                )
                #expect(!reusing.standardOutput.contains("sleepy=hollow"))
            }
        }
    }

    @Test func `rm deletes the jar entirely`() async throws {
        try await withRoot { root in
            try await mint("login", in: root)
            let removed = try await GoldenBinary.runOffPool(["jars", "rm", "login"], environment: environment(root))
            #expect(removed.exitCode == 0)
            let listed = try await GoldenBinary.runOffPool(["jars", "list"], environment: environment(root))
            #expect(listed.standardOutput.isEmpty)
        }
    }

    @Test func `clearing an unknown jar exits 5 and teaches list`() async throws {
        try await withRoot { root in
            let result = try await GoldenBinary.runOffPool(["jars", "clear", "nope"], environment: environment(root))
            #expect(result.exitCode == 5)
            #expect(result.standardError.contains("sleepy jars list"))
        }
    }

    @Test func `removing an unknown jar exits 5`() async throws {
        try await withRoot { root in
            let result = try await GoldenBinary.runOffPool(["jars", "rm", "nope"], environment: environment(root))
            #expect(result.exitCode == 5)
        }
    }

    @Test func `an unsafe jar name is refused as a usage error`() async throws {
        try await withRoot { root in
            let result = try await GoldenBinary.runOffPool(["jars", "rm", "../escape"], environment: environment(root))
            #expect(result.exitCode == 2)
        }
    }
}
