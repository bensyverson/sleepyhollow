import Foundation
import SleepyHollow
import Testing
import TestSupport

/// `PageHost.waitUntil` on a page that is already loaded. Expected-timeout
/// budgets are 6 s, the floor `project/gotchas.md` (2026-09-27) sets; success
/// paths get ``TestSupport/livenessBudget``.
@Suite("PageHost waitUntil")
struct PageHostWaitUntilTests {
    private static let timeoutBudget: TimeInterval = 6

    @MainActor
    private static func loadedHost(_ base: URL) async throws -> PageHost {
        let host = PageHost()
        _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
        return host
    }

    @Test
    @MainActor
    func `a condition already true resolves at once`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await Self.loadedHost(base)
            try await host.waitUntil("document.title === 'Static fixture'", budget: TestSupport.livenessBudget)
        }
    }

    @Test
    @MainActor
    func `a condition the page makes true later resolves when it does`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await Self.loadedHost(base)
            try await host.evaluate("setTimeout(() => { window.__ready = true; }, 300); return null;", in: .page)
            try await host.waitUntil("window.__ready === true", budget: TestSupport.livenessBudget)
            let ready: Bool = try await host.evaluate("return window.__ready === true;", as: Bool.self, in: .page)
            #expect(ready)
        }
    }

    @Test
    @MainActor
    func `a condition that never holds times out with a teaching error`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await Self.loadedHost(base)
            do {
                try await host.waitUntil("window.__never === true", budget: Self.timeoutBudget)
                Issue.record("expected a timeout")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.message.contains("window.__never === true"))
                #expect(error.message.contains("6"))
                #expect(error.nextMove != nil)
            }
            #expect(host.abandonedCall == nil, "a wait that times out leaves the host reusable")
        }
    }

    @Test
    @MainActor
    func `a condition that throws every time says why in the timeout`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await Self.loadedHost(base)
            do {
                try await host.waitUntil("window.__missing.deeper === 1", budget: Self.timeoutBudget)
                Issue.record("expected a timeout")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.message.contains("TypeError"))
            }
        }
    }

    @Test
    @MainActor
    func `an expression that does not parse fails at once, naming the syntax error`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await Self.loadedHost(base)
            let started = Date()
            do {
                try await host.waitUntil("window.__ready ===", budget: TestSupport.livenessBudget)
                Issue.record("expected a syntax error")
            } catch let EvaluationError.javaScript(message) {
                #expect(message.contains("SyntaxError"))
            }
            #expect(Date().timeIntervalSince(started) < TestSupport.livenessBudget)
        }
    }

    @Test
    @MainActor
    func `the page's own world is the default`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await Self.loadedHost(base)
            try await host.evaluate("window.__pageGlobal = 1; return null;", in: .page)
            try await host.waitUntil("window.__pageGlobal === 1", budget: TestSupport.livenessBudget)
        }
    }

    @Test
    @MainActor
    func `concurrent waits answer only their own condition`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await Self.loadedHost(base)
            try await host.evaluate("setTimeout(() => { window.__soon = true; }, 300); return null;", in: .page)
            let never = Task { @MainActor in
                try await host.waitUntil("window.__never === true", budget: Self.timeoutBudget)
            }
            try await host.waitUntil("window.__soon === true", budget: TestSupport.livenessBudget)
            await #expect(throws: SleepyError.self) { try await never.value }
        }
    }
}
