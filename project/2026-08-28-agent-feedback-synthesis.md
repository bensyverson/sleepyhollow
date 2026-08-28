# Reading between the lines of the first agent field reports

**Date:** 2026-08-28. Ben Syverson & Claude (Fable) · status: **agreed direction**. Converges three field reports — `2026-08-24-first-agent-user-feedback.md`, `2026-08-28-shot-scale-flag.md`, `2026-08-28-agent-readout-and-checks.md` — plus the design conversation of this date. The reports list fixes; this note names the needs underneath them, rules on the open questions, and ends with the `job import` block that schedules the work. Where this note overrules an earlier recommendation it says so in place.

## Five themes underneath the asks

1. **The agent's bottleneck is its own eyes, not the browser.** `--max-pixels`, `--slices`, `--max-size`, `--tile`, `--rect`, `--scale` are six spellings of one need: pixels that fit a ~2,000px vision budget at legible density. Sleepy is already fast (a session element shot measured 0.055s); the last mile is that it does not know its reader is a vision model. Every field session ended in `sips` or PIL.
2. **Agents want assertions, not readouts — and their hand-rolled ones are wrong.** `scrollWidth === clientWidth` passes under `body { overflow-x: hidden }`; luminance math without effective-background compositing gives a confident wrong ratio. `query --exists`, `find` and `eval`-false-exits-1 already establish that the exit code *is* the verdict; every check an agent hand-rolls and gets subtly wrong is a verb candidate.
3. **A plausible wrong answer is the worst failure class.** Isolated-world `eval` reporting `undefined` for a real method; a blank PNG with exit 0; `pdf` claiming pagination; `null` from a bare expression; a sandbox denial dressed as a timeout. Each cost a debugging spiral, not a round trip. This becomes a rule beside "everything terminates" (see Rulings).
4. **Agents re-guess every time, so the first guess must land.** Flag consistency, the suggester, `mkdir -p`, aliases, "3 of 19 verbs used". The recipes doc is right, and one step further: the expensive misses were on *successful* calls, so the tool should nudge on success too ("tip: `--max-size 2000` fits this to a vision model"), not only on failure.
5. **There is a second persona.** The 2026-08-24 report is *an agent verifying a page*; the 2026-08-28 reports are *an agent producing a deliverable for a human on a Retina Mac*. `--scale`, real `pdf`, hero crops are not testing needs. Naming the persona changes what "done" means for `shot` and `pdf`.

## Rulings

### Sleepy vs PixelPeeper

One rule: **anything that needs the page or page coordinates is Sleepy; anything that works on an arbitrary PNG is PixelPeeper.** Sleepy owns render and every output transform expressed in CSS document px — `--rect`, `--tile` (with its CSS-px index), `--max-size`, `--scale`, `--grid`, `--sheet`. PixelPeeper owns compare/MAE, sample, and growth in pixel space — crop, resize, contact sheets, diff visualization, its own grid — for images Sleepy didn't make. Small duplication (a max-side fit in both) is fine; each needs it in its own coordinate system.

The two stay separate binaries. PixelPeeper's value is that it serves images from anywhere; a browser that owns image tooling is the monolith the principles argue against. The vision doc's order stands: chain first, `shot --diff <baseline>` with PixelPeeper as a library once the seam is proven. "Sleepy users don't know PixelPeeper exists" is a documentation problem: the primer, recipes and success nudges **name `peep`** ("compare against a baseline → `peep compare`"), and both READMEs cross-link.

> **Overrules, in place:** `2026-08-28-agent-readout-and-checks.md` § "What was consciously left out" filed the grid overlay under PixelPeeper as "an image operation, not a rendering one." That was wrong by this note's rule: a grid labeled in *document CSS px* is page knowledge — it makes an overview an addressing surface (one `--max-size 2000 --grid 100` shot, then `--rect` or `click --at` straight off the labels). The grid lands in Sleepy; PixelPeeper may still grow a pixel-space grid for foreign images.

