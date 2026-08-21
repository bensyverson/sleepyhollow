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
public struct LoadFlagOptions: ParsableArguments {
    /// How a `confirm()`/`prompt()` dialog is answered.
    public enum DialogChoice: String, ExpressibleByArgument, Friendly {
        /// `confirm()` returns true; `prompt()` returns `--prompt-text`.
        case accept
        /// `confirm()` returns false; `prompt()` returns `nil`. The default.
        case dismiss
    }

    @Option(name: .long, help: "Viewport size WxH, e.g. 1280x800. Default 1280x800.")
    public var size: String?

    @Option(name: .long, help: "Rendering appearance: light or dark. Default light.")
    public var theme: ColorTheme?

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
    /// `LoadOptions`.
    public func resolveLoadOptions(steps: [ActionStep]) throws -> LoadOptions {
        try Self.resolve(
            size: size,
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
        let parts = raw.lowercased().split(separator: "x", maxSplits: 1)
        guard
            parts.count == 2,
            let width = Int(parts[0]), width > 0,
            let height = Int(parts[1]), height > 0
        else {
            throw SleepyError(
                kind: .usage,
                message: "'--size \(raw)' is not WxH.",
                nextMove: "Use e.g. --size 1280x800.",
            )
        }
        return ViewportSize(width: width, height: height)
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
