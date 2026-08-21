/// One dialog the page raised and how the policy answered it.
public struct DialogRecord: Friendly {
    /// The dialog's kind.
    ///
    /// `beforeunload` deliberately has no case: `WKUIDelegate` exposes no
    /// public hook for it, so WebKit always leaves the page (the policy's
    /// answer) and a record could never be produced — an unreachable case
    /// would be a lie in the API surface.
    public enum Kind: String, Friendly {
        /// `alert()` — always acknowledged.
        case alert
        /// `confirm()` — answered per ``DialogPolicy/acceptsConfirms``.
        case confirm
        /// `prompt()` — answered per ``DialogPolicy/promptResponse``.
        case prompt
    }

    /// The answer the policy gave.
    public enum Response: Friendly {
        /// An alert was acknowledged.
        case acknowledged
        /// A confirm was accepted.
        case accepted
        /// A confirm or prompt was cancelled.
        case dismissed
        /// A prompt was answered with text.
        case answered(String)
    }

    /// The dialog's kind.
    public var kind: Kind

    /// The message the page showed.
    public var message: String

    /// The answer given.
    public var response: Response

    /// Creates a record.
    public init(kind: Kind, message: String, response: Response) {
        self.kind = kind
        self.message = message
        self.response = response
    }
}
