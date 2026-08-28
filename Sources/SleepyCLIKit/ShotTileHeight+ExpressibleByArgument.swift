import ArgumentParser
import CoreGraphics
import SleepyHollow

/// Lets `--tile` take a CSS-px height (`--tile 1000`) or no value at all
/// (`--tile`, ArgumentParser's `defaultAsFlag`, which hands over
/// ``ShotTile/Height/automatic``).
///
/// Only a non-number is refused here: ArgumentParser answers a rejected
/// value by *silently* falling back to the flag form, so a too-short
/// `--tile 20` must parse and then fail ``ShotTile/Height/validated(overlap:)``
/// with a teaching error, rather than turning into a bare `--tile` and a
/// stray positional.
extension ShotTile.Height: ExpressibleByArgument {
    /// Parses a whole number of CSS pixels.
    public init?(argument: String) {
        guard let value = Int(argument) else { return nil }
        self = .cssPixels(CGFloat(value))
    }

    /// How the height reads back in help and error text.
    public var defaultValueDescription: String {
        switch self {
        case .automatic: "the --max-size cap, else the viewport height"
        case let .cssPixels(value): "\(Int(value))"
        }
    }
}
