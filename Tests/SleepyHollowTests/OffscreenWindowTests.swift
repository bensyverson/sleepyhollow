import AppKit
import Foundation
import SleepyHollow
import Testing
import TestSupport

/// Proves the off-screen window host opens nothing a human can see, and pins
/// what a hosted web view does that a windowless one does not.
///
/// The measurements behind the assertions — rAF rate, transition progress,
/// snapshot density, the ordering and occlusion findings — are recorded in
/// `project/2026-08-28-offscreen-window-host.md`; reproduce them with
/// `swift test --filter OffscreenWindow` (without `--quiet`, so the printed
/// figures show).
@Suite("OffscreenWindow")
struct OffscreenWindowTests {
    /// How long a probe watches the page's own clocks: long enough for a
    /// running rAF chain to be unmistakable, short enough that the gate slot
    /// this test holds while it sleeps does not starve the rest of the suite.
    ///
    /// The assertions are qualitative — frozen or running — on purpose. The
    /// whole suite runs twelve WebKit instances at once (`WebKitGate`), and a
    /// hosted page that ticks ~34 times in 500ms on an idle machine ticks 4
    /// under that load; the rates themselves belong in the finding doc, never
    /// in a threshold.
    private static let probeNanoseconds: UInt64 = 300_000_000

    @Test
    @MainActor
    func `a hosted view is in a window that is on no screen`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            let offscreen = host.ensureOffscreenWindow()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            _ = try await host.execute(ShotOperation())

