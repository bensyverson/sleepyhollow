import Foundation
import Testing
import TestSupport
import WebKit

/// The measurement behind ``PageHost``'s step-navigation settle: which
/// navigation-delegate callbacks a main-frame navigation that is decided but
/// never commits actually produces — a `204`, a download, a cancelled
/// response policy — next to one that commits late.
///
/// Off unless `SLEEPY_MEASURE` is set: it prints a table rather than testing
/// a behavior. Run with
/// `SLEEPY_MEASURE=1 swift test --filter NavigationSignalMeasurement`; the
/// figures are in `project/2026-11-06-trusted-click.md`.
@Suite(
    "Navigation signal measurement",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SLEEPY_MEASURE"] != nil),
)
struct NavigationSignalMeasurementTests {
    /// Records every navigation-delegate callback in order, with `isLoading`
    /// at the time.
    @MainActor
    final class Recorder: NSObject, WKNavigationDelegate {
        var events: [String] = []
        var cancelResponse = false
        let start = Date()

        private func note(_ event: String, _ view: WKWebView) {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            events.append("\(ms)ms \(event) loading=\(view.isLoading)")
        }

        func webView(
            _ view: WKWebView,
            decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void,
        ) {
            note("action \(action.request.url?.path ?? "?") main=\(action.targetFrame?.isMainFrame == true)", view)
            decisionHandler(.allow)
        }

        func webView(
            _ view: WKWebView,
            decidePolicyFor response: WKNavigationResponse,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void,
        ) {
            let status = (response.response as? HTTPURLResponse)?.statusCode ?? 0
            note("response \(status) canShow=\(response.canShowMIMEType) main=\(response.isForMainFrame)", view)
            decisionHandler(cancelResponse ? .cancel : .allow)
        }

        func webView(_ view: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            note("didStartProvisional", view)
        }

        func webView(_ view: WKWebView, didCommit _: WKNavigation!) {
            note("didCommit", view)
        }

        func webView(_ view: WKWebView, didFinish _: WKNavigation!) {
            note("didFinish", view)
        }

        func webView(_ view: WKWebView, didFail _: WKNavigation!, withError error: any Error) {
            note("didFail \((error as NSError).domain) \((error as NSError).code)", view)
        }

        func webView(_ view: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: any Error) {
            note("didFailProvisional \((error as NSError).domain) \((error as NSError).code)", view)
        }
    }

    @MainActor
    private func measure(
        _ label: String,
        target: String,
        cancelResponse: Bool = false,
        base: URL,
    ) async throws {
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let recorder = Recorder()
        recorder.cancelResponse = false
        view.navigationDelegate = recorder
        let observation = view.observe(\.isLoading, options: [.new]) { view, _ in
            MainActor.assumeIsolated { recorder.events.append("  kvo isLoading=\(view.isLoading)") }
        }
        defer { observation.invalidate() }
        let page = "<a id=go href='\(target)'>go</a>"
        view.loadHTMLString(page, baseURL: base)
        while recorder.events.contains(where: { $0.contains("didFinish") }) == false {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        recorder.events.removeAll()
        recorder.cancelResponse = cancelResponse
        _ = try await view.evaluateJavaScript("document.getElementById('go').click(); 1")
        recorder.events.append("click returned loading=\(view.isLoading)")
        for _ in 0 ..< 150 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        print("== \(label)")
        for event in recorder.events {
            print("   \(event)")
        }
    }

    @Test
    @MainActor
    func `which callbacks a decided navigation produces`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            await server.register(path: "/no-content") { _ in
                FixtureResponse(status: 204, contentType: .plainText, body: Data())
            }
            await server.register(path: "/attachment") { _ in
                FixtureResponse(
                    status: 200,
                    contentType: .octetStream,
                    headers: ["Content-Disposition": "attachment; filename=x.bin"],
                    body: Data("bytes".utf8),
                )
            }
            await server.register(path: "/held") { _ in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                return FixtureResponse(status: 200, contentType: .html, body: Data("<p>held</p>".utf8))
            }
            try await measure("204", target: "/no-content", base: base)
            try await measure("attachment", target: "/attachment", base: base)
            try await measure("held 1 s, then 200", target: "/held", base: base)
            try await measure("response policy cancel", target: "/static.html", cancelResponse: true, base: base)
            var cross = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            cross.host = "localhost"
            cross.path = "/held"
            try await measure("cross-site held 1 s", target: cross.url!.absoluteString, base: base)
            let crossTarget = cross.url!.absoluteString
            await server.register(path: "/bounce") { _ in
                FixtureResponse(status: 302, contentType: .plainText, headers: ["Location": crossTarget], body: Data())
            }
            try await measure("same-site 302 to cross-site held 1 s", target: "/bounce", base: base)
            try await measure("mailto:", target: "mailto:someone@example.com", base: base)
            try await measure("unknown scheme", target: "sleepy-nowhere:thing", base: base)
            try await measure("data: URL", target: "data:text/html,<p>data</p>", base: base)
        }
    }
}
