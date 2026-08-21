import Foundation
@testable import SleepyHollow
import Testing

/// The on-disk session directory: layout, liveness classification, pruning.
@Suite("Session registry")
struct SessionRegistryTests {
    @Test func `the default root honours the home environment variable`() {
        let root: URL = SessionRegistry.defaultRoot(
            environment: [SessionRegistry.homeEnvironmentVariable: "/tmp/sleepy-home"],
        )
        #expect(root.path == "/tmp/sleepy-home")
    }

    @Test func `the default root falls back to a dot directory in the user's home`() {
        let root: URL = SessionRegistry.defaultRoot(environment: [:])
        #expect(root.lastPathComponent == ".sleepyhollow")
        #expect(root.deletingLastPathComponent().path == NSHomeDirectory())
    }

    @Test func `the layout puts the socket inside the session's own directory`() throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let name: SessionName = try #require(SessionName("login"))
        #expect(registry.directory(for: name).path == root.path + "/sessions/login")
        #expect(try registry.socketPath(for: name) == root.path + "/sessions/login/sock")
        #expect(registry.recordURL(for: name).lastPathComponent == "session.json")
    }

    @Test func `a socket path the kernel cannot address is refused, not truncated`() throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let deep: URL = root.appendingPathComponent(String(repeating: "d", count: 120))
        let registry = SessionRegistry(root: deep)
        let name: SessionName = try #require(SessionName("login"))
        let thrown = #expect(throws: SleepyError.self) {
            _ = try registry.socketPath(for: name)
        }
        let error: SleepyError = try #require(thrown)
        #expect(error.exitStatus == .environment)
        #expect(error.nextMove != nil)
    }

    @Test func `an unknown name has no record and no entry`() throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let name: SessionName = try #require(SessionName("ghost"))
        #expect(registry.liveness(of: name) == .noRecord)
        #expect(registry.entry(for: name) == nil)
        #expect(registry.entries().isEmpty)
    }

    @Test func `a record naming an exited process classifies as a dead process`() throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let name: SessionName = try #require(SessionName("stale"))
        let record = try SessionRecord(
            processID: SessionTestRoot.exitedProcessID(),
            url: URL(string: "http://example.com/"),
            startedAt: Date(),
            idleTimeout: 900,
        )
        try registry.write(record, for: name)
        try FileManager.default.createFile(atPath: registry.socketPath(for: name), contents: Data())
        #expect(registry.liveness(of: name) == .deadProcess)
        #expect(registry.entry(for: name)?.liveness.isLive == false)
    }

    @Test func `a live process with no socket classifies as unreachable`() throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let name: SessionName = try #require(SessionName("halfborn"))
        let record = SessionRecord(processID: getpid(), url: nil, startedAt: Date(), idleTimeout: 900)
        try registry.write(record, for: name)
        #expect(registry.liveness(of: name) == .unreachableSocket)
    }

    @Test func `entries lists every readable session by name`() throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let record = SessionRecord(processID: getpid(), url: nil, startedAt: Date(), idleTimeout: 900)
        try registry.write(record, for: #require(SessionName("second")))
        try registry.write(record, for: #require(SessionName("first")))
        #expect(registry.entries().map(\.name.rawValue) == ["first", "second"])
    }

    @Test func `prune removes dead sessions and reports them`() throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let dead: SessionName = try #require(SessionName("dead"))
        try registry.write(
            SessionRecord(processID: SessionTestRoot.exitedProcessID(), url: nil, startedAt: Date(), idleTimeout: 900),
            for: dead,
        )
        #expect(registry.prune() == [dead])
        #expect(!FileManager.default.fileExists(atPath: registry.directory(for: dead).path))
        #expect(registry.entries().isEmpty)
    }

    @Test func `prune sweeps a directory with no readable record`() throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let debris: SessionName = try #require(SessionName("debris"))
        try FileManager.default.createDirectory(
            at: registry.directory(for: debris),
            withIntermediateDirectories: true,
        )
        #expect(registry.prune() == [debris])
        #expect(!FileManager.default.fileExists(atPath: registry.directory(for: debris).path))
    }

    @Test func `pruning an empty registry is a no-op`() throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        #expect(SessionRegistry(root: root).prune().isEmpty)
    }
}
