import CoreGraphics
import Foundation
@testable import SleepyHollow
import Testing
import TestSupport
import WebKit

/// ``LoadOptions/Backdrop``: whether the web view paints anything behind the
/// page, and whether the resulting alpha survives the whole shot pipeline.
///
/// `backdrop.html` is the probe: a 1600px-tall body with `background:
/// transparent` and two 200×200 red boxes, one at the top and one at 1400px.
/// Everything between them is page that paints nothing, so the pixels there
/// say which backdrop is in force.
///
/// **This suite is the canary.** `.transparent` is implemented with a private
/// KVC key (`drawsBackground`) because macOS publishes no API for it — the
/// ruling in `project/2026-08-29-woodcase-harness-plan.md`. If a future WebKit
/// stops honouring the key, ``a bare web view accepts the private backdrop
/// key`` fails on the seam and the pixel tests fail on the consequence.
@Suite("Backdrop")
struct BackdropTests {
    private static let page = "backdrop.html"

    /// Where the top box is, and where nothing is painted, in CSS px.
    private static let insideBox = CGPoint(x: 50, y: 50)
    private static let outsideBox = CGPoint(x: 600, y: 500)

    @MainActor
    private func shot(
        _ backdrop: LoadOptions.Backdrop,
        operation: ShotOperation = ShotOperation(),
    ) async throws -> [ShotImage] {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(backdrop: backdrop))
            _ = try await host.load(#require(URL(string: Self.page, relativeTo: base)))
            return try await host.execute(operation).images
        }
    }

    @Test
    @MainActor
    func `a bare web view accepts the private backdrop key`() {
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(
            view.applyBackdrop(.transparent),
            "WKWebView no longer accepts the private drawsBackground key — --transparent is now a lie.",
        )
    }

    @Test
    @MainActor
    func `a transparent backdrop leaves the unpainted page empty`() async throws {
        let images = try await shot(.transparent)
        let first: ShotImage = try #require(images.first)
        let pixels = try #require(decodedImage(ofPNG: first.png))
        let empty = try #require(pixelRGBA(of: pixels, x: Int(Self.outsideBox.x), y: Int(Self.outsideBox.y)))
        #expect(empty.alpha == 0, "the page paints nothing here, so the capture should hold nothing")
        let box = try #require(pixelRGBA(of: pixels, x: Int(Self.insideBox.x), y: Int(Self.insideBox.y)))
        #expect(box.alpha == 255)
        #expect(box.red > 200)
    }

    @Test
    @MainActor
    func `an opaque backdrop paints white behind the page`() async throws {
        let images = try await shot(.opaque)
        let first: ShotImage = try #require(images.first)
        let pixels = try #require(decodedImage(ofPNG: first.png))
        let behind = try #require(pixelRGBA(of: pixels, x: Int(Self.outsideBox.x), y: Int(Self.outsideBox.y)))
        #expect(behind.alpha == 255)
        #expect(behind.red == 255)
        #expect(behind.green == 255)
        #expect(behind.blue == 255)
        let box = try #require(pixelRGBA(of: pixels, x: Int(Self.insideBox.x), y: Int(Self.insideBox.y)))
        #expect(box.alpha == 255)
        #expect(box.red > 200)
    }

    @Test
    @MainActor
    func `opaque is the default`() {
        #expect(LoadOptions().backdrop == .opaque)
    }

    @Test
    @MainActor
    func `alpha survives a scale-2 capture`() async throws {
        let images = try await shot(.transparent, operation: ShotOperation(scale: ShotScale(factor: 2)))
        let image = try #require(images.first)
        let dimensions = try #require(pixelDimensions(ofPNG: image.png))
        #expect(dimensions.width == LoadOptions().size.width * 2)
        let pixels = try #require(decodedImage(ofPNG: image.png))
        let empty = try #require(pixelRGBA(of: pixels, x: Int(Self.outsideBox.x) * 2, y: Int(Self.outsideBox.y) * 2))
        #expect(empty.alpha == 0)
        let box = try #require(pixelRGBA(of: pixels, x: Int(Self.insideBox.x) * 2, y: Int(Self.insideBox.y) * 2))
        #expect(box.alpha == 255)
    }

    @Test
    @MainActor
    func `alpha survives tiling a full-page capture`() async throws {
        let images = try await shot(
            .transparent,
            operation: ShotOperation(region: .fullPage, tile: ShotTile.Height.cssPixels(400)),
        )
        #expect(images.count >= 3, "a 1600px page cut into 400px strips is several tiles")
        // The second strip starts at 360 CSS px and ends at 760 — entirely
        // between the two boxes, so every pixel in it is unpainted page.
        let strip = try #require(images.dropFirst().first)
        let pixels = try #require(decodedImage(ofPNG: strip.png))
        let empty = try #require(pixelRGBA(of: pixels, x: pixels.width / 2, y: pixels.height / 2))
        #expect(empty.alpha == 0)
    }
}
