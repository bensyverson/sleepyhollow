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

    /// The failure act verbs raise until session routing lands.
    ///
    /// The operations themselves are ready and registered: what is missing is
    /// the generic `--session` route, which leaf DLHu7 owns.
    static func pendingRouting(verb: String, session: SessionName, example: String) -> SleepyError {
        SleepyError(
            kind: .environment,
            message: "'\(verb)' can't reach session '\(session)' yet: the operation is ready, the routing is not.",
            nextMove: "Session routing lands with leaf DLHu7; until then act in one shot: "
                + "`sleepy load <url> \(example)`.",
        )
    }

    private static func oneShotAdvice(verb _: String, example: String) -> String {
        "Open a session with `sleepy open <url> --name <n>` and pass --session <n>, "
            + "or act in one shot on a loading verb: `sleepy load <url> \(example)`."
    }
}
