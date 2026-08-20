import ArgumentParser
import SleepyHollow

/// Lets `--format` accept ``OutputFormat``'s raw values directly, via
/// ArgumentParser's built-in bridge for `String`-backed `RawRepresentable`
/// types.
extension OutputFormat: ExpressibleByArgument {}
