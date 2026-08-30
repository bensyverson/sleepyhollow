import Foundation
import WebKit

/// Resumes one continuation when a bare `WKWebView`'s navigation ends.
///
/// The measurement suite drives raw web views rather than ``PageHost``s, so
/// that each arrangement it compares is one variable away from the next; this
/// is the whole of the navigation plumbing that needs.
@MainActor
final class MeasurementNavigationDelegate: NSObject, WKNavigationDelegate {
    /// Called once, on the first outcome the navigation reaches.
    var finish: (() -> Void)?

    nonisolated func webView(_: WKWebView, didFinish _: WKNavigation!) {
        MainActor.assumeIsolated { end() }
    }

    nonisolated func webView(_: WKWebView, didFail _: WKNavigation!, withError _: any Error) {
        MainActor.assumeIsolated { end() }
    }

    nonisolated func webView(
        _: WKWebView,
        didFailProvisionalNavigation _: WKNavigation!,
        withError _: any Error,
    ) {
        MainActor.assumeIsolated { end() }
    }

    private func end() {
        finish?()
        finish = nil
    }
}
