import CoreGraphics
import Foundation
import SleepyHollow
import Testing
import TestSupport

/// The pin for `project/2026-08-29-paint-after-fonts-ready.md`: a shot taken
/// with no settle after `document.fonts.ready` already shows the loaded
/// webfont, so a consumer needs no sleep between a page-side promise and a
/// capture.
///
/// Every test here is a happens-before, never a margin. The webfont's bytes
/// sit behind a ``FixtureGate``, so the fallback baseline provably predates
/// the font; the immediate capture is then compared against a *settled*
/// capture of the same page rather than against a golden image, which is the
/// question a caller actually has — "would waiting have changed the pixels?"
/// — and is decidable without asserting that the host beat anything.
@Suite("Paint after fonts.ready")
struct CapturePaintAfterFontsReadyTests {
    /// How different two captures of the same page must be before we call the
    /// webfont "landed". The fixture swaps five 160px serif glyphs for five
    /// solid bars, which measures 9.9365 mean channel levels over the whole
    /// viewport; antialiasing between two renderings of the same text is a
    /// fraction of one.
    private static let swapThreshold: Double = 5

    /// How long the settled reference waits after the immediate capture.
    /// Generous — it is an upper bound on "any repaint that was going to
    /// happen", not a discriminator, so load can stretch it freely.
    private static let settleSeconds: Double = 0.4

    /// How many times the repeat test samples the race. Each sample is a fresh
    /// host, so this is the term that decides the suite's cost under load.
    private static let repeats: Int = 4

    /// Every host here loads with a budget far past the default 30 s.
    ///
    /// Not a margin: nothing in this suite is decided by how long a load takes,
    /// and a parallel-agent Mac stretches host-side work 20–50× (`gotchas.md`,
    /// 2026-08-28). Under twelve CPU spinners the default budget failed the
    /// repeat test on a *load*, having measured the paint correctly — a
    /// generous upper bound removes the one thing here that was a race.
    private static let loadOptions: LoadOptions = .init(budget: 300)

