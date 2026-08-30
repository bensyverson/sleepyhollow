import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

@Suite("Wait for a JavaScript predicate")
struct WaitPredicateTests {
    /// Waits — generously — for the engine's one load-event check to have run.
    ///
    /// `@testable` on purpose: `probeCount` is the evidence that the *page*,
    /// not a host poll, settled the wait.
    @MainActor
    private static func awaitFirstProbe(_ engine: WaitEngine, timeout: TimeInterval = 30) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while engine.probeCount == 0, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return engine.probeCount > 0
    }

    @Test
    @MainActor
    func `the page's push settles a predicate with no host poll behind it`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let gate = FixtureGate()
            await gate.install(on: server)
            var options = LoadOptions()
            options.wait = .predicate("window.sleepyReady === true")
            options.budget = 30
            let host = PageHost(options: options)
            let engine: WaitEngine = try #require(host.waiter)
            // The host's periodic re-check is pushed past any run of this test:
            // whatever ends the wait, it is not the host asking again.
            engine.backstopInterval = 3600
            let url = URL(string: "wait-late.html?flip=gate", relativeTo: base)!
            let load = Task { @MainActor in try await host.load(url) }
            // Program order, not a margin: the host's one check has completed
            // and the page is still held at the gate, so the predicate was
            // false when the host looked — and the host will not look again.
            #expect(await Self.awaitFirstProbe(engine), "the host never ran its load-event check")
            #expect(engine.probeCount == 1)
            #expect(await gate.awaitRequest(), "the page never reached the gate, so the assertion above proved nothing")
            await gate.open()
            _ = try await load.value
            #expect(engine.probeCount == 1, "only the load-event check ran host-side; the page pushed the rest")
        }
    }

    @Test
    @MainActor
    func `a predicate already true at the load event settles at once`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let gate = FixtureGate()
            await gate.install(on: server)
            var options = LoadOptions()
            options.wait = .predicate("window.sleepyStage === 'early'")
            options.budget = 5
            let host = PageHost(options: options)
            _ = try await host.load(URL(string: "wait-late.html?flip=gate", relativeTo: base)!)
            // The page moves to 'late' only when the test opens the gate, and
            // it has not: settling on the condition that was already true is
            // program order here, not a race with the page's timer.
            let stage: String = try await host.evaluate("return window.sleepyStage;", in: .page)
            #expect(stage == "\"early\"", "a predicate true at the load event must not wait for the page's later work")
            // Not vacuous: the page really did have that work outstanding.
            #expect(await gate.awaitRequest(), "the page never reached the gate, so the assertion above proved nothing")
            await gate.open()
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
