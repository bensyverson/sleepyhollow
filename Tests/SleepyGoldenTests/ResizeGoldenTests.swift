import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `sleepy resize <WxH>` against the real binary: check another breakpoint
/// without reopening the session.
///
/// `--budget 60000` on the `open`, as everywhere in this suite: WebKit
/// contention across parallel golden subprocesses pushes loads past the
/// 30-second default (see ``CaptureGoldenTests``).
@Suite(.serialized)
struct ResizeGoldenTests {
    /// Runs `sleepy` against a throwaway registry root.
    private static func sleepy(_ arguments: [String], root: URL) async throws -> CliInvocation {
        try await GoldenBinary.runOffPool(
            arguments,
            environment: [SessionRegistry.homeEnvironmentVariable: root.path],
        )
    }

    @Test func `resize moves a live session to another breakpoint`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let root = try SessionHelperProcess.makeRoot()
            defer { SessionHelperProcess.reap(root) }
            let name: SessionName = try #require(SessionName("golden-resize"))
            let url = baseURL.appendingPathComponent("capture-breakpoint.html").absoluteString

            let opened = try await Self.sleepy(
                ["open", url, "--name", name.rawValue, "--size", "1280x800", "--budget", "60000"],
                root: root,
            )
            #expect(opened.exitCode == 0)

            let wide = try await Self.sleepy(
                ["eval", "--session", name.rawValue, "--js", "return window.innerWidth;"],
                root: root,
            )
            #expect(wide.standardOutput.contains("1280"))

            let resized = try await Self.sleepy(["resize", "--session", name.rawValue, "390x844"], root: root)
            #expect(resized.exitCode == 0)
            #expect(resized.standardOutput.contains("\"width\" : 390"))
            #expect(resized.standardOutput.contains("\"height\" : 844"))

            let narrow = try await Self.sleepy(
                ["eval", "--session", name.rawValue, "--js", "return window.innerWidth;"],
                root: root,
            )
            #expect(narrow.standardOutput.contains("390"))

            _ = try await Self.sleepy(["close", name.rawValue], root: root)
        }
    }

    @Test func `a bare width keeps the default height`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let root = try SessionHelperProcess.makeRoot()
            defer { SessionHelperProcess.reap(root) }
            let name: SessionName = try #require(SessionName("golden-resize-width"))
            let url = baseURL.appendingPathComponent(FixturePage.staticText.fileName).absoluteString

            #expect(try await Self.sleepy(
                ["open", url, "--name", name.rawValue, "--budget", "60000"],
                root: root,
            ).exitCode == 0)

            let resized = try await Self.sleepy(["resize", "--session", name.rawValue, "480"], root: root)
            #expect(resized.exitCode == 0)
            #expect(resized.standardOutput.contains("\"width\" : 480"))
            #expect(resized.standardOutput.contains("\"height\" : \(ViewportSize.default.height)"))

            _ = try await Self.sleepy(["close", name.rawValue], root: root)
        }
    }

    @Test func `resize without a session is a usage error that teaches both ways`() async throws {
        let result = try await GoldenBinary.runOffPool(["resize", "390x844"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--session"))
        #expect(result.standardError.contains("--size"))
    }

    @Test func `an unreadable size names both shapes`() async throws {
        let result = try await GoldenBinary.runOffPool(["resize", "--session", "nobody", "wide"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("WxH"))
    }
}
