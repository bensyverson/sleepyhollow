# Plan: what the first library embedding asked for

**Date:** 2026-08-29. **Source:** [2026-08-29-woodcase-harness-feedback.md](2026-08-29-woodcase-harness-feedback.md) — eleven findings from Woodcase rebuilding its `WKWebView` test harness on `PageHost`. The library did the job (25 of 25 snapshot rows byte-identical); this plan is the work that lets the consumer delete its workarounds. Discussed and agreed with Ben on 2026-08-29; the rulings below are his.

## Rulings

- **Waiting is page-side, host-bounded.** Finding 1 overturns a premise of [2026-08-20-wait-engine.md](2026-08-20-wait-engine.md): a host that *polls* on `@MainActor` starves under a busy main actor and reports a 10 s timeout on a page that was ready at 200 ms. `SelectorWatch` already has the right shape — the page pushes once, the host awaits a stream and keeps the deadline. `.predicate` adopts that shape; a `.message(name:)` condition is added for pages that instrument themselves. The host still owns every clock; it just stops being the thing that *checks*.
- **The backdrop uses the private `drawsBackground` KVC key, inside the library, with a canary.** macOS has no public API for a non-painting `WKWebView`. Owning the key in one place with a test that fails loudly if it stops working is better than every consumer setting it on a `webView` the docs reserve for capture. This tool will never see an App Store review.
- **A `HostGroup` is one browser, and the jar belongs to the browser.** WebKit keeps cookies and the HTTP cache in the same `WKWebsiteDataStore`, so sharing a cache means sharing cookies.

  > **Corrected 2026-08-29, while building the leaf** ([2026-08-29-host-group-cache.md](2026-08-29-host-group-cache.md)). The cookie half holds and is built; the cache half does not. A shared *non-persistent* data store shares no HTTP cache — an ephemeral session has no network cache, and the cache that does serve a repeated subresource lives in the web view's own content process, which two views never share. Measured: two views on one ephemeral store fetch the script twice, with or without a shared `WKProcessPool` (itself deprecated at this package's floor and provably inert); one view loading twice fetches once; two views on the *persistent* default store fetch once. Grouping buys no measurable per-load time. So finding 9's performance goal is unmet, and reaching it needs a decision about persistence or about re-using one web view — both now in `project/backlog.md`.
 Today's per-host jar bracket (import once per host, export after each load — `PageHost+Cookies.swift`) would resurrect deleted cookies and cross-write jars if two hosts shared a store. So the group carries the jar: imported once per group, exported after any member's load; a member whose `LoadOptions.jar` disagrees with the group's is a usage error. Ungrouped hosts are unchanged.
- **No fixed delay survives.** Woodcase sleeps a flat 150 ms after `document.fonts.ready` so a repaint with the loaded font lands before the snapshot — a guess in both directions, and the class of workaround this project exists to retire. The leaf is a spike first: `takeSnapshot` flushes the layer tree before rasterizing, so the sleep may already be unnecessary. If a snapshot straight after `fonts.ready` is pixel-correct under load, the deliverable is a finding, a pinning test and a doc sentence. Only if it is not do we build a paint signal — double `requestAnimationFrame` under the offscreen window with a host deadline, a happens-before rather than a timer.
- **Library first, CLI analog in the same leaf.** Every behaviour the library gains gets its flag or verb: `--wait-for message:<name>`, `--file-root`, `--transparent`, `sleepy resize`, and `HostGroup` under `shot --sweep`. The CLI stays a thin consumer; parity is a criterion, not a separate leaf.

## Decided against (to `project/backlog.md`)

- **Per-load `wait:`** — wait instrumentation is document-start user scripts installed at host init; per-load would mean tearing down and reinstalling user scripts between loads. Un-parked by a consumer that needs one host for pages with different conditions *and* cannot express them as one predicate.
- **Page-side `.idle`** — `settleIdle` samples from the host every 100 ms and starves the same way, but its quiet-window contract is deliberately host-owned. Un-parked by an `idle` timeout reported under load on a page that was quiet.

## Waves and file ownership

Leaves 2, 3 and 4 all write `PageHost.swift`, `LoadOptions.swift` and `LoadFlagOptions.swift`; they run under one writer, in that order. Leaves 1, 5 and 6 are disjoint from them and from each other, so the first wave is {1, 2, 5, 6} in parallel, then 3, then 4. Leaf 7 is the integrator's, last.

