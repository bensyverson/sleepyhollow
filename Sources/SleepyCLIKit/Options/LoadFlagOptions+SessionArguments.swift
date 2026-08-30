import ArgumentParser
import Foundation
import SleepyHollow

public extension LoadFlagOptions {
    /// This invocation's loading flags, back in their argument form, for the
    /// `_host` helper `sleepy open` spawns.
    ///
    /// A session's `LoadOptions` never crosses the socket as JSON: the helper
    /// is a second `sleepy` process, and the honest way to hand it the same
    /// load shape is to hand it the same flags. That makes this the seam a new
    /// loading flag drifts through — nothing in the compiler notices a flag
    /// that parses, resolves, and is then never forwarded, so it lives here
    /// beside the option group rather than inside `OpenCommand`, where a test
    /// can parse the output back and compare the two `LoadOptions`.
    ///
    /// - Parameter steps: the ordered action steps, read from the raw argument
    ///   vector by ``ActionStepParser`` because ArgumentParser loses their
    ///   interleave order.
    /// - Returns: the flags, in declaration order, followed by the steps.
    func sessionArguments(steps: [ActionStep]) -> [String] {
        var arguments: [String] = []
        if let size: String = size.first {
            arguments += ["--size", size]
        }
        if let theme: ColorTheme = theme.first {
            arguments += ["--theme", theme.rawValue]
        }
        if transparent {
            arguments.append("--transparent")
        }
        if let jar: JarName = jar {
            arguments += ["--jar", jar.rawValue]
        }
        if let fileRoot: String = fileRoot {
            arguments += ["--file-root", fileRoot]
        }
        for path in inject {
            arguments += ["--inject", path]
        }
        if let injectWorld: InjectedScript.World = injectWorld {
            arguments += ["--inject-world", injectWorld.rawValue]
        }
        if let waitFor: String = waitFor {
            arguments += ["--wait-for", waitFor]
        }
        if let budget: Int = budget {
            arguments += ["--budget", String(budget)]
        }
        if let confirm: DialogChoice = confirm {
            arguments += ["--confirm", confirm.rawValue]
        }
        if let promptText: String = promptText {
            arguments += ["--prompt-text", promptText]
        }
        return arguments + steps.flatMap(Self.arguments(for:))
    }

    /// One ordered action step, back in its flag form for the helper.
    private static func arguments(for step: ActionStep) -> [String] {
        switch step {
        case let .click(selector): ["--click", selector]
        case let .fill(selector, value): ["--fill", "\(selector)=\(value)"]
        case let .submit(selector): ["--submit", selector]
        }
    }
}
