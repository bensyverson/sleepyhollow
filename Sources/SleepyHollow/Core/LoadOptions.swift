import Foundation

/// Everything that shapes an ephemeral load: viewport, theme, backdrop,
/// whether the page's own scripts run, jar, file-access root, injected
/// scripts, dialog policy, waiting, and the ordered one-shot action steps.
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

    /// Whether the page's *own* JavaScript runs.
    ///
    /// A typed fact rather than a `Bool`, like ``Backdrop``: it names what is
    /// switched off — the page's scripts — so it cannot be read as a switch on
    /// this library's instrumentation, most of which keeps running.
    public enum PageScripts: String, Friendly, CaseIterable {
        /// The page's scripts run, as in any browser. The default.
        case enabled

        /// The page is loaded as a browser with JavaScript turned off renders
        /// it: no `<script>`, no `on…` attribute handler, no `javascript:` URL
        /// runs; `<noscript>` content renders; `@media (scripting: none)`
        /// matches. A page that enhances itself is read as the server sent it
        /// — the progressive-enhancement check
        /// (`project/2026-08-30-sleepy-hollow-feedback.md`, item 1).
        ///
        /// WebKit's switch closes the page's own content world to this tool as
        /// well, while the isolated world keeps working, so every verb either
        /// answers or refuses with a teaching error:
        ///
        /// - **Work as usual:** query, dom, style, find, ax, shot (its CSS 3D
        ///   caveat included), pdf, archive, cookies, resize, and the act
        ///   primitives — a click or a submit lands, nothing of the page's
        ///   listens, and a form posts natively.
        /// - **Work from the isolated world:** contrast, overflow and the
        ///   caveat call the `window.sleepy` helpers there (``SleepyHelpers``),
        ///   so `eval` reaches them with ``InjectedScript/World/isolated``;
        ///   `--wait-for idle` samples there (``WaitCondition/idle``); wire
        ///   reads its inventory, and its fetch layer is empty because nothing
        ///   could call `fetch()`.
        /// - **Refuse:** `eval` in ``InjectedScript/World/page`` — the
        ///   default world — and the console, which no script could write to;
        ///   a `js:` or `message:` wait is refused before navigating.
        ///
        /// Event listeners do not fire either — WebKit invokes none, the
        /// isolated world's included — so whether a click navigated is judged
        /// from the host's side, at the cost of a short grace period per click
        /// that does not.
        case disabled
    }

    /// The budget hosts apply when ``budget`` is `nil`: every operation
    /// terminates (30 seconds).
    public static let defaultBudget: TimeInterval = 30

    /// The deadline hosts give each call into the page when ``callBudget`` is
    /// `nil` (60 seconds).
    ///
    /// Sized for a machine under load, not for a healthy page: a call that
    /// answers in milliseconds alone has taken tens of seconds under a
    /// parallel test suite, and a deadline near the healthy figure would
    /// report the machine's load as the page's failure. Its one job is that
    /// no call waits forever.
    public static let defaultCallBudget: TimeInterval = 60

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

    /// Whether the page's own scripts run. Default ``PageScripts/enabled``.
    ///
    /// Fixed when the host builds its web view, like ``backdrop``: it is a
    /// property of the host rather than of a load, so `sleepy open --no-js`
    /// opens a session whose every navigation runs without the page's
    /// scripts.
    public var pageScripts: PageScripts

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

    /// Deadline in seconds for each single call into the loaded page — an
    /// evaluation, a snapshot, the console count a load ends with; `nil`
    /// applies ``defaultCallBudget``.
    ///
    /// Separate from ``budget`` because it bounds something else: ``budget``
    /// is how long a load may take to settle, this is how long the page may
    /// take to *answer* one question. WebKit's completion handlers have no
    /// timeout of their own, so without it a page that never settles an
    /// evaluated promise suspends its caller for good. A call that outlives
    /// it throws ``SleepyError/Kind/timeout`` and leaves the host
    /// ``PageHost/abandonedCall``.
    public var callBudget: TimeInterval?

    /// Ordered actions executed after the load event and before ``wait``
    /// gates the verb's read; each auto-waits for its selector.
    public var steps: [ActionStep]

    /// Creates options, defaulting every field to the deterministic baseline.
    public init(
        size: ViewportSize = ViewportSize.default,
        theme: ColorTheme = .light,
        backdrop: Backdrop = .opaque,
        pageScripts: PageScripts = .enabled,
        jar: JarName? = nil,
        fileAccessRoot: URL? = nil,
        scripts: [InjectedScript] = [],
        dialogs: DialogPolicy = DialogPolicy(),
        wait: WaitCondition? = nil,
        budget: TimeInterval? = nil,
        callBudget: TimeInterval? = nil,
        steps: [ActionStep] = [],
    ) {
        self.size = size
        self.theme = theme
        self.backdrop = backdrop
        self.pageScripts = pageScripts
        self.jar = jar
        self.fileAccessRoot = fileAccessRoot
        self.scripts = scripts
        self.dialogs = dialogs
        self.wait = wait
        self.budget = budget
        self.callBudget = callBudget
        self.steps = steps
    }
}
