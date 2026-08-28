import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("The budget is one ceiling over load and settle")
struct WaitBudgetTests {
    /// The slow page: the server holds the document back by two seconds, so
    /// the navigation spends two seconds of whatever budget the test sets
    /// before the wait even starts. `flip` chooses what makes the page's
    /// `#late` element arrive — `gate` waits on a ``FixtureGate`` the test
    /// opens, a number is a page timer of that many milliseconds.
    private func slowLatePage(base: URL, flip: String) -> URL {
        URL(string: "delay/2000/wait-late.html?flip=\(flip)", relativeTo: base)!
    }

    @Test
    @MainActor
    func `a slow navigation leaves the wait less budget, not a fresh one`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let gate = FixtureGate()
            await gate.install(on: server)
            var options = LoadOptions()
            options.wait = .selector("#late")
            options.budget = 4
            let host = PageHost(options: options)
            // The release is anchored to the page's own request, not to this
            // test's clock: the page reaches the gate as it parses, which is
            // when the navigation's two seconds are spent, so waiting
            // `budget - delay + 0.5` from there lands half a second *after*
            // the one shared deadline and a second and a half *before* the
            // fresh per-phase deadline a regression would grant — however slow
            // the machine made the navigation, since both margins move with
            // it. A sleep can only fire late, so this can never end the wait
            // early; at worst it lands after both deadlines and the test
            // proves less than it wants.
            let opener = Task {
                _ = await gate.awaitRequest()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await gate.open()
            }
            do {
                _ = try await host.load(slowLatePage(base: base, flip: "gate"))
                Issue.record("expected a timeout: only a per-phase budget is still running when the gate opens")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
            }
            await opener.value
        }
    }

    @Test
    @MainActor
    func `the same page settles when the budget covers both phases`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .selector("#late")
            // Generous: under full-suite load the navigation plus the page's
            // own flip can overshoot a small budget by seconds. Only the
            // upper bound matters here — the element does arrive on its own.
            options.budget = 20
            let host = PageHost(options: options)
            _ = try await host.load(slowLatePage(base: base, flip: "300"))
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
            options.budget = 8
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
            var arrived = false
            let deadline = Date().addingTimeInterval(15)
            while !arrived, Date() < deadline {
                arrived = try await host.evaluate("return document.querySelector('#late') !== null;") == "true"
                if !arrived { try? await Task.sleep(nanoseconds: 50_000_000) }
            }
            #expect(arrived, "opening the gate must produce the element the page was waiting on")
        }
    }
}
