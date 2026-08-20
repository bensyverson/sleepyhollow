import Foundation
import SleepyHollow

/// Scans a raw argument vector for `--click`, `--fill`, and `--submit`
/// (both `--flag value` and `--flag=value` forms) and returns the
/// ``ActionStep``s they describe in the order they appeared.
///
/// ArgumentParser collects each flag into its own array, losing the
/// interleave order across `--click`/`--fill`/`--submit` — ``LoadFlagOptions``
/// still declares them so `--help` renders correctly, but this scanner is
/// the order-of-truth for one-shot flows (see the vision doc's "one-shot
/// flows compose by flags").
public enum ActionStepParser {
    /// The flags this parser recognizes, in the raw argument-vector spelling.
    private enum Flag: String, CaseIterable {
        case click = "--click"
        case fill = "--fill"
        case submit = "--submit"
    }

    /// Parses `arguments` (typically `CommandLine.arguments`) into ordered
    /// action steps.
    ///
    /// Throws a teaching ``SleepyError`` when a recognized flag has no
    /// value, or when a `--fill` value is missing its `=`.
    public static func parse(_ arguments: [String]) throws -> [ActionStep] {
        var steps: [ActionStep] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let token = arguments[index]
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
                guard valueIndex < arguments.endIndex else {
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
