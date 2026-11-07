import AppKit
import Foundation
@testable import SleepyHollow
import Testing
import TestSupport
import WebKit

/// `shot` through the compositor: CSS 3D drawn as a browser draws it, and a
/// flat page drawn as `takeSnapshot` draws it.
///
/// The expected figures are the hand-derived geometry of
/// `project/2026-11-06-compositor-capture.md` § 2, which WebKit's own
/// `getBoundingClientRect()` agrees with to 0.1 px and which Chrome draws;
/// `takeSnapshot` misses every one of them (a rectangle where a trapezoid
/// belongs, the back face where the front belongs). Figures are CSS px and
/// scale with `--scale`.
@Suite("ShotOperation compositor rendering")
struct CaptureShotCompositorTests {
    static let blue: PixelGrid.RGB = (42, 82, 168)
    static let green: PixelGrid.RGB = (21, 102, 79)
    static let orange: PixelGrid.RGB = (194, 70, 28)
    static let purple: PixelGrid.RGB = (140, 40, 160)
    static let red: PixelGrid.RGB = (220, 20, 20)

    /// Shoots `fixture` at `size` and `scale` on a default (live) host.
    @MainActor
    private func shoot(
        _ fixture: String,
        size: ViewportSize,
        scale: Int,
        region: ShotRegion = .viewport,
        base: URL,
    ) async throws -> (ShotCapture, PageHost) {
        let host = PageHost(options: LoadOptions(size: size))
        _ = try await host.load(#require(URL(string: fixture, relativeTo: base)))
        let capture = try await ShotOperation(region: region, scale: ShotScale(factor: scale)).render(on: host)
        return (capture, host)
    }

    @Test(arguments: [1, 2])
    @MainActor
    func `a perspective-transformed element renders foreshortened`(scale: Int) async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let (capture, _) = try await shoot("compositor-t3d.html", size: ViewportSize(width: 1000, height: 260), scale: scale, base: base)
            #expect(capture.renderer == .compositor)
            let s = Double(scale)
            let a = PixelGrid(capture.image).shape(of: Self.blue)
            // Expected x 72.0–216.3, y 10.9–197.1; far (left) edge 140.2 tall,
            // near (right) edge 186.2. takeSnapshot: x 64–203, 160 / 160.
            #expect(abs(Double(a.minX) - 72 * s) <= 3 * s, "A minX \(a.minX)")
            #expect(abs(Double(a.maxX) - 216 * s) <= 3 * s, "A maxX \(a.maxX)")
            #expect(abs(Double(a.leftColumn) - 140 * s) <= 4 * s, "A left column \(a.leftColumn)")
            #expect(abs(Double(a.rightColumn) - 186 * s) <= 4 * s, "A right column \(a.rightColumn)")

            // C: perspective() rotateX(45deg): top row 192.8, bottom 256.2.
            let c = PixelGrid(capture.image).shape(of: Self.purple)
            #expect(abs(Double(c.topRow) - 193 * s) <= 4 * s, "C top row \(c.topRow)")
            #expect(abs(Double(c.bottomRow) - 256 * s) <= 5 * s, "C bottom row \(c.bottomRow)")
        }
    }

    @Test(arguments: [1, 2])
    @MainActor
    func `backface-visibility hidden hides a face turned away`(scale: Int) async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let (capture, _) = try await shoot("compositor-t3d.html", size: ViewportSize(width: 1000, height: 260), scale: scale, base: base)
            let pixels = PixelGrid(capture.image)
            #expect(pixels.shape(of: Self.orange).count == 0, "the back face painted")
            // The front face fills its 220×160 cell.
            #expect(pixels.shape(of: Self.green).count >= 200 * 150 * scale * scale)
        }
    }

    @Test
    @MainActor
    func `preserve-3d sorts by depth, not by DOM order`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let (capture, _) = try await shoot("compositor-t3d.html", size: ViewportSize(width: 1000, height: 260), scale: 1, base: base)
            // Inside both boxes: red is nearer and must win; flat, yellow does.
            #expect(PixelGrid(capture.image).matches(856, 104, Self.red))
        }
    }

    @Test
    @MainActor
    func `a CSS3DRenderer-shaped scene lands where getBoundingClientRect says`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let (capture, _) = try await shoot("compositor-css3d.html", size: ViewportSize(width: 1000, height: 500), scale: 1, base: base)
            let pixels = PixelGrid(capture.image)
            // Expected x 400–600, y 200–300; takeSnapshot drew it double size.
            let blue = pixels.shape(of: (0, 150, 255))
            #expect(abs(blue.minX - 400) <= 2 && abs(blue.maxX - 599) <= 2, "blue x \(blue.minX)–\(blue.maxX)")
            #expect(abs(blue.minY - 200) <= 2 && abs(blue.maxY - 299) <= 2, "blue y \(blue.minY)–\(blue.maxY)")
            // Expected x 823.8–871.6; takeSnapshot drew it nowhere.
            let green = pixels.shape(of: (30, 180, 60))
            #expect(green.count > 0)
            #expect(abs(green.minX - 824) <= 3 && abs(green.maxX - 871) <= 3, "green x \(green.minX)–\(green.maxX)")
        }
    }

    @Test(arguments: [1, 2])
    @MainActor
    func `a flat page matches takeSnapshot to anti-aliasing`(scale: Int) async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let (capture, host) = try await shoot("compositor-flat.html", size: ViewportSize(width: 800, height: 500), scale: scale, base: base)
            #expect(capture.renderer == .compositor)
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(x: 0, y: 0, width: 800, height: 500)
            let snapshot = try await host.snapshot(configuration)
            let flat = try #require(ShotCapture.rasterize(snapshot, atPixelSize: CGSize(width: 800 * scale, height: 500 * scale)))
            let difference = try #require(PixelGrid(capture.image).difference(from: PixelGrid(flat)))
            // Measured with the window pinned to sRGB: 0.02% of pixels off by
            // more than 8, none by more than 32 — glyph and corner edges.
            #expect(difference.shareOver8 < 0.002, "\(difference)")
            #expect(difference.over32 == 0, "\(difference)")
        }
    }

    @Test
    @MainActor
    func `a shot taken right after a change shows the change`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(size: ViewportSize(width: 400, height: 300)))
            _ = try await host.load(#require(URL(string: "compositor-swatch.html", relativeTo: base)))
            // Without waiting for the presentation update, 13 of 20 such
            // captures showed the previous frame.
            for step in 1 ... 10 {
                let value = step * 20
                _ = try await host.evaluate("document.getElementById('s').style.background = 'rgb(\(value), 0, 0)'; return 1;")
                let capture = try await ShotOperation().render(on: host)
                #expect(capture.renderer == .compositor)
                let pixel = PixelGrid(capture.image).rgb(200, 150)
                #expect(abs(pixel.red - value) <= 2, "step \(step): read \(pixel.red), wanted \(value)")
            }
        }
    }

    @Test
    @MainActor
    func `an element shot crops the compositor render to the element`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let (capture, _) = try await shoot(
                "compositor-t3d.html", size: ViewportSize(width: 1000, height: 260), scale: 2,
                region: .rect(CGRect(x: 24, y: 24, width: 220, height: 160)), base: base,
            )
            #expect(capture.renderer == .compositor)
            #expect(capture.image.width == 440 && capture.image.height == 320)
            // A's far edge sits 48 CSS px into the stage, its near edge 192.
            let a = PixelGrid(capture.image).shape(of: Self.blue)
            #expect(abs(a.minX - 96) <= 6, "A minX \(a.minX)")
            #expect(abs(a.maxX - 384) <= 6, "A maxX \(a.maxX)")
        }
    }

    /// `capture-banded.html` is 12,982 CSS px tall: at 2× that is 25,964 px,
    /// past Metal's 16,384-px texture limit, so the render has to come in
    /// strips and be stitched.
    @Test
    @MainActor
    func `a 2x full page taller than one texture is rendered whole`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let (capture, _) = try await shoot(
                "capture-banded.html", size: ViewportSize(width: 320, height: 600), scale: 2, region: .fullPage, base: base,
            )
            #expect(capture.renderer == .compositor)
            #expect(capture.image.height >= 25964)
            let pixels = PixelGrid(capture.image)
            // Band k (1,000 CSS px each) is rgb(17k, 40, 90). Sampled every
            // 250 CSS px, so a strip drawn blank, shifted or upside down
            // shows up wherever its seams fall.
            for y in stride(from: 125, to: 12982, by: 250) {
                let band = y / 1000
                #expect(pixels.matches(20, y * 2, (17 * band, 40, 90), tolerance: 3), "y \(y): \(pixels.rgb(20, y * 2))")
            }
        }
    }
}
