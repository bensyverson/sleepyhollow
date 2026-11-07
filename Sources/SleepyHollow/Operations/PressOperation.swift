/// `sleepy press`: real keystrokes — typed text, then key chords — sent to
/// whatever has focus, the way a keyboard sends them.
///
/// The keys come from the host's window (``TrustedInput``), so the page sees
/// `isTrusted` true and the browser runs each key's default action: text is
/// inserted into a focused field, Tab moves focus, Enter submits a form,
/// Escape closes a modal dialog. A page that ignores untrusted keys takes
/// these. Keys use Playwright's vocabulary (``KeyChord``); ``text`` is typed
/// one character per keystroke on a US layout (``Keystroke``), input methods
/// aside.
///
/// With a ``selector``, that element is focused first, as ``FocusOperation``
/// focuses it; without one, the keys go to whatever has focus — `body` when
/// nothing does.
///
/// **Whether the page navigated** is judged by the host, after every key has
/// landed: a key's default action runs in no listener, so the page-side
/// submit watcher the synthesized verbs use would hear nothing, and with
/// `--no-js` no listener runs at all. The host's ordered check
/// (``PageHost/navigationStarted(sinceRequests:)``) answers either way.
///
/// What WebKit does on its own for a key — inserting text, moving focus,
/// submitting — happens; what a Mac app does through its menu bar does not:
/// `Meta+A`, `Meta+C` and `Meta+V` reach the page as key events, but the
/// host has no Edit menu to turn them into select-all, copy or paste.
public struct PressOperation: ExecutablePageOperation {
    /// This operation's typed result.
    public typealias Output = ActionOutcome

    /// The wire identifier.
    public static let kind: String = "press"

    /// The chords pressed, in order, after ``text`` is typed.
    public var keys: [KeyChord]

    /// Text typed first, one keystroke per character; `nil` for none.
    public var text: String?

    /// A CSS selector focused before any key goes down; `nil` sends the keys
    /// to whatever has focus.
    public var selector: String?

    /// Creates the operation.
    ///
    /// - Parameter keys: chords pressed in order, after `text`.
    /// - Parameter text: text typed first, one keystroke per character.
    /// - Parameter selector: the element to focus first, if any.
    public init(keys: [KeyChord] = [], text: String? = nil, selector: String? = nil) {
        self.keys = keys
        self.text = text
        self.selector = selector
    }

    /// Types ``text`` and presses ``keys``, then reports where they went.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` when
    ///   there is nothing to press, the host is windowless, or ``selector``
    ///   names an element that does not take focus;
    ///   ``SleepyError/Kind/negative`` when ``selector`` matches nothing or
    ///   a disabled control; ``SleepyError/Kind/timeout`` when the page does
    ///   not handle the keys within the host's call budget.
    @MainActor
    public func execute(on host: PageHost) async throws -> ActionOutcome {
        let strokes: [Keystroke] = Keystroke.typing(text ?? "") + keys.map(\.keystroke)
        guard !strokes.isEmpty else {
            throw SleepyError(
                kind: .usage,
                message: "'press' needs keys to press or text to type.",
                nextMove: "Name keys as arguments (sleepy press Enter, sleepy press Meta+K) "
                    + "or pass --text 'hello'.",
            )
        }
        let input = try TrustedInput(for: host, action: "key press")
        if let selector {
            _ = try await FocusOperation(selector: selector).execute(on: host)
        }
        let arguments: [String: Any] = ["pressKey": ActionScript.pressTargetKey]
        let target: ActionScript.Report = try await ActionScript.report(
            for: .press,
            target: .selector(selector ?? ""),
            body: ActionScript.pressTargetBody,
            arguments: arguments,
            on: host,
        )
        let requests: Int = host.navigationRequestCount
        input.send(strokes)
        try await input.keysLanded()
        let navigating: Bool = await host.navigationStarted(sinceRequests: requests)
        // The focused field's value, while the page that holds it is still
        // there to ask; a page being replaced has none to give.
        let after: ActionScript.Report? = navigating ? nil : try? await ActionScript.report(
            for: .press,
            target: .selector(selector ?? ""),
            body: ActionScript.pressValueBody,
            arguments: arguments,
            on: host,
        )
        return ActionOutcome(
            action: .press,
            selector: selector,
            tagName: target.tagName ?? "body",
            value: after?.value,
            startedNavigation: navigating,
        )
    }
}
