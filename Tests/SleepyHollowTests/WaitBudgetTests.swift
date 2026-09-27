import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("The budget is one ceiling over load and settle")
struct WaitBudgetTests {
    /// How long the server holds the slow page's document back: the part of
    /// the budget the navigation provably spends before the wait starts, and
    /// so the extra time a regression granting the wait a fresh budget would
    /// add.
    private static let navigationDelay: TimeInterval = 20

    /// What the budget leaves over the delay, for the rest of the navigation
    /// and the wait together.
    private static let headroom: TimeInterval = 5

    /// How long after the one shared deadline the page's element arrives: the
    /// lateness the host's own deadline may show on a loaded machine and still
    /// end the wait first. "Not hung" scale, since a sleep in this suite has
    /// resumed twelve seconds late; it must stay under ``navigationDelay`` or
    /// the element would beat a regression's fresh deadline too.
    private static let lateness: TimeInterval = 15

    /// The slow page: the server holds the document back by `delay` seconds,
    /// so the navigation spends that much of whatever budget the test sets
    /// before the wait even starts. `flip` chooses what makes the page's
    /// `#late` element arrive — `gate` waits on a ``FixtureGate`` the test
    /// opens, a number is a page timer of that many milliseconds.
    private func slowLatePage(base: URL, delay: TimeInterval, flip: String) -> URL {
        URL(string: "delay/\(Int(delay * 1000))/wait-late.html?flip=\(flip)", relativeTo: base)!
    }

    @Test
    @MainActor
    func `a slow navigation leaves the wait less budget, not a fresh one`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let gate = FixtureGate()
            await gate.install(on: server)
            var options = LoadOptions()
            options.wait = .selector("#late")
            options.budget = Self.navigationDelay + Self.headroom
            let host = PageHost(options: options)
            // The release is anchored to the page's own request, not to this
            // test's clock. The page reaches the gate as it parses, after the
            // server's delay, so the one shared deadline is at most `headroom`
            // past that request and the gate opens `lateness` after it — a
            // margin a host deadline running late under load cannot close.
            // A regression's fresh deadline would sit a whole
            // `navigationDelay` past the request, well after the gate opens.
            // Both sleeps can only fire late: a late server makes the margin
            // wider, and a late opener can only make this test prove less,
            // never fail on a correct host.
            let opener = Task {
                while await gate.requestCount == 0 {
                    if Task.isCancelled { return }
                    try? await Task.sleep(nanoseconds: 25_000_000)
                }
                try? await Task.sleep(nanoseconds: UInt64((Self.headroom + Self.lateness) * 1_000_000_000))
                await gate.open()
            }
            do {
                _ = try await host.load(slowLatePage(base: base, delay: Self.navigationDelay, flip: "gate"))
                Issue.record("expected a timeout: only a per-phase budget is still running when the gate opens")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
            }
            // The outcome is in; nothing is left for the opener to prove.
            opener.cancel()
            await gate.open()
            await opener.value
        }
    }

    @Test
    @MainActor
    func `the same page settles when the budget covers both phases`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .selector("#late")
            // Hang-sized over the delay: under full-suite load the navigation
            // plus the page's own flip can overshoot a small budget by
            // seconds. Only the upper bound matters here — the element does
            // arrive on its own.
            let delay: TimeInterval = 2
            options.budget = delay + TestSupport.livenessBudget
            let host = PageHost(options: options)
            _ = try await host.load(slowLatePage(base: base, delay: delay, flip: "300"))
            let matched: String = try await host.evaluate("return document.querySelector('#late') !== null;")
            #expect(matched == "true")
        }
    }

    /// A regression guard, green before this leaf and required to stay green:
    /// adding a settle phase must not add one to the conditions that never had
    /// one.
    @Test
    @MainActor
    func `wait load still settles on the load event alone`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let gate = FixtureGate()
            await gate.install(on: server)
            var options = LoadOptions()
            options.wait = .load
            options.budget = TestSupport.livenessBudget
            let host = PageHost(options: options)
            // The page's late element waits on a gate this test never opens
            // before it looks: whatever the host's clock did with the load,
            // `--wait-for load` demonstrably did not wait for that element.
            _ = try await host.load(URL(string: "wait-late.html?flip=gate", relativeTo: base)!)
            let matched: String = try await host.evaluate("return document.querySelector('#late') !== null;")
            #expect(matched == "false", "--wait-for load must not wait for anything the page does later")
            // Not vacuous: the page really did have that work outstanding when
            // the load returned. Generously bounded — a liveness check, never
            // a discriminator.
            #expect(await gate.awaitRequest(), "the page never reached the gate, so the assertion above proved nothing")
            // And the gate is what held the element back: opening it produces
            // exactly the element the assertion above found absent. A liveness
            // bound, generous on purpose.
            await gate.open()
            // Looks once more after the deadline: a poll sleep resuming late
            // must not turn an element that did arrive into a failure.
            var arrived = false
            let deadline = Date().addingTimeInterval(TestSupport.livenessBudget)
            while true {
                arrived = try await host.evaluate("return document.querySelector('#late') !== null;") == "true"
                if arrived || Date() >= deadline { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            #expect(arrived, "opening the gate must produce the element the page was waiting on")
        }
    }
}
