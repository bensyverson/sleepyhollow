import Foundation

public extension PageHost {
    /// Runs `body` as ``evaluate(_:arguments:in:budget:)`` does and decodes
    /// its completion value as `type`.
    ///
    /// The JSON-text form transports a string *quoted*, so an embedder that
    /// compares its answer against `"ok"` reads a mismatch between two strings
    /// that look the same. This form decodes instead: a JavaScript string
    /// arrives as a `String`, a number as an `Int` or `Double`, `null` as
    /// `nil` in an `Optional`, an object as any `Decodable` struct with
    /// matching keys.
    ///
    /// ```swift
    /// let title = try await host.evaluate("return document.title;", as: String.self)
    /// ```
    ///
    /// `as:` is required on purpose: an inferred `String` result would pick
    /// the JSON-text overload, which is the very trap this one exists to
    /// remove.
    ///
    /// - Parameter body: an async function body: it may `await`, and must
    ///   `return` the value to transport.
    /// - Parameter type: what to decode the page's value as.
    /// - Parameter arguments: values put in scope under their keys; each must
    ///   be JSON-serializable.
    /// - Parameter world: ``InjectedScript/World/isolated`` by default, as
    ///   for the JSON-text form.
    /// - Parameter budget: seconds to wait for the answer, or `nil` for the
    ///   host's ``callBudget``.
    /// - Returns: the page's value, decoded.
    /// - Throws: ``EvaluationError/typeMismatch(expected:json:detail:)`` with
    ///   the page's JSON when it does not decode as `type`, and everything
    ///   ``evaluate(_:arguments:in:budget:)`` throws —
    ///   ``EvaluationError/javaScript(message:)`` when the body throws or
    ///   does not parse.
    func evaluate<Value: Decodable>(
        _ body: String,
        as type: Value.Type,
        arguments: [String: Any] = [:],
        in world: InjectedScript.World = .isolated,
        budget: TimeInterval? = nil,
    ) async throws -> Value {
        let json: String = try await evaluate(body, arguments: arguments, in: world, budget: budget)
        return try Self.decode(type, from: json)
    }

    /// Decodes one page answer, turning the decoder's failure into a
    /// ``EvaluationError/typeMismatch(expected:json:detail:)`` that shows
    /// what the page sent.
    internal static func decode<Value: Decodable>(_ type: Value.Type, from json: String) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: Data(json.utf8))
        } catch let error as DecodingError {
            throw EvaluationError.typeMismatch(
                expected: String(describing: type),
                json: json,
                detail: Self.describing(error),
            )
        }
    }

    /// The decoder's complaint in one sentence, with the key path it failed
    /// at when there is one.
    private static func describing(_ error: DecodingError) -> String {
        let context: DecodingError.Context
        switch error {
        case let .typeMismatch(_, found), let .valueNotFound(_, found),
             let .keyNotFound(_, found), let .dataCorrupted(found):
            context = found
        @unknown default:
            return String(describing: error)
        }
        let path: String = context.codingPath.map(\.stringValue).joined(separator: ".")
        let location: String = path.isEmpty ? "" : " (at \(path))"
        return context.debugDescription + location
    }
}
