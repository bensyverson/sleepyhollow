import AppKit
import Foundation

/// Where a host's web view lives: in a live off-screen window by default, or
/// in none.
public extension PageHost {
    /// Where a host's web view lives.
    ///
    /// The choice changes what the page does with time and how it draws, which
    /// is why it is made once, when the host is built: WebKit fixes a page's
    /// visibility and the window's key status at the moment the view is
    /// parked.
    enum Hosting: String, Friendly, CaseIterable {
        /// Parked in an ``OffscreenWindow`` with
        /// ``OffscreenWindow/Rendering/live``: the page is visible to WebKit,
        /// so rAF, CSS transitions, Web Animations and nested timers run as on
        /// a display; the window claims key status, so native controls draw
        /// active and the focused element matches `:focus`; and the window
        /// paints in sRGB. Every verb's host, sessions included — the ruling
        /// of 2026-11-06 (`project/2026-11-06-true-3d-shots.md` § Ruling on
        /// the capture path).
        case live
        /// No window at all: WebKit's hidden-page state, where rAF never fires,
        /// animations stay at their start, nested timers are aligned to one
        /// second and native controls draw inactive. Kept for measuring
        /// against, and for an embedder that wants a page with no clock of its
        /// own; ``PageHost/ensureOffscreenWindow(ordering:rendering:)`` can
        /// still park it later.
        case windowless
    }

    /// Parks this host's ``PageHost/webView`` in an ``OffscreenWindow``,
    /// creating the window on the first call and returning the same one after.
    ///
    /// A ``Hosting/live`` host already has its window from init, so this
    /// returns it unchanged; the call only creates one for a
    /// ``Hosting/windowless`` host.
    ///
    /// The ordering and rendering arguments describe the window this host
    /// *gets*, not the one it already has: a second call returns the existing
    /// window unchanged, because the two settings are properties of the
    /// window and of WebKit's activity state at the moment the view was
    /// parked.
    ///
    /// - Parameter ordering: how far the new window is ordered in;
    ///   ``OffscreenWindow/Ordering/back`` by default, which is what AppKit's
    ///   printing path needs (`NSWindow.isVisible` must be `true`) and what a
    ///   live page was measured with.
    /// - Parameter rendering: whether the hosted page runs rendering updates;
    ///   ``OffscreenWindow/Rendering/live`` by default, as ``Hosting/live``
    ///   does. Pass ``OffscreenWindow/Rendering/hidden`` for a window that
    ///   keeps the page hidden and never reaches the private API.
    /// - Returns: the host's window, parked off every screen; the same
    ///   instance on every call.
    @discardableResult
    func ensureOffscreenWindow(
        ordering: OffscreenWindow.Ordering = .back,
        rendering: OffscreenWindow.Rendering = .live,
    ) -> OffscreenWindow {
        if let offscreenWindow {
            return offscreenWindow
        }
        let window = OffscreenWindow(hosting: webView, ordering: ordering, rendering: rendering)
        offscreenWindow = window
        return window
    }

    /// Moves the web view to `frame`, growing or shrinking its window with it.
    ///
    /// A hosted view that outgrows its window is clipped by it, so every
    /// change to the view's frame — a viewport resize, a full-page shot's
    /// temporary growth — goes through here rather than setting
    /// `webView.frame` directly (job issue `brc0C`).
    ///
    /// - Parameter frame: the view's new frame, origin at zero, in points.
    internal func applyFrame(_ frame: CGRect) {
        if let offscreenWindow {
            offscreenWindow.resize(to: frame.size)
        } else {
            webView.frame = frame
        }
    }
}
