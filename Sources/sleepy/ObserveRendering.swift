import Foundation
import SleepyHollow

/// Turns an observe verb's result into the bytes `--format` asked for.
///
/// Wiring only: the terse text belongs to the result type (`ConsoleLog` and
/// `WireLog` each render their own), and the JSON shape is the type's own
/// `Codable` form. This just picks one and adds the trailing newline a
/// terminal expects.
enum ObserveRendering {
    /// The encoder both observe verbs emit JSON with: stable key order, so the
    /// same invocation emits the same bytes every time.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Encodes `value` as `format`, using `text` for
    /// `OutputFormat.text`.
    ///
    /// - Parameters:
    ///   - value: the observe verb's result, encoded for `json`.
    ///   - text: the result's own terse rendering, used for `text`.
    ///   - format: the format the invocation resolved to.
    ///   - verb: the verb doing the rendering, so an unsupported format names
    ///     the invocation that produced it rather than "here".
    static func render(
        _ value: some Encodable,
        text: String,
        as format: OutputFormat,
        verb: String,
    ) throws -> Data {
        switch format {
        case .json:
            return try encoder.encode(value)
        case .text:
            return text.isEmpty ? Data() : Data((text + "\n").utf8)
        case .html, .outline:
            throw SleepyError(
                kind: .usage,
                message: "'\(verb)' doesn't support --format \(format.rawValue).",
                nextMove: "Choose one of: json, text.",
            )
        }
    }
}
