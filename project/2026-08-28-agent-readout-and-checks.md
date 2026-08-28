# Agent readout and page checks: `--max-size`, `--tile`, `--rect`, `--scale`, and two assertion verbs

**Date:** 2026-08-28. Written by Claude (Fable) with Ben, converging two field reports from the same afternoon — the main-thread agent producing a client report page, and the subagent revising it (27 `sleepy` calls: `eval` ×10, `shot` ×15, `console` ×2, `help` ×1). Every ask below traces to a concrete cost in those sessions. The `--scale` half is specified in `2026-08-28-shot-scale-flag.md`; this note composes it with the rest.

## The problem in one paragraph

An agent reads images through a fixed pixel budget — roughly 2,000px on the long side before downsampling makes 16px text illegible. `sleepy shot --full-page` of a 1280×12,982 document therefore comes back unreadable, and the agent hand-slices it with PIL into ~2,600px strips (six image reads per review, three reviews per page). Element shots at 1:1 sit at the legibility floor for 10px labels, which produced one false positive (a white glyph read as a hole in a ribbon; two calls to disprove). And the two questions every layout change raises — *does anything spill the viewport?* and *is every label readable against what it sits on?* — are answered today by hand-rolled `eval` loops and Python luminance math, the naive versions of which are wrong.

## Recommendation, in priority order

### 1. `shot --max-size <px>` — the zoomed-out overview

Longest side of the **output PNG** capped at `<px>`; the capture is downsampled after rendering. Nothing about the page changes — viewport, layout, breakpoints all as `--size` says. This is "let me see the whole thing first." `--max-size 2000 --full-page` of the report gives one legible-at-a-glance 197×2000 overview; the agent then picks a region and zooms.

### 2. `shot --tile [<css-px>]` — strips at readable scale

Cuts a capture into horizontal strips of `<css-px>` CSS pixels tall, writing `<out>-01.png`, `<out>-02.png` … and a JSON index on stdout: `{ "tiles": [ { "file", "y", "height", "scale" } ] }` with `y`/`height` in CSS px so the agent can name a region for a follow-up `--rect`. Default overlap **40 CSS px** so a line cut at a boundary reads whole in one strip. Bare `--tile` (no number) takes its height from `--max-size` when given, else from the viewport height.

**Composition** (the ordering that keeps the flags from fighting):

1. render at `--scale` (device pixels per CSS px; `2026-08-28-shot-scale-flag.md`)
2. crop to `--element` / `--rect`, or the full page
3. cut into `--tile` strips, measured in CSS px
4. fit each output image to `--max-size`

So `--max-size 2000 --tile` = strips 2,000 CSS px tall, each output ≤ 2,000 px on its long side (at 1280 wide that is 1:1 — exactly the hand-made PIL strips). `--max-size 2000 --tile 1000` = 1,000-px strips, each ≤ 2,000 px, so at `--scale 2` a 1280×1000 strip renders 2560×2000 and is fitted to 2000×1563 — denser than 1:1, still inside the budget. `--tile` without `--max-size` at `--scale 2` emits full-density strips for a reader with a bigger budget. No flag changes what another means; each is one stage.

### 3. `shot --rect x,y,w,h` — a region without a selector

CSS-px rectangle in document coordinates (full-page space, so a `--tile` index entry can be pasted straight back). Today the only regions are "an element" or "everything"; the report's three hero crops (e.g. y 850–2135 of a 6,000-px render) all went through PIL because there is no selector for "the top of the form." Composes with `--scale` and `--max-size` like `--element` does.

### 4. `sleepy contrast <url> [--min wcag-aa | wcag-aaa | <ratio>] [--selector <sel>]` — a legibility assertion

For every rendered text node (and SVG `<text>`), compute the WCAG contrast ratio between its computed `color` and its **effective** background, and list the failures. Exit 0 clean, 1 with failures (JSON: selector path, text excerpt, foreground, background, ratio, threshold, whether the text counts as "large").

- `--min` takes a named constant or a bare ratio: `wcag-aa` = 4.5 (3.0 for large text — ≥ 24px, or ≥ 18.66px bold), `wcag-aaa` = 7.0 (4.5 large), or `1.7` etc. Default `wcag-aa`. A bare number applies to all text regardless of size; say so in help.
- **Effective background is the hard part and the reason this belongs in the tool.** Walk ancestors compositing `background-color` alpha over the next opaque layer; stop at the first `background-image`/gradient and report `background: "unknown (image)"` rather than a number — an honest gap beats a wrong ratio. For SVG text, find the shape(s) whose geometry contains the text's bounding box (paths, rects, circles — `isPointInFill` on the four corners and the center is enough) and use the topmost `fill`, compositing `fill-opacity`. That case had no computed-style answer at all and cost five hand calculations in Python.
- `--selector` scopes the walk (one figure, one section). Text with `opacity: 0`, `visibility: hidden`, `display: none`, or zero rendered area is skipped and counted in a `skipped` field.

