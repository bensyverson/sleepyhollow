import AppKit
import Foundation
import SleepyHollow
import Testing
import TestSupport

/// A host's page lives in a live, sRGB off-screen window by default (leaf
/// `GzK3Rl`): WebKit treats it as visible, so animation time and nested
/// timers run as on a display, and its pixels are painted in sRGB whatever
/// display the Mac has.
///
/// The ruling is `project/2026-11-06-true-3d-shots.md` § Ruling on the
/// capture path; the measurements are `project/2026-11-06-compositor-capture.md`
/// questions 6 and 8.
@Suite("Live hosting")
struct LiveHostingTests {
    @Test
    @MainActor
    func `a default host is parked in a live off-screen window`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            let window = try #require(host.webView.window)
            #expect(window.screen == nil)
            #expect(window.frame.origin == OffscreenWindow.parkedOrigin)
            _ = try await host.load(#require(URL(string: "static.html", relativeTo: base)))
            #expect(try await host.evaluate("return document.visibilityState;") == "\"visible\"")
        }
    }

    /// Sessions are hosted live too: a session is where an agent clicks
    /// something and checks what the page did next, which is exactly where a
    /// frozen animation reads as a broken page (job issue `ND4YmR`).
    @Test
    @MainActor
    func `a session's page is hosted live, in a key window`() throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let host = try SessionHost(
            name: #require(SessionName("live")),
            url: nil,
            registry: SessionRegistry(root: root),
        )
        let window = try #require(host.page.webView.window)
        #expect(window.isKeyWindow)
        #expect(window.colorSpace == NSColorSpace.sRGB)
    }

    @Test
    @MainActor
    func `a windowless host stays out of every window`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(hosting: .windowless)
            #expect(host.webView.window == nil)
            _ = try await host.load(#require(URL(string: "static.html", relativeTo: base)))
            #expect(try await host.evaluate("return document.visibilityState;") == "\"hidden\"")
        }
    }

    /// Without the pin WebKit paints its tiles in the main display's color
    /// space (Display P3 on a recent Mac), and a compositor capture drifts by
    /// up to 29 levels (`project/2026-11-06-compositor-capture.md` § 2).
    /// `takeSnapshot` converts correctly either way, so the window's color
    /// space itself is what is pinned and asserted.
    @Test
    @MainActor
    func `the host window paints in sRGB`() throws {
        let host = PageHost()
        let window = try #require(host.webView.window)
        #expect(window.colorSpace == NSColorSpace.sRGB)
    }

    /// The wait engine's page-side backstop is exactly this shape — a
    /// `setTimeout(check, 16)` chain — so this is also job issue `PFrL42`'s
    /// regression test: on a hidden page the chain is aligned to one second
    /// from about its tenth tick.
    @Test
    @MainActor
    func `a nested setTimeout chain keeps its cadence past its tenth tick`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let options = LoadOptions(wait: .selector("body[data-done]"), budget: TestSupport.livenessBudget)
            let host = PageHost(options: options)
            _ = try await host.load(#require(URL(string: "timer-chain.html", relativeTo: base)))
            let json = try await host.evaluate("return window.timerGaps;", in: .page)
            let gaps = try JSONDecoder().decode([Double].self, from: Data(json.utf8))
            try #require(gaps.count == 40)
            let late = gaps[10...].sorted()
            let median = late[late.count / 2]
            print("[live] nested timer gaps past tick 10 — median \(Int(median)) ms, max \(Int(late.last ?? 0)) ms")
            // Throttled, every late gap is ~1000 ms; live, they are 16–20 ms.
            // The median shrugs off a few gaps a loaded machine stretches.
            #expect(median < 250)
        }
    }

    @Test
    @MainActor
    func `a released host closes its window`() async throws {
        weak var released: NSWindow?
        do {
            let host = PageHost()
            released = host.webView.window
            #expect(released != nil)
        }
        // The close is hopped to the main actor from the host's deinit.
        for _ in 0 ..< 50 where released?.isVisible == true {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(released?.isVisible != true)
    }
}
