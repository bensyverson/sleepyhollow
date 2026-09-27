import Foundation

/// Shared test apparatus for SleepyHollow's suites: the in-process HTTP
/// ``FixtureServer`` and the shared fixture pages it serves.
public enum TestSupport {
    /// Seconds at the scale of "this is wedged", never of "this was slow": the
    /// budget a test hands to work it expects to *succeed*, and the upper
    /// bound it puts on elapsed time.
    ///
    /// Under the parallel suite, with other agents building on the same Mac
    /// (load average 150+), a trivial local load has taken seven seconds and a
    /// 10 ms `Task.sleep` has resumed twelve seconds late. A budget of a few
    /// seconds then measures the machine: it fails as a `.timeout` that reads
    /// like the product misbehaving. Assert the typed outcome instead, and let
    /// only a hang reach this bound. Where a test's point *is* a budget, give
    /// its discriminating margin this scale too, as `WaitBudgetTests` does.
    /// See Woodcase's `project/2026-08-31-load-shaped-budgets.md`.
    public static let livenessBudget: TimeInterval = 60

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
