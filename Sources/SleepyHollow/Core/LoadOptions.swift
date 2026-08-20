import Foundation

/// Everything that shapes an ephemeral load: viewport, theme, jar, injected
/// scripts, dialog policy, waiting, and the ordered one-shot action steps.
///
/// Loading verbs pass these through to the page host untouched — waiting and
/// step execution live in the host's load pipeline, so verbs gain them
/// without code of their own. Defaults are the vision doc's deterministic
/// ones: same invocation, same page.
public struct LoadOptions: Friendly {
    /// The budget hosts apply when ``budget`` is `nil`: every operation
    /// terminates (30 seconds).
    public static let defaultBudget: TimeInterval = 30

    /// Viewport size in points. Default 1280×800.
    public var size: ViewportSize

    /// Rendering appearance. Default ``ColorTheme/light`` for determinism.
    public var theme: ColorTheme

    /// Cookie jar to attach; `nil` keeps cookies in memory for this load only.
    public var jar: JarName?

    /// User scripts installed before the load.
    public var scripts: [InjectedScript]

    /// How dialogs are answered. Default declines everything and records it.
    public var dialogs: DialogPolicy

    /// The condition that ends the settle phase; `nil` waits for load alone.
    public var wait: WaitCondition?

    /// Ceiling in seconds for load + settle + steps; `nil` applies
    /// ``defaultBudget``. The CLI expresses this in milliseconds.
    public var budget: TimeInterval?

    /// Ordered actions executed after settle and before the verb's read.
    public var steps: [ActionStep]

    /// Creates options, defaulting every field to the deterministic baseline.
    public init(
        size: ViewportSize = ViewportSize.default,
        theme: ColorTheme = .light,
        jar: JarName? = nil,
        scripts: [InjectedScript] = [],
        dialogs: DialogPolicy = DialogPolicy(),
        wait: WaitCondition? = nil,
        budget: TimeInterval? = nil,
        steps: [ActionStep] = [],
    ) {
        self.size = size
        self.theme = theme
        self.jar = jar
        self.scripts = scripts
        self.dialogs = dialogs
        self.wait = wait
        self.budget = budget
        self.steps = steps
    }
}
