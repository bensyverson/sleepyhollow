import Foundation
import WebKit

/// Why a ``PageHost/evaluate(_:arguments:in:budget:)`` (or its decoding
/// sibling) did not produce a value — when the *page* is the reason.
///
/// WebKit reports a JavaScript failure as an `NSError` whose
/// `localizedDescription` is only "A JavaScript exception occurred"; the
/// page's own message hides in its `userInfo`. An embedder that logs the
/// error, or compares an answer, then sees nothing it can act on. The host
/// lifts that message into ``javaScript(message:)`` instead, so the reason
/// is in the error's type and its description alike.
///
/// The host's own failures — a spent budget, a cancelled caller, a frame
/// torn down mid-call — are not this type: they stay ``SleepyError`` and
/// `CancellationError`, because the page did nothing wrong.
public enum EvaluationError: Error, Friendly, CustomStringConvertible, LocalizedError {
    /// The body threw, or never parsed. `message` is the page's own:
    /// `Error: deliberate`, `SyntaxError: Unexpected token ';'`, or the bare
    /// value of a `throw` that threw a non-`Error`.
    case javaScript(message: String)

    /// The page answered, but its JSON does not decode as the type the caller
    /// asked for.
    ///
    /// - Parameter expected: the requested type, as Swift names it.
    /// - Parameter json: exactly what the page sent, as JSON text.
    /// - Parameter detail: the decoder's own account of where the mismatch is.
    case typeMismatch(expected: String, json: String, detail: String)

    /// The failure in one sentence, followed by the next move.
    public var description: String {
        switch self {
        case let .javaScript(message):
            "The page threw while evaluating the script: \(message)"
        case let .typeMismatch(expected, json, detail):
            "The page returned \(Self.excerpt(of: json)), which does not decode as \(expected): \(detail) "
                + "Return a value of that shape from the body, or decode it as a type that matches."
        }
    }

    /// The same as ``description``, so `localizedDescription` names the
    /// page's message too.
    public var errorDescription: String? {
        description
    }

    /// The page's JSON, cut short enough to read in one line.
    private static func excerpt(of json: String) -> String {
        json.count > 200 ? String(json.prefix(200)) + "…" : json
    }

    /// The typed error for what WebKit reported, or `nil` when WebKit's
    /// error is not the page's doing.
    ///
    /// Only `WKError.javaScriptExceptionOccurred` is: the other codes describe
    /// the frame or the process, which a ``javaScript(message:)`` would
    /// misattribute to the script.
    static func lifting(_ error: any Error) -> EvaluationError? {
        let details = error as NSError
        guard details.domain == WKError.errorDomain,
              details.code == WKError.Code.javaScriptExceptionOccurred.rawValue
        else { return nil }
        let message: String = (details.userInfo[exceptionMessageKey] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? details.localizedDescription
        return .javaScript(message: message)
    }

    /// WebKit's `userInfo` key carrying the page's own exception message.
    private static let exceptionMessageKey: String = "WKJavaScriptExceptionMessage"
}
