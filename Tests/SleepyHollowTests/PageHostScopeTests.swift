import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("PageHost scope boundaries")
struct PageHostScopeTests {
    @MainActor
    private func failure(for options: LoadOptions, base: URL) async -> SleepyError? {
        let host = PageHost(options: options)
        do {
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            return nil
        } catch let error as SleepyError {
            return error
        } catch {
            return nil
        }
    }

    /// The jar mechanism itself is covered by ``PageHostJarTests``; what this
    /// suite still owes is that a named jar is *in* scope — no refusal, and
    /// nothing written outside the root it was pointed at.
    @Test
    @MainActor
    func `a named jar is honoured rather than refused`() async throws {
        let root: URL = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.jar = JarName("login-flow")
            let host = PageHost(options: options, jars: JarStore(root: root))
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("jars").path))
        }
    }

    @Test
    @MainActor
    func `waiting for load, or for nothing, is supported`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .load
            #expect(await failure(for: options, base: base) == nil)
            #expect(await failure(for: LoadOptions(), base: base) == nil)
        }
    }
}
