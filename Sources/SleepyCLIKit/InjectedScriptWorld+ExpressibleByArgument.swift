import ArgumentParser
import SleepyHollow

/// Lets `--inject-world` accept `isolated`/`page` directly as
/// ``InjectedScript/World``, via ArgumentParser's built-in bridge for
/// `String`-backed `RawRepresentable` types. Any other word fails
/// `init(rawValue:)` and surfaces as ArgumentParser's own "invalid value"
/// usage error, which lists both worlds.
extension InjectedScript.World: ExpressibleByArgument {}
