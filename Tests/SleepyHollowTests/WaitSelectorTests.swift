import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("Wait for a selector")
struct WaitSelectorTests {
    @Test
    @MainActor
    func `a selector already present when the load event fires settles at once`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .selector("#early")
            options.budget = 5
            let host = PageHost(options: options)
            // A generous flip: settling at once must beat it even on a machine
            // busy building five agent worktrees.
            let facts: PageFacts = try await host.load(URL(string: "wait-late.html?flip=3000", relativeTo: base)!)
            #expect(facts.httpStatus == 200)
            // The page's own late element is the clock here: a condition
            // already true at didFinish must settle before that arrives.
            let late: String = try await host.evaluate("return document.querySelector('#late') !== null;")
            #expect(late == "false", "a condition true at the load event must not wait a poll cycle")
        }
    }

    @Test
    @MainActor
    func `a selector that appears after the load event settles when it appears`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .selector("#late")
            options.budget = 10
            let host = PageHost(options: options)
            let started = Date()
            _ = try await host.load(URL(string: "wait-late.html", relativeTo: base)!)
            let elapsed: TimeInterval = Date().timeIntervalSince(started)
            #expect(elapsed < 30, "the host's clock ends the wait, not the fixture")
            let matched: String = try await host.evaluate("return document.querySelector('#late') !== null;")
            #expect(matched == "true", "the load must not return before the element exists")
        }
    }

    @Test
    @MainActor
    func `a match with no mutation record behind it is still seen`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .selector("#agree:checked")
            options.budget = 10
            let host = PageHost(options: options)
            _ = try await host.load(URL(string: "wait-checked.html", relativeTo: base)!)
            let matched: String = try await host.evaluate("return document.querySelector('#agree:checked') !== null;")
            #expect(matched == "true")
        }
    }

    @Test
    @MainActor
    func `a selector that never matches ends on the budget with the last state attached`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .selector("#never-in-this-page")
            options.budget = 6
            let host = PageHost(options: options)
            let url = URL(string: "static.html", relativeTo: base)!
            let started = Date()
            do {
                _ = try await host.load(url)
                Issue.record("expected a timeout")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.exitStatus == ExitStatus.timeout)
                #expect(error.message.contains("#never-in-this-page"))
                #expect(error.nextMove != nil)
            }
            let elapsed: TimeInterval = Date().timeIntervalSince(started)
            #expect(elapsed < 30, "the host clock, not the page, ends the wait")
            #expect(host.facts.finalURL?.absoluteString == url.absoluteURL.absoluteString)
            #expect(host.facts.httpStatus == 200, "the page's last known state survives the throw")
        }
    }

    @Test
    @MainActor
    func `an invalid selector is a usage error, not a budget spent waiting`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .selector("#not a { valid selector")
            options.budget = 10
            let host = PageHost(options: options)
            let started = Date()
            do {
                _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
                Issue.record("expected a usage error")
            } catch let error as SleepyError {
                #expect(error.kind == .usage)
                #expect(error.exitStatus == ExitStatus.usage)
            }
            #expect(Date().timeIntervalSince(started) < 30, "an invalid selector is invalid immediately")
        }
    }
}
