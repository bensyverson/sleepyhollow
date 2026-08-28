# Wait-family flakes — the host's clock and the page's clock are not the same clock

*2026-08-28 · Claude (implementation agent, leaf p9MFz) · status: shipped*

Three wait tests each failed once on 2026-08-28 during full-suite runs while
five to seven other agents were building and testing on the same Mac, and
passed in isolation and on every clean re-run:

- `WaitBudgetTests` — "wait load still settles on the load event alone"
  (`Expectation failed: (matched → "true") == "false"`)
- `WaitBudgetTests` — "a slow navigation leaves the wait less budget"
- `WaitSelectorTests` — "a selector already present when the load event fires
  settles at once"

They are not the golden-test contention class (subprocess storms, capped by
`TestSupport.WebKitGate` on 2026-08-20). These are in-process unit tests, and
what they have in common is that each one **bets that the host gets back to
the page before a page-side `setTimeout` fires**. Under load that bet is lost:
the page's timers keep wall time while everything on the host's side stretches
by one to two orders of magnitude.

## The measurement

Taken with a throwaway probe test in the package (now deleted; the fixture
marker it used, `window.sleepyLoadAt` in `wait-late.html`, stayed). Each
iteration loads `wait-late.html?flip=gate` with `--wait-for load` and then
evaluates `performance.now() - window.sleepyLoadAt` in the page world — the
page's own measure of how long the host took to come back to it.

Quiet machine, `swift test --skip-build --filter FlakeProbe`:

| | `load()` wall time |
|---|---|
| first load in the process (WebKit warm-up) | 1804 ms |
| every later load | 108–147 ms |

Under load — the full 700-test suite in one process (so 12 concurrent WebKit
instances, the `WebKitGate` width) with twelve `yes > /dev/null` spinners on an
8-core Mac, which is the load `scripts/flake-hunt.sh 1 12` now produces (a
green full suite on the same machine ran in 47 s unloaded; one measured run
under sixteen spinners took 742 s):

| probe | load-event → first evaluate (page clock) | `load()` wall time |
|---|---|---|
| 0 | 302 ms | 1677 ms |
| 1 | 205 ms | 7019 ms |
| 2 | 231 ms | 4164 ms |
| 3 | 153 ms | 4657 ms |
| 4 | 696 ms | 2565 ms |
| 5 | 1149 ms | 2404 ms |

A trivial local page taking **7 seconds** to load, and over a second between
the load event and the first evaluation the host manages, is a 20–50× stretch
of exactly the quantity these tests had 3 seconds of margin for. The page's
`setTimeout` does not stretch with it (measured 2026-08-20, wait-engine doc:
timers in this WebKit fire on time), so the margin is not a margin — it is a
race between two clocks that decouple under load.

In the same loaded run, the old assertion restated with its margin at 200 ms
failed with the reported wording:

```
Test "the old margin-based assertion…" recorded an issue:
Expectation failed: (matched → "true") == "false"
flip=200: --wait-for load must not wait for anything the page does later
```

## Diagnosis, test by test

**"wait load still settles on the load event alone."** `#late` is appended by
a page timer 3000 ms after parse; the test asserts it is absent after `load()`
returns. The assertion holds only while (host latency from parse to the test's
first evaluate) < 3000 ms — measured at ~150 ms quiet, 1149 ms under load, with
`load()` alone reaching 7 s. *Reproduced* (forced: margin shrunk to 200 ms,
identical failure text).

**"a selector already present when the load event fires settles at once."**
The same fixture, the same 3000 ms flip, the same assertion one evaluation
later (after `facts.httpStatus`), so it has *less* margin than the first.
*Reproduced by the same forced run* — same mechanism, same fixture.

**"a slow navigation leaves the wait less budget, not a fresh one."** Budget
1 s, document held back 900 ms by the server, `#late` appended 300 ms after
parse; the test expects a `.timeout`, because a shared budget cannot reach the
element while a per-phase one could. Two *host* clocks decide it:
`PageHost.navigate`'s budget task (`Task.sleep(1s)`, resumed on the main actor)
and WebKit's `didFinish`. When main-actor congestion delays the budget task
past a `didFinish` that is itself late — plausible when the first load in a
process costs 1.7 s against a 1 s budget — `navigate` returns `.finished`
*after* the deadline has passed, and `WaitEngine.settleSelector` takes its
first probe before it consults the deadline. It finds `#late` already in the
DOM, because the page's own 300 ms timer fired on time long ago, and returns
success: no timeout, and `Issue.record("expected a timeout")` fires. **Not
reproduced** — this is the only mechanism consistent with the failure, and the
measurements above make it reachable, but I did not catch it red.

## The fix: happens-before, not margins

`TestSupport.FixtureGate` is a latch a fixture page blocks on. It registers a
route that holds every request until the test calls `open()`, and
`wait-late.html?flip=gate` appends `#late` when that request resolves (a
`fetch`, deliberately: an outstanding fetch does not delay the load event,
while a script or image element would).

So "the element is not there yet" stops being a race the host can lose and
becomes **program order**: with the gate closed, the page cannot have flipped,
however slow the machine is. The three settles-at-once assertions — and their
untouched-but-identical twin in `WaitPredicateTests` — now read that way, plus
two generously-bounded liveness checks that keep them from proving nothing
(the page really did reach the gate; opening it really does produce the
element).

The budget test keeps one timing element, because "the wait got less than a
fresh budget" is irreducibly about elapsed time. It is now one-sided and
anchored to the page rather than to the test's own clock: the release waits
for the page's gate request (which happens as the document parses, i.e. when
the navigation's delay is spent) and then sleeps `budget - delay + 0.5s`, so
it lands after the shared deadline and inside the fresh per-phase deadline a
regression would grant — both margins moving with the navigation, however slow
it was. A sleep can only fire *late*, so a loaded machine can only push the
release past both deadlines and make the test prove less; it can never end the
wait early and turn the test red.

## What was considered and not done

**An injectable clock in the engine (route 2).** The fragile quantity is not
`WaitEngine`'s own cadence — it is the skew between the page's real
`setTimeout` and the host's scheduling. A fake clock would not remove the
page's timer or WebKit's real navigation, so it would move the flake rather
than end it, and `deadline` is a `DispatchTime` threaded from `PageHost`
through the navigate budget task, `runActionSteps` and the engine: a clock
seam is a broad change to `PageHost` for no gain here.

**Widening the bounds (route 3).** Rejected as the fix. The bounds that remain
are pure liveness guards (15 s for "the page reached the gate", 15 s for "the
element arrived after the gate opened"): they can only fail if something is
actually broken, and they decide nothing.

## The rule this leaves

An upper bound on the host's clock is fine — "this must end, not hang". What
is never safe is asserting that **the host beat something the page does on its
own clock**: under parallel-agent load the host stretches 20–50× and the page
does not. Where a test needs the page's next step not to have happened yet,
gate it (`FixtureGate`) instead of racing it.
