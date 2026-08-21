import Foundation

/// The load pipeline's action-step phase: the ordered one-shot
/// `--click`/`--fill`/`--submit` steps, executed after settle and before the
/// verb's read.
///
/// This file is the act family's seam into the host: ``PageHost/load(_:)``
/// calls ``PageHost/runActionSteps(by:)`` unconditionally, so the family
/// lands step execution by rewriting this file alone. Until it does, the
/// placeholder refuses non-empty steps with a teaching error.
extension PageHost {
    /// Executes ``LoadOptions/steps`` in flag order, sharing the load's
    /// budget: `deadline` is the same ceiling navigation and settle drew on.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment``
    ///   while step execution is unimplemented.
    func runActionSteps(by _: DispatchTime) async throws {
        guard !options.steps.isEmpty else { return }
        throw SleepyError(
            kind: .environment,
            message: "\(options.steps.count) action step(s) were requested, but this host cannot act yet.",
            nextMove: "Action steps land with leaf q6mlw; until then load without --click/--fill/--submit.",
        )
    }
}
