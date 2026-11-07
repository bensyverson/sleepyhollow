import Foundation

/// The US ANSI layout: which Mac key code each named key and printable
/// character lives on.
///
/// Key codes are the `kVK_*` constants from Carbon's `Events.h`; the named
/// keys' characters are what AppKit puts in `NSEvent.characters` for them
/// (the function-key range `U+F700…` for arrows, Home, End and the rest).
extension Keystroke {
    /// One printable character's key: its code, its unshifted face, and
    /// whether the character is the shifted face.
    struct PrintableKey {
        /// The `kVK_*` key code.
        let keyCode: UInt16
        /// What the key types without Shift.
        let base: Character
        /// Whether the character this entry was looked up by needs Shift.
        let shifted: Bool
    }

    /// One named key's code and the character AppKit reports for it.
    struct NamedKey {
        /// The `kVK_*` key code.
        let keyCode: UInt16
        /// `NSEvent.characters` for the key.
        let character: String
    }

    /// The named keys, by DOM `KeyboardEvent.key` name, in the order they
    /// are documented.
    static let namedKeys: [String] = [
        "Enter", "Tab", "Escape", "Backspace", "Delete",
        "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight",
        "Home", "End", "PageUp", "PageDown",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
    ]

    /// Every named key's code and character.
    static let named: [String: NamedKey] = {
        func function(_ offset: UInt32) -> String {
            String(Character(Unicode.Scalar(0xF700 + offset)!))
        }
        var table: [String: NamedKey] = [
            "Enter": NamedKey(keyCode: 36, character: "\r"),
            "Tab": NamedKey(keyCode: 48, character: "\t"),
            "Escape": NamedKey(keyCode: 53, character: "\u{1B}"),
            "Backspace": NamedKey(keyCode: 51, character: "\u{7F}"),
            "Delete": NamedKey(keyCode: 117, character: function(0x28)),
            "ArrowUp": NamedKey(keyCode: 126, character: function(0x00)),
            "ArrowDown": NamedKey(keyCode: 125, character: function(0x01)),
            "ArrowLeft": NamedKey(keyCode: 123, character: function(0x02)),
            "ArrowRight": NamedKey(keyCode: 124, character: function(0x03)),
            "Home": NamedKey(keyCode: 115, character: function(0x29)),
            "End": NamedKey(keyCode: 119, character: function(0x2B)),
            "PageUp": NamedKey(keyCode: 116, character: function(0x2C)),
            "PageDown": NamedKey(keyCode: 121, character: function(0x2D)),
        ]
        let functionCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (index, code) in functionCodes.enumerated() {
            table["F\(index + 1)"] = NamedKey(keyCode: code, character: function(0x04 + UInt32(index)))
        }
        return table
    }()

    /// The modifier keys' own codes (left-hand side).
    static let modifierKeyCodes: [KeyChord.Modifier: UInt16] = [
        .shift: 56, .control: 59, .alt: 58, .meta: 55,
    ]

    /// Unshifted face, key code: every printable key on the layout.
    private static let unshifted: [(Character, UInt16)] = [
        ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8), ("v", 9),
        ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("1", 18), ("2", 19),
        ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("=", 24), ("9", 25), ("7", 26), ("-", 27), ("8", 28),
        ("0", 29), ("]", 30), ("o", 31), ("u", 32), ("[", 33), ("i", 34), ("p", 35), ("l", 37), ("j", 38),
        ("'", 39), ("k", 40), (";", 41), ("\\", 42), (",", 43), ("/", 44), ("n", 45), ("m", 46), (".", 47),
        ("`", 50), (" ", 49),
    ]

    /// Unshifted face to shifted face, for the keys whose shifted face is not
    /// simply the upper case.
    private static let symbolShifts: [Character: Character] = [
        "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
        "-": "_", "=": "+", "[": "{", "]": "}", "\\": "|", ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?",
        "`": "~",
    ]

    /// Every printable character the layout can type, by character.
    static let printable: [Character: PrintableKey] = {
        var table: [Character: PrintableKey] = [:]
        for (face, code) in unshifted {
            table[face] = PrintableKey(keyCode: code, base: face, shifted: false)
            let shiftedFace: Character = shiftedFace(of: face)
            if shiftedFace != face {
                table[shiftedFace] = PrintableKey(keyCode: code, base: face, shifted: true)
            }
        }
        return table
    }()

    /// What a key types with Shift held: the symbol above it, or the upper
    /// case of a letter. The space bar types a space either way.
    static func shiftedFace(of base: Character) -> Character {
        if let symbol = symbolShifts[base] { return symbol }
        return Character(base.uppercased())
    }
}
