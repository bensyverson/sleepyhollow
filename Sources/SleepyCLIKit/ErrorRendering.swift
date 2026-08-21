import Foundation
import SleepyHollow

/// Renders a thrown error as terminal text and a process exit code —
/// never a stack trace, and for a `SleepyError` always the message plus
/// its next move.
public enum ErrorRendering {
    /// The result of rendering a failure: what to print, which stream it
    /// goes to, and the code to exit with.
    public struct Rendered: Friendly {
        /// The text to print, without a trailing newline.
        public let text: String

        /// `true` for standard error, `false` for standard output.
        public let toStandardError: Bool

        /// The process exit code.
        public let exitCode: Int32

        /// Creates a rendered failure.
        public init(text: String, toStandardError: Bool, exitCode: Int32) {
            self.text = text
            self.toStandardError = toStandardError
            self.exitCode = exitCode
        }
    }

    /// Renders a `SleepyError`: its message and next move, to standard
    /// error, exiting with the status its `SleepyError/kind` maps to.
    public static func render(sleepyError error: SleepyError) -> Rendered {
        Rendered(text: error.description, toStandardError: true, exitCode: error.exitStatus.rawValue)
    }

    /// Renders a word typed where a verb belongs.
    ///
    /// ArgumentParser calls this "Unexpected argument" and hands back the
    /// root usage line, which is true but says nothing about *why*. A word in
    /// the verb slot that is not a verb is almost always a typo or a guess, so
    /// this names it, suggests the closest verb when there is a close one, and
    /// points at the list.
    ///
    /// - Parameters:
    ///   - typed: the word that was typed where a verb belongs.
    ///   - knownVerbs: every verb an agent may type, hidden ones excluded.
    ///   - commandName: the tool's own name, for the message.
    public static func renderUnknownVerb(
        _ typed: String,
        knownVerbs: [String],
        commandName: String,
    ) -> Rendered {
        let suggestion: String? = nearestVerb(to: typed, among: knownVerbs)
        let didYouMean: String = suggestion.map { "Did you mean `\(commandName) \($0)`? " } ?? ""
        return Rendered(
            text: "\(commandName): there is no verb named '\(typed)'. "
                + didYouMean
                + "`\(commandName) --help` lists every verb.",
            toStandardError: true,
            exitCode: ExitStatus.usage.rawValue,
        )
    }

    /// The verb `typed` most likely meant, or `nil` when nothing is close.
    ///
    /// "Close" is a shared prefix or an edit distance of at most two — enough
    /// for a slip or a dropped letter, tight enough that a genuinely wrong
    /// guess gets the verb list instead of a misleading suggestion.
    ///
    /// A shared prefix outranks distance, because a short abbreviation is
    /// nearly always what the typist meant: `q` is `query`, even though `ax`
    /// is two edits away and `query` four.
    public static func nearestVerb(to typed: String, among knownVerbs: [String]) -> String? {
        let lowered: String = typed.lowercased()
        var best: (verb: String, shares: Bool, distance: Int)?
        for verb in knownVerbs {
            let shares: Bool = verb.hasPrefix(lowered) || lowered.hasPrefix(verb)
            let distance: Int = editDistance(lowered, verb)
            guard shares || distance <= 2 else { continue }
            let candidate = (verb: verb, shares: shares, distance: distance)
            guard let current = best else {
                best = candidate
                continue
            }
            if outranks(candidate, current) { best = candidate }
        }
        return best?.verb
    }

    /// Whether `candidate` is the better suggestion: prefix first, then the
    /// smaller edit distance, then alphabetical so the answer is stable.
    private static func outranks(
        _ candidate: (verb: String, shares: Bool, distance: Int),
        _ current: (verb: String, shares: Bool, distance: Int),
    ) -> Bool {
        if candidate.shares != current.shares { return candidate.shares }
        if candidate.distance != current.distance { return candidate.distance < current.distance }
        return candidate.verb < current.verb
    }

    /// Levenshtein distance, the two-row form: one insertion, deletion or
    /// substitution counts as one.
    private static func editDistance(_ left: String, _ right: String) -> Int {
        let source: [Character] = Array(left)
        let target: [Character] = Array(right)
        guard !source.isEmpty else { return target.count }
        guard !target.isEmpty else { return source.count }

        var previous: [Int] = Array(0 ... target.count)
        for (sourceIndex, sourceCharacter) in source.enumerated() {
            var current: [Int] = [sourceIndex + 1]
            for (targetIndex, targetCharacter) in target.enumerated() {
                let substitution: Int = previous[targetIndex] + (sourceCharacter == targetCharacter ? 0 : 1)
                current.append(min(previous[targetIndex + 1] + 1, current[targetIndex] + 1, substitution))
            }
            previous = current
        }
        return previous[target.count]
    }

    /// Renders an argument-parsing failure that isn't a `SleepyError` — an
    /// unrecognized flag, a missing required option, an unknown verb.
    ///
    /// `fullText` is what ArgumentParser's own `fullMessage(for:)` produced
    /// for the error: it names the offending flag *and* the subcommand that
    /// was being parsed, and ends with that subcommand's `--help` — a stated
    /// next move, aimed at the verb the agent actually typed rather than at
    /// the root. Passing it through beats re-deriving it: the parser is the
    /// only thing that knows which command in the stack failed.
    ///
    /// When ArgumentParser has nothing to say (an error it renders as empty
    /// text), this falls back to naming both help screens, so no invocation
    /// ever fails silently.
    ///
    /// Every such failure exits with Core's `ExitStatus/usage` (2),
    /// regardless of ArgumentParser's own default (`EX_USAGE`, 64) — one exit
    /// code for every usage error, whatever produced it.
    public static func renderParsingFailure(fullText: String, commandName: String) -> Rendered {
        let stated: String = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "\(commandName): didn't understand that invocation. "
            + "Run `\(commandName) --help` for the verb list, "
            + "or `\(commandName) <verb> --help` for one verb's flags and examples."
        return Rendered(
            text: stated.isEmpty ? fallback : stated,
            toStandardError: true,
            exitCode: ExitStatus.usage.rawValue,
        )
    }
}
