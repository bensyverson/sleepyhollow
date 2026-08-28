/// `sleepy submit`: submit the form a selector names, or the form the
/// selector's element belongs to.
///
/// The submission goes through a real, cancellable `submit` event — a page
/// that calls `preventDefault()` stops it, and the outcome says so by
/// reporting no navigation. A form the browser considers invalid is refused
/// with the field that failed, rather than submitted behind the validation's
/// back.
public struct SubmitOperation: ExecutablePageOperation {
    /// This operation's typed result.
    public typealias Output = ActionOutcome

    /// The wire identifier.
    public static let kind: String = "submit"

    /// The CSS selector naming the form, or an element inside it.
    public var selector: String

    /// Creates the operation.
    public init(selector: String) {
        self.selector = selector
    }

    /// Submits the form for the first element matching ``selector``.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/negative`` when
    ///   nothing matches or the form fails its own validation, and
    ///   ``SleepyError/Kind/usage`` when the element is not a form and is not
    ///   inside one.
    @MainActor
    public func execute(on host: PageHost) async throws -> ActionOutcome {
        try await ActionScript.outcome(
            for: .submit,
            target: .selector(selector),
            body: ActionScript.submitBody,
            on: host,
        )
    }
}
