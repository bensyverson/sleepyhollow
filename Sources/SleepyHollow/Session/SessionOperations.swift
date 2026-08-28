/// The one place that says which operations a session helper can run.
///
/// The session layer decodes with an injected ``OperationRegistry`` precisely
/// so it never learns the verbs; this is where the *binary* makes the opposite
/// choice and names them. A verb family that ships an
/// ``ExecutablePageOperation`` registers it here — one line — and gains
/// `--session` support for free.
public enum SessionOperations {
    /// Every operation `sleepy _host` can decode and execute.
    ///
    /// Computed rather than stored: a registry is a value, and a mutable
    /// global would be shared state the tool has no use for.
    public static var registry: OperationRegistry {
        var registry = OperationRegistry()
        registry.register(ReadFactsOperation.self)
        registry.register(NavigateOperation.self)
        registry.register(ShotOperation.self)
        registry.register(PDFOperation.self)
        registry.register(ArchiveOperation.self)
        registry.register(DOMOperation.self)
        registry.register(QueryOperation.self)
        registry.register(StyleOperation.self)
        registry.register(FindOperation.self)
        registry.register(AXOperation.self)
        registry.register(ContrastOperation.self)
        registry.register(OverflowOperation.self)
        registry.register(ConsoleOperation.self)
        registry.register(WireOperation.self)
        registry.register(CookiesOperation.self)
        registry.register(EvalOperation.self)
        registry.register(ClickOperation.self)
        registry.register(FillOperation.self)
        registry.register(SubmitOperation.self)
        return registry
    }
}
