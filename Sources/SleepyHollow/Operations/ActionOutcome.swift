/// What one act primitive did: the answer `click`, `fill` and `submit` share.
///
/// Deliberately small and factual. It reports what was acted on and whether
/// the page reacted by starting a navigation — the fact the load pipeline
/// needs in order to settle before the verb's read, and the fact an agent
/// needs in order to know the page it is about to read is a different one.
public struct ActionOutcome: Friendly {
    /// Which primitive produced this outcome.
    public enum Action: String, Friendly {
        /// A synthesized pointer/mouse/click sequence.
        case click
        /// A value set natively, with `input` and `change` dispatched.
        case fill
        /// A form submitted through a real, cancellable `submit` event.
        case submit
    }

    /// The primitive that ran.
    public var action: Action

    /// The selector that chose the element.
    public var selector: String

    /// The acted-on element's tag name, lowercased — the form's tag for
    /// ``Action/submit``.
    public var tagName: String

    /// The value the action settled on: what a ``Action/fill`` left in the
    /// field, the form's `id` for a ``Action/submit``, `nil` for a click.
    public var value: String?

    /// Whether the action set the page navigating — a link followed, or a
    /// form submission the page did not cancel.
    public var startedNavigation: Bool

    /// Creates an outcome.
    public init(action: Action, selector: String, tagName: String, value: String? = nil, startedNavigation: Bool) {
        self.action = action
        self.selector = selector
        self.tagName = tagName
        self.value = value
        self.startedNavigation = startedNavigation
    }
}
