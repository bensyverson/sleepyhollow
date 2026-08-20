import ArgumentParser
import SleepyHollow

/// Lets `--jar` accept a jar name directly as ``JarName``, via
/// ArgumentParser's built-in bridge for `String`-backed `RawRepresentable`
/// types. An invalid name fails ``JarName/init(rawValue:)`` and surfaces as
/// ArgumentParser's own "invalid value" usage error.
extension JarName: ExpressibleByArgument {}