            #expect(host.webView.window === offscreen.window)
            #expect(offscreen.window.screen == nil)
            for screen in NSScreen.screens {
                #expect(!screen.frame.intersects(offscreen.window.frame))
            }
        }
    }

    @Test
    @MainActor
    func `the app never activates and stays prohibited during a hosted render`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = host.ensureOffscreenWindow()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            #expect(NSApp.isActive == false)
            #expect(NSApp.activationPolicy() == .prohibited)
            _ = try await host.execute(ShotOperation())
            #expect(NSApp.isActive == false)
            #expect(NSApp.activationPolicy() == .prohibited)
            // Nothing this process has ordered in reaches a display.
            for window in NSApp.windows where window.isVisible {
                for screen in NSScreen.screens {
                    #expect(!screen.frame.intersects(window.frame), "\(type(of: window)) is on a screen")
                }
            }
        }
    }

    @Test
    @MainActor
    func `ensureOffscreenWindow is idempotent`() {
        let host = PageHost()
        let first = host.ensureOffscreenWindow()
        let second = host.ensureOffscreenWindow()
        #expect(first === second)
        #expect(host.webView.window === first.window)
        #expect(first.window.frame.origin == OffscreenWindow.parkedOrigin)
    }

    @Test
    @MainActor
    func `resizing grows the window and the hosted view together, still parked`() {
        let host = PageHost()
        let offscreen = host.ensureOffscreenWindow()
        offscreen.resize(to: CGSize(width: 900, height: 4000))
        #expect(host.webView.frame.size == CGSize(width: 900, height: 4000))
        #expect(offscreen.window.frame.size == CGSize(width: 900, height: 4000))
        #expect(offscreen.window.frame.origin == OffscreenWindow.parkedOrigin)
        #expect(offscreen.window.screen == nil)
    }

    @Test
    @MainActor
    func `closing releases the hosted view without destroying it`() {
        let host = PageHost()
        let offscreen = host.ensureOffscreenWindow()
        offscreen.close()
        #expect(host.webView.window == nil)
        offscreen.close()
    }

    @Test
    @MainActor
    func `a hosted host still loads, evaluates and snapshots`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = host.ensureOffscreenWindow()
            let facts = try await host.load(URL(string: "static.html", relativeTo: base)!)
            #expect(facts.httpStatus == 200)
            let title = try await host.evaluate("return document.title;")
            #expect(title.contains("Static"))
            let output = try await host.execute(ShotOperation())
            let dimensions = try #require(pixelDimensions(ofPNG: output.images[0].png))
            #expect(dimensions.width == LoadOptions().size.width)
            #expect(dimensions.height == LoadOptions().size.height)
        }
    }

    @Test
    @MainActor
    func `requestAnimationFrame fires in a hosted view and not in a windowless one`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let url = URL(string: "animation.html", relativeTo: base)!

            let windowless = PageHost()
            _ = try await windowless.load(url)
            try await Task.sleep(nanoseconds: Self.probeNanoseconds)
            let windowlessCount = try await Self.number(windowless, "return window.rafCount;")

            let hosted = PageHost()
            _ = hosted.ensureOffscreenWindow(rendering: .live)
            _ = try await hosted.load(url)
            try await Task.sleep(nanoseconds: Self.probeNanoseconds)
            let hostedCount = try await Self.number(hosted, "return window.rafCount;")

            print("[offscreen] rAF ticks in 300ms — windowless: \(windowlessCount), hosted: \(hostedCount)")
            // The fixture's first tick is a direct call, so 1 means "no frame".
            #expect(windowlessCount <= 1)
            #expect(hostedCount > 1)
        }
    }

    @Test
    @MainActor
    func `the default hosting leaves the page hidden, so the private API is never reached`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let url = URL(string: "static.html", relativeTo: base)!
            let hosted = PageHost()
            _ = hosted.ensureOffscreenWindow()
            _ = try await hosted.load(url)
            #expect(try await hosted.evaluate("return document.visibilityState;") == "\"hidden\"")
        }
    }

    @Test
    @MainActor
    func `a hosted page reports itself visible and a windowless one hidden`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let url = URL(string: "static.html", relativeTo: base)!

            let windowless = PageHost()
            _ = try await windowless.load(url)
            #expect(try await windowless.evaluate("return document.visibilityState;") == "\"hidden\"")

            let hosted = PageHost()
            _ = hosted.ensureOffscreenWindow(rendering: .live)
            _ = try await hosted.load(url)
            #expect(try await hosted.evaluate("return document.visibilityState;") == "\"visible\"")
        }
    }

    @Test
    @MainActor
    func `a CSS transition advances in a hosted view and not in a windowless one`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let url = URL(string: "animation.html", relativeTo: base)!

            let windowless = PageHost()
            _ = try await windowless.load(url)
            try await windowless.evaluate("window.startTransition();", in: .page)
            try await Task.sleep(nanoseconds: Self.probeNanoseconds)
            let windowlessProgress = try await Self.progress(windowless)

            let hosted = PageHost()
            _ = hosted.ensureOffscreenWindow(rendering: .live)
            _ = try await hosted.load(url)
            try await hosted.evaluate("window.startTransition();", in: .page)
            try await Task.sleep(nanoseconds: Self.probeNanoseconds)
            let hostedProgress = try await Self.progress(hosted)

            print(
                "[offscreen] linear opacity transition — windowless: \(windowlessProgress), "
                    + "hosted: \(hostedProgress)",
            )
            // The page reports the time it actually had, because this sleep
            // runs several times over under a full-suite load. What is
            // asserted is that the transition tracked *that* clock.
            #expect(windowlessProgress.opacity == 0)
            #expect(hostedProgress.elapsedMilliseconds > 100)
            #expect(hostedProgress.opacity > 0.02)
            #expect(abs(hostedProgress.opacity - hostedProgress.expectedOpacity) < 0.1)
        }
    }

    @Test
    @MainActor
    func `no window ordering alone makes the page render — only live rendering does`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let url = URL(string: "animation.html", relativeTo: base)!
            var hiddenCounts: [OffscreenWindow.Ordering: Double] = [:]
            for ordering in OffscreenWindow.Ordering.allCases {
                let host = PageHost()
                let window = OffscreenWindow(hosting: host.webView, ordering: ordering, rendering: .hidden)
                _ = try await host.load(url)
                try await Task.sleep(nanoseconds: Self.probeNanoseconds)
                hiddenCounts[ordering] = try await Self.number(host, "return window.rafCount;")
                window.close()
            }
            let live = PageHost()
            let liveWindow = OffscreenWindow(hosting: live.webView, ordering: .back, rendering: .live)
            _ = try await live.load(url)
            try await Task.sleep(nanoseconds: Self.probeNanoseconds)
            let liveCount = try await Self.number(live, "return window.rafCount;")
            liveWindow.close()

            print("[offscreen] rAF ticks in 300ms — hidden by ordering: \(hiddenCounts), live: \(liveCount)")
            for (ordering, count) in hiddenCounts {
                #expect(count <= 1, "\(ordering) rendered without asking for live rendering")
            }
            #expect(liveCount > 1)
        }
    }

    @Test
    @MainActor
    func `hosting does not change the page's device pixel ratio`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let url = URL(string: "static.html", relativeTo: base)!

            let windowless = PageHost()
            _ = try await windowless.load(url)
            let windowlessRatio = try await Self.number(windowless, "return window.devicePixelRatio;")

            let hosted = PageHost()
            let offscreen = hosted.ensureOffscreenWindow()
            _ = try await hosted.load(url)
            let hostedRatio = try await Self.number(hosted, "return window.devicePixelRatio;")
            let backing = Double(offscreen.window.backingScaleFactor)

            print(
                "[offscreen] devicePixelRatio — windowless: \(windowlessRatio), hosted: \(hostedRatio); "
                    + "window backingScaleFactor: \(backing)",
            )
            #expect(hostedRatio == windowlessRatio)
            #expect(hostedRatio == backing)
        }
    }

    /// Reads a numeric page-world expression through the host's JSON transport.
    @MainActor
    private static func number(_ host: PageHost, _ body: String) async throws -> Double {
        let text = try await host.evaluate(body, in: .page)
        return try #require(Double(text))
    }

    /// What `animation.html` reports about its running transition: how opaque
    /// the box is, and how much wall-clock time the transition has had.
    private struct TransitionProgress: Decodable, CustomStringConvertible {
        let opacity: Double
        let elapsedMilliseconds: Double
        let durationMilliseconds: Double

        /// Where a transition running on the wall clock would be by now.
        var expectedOpacity: Double {
            min(1, elapsedMilliseconds / durationMilliseconds)
        }

        var description: String {
            "opacity \(opacity) after \(Int(elapsedMilliseconds))ms of "
                + "\(Int(durationMilliseconds))ms (expected \(expectedOpacity))"
        }
    }

    /// Reads the fixture's transition progress.
    @MainActor
    private static func progress(_ host: PageHost) async throws -> TransitionProgress {
        let text = try await host.evaluate("return window.transitionProgress();", in: .page)
        return try JSONDecoder().decode(TransitionProgress.self, from: Data(text.utf8))
    }
}
