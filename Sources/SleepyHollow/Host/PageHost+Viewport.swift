import AppKit
import CoreGraphics
import Foundation

/// Moving an open page's viewport — the one load option that is honestly
/// mutable.
public extension PageHost {
    /// Resizes the page to `size`, in points, without reloading it.
    ///
    /// This is a live change, not a re-shape of the next load: the web view's
    /// frame moves, the page relayouts, `matchMedia` and every CSS media query
    /// re-evaluate against the new width, and the next capture is taken at the
    /// new size. Checking a second breakpoint therefore costs a resize rather
    /// than a fresh host and a second navigation — which is the point, because
    /// a fresh navigation loses whatever the page had been driven into (the
    /// first library embedding kept a host per breakpoint to work around this:
    /// `project/2026-08-29-woodcase-harness-feedback.md`, finding 6).
    ///
    /// What it does **not** do is re-run anything the page did once. A script
    /// that read `window.innerWidth` at load time keeps its old answer, and a
    /// framework that only measures on its own resize handler is a page fact,
    /// not a host one. When the layout must be built at the new width from
    /// scratch, load again instead.
    ///
    /// When ``PageHost/ensureOffscreenWindow()`` has parked the web view in a
    /// window, that window is resized with it: a hosted view that outgrows its
    /// window is clipped by it, so leaving the window behind would silently
    /// crop every capture past the old height. The window stays parked off
    /// every screen.
    ///
    /// - Parameter size: the new viewport, in points; also the new
    ///   ``PageHost/viewport``.
    func resize(to size: ViewportSize) {
        let frame: CGRect = PageHost.frame(for: size)
        webView.frame = frame
        offscreenWindow?.resize(to: frame.size)
        webView.layoutSubtreeIfNeeded()
        viewport = size
    }

    /// The web view's frame for a viewport: origin at zero, size in points.
    ///
    /// One place, so ``PageHost/init(options:jars:)`` and ``resize(to:)``
    /// cannot disagree about what a ``ViewportSize`` means in AppKit
    /// coordinates.
    internal static func frame(for size: ViewportSize) -> CGRect {
        CGRect(x: 0, y: 0, width: CGFloat(size.width), height: CGFloat(size.height))
    }
}
