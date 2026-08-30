import Foundation
import SleepyHollow
import Testing
import TestSupport

/// The per-call budget: one host, callers with different clocks.
///
/// Every assertion here is an upper bound — "this ends, and the message names
/// the number that ended it" — never a claim that the host beat a page timer
/// (`project/2026-08-28-wait-test-timing.md`).
@Suite("PageHost per-call budget")
struct PageHostBudgetTests {
    @Test
    @MainActor
    func `a per-call budget bounds the load and the timeout names it`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            // Far longer than the call's own budget: whatever ends this load,
            // it is not the host's default.
            options.budget = 600
            let host = PageHost(options: options)
            let url: URL = try #require(URL(string: "delay/600000/static.html", relativeTo: base))
            do {
                _ = try await host.load(url, budget: 1)
                Issue.record("expected a timeout")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(
                    error.message.contains("1.0s"),
                    "the timeout must name the budget that applied: \(error.message)",
                )
                #expect(!error.message.contains("600.0s"))
            }
            // The override is per call: the host's own default is untouched.
            #expect(host.budget == 600)
        }
    }

    @Test
    @MainActor
    func `no per-call budget falls back to the host's own`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.budget = 1
            let host = PageHost(options: options)
            let url: URL = try #require(URL(string: "delay/600000/static.html", relativeTo: base))
            do {
                _ = try await host.load(url, budget: nil)
                Issue.record("expected a timeout")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.message.contains("1.0s"), "the message must name the host's budget: \(error.message)")
            }
        }
    }

    @Test
    @MainActor
    func `a host with no budget of its own falls back to the library default`() {
        #expect(PageHost().budget == LoadOptions.defaultBudget)
    }

    @Test
    @MainActor
    func `a generous per-call budget outlives a host built with a hopeless one`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.budget = 0.001
            let host = PageHost(options: options)
            let url: URL = try #require(URL(string: FixturePage.staticText.fileName, relativeTo: base))
            let facts: PageFacts = try await host.load(url, budget: 60)
            #expect(facts.httpStatus == 200)
        }
    }
}
