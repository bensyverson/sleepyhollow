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

    func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        host?.noteNavigationStarted()
    }

    func webView(_: WKWebView, didCommit _: WKNavigation!) {
        host?.noteNavigationStarted()
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
        host?.finishNavigation(.failed, failure: error)
    }

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
