import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("PageHost console capture")
struct PageHostConsoleTests {
    @Test
    @MainActor
    func `console.error calls and uncaught errors are counted`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            let facts: PageFacts = try await host.load(URL(string: "console-errors.html", relativeTo: base)!)
            // Two console.error calls plus one uncaught TypeError; console.log is not an error.
            #expect(facts.consoleErrorCount == 3)
        }
    }

    @Test
    @MainActor
    func `a quiet page counts zero, and the page's own console still works`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            let facts: PageFacts = try await host.load(URL(string: "static.html", relativeTo: base)!)
            #expect(facts.consoleErrorCount == 0)
            let stillCallable: String = try await host.evaluate(
                "return typeof console.error;",
                in: .page,
            )
            #expect(stillCallable == "\"function\"")
        }
    }

    @Test
    @MainActor
    func `each load starts the count fresh`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "console-errors.html", relativeTo: base)!)
            let second: PageFacts = try await host.load(URL(string: "static.html", relativeTo: base)!)
            #expect(second.consoleErrorCount == 0)
        }
    }
}
