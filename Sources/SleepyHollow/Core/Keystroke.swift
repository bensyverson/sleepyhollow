import Foundation

/// The physical key a ``KeyChord`` presses on a US keyboard: the Mac virtual
/// key code, the characters it types, and the modifiers held.
///
/// This is what an `NSEvent` key event is built from. WebKit derives the DOM
/// event's `code` from the key code and its `key` from the characters, so
/// both have to be what a real keyboard would send — `A` is the `a` key with
/// Shift held, and `!` is the `1` key with Shift held.
///
/// The layout is US ANSI, the one Playwright's own key definitions assume. A
/// character that has no key on it (`é`, `中`, an emoji) is still typed — the
/// characters are what a text field inserts — but with
/// ``unidentifiedKeyCode``, so the page reads `code` as `"Unidentified"` rather than
/// the plausible wrong answer of some real key's. Input methods (IME) are out
/// of scope.
public struct Keystroke: Friendly {
    /// The key code given to a character that has no key on a US keyboard:
    /// one no Mac keyboard sends, which WebKit reports as `code` `"Unidentified"`.
    public static let unidentifiedKeyCode: UInt16 = 0xFFFF

    /// The Mac virtual key code (`kVK_*`).
    public var keyCode: UInt16

    /// What the key types with its modifiers applied — `NSEvent.characters`.
    public var characters: String

    /// What the key types with no modifiers —
    /// `NSEvent.charactersIgnoringModifiers`.
    public var charactersIgnoringModifiers: String

    /// The modifiers held while the key goes down, in the order they are
    /// pressed.
    public var modifiers: [KeyChord.Modifier]

    /// The modifier this keystroke presses on its own — `Shift` pressed and
    /// released — or `nil` for an ordinary key. A modifier key reaches the
    /// page as `keydown`/`keyup` too, but AppKit sends it as a flags change.
    public var modifierKey: KeyChord.Modifier?

    /// Creates a keystroke.
    public init(
        keyCode: UInt16,
        characters: String,
        charactersIgnoringModifiers: String,
        modifiers: [KeyChord.Modifier] = [],
        modifierKey: KeyChord.Modifier? = nil,
    ) {
        self.keyCode = keyCode
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.modifiers = modifiers
        self.modifierKey = modifierKey
    }

    /// The keystroke a chord presses.
    public init(chord: KeyChord) {
        if let modifier = KeyChord.Modifier(rawValue: chord.key) {
            self.init(
                keyCode: Self.modifierKeyCodes[modifier] ?? Self.unidentifiedKeyCode,
                characters: "",
                charactersIgnoringModifiers: "",
                modifiers: chord.modifiers,
                modifierKey: modifier,
            )
        } else if let named = Self.named[chord.key] {
            self.init(
                keyCode: named.keyCode,
                characters: named.character,
                charactersIgnoringModifiers: named.character,
                modifiers: chord.modifiers,
            )
        } else {
            self.init(character: chord.key, holding: chord.modifiers)
        }
    }

    /// The keystrokes that type `text`, one per character: a newline is
    /// Enter and a tab is Tab, as on a keyboard.
    public static func typing(_ text: String) -> [Keystroke] {
        text.map { character in
            switch character {
            case "\n", "\r", "\r\n":
                Keystroke(chord: KeyChord(modifiers: [], key: "Enter"))
            case "\t":
                Keystroke(chord: KeyChord(modifiers: [], key: "Tab"))
            default:
                Keystroke(character: String(character), holding: [])
            }
        }
    }

    /// A printable character's key, Shift added when the character is a
    /// key's shifted face and applied when Shift is already held.
    private init(character: String, holding held: [KeyChord.Modifier]) {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
              let key = Self.printable[Character(scalar)]
        else {
            self.init(
                keyCode: Self.unidentifiedKeyCode,
                characters: character,
                charactersIgnoringModifiers: character,
                modifiers: held,
            )
            return
        }
        var modifiers: [KeyChord.Modifier] = held
        if key.shifted, !modifiers.contains(.shift) {
            modifiers.append(.shift)
        }
        let typed: String = modifiers.contains(.shift) ? String(Self.shiftedFace(of: key.base)) : String(key.base)
        self.init(
            keyCode: key.keyCode,
            characters: typed,
            charactersIgnoringModifiers: String(key.base),
            modifiers: modifiers,
        )
    }
}
