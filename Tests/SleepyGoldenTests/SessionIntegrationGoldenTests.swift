import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// The convergence proof: every 1.0 page verb answers against a live
/// `--session`, the canonical multi-step flow holds end to end, and state a
/// session gained persists to its jar.
///
/// One helper serves a whole test — the point is the seam, not helper
/// spawning, and a `WKWebView` per subprocess is the suite's scarcest
/// resource. `--budget 60000` on loading invocations, per the gotcha.
@Suite(.serialized)
struct SessionIntegrationGoldenTests {
    /// Runs `sleepy` against a throwaway registry root.
    private static func sleepy(_ arguments: [String], root: URL) async throws -> CliInvocation {
        try await GoldenBinary.runOffPool(
            arguments,
            environment: [SessionRegistry.homeEnvironmentVariable: root.path],
        )
    }

    /// Retries a read until `predicate` accepts it — a click that navigates
    /// races any single read, and the page itself is the only honest clock.
    private static func poll(
        every interval: TimeInterval = 0.2,
        upTo ceiling: TimeInterval = 15,
        _ read: () async throws -> CliInvocation,
        until predicate: (CliInvocation) -> Bool,
    ) async throws -> CliInvocation {
        let deadline = Date().addingTimeInterval(ceiling)
        var last: CliInvocation = try await read()
        while !predicate(last), Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            last = try await read()
        }
        return last
    }

    @Test func `every page verb answers against a live session`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let root = try SessionHelperProcess.makeRoot()
            defer { SessionHelperProcess.reap(root) }
            let name = "matrix"
            let url = baseURL.appendingPathComponent(FixturePage.form.fileName).absoluteString

            // --record-wire at open: `wire --session` needs the recorder to
            // exist before the load, and refuses (teaching `open`) otherwise.
            let opened = try await Self.sleepy(
                ["open", url, "--name", name, "--record-wire", "--budget", "60000"],
                root: root,
            )
            #expect(opened.exitCode == 0)

            // Reads first — each verb's core answer, from the same live page.
            let reads: [(arguments: [String], expected: String)] = [
                (["dom", "--session", name], "<form"),
                (["query", "--session", name, "--selector", "#title"], "\"tagName\""),
                (["style", "--session", name, "--selector", "#title", "--property", "display"], "display"),
                (["find", "--session", name, "--text", "Publish"], "matched"),
                (["ax", "--session", name], "Publish"),
                (["console", "--session", name], ""),
                (["wire", "--session", name], ""),
                (["eval", "--session", name, "--js", "return document.title;"], "Form fixture"),
                (["cookies", "get", "--session", name], ""),
            ]
            for read in reads {
                let result = try await Self.sleepy(read.arguments, root: root)
                #expect(result.exitCode == 0, "\(read.arguments.joined(separator: " ")) → \(result.standardError)")
                if !read.expected.isEmpty {
                    #expect(
                        result.standardOutput.contains(read.expected),
                        "\(read.arguments.joined(separator: " ")) output lacked '\(read.expected)'",
                    )
                }
            }

            // Artifact verbs write real files.
            for verb in ["shot", "pdf", "archive"] {
                let out = root.appendingPathComponent("matrix-\(verb).bin")
                let result = try await Self.sleepy([verb, "--session", name, "--out", out.path], root: root)
                #expect(result.exitCode == 0, "\(verb) --session → \(result.standardError)")
                let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
                #expect(size > 0, "\(verb) --session wrote an empty file")
            }

            // Acts last: fill then a click that navigates the live page.
            let filled = try await Self.sleepy(
                ["fill", "--session", name, "--selector", "#title", "--value", "Hello"],
                root: root,
            )
            #expect(filled.exitCode == 0, "\(filled.standardError)")
            let clicked = try await Self.sleepy(
                ["click", "--session", name, "--selector", "#save"],
                root: root,
            )
            #expect(clicked.exitCode == 0, "\(clicked.standardError)")
            let landed = try await Self.poll {
                try await Self.sleepy(["dom", "--session", name], root: root)
            } until: { $0.standardOutput.contains("received: title=Hello") }
            #expect(landed.standardOutput.contains("received: title=Hello"))

            _ = try await Self.sleepy(["close", name], root: root)
        }
    }

    @Test func `a cookie set into a session persists to its jar`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let root = try SessionHelperProcess.makeRoot()
            defer { SessionHelperProcess.reap(root) }
            let url = baseURL.appendingPathComponent(FixturePage.staticText.fileName).absoluteString

            let opened = try await Self.sleepy(
                ["open", url, "--name", "minting", "--jar", "minted", "--budget", "60000"],
                root: root,
            )
            #expect(opened.exitCode == 0)

            let set = try await Self.sleepy(
                [
                    "cookies", "set", "--session", "minting",
                    "--name", "token", "--value", "s3cret", "--domain", "127.0.0.1",
                ],
                root: root,
            )
            #expect(set.exitCode == 0, "\(set.standardError)")

            _ = try await Self.sleepy(["close", "minting"], root: root)
            let jar = JarStore(root: root)
            let minted = try #require(JarName("minted"))
            let cookies: [CookieRecord] = try jar.cookies(in: minted)
            #expect(
                cookies.contains { $0.name == "token" && $0.value == "s3cret" },
                "the session's jar must hold the cookie the session was given",
            )
        }
    }

    @Test func `the canonical flow holds: open, login via jar, navigate, assert, shot`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let root = try SessionHelperProcess.makeRoot()
            defer { SessionHelperProcess.reap(root) }
            let name = "flow"
            let login = baseURL.appendingPathComponent("cookie").absoluteString
            let app = baseURL.appendingPathComponent("echo-cookie").absoluteString

            // Open on the login page: the server's Set-Cookie mints into the jar.
            let opened = try await Self.sleepy(
                ["open", login, "--name", name, "--jar", "login", "--budget", "60000"],
                root: root,
            )
            #expect(opened.exitCode == 0)

            // Navigate the live session; the cookie rides along.
            let navigated = try await Self.sleepy(["load", "--session", name, app], root: root)
            #expect(navigated.exitCode == 0, "\(navigated.standardError)")

            // Assert via ax: the echoed Cookie header is in the page's text.
            let outline = try await Self.sleepy(["ax", "--session", name], root: root)
            #expect(outline.exitCode == 0)
            #expect(outline.standardOutput.contains("sleepy=hollow"))

            // Shot: a real PNG of the live page.
            let shot = root.appendingPathComponent("flow.png")
            let taken = try await Self.sleepy(["shot", "--session", name, "--out", shot.path], root: root)
            #expect(taken.exitCode == 0, "\(taken.standardError)")
            let header: Data = (try? Data(contentsOf: shot).prefix(8)) ?? Data()
            #expect(header.starts(with: [0x89, 0x50, 0x4E, 0x47]), "shot --session must write a real PNG")

            _ = try await Self.sleepy(["close", name], root: root)

            // The login outlives every process that touched it: the jar holds it.
            let jar = JarStore(root: root)
            let loginJar = try #require(JarName("login"))
            #expect(try jar.cookies(in: loginJar).contains { $0.name == "sleepy" && $0.value == "hollow" })
        }
    }
}
