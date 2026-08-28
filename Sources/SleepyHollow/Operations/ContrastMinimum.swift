import Foundation

/// The bar `sleepy contrast` holds text to: a named WCAG 2 conformance level,
/// or one bare ratio applied to every size.
///
/// Named constants exist because WCAG's bar is *two* numbers, not one — large
/// text has a lower threshold — and an agent that types `4.5` never learns
/// that. `wcag-aa` and `wcag-aaa` carry both numbers; a bare ratio carries
/// one and applies it regardless of size, which is what a designer asking
/// "is anything under 3:1?" means.
///
/// Large text is WCAG's own definition, in CSS pixels: at least 24px, or at
/// least 18.66px when bold (18pt and 14pt bold).
public enum ContrastMinimum: Friendly, CustomStringConvertible {
    /// WCAG 2 level AA: 4.5:1 normal, 3:1 large.
    case wcagAA
    /// WCAG 2 level AAA: 7:1 normal, 4.5:1 large.
    case wcagAAA
    /// One ratio, applied to text of every size.
    case ratio(Double)

    /// The spelling `--min` accepts for ``wcagAA``.
    public static let wcagAAName: String = "wcag-aa"

    /// The spelling `--min` accepts for ``wcagAAA``.
    public static let wcagAAAName: String = "wcag-aaa"

    /// The ratio text at normal size must meet.
    public var normalThreshold: Double {
        switch self {
        case .wcagAA: 4.5
        case .wcagAAA: 7.0
        case let .ratio(value): value
        }
    }

    /// The ratio text at large size must meet.
    public var largeThreshold: Double {
        switch self {
        case .wcagAA: 3.0
        case .wcagAAA: 4.5
        case let .ratio(value): value
        }
    }

    /// The minimum as it is typed and printed: a constant's name, or the
    /// ratio itself.
    public var description: String {
        switch self {
        case .wcagAA: Self.wcagAAName
        case .wcagAAA: Self.wcagAAAName
        case let .ratio(value): Self.text(for: value)
        }
    }

    /// Reads `text` as a named constant or a bare ratio.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` when it is
    ///   neither, or a ratio below 1 — the contrast ratio of a colour with
    ///   itself, so no text can be under it.
    public static func parse(_ text: String) throws -> ContrastMinimum {
        let trimmed: String = text.trimmingCharacters(in: .whitespaces).lowercased()
        switch trimmed {
        case wcagAAName, "aa": return .wcagAA
        case wcagAAAName, "aaa": return .wcagAAA
        default: break
        }
        guard let value = Double(trimmed) else {
            throw SleepyError(
                kind: .usage,
                message: "'\(text)' is not a contrast minimum.",
                nextMove: "Use \(wcagAAName) (the default), \(wcagAAAName), or a bare ratio like 3.5.",
            )
        }
        guard value >= 1 else {
            throw SleepyError(
                kind: .usage,
                message: "'\(text)' is below 1:1, which no text can fail.",
                nextMove: "Contrast ratios run from 1 (identical colours) to 21 (black on white).",
            )
        }
        return .ratio(value)
    }

    /// A ratio without a trailing `.0`, so `3` prints as `3` and `3.25` keeps
    /// its digits.
    private static func text(for value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// Encoded as the single string it is typed as, so the JSON a verb emits reads
/// `"minimum": "wcag-aa"` rather than a tagged union nobody asked for.
public extension ContrastMinimum {
    /// Decodes the spelling ``description`` produces.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text: String = try container.decode(String.self)
        do {
            self = try ContrastMinimum.parse(text)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "'\(text)' is not a contrast minimum.",
            )
        }
    }

    /// Encodes as ``description``.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
