import Foundation
import SleepyHollow
import Testing

/// `KeyChord`: Playwright's key vocabulary — DOM `KeyboardEvent.key` names,
/// modifiers joined with `+` — parsed once, so a bad chord is a usage error
/// before any page is touched.
struct KeyChordTests {
    @Test func `a named key parses with no modifiers`() throws {
        let chord = try KeyChord(parsing: "Enter")
        #expect(chord.key == "Enter")
        #expect(chord.modifiers.isEmpty)
    }

    @Test func `modifiers are read in order before the key`() throws {
        let chord = try KeyChord(parsing: "Shift+Meta+K")
        #expect(chord.modifiers == [.shift, .meta])
        #expect(chord.key == "K")
    }

    @Test func `the plus key parses alone and after a modifier`() throws {
        #expect(try KeyChord(parsing: "+").key == "+")
        let chord = try KeyChord(parsing: "Shift++")
        #expect(chord.modifiers == [.shift])
        #expect(chord.key == "+")
    }

    @Test func `ControlOrMeta is Meta on a Mac`() throws {
        #expect(try KeyChord(parsing: "ControlOrMeta+K").modifiers == [.meta])
    }

    @Test func `a single printable character is a key`() throws {
        #expect(try KeyChord(parsing: "a").key == "a")
        #expect(try KeyChord(parsing: "é").key == "é")
        #expect(try KeyChord(parsing: " ").key == " ")
    }

    @Test func `Space is accepted as a name for the space bar`() throws {
        #expect(try KeyChord(parsing: "Space").key == " ")
    }

    @Test func `a modifier pressed alone is a key`() throws {
        let chord = try KeyChord(parsing: "Shift")
        #expect(chord.key == "Shift")
        #expect(chord.modifiers.isEmpty)
    }

    @Test(arguments: ["", "enter", "Hyper+A", "Shift+", "Meta+Shift+Meta+K", "Return", "Shift+Enterr"])
    func `an unknown or malformed chord is a usage error that teaches`(raw: String) {
        do {
            _ = try KeyChord(parsing: raw)
            Issue.record("'\(raw)' parsed")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.nextMove?.contains("Enter") == true)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func `a misspelled name suggests the right case`() {
        do {
            _ = try KeyChord(parsing: "arrowdown")
            Issue.record("parsed")
        } catch let error as SleepyError {
            #expect(error.message.contains("ArrowDown"))
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func `a chord reads back as it is written`() throws {
        #expect(try KeyChord(parsing: "Shift+Tab").description == "Shift+Tab")
        #expect(try KeyChord(parsing: "ControlOrMeta+k").description == "Meta+k")
        #expect(try KeyChord(parsing: "Shift++").description == "Shift++")
    }

    @Test func `a chord crosses the wire as its string`() throws {
        let chord = try KeyChord(parsing: "Meta+K")
        let data = try JSONEncoder().encode([chord])
        #expect(String(decoding: data, as: UTF8.self) == "[\"Meta+K\"]")
        #expect(try JSONDecoder().decode([KeyChord].self, from: data) == [chord])
    }

    // MARK: - The physical key a chord presses

    @Test func `a letter resolves to its US key and character`() throws {
        let stroke = try KeyChord(parsing: "a").keystroke
        #expect(stroke.keyCode == 0)
        #expect(stroke.characters == "a")
        #expect(stroke.modifiers.isEmpty)
    }

    @Test func `an upper-case letter is the same key with Shift held`() throws {
        let stroke = try KeyChord(parsing: "A").keystroke
        #expect(stroke.keyCode == 0)
        #expect(stroke.characters == "A")
        #expect(stroke.charactersIgnoringModifiers == "a")
        #expect(stroke.modifiers == [.shift])
    }

    @Test func `Shift with a letter types the upper case, as a keyboard does`() throws {
        let stroke = try KeyChord(parsing: "Shift+a").keystroke
        #expect(stroke.characters == "A")
        #expect(stroke.modifiers == [.shift])
    }

    @Test func `a shifted symbol holds Shift on its base key`() throws {
        let stroke = try KeyChord(parsing: "!").keystroke
        #expect(stroke.keyCode == 18)
        #expect(stroke.charactersIgnoringModifiers == "1")
        #expect(stroke.modifiers == [.shift])
    }

    @Test func `named keys resolve to their Mac key codes`() throws {
        #expect(try KeyChord(parsing: "Enter").keystroke.keyCode == 36)
        #expect(try KeyChord(parsing: "Tab").keystroke.keyCode == 48)
        #expect(try KeyChord(parsing: "Escape").keystroke.keyCode == 53)
        #expect(try KeyChord(parsing: "ArrowDown").keystroke.keyCode == 125)
        #expect(try KeyChord(parsing: "Backspace").keystroke.keyCode == 51)
    }

    @Test func `a character with no key on a US keyboard is typed as unidentified`() throws {
        let stroke = try KeyChord(parsing: "é").keystroke
        #expect(stroke.characters == "é")
        #expect(stroke.keyCode == Keystroke.unidentifiedKeyCode)
    }

    @Test func `typing a string is one keystroke per character, with newline as Enter`() {
        let strokes = Keystroke.typing("Hi\n")
        #expect(strokes.map(\.characters) == ["H", "i", "\r"])
        #expect(strokes.map(\.keyCode) == [4, 34, 36])
        #expect(strokes[0].modifiers == [.shift])
    }
}
