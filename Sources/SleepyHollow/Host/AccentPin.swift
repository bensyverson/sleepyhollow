import AppKit
import Foundation

/// Pins the accent color native controls draw in to the system default blue,
/// so a shot does not depend on the accent the Mac running it has chosen.
///
/// Active controls — a checked box, a radio, a range fill, a focus ring, a
/// default button — draw in the accent color, and WebKit's web content process
/// reads the user's choice from System Settings itself: no defaults domain in
/// this process reaches it (measured, `scripts/accent-lever-probe.swift`).
/// What does reach it is the *app* accent. WebKit copies
/// `-[NSApplication _effectiveAccentColor]` into every new page's creation
/// parameters (`WebPageProxy::creationParameters`, via
/// `PageClientImpl::accentColor`) and the content process applies it with
/// `-[NSApplication _setAccentColor:]` (`WebPage::setAccentColor`). Setting the
/// app accent here, before the first page exists, therefore pins the accent of
/// every page this process creates. Measured 2026-11-06: an orange pin turns a
/// checked box orange, and the default pin reproduces the stock blue
/// rendering pixel for pixel (`project/2026-11-06-compositor-capture.md`
/// question 7).
///
/// **Private API**, approved for this use by Ben on 2026-11-06. Both
/// selectors are guarded with `responds(to:)`; when either is gone the pin is
/// skipped, ``isPinned`` is `false`, and `sleepy doctor` fails its `accent`
/// check — the fallback is loud, never silent. `AccentPinTests` goes red if
/// WebKit stops forwarding the app accent.
///
/// The *highlight* color (text selection) is not pinned: WebKit draws it from
/// `NSColor.selectedTextBackgroundColor` in the content process with no
/// app-level override, and nothing in this process reaches it.
@MainActor
enum AccentPin {
    /// The private setter on `NSApplication`.
    private static let setter: Selector = NSSelectorFromString("_setAccentColor:")

    /// The private getter WebKit reads the app accent through.
    private static let getter: Selector = NSSelectorFromString("_effectiveAccentColor")

    /// Whether ``ensureApplied()`` has already run in this process.
    private static var hasApplied = false

    /// The color pinned: AppKit's own catalog color for the blue accent,
    /// which adapts to the light and dark appearances and to Increase
    /// Contrast as the stock accent does. Falls back to its sRGB light value
    /// if the catalog name is gone.
    static var pinned: NSColor {
        let name = NSSelectorFromString("controlAccentBlueColor")
        if NSColor.responds(to: name), let color = NSColor.perform(name)?.takeUnretainedValue() as? NSColor {
            return color
        }
        return NSColor(srgbRed: 0, green: 122.0 / 255.0, blue: 1, alpha: 1)
    }

    /// Sets the process's app accent to `color`, for every page created
    /// after this call; pages that already exist keep the accent they were
    /// created with.
    ///
    /// - Parameter color: the accent to draw active controls in.
    static func apply(_ color: NSColor) {
        let app = NSApplication.shared
        guard app.responds(to: setter) else { return }
        _ = app.perform(setter, with: color)
    }

    /// Applies ``pinned`` once per process. ``PageHost`` calls this before it
    /// creates its web view.
    static func ensureApplied() {
        guard !hasApplied else { return }
        hasApplied = true
        apply(pinned)
    }

    /// Whether the app accent WebKit will forward is set — `false` when the
    /// private selectors are gone and pages follow the Mac's own accent.
    static var isPinned: Bool {
        let app = NSApplication.shared
        guard app.responds(to: setter), app.responds(to: getter) else { return false }
        return app.perform(getter)?.takeUnretainedValue() is NSColor
    }
}
