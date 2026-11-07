import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy press` — real keystrokes in a live session.
///
/// An act verb: it requires `--session`. For a one-shot flow, ride a loading
/// verb with the `--focus`/`--type`/`--press` steps instead. The keys and the
/// text resolve into one ``PressOperation`` in the library, so the CLI holds
/// no part of the decision.
struct PressCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "press",
        abstract: "Press keys or type text in a live session, as real keystrokes (isTrusted true).",
        discussion: """
        Real input, like click and unlike fill and submit: each key is an AppKit key event sent through the page's window, so the page sees isTrusted true and the browser runs the key's default action — text goes into the focused field, Tab moves focus, Enter submits the form, Escape closes a modal dialog.

        Keys use Playwright's names, DOM KeyboardEvent.key with modifiers joined by '+': Enter, Tab, Escape, Backspace, Delete, ArrowUp/Down/Left/Right, Home, End, PageUp, PageDown, F1-F12, Space, a single character (a, A, 7, !), and the modifiers Shift, Control, Alt, Meta (ControlOrMeta is Meta on a Mac). Names are case-sensitive. Several keys are pressed in order.

        --text types a string one keystroke per character on a US layout (a newline is Enter); it is typed before the keys, so --text 'query' Enter types and submits. Input methods (IME) are out of scope.

        --selector focuses that element first, as Tab would (:focus-visible matches); without it the keys go to whatever has focus. Meta+A, Meta+C and Meta+V reach the page as key events, but there is no Edit menu to select, copy or paste.

        Examples:
          sleepy press --session app --selector '#q' --text 'webkit' Enter
          sleepy press --session app Tab Tab Shift+Tab
          sleepy press --session app Escape
          sleepy dom http://localhost:3000/ --focus '#q' --type 'webkit' --press Enter   # one shot

        Exit codes: 0 pressed, 1 the --selector matched nothing or a disabled control (the reason is on stderr; nothing on stdout), 2 usage — an unknown key name, nothing to press, a --selector that cannot take focus, or a URL instead of --session, 5 no such session.
        """,
    )

    /// The one-shot flags that do the same thing, named by every failure.
    static let oneShotExample: String = "--focus '#q' --type 'webkit' --press Enter"

    @Option(name: .long, help: "The live session to press keys in.")
    var session: String?

    @Argument(help: "Key chords to press in order, e.g. Enter, Tab, Meta+K, Shift+Tab.")
    var keys: [String] = []

    @Option(name: .long, help: "Text to type first, one real keystroke per character.")
    var text: String?

    /// `--element` is the same flag, as on the other act verbs.
    @Option(
        name: [.long, .customLong("element")],
        help: "CSS selector to focus before pressing (--element is the same flag).",
    )
    var selector: String?

    @OptionGroup var out: OutOption

    @OptionGroup var quiet: QuietOption

    @MainActor
    mutating func run() async throws {
        // A URL where the keys go is the one-shot mistake every act verb
        // teaches, not a key named "http://…".
        let url: String? = keys.first { $0.contains("://") }
        let name: SessionName = try ActTarget.session(
            url: url,
            session: session,
            verb: PressOperation.kind,
            example: Self.oneShotExample,
        )
        let chords: [KeyChord] = try keys.map { try KeyChord(parsing: $0) }
        if chords.isEmpty, (text ?? "").isEmpty {
            throw SleepyError(
                kind: .usage,
                message: "'press' needs keys to press or text to type.",
                nextMove: "Name keys as arguments (sleepy press --session <n> Enter) or pass --text 'hello'.",
            )
        }
        let operation = PressOperation(keys: chords, text: text, selector: selector)
        try await ActTarget.act(operation, in: name, to: out.sink)
    }
}