### `eval` runs in the page world by default

WebKit content worlds share the DOM but not JavaScript. An isolated world sees the same nodes, attributes and shadow roots but has its own global object, so the page's globals, its classes and — the trap — the prototypes it installed on upgraded custom elements are invisible, while `customElements.get()` (a DOM-side registry) still answers. The vision doc chose isolated-by-default so Sleepy's *own* instrumentation can never collide with page JS, and promised a `--page-world` opt-in that never shipped.

Ruling: that reasoning stays for Sleepy's internal scripts (the `ax` computation stays isolated; the wire recorder must be page-world regardless). For the **user's `eval`**, the agent's question is almost always about the page's own state, and isolated silently answers a different question — the most expensive spiral in the field reports. So `eval` runs in the **page world by default**; `--world isolated` opts out; help states the difference and what does not cross. Cost accepted: page code can observe or shadow what `eval` does, but an agent running JS is already a participant, not a witness. Sleepy's injected helper library (below) lives in the page world too, under one namespace.

> **Amends the vision doc § 3 "Isolated world by default":** the default there now applies to Sleepy's internal scripts only; user `eval` defaults to the page world for the reason above. The flag is `--world page|isolated`, not `--page-world`.

### Never a plausible wrong answer

Added beside "everything terminates": when the tool cannot give the true answer it says so — `"background": "unknown (image)"` over a wrong contrast ratio, exit 4 over a silently upscaled "2×" PNG, a stderr note over an empty element shot, "WebKit could not start under this sandbox" over a timeout. An answer that could be mistaken for truth is worse than an error.

### The off-screen window host is one piece of infrastructure, built first

`pdf` pagination (`NSPrintOperation` needs a windowed view), `--scale` density forcing (a window with an explicit backing scale), and the time-series spike (rAF never fires in a windowless view — `gotchas.md` — so animations may be frozen) all need a `WKWebView` parked in an off-screen `NSWindow` at (−20000, −20000) with activation policy `.prohibited`. Build it once, behind the existing host, and prove it opens nothing visible.

## Designs settled in conversation

**Readout pipeline.** Stages in order, each one flag, none changing what another means: render at `--scale` → crop to `--element` / `--rect` / full page → cut into `--tile` strips (CSS px, 40px overlap) → fit each image to `--max-size` → draw `--grid`. `--rect` is in CSS document px so a `--tile` index entry pastes straight back.

**Grid.** Labels are on the image — a vision model reads landmarks, it does not count pixels, and an off-by-one at 100px is a wrong `--rect`. Form: rulers in a padded gutter (top and left, ~24px, labeled in CSS document px) plus faint lines across the image at each major step so a mid-image element can be triangulated. `--grid rulers` drops the lines when the same image will be judged for contrast or alignment. Drawn after the `--max-size` fit so labels stay legible; the gutter may exceed the cap by its own width rather than shrinking the page — help says so.

**Repeatable render axes.** `--size`, `--scale` and `--theme` repeat (ArgumentParser idiom: repeat the flag; a space-separated list fights the positional URL), with a width-only `--size 480` shorthand since breakpoints are widths. Cross product; size and theme are separate renders, scale is raster only. Filenames suffix only the axes that vary, in fixed order — `header-480@2x-dark.png`, `header-480.png` when only size varies — and a JSON index on stdout maps file → parameters so nothing parses names.

**Contact sheet (`--sheet`).** "N captures → one image": frames (time series) or breakpoints (repeated `--size`/`--theme`) laid out in a `cols × rows` mosaic sized to the budget, each cell downscaled, its label (timestamp or parameters) burned in a gutter, plus the index of the individual full-size files. The sheet answers *when* or *where* something changed; detail comes from the frame or a `--rect`. Not for `--tile`: a tall page shrunk into a mosaic scrambles reading order.

