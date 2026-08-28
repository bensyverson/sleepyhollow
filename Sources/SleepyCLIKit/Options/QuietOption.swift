import ArgumentParser

/// The shared `--quiet` flag: every verb takes it, and it silences the
/// advisory tips ``Nudge`` prints on a *successful* call.
///
/// Declared as its own group rather than as a field on ``OutOption`` because
/// the two answer different questions — `--out` is where the artifact goes,
/// `--quiet` is whether the tool volunteers advice — and because `--quiet`
/// has to reach the handful of verbs that emit no artifact at all (`close`,
/// `recipes`, `jars clear`). A flag an agent can type on one verb and not the
/// next is the inconsistency the teaching layer exists to remove.
///
/// It never silences an error: a failure is the answer, not advice.
public struct QuietOption: ParsableArguments {
    @Flag(name: .long, help: "Silence advisory tips on stderr. Errors and results are never silenced.")
    public var quiet: Bool = false

    /// Creates an empty option group for ArgumentParser to populate.
    public init() {}
}
