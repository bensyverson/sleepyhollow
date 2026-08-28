import ArgumentParser
import Foundation
import SleepyHollow

/// The shared loading flags every loading verb takes: viewport, theme, jar,
/// injected scripts and the world they land in, waiting, budget, dialog
/// policy, and the ordered one-shot action flags.
///
/// `--click`/`--fill`/`--submit` are declared here only so `--help` renders
/// them; ArgumentParser loses interleave order across separate array
/// options, so the ordered truth comes from ``ActionStepParser`` scanning
/// the raw argument vector instead. Pass its result to
/// ``resolveLoadOptions(steps:)`` to assemble a full `LoadOptions`.
///
/// `--size` and `--theme` parse as arrays because `shot` sweeps them into a
/// cross product of renders (``ShotPlan``). Declaring them twice — once here,
/// once on `shot` — is not an option ArgumentParser offers, so instead they
/// are repeatable *everywhere* and ``resolveLoadOptions(steps:)`` refuses a
/// repeat on behalf of every verb that renders one page; `shot` skips that
/// refusal by calling ``resolveLoadOptions(steps:size:theme:)`` with the pair
/// for each combination.
public struct LoadFlagOptions: ParsableArguments {
    /// How a `confirm()`/`prompt()` dialog is answered.
    public enum DialogChoice: String, ExpressibleByArgument, Friendly {
        /// `confirm()` returns true; `prompt()` returns `--prompt-text`.
        case accept
        /// `confirm()` returns false; `prompt()` returns `nil`. The default.
        case dismiss
    }

    @Option(
        name: .long,
        parsing: .singleValue,
        help: "Viewport size WxH, e.g. 1280x800, or a width alone (480 means 480x800). Default 1280x800. Repeatable on `shot`, which renders each size.",
    )
    public var size: [String] = []

    @Option(
        name: .long,
        parsing: .singleValue,
        help: "Rendering appearance: light or dark. Default light. Repeatable on `shot`, which renders each theme.",
    )
    public var theme: [ColorTheme] = []

    @Option(name: .long, help: "Attach a persistent cookie jar by name.")
    public var jar: JarName?

    @Option(
        name: .long,
        parsing: .singleValue,
        help: "Install a user script from this file at document start, in the isolated world (repeatable).",
    )
    public var inject: [String] = []

    @Option(
        name: .long,
        help: "Which world --inject's scripts run in: isolated or page. Default isolated.",
    )
    public var injectWorld: InjectedScript.World?

    @Option(name: .long, help: "Wait condition: a selector, 'js:<expr>', 'idle', or 'load'.")
    public var waitFor: String?

    @Option(name: .long, help: "Ceiling in milliseconds for load, settle, and steps.")
    public var budget: Int?

    @Option(name: .long, help: "How confirm()/prompt() dialogs are answered: accept or dismiss. Default dismiss.")
    public var confirm: DialogChoice?

    @Option(name: .long, help: "Text prompt() receives when --confirm accept.")
    public var promptText: String?

    @Option(name: .long, parsing: .singleValue, help: "Click the selector's first match, in order (repeatable).")
    public var click: [String] = []

    @Option(
        name: .long,
        parsing: .singleValue,
        help: "Set <selector>=<value> and dispatch input events, in order (repeatable).",
    )
    public var fill: [String] = []

    @Option(name: .long, parsing: .singleValue, help: "Submit the form for selector, in order (repeatable).")
    public var submit: [String] = []

    /// Creates an empty option group for ArgumentParser to populate.
    public init() {}

    /// Resolves the parsed flags plus externally-scanned `steps` to a full
    /// `LoadOptions`, for the verbs that render exactly one page.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` when
    ///   `--size` or `--theme` was repeated — only `shot` sweeps those axes,
    ///   and silently taking the last value would be a plausible wrong answer.
    public func resolveLoadOptions(steps: [ActionStep]) throws -> LoadOptions {
        try requireSingleRenderAxes()
        return try Self.resolve(
            size: size.first,
            theme: theme.first,
            jar: jar,
            injectPaths: inject,
            injectWorld: injectWorld,
            waitFor: waitFor,
            budgetMilliseconds: budget,
            confirm: confirm,
            promptText: promptText,
            steps: steps,
        )
    }

    /// Resolves the flags for **one render of a sweep**: `shot` owns the
    /// `--size` and `--theme` axes, so it supplies the pair for this
    /// combination and every other flag comes from the invocation as usual.
    ///
    /// This is the seam that keeps the repeatable form `shot`-only without
    /// declaring `--size` twice: the flags parse into arrays everywhere, and
    /// only the verb that knows what to do with more than one reads past the
    /// first.
    public func resolveLoadOptions(
        steps: [ActionStep],
        size: ViewportSize,
        theme: ColorTheme,
    ) throws -> LoadOptions {
        var options: LoadOptions = try Self.resolve(
            size: nil,
            theme: theme,
            jar: jar,
            injectPaths: inject,
            injectWorld: injectWorld,
            waitFor: waitFor,
            budgetMilliseconds: budget,
            confirm: confirm,
            promptText: promptText,
            steps: steps,
        )
        options.size = size
        return options
    }

