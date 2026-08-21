/// `sleepy fill`: set a field's value the way a person editing it would leave
/// the page — natively, then `input` and `change`.
///
/// Text inputs and textareas take the value as typed; a checkbox or radio
/// takes a boolean word (`true`, `1`, `on`, `yes`, `checked`, or anything
/// else for off); a `<select>` takes an option's value or its visible label;
/// a contenteditable element takes text. Anything else is refused, because a
/// fill that quietly did nothing is worse than one that says why.
public struct FillOperation: ExecutablePageOperation {
    /// This operation's typed result.
    public typealias Output = ActionOutcome

    /// The wire identifier.
    public static let kind: String = "fill"

    /// The CSS selector whose first match is filled.
    public var selector: String

    /// The value to set, interpreted by the element's kind.
    public var value: String

    /// Creates the operation.
    public init(selector: String, value: String) {
        self.selector = selector
        self.value = value
    }

    /// Fills the first element matching ``selector``.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/negative`` when
    ///   nothing matches, the field is disabled or read-only, or a `<select>`
    ///   has no such option, and ``SleepyError/Kind/usage`` when the element
    ///   holds no value at all.
    @MainActor
    public func execute(on host: PageHost) async throws -> ActionOutcome {
        try await ActionScript.outcome(
            for: .fill,
            selector: selector,
            body: ActionScript.fillBody,
            arguments: ["value": value],
            on: host,
        )
    }
}