Named constants over raw ratios wherever possible — an agent will otherwise pass `4.5` and never learn that large text has a different bar.

### 5. `sleepy overflow <url> [--size WxH]` — the spill assertion done right

List every element whose bounding rect exceeds the viewport horizontally, **excluding descendants of an ancestor that scrolls** (`overflow-x: auto | scroll` on any ancestor, which is the legitimate "wide table scrolls inside its own container" case). Exit 1 if any. This is the loop every agent hand-rolls — and the obvious shortcut, `scrollWidth === clientWidth`, silently passes on any page with `body { overflow-x: hidden }` (the subagent found this the hard way and had to run both). A verb that encodes the exclusion is the difference between a check and a lie. Accepts several `--size` values in one call (`--size 390x800 --size 1280x900`) since the question is always "at every breakpoint."

> **Corrected in place, 2026-08-28, while building the verb.** `body { overflow-x: hidden }` alone does *not* silence the shortcut in WebKit: measured against `Tests/TestSupport/Fixtures/overflow-spill.html` at 1280px, `document.documentElement.scrollWidth` still read 2505 with `overflow-x: hidden` on `body` only, and 1280 once `html` carried it too. It takes the root scroller — `html`, or the `html, body` pair people actually write — for the naive check to report a clean page. The recommendation stands unchanged; only the example that motivates it needed the extra selector. `sleepy overflow` reports `documentWidth` (the root scroller's own number) beside `viewportWidth` for exactly this reason, and never decides from it.

### 6. Three small fixes, each a lost round trip

- **`eval --js` with a bare expression returns `null`, exit 0.** Either wrap a bare expression in `return (…)` when the script contains no `return` statement and no `;`, or refuse with exit 2 and the help text's "async function body" line. Never a null that looks like an answer.
- **`shot --out` into a missing directory reports "The file 'x.png' doesn't exist."** Create the parent (like `mkdir -p`) or name the directory in the error. The agent lost a cycle to `$TMPDIR` differing between sandboxed and unsandboxed shells, which made this message doubly misleading.
- **A sandbox denial surfaces as "did not finish loading within 30.0s."** WebKit fails to obtain a `launchservicesd` extension under the agent sandbox and the timeout is the only thing that reaches the agent's eye; the cause is two stderr lines above. When the load never starts (no first byte, no navigation event) and the process-launch error is present, say "WebKit could not start under this sandbox" with exit 4, not the timeout text.

## What was consciously left out

- **A grid/ruler overlay** (burned-in coordinates so an agent can name a region after one overview). Useful, but it is an image operation, not a rendering one; it belongs in `pixelpeeper` (`peep grid`, `peep crop`), which can also serve images sleepy didn't make. Sleepy's `--tile` JSON index covers the same need for pages.

  > **Overruled (2026-08-28, `2026-08-28-agent-feedback-synthesis.md`).** A grid labeled in *document CSS px* is page knowledge, not an image operation — it turns an overview into an addressing surface for `--rect` and `click --at`. `shot --grid` lands in Sleepy; PixelPeeper may still grow a pixel-space grid for foreign images.
- **A visual diff against a previous capture** — `pixelpeeper compare`, ideally per tile ("draft1 vs final differ in strips 2 and 5"), is the right home.
- **APCA** as a contrast model. WCAG 2 ratios are what the design rules and the auditors quote; add APCA behind a name later if asked.

## Acceptance, in the order an agent would run them

1. `sleepy shot <report> --full-page --max-size 2000 --out over.png` → one PNG, longest side 2000.
2. `… --full-page --max-size 2000 --tile --out strips.png` → `strips-01.png…`, JSON index with CSS-px `y` ranges; adjacent tiles share 40 px.
3. `… --rect 0,850,1280,1285 --scale 2 --out hero.png` → 2560×2570, layout identical to the 1× page at 1280.
4. `sleepy contrast <report> --min wcag-aa` → exits 1 naming the one SVG sub-label at 2.9:1 that the subagent found by eye; after the fix, exit 0.
5. `sleepy overflow <report> --size 390x800 --size 1280x900` → exit 0 with the flow figure's scroll container listed under `scrollContainers`, not `violations`; add a 1,000-px unbreakable string to a paragraph and it exits 1 naming that paragraph.
6. `sleepy eval <url> --js 'document.title'` → the title, or exit 2 — never `null`.
