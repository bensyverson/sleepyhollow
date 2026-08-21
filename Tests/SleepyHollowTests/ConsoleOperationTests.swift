import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("Console verb")
struct ConsoleOperationTests {
    @Test
    @MainActor
    func `every console level is captured, in call order`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "observe-console.html", relativeTo: base)!)
            let log: ConsoleLog = try await host.execute(ConsoleOperation())
            let console: [ConsoleMessage] = log.messages.filter { $0.origin == .console }
            #expect(console.map(\.level) == [.debug, .log, .info, .warn, .error])
            #expect(console.map(\.text) == [
                "a debug line",
                "a log line 1 true",
                "an info line",
                "a warn line",
                "an error line",
            ])
            #expect(log.droppedMessages == 0)
        }
    }

    @Test
    @MainActor
    func `uncaught errors and unhandled rejections carry their origin`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "console-errors.html", relativeTo: base)!)
            let log: ConsoleLog = try await host.execute(ConsoleOperation())
            let uncaught: ConsoleMessage? = log.messages.first { $0.origin == .uncaught }
            #expect(uncaught?.level == .error)
            #expect(uncaught?.text.contains("null") == true)
            // The page's own console.log is in the log, though it is not an error.
            #expect(log.messages.contains { $0.level == .log && $0.text.contains("not an error") })
        }
    }

    @Test
    @MainActor
    func `an unhandled rejection is reported with its reason`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "observe-console.html", relativeTo: base)!)
            let log: ConsoleLog = try await host.execute(ConsoleOperation())
            let rejection: ConsoleMessage? = log.messages.first { $0.origin == .unhandledRejection }
            #expect(rejection?.level == .error)
            #expect(rejection?.text.contains("rejected on purpose") == true)
        }
    }

    @Test
    @MainActor
    func `a quiet page produces an empty log`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            let log: ConsoleLog = try await host.execute(ConsoleOperation())
            #expect(log.messages.isEmpty)
        }
    }

    @Test
    @MainActor
    func `capture keeps working after the load, and the page's console still runs`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            _ = try await host.evaluate("console.info('after the load'); return null;", in: .page)
            let log: ConsoleLog = try await host.execute(ConsoleOperation())
            #expect(log.messages.map(\.text) == ["after the load"])
            #expect(log.messages.first?.level == .info)
        }
    }

    @Test
    @MainActor
    func `each load starts the log fresh`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "observe-console.html", relativeTo: base)!)
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            let log: ConsoleLog = try await host.execute(ConsoleOperation())
            #expect(log.messages.isEmpty)
        }
    }

    @Test
    @MainActor
    func `the error count in the load facts still counts only errors`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            let facts: PageFacts = try await host.load(URL(string: "observe-console.html", relativeTo: base)!)
            let log: ConsoleLog = try await host.execute(ConsoleOperation())
            // One console.error, one unhandled rejection — debug/log/info/warn are not errors.
            #expect(facts.consoleErrorCount == 2)
            #expect(log.messages.count == 6)
        }
    }
}
