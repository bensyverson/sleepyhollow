# Triage of the 2026-08-30 Woodcase feedback — plan

**Date:** 2026-11-06. Triages `2026-08-30-sleepy-hollow-feedback.md`, a field report from one day of heavy library and CLI use in Woodcase (three agents, about 50 browser tests). It arrived on 2026-09-15 inside an unrelated commit and was never triaged; a coverage audit on 2026-11-06 found nine of its ten friction items untracked.

## Where each item went

| 08-30 item | Leaf |
|---|---|
| 1. Load with JavaScript off | JavaScript-off loading |
| 2. No keyboard act verb | A trusted `press` |
| 3. `evaluate` decoded overload, built-in `waitUntil` | Embedder scripting ergonomics |
| 4. A thrown JS body reads as `""` | Embedder scripting ergonomics |
| 5. Navigation vs same-document swap | A navigation signal |
| 6. CSS transitions don't advance | Fix: `ND4YmR` and the True-3D plan's spike. The loud docs paragraph: Docs and discoverability |
| 7. Resize after load | Already shipped (`PageHost.resize(to:)`) before the report; a discoverability gap, so Docs and discoverability |
| 8. Integer `clientX` under transforms | Small investigations |
| 9. `CFPasteboardSetExpirationDate` noise | Small investigations |
| 10a. Hover and focus states before a shot | Shot staging and the `--viewport` alias |
| 10b. `--scale` on a `--selector` crop | Already shipped (`shot --scale`); Docs and discoverability |
| 10c. Accept `--viewport` | Shot staging and the `--viewport` alias |

The report's "what worked" section is worth keeping too: `PageHost` + `LoadOptions` + `evaluate(_:in: .page)` is the right primitive set, multi-statement bodies carry the testing style, and returning a diagnostic string beats returning a bool. Nothing here should break those.

Each leaf is *investigate, then fix if it holds up*: confirm the problem against today's code first (several items are from a September build), and where a fix needs a product decision, stop and bring it back rather than guessing.

## Verdicts

**Item 1, JavaScript off (2026-11-06, leaf `4GBnw4`).** Shipped as `--no-js` / `LoadOptions(pageScripts: .disabled)`: `<noscript>` renders, every verb answers or refuses with a teaching error (`eval` in the page world, `console`, `js:`/`message:` waits, `--inject-world page`). Rulings made in Claude's hands, two-way doors: `eval` under `--no-js` refuses rather than silently switching to the isolated world; `console` refuses while `load` reports `consoleErrorCount: 0` (literally true: the console records only what scripts write); depending on the deprecated `WKPreferences.javaScriptEnabled` is accepted, since nothing else renders `<noscript>`.

**Item 4, a thrown body reads as `""` (2026-11-06, leaf `emvuHf`).** Not reproduced: raw `PageHost.evaluate` always threw on a thrown body, an unparseable one, `throw 'bare string'` and a `BigInt` return, so the `""` came from Woodcase's own helper. The real defect was that WebKit's error said only "A JavaScript exception occurred" and hid the page's message in `userInfo`; `evaluate` now throws `EvaluationError.javaScript(message:)` naming it (`PageHostScriptErrorTests`).

