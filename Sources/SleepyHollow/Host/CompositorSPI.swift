import Foundation
import WebKit

/// The private WebKit hook the compositor path waits on, isolated in one
/// place and guarded by `responds(to:)`.
///
/// `-[WKWebView _doAfterNextPresentationUpdate:]` calls back once the UI
/// process has applied a layer-tree commit that includes everything the page
/// did before the call — the hook WebKit's own layout tests use before
/// reading pixels. Without it, 13 of 20 captures taken straight after a
/// change showed the previous frame; with it, 20 of 20 were current
/// (`project/2026-11-06-compositor-capture.md` § 4). Private API, approved
/// for `shot` on 2026-11-06 (decision `BJkByM`).
///
/// If a future WebKit drops the selector, ``supportsPresentationUpdate(_:)``
/// says so, every shot falls back to `takeSnapshot` and names
/// ``ShotRenderer/Fallback/unavailable`` — never a silently stale frame —
/// and `CompositorRendererTests` goes red.
@MainActor
enum CompositorSPI {
    /// `-[WKWebView _doAfterNextPresentationUpdate:]`.
    static let presentationUpdate: Selector = NSSelectorFromString("_doAfterNextPresentationUpdate:")

    /// Whether `webView` still answers ``presentationUpdate``.
    static func supportsPresentationUpdate(_ webView: WKWebView) -> Bool {
        webView.responds(to: presentationUpdate)
    }

    /// Asks `webView` to call `completion` after its next presentation
    /// update.
    ///
    /// - Returns: `false`, without calling anything, when the selector is
    ///   gone; `true` when the request was made.
    @discardableResult
    static func afterNextPresentationUpdate(
        of webView: WKWebView,
        _ completion: @escaping @MainActor () -> Void,
    ) -> Bool {
        guard supportsPresentationUpdate(webView) else { return false }
        typealias Call = @convention(c) (AnyObject, Selector, @escaping @convention(block) () -> Void) -> Void
        let call = unsafeBitCast(webView.method(for: presentationUpdate), to: Call.self)
        call(webView, presentationUpdate) {
            // WebKit answers on the main thread; hop rather than trap if a
            // future one does not (an AppKit callback off the main thread
            // dies in the isolation check with no message, project/gotchas.md).
            if Thread.isMainThread {
                MainActor.assumeIsolated { completion() }
            } else {
                Task { @MainActor in completion() }
            }
        }
        return true
    }
}