**In-world helpers.** `contrast` and `overflow` are implemented as `window.sleepy.contrast()` / `window.sleepy.overflow()` in an injected helper library; the verbs are thin callers. One implementation, no drift, testable against fixtures as JS, and reachable from `eval` so agents compose them. Later helpers (`sleepy.rect(sel)`, `sleepy.effectiveBackground(el)`, `sleepy.layoutShift(a, b)`) join the namespace.

**`sleepy doctor`.** Three of the worst failures were environment, not page: the helper resolved against cwd, a sandbox denial as a timeout, `$TMPDIR` drift. One verb checks binary resolution, WebKit launch under the current sandbox, the sessions directory and the temp directory, with a teaching error each.

**JS-only use.** Already exists — `eval --js` returns JSON and was the workhorse (10 of 27 calls). The feedback shows it is painful, not missing: fix the world default, the bare-expression `null`, add `--file`/stdin for multi-line scripts, and document `about:blank` as "no page". No JavaScriptCore path: `jsc` and `node` exist, and a page-less eval has no WebKit reason to be here.

> **Settled while building, 2026-08-28 (leaf BXNVm).** This note left `click --at` as "viewport or document CSS px". It is **document CSS px** — one space, no flag, matching `--rect` and the `--grid` labels this note already promised agents would click straight off. The verb scrolls the point into view itself and hit-tests at the viewport-relative position, so the caller never converts; a point past the end of the document is a clean negative rather than a click at the clamped scroll offset. Caveat found in passing and *not* fixed here: `query` reports element geometry relative to the **viewport**, so its numbers only equal document space on an unscrolled page — the two documented conventions disagree, and something should reconcile them.

> **Reconciled, 2026-08-28 (leaf Az3RQ).** That caveat is closed: `query` now reports `getBoundingClientRect()` **plus `window.scrollX`/`scrollY`**, so `ElementFact.Geometry` is document CSS px like everything else, and a rect from `query` pastes into `shot --rect` and its centre into `click --at` at any scroll position. `shot` also scrolls the page to its origin before measuring a non-viewport region, which it previously only got by accident: growing the frame to the document height clamps `scrollY` to 0 but leaves `scrollX` alone, so `--rect` on a horizontally scrolled page cropped the wrong columns. To recover viewport coordinates, subtract the offset `sleepy eval <page> 'return [window.scrollX, window.scrollY]'` reports.

## Parked, with un-park conditions

Recorded in `backlog.md` as well:

- **Time series (`shot --every <ms> --for <ms>`)** — parked until the off-screen window host lands and a spike shows CSS animations and rAF advance in it; until then a filmstrip of a headless view may photograph frozen motion. Sessions already allow an agent to loop shots at ~55ms each.
- **Layout-shift assertion** (`query` geometry diffed between two moments) — un-parked by a page whose shift an agent could not catch with two `query` calls.
- **More assertion verbs** (tap-target size, truncated text, webfont fallback, unlabeled controls, overlap) — un-parked one at a time by a field report of an agent hand-rolling that check wrong.
- **`--rect` element-relative form** — un-parked by an agent needing "200px below this element" without arithmetic.

## Priority

1. Bugs that produce plausible-wrong answers — cheap, and nothing else is trustworthy until they land.
2. Off-screen window host.
3. Readout pipeline: `--scale`, `--max-size`, `--tile`, `--rect`, `--grid`, repeatable axes, `--sheet`.
4. Assertion verbs `contrast`, `overflow` on the helper library; `click --at`.
5. Teaching layer: recipes, success nudges naming `peep`, `doctor`, vision-doc amendments.

---

