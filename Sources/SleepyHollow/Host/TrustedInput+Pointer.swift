import AppKit
import Foundation
import WebKit

/// The pointer half of ``TrustedInput``: moving it, and pressing its primary
/// button, at a point in viewport CSS px.
///
/// A move goes through `-[WKWebView _simulateMouseMove:]` (the only route to
/// the page from a window whose app is never active); a press and release go
/// through `NSWindow.sendEvent(_:)` as `leftMouseDown`/`leftMouseUp`, which
/// the window routes to the web view under the point. **WebKit hit-tests the
/// press itself**, the way it does a user's: through shadow roots, CSS
/// transforms, `pointer-events` and whatever is on top, so what receives the
/// click is what a user's click would reach — not what a script picked.
extension TrustedInput {
    /// Moves the pointer to a point in viewport CSS px and waits until the
    /// page has handled the move.
    ///
    /// - Throws: ``SleepyError/Kind/environment`` when this WebKit lacks the
    ///   SPI, and a ``SleepyError/Kind/timeout`` when the page does not
    ///   handle the move within the host's call budget.
    func movePointer(toViewport point: CGPoint) async throws {
        try sendMove(to: windowLocation(ofViewport: point))
        try await pointerLanded()
    }

    /// Clicks the primary button at a point in viewport CSS px: the pointer
    /// moves there, presses and releases, and this waits until the page has
    /// handled all three.
    ///
    /// The page sees `pointermove`, `pointerdown`, `mousedown`, `pointerup`,
    /// `mouseup` and `click`, each with `isTrusted` true, and WebKit runs the
    /// click's default action — a link followed, a form submitted, a checkbox
    /// toggled, focus moved — with or without the page's scripts. The pointer
    /// stays where it clicked, as a user's would, so `:hover` matches there
    /// afterwards.
    ///
    /// - Throws: ``SleepyError/Kind/environment`` when this WebKit lacks the
    ///   SPI, and a ``SleepyError/Kind/timeout`` when the page does not
    ///   handle the events within the host's call budget.
    func click(atViewport point: CGPoint) async throws {
        let location: NSPoint = windowLocation(ofViewport: point)
        try sendMove(to: location)
        postButton(.leftMouseDown, at: location)
        postButton(.leftMouseUp, at: location)
        try await pointerLanded()
    }

    /// Waits until WebKit has delivered every pointer event sent so far.
    func pointerLanded() async throws {
        try await drain(InputSPI.afterPendingMouseEvents, naming: "the pending pointer events")
    }

    /// A viewport CSS px point in the window's base coordinates, through the
    /// page's zoom and the view's magnification. Unrounded: AppKit carries the
    /// fraction to WebKit.
    private func windowLocation(ofViewport point: CGPoint) -> NSPoint {
        let view: WKWebView = host.webView
        let scale: CGFloat = view.pageZoom * view.magnification
        let local = NSPoint(
            x: point.x * scale,
            y: view.isFlipped ? point.y * scale : view.bounds.height - point.y * scale,
        )
        return view.convert(local, to: nil)
    }

    private func sendMove(to location: NSPoint) throws {
        let view: WKWebView = host.webView
        guard let event = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0,
        ) else { return }
        let selector = NSSelectorFromString(InputSPI.simulateMouseMove)
        guard view.responds(to: selector) else { throw Self.missing(InputSPI.simulateMouseMove, for: "a pointer move") }
        typealias Move = @convention(c) (AnyObject, Selector, NSEvent) -> Void
        let move = unsafeBitCast(view.method(for: selector), to: Move.self)
        move(view, selector, event)
    }

    private func postButton(_ type: NSEvent.EventType, at location: NSPoint) {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseDown ? 1 : 0,
        ) else { return }
        window.sendEvent(event)
    }
}
