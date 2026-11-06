import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// The library's page-world calls with the page's scripts off: they refuse
/// with the teaching error, never as WebKit's "Cannot execute JavaScript"
/// dressed up as ``EvaluationError/javaScript(message:)`` — the page did not
/// throw; Sleepy closed the world.
@Suite("Page world with page scripts off")
struct PageScriptsWorldTests {
    @MainActor
    private func scriptlessHost(base: URL) async throws -> PageHost {
        var options = LoadOptions(pageScripts: .disabled)
        options.budget = TestSupport.livenessBudget
        let host = PageHost(options: options)
        _ = try await host.load(URL(string: "no-js.html", relativeTo: base)!)
        return host
    }

    @Test
    @MainActor
    func `a page-world evaluate refuses with the teaching error`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await scriptlessHost(base: base)
            let error = await #expect(throws: SleepyError.self) {
                try await host.evaluate("return 1;", in: .page)
            }
            #expect(error?.kind == .usage)
            #expect(error?.message.contains("--no-js") == true)
        }
    }

    @Test
    @MainActor
    func `waitUntil in its default page world refuses with the teaching error`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await scriptlessHost(base: base)
            let error = await #expect(throws: SleepyError.self) {
                try await host.waitUntil("true", budget: 5)
            }
            #expect(error?.kind == .usage)
        }
    }
}
