# Wait engine — the settle phase, and what a headless page actually does

*2026-08-20 · Claude (implementation agent, leaf oCDLF) · status: shipped*

`--wait-for <selector | js:<expr> | idle | load>` now runs inside
`PageHost.load(_:)`, so every loading verb inherits it by passing its
`LoadOptions` through unchanged. This records the two things the code cannot:
what "idle" means exactly, and the measurements the mechanism choices rest on.

## The shape

One `WaitEngine` per host, built from `LoadOptions.wait` (`nil` and `.load`
build none, so those loads keep exactly their old pipeline). The engine
contributes document-start instrumentation the host installs before any
navigation, and then runs after `didFinish` until the condition holds or the
deadline passes. **One deadline covers both phases**: whatever navigating
spends, settling does not get again. Exhaustion is a `.timeout` naming the
condition — exit 3 — with the page left alone so `PageHost.facts` and the live
page stay readable.

| Kind | Mechanism | Cadence |
|---|---|---|
| `.selector` | isolated-world `MutationObserver` posting a script message, **plus** a host-side re-check | push, backstop every 250 ms |
| `.predicate` | host-side `evaluate` in the **page world** | every 50 ms |
| `.idle` | host-side sampling of a page-world activity watcher | every 100 ms, 500 ms quiet window |

## What "idle" means, exactly

A page is idle when 500 ms pass — measured on the host's clock — in which all
four hold:

1. no new `PerformanceResourceTiming` entry is recorded;
2. no `window.fetch` call starts or settles;
3. no `XMLHttpRequest.send` starts or reaches `loadend`;
4. nothing is outstanding: zero fetches and XHRs in flight, and every `<img>`
   in the document reports `complete`.

The window starts when the settle phase does, so `--wait-for idle` always
costs at least 500 ms: idle is a *measured* quiet window, not a snapshot of
"nothing in flight right now". A fetch counts as finished when its promise
settles (the response head), not when the page has read the body — an unread
streaming body is idle by this definition.

Deliberately invisible, because no API offers them to a page: work inside
workers and service workers (their fetches appear in neither the window's
resource timeline nor these hooks — see the wire spike), WebSocket and
EventSource traffic, and downloads that are connecting but have not yet
produced an entry. A page that requests something once per second *is* idle by
this contract, and that is the honest reading of a 500 ms window.

## Measurements (macOS 26.5.2, this machine, 2026-08-20)

Taken with throwaway probe tests in the package (`swift test --filter
WaitProbeTests`, sandbox off), each driving a real `PageHost` against
`FixtureServer`. The probes were deleted; the fixtures they used
(`wait-late.html`, `wait-idle.html`) are in the suite.

- **Page timers are not throttled in this WebKit.** With *no* host-side
  evaluation at all after `didFinish`, `setTimeout(…, 400)` fired at 400 ms and
  `setTimeout(…, 1500)` at 1501 ms. A host pump at 250 ms or 50 ms changed
  nothing (401/1501 ms). The page reports `document.visibilityState ===
  "hidden"`, so hidden-page throttling is available and simply is not being
  applied here.
- **`requestAnimationFrame` never fires**, pumped or not — there is no window
  to render into. Any fixture or page that schedules work through a rAF chain
  waits forever.
- **Network completions arrive unpumped**: a `fetch` issued on `load` resolved
  and produced its resource-timing entry during a 2 s host sleep with no
  evaluation.
- **A `MutationObserver` message reached the host 301 ms after `didFinish`**
  for an element the page appends on a 300 ms timer, with no host evaluation
  in between — the push path is real, not a formality.
- **The observer cannot see every match.** Neutering the backstop (one-line
  edit, re-run) leaves `#late` settling fine and `#agree:checked` timing out:
  assigning the IDL property `checked` changes what `:checked` matches without
  producing a single mutation record. Both mechanisms are load-bearing, and
  each is proven so by a test that fails without it.

## Decisions worth revisiting

- **Predicates evaluate in the page world**, not the isolated world the vision
  makes the default for `sleepy eval`. A wait predicate is a statement about
  the page's own state; in an isolated world every page global reads
  `undefined`, which is a silently wrong answer rather than a slow one. If
  `--page-world` ever lands as a flag, `--wait-for js:` should take it and keep
  page world as its default.

  > **Corrected in place (2026-08-28, eval world leaf):** the premise here is
  > gone — the vision no longer makes the isolated world the default for
  > `sleepy eval`, for exactly the reason this bullet gives. `eval` defaults
  > to the page world and takes `--world page|isolated`; the flag is not
  > `--page-world`. Should `--wait-for js:` ever grow a world flag, it is
  > `--world`, and this bullet's ruling — page world as the default — already
  > matches the verb's. See
  > [2026-08-28-agent-feedback-synthesis.md](2026-08-28-agent-feedback-synthesis.md)
  > § Rulings.
- **A predicate that throws is "not true yet"**, not a failure: `window.app.ready`
  before `app` exists is the common case. The last JavaScript failure is kept
  and printed in the timeout message, so a typo costs one budget and then says
  `TypeError: …`. An invalid *selector*, by contrast, is a usage error the
  first time it is checked — it can never start matching.
- **Wall-clock assertions in tests must stay generous.** Every WebKit test is
  `@MainActor`, and the full suite runs in parallel, so a load that takes 1.5 s
  alone can measure 4.2 s in the full run. Tests that need to prove *when*
  something settled use the page's own late element as the clock instead.
