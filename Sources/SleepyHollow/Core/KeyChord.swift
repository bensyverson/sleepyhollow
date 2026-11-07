import Foundation

/// One key press, with the modifiers held while it goes down, in Playwright's
/// vocabulary: DOM `KeyboardEvent.key` names joined with `+` — `Enter`,
/// `Tab`, `ArrowDown`, `Meta+K`, `Shift+Tab`.
///
/// The vocabulary is the one agents already know from Playwright (the ruling
/// on leaf `XerXuw`, 2026-11-06): named keys are case-sensitive DOM key
/// names, a single character is that character's key, and the modifiers are
/// `Shift`, `Control`, `Alt` and `Meta`, plus `ControlOrMeta`, which is
/// `Meta` on a Mac. `+` is a key too: `+` alone, or `Shift++`.
///
/// A chord is parsed once, before any page is touched, so a misspelled key is
/// a usage error rather than a keystroke the page never expected. It crosses
/// the session wire as the string it reads back as.
///
/// ```swift
/// let chord = try KeyChord(parsing: "Shift+Tab")
/// try await host.press([chord])
/// ```
public struct KeyChord: Friendly, CustomStringConvertible {
    /// A key held down while the chord's key is pressed.
    public enum Modifier: String, Friendly, CaseIterable {
        /// The Shift key.
        case shift = "Shift"
        /// The Control key.
        case control = "Control"
        /// The Option key, which the DOM calls `Alt`.
        case alt = "Alt"
        /// The Command key, which the DOM calls `Meta`.
        case meta = "Meta"
    }

    /// The modifiers held, in the order they go down.
    public var modifiers: [Modifier]

    /// The pressed key's DOM name: a named key such as `Enter`, a modifier
    /// pressed on its own such as `Shift`, or a single character.
    public var key: String

    /// The named keys this vocabulary accepts beyond single characters and
    /// the modifiers themselves.
    public static var namedKeys: [String] {
        Keystroke.namedKeys
    }

    /// Parses a chord such as `Meta+K`.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` for an
    ///   empty chord, an unknown modifier, a modifier named twice, or a key
    ///   that is neither a named key nor a single character — with the right
    ///   spelling when only the case was wrong.
    public init(parsing raw: String) throws {
        let parts: [String]
        let key: String
        if raw == "+" {
            parts = []
            key = "+"
        } else if raw.hasSuffix("++") {
            parts = raw.dropLast(2).split(separator: "+", omittingEmptySubsequences: false).map(String.init)
            key = "+"
        } else {
            var split: [String] = raw.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
            key = split.removeLast()
            parts = split
        }
        var modifiers: [Modifier] = []
        for part in parts {
            guard let modifier = Self.modifier(named: part) else {
                throw Self.unknown(raw, detail: "'\(part)' is not a modifier (Shift, Control, Alt, Meta, ControlOrMeta).")
            }
            guard !modifiers.contains(modifier) else {
                throw Self.unknown(raw, detail: "'\(modifier.rawValue)' is held twice.")
            }
            modifiers.append(modifier)
        }
        let resolved: String = try Self.resolvedKey(key, in: raw)
        self.modifiers = modifiers
        self.key = resolved
    }

    /// Creates a chord from parts already known to be valid — the typing
    /// path, which never parses.
    init(modifiers: [Modifier], key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    /// The chord as Playwright would spell it, `ControlOrMeta` resolved.
    public var description: String {
        (modifiers.map(\.rawValue) + [key == " " ? "Space" : key]).joined(separator: "+")
    }

    /// The physical key this chord presses on a US keyboard, and what it
    /// types.
    public var keystroke: Keystroke {
        Keystroke(chord: self)
    }

    // MARK: - Parsing

    private static func modifier(named name: String) -> Modifier? {
        if name == "ControlOrMeta" { return .meta }
        return Modifier(rawValue: name)
    }

    private static func resolvedKey(_ key: String, in raw: String) throws -> String {
        if key == "Space" { return " " }
        if key.count == 1 { return key }
        if Modifier(rawValue: key) != nil || Keystroke.namedKeys.contains(key) { return key }
        if key.isEmpty {
            throw unknown(raw, detail: "it names no key.")
        }
        let candidates: [String] = Keystroke.namedKeys + Modifier.allCases.map(\.rawValue)
        if let spelled = candidates.first(where: { $0.lowercased() == key.lowercased() }) {
            throw unknown(raw, detail: "key names are case-sensitive: did you mean '\(spelled)'?")
        }
        throw unknown(raw, detail: "'\(key)' is not a DOM key name or a single character.")
    }

    private static func unknown(_ raw: String, detail: String) -> SleepyError {
        SleepyError(
            kind: .usage,
            message: "'\(raw)' is not a key chord: \(detail)",
            nextMove: "Name keys as DOM KeyboardEvent.key does, modifiers joined with '+': Enter, Tab, Escape, "
                + "ArrowDown, Backspace, Meta+K, Shift+Tab, or a single character. "
                + "To type a string, use --text (or the --type step).",
        )
    }

    // MARK: - Codable

    /// Decodes a chord from the string it reads back as.
    public init(from decoder: any Decoder) throws {
        let raw: String = try decoder.singleValueContainer().decode(String.self)
        try self.init(parsing: raw)
    }

    /// Encodes the chord as its ``description``.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
