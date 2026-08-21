import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("The budget is one ceiling over load and settle")
struct WaitBudgetTests {
    /// The page's element appears 300ms after *its* parse, which the server
    /// holds back by 900ms. A budget of one second therefore reaches the load
    /// event with almost nothing left — and a budget spent per phase would
    /// have a second full second to find the element.
    private func slowLatePage(base: URL) -> URL {
        URL(string: "delay/900/wait-late.html", relativeTo: base)!
    }

    @Test
    @MainActor
    func `a slow navigation leaves the wait less budget, not a fresh one`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .selector("#late")
            options.budget = 1
            let host = PageHost(options: options)
            let started = Date()
            do {
                _ = try await host.load(slowLatePage(base: base))
                Issue.record("expected a timeout: the navigation spent almost the whole budget")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
            }
            #expect(Date().timeIntervalSince(started) < 10, "and it must still end on the host's clock")
        }
    }

    @Test
    @MainActor
    func `the same page settles when the budget covers both phases`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .selector("#late")
            options.budget = 8
            let host = PageHost(options: options)
            _ = try await host.load(slowLatePage(base: base))
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
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .load
            options.budget = 8
            let host = PageHost(options: options)
            _ = try await host.load(URL(string: "wait-late.html", relativeTo: base)!)
            let matched: String = try await host.evaluate("return document.querySelector('#late') !== null;")
            #expect(matched == "false", "--wait-for load must not wait for anything the page does later")
        }
    }
}
