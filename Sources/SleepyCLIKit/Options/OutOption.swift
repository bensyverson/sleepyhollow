import ArgumentParser

/// The shared `--out <file>` flag: any verb that emits an artifact (a
/// screenshot, a PDF, a serialized DOM) writes to this file instead of
/// standard output when given.
public struct OutOption: ParsableArguments {
    @Option(name: .long, help: "Write output to this file instead of standard output.")
    public var out: String?

    /// Creates an empty option group for ArgumentParser to populate.
    public init() {}

    /// The resolved sink: a file sink when `--out` was given, a
    /// standard-output sink otherwise.
    public var sink: OutputSink {
        OutputSink(path: out)
    }
}
