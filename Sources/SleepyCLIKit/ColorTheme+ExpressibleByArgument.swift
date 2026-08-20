import ArgumentParser
import SleepyHollow

/// Lets `--theme` accept `light`/`dark` directly as ``ColorTheme``, via
/// ArgumentParser's built-in bridge for `String`-backed `RawRepresentable`
/// types.
extension ColorTheme: ExpressibleByArgument {}