**Item 6, frozen animation (2026-11-06, leaf `GzK3Rl`).** Fixed rather than documented: every `PageHost` is now live-hosted, so rAF, transitions and Web Animations run (`LiveHostingGoldenTests`, ND4YmR's fixture). The docs leaf's "loud paragraph" becomes "pages animate; wait for the end state", now in `shot --help` and recipes; the frozen behavior is opt-in via `PageHost.Hosting.windowless`.

**Item 8, integer `clientX` (2026-11-06, leaf `ez5x58`).** WebKit's limit, not ours: nothing in Sleepy rounds the point, but WebKit truncates a `MouseEvent`'s `clientX`/`clientY` to whole px whatever the init dictionary says, and a `PointerEvent` too when its type is `click` or `auxclick`. So `mousedown`, `mouseup` and `click` handlers see the integer part, and `pointerdown`/`pointerup` keep the fraction (probed in-page). Documented in `click --help` and DocC, pinned by `ClickFractionalPointTests` (a canary: it goes red if WebKit starts keeping the fraction). Woodcase's workaround: read the position from `pointerdown`/`pointerup`, or click with `--selector`. Element-relative `--at` is parked in `backlog.md` (2026-11-06).

**Item 9, pasteboard noise (2026-11-06, leaf `ez5x58`).** WebKit's, not Woodcase's tests and not Sleepy code. `sleepy dom <page> --click '#b'`, where the click runs `document.execCommand('copy')` or `navigator.clipboard.writeText`, prints `CFPasteboardSetExpirationDate returns error: Pasteboard already has contents.` on stderr (reproduced twice). Any page that copies triggers it under any host; not silenced. The same probe suggests the page's copy reaches the user's real system clipboard, which is a bigger problem than the noise: filed as issue `OqJ4a7`.

**Docs leaf, discoverability (2026-11-06, leaf `0WjGWJ`).** Done: the diagnostic-string pattern (a worked `evaluate(_:as:)` example in DocC and the README, and an `eval` recipe), `resize(to:)` and `shot --scale` (README quick start, a new DocC landing page at `Sources/SleepyHollow/SleepyHollow.docc/SleepyHollow.md` since the module had no catalog, and a `--scale` recipe), the eval-world note in the README, and the new library API (typed `evaluate`, `waitUntil`, `navigationCount`, `EvaluationError`, `--no-js`, live hosting) in the README's embedding section and the landing page. The frozen-animation paragraph is obsolete (item 6). Declined: the "about 50 MB" figure in `shot --help`. The 08-28 scale-flag doc's intent holds (warn that `--full-page --scale` is expensive), but the number is wrong: the bitmap is width x height x scale squared x 4 bytes, so 1280 x 9,000 points at 2x is about 184 MB, and 50 MB fits only a page about 350 points wide; its "existing height ceiling" does not exist in the code either. The corrected note is in the `--scale` recipe; `ShotCommand.swift` belongs to the compositor agent, so the matching `--help` sentence goes there as an integration note.

## Tasks

Imported 2026-11-06; the tracker holds the current version (`job ls`).

```yaml
tasks:
  - title: Triage the 2026-08-30 Woodcase feedback
    desc: |
      Plan: project/2026-11-06-woodcase-0830-triage.md; the report is project/2026-08-30-sleepy-hollow-feedback.md. Each leaf confirms its problem against today's code first, then fixes it or brings a decision back.
    labels: [epic, feedback]
    children:
      - title: JavaScript-off loading
        desc: |
          Why: Woodcase treats progressive enhancement as a first-class acceptance criterion, and "the page works with JS off" is exactly what a browser can settle. With no way to turn scripting off, they proved it over URLSession instead, a 133-line suite testing the server's markup rather than the browser's rendering (08-30 item 1).

          What: a load option that disables the page's own JavaScript, in the library (`LoadOptions`, Sources/SleepyHollow/Core/LoadOptions.swift) and as a CLI load flag shared by every verb (Sources/SleepyCLIKit/Options/LoadFlagOptions*.swift), so `sleepy shot --no-js` and an embedder's three-line test both work.

          Investigate first: `WKWebpagePreferences.allowsContentJavaScript` (public, macOS 11) disables page content scripts per navigation. The key question is what still works with it off. Sleepy's own helpers run in an isolated content world (InjectedScript, SleepyHelpers*), and `query`, `ax`, `eval --world isolated`, `contrast`, `overflow` and the wait engine all depend on injected script. Measure which verbs keep working, and decide what `eval --world page` does (refuse with a teaching error, presumably). `--wait-for idle` and `js:` predicates also need an answer. `<noscript>` content must render.

          Open questions: the flag's name and shape (`--no-js`, `--scripting off`) is the builder's call, following existing flag style; anything that changes a verb's contract is Ben's.
        criteria:
          - A page with a noscript fallback renders the fallback with scripting off, through the library and the CLI (tests)
          - Every verb either works with scripting off or refuses with a teaching error (test per verb family)
          - DocC, --help and recipes describe it
      - title: A trusted press
        desc: |
          Why: there is no keyboard act verb. Woodcase hand-copies an untrusted `KeyboardEvent` dispatch into four test files, and nothing built that way can exercise an `isTrusted` check or a real default action: typing into a field, Tab focus movement, Enter submitting a form, Escape closing a dialog (08-30 item 2).

          What: `PageHost.press(_:)` in the library and a `sleepy press` act verb beside click/fill/submit, delivering keys the way a user's keyboard would, so `isTrusted` is true and default actions run.

          Investigate first: whether WebKit delivers trusted key events to a windowless or off-screen-hosted WKWebView. Likely route: synthesize `NSEvent` key events and send them through `WKWebView.keyDown(with:)`/`keyUp(with:)`; that may need the view to be first responder in an `OffscreenWindow`, and possibly a key window (see project/2026-11-06-true-3d-shots.md and spike leaf B3dXgQ question 7, which measures a key-window override; coordinate rather than duplicate). Modifiers, named keys (Enter, Tab, Escape, arrows) and text input (IME aside) all need a shape.

          Seams: act verbs live in Sources/SleepyHollow/Operations/ (ClickOperation, ActionScript*) and Sources/sleepy/ClickCommand.swift etc.; the session and one-shot paths both apply.

          Open questions for Ben: the key syntax (`Enter`, `Meta+K`, a string to type) and whether `press` targets a selector (focus it first) or whatever has focus. If trusted delivery proves impossible, bring that back rather than shipping untrusted events under a trusted-sounding name: that would be a plausible wrong answer.
        criteria:
          - "A pressed key arrives with isTrusted true and runs its default action: text typed into a focused input, Enter submits a form, Tab moves focus (tests)"
          - press exists in the library and the CLI with DocC, --help and recipes
      - title: Embedder scripting ergonomics
        desc: |
          Why: every Woodcase bench hand-writes the same two helpers: five copies of a 6-line `ask()` that decodes `evaluate`'s JSON-text return, and five of a polling `waitFor(_:_:within:)` (08-30 item 3). A thrown JS body also reportedly comes back as `""`, so the failure reads as a mismatch against an empty string (item 4).

          What:
          - An `evaluate` overload that returns a decoded `Decodable` value (Sources/SleepyHollow/Host/PageHost+Scripting.swift). The JSON-text return stays; the gotcha "`PageHost.evaluate` returns the value's JSON, so a string comes back quoted" is the trap this removes.
          - A `waitUntil` for a page that is already loaded. Already decided: waiting is page-side, because host-side polling starves under a busy main actor (project/2026-08-29-woodcase-harness-plan.md and -feedback.md). Reuse the wait engine's page-side predicate watch (WaitEngine+Predicate, PredicateWatch) rather than adding a host poll loop.
          - Item 4: first reproduce it. `PageHost.evaluate`'s DocC says it throws WebKit's error, and EvalOperationTests covers a syntax error through EvalOperation, but nothing tests the raw `PageHost.evaluate` throw path. If it throws, add the regression test and record that the `""` was Woodcase's own helper. If it doesn't, fix it with a typed error that carries the JS message.

          Out of scope: CLI changes; `eval` already reports errors.
        criteria:
          - A decoded evaluate returns typed values and throws a typed error on a type mismatch (tests)
          - waitUntil on a loaded page resolves on a page-side condition and times out with a teaching error (tests, no host polling)
          - A thrown or syntactically invalid JS body surfaces as a thrown error naming the JS message (regression test)
      - title: A navigation signal
        desc: |
          Why: a client-side-navigation test's whole subject was "did the page reload?" The only probe was a self-stamped `window` marker, which silently fails for back navigations because WebKit's back-forward cache restores the document with its JS heap (08-30 item 5).

          What: a way for an embedder to tell a real navigation from a same-document swap: a navigation count on `PageHost`, an awaitable navigation event, or both. Builder's call after investigating, but it must count bfcache restores as navigations, and must not count `history.pushState`/hash changes (or must report them distinctly).

          Seams: `PageHostDelegate` (Sources/SleepyHollow/Host/PageHostDelegate.swift) already sees `didCommit`; WKNavigationDelegate distinguishes same-document navigation. Check what a bfcache restore looks like from the delegate.

          Open question for Ben if it comes up: whether the CLI needs this at all (sessions?) or it stays library-only.
        criteria:
          - A full navigation, a back navigation restored from the bfcache, and a pushState swap are each told apart (tests)
          - DocC describes it
      - title: Shot staging and the --viewport alias
        desc: |
          Why: verifying a hover-color fix or a client-side mode was impossible in a static shot: anything whose state isn't in the URL can't be staged (08-30 item 10a). And `--viewport` is the name people reach for; Woodcase's agent misremembered it, and so did an agent here on 2026-11-06 (item 10c).

          What:
          - Check what already exists: `shot` takes `--click`, `--fill` and `--submit` staging steps today (ActionStep, LoadOptions.steps), so "an interaction before capture" may be covered. Add hover and focus as staging steps if they're missing.
          - Hover needs a real pointer: CSS `:hover` responds to the mouse position, not to a dispatched `mouseover`. Investigate synthesizing an `NSEvent` mouse move through the web view (it may need the off-screen window), and whether `:focus-visible` follows a programmatic focus.
          - Accept `--viewport` as an alias for `--size` on every verb that takes `--size`. Existing aliases use `customLong` (`--element`, `--full`); follow them.
        criteria:
          - A shot staged with hover shows the :hover style, and one staged with focus shows the focus style (golden tests)
          - --viewport works wherever --size does (test)
      - title: Small investigations, clientX and pasteboard noise
        desc: |
          Two small items from 08-30; each needs a verdict more than a feature.

          Integer clientX (item 8): `click --at` hit-tests through `elementFromPoint`, which handles transformed ancestors, but then dispatches `clientX: x` (Sources/SleepyHollow/Operations/ActionScript+Bodies.swift, the mouse event init), and a page handler that recomputes position from `clientX` on a sub-1-scaled canvas truncates into the wrong box. Find out whether WebKit's MouseEvent keeps fractional clientX (the CSSOM View spec made it a double). If it does, pass the fraction through; if it doesn't, document the limit in `click --help` and DocC. Woodcase's helper is quoted in its project/gotchas.md (2026-08-30). Element-relative `click --at` was promised "later" in project/2026-08-28-agent-feedback-synthesis.md and never parked; park it in project/backlog.md or fold it in.

          Pasteboard noise (item 9): `CFPasteboardSetExpirationDate returns error: Pasteboard already has contents.` appears on stderr in clipboard-touching suites. Sources/ has no pasteboard code, so it is probably Woodcase's own tests or WebKit's. Find out which; if it's ours or WebKit's under our host, silence or document it; if it's Woodcase's, say so in the plan doc and close.
        criteria:
          - Fractional clientX either reaches the page (test) or the limit is documented in click --help and DocC
          - The pasteboard message's source is identified and handled or ruled out, with the verdict in project/2026-11-06-woodcase-0830-triage.md
      - title: Docs and discoverability
        desc: |
          Why: two of the report's asks (resize after load, `--scale` on a selector crop) had already shipped and the Woodcase agents didn't find them; the report also asked for two pieces of documentation.

          What:
          - A loud paragraph in the library docs that animation time doesn't advance in a windowless host (rAF, CSS transitions, Web Animations), with the workaround (assert the class change plus the transition rule) and a pointer to issue ND4YmR. Update it if the True-3D plan's spike (B3dXgQ) changes the answer.
          - Showcase the house pattern of returning a diagnostic string from `evaluate` rather than a bool.
          - Make `PageHost.resize(to:)` and `shot --scale` discoverable where an embedder or agent would look: the README's quick start, the DocC landing page, recipes.
          - The README note on the eval world, which 08-24 asked for and only --help got.
          - The shot help note that a 9,000-point page at 2× is about 50 MB, if the 08-28 scale-flag doc's intent still holds.

          Seams: README.md, DocC comments in Sources/, project/recipes.md (same content as `sleepy recipes`; keep them in step).
        criteria:
          - Each of the five items is in the docs, or recorded as declined with a reason in project/2026-11-06-woodcase-0830-triage.md
```
