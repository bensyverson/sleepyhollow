import ArgumentParser
import SleepyHollow

/// The shared `--format` flag every verb takes, resolved against the verb's
/// own default and the subset of ``OutputFormat``s it supports.
///
/// Each verb passes its own default (its tersest faithful form) and its
/// supported subset; an unsupported choice is a teaching usage error that
/// lists what the verb does support.
public struct FormatOption: ParsableArguments {
    @Option(name: .long, help: "Output format; each verb documents its supported set.")
    public var format: OutputFormat?

    /// Creates an empty option group for ArgumentParser to populate.
    public init() {}

    /// Resolves to `format`, or `defaultFormat` when none was given.
    ///
    /// Throws a teaching ``SleepyError`` when the resolved format isn't in
    /// `supported`.
    public func resolve(
        default defaultFormat: OutputFormat,
        supporting supported: Set<OutputFormat>,
        verb: String,
    ) throws -> OutputFormat {
        try Self.resolve(format, default: defaultFormat, supporting: supported, verb: verb)
    }

    /// The pure resolution logic behind ``resolve(default:supporting:verb:)``,
    /// exposed as a static function so it can be tested without invoking
    /// ArgumentParser.
    public static func resolve(
        _ format: OutputFormat?,
        default defaultFormat: OutputFormat,
        supporting supported: Set<OutputFormat>,
        verb: String,
    ) throws -> OutputFormat {
        let chosen = format ?? defaultFormat
        guard supported.contains(chosen) else {
            let list = supported.map(\.rawValue).sorted().joined(separator: ", ")
            throw SleepyError(
                kind: .usage,
                message: "'\(verb)' doesn't support --format \(chosen.rawValue).",
                nextMove: "Choose one of: \(list).",
            )
        }
        return chosen
    }
}
