import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("Wait for a JavaScript predicate")
struct WaitPredicateTests {
    @Test
    @MainActor
    func `a predicate already true at the load event settles at once`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .predicate("window.sleepyStage === 'early'")
            options.budget = 5
            let host = PageHost(options: options)
            // A generous flip: settling at once must beat it even on a loaded
            // machine.
            _ = try await host.load(URL(string: "wait-late.html?flip=3000", relativeTo: base)!)
            // The page moves to 'late' after its flip delay; settling on the
            // condition that was already true has to beat that.
            let stage: String = try await host.evaluate("return window.sleepyStage;", in: .page)
            #expect(stage == "\"early\"", "a predicate true at the load event must not cost a poll cycle")
        }
    }

    @Test
    @MainActor
    func `a predicate that turns true later ends the wait when it does`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            // Generous on purpose: the budget is free on the green path, and a
            // stingy one is what let full-suite contention flake this test.
            options.wait = .predicate("window.sleepyReady === true")
            options.budget = 30
            let host = PageHost(options: options)
            let started = Date()
            _ = try await host.load(URL(string: "wait-late.html", relativeTo: base)!)
            let elapsed: TimeInterval = Date().timeIntervalSince(started)
            #expect(elapsed < 60, "the host's clock ends the wait, not the fixture")
            let stage: String = try await host.evaluate("return window.sleepyStage;", in: .page)
            #expect(stage == "\"late\"", "the load must not return before the page said it was ready")
        }
    }

    @Test
    @MainActor
    func `a predicate that never becomes true ends on the budget`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .predicate("window.neverSet === 42")
            options.budget = 6
            let host = PageHost(options: options)
            let started = Date()
            do {
                _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
                Issue.record("expected a timeout")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.message.contains("window.neverSet === 42"))
            }
            #expect(Date().timeIntervalSince(started) < 30)
        }
    }

    @Test
    @MainActor
    func `a predicate that throws every time says so in the timeout`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .predicate("window.missing.deep.value")
            options.budget = 6
            let host = PageHost(options: options)
            do {
                _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
                Issue.record("expected a timeout")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.message.contains("TypeError"), "the JS failure is what the agent needs to see")
            }
        }
    }
}
