import AppKit
import Foundation

/// Opting a host into a window. Off by default, on request, once per host.
public extension PageHost {
    /// Parks this host's ``PageHost/webView`` in an ``OffscreenWindow``,
    /// creating the window on the first call and returning the same one after.
    ///
    /// Nothing calls this by default. Every verb stays windowless — WebKit's
    /// hidden-page state, which is what the wait engine's budgets and the
    /// snapshot path were measured against — until an operation that needs a
    /// window asks for one. `pdf` pagination needs a window because
    /// `NSPrintOperation` does; `shot --scale` will need one to force a
    /// backing scale; a time-series capture needs one because rAF and CSS
    /// transitions only advance in a window
    /// (`project/2026-08-28-offscreen-window-host.md`).
    ///
    /// Hosting changes what the page does with time, so it is deliberately a
    /// per-operation choice rather than a ``LoadOptions`` field: flipping the
    /// default would change every verb's timing at once, and that is its own
    /// decision.
    ///
    /// The ordering and rendering arguments describe the window this host
    /// *gets*, not the one it already has: a second call returns the existing
    /// window unchanged, because the two settings are properties of the
    /// window and of WebKit's activity state at the moment the view was
    /// parked. An operation with its own needs (``PDFOperation`` wants a
    /// window in the list and no rendering updates) should therefore ask
    /// first, on a host of its own.
    ///
    /// - Parameter ordering: how far the new window is ordered in;
    ///   ``OffscreenWindow/Ordering/back`` by default, which is what AppKit's
    ///   printing path needs (`NSWindow.isVisible` must be `true`).
    /// - Parameter rendering: whether the hosted page runs rendering updates;
    ///   ``OffscreenWindow/Rendering/live`` by default.
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
}
