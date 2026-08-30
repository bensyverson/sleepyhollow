import CoreGraphics
import Foundation
import SleepyHollow
import Testing
import TestSupport

// The import above is deliberately not `@testable`: this suite is the proof
// that an embedder outside the module can reach the CGImage without decoding
// a PNG.

/// `ShotOperation.render(on:)` — the un-encoded path.
///
/// `execute(on:)` hands back PNG bytes because that is what crosses the wire;
/// a host-side embedder that only wants pixels would otherwise encode and
/// immediately decode them again. This suite pins that `render(on:)` and the
/// ``ShotCapture`` it returns are public enough to skip that round trip.
@Suite("ShotOperation.render")
struct CaptureShotRenderTests {
    @Test
    @MainActor
    func `render hands an embedder a CGImage with no PNG round trip`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(size: ViewportSize(width: 400, height: 300)))
            _ = try await host.load(#require(URL(string: "capture-breakpoint.html", relativeTo: base)))

            let capture: ShotCapture = try await ShotOperation().render(on: host)
            let image: CGImage = capture.image
            #expect(image.width == 400)
            #expect(image.height == 300)
            #expect(capture.rect == CGRect(x: 0, y: 0, width: 400, height: 300))
            #expect(capture.scale == 1)
            #expect(Double(capture.pixelsPerCSSPixel) == 1)
            #expect(capture.pixelSize == CGSize(width: 400, height: 300))
            let probe = try #require(pixelColor(of: image, x: 150, y: 150))
            #expect(probe.red > 200, "400 CSS px is below the fixture's breakpoint")
        }
    }

    @Test
    @MainActor
    func `render at scale 2 doubles the pixels and leaves the rect in CSS px`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(size: ViewportSize(width: 400, height: 300)))
            _ = try await host.load(#require(URL(string: "capture-breakpoint.html", relativeTo: base)))

            let capture: ShotCapture = try await ShotOperation(scale: ShotScale(factor: 2)).render(on: host)
            #expect(capture.image.width == 800)
            #expect(capture.image.height == 600)
            #expect(capture.rect == CGRect(x: 0, y: 0, width: 400, height: 300))
            #expect(Double(capture.pixelsPerCSSPixel) == 2)
            // The same capture still encodes, for a caller that wants both.
            #expect(try capture.encoded().pixelSize == CGSize(width: 800, height: 600))
        }
    }
}
