import Foundation
import WebKit

/// Keeping an idle page at full priority for a call that would not lift it.
///
/// A host's web view has no window, so WebKit throttles its content process
/// once the view goes idle: about a second after the last call that held a
/// foreground activity, the process drops to the background priority band
/// (measured 2026-09-26: task priority 31 while called, 4 once idle). A
/// JavaScript call takes that activity for as long as it runs, so an
/// evaluate lifts the page back before it arrives. `takeSnapshot`, printing
/// and `createWebArchiveData` take none, and reach a page still in the
/// background band — where, on a loaded machine, it gets no CPU at all: a
/// session idle for two seconds could not answer its next shot, pdf or
/// archive before the call budget ran out (job leaf 116NLb).
///
/// No public API asks WebKit to keep a windowless view's process at
/// foreground priority — `WKPreferences.inactiveSchedulingPolicy = .none`
/// was measured and leaves the drop to 4 in place, and making the view
/// visible would change what the page does with time. So such a call is
/// made under a *hold*: an async JavaScript call, in a world of its own, that
/// waits on a promise until the call has answered. WebKit keeps its
/// foreground activity for exactly that long.
extension PageHost {
    /// Runs `body` with the page's content process held at the priority a
    /// JavaScript call runs at.
    ///
    /// For WebKit calls that take no foreground activity of their own; an
    /// evaluate needs no hold. The hold is released however `body` ends, and
    /// ends by itself if the page navigates or its process goes away.
    ///
    /// - Parameter body: the call to make while the page is held.
    /// - Returns: what `body` returns.
    func holdingForeground<Value>(_ body: () async throws -> Value) async rethrows -> Value {
        let token: String = UUID().uuidString
        webView.callAsyncJavaScript(
            Self.holdBody,
            arguments: ["token": token],
            in: nil,
            in: Self.holdWorld,
            completionHandler: nil,
        )
        defer {
            webView.callAsyncJavaScript(
                Self.releaseBody,
                arguments: ["token": token],
                in: nil,
                in: Self.holdWorld,
                completionHandler: nil,
            )
        }
        return try await body()
    }

    /// The world holds live in: out of reach of page script, which could
    /// otherwise settle a hold early or trip over its bookkeeping.
    private static var holdWorld: WKContentWorld {
        WKContentWorld.world(name: "sleepy-foreground-hold")
    }

    /// Parks a resolver under the token and waits for it — the whole hold.
    private static let holdBody: String = """
    const holds = globalThis.__sleepyHolds ??= new Map();
    await new Promise((resolve) => holds.set(token, resolve));
    """

    /// Settles the hold the token names, if the document still has it.
    private static let releaseBody: String = """
    const holds = globalThis.__sleepyHolds;
    holds?.get(token)?.();
    holds?.delete(token);
    """
}
