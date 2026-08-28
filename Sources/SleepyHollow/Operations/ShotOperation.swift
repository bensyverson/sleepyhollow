import AppKit
import Foundation
import WebKit

/// `sleepy shot` — a PNG of a ``ShotRegion``: the viewport, the whole
/// scrollable page, one element's box, or an explicit document rect.
///
/// The default capture is viewport-shaped: whatever ``LoadOptions/size`` the
/// host was built with. Every other region needs content the viewport-sized
/// backing store may never have rasterized — a headless `WKWebView` only
/// reliably paints what's within its current `frame` — so they temporarily
/// grow the frame to the document's full scroll height before capturing and
/// restore it after. This is the fix for the exact bug the vision doc names:
/// a control 2,400px down a page invisible to a viewport-shaped shot.
///
/// Execution is a pipeline: **render** the region to a ``ShotCapture`` at
/// ``scale`` device pixels per CSS px (the crop *is* the region), then
/// **tile** it into strips, **fit** each strip to a pixel budget, and finally
/// **encode** every capture to a ``ShotImage``.
/// Each stage is a pure function over captures, and none changes what
/// another means: `--scale` measures in device px per CSS px, `--tile`
/// measures in CSS px of the page, `--max-size`
/// measures in pixels of the file. The output is a list even for a plain
/// shot, because tiles and contact sheets are many images from one operation
/// and the wire shape should not change when they arrive.
public struct ShotOperation: ExecutablePageOperation {
    /// The captures a shot produced, in order.
    public struct Output: Friendly {
        /// Every encoded image, with its rect and scale. A plain shot has
        /// exactly one.
        public let images: [ShotImage]

        /// Wraps the captures.
        public init(images: [ShotImage]) {
            self.images = images
        }
    }

    /// The wire identifier.
    public static let kind: String = "shot"

    /// What to capture.
    public let region: ShotRegion

    /// Device pixels per CSS px in the rendered raster (`--scale`). The page
    /// is laid out identically at every density; only the pixels differ.
    public let scale: ShotScale

    /// The pixel budget each output image is fitted to, when one was asked
    /// for (`--max-size`).
    public let fit: ShotFit?

    /// How tall to cut the capture's strips, when tiling was asked for
    /// (`--tile`).
    public let tile: ShotTile.Height?

    /// The grid to draw over each finished capture, or `nil` for none.
    /// Drawn last, after any `--max-size` fit, so its labels stay legible;
    /// the gutter therefore pushes the image past the cap by its own width.
    public let grid: ShotGrid.Options?

    /// Creates a shot operation.
    public init(
        region: ShotRegion = .viewport,
        scale: ShotScale = .one,
        fit: ShotFit? = nil,
        tile: ShotTile.Height? = nil,
        grid: ShotGrid.Options? = nil,
    ) {
        self.grid = grid
        self.region = region
        self.scale = scale
        self.fit = fit
        self.tile = tile
    }

    /// Captures the region and returns its encoded images.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/negative`` when
    ///   the region is an element that either matches nothing or matches
    ///   something with no rendered area (a `display: none` box, an empty
    ///   inline) — the clean-negative shape `query --exists` and `find`
    ///   share, and the reason no blank PNG is written;
    ///   ``SleepyError/Kind/environment`` when the page's geometry or the
    ///   snapshot itself can't be read, or when ``scale`` is denser than the
    ///   host's own raster; ``SleepyError/Kind/usage`` when the
    ///   resolved tile height is no taller than the overlap.
    @MainActor
    public func execute(on host: PageHost) async throws -> Output {
        let viewportHeight: CGFloat = host.webView.frame.height
        let capture = try await render(on: host)
        let strips = try tiled(capture, viewportHeight: viewportHeight)
        let fitted = try strips.map { try fit?.applied(to: $0) ?? $0 }
        let gridded = try fitted.map { capture in
            try grid.map { try ShotGrid.draw($0, on: capture, pixelsPerCSSPixel: capture.pixelsPerCSSPixel) } ?? capture
        }
        return try Output(images: gridded.map { try $0.encoded() })
    }

    /// The tile stage: the capture as itself when `--tile` wasn't asked for,
    /// and otherwise the strips it cuts into.
    ///
    /// The bare `--tile`'s height is resolved here because this is the first
    /// point that knows both the pixel budget and the viewport the page was
    /// rendered at.
    private func tiled(_ capture: ShotCapture, viewportHeight: CGFloat) throws -> [ShotCapture] {
        guard let tile else { return [capture] }
        let height: CGFloat = tile.resolved(maxSize: fit?.maxSize, viewportHeight: viewportHeight)
        return try ShotTile(height: height).applied(to: capture)
    }

