import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("Wait for idle")
struct WaitIdleTests {
    @Test
    @MainActor
    func `a quiet page settles after the quiet window and no longer`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .idle
            options.budget = 30
            let host = PageHost(options: options)
            let started = Date()
            let facts: PageFacts = try await host.load(URL(string: "static.html", relativeTo: base)!)
            let elapsed: TimeInterval = Date().timeIntervalSince(started)
            #expect(facts.httpStatus == 200)
            #expect(elapsed >= 0.5, "idle means a measured quiet window, not 'nothing in flight right now'")
            #expect(elapsed < 30)
        }
    }

    @Test
    @MainActor
    func `a page with a request still in flight is not idle until it finishes`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .idle
            options.budget = 30
            let host = PageHost(options: options)
            let started = Date()
            _ = try await host.load(URL(string: "wait-idle.html", relativeTo: base)!)
            let elapsed: TimeInterval = Date().timeIntervalSince(started)
            let done: String = try await host.evaluate("return window.sleepyFetchDone === true;", in: .page)
            #expect(done == "true", "the in-flight fetch must have finished before idle was declared")
            #expect(elapsed >= 1.0, "600ms of request plus the 500ms quiet window is the floor")
            #expect(elapsed < 30)
        }
    }

    @Test
    @MainActor
    func `a page that never goes quiet ends on the budget`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .idle
            options.budget = 6
            let host = PageHost(options: options)
            let started = Date()
            do {
                _ = try await host.load(URL(string: "wait-busy.html", relativeTo: base)!)
                Issue.record("expected a timeout")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.message.contains("idle"))
            }
            #expect(Date().timeIntervalSince(started) < 30)
            #expect(host.facts.httpStatus == 200)
        }
    }
}
