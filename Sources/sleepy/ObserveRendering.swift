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
    static func render(_ value: some Encodable, text: String, as format: OutputFormat) throws -> Data {
        switch format {
        case .json:
            return try encoder.encode(value)
        case .text:
            return text.isEmpty ? Data() : Data((text + "\n").utf8)
        case .html, .outline:
            throw SleepyError(
                kind: .usage,
                message: "That format is not available here.",
                nextMove: "Choose one of: json, text.",
            )
        }
    }
}
