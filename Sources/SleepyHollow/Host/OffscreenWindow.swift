import AppKit
import Foundation

/// An `NSWindow` parked far off every screen, whose only job is to give a view
/// a window without ever showing one.
///
/// Two different needs bring a web view here, and they are not the same need:
///
/// - **A window at all.** `NSPrintOperation`, which `pdf` pagination needs,
///   refuses a view that has none.
/// - **A page WebKit considers visible.** A windowless web view sits in
///   WebKit's hidden-page state: it still renders on demand for
///   `takeSnapshot`, but never runs a rendering update, so
///   `requestAnimationFrame` never fires and CSS transitions never advance.
///   A window alone does *not* fix that — measured, at every ordering, on- and
///   off-screen (`project/2026-08-28-offscreen-window-host.md`). What fixes it
///   is a window *plus* ``Rendering/live``.
///
/// Nothing about this window is visible, and the proof is mechanical rather
/// than a promise:
///
/// - the app's activation policy is set to `.prohibited` **before** the first
///   window exists, so the process has no Dock tile, no menu bar, and cannot
///   become active;
/// - the window is borderless and parked at ``parkedOrigin``, twenty thousand
///   points below and to the left of any real display, so its frame intersects
///   no `NSScreen` and `NSWindow.screen` is `nil`;
/// - it is never made key and the app is never activated.
///
/// `OffscreenWindowTests` asserts all of that during a real render.
///
/// ```swift
/// let host = PageHost()
/// _ = host.ensureOffscreenWindow()   // opt in, once, per host
/// _ = try await host.load(url)       // now rAF fires and transitions run
/// ```
@MainActor
public final class OffscreenWindow {
    /// Where the window is parked: far enough from the origin that no display
    /// arrangement, however many screens are placed left of or below the main
    /// one, can reach it.
    public static let parkedOrigin: CGPoint = .init(x: -20000, y: -20000)

    /// How far into the window list the window is placed.
    ///
    /// Measured: ordering changes nothing about whether WebKit renders — the
    /// page is hidden at all three unless ``Rendering/live`` is asked for. It
    /// changes only `NSWindow.isVisible`, which AppKit's own printing and
    /// drawing paths consult, so the default puts the window in the list at
    /// the back where it costs nothing.
    public enum Ordering: Int, CaseIterable, Sendable {
        /// The window is created and never ordered into the window list;
        /// `isVisible` stays `false`.
        case unordered = 0
        /// `orderBack(nil)` — in the list, behind everything.
        case back = 1
        /// `orderFrontRegardless()` — in the list, without activating the app.
        case frontRegardless = 2
    }

    /// Whether the hosted page runs WebKit's rendering updates.
    ///
    /// A window parked off-screen is, correctly, never occluded-visible: the
    /// window server has nothing to show it on, so WebKit keeps the page in
    /// its hidden activity state. ``live`` opts the web view out of that
    /// determination, which is what makes `requestAnimationFrame`, CSS
    /// transitions and `document.visibilityState === "visible"` behave the way
    /// they do on a real display.
    public enum Rendering: CaseIterable, Sendable {
        /// Leave WebKit's own occlusion determination alone: off-screen means
        /// hidden, so rAF is frozen and transitions do not advance.
        case hidden
        /// Tell the web view to stop deciding visibility from window
        /// occlusion, so the page renders as if on screen.
        ///
        /// A live page keeps working — an infinite rAF chain is genuine
        /// activity, so a `--wait-for idle` over one will not settle. That is
        /// the caller's choice to make per operation.
        case live
    }

    /// The window itself. Read it for geometry and backing scale; do not
    /// order, key or show it.
    public let window: NSWindow

    /// Whether the activation policy has already been prohibited — the call is
    /// idempotent, but `NSApplication.shared` is not free.
    private static var hasProhibitedActivation = false

    /// Parks `view` in a fresh off-screen window sized to the view's frame.
    ///
    /// The activation policy is prohibited before the window exists, so no
    /// window this process opens can ever be presented.
    ///
    /// - Parameter view: the view to host; it becomes the window's content
    ///   view, and its frame size becomes the window's content size.
    /// - Parameter ordering: how far the window is ordered in.
    /// - Parameter rendering: whether the hosted page runs rendering updates;
    ///   ``Rendering/live`` by default, which is the reason to host a page
    ///   that is not being printed.
    public init(hosting view: NSView, ordering: Ordering = .back, rendering: Rendering = .live) {
        Self.prohibitActivation()
        window = NSWindow(
            contentRect: CGRect(origin: Self.parkedOrigin, size: view.frame.size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.contentView = view
        switch ordering {
        case .unordered:
            break
        case .back:
            window.orderBack(nil)
        case .frontRegardless:
            window.orderFrontRegardless()
        }
        // Parking is asserted, not assumed: `contentRect` is honoured, but a
        // borderless window can still be nudged by AppKit's constrain pass.
        window.setFrameOrigin(Self.parkedOrigin)
        if rendering == .live {
            Self.disableWindowOcclusionDetection(on: view)
        }
    }

    /// Resizes the window and its content view together, keeping the window
    /// parked.
    ///
    /// A hosted view that outgrows its window is clipped by it, so anything
    /// that changes the viewport — full-page capture, `pdf` pagination — must
    /// grow the window too.
    ///
    /// - Parameter size: the new content size, in points.
    public func resize(to size: CGSize) {
        window.setFrame(CGRect(origin: Self.parkedOrigin, size: size), display: false)
        window.contentView?.frame = CGRect(origin: .zero, size: size)
    }

    /// Closes the window, releasing the content view back to its owner.
    ///
    /// The window is not released on close, so this is safe to call more than
    /// once; the hosted view survives and can be re-parked.
    public func close() {
        window.contentView = nil
        window.close()
    }

    /// Puts the process in the activation policy that makes every window
    /// unpresentable, once per process.
    ///
    /// This is the load-bearing half of "nothing visible": a `.prohibited`
    /// process has no Dock tile and cannot be activated, so even a window
    /// ordered front regardless never reaches a display.
    private static func prohibitActivation() {
        guard !hasProhibitedActivation else { return }
        hasProhibitedActivation = true
        _ = NSApplication.shared.setActivationPolicy(.prohibited)
    }

    /// Stops a `WKWebView` deciding its page's visibility from window
    /// occlusion, so an off-screen window still renders.
    ///
    /// **This is the one piece of private API in the project.**
    /// `-[WKWebView _setWindowOcclusionDetectionEnabled:]` is what WebKit's own
    /// test runner uses to host a web view in an off-screen window, and there
    /// is no public equivalent: `WKWebView` derives page visibility from the
    /// window's `occlusionState`, which the window server will never report as
    /// visible for a window parked off every display. Measured alternatives
    /// that do *not* work: any window ordering, an on-screen window at alpha 0,
    /// `NSApplication.finishLaunching()`, pumping the run loop, and the
    /// `.accessory` activation policy — all leave the page hidden.
    ///
    /// The call is guarded by `responds(to:)`: on an OS where the selector is
    /// gone this is a no-op and the page falls back to ``Rendering/hidden``
    /// behaviour, which the rAF test will catch as a red rather than a lie.
    private static func disableWindowOcclusionDetection(on view: NSView) {
        let selector = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        guard view.responds(to: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
        let setter = unsafeBitCast(view.method(for: selector), to: Setter.self)
        setter(view, selector, ObjCBool(false))
    }
}
