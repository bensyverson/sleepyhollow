import Foundation

/// Why a page's web content process — the separate process `WKWebView` renders
/// in — stopped existing, and therefore which failure the load reports.
///
/// The two cases are told apart by how far the navigation had got when WebKit
/// called `webViewWebContentProcessDidTerminate(_:)`: nothing at all, or a page
/// already under way. That distinction is the whole point. A process that never
/// launched is an *environment* fact — under an agent sandbox WebKit's XPC
/// launch is denied, no navigation ever begins, and the load would otherwise sit
/// there until the budget expired and report a timeout, sending the reader to
/// raise a budget that was never the problem.
///
/// Observed 2026-08-28 in this repo, running
/// `.build/debug/sleepy load file://…/static.html --budget 5000` inside Claude
/// Code's Bash sandbox: WebKit writes
/// `Could not create a 'com.apple.coreservices.launchservicesd' sandbox
/// extension` to stderr (twice), then delivers
/// `webViewWebContentProcessDidTerminate(_:)` — and neither
/// `didStartProvisionalNavigation` nor `didCommit` ever arrives. The same
/// command with the sandbox disabled reports all three navigation callbacks and
/// exits 0. The delegate callback is the signal this type is built on; the
/// stderr line is not parsed.
public enum WebContentProcessFailure: String, Friendly {
    /// WebKit never got its content process at all: the process was reported
    /// gone before any navigation had begun. In practice a sandbox denial.
    case neverLaunched
    /// The content process ended after the navigation had started — the page
    /// took the renderer down with it.
    case crashedMidLoad

    /// The failure a load throws for this ending, with the next move spelled
    /// out.
    ///
    /// - Parameter url: the page being loaded, named in the message when known.
    /// - Returns: a ``SleepyError`` of kind ``SleepyError/Kind/loadFailure`` —
    ///   exit 4, never the timeout exit 3 this case used to be mistaken for.
    public func error(url: URL?) -> SleepyError {
        let page: String = url.map { " \($0.absoluteString)" } ?? " the page"
        switch self {
        case .neverLaunched:
            return SleepyError(
                kind: .loadFailure,
                message: "WebKit could not start under this sandbox: its web content process was gone before"
                    + "\(page) began loading.",
                nextMove: "Run the command outside the sandbox — in Claude Code, set dangerouslyDisableSandbox on "
                    + "that one Bash call, or allow WebKit with /sandbox.",
            )
        case .crashedMidLoad:
            return SleepyError(
                kind: .loadFailure,
                message: "WebKit's web content process ended while loading\(page).",
                nextMove: "Retry; if it repeats, the page is crashing the renderer — narrow it down with a smaller "
                    + "page or by loading its resources one at a time.",
            )
        }
    }
}
