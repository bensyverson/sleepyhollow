# Backlog

Work consciously decided against, so it doesn't vanish into silence. One
dated H2 per item: what it is, why it's parked, and what would un-park it.
Nothing here is scheduled or blocking; active work lives in `job`.

## 2026-08-20 — Reproducible-builds-style PDF metadata

`sleepy pdf`'s output differs between identical runs in exactly the
trailer's `/CreationDate`, `/ModDate` and `/ID` (measured: 66 bytes of
24,286 on `static.html`); content bytes, page count, text and media box
are identical. The reproducible-builds convention (fixed epoch stamps)
would make the whole file byte-stable, which lets agents diff PDFs
byte-wise for change detection. Parked because the obvious fix — a
PDFKit re-serialization pass — may regenerate `/ID` nondeterministically
itself, so it needs a spike, and the golden suite already pins byte
length, page count, page text and media box. Un-parked by: an agent flow
that needs byte-wise PDF comparison, or a spike showing PDFKit (or a
hand-patch of the trailer) holds the bytes still.

## 2026-08-20 — A `.docc` catalog for the module landing page

The DocC pass reached zero warnings, but the `SleepyHollow` module's own
landing page is DocC's synthesized stub — a curated overview needs a
`.docc` catalog (an articles bundle), which is new documentation surface
rather than doc comments. Parked as a nicety: the README and the vision
doc currently carry the overview role. Un-parked by: publishing the DocC
archive anywhere public-facing (a hosted reference makes the landing page
the front door).

## 2026-08-20 — Auto-wait for the session act verbs

The one-shot step runner auto-waits for each step's selector before acting
(the wave-2 wait-vs-steps ruling; see the correction block in the vision
doc's "One-shot flows compose by flags"). The session verbs `sleepy
click|fill|submit` deliberately do **not**: they answer immediately, and a
missing selector is a clean negative (exit 1). Parked because auto-waiting
there means threading a wait budget through the operations themselves
(they ship over the session socket and must carry their own deadline —
a live session has no load in flight to borrow one from), which is real
API surface for a need nobody has demonstrated yet. Un-parked by: an agent
flow that genuinely needs to act on a late element in a live session and
can't express it with `sleepy eval` polling first.

## 2026-08-28 — Time-series capture (`shot --every <ms> --for <ms>`)

A filmstrip of loading states, skeletons and transitions, delivered as
frames plus a `--sheet` mosaic. Parked because `requestAnimationFrame`
never fires in a windowless `WKWebView` (`gotchas.md`), so a headless
filmstrip may photograph frozen motion and report a state that never
existed. Sessions already let an agent loop shots at ~55 ms each.
Un-parked by: the off-screen window host landing and its spike showing
rAF and CSS transitions advance in the hosted view
(`2026-08-28-agent-feedback-synthesis.md`).

## 2026-08-28 — Layout-shift assertion

`query` geometry diffed between two moments, as an exit-code verdict.
Parked because two `query` calls answer it today. Un-parked by: a page
whose shift an agent could not catch that way.

## 2026-08-28 — Further assertion verbs

Tap-target size, truncated text, webfont fallback, unlabeled controls,
overlapping elements. Each is a plausible `window.sleepy` helper plus a
thin verb. Parked one at a time; un-parked individually by a field report
of an agent hand-rolling that check and getting it wrong.

## 2026-08-28 — Element-relative `--rect`

"200 px below this element" without arithmetic. Parked: document-space
`--rect` plus `query` geometry covers it. Un-parked by an agent flow that
needs it more than once.
