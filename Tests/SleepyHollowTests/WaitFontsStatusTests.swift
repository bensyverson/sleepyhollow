import CoreGraphics
import Foundation
import SleepyHollow
import Testing
import TestSupport

/// What an agent must actually type to capture a page whose webfonts arrive
/// late — the routing half of
/// `project/2026-08-29-paint-after-fonts-ready.md`, which proves the *other*
/// half: that no settle is needed between the wait and the shot.
///
/// Three facts are pinned here, and each contradicts the obvious guess. A
/// `@font-face` in the page's own stylesheet is already covered by the load
/// event, so the everyday case needs no flag at all. Neither
/// `document.fonts.status === 'loaded'` nor `document.fonts.check(…)` is a
/// safe webfont condition: both read ready on a page that has not requested
/// the font, so a page that asks for one *after* load settles on its fallback.
/// The one thing that does work — a predicate wait followed straight by a
/// capture — is pinned too, so the seam stays honest even though the recipe
/// no longer sends anyone through it for fonts.
///
/// Every comparison is against a settled capture of the same page, never a
/// golden image, and every claim about a font's absence is held by the page
/// never asking for it — no clock, and in particular no shut ``FixtureGate``,
/// whose hold expires after 30 s and is documented as a safety net rather
/// than something a test may lean on.
@Suite("Waiting for webfonts")
struct WaitFontsStatusTests {
    /// The global-status predicate: correct for a font already requested,
    /// prematurely true for one that has not been.
    private static let fontsLoaded: String = "document.fonts.status === 'loaded'"

    /// The named-font predicate that *looks* safer than the global status and
    /// is not: a family with no `@font-face` resolves to an available
    /// fallback, so `check` is true before the page has asked for anything.
    private static let fontChecks: String = "document.fonts.check('160px SleepyBlock')"

    /// Every host here loads with a budget far past the default 30 s: a
    /// parallel-agent Mac stretches host-side work 20–50× (`gotchas.md`,
    /// 2026-08-28), and nothing here is decided by how long a load takes.
    private static let budget: TimeInterval = 300

    /// Mean channel difference above which the bar glyphs have replaced the
    /// serif fallback. Measured at ~10; single digits are antialiasing.
    private static let swapThreshold: Double = 5

    @Test
    @MainActor
    func `the load event already waits for a stylesheet webfont`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let (status, landed) = try await retryingStarvedWebKit { () -> (String, Double) in
                let fallback = try await Self.fallbackCapture(base: base)
                let host = PageHost(options: LoadOptions(wait: .load, budget: Self.budget))
                _ = try await host.load(URL(string: "webfont-late.html", relativeTo: base)!)
                let status = try await host.evaluate("return document.fonts.status;", in: .page)
                let atLoad = try await webfontCapture(on: host)
                return try (status, webfontDifference(fallback, atLoad))
            }
            print("[paint] at the load event: fonts.status \(status), vs fallback \(Self.render(landed))")
            // Measured 2026-08-29: WebKit holds the load event for a pending
            // @font-face subresource, so `sleepy shot <url>` with no flag at
            // all already shows the webfont. If this ever goes the other way,
            // the recipe stops being optional.
            #expect(status == "\"loaded\"")
            #expect(landed > Self.swapThreshold)
        }
    }

    @Test
    @MainActor
    func `both font predicates read ready before the page has requested a font`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            // No gate route is registered, so nothing on the page ever asks for
            // the webfont: the premature-true case, by program order and with
            // no clock in it at all.
            let (status, checks) = try await retryingStarvedWebKit { () -> (String, String) in
                let host = PageHost(options: LoadOptions(budget: Self.budget))
                _ = try await host.load(URL(string: "webfont.html", relativeTo: base)!)
                return try await (
                    host.evaluate("return document.fonts.status;", in: .page),
                    host.evaluate("return \(Self.fontChecks);", in: .page),
                )
            }
            print("[paint] with no font requested: fonts.status \(status), fonts.check \(checks)")
            // Both are the *plausible wrong answer* this tool refuses to give:
            // status is "loaded" because nothing is loading, and check() is
            // true because a family with no @font-face resolves to a fallback
            // that is trivially available. Neither can be a webfont recipe.
            #expect(status == "\"loaded\"")
            #expect(checks == "true")
        }
    }

    @Test
    @MainActor
    func `a shot after the fonts-loaded predicate shows a late webfont`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let run = try await retryingStarvedWebKit {
                try await Self.wait(
                    on: Self.fontsLoaded,
                    for: "webfont-late.html",
                    base: base,
                    label: "js:fonts.status, stylesheet font",
                )
            }
            #expect(run.landed > Self.swapThreshold)
            #expect(run.waited == 0)
        }
    }

    @Test
    @MainActor
    func `a font predicate settles on a page whose font has not arrived`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            // No gate route, so the page never requests its webfont — yet the
            // wait settles and the load returns, on the fallback.
            let difference: Double = try await retryingStarvedWebKit {
                let fallback = try await Self.fallbackCapture(base: base)
                let host = PageHost(options: LoadOptions(wait: .predicate(Self.fontChecks), budget: Self.budget))
                _ = try await host.load(URL(string: "webfont-later.html", relativeTo: base)!)
                return try await webfontDifference(fallback, webfontCapture(on: host))
            }
            print("[paint] js:fonts.check on a font-less page: vs fallback \(Self.render(difference))")
            #expect(difference == 0)
        }
    }

    // MARK: - Apparatus

    /// What one predicate wait measured.
    private struct Run {
        /// Fallback against the settled capture: proof the font arrived at all.
        let landed: Double
        /// The capture taken straight after the wait, against the settled one.
        /// Zero says the wait was sufficient and no settle was needed.
        let waited: Double
    }

    /// Loads `page` behind `predicate`, captures immediately, then captures
    /// again after a generous settle.
    @MainActor
    private static func wait(
        on predicate: String,
        for page: String,
        base: URL,
        label: String,
    ) async throws -> Run {
        let fallback = try await fallbackCapture(base: base)
        let host = PageHost(options: LoadOptions(wait: .predicate(predicate), budget: budget))
        _ = try await host.load(URL(string: page, relativeTo: base)!)

        let immediate = try await webfontCapture(on: host)
        try await Task.sleep(nanoseconds: 800_000_000)
        let settled = try await webfontCapture(on: host)

        let landed: Double = try webfontDifference(fallback, settled)
        let waited: Double = try webfontDifference(immediate, settled)
        print("[paint] \(label): fallback vs settled \(render(landed)), immediate vs settled \(render(waited))")
        return Run(landed: landed, waited: waited)
    }

    /// The same text and viewport with no webfont available, from the gated
    /// fixture with its gate left shut — the fallback every late page starts at.
    @MainActor
    private static func fallbackCapture(base: URL) async throws -> CGImage {
        let host = PageHost(options: LoadOptions(budget: budget))
        _ = try await host.load(URL(string: "webfont.html", relativeTo: base)!)
        return try await webfontCapture(on: host)
    }

    /// A difference figure as the finding doc quotes it.
    private static func render(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}
