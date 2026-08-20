import Foundation

/// Shared test apparatus for SleepyHollow's suites: the in-process HTTP
/// ``FixtureServer`` and the shared fixture pages it serves.
public enum TestSupport {
    /// The bundled directory holding the shared fixture pages and assets.
    ///
    /// Copied into the target's resource bundle by the `Fixtures` resource
    /// declaration in `Package.swift`.
    public static var fixturesDirectory: URL {
        guard let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            fatalError("Fixtures directory missing from the TestSupport resource bundle")
        }
        return url
    }
}
