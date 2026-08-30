# A shot needs no settle after `document.fonts.ready`

**Date:** 2026-08-29. Measured by the `paint` agent (leaf Ea7ly) against
[2026-08-29-woodcase-harness-feedback.md](2026-08-29-woodcase-harness-feedback.md)
finding 11 — Woodcase sleeps a flat 150 ms after `document.fonts.ready`
before snapshotting, in case the repaint with the loaded webfont has not
landed. That is 1.75 s of an 8.1 s suite and a guess in both directions.

**Host:** MacBookAir10,1 (Apple silicon, 8 cores), macOS 26.5.2 (build
25F84), Swift 6.3.3, `arm64e-apple-macos14.0` test platform, one Retina
display.

## The headline

**The sleep is unnecessary. Outcome A.** `WKWebView.takeSnapshot` flushes the
layer tree before it rasterizes, so a capture taken on the host's very next
instruction after a page-side promise resolves already shows what that
promise announced. Across **108 samples** of the race in four host
configurations, a capture with **no** settle was **byte-for-byte identical**
to a capture of the same page 400 ms later — mean channel difference 0.0000,
every time, with not one non-zero reading.

Nothing was built. The deliverable is this document, two suites that pin it,
one DocC sentence each on `ShotOperation` and `PageHost`, and a corrected
recipes entry. `PageHost.awaitPaint(within:)` and `WaitCondition.painted` —
the outcome-B design in [the plan](2026-08-29-woodcase-harness-plan.md) —
were **not** built and should not be: a signal whose answer is always
"already true" is a round trip that teaches a caller to expect a race that
does not exist, and windowless it could not even be implemented (`rAF` never
fires there).

## What the finding is *not*

It is not "the offscreen window fixed it". The windowless host — every verb's
default, and the one Woodcase snapshots through — is the configuration that
matters, and it is correct on its own. `requestAnimationFrame` never fires
windowless ([2026-08-28-offscreen-window-host.md](2026-08-28-offscreen-window-host.md)),
so the outcome-B double-rAF signal would have *hung* there; that trap is
exactly what makes the negative result worth writing down.

It is also not a claim about arbitrary asynchrony. It says a *snapshot* is
ordered after everything the page had committed when the promise resolved. A
page that schedules its next visual change on a timer is a different
question, and `--wait-for` is the answer to that one.

## Method

The measurement has to answer one question — *would waiting have changed the
pixels?* — without ever asserting that the host beat the page, which is the
bet [2026-08-28-wait-test-timing.md](2026-08-28-wait-test-timing.md) says a
loaded Mac loses. So it compares the **immediate** capture against a
**settled** capture of the same page rather than against a golden image.
Equal means the wait would have bought nothing, and that is decidable at any
speed.

### The fixture font

A webfont only tests this if its glyphs are unmistakably not the fallback's.
`scripts/make-fixture-font.py` generates
`Tests/TestSupport/Fixtures/block-font.ttf` (1,160 bytes, fontTools 4.62.1):
every letter and digit maps to one filled rectangle, so five 160 px
characters render as five solid bars where the serif fallback draws
letterforms. Nothing licensed is vendored, and the fixture is reproducible
with `python3 scripts/make-fixture-font.py`. The `.ttf` is committed; the
tests never run the script.

Separation, as mean absolute per-channel difference over the whole 1280×800
viewport (`meanChannelDifference`, `Tests/SleepyHollowTests/CapturePixelSize.swift`):

| comparison | mean channel difference |
| --- | --- |
| fallback (Times) vs webfont (bars) | **9.9365** |
| immediate capture vs settled capture | **0.0000** |

Both numbers come from the same comparator on the same pairs of captures, so
the zero is a measurement and not an absence of one: the metric that reads
9.94 when the font changes reads exactly 0 when the only difference would
have been timing.

### The gate

`Tests/TestSupport/Fixtures/webfont.html` reaches the font only through a
`TestSupport.FixtureGate`, so the fallback baseline provably predates the
webfont — program order, not a wall-clock margin. Two swaps are exercised:

- **In-memory bytes.** `fetch` → `new FontFace(bytes)` → `face.load()` →
  `document.fonts.add` → `await document.fonts.ready`. The bytes are already
  in memory when the face is built, so the swap lands as close to the host's
  next instruction as a font swap can. If a snapshot could ever miss a
  repaint, it would miss this one.
- **CSS `@font-face` off the wire.** A `<style>` element appended after load,
  then `offsetWidth` read to force the style and layout pass that *starts*
  the font load, then `await document.fonts.ready`. Woodcase's own shape,
  with a real network round trip between the promise and its resolution.

