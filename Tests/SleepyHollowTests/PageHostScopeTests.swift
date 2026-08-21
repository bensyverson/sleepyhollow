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

    @Test
    @MainActor
    func `a named jar is refused, naming the leaf that will deliver jars`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.jar = JarName("login-flow")
            let error: SleepyError? = await failure(for: options, base: base)
            #expect(error?.kind == .environment)
            #expect(error?.description.contains("XDmfo") == true)
        }
    }

    @Test
    @MainActor
    func `wait conditions beyond load are refused, naming the wait-engine leaf`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            for condition in [
                WaitCondition.selector("#greeting"),
                WaitCondition.predicate("true"),
                WaitCondition.idle,
            ] {
                var options = LoadOptions()
                options.wait = condition
                let error: SleepyError? = await failure(for: options, base: base)
                #expect(error?.kind == .environment)
                #expect(error?.description.contains("oCDLF") == true)
            }
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

    @Test
    @MainActor
    func `action steps are refused, naming the act leaf`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.steps = [ActionStep.click(selector: "#go")]
            let error: SleepyError? = await failure(for: options, base: base)
            #expect(error?.kind == .environment)
            #expect(error?.description.contains("q6mlw") == true)
        }
    }
}
