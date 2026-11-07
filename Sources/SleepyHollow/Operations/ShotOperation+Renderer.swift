import AppKit
import Foundation
import WebKit

/// The render stage's two renderers and the choice between them
/// (``ShotRenderer``).
extension ShotOperation {
    /// The renderer that will draw `rect` faithfully on `host`: the
    /// compositor, unless the host cannot run it or the area holds a video.
    ///
    /// Asked after the region is resolved and the frame grown, against the
    /// layout the render will draw.
    @MainActor
    func chooseRenderer(for rect: CGRect, on host: PageHost) async throws -> ShotRenderer {
        if let unavailable = host.compositorUnavailability {
            return .snapshot(unavailable)
        }
        guard rect.width * CGFloat(scale.factor) <= CGFloat(CompositorRenderer.maximumTextureSide) else {
            return .snapshot(.tooWide)
        }
        if try await Self.holdsVideo(rect, on: host) {
            return .snapshot(.video)
        }
        return .compositor
    }

    /// Renders `rect` through the compositor.
    @MainActor
    func compositorCapture(of rect: CGRect, on host: PageHost) async throws -> ShotCapture {
        try requireDensity(available: host.webView.window?.backingScaleFactor ?? 1)
        let image: CGImage = try await host.compositorImage(of: rect, scale: scale.factor)
        return ShotCapture(image: image, rect: rect, scale: scale.factor, renderer: .compositor)
    }

    /// Renders `rect` with `takeSnapshot`, reporting the CSS 3D in it that
    /// the flat paint draws wrong.
    @MainActor
    func snapshotCapture(of rect: CGRect, on host: PageHost, because fallback: ShotRenderer.Fallback) async throws -> ShotCapture {
        let flattened: [FlattenedElement] = try await Self.flattened3D(in: rect, on: host)
        let configuration = WKSnapshotConfiguration()
        configuration.rect = rect
        let image: NSImage = try await host.snapshot(configuration)
        try requireDensity(available: ShotCapture.density(of: image))
        let pixels = CGSize(width: rect.width * CGFloat(scale.factor), height: rect.height * CGFloat(scale.factor))
        guard let rasterized = ShotCapture.rasterize(image, atPixelSize: pixels) else {
            throw SleepyError(
                kind: .environment,
                message: "Could not rasterize the snapshot.",
                nextMove: "Retry; if this persists, it is a seam bug against WKWebView.takeSnapshot.",
            )
        }
        return ShotCapture(
            image: rasterized,
            rect: rect,
            scale: scale.factor,
            flattened3D: flattened,
            renderer: .snapshot(fallback),
        )
    }

    /// Whether a rendered `<video>` reaches into `rect` (view coordinates, as
    /// `getBoundingClientRect()` answers), in the document or in any
    /// same-origin frame inside it.
    ///
    /// Any video with a box counts, playing or not, poster or none: the
    /// compositor draws a video's layer blank and says nothing, so a false
    /// alarm costs only the flat render (which says so), while a miss would
    /// be a plausible wrong answer. A video hidden by `visibility` or with no
    /// box draws nothing either way and does not count. A cross-origin frame
    /// cannot be looked into and is not counted.
    @MainActor
    static func holdsVideo(_ rect: CGRect, on host: PageHost) async throws -> Bool {
        let area: [String: Double] = [
            "x": Double(rect.minX), "y": Double(rect.minY),
            "width": Double(rect.width), "height": Double(rect.height),
        ]
        return try await host.evaluate(videoScript, as: Bool.self, arguments: ["area": area])
    }

    /// The page side of ``holdsVideo(_:on:)``.
    private static let videoScript: String = """
    const right = area.x + area.width, bottom = area.y + area.height;
    const search = (doc, dx, dy) => {
      for (const video of doc.querySelectorAll("video")) {
        const r = video.getBoundingClientRect();
        if (r.width < 1 || r.height < 1) continue;
        if (doc.defaultView.getComputedStyle(video).visibility !== "visible") continue;
        const left = r.left + dx, top = r.top + dy;
        if (left < right && left + r.width > area.x && top < bottom && top + r.height > area.y) return true;
      }
      for (const frame of doc.querySelectorAll("iframe, frame")) {
        let inner = null;
        try { inner = frame.contentDocument; } catch (e) { inner = null; }
        if (!inner) continue;
        const r = frame.getBoundingClientRect();
        if (search(inner, dx + r.left + frame.clientLeft, dy + r.top + frame.clientTop)) return true;
      }
      return false;
    };
    return search(document, 0, 0);
    """
}
