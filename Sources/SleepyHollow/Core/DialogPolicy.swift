/// How JavaScript dialogs are answered — never blocking, always recorded.
///
/// The default declines everything: alerts are acknowledged, confirms
/// cancelled, prompts cancelled, `beforeunload` allowed to leave. Declining is
/// the least-side-effect answer (an auto-accepted "Delete this item?" is an
/// agent-caused incident); every dialog lands in the output as a
/// ``DialogRecord`` so the agent sees what was declined and reruns with an
/// explicit override.
public struct DialogPolicy: Friendly {
    /// Whether `confirm()` returns true. Default `false` (cancel).
    public var acceptsConfirms: Bool

    /// The text `prompt()` receives; `nil` cancels. Default `nil`.
    public var promptResponse: String?

    /// Creates a policy; the default declines everything.
    public init(acceptsConfirms: Bool = false, promptResponse: String? = nil) {
        self.acceptsConfirms = acceptsConfirms
        self.promptResponse = promptResponse
    }
}
