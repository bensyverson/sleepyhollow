import CoreGraphics
import Foundation
import SleepyHollow
import Testing
import TestSupport

/// `PageHost.resize(to:)`: the viewport as a live property of an open page,
/// not something fixed when the host was built.
///
/// `capture-breakpoint.html` is the probe: its `#probe` block is blue at 1000
/// CSS px and wider and red below, so one page proves both halves — the media
/// query re-evaluates, and the pixels the next shot returns follow.
@Suite("PageHost viewport")
struct PageHostViewportTests {
    /// `matchMedia` as the page sees it right now.
    @MainActor
    private func isNarrow(_ host: PageHost) async throws -> Bool {
        try await host.evaluate("return window.matchMedia('(max-width: 999px)').matches;") == "true"
    }

    @Test
    @MainActor
    func `a fresh host reports the viewport its options named`() {
        let host = PageHost(options: LoadOptions(size: ViewportSize(width: 390, height: 844)))
        #expect(host.viewport == ViewportSize(width: 390, height: 844))
        #expect(PageHost().viewport == ViewportSize.default)
    }

    @Test
    @MainActor
    func `resize re-evaluates the page's media queries and moves the next shot's pixels`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(size: ViewportSize(width: 1280, height: 800)))
            _ = try await host.load(#require(URL(string: "capture-breakpoint.html", relativeTo: base)))
            #expect(try await isNarrow(host) == false)

            host.resize(to: ViewportSize(width: 390, height: 844))
            #expect(host.viewport == ViewportSize(width: 390, height: 844))
            #expect(try await isNarrow(host) == true)

            let shot = try await host.execute(ShotOperation())
            let image = try #require(shot.images.first)
            let dimensions = try #require(pixelDimensions(ofPNG: image.png))
            #expect(dimensions.width == 390)
            #expect(dimensions.height == 844)
            let pixels = try #require(decodedImage(ofPNG: image.png))
            let probe = try #require(pixelColor(of: pixels, x: 150, y: 150))
            #expect(probe.red > 200, "below the breakpoint the probe is red")
            #expect(probe.blue < 50)
        }
    }

    @Test
    @MainActor
    func `resize follows through to a parked offscreen window`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(size: ViewportSize(width: 1280, height: 800)))
            let window = host.ensureOffscreenWindow()
            _ = try await host.load(#require(URL(string: "capture-breakpoint.html", relativeTo: base)))
            #expect(try await isNarrow(host) == false)

            host.resize(to: ViewportSize(width: 480, height: 640))
            #expect(Double(window.window.frame.width) == 480)
            #expect(Double(window.window.frame.height) == 640)
            #expect(Double(host.webView.frame.width) == 480)
            #expect(Double(host.webView.frame.height) == 640)
            #expect(try await isNarrow(host) == true)
            // Still parked: resizing must not walk the window onto a screen.
            #expect(window.window.screen == nil)
        }
    }

    @Test
    @MainActor
    func `resize without a window still moves the web view`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(size: ViewportSize(width: 1280, height: 800)))
            _ = try await host.load(#require(URL(string: "capture-breakpoint.html", relativeTo: base)))
            host.resize(to: ViewportSize(width: 480, height: 640))
            #expect(Double(host.webView.frame.width) == 480)
            #expect(Double(host.webView.frame.height) == 640)
            #expect(host.webView.window == nil)
            #expect(try await isNarrow(host) == true)
        }
    }
}
