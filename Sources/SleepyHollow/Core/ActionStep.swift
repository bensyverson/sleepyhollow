/// One ordered action in a one-shot flow, executed after settle and before
/// the verb's read.
///
/// These are the flag forms (`--click`, `--fill`, `--submit`) that let a
/// two-step check run without naming a session. Mechanism is honest:
/// synthesized events, not OS-level hit-testing.
public enum ActionStep: Friendly {
    /// Click the first element matching `selector`.
    case click(selector: String)
    /// Set the value of the first element matching `selector` and dispatch
    /// input events.
    case fill(selector: String, value: String)
    /// Submit the form matching (or containing) `selector`.
    case submit(selector: String)
}
