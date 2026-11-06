import AppKit
import Foundation
import SleepyHollow
import Testing
import TestSupport

/// A full-page shot on a host parked in a window (job issue `brc0C`).
///
/// `ShotOperation.render` grows the web view to the document's height before
/// it captures. A view in a window is clipped by that window, so the window
/// has to grow with it — and shrink back after — or everything past the
/// viewport comes back blank.
@Suite("ShotOperation full page in a window")
struct CaptureShotWindowedFullPageTests {
    @Test
    @MainActor
    func `a full-page shot is not clipped by the host window`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(size: ViewportSize(width: 400, height: 300)), hosting: .windowless)
            // Live, as every verb's host is: a hidden page renders the whole
            // grown view on demand, so only a live one shows the clip.
            let offscreen = host.ensureOffscreenWindow(rendering: .live)
            _ = try await host.load(#require(URL(string: "capture-tall.html", relativeTo: base)))

            let capture = try await ShotOperation(region: .fullPage, scale: ShotScale(factor: 1)).render(on: host)
            // 3,000 px of body plus the paragraph's collapsed top margin.
            #expect(capture.image.height >= 3000)
            // capture-tall.html's #ff3366 target sits at (100, 2400), 200×150.
            let target = try #require(pixelColor(of: capture.image, x: 200, y: 2475))
            #expect(target.red > 200 && target.green < 120, "target pixel \(target)")

            // The viewport is put back, window and view together.
            #expect(offscreen.window.frame.size == CGSize(width: 400, height: 300))
            #expect(host.webView.frame.size == CGSize(width: 400, height: 300))
            #expect(offscreen.window.frame.origin == OffscreenWindow.parkedOrigin)
        }
    }
}
