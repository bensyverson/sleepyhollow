import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// The session lifecycle verbs against the real binary: `open` claiming a
/// name, a read verb running against the live page, `load --session`
/// navigating it, `close` taking it down, and `sessions list|prune` reaping
/// what a `kill -9` left behind.
///
/// `--budget 60000` throughout: see ``CaptureGoldenTests`` — WebKit contention
/// across parallel golden subprocesses pushes loads past the 30-second default.
@Suite(.serialized)
struct SessionVerbsGoldenTests {
    /// Runs `sleepy` against a throwaway registry root.
    private static func sleepy(_ arguments: [String], root: URL) async throws -> CliInvocation {
        try await GoldenBinary.runOffPool(
            arguments,
            environment: [SessionRegistry.homeEnvironmentVariable: root.path],
        )
    }

    @Test func `open claims a name, a verb reads it, close takes it down`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let root = try SessionHelperProcess.makeRoot()
            defer { SessionHelperProcess.reap(root) }
            let name: SessionName = try #require(SessionName("golden-open"))
            let url = baseURL.appendingPathComponent(FixturePage.staticText.fileName).absoluteString

            let opened = try await Self.sleepy(["open", url, "--name", name.rawValue, "--budget", "60000"], root: root)
            #expect(opened.exitCode == 0)
            #expect(opened.standardOutput.contains("\"httpStatus\""))
            #expect(opened.standardOutput.contains("200"))

            let registry = SessionRegistry(root: root)
            #expect(registry.liveness(of: name) == .live)

            let read = try await Self.sleepy(["dom", "--session", name.rawValue], root: root)
            #expect(read.exitCode == 0)
            #expect(read.standardOutput.contains("Sleepy Hollow"))

