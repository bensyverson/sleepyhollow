/// A ``PageOperation`` that knows how to run against a ``PageHost``.
///
/// This is the refinement that keeps `Core` free of WebKit: the operation's
/// *value* — what to shoot, what to query — is a `Friendly` struct any layer
/// can encode, decode and ship over a socket, while its *execution* is
/// main-actor work that only the Host layer can perform. One-shot invocations
/// and the session helper run the identical value through the identical
/// ``execute(on:)``.
public protocol ExecutablePageOperation: PageOperation {
    /// Runs the operation against `host` and returns its typed output.
    @MainActor
    func execute(on host: PageHost) async throws -> Output
}

public extension PageHost {
    /// Runs `operation` against this host.
    ///
    /// The verb-neutral entry point: the session helper calls exactly this
    /// after decoding an envelope, so a family adding an operation adds no
    /// wiring here.
    func execute<Operation: ExecutablePageOperation>(_ operation: Operation) async throws -> Operation.Output {
        try await operation.execute(on: self)
    }
}
