/// One read or act against a page: the seam every verb is built on.
///
/// A `PageOperation` is a `Friendly` value describing what to do — shoot this
/// rect, query this selector, evaluate this script — with a typed ``Output``.
/// One-shot invocations execute the operation against a local page host;
/// sessions ship the identical value over a Unix socket (via
/// ``OperationEnvelope``) to a helper that executes it the same way. The
/// session layer never needs to know which operations exist — only how to
/// decode and run one.
///
/// Execution deliberately lives outside this protocol: the Host layer defines
/// the executable refinement, keeping Core WebKit-free.
public protocol PageOperation: Friendly {
    /// The operation's typed result.
    associatedtype Output: Friendly

    /// The stable wire identifier for this operation type (e.g. `"shot"`,
    /// `"query"`). Lowercase, unique across the tool.
    static var kind: String { get }
}
