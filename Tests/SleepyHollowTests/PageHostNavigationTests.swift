import Foundation
import SleepyHollow
import Testing
import TestSupport

/// Telling a real navigation from a same-document swap (2026-08-30 Woodcase
/// report, item 5). The pages are served over HTTP with no `unload` handler,
/// the two conditions WebKit's back-forward cache needs.
@Suite("PageHost navigation signal")
struct PageHostNavigationTests {
    private static let timeoutBudget: TimeInterval = 6

    /// Two pages; each records in `window.__shows` how it was shown, so a test
    /// can prove a back navigation really was restored from the cache.
    private static func page(_ title: String) -> FixtureResponse {
        let html = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(title)</title></head>
        <body><h1>\(title)</h1>
        <script>
          window.__shows = [];
          addEventListener('pageshow', (event) => { window.__shows.push(event.persisted ? 'restored' : 'fresh'); });
        </script>
        </body></html>
        """
        return FixtureResponse(status: 200, contentType: .html, body: Data(html.utf8))
    }

    @MainActor
    private static func serve(_ server: FixtureServer) async {
        await server.register(path: "/nav-a.html") { _ in page("Page A") }
        await server.register(path: "/nav-b.html") { _ in page("Page B") }
    }

    @Test
    @MainActor
    func `the load itself is the first navigation`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            await Self.serve(server)
            let host = PageHost()
            #expect(host.navigationCount == 0)
            _ = try await host.load(URL(string: "nav-a.html", relativeTo: base)!)
            #expect(host.navigationCount == 1)
        }
    }

    @Test
    @MainActor
    func `a page-initiated navigation counts and can be awaited`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            await Self.serve(server)
            let host = PageHost()
            _ = try await host.load(URL(string: "nav-a.html", relativeTo: base)!)
            let before: Int = host.navigationCount
            try await host.evaluate("location.href = 'nav-b.html'; return null;", in: .page)
            let navigation: PageHost.Navigation = try await host.waitForNavigation(
                after: before,
                budget: TestSupport.livenessBudget,
            )
            #expect(navigation.number == before + 1)
            #expect(navigation.url?.path == "/nav-b.html")
            #expect(host.navigationCount == before + 1)
        }
    }

    @Test
    @MainActor
    func `pushState and hash changes are not navigations`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            await Self.serve(server)
            let host = PageHost()
            _ = try await host.load(URL(string: "nav-a.html", relativeTo: base)!)
            let before: Int = host.navigationCount
            try await host.evaluate(
                "history.pushState({}, '', 'swapped'); location.hash = 'section'; return null;",
                in: .page,
            )
            #expect(host.webView.url?.fragment == "section", "the swaps happened")
            // A real navigation after the swaps, so their absence from the
            // count is program order rather than a race with a late callback.
            try await host.evaluate("location.href = '/nav-b.html'; return null;", in: .page)
            let navigation: PageHost.Navigation = try await host.waitForNavigation(
                after: before,
                budget: TestSupport.livenessBudget,
            )
            #expect(navigation.number == before + 1, "only the real navigation counted")
            #expect(navigation.url?.path == "/nav-b.html")
        }
    }

    @Test
    @MainActor
    func `a back navigation restored from the back-forward cache counts`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            await Self.serve(server)
            let host = PageHost()
            _ = try await host.load(URL(string: "nav-a.html", relativeTo: base)!)
            // The self-stamped marker Woodcase relied on: it survives a cache
            // restore, which is exactly why it cannot see one.
            try await host.evaluate("window.__marker = 'stamped'; return null;", in: .page)
            try await host.evaluate("location.href = 'nav-b.html'; return null;", in: .page)
            _ = try await host.waitForNavigation(after: 1, budget: TestSupport.livenessBudget)
            try await host.waitUntil("document.readyState === 'complete'", budget: TestSupport.livenessBudget)

            try await host.evaluate("history.back(); return null;", in: .page)
            let back: PageHost.Navigation = try await host.waitForNavigation(
                after: 2,
                budget: TestSupport.livenessBudget,
            )
            #expect(back.number == 3)
            #expect(back.url?.path == "/nav-a.html")
            try await host.waitUntil("window.__shows.length === 2", budget: TestSupport.livenessBudget)
            let shows: [String] = try await host.evaluate("return window.__shows;", as: [String].self, in: .page)
            let marker: String? = try await host.evaluate("return window.__marker ?? null;", as: String?.self, in: .page)
            try #require(shows == ["fresh", "restored"], "WebKit did not restore the page from its cache: \(shows)")
            #expect(marker == "stamped", "a cache restore keeps the old JS heap")
        }
    }

    @Test
    @MainActor
    func `a navigation that already happened ends the wait at once`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            await Self.serve(server)
            let host = PageHost()
            _ = try await host.load(URL(string: "nav-a.html", relativeTo: base)!)
            let navigation: PageHost.Navigation = try await host.waitForNavigation(
                after: 0,
                budget: TestSupport.livenessBudget,
            )
            #expect(navigation.number == 1)
        }
    }

    @Test
    @MainActor
    func `no navigation within the budget times out with a teaching error`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            await Self.serve(server)
            let host = PageHost()
            _ = try await host.load(URL(string: "nav-a.html", relativeTo: base)!)
            do {
                _ = try await host.waitForNavigation(after: host.navigationCount, budget: Self.timeoutBudget)
                Issue.record("expected a timeout")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.message.contains("6"))
                #expect(error.nextMove?.contains("pushState") == true, "names the same-document case")
            }
        }
    }
}
