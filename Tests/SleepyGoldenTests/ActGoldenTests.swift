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

    @Test func `an act verb routed at a session nobody opened teaches the next move`() async throws {
        let result = try await GoldenBinary.runOffPool(["click", "--session", "no-such-session", "--selector", "#go"])
        #expect(result.exitCode == 5)
        #expect(result.standardError.contains("No session named 'no-such-session'"))
        #expect(result.standardError.contains("sleepy sessions list"))
    }

    @Test func `a one-shot fill-click-read flow reaches the submitted page`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let page = baseURL.appendingPathComponent("form.html").absoluteString
            let result = try await GoldenBinary.runOffPool([
                "dom", page,
                "--fill", "#title=Hello",
                "--click", "#save",
                "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("received: title=Hello"))
        }
    }

    @Test func `the vision doc's one-shot example shape works as written`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let page = baseURL.appendingPathComponent("act-late.html").absoluteString
            let result = try await GoldenBinary.runOffPool([
                "dom", page,
                "--click", "#go",
                "--wait-for", ".results",
                "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("Results!"))
        }
    }

    @Test func `a one-shot step that never matches is a timeout`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let page = baseURL.appendingPathComponent("form.html").absoluteString
            let result = try await GoldenBinary.runOffPool([
                "load", page, "--click", "#nowhere", "--budget", "3000",
            ])
            #expect(result.exitCode == 3)
            #expect(result.standardError.contains("#nowhere"))
        }
    }

    @Test func `naming both --selector and --at is a usage error that says to pick one`() async throws {
        let result = try await GoldenBinary.runOffPool([
            "click", "--session", "whatever", "--selector", "#go", "--at", "620,180",
        ])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--selector"))
        #expect(result.standardError.contains("--at"))
        #expect(result.standardOutput.isEmpty)
    }

    @Test func `naming neither --selector nor --at is a usage error that teaches both`() async throws {
        let result = try await GoldenBinary.runOffPool(["click", "--session", "whatever"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--selector"))
        #expect(result.standardError.contains("--at"))
    }

    @Test func `an --at value that is not a point is a usage error naming the shape`() async throws {
        let result = try await GoldenBinary.runOffPool(["click", "--session", "whatever", "--at", "middle"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("x,y"))
    }

    @Test func `click --help states the coordinate space --at is measured in`() async throws {
        let result = try await GoldenBinary.runOffPool(["click", "--help"])
        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("--at"))
        #expect(result.standardOutput.lowercased().contains("document"))
        #expect(result.standardOutput.lowercased().contains("shadow"))
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
