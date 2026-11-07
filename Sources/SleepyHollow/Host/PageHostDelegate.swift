import Foundation
import WebKit

/// The `WKWebView` delegate trio, kept off ``PageHost``'s public surface.
///
/// It owns three jobs: ending the pending navigation, answering dialogs by
/// policy (never blocking, always recorded), and forwarding script messages.
/// `WKWebView` holds its delegates weakly, and this holds the host weakly, so
/// nothing retains anything in a cycle.
@MainActor
final class PageHostDelegate: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    /// The host being driven.
    weak var host: PageHost?

    /// The main frame's HTTP status for the navigation in flight.
    ///
    /// The only place WebKit offers it: `PerformanceResourceTiming` has never
    /// shipped `responseStatus` in Safari (see the wire spike).
    var mainFrameStatus: Int?

    // MARK: - Navigation

    /// Main-frame navigation requests WebKit has asked to decide, behind
    /// ``PageHost/navigationRequestCount``.
    private(set) var navigationRequests: Int = 0

    /// The earliest the host hears of a main-frame navigation: the web
    /// process asks before it starts loading, in the same message order as
    /// everything else the page sends — which is what lets
    /// ``PageHost/navigationStarted(sinceRequests:)`` answer by ordering
    /// rather than by a grace period. A same-document change (a fragment)
    /// is not a navigation the verb's read must wait for, so it is not
    /// counted. Every request is allowed, as WebKit does with no delegate.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void,
    ) {
        if navigationAction.targetFrame?.isMainFrame == true,
           !Self.isFragmentChange(from: webView.url, to: navigationAction.request.url)
        {
            navigationRequests += 1
        }
        if let holdDecision {
            holdDecision(navigationAction.request.url) { decisionHandler(.allow) }
        } else {
            decisionHandler(.allow)
        }
    }

    /// A test seam: when set, each navigation decision is handed here with
    /// the call that allows it, so a test can hold a navigation's start for
    /// as long as a loaded machine might — the condition a settle that bets
    /// on a wall-clock window loses. `nil`, the only production value,
    /// allows at once.
    var holdDecision: ((URL?, @escaping @MainActor () -> Void) -> Void)?

    /// Whether `target` differs from `current` only by its fragment.
    private static func isFragmentChange(from current: URL?, to target: URL?) -> Bool {
        guard let current, let target, target.fragment != nil else { return false }
        func withoutFragment(_ url: URL) -> String {
            url.absoluteString.split(separator: "#", maxSplits: 1).first.map(String.init) ?? url.absoluteString
        }
        return withoutFragment(current) == withoutFragment(target)
    }

    func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        host?.noteNavigationStarted()
    }

    /// Main-frame commits, behind ``PageHost/navigationCount``.
    let navigations: NavigationTracker = .init()

    func webView(_ webView: WKWebView, didCommit _: WKNavigation!) {
        host?.noteNavigationStarted()
        // Every main-frame document that becomes the page arrives here once,
        // a back-forward-cache restore included; a same-document change never
        // does — which is the whole distinction ``PageHost/navigationCount``
        // draws.
        navigations.commit(url: webView.url)
    }

    /// WebKit's only report that the web content process is gone — and the one
    /// signal that separates a sandbox denial from a slow page.
    ///
    /// Under an agent sandbox the process launch is denied, this arrives, and
    /// no navigation callback ever does; the host turns that into a
    /// ``WebContentProcessFailure/neverLaunched`` load failure rather than
    /// letting the budget expire on a page that was never going to answer.
    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        host?.reportContentProcessTermination()
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        host?.finishNavigation(.finished)
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: any Error) {
        host?.finishNavigation(.failed, failure: error)
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: any Error) {
        abandonedNavigations += 1
        host?.finishNavigation(.failed, failure: error)
    }

    /// Main-frame navigations that ended before committing, behind
    /// ``PageHost/navigationProgress``.
    ///
    /// Measured 2026-11-06 (`NavigationSignalMeasurementTests`): every
    /// navigation WebKit decides and then drops ends here — a `204`, a
    /// response the policy cancels, a top-level `data:` URL (all
    /// `WebKitErrorDomain` 102), a `mailto:` or unknown scheme
    /// (`NSURLErrorDomain` -1002) — so a wait for "committed or abandoned"
    /// always ends. A download-only response (`Content-Disposition:
    /// attachment`) with the response allowed commits instead.
    private(set) var abandonedNavigations: Int = 0

    func webView(
        _: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void,
    ) {
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse {
            mainFrameStatus = response.statusCode
        }
        decisionHandler(.allow)
    }

    // MARK: - Dialogs

    /// `beforeunload` is deliberately absent, because `WKUIDelegate` has no
    /// public hook for it.
    ///
    /// The only public `runBeforeUnloadConfirmPanel…` in the SDK belongs to
    /// the legacy `WebUIDelegate`/`WebView` pair; `WKWebView`'s equivalent is
    /// SPI (`_webView:runBeforeUnloadConfirmPanel…`). Unimplemented, WebKit
    /// leaves the page — which is exactly the vision's policy, so the outcome
    /// is right even though nothing is observed. The consequence for the
    /// output: no `beforeunload` record kind exists (``DialogRecord/Kind``
    /// deliberately omits it), and a `beforeunload` handler cannot stall a
    /// navigation.
    func webView(
        _: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void,
    ) {
        host?.record(DialogRecord(kind: .alert, message: message, response: .acknowledged))
        completionHandler()
    }

    func webView(
        _: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void,
    ) {
        let accepts: Bool = host?.options.dialogs.acceptsConfirms ?? false
        host?.record(DialogRecord(
            kind: .confirm,
            message: message,
            response: accepts ? .accepted : .dismissed,
        ))
        completionHandler(accepts)
    }

    func webView(
        _: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText _: String?,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void,
    ) {
        let answer: String? = host?.options.dialogs.promptResponse
        host?.record(DialogRecord(
            kind: .prompt,
            message: prompt,
            response: answer.map { DialogRecord.Response.answered($0) } ?? .dismissed,
        ))
        completionHandler(answer)
    }

    // MARK: - Script messages

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        host?.deliver(message: message.body, named: message.name)
    }
}
