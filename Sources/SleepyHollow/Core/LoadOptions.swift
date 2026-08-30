import Foundation

/// Everything that shapes an ephemeral load: viewport, theme, backdrop, jar,
/// file-access root, injected scripts, dialog policy, waiting, and the ordered
/// one-shot action steps.
///
/// Loading verbs pass these through to the page host untouched — waiting and
/// step execution live in the host's load pipeline, so verbs gain them
/// without code of their own. Defaults are the vision doc's deterministic
/// ones: same invocation, same page.
public struct LoadOptions: Friendly {
    /// Whether the web view paints anything behind the page.
    ///
    /// A typed fact rather than a `Bool`, because "transparent" is one of the
    /// backdrops a capture can be taken against, not a switch on some other
    /// behaviour: a later "checkerboard" or "named colour" belongs here as
    /// another case, not as a second flag.
    public enum Backdrop: String, Friendly, CaseIterable {
        /// The web view paints its own opaque white behind the page — what a
        /// browser window does, and the default. Every pixel of a capture has
        /// alpha 255.
        case opaque

        /// The web view paints nothing. A page whose `body` background is
        /// `transparent` therefore yields capture pixels with alpha 0 wherever
        /// it painted nothing itself — what a component snapshot compared
        /// against a renderer's output needs
        /// (`project/2026-08-29-woodcase-harness-feedback.md`, finding 4).
        case transparent
    }

    /// The budget hosts apply when ``budget`` is `nil`: every operation
    /// terminates (30 seconds).
    public static let defaultBudget: TimeInterval = 30

    /// Viewport size in points. Default 1280×800.
    public var size: ViewportSize

    /// Rendering appearance. Default ``ColorTheme/light`` for determinism.
    public var theme: ColorTheme

    /// What the web view paints behind the page. Default ``Backdrop/opaque``.
    ///
    /// Fixed when the host builds its web view, so it is a property of the
    /// session rather than of a single capture: `sleepy open --transparent`
    /// opens a session whose every shot is transparent.
    public var backdrop: Backdrop

    /// Cookie jar to attach; `nil` keeps cookies in memory for this load only.
    public var jar: JarName?

    /// Lets a `file:` page read local files, bounding its *subresources* to
    /// this directory; `nil` — the default — leaves a `file:` page unable to
    /// read anything from script.
    ///
    /// A plain `file:` load already reaches relative subresources in sibling
    /// and parent directories — `<script src="../js/app.js">`, an `@font-face`
    /// pointing two levels up (measured by the first library embedding:
    /// `project/2026-08-29-woodcase-harness-feedback.md`, finding 3). What it
    /// cannot do is read a local file *from script*: `fetch()` and
    /// `XMLHttpRequest` against a `file:` URL are refused, because a `file:`
    /// document has an opaque origin. Naming a root here turns that on.
    ///
    /// Two things follow, and neither is guessable:
    ///
    /// - The page must live under the root. The navigation goes through
    ///   `WKWebView.loadFileURL(_:allowingReadAccessTo:)`, which refuses a URL
    ///   outside the root it is given, and which is what confines the page's
    ///   subresource loading to that subtree.
    /// - The root does **not** confine what a *script* reads. WebKit's grant
    ///   for script-initiated reads is all-or-nothing: measured 2026-08-29, a
    ///   page under a fixtures-directory root still read `file:///etc/hosts`.
    ///   So this says *whether* the page may read local files, not which.
    ///
    /// Ignored for a non-`file:` URL — an `http:` page's `fetch()` is
    /// governed by CORS, not by a local grant. It must itself be a `file:`
    /// URL; ``PageHost/load(_:budget:)`` refuses anything else rather than
    /// silently granting nothing.
    public var fileAccessRoot: URL?

    /// User scripts installed before the load.
    public var scripts: [InjectedScript]

    /// How dialogs are answered. Default declines everything and records it.
    public var dialogs: DialogPolicy

    /// The condition that ends the settle phase — after any ``steps`` have
    /// run, so it can name something the steps produce; `nil` waits for load
    /// alone.
    public var wait: WaitCondition?

    /// Ceiling in seconds for load + settle + steps; `nil` applies
    /// ``defaultBudget``. The CLI expresses this in milliseconds.
    public var budget: TimeInterval?

    /// Ordered actions executed after the load event and before ``wait``
    /// gates the verb's read; each auto-waits for its selector.
    public var steps: [ActionStep]

    /// Creates options, defaulting every field to the deterministic baseline.
    public init(
        size: ViewportSize = ViewportSize.default,
        theme: ColorTheme = .light,
        backdrop: Backdrop = .opaque,
        jar: JarName? = nil,
        fileAccessRoot: URL? = nil,
        scripts: [InjectedScript] = [],
        dialogs: DialogPolicy = DialogPolicy(),
        wait: WaitCondition? = nil,
        budget: TimeInterval? = nil,
        steps: [ActionStep] = [],
    ) {
        self.size = size
        self.theme = theme
        self.backdrop = backdrop
        self.jar = jar
        self.fileAccessRoot = fileAccessRoot
        self.scripts = scripts
        self.dialogs = dialogs
        self.wait = wait
        self.budget = budget
        self.steps = steps
    }
}
