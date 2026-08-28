import ArgumentParser

/// The shared `--out <file>` flag: any verb that emits an artifact (a
/// screenshot, a PDF, a serialized DOM) writes to this file instead of
/// standard output when given.
///
/// `-o` is declared here rather than on any one verb, because this group is
/// where "write it to a file" lives: every verb that adopts it gets the same
/// short form, and no verb can quietly disagree about what `-o` means.
public struct OutOption: ParsableArguments {
    @Option(
        name: [.customShort("o"), .long],
        help: "Write output to this file instead of standard output.",
    )
    public var out: String?

    /// Creates an empty option group for ArgumentParser to populate.
    public init() {}

    /// The resolved sink: a file sink when `--out` was given, a
    /// standard-output sink otherwise.
    public var sink: OutputSink {
        OutputSink(path: out)
    }
}
