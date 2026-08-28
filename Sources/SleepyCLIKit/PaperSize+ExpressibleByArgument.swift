import ArgumentParser
import SleepyHollow

/// Lets `--paper` accept `letter`/`a4` directly as ``PaperSize``, via
/// ArgumentParser's built-in bridge for `String`-backed `RawRepresentable`
/// types.
extension PaperSize: ExpressibleByArgument {}