    /// The render stage: resolves the region to a document rect and
    /// snapshots exactly that, one CSS px to one pixel.
    @MainActor
    func render(on host: PageHost) async throws -> ShotCapture {
        let webView = host.webView
        let originalFrame = webView.frame
        let needsFullHeight = region != .viewport
        defer { if needsFullHeight { webView.frame = originalFrame } }

        if needsFullHeight {
            let height = try await Self.documentHeight(on: host)
            webView.frame = CGRect(x: 0, y: 0, width: originalFrame.width, height: max(originalFrame.height, height))
        }

        let rect: CGRect = try await resolvedRect(on: host, frame: webView.frame)
        let configuration = WKSnapshotConfiguration()
        configuration.rect = rect
        let image = try await webView.takeSnapshot(configuration: configuration)
        try requireDensity(of: image)
        let pixels = CGSize(width: rect.width * CGFloat(scale.factor), height: rect.height * CGFloat(scale.factor))
        guard let rasterized = ShotCapture.rasterize(image, atPixelSize: pixels) else {
            throw SleepyError(
                kind: .environment,
                message: "Could not rasterize the snapshot.",
                nextMove: "Retry; if this persists, it is a seam bug against WKWebView.takeSnapshot.",
            )
        }
        return ShotCapture(image: rasterized, rect: rect, scale: scale.factor)
    }

    /// Refuses a `--scale` denser than the snapshot WebKit actually produced.
    ///
    /// The source raster's density is the *host's* screen backing scale, and
    /// nothing in a headless view moves it (measured:
    /// `project/2026-08-28-offscreen-window-host.md` § Density). Above it the
    /// only way to fill the requested pixels is to upscale, which would hand
    /// back a soft image that looks like a dense one — the plausible wrong
    /// answer this tool refuses to produce.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment``
    ///   naming the host's density and the flag that exceeded it.
    private func requireDensity(of image: NSImage) throws {
        let available: CGFloat = ShotCapture.density(of: image)
        // A hair of tolerance: the density is a ratio of measured numbers.
        guard CGFloat(scale.factor) > available + 0.01 else { return }
        throw SleepyError(
            kind: .environment,
            message: "This host renders at \(Self.measurement(available))×; "
                + "--scale \(scale.factor) would upsample.",
            nextMove: "Capture at --scale \(Int(available.rounded(.down))) or less on this Mac, "
                + "or run it on a display whose backing scale is \(scale.factor)×.",
        )
    }

    /// The document rect the region names, given the (possibly grown) view
    /// frame. The view is unscrolled, so view coordinates are document
    /// coordinates.
    @MainActor
    private func resolvedRect(on host: PageHost, frame: CGRect) async throws -> CGRect {
        switch region {
        case .viewport, .fullPage:
            return CGRect(origin: .zero, size: frame.size)
        case let .rect(rect):
            return rect
        case let .element(selector):
            guard let measured = try await Self.boundingRect(of: selector, on: host) else {
                throw SleepyError(
                    kind: .negative,
                    message: "No element matched '\(selector)', so there was nothing to crop to.",
                    nextMove: "Check the selector against the page: "
                        + "`sleepy query <page> --selector '\(selector)'`; "
                        + "if it arrives late, wait for it with --wait-for '\(selector)'.",
                )
            }
            guard measured.width.rounded() >= 1, measured.height.rounded() >= 1 else {
                throw SleepyError(
                    kind: .negative,
                    message: "'\(selector)' matched, but it has no rendered area: "
                        + "its rect is \(Self.describe(measured)).",
                    nextMove: "An element that is display:none, or an empty inline, has no box to crop to. "
                        + "Check what the cascade resolved to: "
                        + "`sleepy style <page> --selector '\(selector)' --property display`; "
                        + "if it is sized late, wait for that with --wait-for.",
                )
            }
            return measured
        }
    }

    /// The document's full scroll height in points, via
    /// `document.documentElement.scrollHeight`.
    private static func documentHeight(on host: PageHost) async throws -> CGFloat {
        let text = try await host.evaluate("return document.documentElement.scrollHeight;")
        guard let value = Double(text) else {
            throw SleepyError(
                kind: .environment,
                message: "Could not read the document's scroll height ('\(text)').",
                nextMove: "Retry; if this persists, it is a seam bug against PageHost.evaluate.",
            )
        }
        return CGFloat(value)
    }

    /// `selector`'s `getBoundingClientRect()`, or `nil` when nothing matches.
    private static func boundingRect(of selector: String, on host: PageHost) async throws -> CGRect? {
        let text = try await host.evaluate(
            """
            const el = document.querySelector(selector);
            if (!el) { return null; }
            const r = el.getBoundingClientRect();
            return { x: r.x, y: r.y, width: r.width, height: r.height };
            """,
            arguments: ["selector": selector],
        )
        guard text != "null", let data = text.data(using: .utf8) else { return nil }
        guard let decoded = try? JSONDecoder().decode(BoundingRect.self, from: data) else { return nil }
        return CGRect(x: decoded.x, y: decoded.y, width: decoded.width, height: decoded.height)
    }

    /// A rect as an agent should read it back: `200×150 at (100, 2400)`, in
    /// CSS pixels, trailing zeroes trimmed.
    private static func describe(_ rect: CGRect) -> String {
        "\(measurement(rect.width))×\(measurement(rect.height))"
            + " at (\(measurement(rect.origin.x)), \(measurement(rect.origin.y)))"
    }

    /// One coordinate, rendered without a pointless `.0` and without the
    /// current locale's decimal separator.
    private static func measurement(_ value: CGFloat) -> String {
        String(format: "%g", Double(value))
    }

    /// The JSON shape ``boundingRect(of:on:)`` decodes from the page.
    private struct BoundingRect: Decodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }
}
