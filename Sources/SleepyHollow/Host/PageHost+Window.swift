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
    /// - Returns: the host's window, parked off every screen; the same
    ///   instance on every call.
    @discardableResult
    func ensureOffscreenWindow() -> OffscreenWindow {
        if let offscreenWindow {
            return offscreenWindow
        }
        let window = OffscreenWindow(hosting: webView)
        offscreenWindow = window
        return window
    }
}
