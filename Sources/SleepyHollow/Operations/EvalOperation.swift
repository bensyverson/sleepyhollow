import Foundation

/// `sleepy eval`: the universal escape hatch — run JavaScript against the page
/// and get its value back as JSON.
///
/// The script is an **async function body**, exactly as
/// `WKWebView.callAsyncJavaScript` defines one: it may `await`, and it must
/// `return` the value to transport. Nothing is auto-wrapped — a body with no
/// `return` yields `null`, because guessing whether a script is an expression
/// or a statement is how a tool starts returning silently wrong answers.
///
/// The value is stringified *page-side*, so what the page can serialize is
/// what crosses. A page-side failure — a thrown error or a syntax error —
/// comes back as a ``SleepyError`` carrying the page's own message, never a
/// WebKit stack trace.
///
/// Evaluation happens in the tool's isolated ``InjectedScript/World`` by
/// default, so an eval cannot collide with page script; pass
/// ``InjectedScript/World/page`` when the page's own globals are the subject.
public struct EvalOperation: ExecutablePageOperation {
    /// This operation's typed result: the value as JSON text.
    public typealias Output = String

    /// The wire identifier.
    public static let kind: String = "eval"

    /// The async function body to evaluate.
    public var source: String

    /// A JSON **object** whose keys arrive in scope as named arguments;
    /// `nil` passes none. Kept as text so the operation stays `Friendly`.
    public var argumentsJSON: String?

    /// Which JavaScript world the body runs in. Default
    /// ``InjectedScript/World/isolated``.
    public var world: InjectedScript.World

    /// Creates the operation.
    public init(source: String, argumentsJSON: String? = nil, world: InjectedScript.World = .isolated) {
        self.source = source
        self.argumentsJSON = argumentsJSON
        self.world = world
    }

    /// Evaluates ``source`` and returns its value as JSON text.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` when
    ///   ``argumentsJSON`` is not a JSON object or the page reports a
    ///   JavaScript failure, and ``SleepyError/Kind/environment`` when WebKit
    ///   could not run the script at all.
    @MainActor
    public func execute(on host: PageHost) async throws -> String {
        let arguments: [String: Any] = try Self.arguments(from: argumentsJSON)
        do {
            return try await host.evaluate(source, arguments: arguments, in: world)
        } catch let error as SleepyError {
            throw error
        } catch {
            throw Self.failure(from: error)
        }
    }

    /// Decodes the `--args` payload into named values for the page.
    static func arguments(from json: String?) throws -> [String: Any] {
        guard let json, !json.isEmpty else { return [:] }
        guard
            let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed]),
            let object = parsed as? [String: Any]
        else {
            throw SleepyError(
                kind: .usage,
                message: "'--args' must be a JSON object; '\(json)' is not one.",
                nextMove: "Pass named values, e.g. --args '{\"count\": 3}'; each key arrives in scope by name.",
            )
        }
        return object
    }

    /// WebKit's userInfo key carrying the page's own exception message.
    private static let exceptionMessageKey: String = "WKJavaScriptExceptionMessage"

    /// Turns WebKit's error into a failure that states the page's complaint.
    private static func failure(from error: any Error) -> SleepyError {
        let details = error as NSError
        guard let message = details.userInfo[exceptionMessageKey] as? String, !message.isEmpty else {
            return SleepyError(
                kind: .environment,
                message: "The page could not run the script: \(details.localizedDescription)",
                nextMove: "Retry against a settled page — a frame that navigates mid-evaluation cannot answer.",
            )
        }
        return SleepyError(
            kind: .usage,
            message: "The page rejected the script: \(message)",
            nextMove: "The body is an async function body — use 'return' to send a value back, and 'await' for promises.",
        )
    }
}