```yaml
tasks:
  - title: Plausible-wrong-answer bug sweep
    desc: >
      Seven field bugs whose common property is an answer that looks true. Each starts with
      a regression test. See 2026-08-28-agent-feedback-synthesis.md § Rulings.
    labels: [bug, epic]
    children:
      - title: Session helper resolves the sleepy binary against cwd
        desc: >
          `sleepy open` via PATH from another directory fails "Couldn't start a session helper
          from '<cwd>/sleepy'". Resolve the helper from the executable's own resolved path,
          not argv[0]. Repro: install to ~/.swiftpm/bin, cd elsewhere, sleepy open.
        labels: [bug, sessions]
        criteria:
          - sleepy open works as a bare PATH command from an unrelated cwd
          - a regression test covers PATH invocation from a foreign cwd
      - title: eval runs in the page world by default, with --world
        desc: >
          Ruling in the synthesis doc: user eval defaults to the page world; `--world
          page|isolated` opts out; help states what does not cross an isolated world
          (page globals, classes, upgraded custom-element prototypes) and that
          customElements.get() still answers. Sleepy's internal scripts keep their worlds.
          Amend the vision doc § 3 in place.
        labels: [bug, eval, docs]
        criteria:
          - "eval --js 'typeof el.someUpgradedMethod' returns function for an upgraded custom element by default"
          - "--world isolated restores today's behaviour and eval --help states the difference"
          - vision doc § 3 carries the amendment block
      - title: eval refuses a bare expression instead of returning null
        desc: >
          `eval --js 'document.title'` returns null, exit 0. Wrap a bare expression in
          `return (...)` when the script has no return statement and no `;`; otherwise
          exit 2 with the "async function body" help line. Also add --file <path> (and
          `-` for stdin) for multi-line scripts.
        labels: [bug, eval]
        criteria:
          - "eval --js 'document.title' prints the title"
          - a script that cannot be wrapped exits 2 naming the fix
          - --file reads a multi-line script from a path or stdin
      - title: Make pdf actually paginate with print media
        desc: >
          WKWebView.pdf renders a screen-media snapshot on one long page. Use NSPrintOperation
          on the off-screen window host: drive it with runModal(for:delegate:didRun:contextInfo:)
          (synchronous .run() yields infinite empty pages). Margins come from NSPrintInfo, not
          @page - decide and document which wins. Depends on the off-screen window host.
        labels: [bug, pdf]
        criteria:
          - pdf of a page with @media print rules emits multiple Letter/A4 pages with no-print elements absent
          - rendering opens no visible window and never activates the app
      - title: Warn on zero-area element shots
        desc: >
          An --element shot whose match has zero rendered area writes a blank PNG with exit 0.
          Emit a stderr note naming the condition and exit 1 (clean negative: nothing to see).
        labels: [bug, shot]
        criteria:
          - a zero-area --element shot exits 1 with a stderr note naming the element and its rect
      - title: Suggester proposes flags the verb does not have
        desc: >
          `sleepy shot --full` suggests '--fill', a different subcommand. Constrain did-you-mean
          candidates to the invoked verb's flags. Alias -o for --out and --full for --full-page.
        labels: [bug, cli]
        criteria:
          - unknown-option suggestions only name flags valid on the invoked verb
          - "-o and --full are accepted aliases on shot"
      - title: Sandbox denial reports itself, not a timeout
        desc: >
          When WebKit cannot obtain its launchservicesd extension the load never starts and the
          agent sees "did not finish loading within 30.0s". When no navigation ever began and the
          process-launch error is present on stderr, exit 4 with "WebKit could not start under
          this sandbox" and the next move.
        labels: [bug, cli]
        criteria:
          - a load that never starts under a sandbox denial exits 4 with the sandbox message, not exit 3
      - title: shot --out creates missing parent directories
        desc: >
          --out into a missing directory reports "The file 'x.png' doesn't exist." Create the
          parent like mkdir -p, or name the directory in the error.
        labels: [bug, shot]
        criteria:
          - --out into a missing directory succeeds and creates it
  - title: Off-screen window host
    desc: >
      A WKWebView hosted in an NSWindow parked at (-20000,-20000) with activation policy
      .prohibited, behind the existing page host. Serves pdf pagination, --scale density
      forcing, and the time-series spike. Must prove it opens nothing visible and never
      activates the app; measure whether requestAnimationFrame and CSS animations advance in
      it and record the finding in a dated doc (and correct gotchas.md if they do).
    labels: [infra, shot, pdf]
    criteria:
      - a test asserts no window is visible and the app is never activated during a render
      - a dated finding records whether rAF and CSS transitions advance in the hosted view
  - title: Readout pipeline for shot
    desc: >
      Stages in order, each one flag: render at --scale, crop to --element/--rect/full page,
      cut into --tile strips, fit to --max-size, draw --grid. Design in
      2026-08-28-agent-feedback-synthesis.md § Designs; --scale in 2026-08-28-shot-scale-flag.md;
      --max-size/--tile/--rect in 2026-08-28-agent-readout-and-checks.md.
    labels: [feature, shot, epic]
    children:
      - title: shot --scale
        desc: >
          Device pixels per CSS point of the PNG: 1 (default), 2, 3. Layout, breakpoints and
          --size unchanged. Force the source density via the off-screen window host; if the
          host cannot render at that density, exit 4 - never upsample silently. PNG carries the
          matching DPI. Depends on the off-screen window host.
        labels: [feature, shot]
        criteria:
          - "--size 1280x800 --scale 2 yields 2560x1600 that halves to a.png within antialiasing noise"
          - a media query at 1000 points renders the same breakpoint at scale 1 and 2
          - --element and --full-page rects at scale 2 are exactly 2x the scale-1 rects
      - title: shot --max-size
        desc: Longest side of the output PNG capped at <px>; downsampled after rendering; page unchanged.
        labels: [feature, shot]
        criteria:
          - "--full-page --max-size 2000 of a 1280x12982 page yields one PNG with longest side 2000"
      - title: shot --rect
        desc: >
          x,y,w,h in CSS document px (full-page space). Composes with --scale and --max-size
          like --element. A --tile index entry pastes straight back.
        labels: [feature, shot]
        criteria:
          - "--rect 0,850,1280,1285 --scale 2 yields 2560x2570 with layout identical to the 1x page"
      - title: shot --tile
        desc: >
          Horizontal strips of <css-px> height (default from --max-size, else viewport height),
          40 CSS px overlap, written as <out>-01.png ... with a JSON index on stdout
          { tiles: [ { file, y, height, scale } ] } in CSS px.
        labels: [feature, shot]
        criteria:
          - "--full-page --max-size 2000 --tile writes strips whose adjacent y ranges share 40 px"
          - the index's y/height values are CSS px usable as --rect input
      - title: shot --grid
        desc: >
          Rulers in a padded gutter (top and left, ~24px, labeled in CSS document px) plus faint
          lines at each major step; `--grid rulers` drops the lines. Drawn after the --max-size
          fit; the gutter may exceed the cap by its own width, and help says so. Default step
          100 CSS px.
        labels: [feature, shot]
        criteria:
          - labels read in CSS document px after --max-size and --rect and --scale
          - "--grid rulers leaves the page pixels byte-identical to the ungridded capture"
      - title: Repeatable --size, --scale and --theme with an index
        desc: >
          Repeat-the-flag form; width-only --size 480 shorthand. Cross product; filenames suffix
          only the axes that vary, in the order size, scale, theme (header-480@2x-dark.png);
          a JSON index on stdout maps file to parameters.
        labels: [feature, shot]
        criteria:
          - "--size 480 --size 1280 --theme light --theme dark writes four files and one index"
          - a single-valued axis adds no suffix
      - title: shot --sheet
        desc: >
          N captures to one image: repeated sizes/themes (and later frames) in a cols x rows
          mosaic sized to --max-size, each cell labeled in a gutter, plus the index of the
          full-size files. Refused with --tile.
        labels: [feature, shot]
        criteria:
          - "--size 390 --size 1280 --sheet writes one mosaic and the two full-size files"
  - title: In-world helper library and assertion verbs
    desc: >
      A `window.sleepy` helper library injected into the page world, with contrast and
      overflow implemented there and exposed as verbs. Specs in
      2026-08-28-agent-readout-and-checks.md §§ 4-5.
    labels: [feature, epic]
    children:
      - title: window.sleepy helper library
        desc: >
          Namespaced helpers injected at document end in the page world, reachable from eval:
          sleepy.contrast(opts), sleepy.overflow(opts), sleepy.rect(sel),
          sleepy.effectiveBackground(el). Tested as JS against fixtures.
        labels: [feature, eval]
        criteria:
          - "eval --js 'return sleepy.rect(\"h1\")' returns the element's CSS-px rect"
      - title: sleepy contrast
        desc: >
          WCAG ratio of every rendered text node and SVG text against its effective background;
          --min wcag-aa (default) | wcag-aaa | <ratio>; --selector scopes. Effective background
          walks ancestors compositing alpha, reports "unknown (image)" at the first
          background-image; SVG text uses the topmost containing shape's fill. Exit 1 on failures.
        labels: [feature, verb]
        criteria:
          - exits 1 naming an SVG sub-label at 2.9:1 and exit 0 after the fix
          - text over a background-image reports unknown rather than a number
      - title: sleepy overflow
        desc: >
          Every element whose rect exceeds the viewport horizontally, excluding descendants of a
          scrolling ancestor (listed under scrollContainers). Repeatable --size. Exit 1 if any.
        labels: [feature, verb]
        criteria:
          - a scroll container's wide table lands under scrollContainers, not violations
          - a 1000-px unbreakable string in a paragraph exits 1 naming the paragraph
      - title: click --at with a real hit test
        desc: >
          Coordinate click (viewport or document CSS px; element-relative later) using
          elementFromPoint through shadow roots, so a button rendered inside an open shadow root
          activates. Pairs with --grid for addressing.
        labels: [feature, interaction]
        criteria:
          - a click at grid-read coordinates activates a button inside an open shadow root, verified by page state
  - title: Teaching layer
    desc: Discoverability and environment diagnosis; the field reports' cheapest wins.
    labels: [docs, cli, epic]
    children:
      - title: Agent-facing recipes
        desc: >
          Goal-to-verb routing (prove no external requests -> wire; semantic check -> ax/query/
          find; drive an interaction -> open/click/shot --session; compare against a baseline ->
          peep compare) plus the sandbox note. Ship as `sleepy help recipes` and a doc.
        labels: [docs]
        criteria:
          - "`sleepy help recipes` lists goal -> verb pairs and names peep"
      - title: Success nudges
        desc: >
          One stderr tip on a successful call when a cheaper path exists: a --full-page over
          2000 px tall names --max-size/--tile; a shot without --out names peep compare for
          baselines. Never on --format json's stdout; silenced by --quiet.
        labels: [cli]
        criteria:
          - a 9000-px --full-page shot prints one tip naming --max-size and --tile
      - title: sleepy doctor
        desc: >
          Checks binary and helper resolution, WebKit launch under the current sandbox, the
          sessions directory, and the temp directory, with a teaching error for each.
        labels: [feature, verb]
        criteria:
          - under a sandbox that blocks WebKit, doctor exits 5 naming the sandbox and the next move
      - title: Unify element addressing across verbs
        desc: shot uses --element; click/fill use --selector. Pick --selector everywhere; accept --element as an alias.
        labels: [cli, consistency]
      - title: Vision-doc amendments and PixelPeeper cross-links
        desc: >
          Add the second persona (deliverables for humans) and "never a plausible wrong answer"
          to the vision doc as dated amendment blocks; cross-link PixelPeeper from the README and
          primer; record the parked items in backlog.md.
        labels: [docs]
```
