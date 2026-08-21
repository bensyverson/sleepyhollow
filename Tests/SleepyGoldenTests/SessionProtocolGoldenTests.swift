import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// The session protocol against the real binary: a spawned helper serving an
/// operation, a killed helper detected as dead, a short TTL reaping itself.
@Suite("Session protocol, end to end")
struct SessionProtocolGoldenTests {
    @Test func `the helper subcommand stays out of the help listing`() async throws {
        let result = try await GoldenBinary.runOffPool(["--help"])
        #expect(result.exitCode == 0)
        #expect(!result.standardOutput.contains("_host"))
    }

    @Test func `a helper that could never reap itself is refused`() async throws {
        let result = try await GoldenBinary.runOffPool(["_host", "--name", "immortal", "--idle-timeout", "0"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("idle-timeout"))
    }

    @Test func `a spawned helper serves an operation over its socket`() async throws {
        try await FixtureServer.withRunning { _, base in
            let root = try SessionHelperProcess.makeRoot()
            let name: SessionName = try #require(SessionName("golden"))
            let url: URL = try #require(URL(string: FixturePage.staticText.fileName, relativeTo: base))
            let helper = try SessionHelperProcess.start(name: name, url: url, root: root)
            defer { helper.tearDown() }
            #expect(await helper.waitUntilLive(name))

            let registry = SessionRegistry(root: root)
            let client = SessionClient(name: name, registry: registry)
            let facts: PageFacts = try await client.run(ReadFactsOperation())
            #expect(facts.httpStatus == 200)
            #expect(facts.finalURL?.absoluteString == url.absoluteURL.absoluteString)

            try await client.shutdown()
            #expect(await helper.waitUntilExited())
            #expect(registry.entries().isEmpty)
            #expect(!FileManager.default.fileExists(atPath: registry.directory(for: name).path))
        }
    }

    @Test func `a kill -9'd helper is detected as dead and pruned`() async throws {
        let root = try SessionHelperProcess.makeRoot()
        let name: SessionName = try #require(SessionName("orphan"))
        let helper = try SessionHelperProcess.start(name: name, url: nil, root: root)
        defer { helper.tearDown() }
        #expect(await helper.waitUntilLive(name))

        let registry = SessionRegistry(root: root)
        helper.kill()
        #expect(registry.liveness(of: name) == .deadProcess)
        #expect(registry.entry(for: name)?.liveness.isLive == false)
        #expect(registry.prune() == [name])
        #expect(!FileManager.default.fileExists(atPath: registry.directory(for: name).path))
    }

    @Test func `a short-TTL helper self-terminates and cleans up`() async throws {
        let root = try SessionHelperProcess.makeRoot()
        let name: SessionName = try #require(SessionName("brief"))
        let helper = try SessionHelperProcess.start(name: name, url: nil, root: root, idleTimeout: 2)
        defer { helper.tearDown() }
        #expect(await helper.waitUntilLive(name))

        #expect(await helper.waitUntilExited())
        #expect(helper.process.terminationStatus == 0)
        let registry = SessionRegistry(root: root)
        #expect(registry.entries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: registry.directory(for: name).path))
    }
}
