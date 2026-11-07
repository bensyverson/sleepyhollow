import Foundation
import SleepyHollow

/// The `--size`-only sweep: `overflow` repeats the viewport axis and nothing
/// else, so it needs every `--size` parsed and every *other* flag resolved
/// once, with the repeated `--theme` refusal still standing.
public extension LoadFlagOptions {
    /// Every `--size` given, parsed, in order; empty when none was.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` for the
    ///   first value that is neither `WxH` nor a width.
    func viewportSizes() throws -> [ViewportSize] {
        try size.map { try Self.viewportSize(parsing: $0) }
    }

    /// Resolves every flag but the viewport, for a verb that supplies the
    /// viewport per load from ``viewportSizes()``.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` when
    ///   `--theme` was repeated — only `shot` sweeps themes.
    func resolveSizeSweepOptions(steps: [ActionStep]) throws -> LoadOptions {
        if theme.count > 1 { throw Self.repeatedAxis("--theme", count: theme.count) }
        return try Self.resolve(
            size: nil,
            theme: theme.first,
            jar: jar,
            injectPaths: inject,
            injectWorld: injectWorld,
            waitFor: waitFor,
            budgetMilliseconds: budget,
            confirm: confirm,
            promptText: promptText,
            fileRoot: fileRoot,
            backdrop: backdrop,
            pageScripts: pageScripts,
            steps: steps,
        )
    }
}