Both run windowless (the default, and Woodcase's) and with
`PageHost.ensureOffscreenWindow()` parked.

### Capture path

`ShotOperation.render(on:)` — the `CGImage` path — is internal and the test
target imports the library rather than `@testable`, so each capture goes
through the public `host.execute(ShotOperation())` and comes back through
`ShotCapture(decoding:)`. That is a lossless PNG round trip on *both* sides
of every comparison, and the timing that matters — `takeSnapshot` itself — is
identical either way. When leaf `host-api` makes `render(on:)` public, the
`capture(on:)` helper in each suite can drop the decode.

## Figures

### One run

```sh
swift test --filter CapturePaintAfterFontsReadyTests --filter WaitFontsStatusTests
```

10 tests, 9 samples of the race, all green in 17.0 s:

| configuration | fallback vs settled | immediate vs settled |
| --- | --- | --- |
| windowless, in-memory bytes | 9.9365 | 0.0000 |
| offscreen window, in-memory bytes | 9.9365 | 0.0000 |
| windowless, CSS `@font-face` | 9.9365 | 0.0000 |
| offscreen window, CSS `@font-face` | 9.9365 | 0.0000 |
| 4 repeats of the tight race | 9.9365 each | 0.0000 each |
| `--wait-for js:fonts.status`, late stylesheet font | 9.9365 | 0.0000 |

### Under load

`scripts/paint-race-hunt.sh <iterations> <spinners>` runs the two suites N
times and tallies every failure. Twelve consecutive green runs, 54 samples
each half:

| command | load average at finish | runs | red | samples | non-zero |
| --- | --- | --- | --- | --- | --- |
| `scripts/paint-race-hunt.sh 6 12` | ~330 | 6 | 0 | 54 | 0 |
| `scripts/paint-race-hunt.sh 6 0` | 40 (1-min), 118 (5-min) | 6 | 0 | 54 | 0 |

The load was **ambient, not synthetic**: this Mac was carrying nine
concurrent agents from another project plus two sibling suites, which is why
the second row runs with no spinners at all. The first row adds twelve
`yes > /dev/null` spinners on top, the regime `gotchas.md` names; per the
coordinator's ruling on 2026-08-29 that is now the exception rather than the
script's default, because synthetic spinners on an already-saturated machine
deadlocked WebKit session tests machine-wide.

Also measured, and worth knowing before the next agent adds spinners: at a
load average near **400** WebKit is starved rather than stretched — a
filtered run made no progress for minutes, and `callAsyncJavaScript` and
`takeSnapshot` began failing outright with a bare `WKErrorDomain Code=1`
(four runs in five). `PageHost.evaluate` documents that it passes WebKit's
own error through, so that reaches the caller unshaped. It is an environment
limit rather than a paint result — **every** measurement those runs did
complete still read 0.0000 — and the suites now retry a whole measurement
once when the seam *throws* (`retryingStarvedWebKit`, never on a failed
expectation, since a paint regression is a pixel difference and pixel
differences do not throw).

**Two failures this hunt produced, neither a paint failure.** The default
30 s *load* budget blew on the repeat test's fifth host at 12 spinners, and a
test leaned on a shut `FixtureGate` for longer than its documented 30 s
`holdLimit`, so the safety net released the font and the fallback baseline
stopped being a fallback. Both were mine. Every host in both suites now loads
with `LoadOptions(budget: 300)` — a generous upper bound, not a margin — and
no test holds a gate shut any more: the font-less pages simply never request
a font, which has no clock in it at all.

### The red check

Pointing the in-memory swap at a missing URL (`/no-such-font.ttf`) fails four
of the six paint tests. The suite is not vacuous: a webfont that silently
never arrives is caught by the `fallback vs settled > 5` calibration in every
test, not only the one named for it.

## Reaching a webfont from the CLI — and why the obvious recipe is wrong

The library finding only helps an agent that can *get* to a loaded font. Three
facts came out of `Tests/SleepyHollowTests/WaitFontsStatusTests.swift`, and
each contradicts the obvious guess.

**1. The load event already waits for a stylesheet `@font-face`.** On
`webfont-late.html`, whose face is served through the fixture server's
`/delay/600/` route, `document.fonts.status` reads `"loaded"` at the load
event and the capture taken there differs from the fallback by 9.9365. So
`sleepy shot <url>` with no flag at all is already correct for the everyday
case, and Woodcase's `await document.fonts.ready` is belt-and-braces rather
than load-bearing.

**2. `document.fonts.status === 'loaded'` is true before a page requests a
font.** On the gated fixture with its gate shut — the font provably absent —
`status` is `"loaded"`, because nothing is loading. As a wait condition it is
therefore a *premature settle* for any font a page asks for after load, which
is precisely the plausible-wrong-answer shape this tool refuses.

**3. `document.fonts.check('160px SleepyBlock')` is true then too**, which is
the one that surprised me: a family with no matching `@font-face` resolves to
a fallback that is trivially available, so `check` returns `true`. Naming the
font does not save the predicate. Pinned twice — once by reading it directly,
once end to end by loading `webfont-later.html` (whose font request is gated
on a route the test does not register, so it never fires) with `--wait-for
"js:document.fonts.check('160px SleepyBlock')"`: the wait settles, the load
returns, and the capture is byte-identical to the fallback (0.0000).

The predicate *machinery* is fine: with the font genuinely in flight
(`webfont-late.html`), `--wait-for "js:document.fonts.status === 'loaded'"`
settles correctly and the capture that follows shows the webfont with nothing
in between (immediate vs settled 0.0000). It is the *condition* that is
unsafe, not the seam.

**So the recipe is a negative one**, and that is what
[recipes.md](recipes.md) and `sleepy recipes` now say: shoot the page, add no
sleep, and do not reach for a font predicate — for a font requested after
load, wait for what the page does instead.

## What this means for Woodcase

Delete the 150 ms sleep. `await document.fonts.ready` through
`host.evaluate`, then `ShotOperation` on the next line, is correct — and
1.75 s of the suite comes back without a single pixel changing. The
`fonts.ready` await itself can go too if every face comes from the page's own
stylesheet, though it costs nothing to keep.
