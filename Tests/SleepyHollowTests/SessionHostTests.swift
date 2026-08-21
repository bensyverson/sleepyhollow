import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// The helper loop and its client, in one process: an operation shipped over
/// the socket, idle self-termination, and two sessions side by side.
@Suite("Session host and client")
@MainActor
struct SessionHostTests {
    @Test func `a client runs an operation against the helper's page`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let root = try SessionTestRoot.make()
            defer { SessionTestRoot.remove(root) }
            let registry = SessionRegistry(root: root)
            let name: SessionName = try #require(SessionName("probe"))
            let url: URL = try #require(URL(string: FixturePage.staticText.fileName, relativeTo: base))
            let host = SessionHost(
                name: name,
                url: url,
                options: LoadOptions(),
                registry: registry,
                operations: SessionOperations.registry,
                idleTimeout: 60,
            )
            try await host.start()
            #expect(registry.liveness(of: name) == .live)

            let client = SessionClient(name: name, registry: registry)
            let facts: PageFacts = try await client.run(ReadFactsOperation())
            #expect(facts.httpStatus == 200)
            #expect(facts.finalURL?.absoluteString == url.absoluteURL.absoluteString)

            try await client.shutdown()
            await host.waitUntilStopped()
            #expect(!FileManager.default.fileExists(atPath: registry.directory(for: name).path))
        }
    }

    @Test func `an idle host self-terminates and cleans up after its TTL`() async throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let name: SessionName = try #require(SessionName("drowsy"))
        let host = SessionHost(
            name: name,
            url: nil,
            options: LoadOptions(),
            registry: registry,
            operations: SessionOperations.registry,
            idleTimeout: 1,
        )
        try await host.start()
        #expect(registry.liveness(of: name) == .live)
        #expect(await stopped(host, within: 20))
        #expect(registry.entries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: registry.directory(for: name).path))
    }

    /// Asserts the mechanism (`lastActivity` advances when work is served),
    /// not a race between wall-clock sleeps and the TTL — an earlier version
    /// slept real seconds against a short TTL and lost under full-suite load.
    /// The idle *expiry* path keeps its own cheap end-to-end test above.
    @Test func `work restarts the idle clock`() async throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let name: SessionName = try #require(SessionName("busy"))
        let host = SessionHost(
            name: name,
            url: nil,
            options: LoadOptions(),
            registry: registry,
            operations: SessionOperations.registry,
            idleTimeout: 60,
        )
        try await host.start()
        let before: Date = host.lastActivity
        // Only needs to be measurable, not to approach the TTL.
        try await Task.sleep(nanoseconds: 50_000_000)
        let client = SessionClient(name: name, registry: registry)
        _ = try await client.run(ReadFactsOperation())
        #expect(host.lastActivity > before, "serving work must restart the idle clock")
        #expect(registry.liveness(of: name) == .live)
        try await client.shutdown()
        await host.waitUntilStopped()
    }

    @Test func `a session whose first load fails leaves nothing behind`() async throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let name: SessionName = try #require(SessionName("doomed"))
        let host = SessionHost(
            name: name,
            url: URL(string: "http://127.0.0.1:9/"),
            options: LoadOptions(),
            registry: registry,
            operations: SessionOperations.registry,
            idleTimeout: 60,
        )
        let thrown = await #expect(throws: SleepyError.self) {
            try await host.start()
        }
        #expect(try #require(thrown).exitStatus == .loadFailure)
        #expect(registry.entries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: registry.directory(for: name).path))
    }

    @Test func `two sessions coexist under one root`() async throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let first: SessionName = try #require(SessionName("one"))
        let second: SessionName = try #require(SessionName("two"))
        let hosts: [SessionHost] = [first, second].map { name in
            SessionHost(
                name: name,
                url: nil,
                options: LoadOptions(),
                registry: registry,
                operations: SessionOperations.registry,
                idleTimeout: 60,
            )
        }
        for host in hosts {
            try await host.start()
        }
        #expect(registry.entries().map(\.name) == [first, second])
        #expect(registry.entries().map(\.liveness) == [.live, .live])

        let facts: PageFacts = try await SessionClient(name: second, registry: registry).run(ReadFactsOperation())
        #expect(facts.finalURL == nil)

        for host in hosts {
            try await SessionClient(name: host.name, registry: registry).shutdown()
            await host.waitUntilStopped()
        }
        #expect(registry.entries().isEmpty)
    }

    @Test func `a second host on an open name refuses to start`() async throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let name: SessionName = try #require(SessionName("claimed"))
        let first = makeHost(name: name, registry: registry)
        try await first.start()
        defer { Task { @MainActor in await first.stop() } }

        let second = makeHost(name: name, registry: registry)
        let thrown = await #expect(throws: SleepyError.self) {
            try await second.start()
        }
        let error: SleepyError = try #require(thrown)
        #expect(error.exitStatus == .environment)
        #expect(error.message.contains("claimed"))
    }

    @Test func `a host that lost the race never deletes the winner's directory`() async throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let name: SessionName = try #require(SessionName("contested"))
        let winner = makeHost(name: name, registry: registry)
        try await winner.start()
        let loser = makeHost(name: name, registry: registry)
        await #expect(throws: SleepyError.self) {
            try await loser.start()
        }
        await loser.stop()
        #expect(registry.liveness(of: name) == .live)
        await winner.stop()
        #expect(registry.entries().isEmpty)
    }

    @Test func `a client on an unknown session teaches the next move`() async throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let name: SessionName = try #require(SessionName("ghost"))
        let client = SessionClient(name: name, registry: registry)
        let thrown = await #expect(throws: SleepyError.self) {
            _ = try await client.run(ReadFactsOperation())
        }
        let error: SleepyError = try #require(thrown)
        #expect(error.exitStatus == .environment)
        #expect(error.message.contains("ghost"))
        #expect(error.nextMove != nil)
    }

    @Test func `a client on a dead helper's leftovers teaches the next move`() async throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let name: SessionName = try #require(SessionName("zombie"))
        try registry.write(
            SessionRecord(
                processID: SessionTestRoot.exitedProcessID(),
                url: nil,
                startedAt: Date(),
                idleTimeout: 900,
            ),
            for: name,
        )
        let thrown = await #expect(throws: SleepyError.self) {
            _ = try await SessionClient(name: name, registry: registry).run(ReadFactsOperation())
        }
        let error: SleepyError = try #require(thrown)
        #expect(error.exitStatus == .environment)
        #expect(error.message.contains("zombie"))
    }

    @Test func `an operation the helper does not know comes back as a teaching failure`() async throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let name: SessionName = try #require(SessionName("empty"))
        let host = SessionHost(
            name: name,
            url: nil,
            options: LoadOptions(),
            registry: registry,
            operations: OperationRegistry(),
            idleTimeout: 60,
        )
        try await host.start()
        let thrown = await #expect(throws: SleepyError.self) {
            _ = try await SessionClient(name: name, registry: registry).run(ReadFactsOperation())
        }
        let error: SleepyError = try #require(thrown)
        #expect(error.message.contains(ReadFactsOperation.kind))
        await host.stop()
    }

    // MARK: - Apparatus

    private func makeHost(name: SessionName, registry: SessionRegistry) -> SessionHost {
        SessionHost(
            name: name,
            url: nil,
            options: LoadOptions(),
            registry: registry,
            operations: SessionOperations.registry,
            idleTimeout: 60,
        )
    }

    /// Waits for `host` to stop, bounded so a broken TTL fails instead of hanging.
    private func stopped(_ host: SessionHost, within seconds: Double) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await host.waitUntilStopped()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return false
            }
            let first: Bool = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
