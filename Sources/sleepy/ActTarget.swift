import Foundation
import SleepyCLIKit
import SleepyHollow

/// Where an act verb runs: act verbs require `--session`.
///
/// Acting on a page that evaporates when the process exits is write-only —
/// nothing can read the result — so `click`, `fill` and `submit` refuse a URL
/// and teach the two ways to act instead: name a session, or ride a loading
/// verb with the ordered one-shot flags (the vision doc's "The grammar").
enum ActTarget {
    /// Resolves the shared page-source arguments for an act verb.
    ///
    /// - Parameter source: the verb's page-source group.
    /// - Parameter verb: the verb's name, for the message.
    /// - Parameter example: the one-shot flag that does the same thing, e.g.
    ///   `--click '#go'`.
    /// - Returns: the session the verb should act on.
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` when no
    ///   session was named, or a URL was given instead.
    static func session(from source: PageSourceOptions, verb: String, example: String) throws -> SessionName {
        guard source.url == nil else {
            throw SleepyError(
                kind: .usage,
                message: "'\(verb)' acts on a live session, not a URL: a page that exits can't show the result.",
                nextMove: oneShotAdvice(verb: verb, example: example),
            )
        }
        guard source.session != nil else {
            throw SleepyError(
                kind: .usage,
                message: "'\(verb)' needs a live session.",
                nextMove: oneShotAdvice(verb: verb, example: example),
            )
        }
        switch try source.resolve() {
        case let .session(name):
            return name
        case .url:
            throw SleepyError(
                kind: .usage,
                message: "'\(verb)' acts on a live session, not a URL.",
                nextMove: oneShotAdvice(verb: verb, example: example),
            )
        }
    }

    /// Runs an act operation against `session` and writes its outcome.
    ///
    /// The outcome is the same ``ActionOutcome`` a one-shot step produces —
    /// what was acted on, and whether the page started navigating — as pretty,
    /// key-sorted JSON, the shape every other verb's JSON takes.
    @MainActor
    static func act<Operation: ExecutablePageOperation>(
        _ operation: Operation,
        in session: SessionName,
        to sink: OutputSink,
    ) async throws where Operation.Output == ActionOutcome {
        let outcome: ActionOutcome = try await PageExecution.run(operation, on: .session(session))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try sink.write(encoder.encode(outcome))
    }

    private static func oneShotAdvice(verb _: String, example: String) -> String {
        "Open a session with `sleepy open <url> --name <n>` and pass --session <n>, "
            + "or act in one shot on a loading verb: `sleepy load <url> \(example)`."
    }
}
