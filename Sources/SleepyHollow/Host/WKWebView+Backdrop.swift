import AppKit
import Foundation
import WebKit

/// The one place in this package that spells the private `drawsBackground`
/// key.
extension WKWebView {
    /// The private KVC key that turns the web view's own background painting
    /// off. macOS publishes no equivalent — iOS's `WKWebView` inherits
    /// `UIView.isOpaque`, and the AppKit one exposes nothing.
    private static let drawsBackgroundKey = "drawsBackground"

    /// The setters KVC resolves ``drawsBackgroundKey`` through, newest first.
    /// Measured 2026-08-29 on macOS 15: this WebKit answers
    /// `_setDrawsBackground:` and not `setDrawsBackground:`, and exposes no
    /// matching instance variable, so probing for the underscored selector is
    /// what keeps ``applyBackdrop(_:)`` from raising `NSUnknownKeyException`
    /// on a WebKit that has dropped it.
    private static let drawsBackgroundSetters = ["_setDrawsBackground:", "setDrawsBackground:"]

    /// Makes the view paint `backdrop` behind the page.
    ///
    /// ``LoadOptions/Backdrop/opaque`` is WebKit's own behaviour, so it is a
    /// no-op; ``LoadOptions/Backdrop/transparent`` needs the private key
    /// above. `underPageBackgroundColor` — the public macOS 12 API that sounds
    /// like it would do this — is neither sufficient nor necessary: measured
    /// 2026-08-29, setting it to `NSColor.clear` on its own leaves every
    /// capture pixel opaque white, and the private key on its own already
    /// yields alpha 0.
    ///
    /// Reaching for a private key is a deliberate, recorded decision — the
    /// ruling in `project/2026-08-29-woodcase-harness-plan.md`: every consumer
    /// that wanted a transparent capture was setting it on
    /// ``PageHost/webView`` themselves, and owning it here with a test that
    /// fails loudly is better than owning it nowhere. `SleepyHollow` is a
    /// developer tool that will never face App Store review.
    ///
    /// - Parameter backdrop: what should be behind the page.
    /// - Returns: `true` when the backdrop is now in force — always for
    ///   ``LoadOptions/Backdrop/opaque``, and for the transparent case only
    ///   when this WebKit still answers the private key. `BackdropTests` is
    ///   the canary that asserts it: a `false` here means `--transparent`
    ///   would otherwise quietly hand back opaque white.
    @discardableResult
    func applyBackdrop(_ backdrop: LoadOptions.Backdrop) -> Bool {
        guard backdrop == .transparent else { return true }
        guard Self.drawsBackgroundSetters.contains(where: { responds(to: NSSelectorFromString($0)) }) else {
            return false
        }
        setValue(false, forKey: Self.drawsBackgroundKey)
        return true
    }
}
