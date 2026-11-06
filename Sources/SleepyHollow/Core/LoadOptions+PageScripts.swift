/// The refusals ``LoadOptions/PageScripts/disabled`` earns: each names what
/// cannot work with the page's scripts off, why, and what to do instead —
/// never an empty answer that reads like a clean one.
public extension LoadOptions {
    /// How the CLI spells the setting, so every refusal names the flag the
    /// agent actually typed.
    static let pageScriptsOffSpelling: String = "page scripts off (--no-js)"

    /// Refuses a ``wait`` that only the page's own script could satisfy.
    ///
    /// A `js:` predicate runs in the page world, which turning scripts off
    /// closes to this tool as well; a `message:` is posted by page script,
    /// which never runs. Either would spend the whole budget and then report
    /// a timeout about the page, when the truth is that the question could
    /// not be asked. Checked before navigating, so the refusal is immediate.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage``.
    func requireWaitAnswerable() throws {
        guard pageScripts == .disabled, let wait else { return }
        switch wait {
        case let .predicate(expression):
            throw SleepyError(
                kind: .usage,
                message: "'--wait-for js:\(expression)' cannot be checked with \(Self.pageScriptsOffSpelling): "
                    + "a js: predicate runs in the page's own world, and turning scripts off closes it to sleepy too.",
                nextMove: "Wait for a selector (--wait-for '<css>') or for 'idle' instead, or drop --no-js.",
            )
        case let .message(name):
            throw SleepyError(
                kind: .usage,
                message: "'--wait-for message:\(name)' can never arrive with \(Self.pageScriptsOffSpelling): "
                    + "only the page's own script posts it, and that script does not run.",
                nextMove: "Wait for a selector (--wait-for '<css>') or for 'idle' instead, or drop --no-js.",
            )
        case .selector, .idle, .load:
            return
        }
    }

    /// The refusal for evaluating in the page world with scripts off.
    static var pageWorldClosed: SleepyError {
        SleepyError(
            kind: .usage,
            message: "The page world cannot run anything with \(pageScriptsOffSpelling): "
                + "WebKit's scripting switch closes it to sleepy as well as to the page.",
            nextMove: "Pass --world isolated: it shares the page's DOM and holds window.sleepy, "
                + "and a page whose scripts never ran has no globals of its own to read. Or drop --no-js.",
        )
    }

    /// The refusal for reading the console with scripts off.
    static var consoleNeverWritten: SleepyError {
        SleepyError(
            kind: .usage,
            message: "There is no console to read with \(pageScriptsOffSpelling): "
                + "the page's scripts never ran, so nothing could write to it — an empty log would read as a clean one.",
            nextMove: "Drop --no-js to read the scripted page's console; to check the page without scripts, "
                + "read it with query, ax or shot.",
        )
    }
}
