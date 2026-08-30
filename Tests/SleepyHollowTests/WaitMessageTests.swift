import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("Wait for a message the page posts")
struct WaitMessageTests {
    @Test
    @MainActor
    func `a load settles when the page posts to the named handler`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .message("sleepyReady")
            options.budget = 30
            let host = PageHost(options: options)
            let started = Date()
            _ = try await host.load(URL(string: "wait-message.html", relativeTo: base)!)
            #expect(Date().timeIntervalSince(started) < 60, "the host's clock ends the wait, not the fixture")
            // Not a margin: the page sets this flag on the line after the post,
            // so a load that returned before the push would read false.
            let posted: String = try await host.evaluate("return window.sleepyPosted;", in: .page)
            #expect(posted == "true", "the load must not return before the page posted")
        }
    }

    @Test
    @MainActor
    func `a message that never arrives ends on the budget, naming the handler`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .message("sleepyNeverPosts")
            options.budget = 6
            let host = PageHost(options: options)
            let started = Date()
            do {
                _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
                Issue.record("expected a timeout")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.message.contains("sleepyNeverPosts"), "the timeout must name the handler waited on")
            }
            #expect(Date().timeIntervalSince(started) < 30)
        }
    }

    @Test
    @MainActor
    func `a handler name that is not an identifier is a usage error`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.wait = .message("not a handler")
            options.budget = 6
            let host = PageHost(options: options)
            do {
                _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
                Issue.record("expected a usage error")
            } catch let error as SleepyError {
                #expect(error.kind == .usage, "a name no page can post to never becomes true; a longer budget cannot fix it")
                #expect(error.message.contains("not a handler"))
            }
        }
    }

    @Test
    @MainActor
    func `the tool's own handler names are refused, not waited on`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            // The console capture posts on this one all through a load: waiting
            // on it would settle on the first console line the page emitted.
            options.wait = .message(PageHost.consoleMessageName)
            options.budget = 6
            let host = PageHost(options: options)
            do {
                _ = try await host.load(URL(string: "console-errors.html", relativeTo: base)!)
                Issue.record("expected a usage error")
            } catch let error as SleepyError {
                #expect(error.kind == .usage)
                #expect(error.message.contains(PageHost.consoleMessageName))
            }
        }
    }

    @Test
    func `a handler name is a plain identifier or nothing`() {
        #expect(WaitCondition.isValidMessageName("ready"))
        #expect(WaitCondition.isValidMessageName("__READY__"))
        #expect(WaitCondition.isValidMessageName("$ready2"))
        #expect(!WaitCondition.isValidMessageName(""))
        #expect(!WaitCondition.isValidMessageName("2ready"))
        #expect(!WaitCondition.isValidMessageName("app ready"))
        #expect(!WaitCondition.isValidMessageName("app.ready"))
        #expect(!WaitCondition.isValidMessageName("app-ready"))
    }
}
