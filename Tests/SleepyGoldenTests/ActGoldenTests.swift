import Foundation
import Testing
import TestSupport

/// The act family end to end: the session verbs' teaching refusals, and the
/// one-shot action flags riding a loading verb.
///
/// `.serialized` and `--budget 60000`: see ``CaptureGoldenTests`` — WebKit
/// contention across parallel golden subprocesses pushes loads past the
/// 30-second default.
@Suite(.serialized)
struct ActGoldenTests {
    @Test func `an act verb without --session is a teaching usage error`() async throws {
        let invocations: [(arguments: [String], oneShotFlag: String)] = [
            (["click", "--selector", "#go"], "--click"),
            (["fill", "--selector", "#title", "--value", "Hello"], "--fill"),
            (["submit", "--selector", "#editor"], "--submit"),
        ]
        for invocation in invocations {
            let result = try await GoldenBinary.runOffPool(invocation.arguments)
            #expect(result.exitCode == 2)
            #expect(result.standardError.contains("--session"))
            #expect(result.standardError.contains(invocation.oneShotFlag))
        }
    }

    @Test func `an act verb given a URL teaches the one-shot flags instead`() async throws {
        let result = try await GoldenBinary.runOffPool(["click", "http://example.com", "--selector", "#go"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--session"))
    }

    @Test func `an act verb with --session names the leaf that will route it`() async throws {
        let result = try await GoldenBinary.runOffPool(["click", "--session", "login", "--selector", "#go"])
        #expect(result.exitCode == 5)
        #expect(result.standardError.contains("DLHu7"))
    }

    @Test func `a one-shot fill-click-wait-read flow reaches the submitted page`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let page = baseURL.appendingPathComponent("form.html").absoluteString
            let result = try await GoldenBinary.runOffPool([
                "dom", page,
                "--wait-for", "#save",
                "--fill", "#title=Hello",
                "--click", "#save",
                "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("received: title=Hello"))
        }
    }

    @Test func `a one-shot step that matches nothing is a clean negative`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let page = baseURL.appendingPathComponent("form.html").absoluteString
            let result = try await GoldenBinary.runOffPool([
                "load", page, "--click", "#nowhere", "--budget", "60000",
            ])
            #expect(result.exitCode == 1)
            #expect(result.standardError.contains("#nowhere"))
        }
    }

    @Test func `another option's value that spells --click is not an action step`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let page = baseURL.appendingPathComponent("static.html").absoluteString
            let result = try await GoldenBinary.runOffPool([
                "load", page, "--confirm", "accept", "--prompt-text=--click", "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
        }
    }
}