Every leaf: TDD red/green, DocC at 100 % on anything public, `swiftformat . --lint --config .swiftformat`, full suite through `FixtureServer.withRunning`, and the report names deviations from the brief and what in the brief was wrong.

## Tasks

```yaml
tasks:
  - title: Woodcase harness feedback
    desc: |
      The work from project/2026-08-29-woodcase-harness-feedback.md, as ruled in project/2026-08-29-woodcase-harness-plan.md. Read the plan's Rulings before claiming any leaf; each ruling is a decision already made.
    labels: [woodcase, wave-2]
    children:
      - title: "Page-side wait: predicate push and message condition"
        ref: wait
        labels: [wave-2a]
        desc: |
          WaitEngine.settlePredicate polls host.evaluate every 50 ms from @MainActor and starves under a saturated main actor (feedback finding 1 and 10). Make .predicate compile to a document-start page-world InjectedScript (a PredicateWatch beside SelectorWatch) that re-evaluates the expression with setTimeout(check, 16) — page timers keep wall time in this WebKit, gotchas 2026-08-28 — and posts once on WaitEngine.messageName; the host awaits the stream with the same slow backstop settleSelector uses. A predicate that throws every time still reports its failure on timeout. Add WaitCondition.message(name:): settle when the page posts anything to a script-message handler of that name in the page world; CLI spelling --wait-for message:<name> in LoadFlagOptions/PageExecution. Correct project/2026-08-20-wait-engine.md in place, as a marked block quote, where it says the engine re-checks on its own cadence; update project/recipes.md and the sleepy recipes text.
        criteria:
          - "A predicate true at 200 ms settles within one host hop under scripts/flake-hunt.sh load, with a regression test that fails against the old host-polling engine"
          - "WaitCondition.message(name:) settles on a page post and times out with a message naming the handler"
          - "--wait-for message:<name> parses, round-trips through LoadOptions+Wire, and is documented in help and recipes"
          - "project/2026-08-20-wait-engine.md carries the in-place correction and names the reproducing tool"
      - title: "Host API: per-load budget, resize, public render"
        ref: host-api
        labels: [wave-2a]
        desc: |
          Findings 5, 6 and 8. PageHost.load(_ url: URL, budget: TimeInterval? = nil) falls back to options.budget then LoadOptions.defaultBudget, so one host serves callers with different budgets. PageHost.resize(to: ViewportSize) sets the web view frame and, when an OffscreenWindow is parked, its frame too (OffscreenWindow already has a setFrame path); PageHost gains a public private(set) viewport that resize updates and ShotOperation reads instead of webView.frame.height. ShotOperation.render(on:) becomes public, documented as the CGImage path that skips the PNG round trip. Add a sleepy resize <WxH> session verb so an agent can check a breakpoint without reopening.
        criteria:
          - "load(_:budget:) applies the per-call budget and a timeout message names it"
          - "resize(to:) changes the next shot's dimensions and the page's matchMedia result, with and without an offscreen window parked"
          - "ShotOperation.render(on:) is public with DocC and a test that uses it without decoding a PNG"
          - "sleepy resize works against an open session and is in help and recipes"
      - title: File access root and transparent backdrop
        ref: file-backdrop
        labels: [wave-2b]
        blockedBy: [host-api]
        desc: |
          Findings 3 and 4. LoadOptions.fileAccessRoot: URL? — when set and the URL is file:, PageHost.load uses loadFileURL(_:allowingReadAccessTo:) so fetch()/XHR reach local files; CLI --file-root <dir>. Document in PageHost what a plain file: load can reach (relative subresources in sibling and parent directories, measured by Woodcase) and what it cannot. LoadOptions.backdrop: Backdrop, a nested enum with .opaque (default) and .transparent — a typed fact, not a bool. .transparent sets the private drawsBackground KVC key at host init, behind one internal function with a canary test that fails loudly if the key stops having an effect. Prove alpha survives ShotCapture.rasterize's pixel-size normalization and PNG encoding. CLI --transparent on shot and on the session open. Fixture pages for both.
        criteria:
          - "A file: page under --file-root can fetch() a sibling file; without it the same fetch fails, and both are tested"
          - "A shot of a transparent-backdrop page has alpha 0 where the page paints nothing, through --scale 2 and tiling"
          - "The canary test fails if drawsBackground stops taking effect"
          - "--file-root and --transparent parse, round-trip through LoadOptions+Wire, and are in help"
      - title: "HostGroup: shared data store, process pool and jar"
        ref: group
        labels: [wave-2b]
        blockedBy: [file-backdrop]
        desc: |
          Finding 9: every PageHost gets its own WKWebsiteDataStore.nonPersistent() and content process, so hosts share no cache; Woodcase measured 142 ms per load on a 3.4 MB-of-scripts page. Add a @MainActor final class HostGroup owning one non-persistent data store and a WKProcessPool, taken by PageHost.init(options:jars:group:). Per the plan's ruling the group is one browser: the group carries the jar — imported once per group, exported after any member's load — and a member whose LoadOptions.jar names a different jar is a usage error. Ungrouped hosts keep today's behaviour exactly. shot --sweep (ShotCommand+Sweep.swift) renders every combination through one group. Measure before and after with a script in scripts/ that names its flags, and record the figure in a note.
        criteria:
          - "Two hosts in a group see one cache: the second load of a fixture with a large script makes no request for it on the wire"
          - "Jar semantics hold across a group: a cookie set in one member's load is exported once, and a member with a different jar is refused"
          - "Ungrouped hosts have no observable change, and the existing jar tests pass unchanged"
          - "shot --sweep uses one group and the per-page cost is measured and noted"
      - title: "Paint after fonts.ready: spike, then signal only if needed"
        ref: paint
        labels: [wave-2a, spike]
        desc: |
          Finding 11. Woodcase sleeps 150 ms after document.fonts.ready before snapshotting, in case the repaint with the loaded font has not landed. Spike first: a fixture with a slow webfont served by FixtureServer, a shot taken immediately after fonts.ready with no sleep, run repeatedly under scripts/flake-hunt.sh 16-spinner load. If the pixels show the loaded font every time, write the finding as a dated project doc, pin it with a test, and add one DocC sentence on PageHost/ShotOperation that a shot flushes rendering and needs no settle after fonts.ready. Only if it fails: PageHost.awaitPaint(within:) — double requestAnimationFrame under ensureOffscreenWindow(), host deadline — and WaitCondition.painted with --wait-for painted, with the finding doc recording why. No fixed delay in either outcome.
        criteria:
          - "A dated finding doc records the measurement, the tool and flags, and which outcome applies"
          - "The chosen outcome is pinned by a test that runs under FixtureServer.withRunning"
          - "If a signal is built, it is a happens-before with a host deadline, documented in DocC and recipes"
      - title: Docs and the ArgumentParser floor
        ref: docs
        labels: [wave-2a]
        desc: |
          Findings 2 and 7. Package.swift declares swift-argument-parser from 1.5.0 but ShotCommand uses defaultAsFlag, which is 1.8+; raise the floor to from 1.8.0 and check Package.resolved. Document two deterministic behaviours a consumer coming from a raw WKWebView will see as a shift: ColorTheme defaults to .light and PageHost stamps NSAppearance(.aqua), so baselines do not follow the Mac's Dark Mode; ShotScale is explicit and refuses to upsample, so a pinned 2x fails loudly on a non-Retina Mac. One sentence each on ColorTheme, PageHost and ShotScale, and a short "Embedding the library" section in README.md pointing at them. Add the plan and feedback docs to CLAUDE.md's documentation list.
        criteria:
          - "Package.swift requires swift-argument-parser from 1.8.0 and the package resolves and builds"
          - "ColorTheme, PageHost and ShotScale DocC each carry the determinism sentence"
          - "README has an embedding section and CLAUDE.md lists both 2026-08-29 docs"
      - title: Backlog entries and integration
        ref: integrate
        blockedBy: [wait, host-api, file-backdrop, group, paint, docs]
        desc: |
          Integrator's leaf. Write the two backlog entries the plan decides against (per-load wait; page-side idle) with their un-park conditions. Merge each leaf's branch by squash, read the diff, commit through the hooks, push, close the leaves. Re-read the feedback doc's eleven items and confirm each is either shipped, documented, or in the backlog.
        criteria:
          - "project/backlog.md has dated entries for per-load wait and page-side idle"
          - "Every finding 1–11 maps to a shipped change, a doc sentence, or a backlog entry"
          - "main is pushed with the full suite green"
```
