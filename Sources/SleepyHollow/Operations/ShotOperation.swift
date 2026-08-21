import AppKit
import Foundation
import WebKit

/// `sleepy shot` — a PNG of the viewport, one element's rect, or the whole
/// scrollable page.
///
/// The default capture is viewport-shaped: whatever ``LoadOptions/size`` the
/// host was built with. ``fullPage`` and ``element`` both need content the
/// viewport-sized backing store may never have rasterized — a headless
/// `WKWebView` only reliably paints what's within its current `frame`, so
/// both temporarily grow the frame to the document's full scroll height
/// before capturing and restore it after. This is the fix for the exact bug
/// the vision doc names: a control 2,400px down a page invisible to a
/// viewport-shaped shot.
public struct ShotOperation: ExecutablePageOperation {
    /// The PNG bytes a capture produced.
    public struct Output: Friendly {
        /// The encoded PNG.
        public let png: Data

        /// Wraps encoded PNG bytes.
        public init(png: Data) {
            self.png = png
        }
    }

    /// Thrown when ``element`` matches nothing in the page.
    ///
    /// The wire identifier.
    public static let kind: String = "shot"

    /// A CSS selector to crop the screenshot to; `nil` captures the viewport
    /// (or the full page, when ``fullPage`` is set).
    public let element: String?

    /// Capture the full scroll height instead of the viewport.
    public let fullPage: Bool

    /// Creates a shot operation.
    public init(element: String? = nil, fullPage: Bool = false) {
        self.element = element
        self.fullPage = fullPage
    }

    /// Captures the page as configured and returns PNG bytes.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/negative`` when
    ///   ``element`` is set and matches nothing — the clean-negative shape
    ///   `query --exists` and `find` share; ``SleepyError/Kind/environment``
    ///   when the page's geometry or the snapshot itself can't be read.
    @MainActor
    public func execute(on host: PageHost) async throws -> Output {
        let webView = host.webView
        let originalFrame = webView.frame
        let needsFullHeight = fullPage || element != nil
        defer { if needsFullHeight { webView.frame = originalFrame } }

        if needsFullHeight {
            let height = try await Self.documentHeight(on: host)
            webView.frame = CGRect(x: 0, y: 0, width: originalFrame.width, height: max(originalFrame.height, height))
        }

        var rect: CGRect?
        if let element {
            guard let measured = try await Self.boundingRect(of: element, on: host) else {
                throw SleepyError(
                    kind: .negative,
                    message: "No element matched '\(element)'.",
                    nextMove: "Check the selector, e.g. with `sleepy query '\(element)'`.",
                )
            }
            rect = measured
        }

        let png = try await Self.snapshotPNG(rect: rect, on: webView)
        return Output(png: png)
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

    /// The JSON shape ``boundingRect(of:on:)`` decodes from the page.
    private struct BoundingRect: Decodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    /// Takes a snapshot of `webView`, cropped to `rect` when given, and
    /// re-encodes it as PNG at exactly `rect`'s (or the view's) point size in
    /// pixels — one CSS point, one output pixel.
    ///
    /// Measured, not documented: `takeSnapshot` hands back an `NSImage`
    /// rasterized at the *host machine's* screen backing scale factor (2x on
    /// a Retina Mac, 1x elsewhere) even though this web view is never
    /// attached to a screen — a bare capture came back 2560×1600 pixels for
    /// a 1280×800-point viewport on this Retina host, and `snapshotWidth`
    /// does not change that (it only relabels the `NSImage`'s logical size;
    /// the backing raster stays at the host's scale). Re-rendering into a
    /// bitmap context built at the exact pixel size normalizes that away, so
    /// the output depends only on `--size`/the element's rect, never on
    /// which Mac ran the command — determinism by construction (vision doc
    /// §5).
    @MainActor
    private static func snapshotPNG(rect: CGRect?, on webView: WKWebView) async throws -> Data {
        let configuration = WKSnapshotConfiguration()
        if let rect {
            configuration.rect = rect
        }
        let image = try await webView.takeSnapshot(configuration: configuration)
        let pixelSize = rect?.size ?? webView.frame.size
        guard let png = Self.pngData(rendering: image, atPixelSize: pixelSize) else {
            throw SleepyError(
                kind: .environment,
                message: "Could not encode the snapshot as PNG.",
                nextMove: "Retry; if this persists, it is a seam bug against WKWebView.takeSnapshot.",
            )
        }
        return png
    }

    /// Renders `image` into a fresh bitmap exactly `pixelSize` pixels wide
    /// and tall — one point, one pixel — independent of the source image's
    /// own backing resolution.
    private static func pngData(rendering image: NSImage, atPixelSize pixelSize: CGSize) -> Data? {
        let width = max(1, Int(pixelSize.width.rounded()))
        let height = max(1, Int(pixelSize.height.rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0,
        ) else {
            return nil
        }
        bitmap.size = CGSize(width: width, height: height)
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: CGRect(x: 0, y: 0, width: width, height: height),
            from: .zero,
            operation: .copy,
            fraction: 1,
        )
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