    /// Refuses a repeated render axis on a verb that renders one page.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` naming the
    ///   repeated flag and the verb that does sweep it.
    public func requireSingleRenderAxes() throws {
        if size.count > 1 { throw Self.repeatedAxis("--size", count: size.count) }
        if theme.count > 1 { throw Self.repeatedAxis("--theme", count: theme.count) }
    }

    /// The refusal a repeated axis earns outside `shot`.
    private static func repeatedAxis(_ flag: String, count: Int) -> SleepyError {
        SleepyError(
            kind: .usage,
            message: "'\(flag)' was given \(count) times, and this verb renders one page.",
            nextMove: "Pass a single \(flag) here. `sleepy shot` is the verb that sweeps sizes, "
                + "scales and themes, writing one file per combination.",
        )
    }

    /// Parses one `--size` value: `WxH`, or a width alone taking the default
    /// height — breakpoints are widths, so `--size 480` is the common form.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` naming
    ///   both shapes.
    public static func viewportSize(parsing raw: String) throws -> ViewportSize {
        let cleaned: String = raw.trimmingCharacters(in: .whitespaces).lowercased()
        let parts: [Substring] = cleaned.split(separator: "x", maxSplits: 1, omittingEmptySubsequences: false)
        let width: Int? = parts.first.flatMap { Int($0) }
        let height: Int? = parts.count == 2 ? Int(parts[1]) : ViewportSize.default.height
        guard parts.count <= 2, let width, width > 0, let height, height > 0 else {
            throw SleepyError(
                kind: .usage,
                message: "'--size \(raw)' is neither WxH nor a width.",
                nextMove: "Use e.g. --size 1280x800, or a width alone — --size 480 means 480x\(ViewportSize.default.height).",
            )
        }
        return ViewportSize(width: width, height: height)
    }

    /// The pure resolution logic behind ``resolveLoadOptions(steps:)``,
    /// exposed as a static function so it can be tested without invoking
    /// ArgumentParser.
    public static func resolve(
        size: String?,
        theme: ColorTheme?,
        jar: JarName?,
        injectPaths: [String],
        injectWorld: InjectedScript.World?,
        waitFor: String?,
        budgetMilliseconds: Int?,
        confirm: DialogChoice?,
        promptText: String?,
        steps: [ActionStep],
    ) throws -> LoadOptions {
        try LoadOptions(
            size: resolveSize(size) ?? ViewportSize.default,
            theme: theme ?? .light,
            jar: jar,
            scripts: resolveScripts(injectPaths, in: injectWorld ?? .isolated),
            dialogs: DialogPolicy(acceptsConfirms: confirm == .accept, promptResponse: promptText),
            wait: resolveWait(waitFor),
            budget: resolveBudget(budgetMilliseconds),
            steps: steps,
        )
    }

    private static func resolveSize(_ raw: String?) throws -> ViewportSize? {
        guard let raw else { return nil }
        return try viewportSize(parsing: raw)
    }

    /// Reads each `--inject` file and puts every one of them in `world` —
    /// one flag for the whole invocation, because a per-script world would
    /// need `--inject` to carry two values and the need has never come up.
    private static func resolveScripts(
        _ paths: [String],
        in world: InjectedScript.World,
    ) throws -> [InjectedScript] {
        try paths.map { path in
            guard let source = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
                throw SleepyError(
                    kind: .usage,
                    message: "Can't read injected script '\(path)'.",
                    nextMove: "Check the path exists and is readable UTF-8 text.",
                )
            }
            return InjectedScript(source: source, injectAt: .documentStart, world: world)
        }
    }

    private static func resolveWait(_ raw: String?) -> WaitCondition? {
        guard let raw else { return nil }
        switch raw {
        case "idle":
            return .idle
        case "load":
            return .load
        default:
            if raw.hasPrefix("js:") {
                return .predicate(String(raw.dropFirst(3)))
            }
            return .selector(raw)
        }
    }

    private static func resolveBudget(_ milliseconds: Int?) throws -> TimeInterval? {
        guard let milliseconds else { return nil }
        guard milliseconds > 0 else {
            throw SleepyError(
                kind: .usage,
                message: "'--budget \(milliseconds)' must be positive.",
                nextMove: "Give a positive number of milliseconds, e.g. --budget 5000.",
            )
        }
        return TimeInterval(milliseconds) / 1000
    }
}
