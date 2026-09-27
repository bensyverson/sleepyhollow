import Foundation
import SleepyHollow
import Testing
import TestSupport
import WebKit

/// Every call the host makes into its page has a deadline the host keeps.
///
/// `callAsyncJavaScript` and `takeSnapshot` are completion handlers with no
/// timeout of their own; a page that holds an evaluated promise forever, or a
/// content process that is not answering, used to suspend the caller for good
/// — a hang with no thread and no stack. Each case builds a page that does not
/// answer and requires a ``SleepyError/Kind/timeout`` instead.
///
/// Every bound asserted here is "this ends", never "this was fast": the
/// budgets under test are short so the test is, and nothing is compared with
/// the elapsed time (`project/2026-08-28-wait-test-timing.md`).
@Suite("PageHost call deadlines")
struct PageHostDeadlineTests {
    /// A body that never answers: it awaits a promise the page keeps reachable.
    /// WebKit fails a call whose promise has been collected ("Completion
    /// handler for function call is no longer reachable"), so an unheld
    /// `new Promise(() => {})` would return an error rather than hang.
    static let neverAnswers: String = "await (window.__never = new Promise(() => {})); return 1;"

    @Test
    @MainActor
    func `an evaluation the page never answers times out at its budget and abandons the host`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(#require(URL(string: "static.html", relativeTo: base)))
            #expect(host.abandonedCall == nil, "a host whose calls have all answered is reusable")
            do {
                _ = try await host.evaluate(Self.neverAnswers, in: .page, budget: 1)
                Issue.record("expected a timeout")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.message.contains("1.0s"), "the timeout must name its budget: \(error.message)")
                #expect(error.message.contains("window.__never"), "the timeout must name the call: \(error.message)")
            }
            let abandoned: PageHost.AbandonedCall = try #require(host.abandonedCall)
            #expect(abandoned.reason == .deadline(1))
        }
    }

    @Test
    @MainActor
    func `an evaluation with no budget of its own takes the host's call budget`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.callBudget = 1
            let host = PageHost(options: options)
            _ = try await host.load(#require(URL(string: "static.html", relativeTo: base)))
            #expect(host.callBudget == 1)
            do {
                _ = try await host.evaluate(Self.neverAnswers, in: .page)
                Issue.record("expected a timeout")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.message.contains("1.0s"), "the timeout must name the host's budget: \(error.message)")
            }
        }
    }

    @Test
    @MainActor
    func `a host with no call budget of its own takes a generous library default`() {
        #expect(PageHost().callBudget == LoadOptions.defaultCallBudget)
        // Load-shaped, not interval-shaped: under the parallel suite a healthy
        // call has taken tens of seconds to answer.
        #expect(LoadOptions.defaultCallBudget >= 60)
    }

    @Test
    @MainActor
    func `cancelling an evaluation the page never answers ends it and abandons the host`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(#require(URL(string: "static.html", relativeTo: base)))
            let call = Task { @MainActor in
                try await host.evaluate("window.__started = true; " + Self.neverAnswers, in: .page, budget: 600)
            }
            // Cancel only once the page is provably inside the call, so the
            // cancellation lands on a call in flight rather than before it.
            while try await host.evaluate("return window.__started === true;", in: .page) != "true" {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            call.cancel()
            await #expect(throws: CancellationError.self) { try await call.value }
            let abandoned: PageHost.AbandonedCall = try #require(host.abandonedCall)
            #expect(abandoned.reason == .cancelled)
        }
    }

    @Test
    @MainActor
    func `a snapshot the page cannot answer in time times out, and its late answer is dropped`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(#require(URL(string: "static.html", relativeTo: base)))
            Self.park(host.webView, forMilliseconds: 4000)
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(x: 0, y: 0, width: 100, height: 100)
            do {
                _ = try await host.snapshot(configuration, budget: 0.5)
                Issue.record("expected a timeout")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.message.contains("snapshot"), "the timeout must name the call: \(error.message)")
            }
            #expect(host.abandonedCall?.reason == .deadline(0.5))
            // The page answers again once the route does; by then the
            // abandoned snapshot's own answer has come back too, and it must
            // be dropped rather than resume a finished call a second time.
            let answer: String = try await host.evaluate("return 2;", budget: 120)
            #expect(answer == "2")
        }
    }

    /// Parks the content process's main thread, without spinning, until a
    /// slow route answers: a synchronous request blocks the page until it
    /// returns.
    ///
    /// Issued straight to the web view, not awaited, so it is ordered ahead
    /// of whatever the test sends next on the same connection, which then has
    /// to wait behind it. Synchronous so the fire-and-forget call is not in an
    /// async context, where the SDK would rather it were awaited.
    @MainActor
    static func park(_ webView: WKWebView, forMilliseconds milliseconds: Int) {
        webView.evaluateJavaScript(
            """
            const request = new XMLHttpRequest();
            request.open('GET', '/delay/\(milliseconds)/static.html', false);
            request.send();
            """,
            completionHandler: nil,
        )
    }

    @Test
    @MainActor
    func `a load whose console count never answers times out and abandons the host`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.callBudget = 1
            let host = PageHost(options: options)
            do {
                _ = try await host.load(#require(URL(string: "console-never-answers.html", relativeTo: base)))
                Issue.record("expected a timeout")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.message.contains("console"), "the timeout must name the call: \(error.message)")
            }
            #expect(host.abandonedCall != nil)
        }
    }
}
