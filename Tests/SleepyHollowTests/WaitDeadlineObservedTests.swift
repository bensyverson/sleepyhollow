import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// A wait's deadline is checked when an answer is *seen*, not only by the timer
/// that races it: an answer the host first sees after the deadline is a
/// timeout, however it got there.
///
/// Every test here is program order, not a margin: the answer is produced only
/// once the deadline is already behind it, so a host that counted it would be
/// reporting a success it never observed in time. `@testable` on purpose — the
/// late answer is injected at the engine's own seams.
@Suite("An answer seen after the deadline is a timeout")
struct WaitDeadlineObservedTests {
    @Test
    @MainActor
    func `a backstop check that answers after the deadline does not settle the race`() async throws {
        let engine: WaitEngine = try #require(WaitEngine(condition: .selector("#late")))
        // Check at once, so the check starts while the deadline is still ahead.
        engine.backstopInterval = 0
        let deadline: DispatchTime = .now() + 1
        let sighting: WaitEngine.Sighting = await engine.race(
            by: deadline,
            accepting: { _ in true },
            checking: {
                // The check is in flight across the deadline — what a starved
                // main actor does to the host's evaluate — and comes back true.
                while DispatchTime.now() <= deadline {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
                return true
            },
        )
        // `.late` when the check started in time; `.never` when a loaded host
        // could not even start it before the deadline. Either is a timeout —
        // the claim is only that a late answer never settles the race.
        #expect(sighting != .inTime)
    }

    @Test
    @MainActor
    func `a push read after the deadline does not settle the race`() async throws {
        let engine: WaitEngine = try #require(WaitEngine(condition: .message("appReady")))
        var continuation: AsyncStream<String>.Continuation?
        engine.pushes = AsyncStream { continuation = $0 }
        let deadline: DispatchTime = .now()
        // Posted only once the deadline has passed.
        while DispatchTime.now() <= deadline {
            await Task.yield()
        }
        continuation?.yield("ready")
        let sighting: WaitEngine.Sighting = await engine.race(by: deadline, accepting: { _ in true })
        #expect(sighting != .inTime)
    }

    @Test
    @MainActor
    func `a waitUntil push read after the deadline does not satisfy the wait`() async {
        var continuation: AsyncStream<String>.Continuation?
        let pushes = AsyncStream<String> { continuation = $0 }
        let deadline: DispatchTime = .now()
        while DispatchTime.now() <= deadline {
            await Task.yield()
        }
        continuation?.yield(#"{"truthy":true,"watch":"w"}"#)
        let outcome: PageHost.WatchOutcome = await PageHost.awaitPush(on: pushes, for: "w", by: deadline)
        #expect(!outcome.satisfied)
        #expect(outcome.heldLate)
    }

    @Test
    @MainActor
    func `a selector already matching is a timeout once the deadline has passed`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions())
            let url = URL(string: "wait-late.html?flip=gate", relativeTo: base)!
            _ = try await host.load(url)
            let engine: WaitEngine = try #require(WaitEngine(condition: .selector("#early")))
            // The navigation spent the whole budget: the first check runs, and
            // answers, after the deadline.
            let deadline: DispatchTime = .now()
            do {
                try await engine.settle(in: host, url: url, by: deadline, budget: 1)
                Issue.record("a match first seen after the deadline must not count as settled")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.message.contains("after the budget ran out"))
            }
        }
    }

    @Test
    @MainActor
    func `a predicate already true is a timeout once the deadline has passed`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions())
            let url = URL(string: "wait-late.html?flip=gate", relativeTo: base)!
            _ = try await host.load(url)
            let engine: WaitEngine = try #require(WaitEngine(condition: .predicate("document.querySelector('#early') !== null")))
            let deadline: DispatchTime = .now()
            do {
                try await engine.settle(in: host, url: url, by: deadline, budget: 1)
                Issue.record("a predicate first seen true after the deadline must not count as settled")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
            }
        }
    }

    @Test
    @MainActor
    func `a quiet window counts only when it closed by the deadline`() {
        let deadline: DispatchTime = .now() + 10
        let window: UInt64 = WaitEngine.nanoseconds(IdleWatch.quietWindow)
        let closedInTime = DispatchTime(uptimeNanoseconds: deadline.uptimeNanoseconds - window)
        let closedLate = DispatchTime(uptimeNanoseconds: deadline.uptimeNanoseconds - window + 1)
        #expect(WaitEngine.quietWindowClosed(quietSince: closedInTime, by: deadline))
        #expect(!WaitEngine.quietWindowClosed(quietSince: closedLate, by: deadline))
    }
}
