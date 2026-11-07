/// One ordered action in a one-shot flow, executed after the load event and
/// before the wait condition gates the verb's read. Each step auto-waits for
/// its selector to become actionable within the load's budget.
///
/// These are the flag forms (`--click`, `--fill`, `--submit`, `--focus`,
/// `--hover`, `--type`, `--press`) that let a two-step check — or a shot of
/// a state no URL reaches — run without naming a session. Mechanism is
/// honest, and differs by step: `fill` and `submit` are synthesized DOM
/// events (`isTrusted` false); `click`, `hover`, `type` and `press` are real
/// `NSEvent`s sent through the host's window (`isTrusted` true, default
/// actions run); `focus` is the element's own `focus()`, as by keyboard.
public enum ActionStep: Friendly {
    /// Click the first element matching `selector`.
    case click(selector: String)
    /// Set the value of the first element matching `selector` and dispatch
    /// input events.
    case fill(selector: String, value: String)
    /// Submit the form matching (or containing) `selector`.
    case submit(selector: String)
    /// Focus the first element matching `selector` as a keyboard would, so
    /// `:focus-visible` matches (see ``FocusOperation``).
    case focus(selector: String)
    /// Move a real pointer over the center of the first element matching
    /// `selector`, so `:hover` matches (see ``HoverOperation``).
    case hover(selector: String)
    /// Type `text` into whatever has focus, one real keystroke per character.
    case type(text: String)
    /// Press one key chord on whatever has focus.
    case press(KeyChord)
}