    @Test
    @MainActor
    func `the fixture's webfont visibly changes the pixels`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let run = try await Self.measure(.bytes, hosting: .windowless, server: server, base: base)
            #expect(run.applied == "true")
            print("[paint] fallback vs settled, bytes swap: \(Self.render(run.fallbackVersusSettled))")
            #expect(run.fallbackVersusSettled > Self.swapThreshold)
        }
    }

    @Test
    @MainActor
    func `a shot straight after fonts ready shows the webfont, windowless`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let run = try await Self.measure(.bytes, hosting: .windowless, server: server, base: base)
            Self.expectImmediateIsSettled(run, label: "windowless, in-memory bytes")
        }
    }

    @Test
    @MainActor
    func `a shot straight after fonts ready shows the webfont in an offscreen window`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let run = try await Self.measure(.bytes, hosting: .offscreenWindow, server: server, base: base)
            Self.expectImmediateIsSettled(run, label: "offscreen window, in-memory bytes")
        }
    }

    @Test
    @MainActor
    func `a shot straight after fonts ready shows a CSS webfont fetched off the wire`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let run = try await Self.measure(.styleSheet, hosting: .windowless, server: server, base: base)
            Self.expectImmediateIsSettled(run, label: "windowless, CSS @font-face")
        }
    }

    @Test
    @MainActor
    func `a CSS webfont in an offscreen window is painted by the shot that follows it`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let run = try await Self.measure(.styleSheet, hosting: .offscreenWindow, server: server, base: base)
            Self.expectImmediateIsSettled(run, label: "offscreen window, CSS @font-face")
        }
    }

    /// Repeats the tight race inside one host, so a single test run samples the
    /// race many times rather than once — the cheap half of the flake hunt.
    @Test
    @MainActor
    func `the immediate shot equals the settled shot on every repeat`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            var mismatches: [Double] = []
            for _ in 0 ..< Self.repeats {
                let run = try await Self.measure(.bytes, hosting: .windowless, server: server, base: base)
                #expect(run.applied == "true")
                #expect(run.fallbackVersusSettled > Self.swapThreshold)
                if run.immediateVersusSettled != 0 {
                    mismatches.append(run.immediateVersusSettled)
                }
            }
            print("[paint] repeats: \(Self.repeats), mismatches: \(mismatches.count) \(mismatches)")
            #expect(mismatches.isEmpty)
        }
    }

    // MARK: - Apparatus

    /// Whether the host's web view is parked in an ``OffscreenWindow``.
    ///
    /// A typed fact rather than a bool: it decides what WebKit does with time
    /// for the whole run, and both values are part of the finding.
    private enum Hosting {
        /// Every verb's default, and the one Woodcase snapshots through.
        case windowless
        /// `PageHost.ensureOffscreenWindow()` parked before the load.
        case offscreenWindow
    }

    /// One measurement, retried from scratch if WebKit's seam threw — see
    /// ``retryingStarvedWebKit(_:)``.
    @MainActor
    private static func measure(
        _ swap: Swap,
        hosting: Hosting,
        server: FixtureServer,
        base: URL,
    ) async throws -> Run {
        try await retryingStarvedWebKit {
            try await Self.swap(swap, hosting: hosting, server: server, base: base)
        }
    }

    /// How the page is made to swap in the webfont.
    private enum Swap {
        /// A `FontFace` built from bytes already in memory — the tightest race
        /// a font swap can present to the snapshot that follows it.
        case bytes
        /// A CSS `@font-face` whose bytes come off the wire after the gate
        /// opens — Woodcase's own shape.
        case styleSheet

        /// The page-world expression that performs the swap and resolves once
        /// `document.fonts.ready` has.
        var body: String {
            switch self {
            case .bytes:
                "return await window.__sleepyApplyBytes();"
            case .styleSheet:
                "return await window.__sleepyApplyStyle('/block-font.ttf');"
            }
        }
    }

    /// One run of the race: what the page reported, and the two differences
    /// that decide the finding.
    private struct Run {
        /// `document.fonts.check` after the swap, as JSON text. A weak signal
        /// on its own — `check` is true for a family with no `@font-face` at
        /// all (`WaitFontsStatusTests`) — so it says only that the page's swap
        /// ran without throwing. ``fallbackVersusSettled`` is what proves the
        /// font actually landed.
        let applied: String
        /// Fallback baseline against the settled capture: the calibration that
        /// stops a silently-failed font load from passing vacuously.
        let fallbackVersusSettled: Double
        /// The immediate capture against the settled one. Zero is the finding.
        let immediateVersusSettled: Double
    }

    /// Loads the fixture, captures the fallback, opens the gate, performs the
    /// swap, captures immediately, then captures again after a settle.
    @MainActor
    private static func swap(
        _ swap: Swap,
        hosting: Hosting,
        server: FixtureServer,
        base: URL,
    ) async throws -> Run {
        let host = PageHost(options: loadOptions)
        if hosting == .offscreenWindow { host.ensureOffscreenWindow() }
        let gate = FixtureGate()
        await gate.install(on: server)
        _ = try await host.load(URL(string: "webfont.html", relativeTo: base)!)

        let fallback = try await webfontCapture(on: host)
        await gate.open()
        let applied = try await host.evaluate(swap.body, in: .page)
        let immediate = try await webfontCapture(on: host)

        try await Task.sleep(nanoseconds: UInt64(settleSeconds * 1_000_000_000))
        let settled = try await webfontCapture(on: host)

        let fallbackVersusSettled: Double = try webfontDifference(fallback, settled)
        let immediateVersusSettled: Double = try webfontDifference(immediate, settled)
        return Run(
            applied: applied,
            fallbackVersusSettled: fallbackVersusSettled,
            immediateVersusSettled: immediateVersusSettled,
        )
    }

    /// Asserts the finding for one configuration: the font landed, and waiting
    /// would have changed nothing.
    private static func expectImmediateIsSettled(_ run: Run, label: String) {
        print(
            "[paint] \(label): fallback vs settled \(render(run.fallbackVersusSettled)), "
                + "immediate vs settled \(render(run.immediateVersusSettled))",
        )
        #expect(run.applied == "true")
        #expect(run.fallbackVersusSettled > swapThreshold)
        #expect(run.immediateVersusSettled == 0)
    }

    /// A difference figure as the finding doc quotes it.
    private static func render(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}
