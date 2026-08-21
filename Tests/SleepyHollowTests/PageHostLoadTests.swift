import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("PageHost load pipeline")
struct PageHostLoadTests {
    @Test
    @MainActor
    func `loads a fixture and reports final URL, status and no console errors`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            let url = URL(string: "static.html", relativeTo: base)!
            let facts: PageFacts = try await host.load(url)
            #expect(facts.finalURL?.absoluteString == url.absoluteURL.absoluteString)
            #expect(facts.httpStatus == 200)
            #expect(facts.consoleErrorCount == 0)
            #expect(facts.dialogs.isEmpty)
            #expect(host.facts == facts)
        }
    }

    @Test
    @MainActor
    func `a missing page reports its 404 status rather than failing`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            let facts: PageFacts = try await host.load(URL(string: "no-such-page.html", relativeTo: base)!)
            #expect(facts.httpStatus == 404)
        }
    }

    @Test
    @MainActor
    func `an unroutable port is a load failure with a next move`() async throws {
        let host = PageHost()
        do {
            _ = try await host.load(#require(URL(string: "http://127.0.0.1:65533/nothing")))
            Issue.record("expected a load failure")
        } catch let error as SleepyError {
            #expect(error.kind == .loadFailure)
            #expect(error.exitStatus == ExitStatus.loadFailure)
            #expect(error.nextMove != nil)
        }
    }

    @Test
    @MainActor
    func `a hanging load becomes a timeout well inside the fixture's delay`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.budget = 1
            let host = PageHost(options: options)
            let url = URL(string: "delay/600000/static.html", relativeTo: base)!
            let started = Date()
            do {
                _ = try await host.load(url)
                Issue.record("expected a timeout")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.exitStatus == ExitStatus.timeout)
            }
            let elapsed: TimeInterval = Date().timeIntervalSince(started)
            #expect(elapsed < 20, "the host clock, not the fixture, must end the load")
        }
    }

    @Test
    @MainActor
    func `a second load while one is in flight is a usage error, not a lost continuation`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.budget = 2
            let host = PageHost(options: options)
            let slow = URL(string: "delay/600000/static.html", relativeTo: base)!
            async let first: PageFacts = host.load(slow)
            // Let the first navigation actually start before racing it.
            try await Task.sleep(nanoseconds: 200_000_000)
            do {
                _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
                Issue.record("expected a usage error")
            } catch let error as SleepyError {
                #expect(error.kind == .usage)
            }
            // The first load must still reach its own timeout rather than hanging.
            do {
                _ = try await first
                Issue.record("expected the first load to time out")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
            }
        }
    }

    @Test
    @MainActor
    func `the default budget is the Core default when none is given`() {
        let host = PageHost()
        #expect(host.budget == LoadOptions.defaultBudget)
    }
}
