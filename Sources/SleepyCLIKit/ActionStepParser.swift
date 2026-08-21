import Foundation
import SleepyHollow

/// Scans a raw argument vector for `--click`, `--fill`, and `--submit`
/// (both `--flag value` and `--flag=value` forms) and returns the
/// `ActionStep`s they describe in the order they appeared.
///
/// ArgumentParser collects each flag into its own array, losing the
/// interleave order across `--click`/`--fill`/`--submit` — ``LoadFlagOptions``
/// still declares them so `--help` renders correctly, but this scanner is
/// the order-of-truth for one-shot flows (see the vision doc's "one-shot
/// flows compose by flags").
///
/// A scanner over raw argv has to know two things ArgumentParser knows and it
/// does not, or it invents steps nobody asked for:
///
/// - **Which tokens are an option's value.** `--prompt-text --click` passes
///   the *string* `--click`; a naive scan reads it as a step and eats the
///   token after it. ``knownValueTakingOptions`` lists every value-taking
///   long option the tool declares, and the scan skips what follows one.
/// - **The `--` terminator.** Everything after a bare `--` is a positional,
///   however it is spelled, so the scan stops there.
public enum ActionStepParser {
    /// The flags this parser recognizes, in the raw argument-vector spelling.
    private enum Flag: String, CaseIterable {
        case click = "--click"
        case fill = "--fill"
        case submit = "--submit"
    }

    /// Every value-taking long option the tool declares, so the scan never
    /// mistakes an option's *value* for a step flag.
    ///
    /// Kept as one list because the scan sees the whole argument vector, not
    /// one command's options: `sleepy find <url> --text '--click'` must be as
    /// safe as `sleepy load <url> --prompt-text '--click'`. **A verb adding a
    /// value-taking option adds it here** (or passes it to
    /// ``parse(_:valueTakingOptions:)``); a boolean `@Flag` needs no entry.
    public static let knownValueTakingOptions: Set<String> = [
        // LoadFlagOptions
        "--size", "--theme", "--jar", "--inject", "--wait-for", "--budget",
        "--confirm", "--prompt-text",
        // Shared option groups
        "--session", "--format", "--out",
        // Verb options
        "--element", "--selector", "--property", "--text", "--count",
        "--js", "--args", "--value",
        // The session helper
        "--name", "--url", "--idle-timeout", "--home",
    ]

    /// Parses `arguments` (typically `CommandLine.arguments`) into ordered
    /// action steps.
    ///
    /// - Parameter arguments: the raw argument vector.
    /// - Parameter valueTakingOptions: value-taking long options beyond
    ///   ``knownValueTakingOptions``, whose values must not be read as steps.
    /// - Throws: a teaching `SleepyError` when a recognized flag has no
    ///   value, or when a `--fill` value is missing its `=`.
    public static func parse(
        _ arguments: [String],
        valueTakingOptions: Set<String> = [],
    ) throws -> [ActionStep] {
        let skippable: Set<String> = knownValueTakingOptions.union(valueTakingOptions)
        var steps: [ActionStep] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let token = arguments[index]

            // Everything after a bare `--` is a positional, not an option.
            if token == "--" { break }

            // The value of an unrelated option is data, whatever it spells.
            if skippable.contains(token) {
                index += 2
                continue
            }

            guard
                let flag = Flag.allCases.first(where: { token == $0.rawValue || token.hasPrefix($0.rawValue + "=") })
            else {
                index += 1
                continue
            }

            let value: String
            if token.count > flag.rawValue.count {
                value = String(token.dropFirst(flag.rawValue.count + 1))
                index += 1
            } else {
                let valueIndex = index + 1
                guard valueIndex < arguments.endIndex, arguments[valueIndex] != "--" else {
                    throw SleepyError(
                        kind: .usage,
                        message: "'\(flag.rawValue)' needs a value.",
                        nextMove: "Provide one, e.g. '\(flag.rawValue) <selector>'.",
                    )
                }
                value = arguments[valueIndex]
                index = valueIndex + 1
            }

            try steps.append(step(for: flag, value: value))
        }
        return steps
    }

    private static func step(for flag: Flag, value: String) throws -> ActionStep {
        switch flag {
        case .click:
            return .click(selector: value)
        case .submit:
            return .submit(selector: value)
        case .fill:
            guard let separator = value.firstIndex(of: "=") else {
                throw SleepyError(
                    kind: .usage,
                    message: "'--fill \(value)' is missing '='.",
                    nextMove: "Use --fill '<selector>=<value>', e.g. --fill '#q=webkit'.",
                )
            }
            let selector = String(value[value.startIndex ..< separator])
            let filled = String(value[value.index(after: separator)...])
            return .fill(selector: selector, value: filled)
        }
    }
}
