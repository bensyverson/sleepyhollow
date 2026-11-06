import WebKit

/// The one place ``LoadOptions/PageScripts`` reaches WebKit.
extension WKWebViewConfiguration {
    /// Turns the page's own JavaScript on or off for every navigation this
    /// configuration's web view makes.
    ///
    /// **Two switches, because the public one does only half the job.**
    /// Measured 2026-11-06 against `no-js.html`:
    ///
    /// - `WKWebpagePreferences.allowsContentJavaScript = false` stops the
    ///   page's scripts but leaves the page *styled as if scripting were on*:
    ///   the parser builds `<noscript>`'s children as elements, yet their
    ///   computed `display` is `none` (an author `!important` cannot override
    ///   it) and `matchMedia('(scripting: enabled)')` is `true`. The fallback
    ///   sits in the DOM at a 0×0 rect — a progressive-enhancement check that
    ///   would report the fallback missing, a plausible wrong answer.
    /// - `WKPreferences.javaScriptEnabled = false` (deprecated in macOS 11 in
    ///   favor of the first, still honored) is the browser's real scripting
    ///   switch: `<noscript>` renders and `(scripting: none)` matches. It also
    ///   closes the **page** content world to the app — `callAsyncJavaScript`
    ///   there fails at once with "Cannot execute JavaScript in this document"
    ///   — while the tool's isolated world keeps evaluating, running its user
    ///   scripts and posting script messages. ``LoadOptions/PageScripts``
    ///   documents what that means verb by verb.
    ///
    /// The deprecated setter is reached through ``ScriptingSwitch`` so the
    /// one use does not put a deprecation warning in every build.
    func applyPageScripts(_ pageScripts: LoadOptions.PageScripts) {
        let enabled: Bool = pageScripts == .enabled
        defaultWebpagePreferences.allowsContentJavaScript = enabled
        var scripting: any ScriptingSwitch = preferences
        scripting.javaScriptEnabled = enabled
    }
}

/// `WKPreferences.javaScriptEnabled`, restated without its deprecation.
///
/// Its replacement, `allowsContentJavaScript`, does not render `<noscript>`
/// (see ``WKWebViewConfiguration/applyPageScripts(_:)``), so this is the one
/// deprecated API the package relies on on purpose.
@MainActor
protocol ScriptingSwitch {
    /// Whether any JavaScript runs in the page's own world.
    var javaScriptEnabled: Bool { get set }
}

extension WKPreferences: ScriptingSwitch {}