            let closed = try await Self.sleepy(["close", name.rawValue], root: root)
            #expect(closed.exitCode == 0)
            #expect(registry.entries().isEmpty)
        }
    }

    @Test func `open on a live name exits 5 and teaches navigate-or-close`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let root = try SessionHelperProcess.makeRoot()
            defer { SessionHelperProcess.reap(root) }
            let name: SessionName = try #require(SessionName("golden-dup"))
            let url = baseURL.appendingPathComponent(FixturePage.staticText.fileName).absoluteString

            let first = try await Self.sleepy(["open", url, "--name", name.rawValue, "--budget", "60000"], root: root)
            #expect(first.exitCode == 0)

            let second = try await Self.sleepy(["open", url, "--name", name.rawValue, "--budget", "60000"], root: root)
            #expect(second.exitCode == 5)
            #expect(second.standardError.contains("already open"))
            #expect(second.standardError.contains("sleepy load --session \(name.rawValue)"))
            #expect(second.standardError.contains("sleepy close \(name.rawValue)"))

            _ = try await Self.sleepy(["close", name.rawValue], root: root)
        }
    }

    @Test func `load --session navigates an open session`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let root = try SessionHelperProcess.makeRoot()
            defer { SessionHelperProcess.reap(root) }
            let name: SessionName = try #require(SessionName("golden-nav"))
            let first = baseURL.appendingPathComponent(FixturePage.staticText.fileName).absoluteString
            let second = baseURL.appendingPathComponent(FixturePage.form.fileName).absoluteString

            #expect(try await Self.sleepy(
                ["open", first, "--name", name.rawValue, "--budget", "60000"],
                root: root,
            ).exitCode == 0)

            let navigated = try await Self.sleepy(["load", "--session", name.rawValue, second], root: root)
            #expect(navigated.exitCode == 0)
            #expect(navigated.standardOutput.contains(FixturePage.form.fileName))

            let read = try await Self.sleepy(["dom", "--session", name.rawValue], root: root)
            #expect(read.exitCode == 0)
            #expect(read.standardOutput.contains("<form"))

            _ = try await Self.sleepy(["close", name.rawValue], root: root)
        }
    }

    @Test func `a loading option on a session invocation is a usage error`() async throws {
        let root = try SessionHelperProcess.makeRoot()
        defer { SessionHelperProcess.reap(root) }
        let result = try await Self.sleepy(["dom", "--session", "whatever", "--theme", "dark"], root: root)
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--theme"))
        #expect(result.standardError.contains("sleepy open"))
    }

    @Test func `sessions list shows a live session then reaps a killed one`() async throws {
        let root = try SessionHelperProcess.makeRoot()
        defer { SessionHelperProcess.reap(root) }
        let name: SessionName = try #require(SessionName("golden-list"))
        let helper = try SessionHelperProcess.start(name: name, url: nil, root: root)
        defer { helper.tearDown() }
        #expect(await helper.waitUntilLive(name))

        let live = try await Self.sleepy(["sessions", "list"], root: root)
        #expect(live.exitCode == 0)
        #expect(live.standardOutput.contains(name.rawValue))
        #expect(live.standardOutput.contains("live"))
        #expect(live.standardOutput.contains(String(helper.process.processIdentifier)))

        #expect(await helper.killAndAwaitDeath(name))
        let dead = try await Self.sleepy(["sessions", "list"], root: root)
        #expect(dead.exitCode == 0)
        #expect(dead.standardOutput.contains(name.rawValue))
        #expect(dead.standardOutput.contains("dead"))

        // list reaps what it reported: the next listing is clean.
        let after = try await Self.sleepy(["sessions", "list"], root: root)
        #expect(!after.standardOutput.contains(name.rawValue))
        #expect(SessionRegistry(root: root).entries().isEmpty)
    }

    @Test func `sessions prune reports the orphans it removed`() async throws {
        let root = try SessionHelperProcess.makeRoot()
        defer { SessionHelperProcess.reap(root) }
        let name: SessionName = try #require(SessionName("golden-prune"))
        let helper = try SessionHelperProcess.start(name: name, url: nil, root: root)
        defer { helper.tearDown() }
        #expect(await helper.waitUntilLive(name))
        #expect(await helper.killAndAwaitDeath(name))

        let pruned = try await Self.sleepy(["sessions", "prune"], root: root)
        #expect(pruned.exitCode == 0)
        #expect(pruned.standardOutput.contains(name.rawValue))
        #expect(SessionRegistry(root: root).entries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: SessionRegistry(root: root).directory(for: name).path))
    }

    @Test func `open reaps a dead name lazily and claims it`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let root = try SessionHelperProcess.makeRoot()
            defer { SessionHelperProcess.reap(root) }
            let name: SessionName = try #require(SessionName("golden-revive"))
            let helper = try SessionHelperProcess.start(name: name, url: nil, root: root)
            defer { helper.tearDown() }
            #expect(await helper.waitUntilLive(name))
            #expect(await helper.killAndAwaitDeath(name))

            let url = baseURL.appendingPathComponent(FixturePage.staticText.fileName).absoluteString
            let opened = try await Self.sleepy(["open", url, "--name", name.rawValue, "--budget", "60000"], root: root)
            #expect(opened.exitCode == 0)
            #expect(SessionRegistry(root: root).liveness(of: name) == .live)

            _ = try await Self.sleepy(["close", name.rawValue], root: root)
        }
    }

    @Test func `closing a session nobody opened is a teaching environment error`() async throws {
        let root = try SessionHelperProcess.makeRoot()
        defer { SessionHelperProcess.reap(root) }
        let result = try await Self.sleepy(["close", "never-opened"], root: root)
        #expect(result.exitCode == 5)
        #expect(result.standardError.contains("never-opened"))
    }

    @Test func `closing a dead session reaps it and exits 0`() async throws {
        let root = try SessionHelperProcess.makeRoot()
        defer { SessionHelperProcess.reap(root) }
        let name: SessionName = try #require(SessionName("golden-corpse"))
        let helper = try SessionHelperProcess.start(name: name, url: nil, root: root)
        defer { helper.tearDown() }
        #expect(await helper.waitUntilLive(name))
        #expect(await helper.killAndAwaitDeath(name))

        let result = try await Self.sleepy(["close", name.rawValue], root: root)
        #expect(result.exitCode == 0)
        #expect(SessionRegistry(root: root).entries().isEmpty)
    }

    @Test func `an act verb runs against a live session`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let root = try SessionHelperProcess.makeRoot()
            defer { SessionHelperProcess.reap(root) }
            let name: SessionName = try #require(SessionName("golden-act"))
            let url = baseURL.appendingPathComponent(FixturePage.form.fileName).absoluteString

            #expect(try await Self.sleepy(
                ["open", url, "--name", name.rawValue, "--budget", "60000"],
                root: root,
            ).exitCode == 0)

            let filled = try await Self.sleepy(
                ["fill", "--session", name.rawValue, "--selector", "#title", "--value", "Hollow"],
                root: root,
            )
            #expect(filled.exitCode == 0)

            let read = try await Self.sleepy(
                ["eval", "--session", name.rawValue, "--js", "return document.querySelector('#title').value;"],
                root: root,
            )
            #expect(read.exitCode == 0)
            #expect(read.standardOutput.contains("Hollow"))

            _ = try await Self.sleepy(["close", name.rawValue], root: root)
        }
    }
}
