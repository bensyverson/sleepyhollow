# True-3D shots — plan

**Date:** 2026-11-06. Answers job issue `Ft2O4Q` (shots render CSS 3D transforms flat), and touches `ND4YmR` (animation time never advances), which needs the same live-rendering host.

## The problem

`sleepy shot` draws CSS 3D wrong, and still exits 0:

- `perspective` (on a parent, or `perspective()` in the element's own transform) loses its foreshortening. A tilted panel comes out as a squeezed rectangle, or as a sheared parallelogram whose edges stay parallel.
- `transform-style: preserve-3d` does no depth sorting. Faces paint in DOM order, and `translateZ` moves nothing.
- `backface-visibility: hidden` is ignored, so a card's back face paints mirrored over its front.

Measured 2026-11-06 with `sleepy shot <file-url> --size 700x320 --out t3d.png` (Homebrew `sleepy`, run outside the Claude Code sandbox) on a three-case fixture; `Ft2O4Q` has a second reproduction checked against headless Chrome.

**Geometry and pixels disagree.** On the same page, `getBoundingClientRect()` reports the true, perspective-correct box (x 22–208, y 1–252 CSS px) while the pixels sit at x 87–181, y 40–240. So `--selector` crops, `--rect` from page coordinates, and `contrast`/`overflow` verdicts can all be quietly wrong on a 3D element. That breaks the "never a plausible wrong answer" ruling (`2026-08-28-agent-feedback-synthesis.md` § Rulings).

## The cause, as far as we know

`shot` goes through `WKWebView.takeSnapshot` (`PageHost+Snapshot.swift`). On macOS that asks the web content process to repaint the page into a bitmap in software, flattening composited layers, rather than reading what the GPU compositor drew. Each layer's 4×4 transform is reduced to a 2D affine one, so the perspective terms and z are dropped. True 3D, with perspective divide and depth sorting, exists only in the compositor's Core Animation layer tree. This explains every symptom above, but is reasoned from WebKit's design, not traced in its source; the spike below should confirm or correct it. `pdf` prints through the same kind of software paint, so it presumably flattens too (not measured).

## Direction

A hybrid of detection and a compositor capture, in that order:

1. **Detect and say so.** Ship now. When the shot area contains an element whose flattened render differs from its true render, the capture says so (library: a fact on the result; CLI: a stderr note, exit 0). This is needed in every outcome: it is the honest fallback wherever a compositor capture can't run, and it may also be what picks the capture path.
2. **Measure a compositor capture before building one.** Host the page in a live `OffscreenWindow` and render its layer tree with `CARenderer` into an off-screen Metal texture, which composites in true 3D. Unknowns: does WebKit's UI-process layer tree render that way at all, do flat pages match `takeSnapshot`, what does it cost, and does `--full-page` survive (the compositor paints only around the viewport).
3. **Decide from the measurements**, then build. One preference recorded now: if the compositor path proves faithful and reliable, it should be the default for viewport, element and rect shots, rather than a fallback switched on by detection. Two renderers chosen by a heuristic mean that one tiny `translateZ` flips a whole shot's anti-aliasing and timing. Whichever renderer runs, the output names it.

### Detection, as built (2026-11-06, leaf `YnX53e`)

`window.sleepy.flattened3D` (`SleepyHelpers+Transforms.swift`) feeds `ShotOperation.Output.flattened3D`. The CLI prints a `Caveat` on stderr that `--quiet` does not silence. What decided the rules, measured with debug `sleepy shot` and `sleepy query` on scratch fixtures (load average about 30):

- A bare `rotateY(60deg)` with no perspective paints at exactly its `getBoundingClientRect()` box (x 75–175 both). The flat paint is orthographic, so this case is not flagged. Chrome was not available to cross-check.
- A parent's `perspective` reaches a child's transform, and nothing past a flat parent: a grandchild under a flat intermediate, positioned or static, measured orthographic. The ancestor walk continues only through `preserve-3d` parents.
- `transform-style` still computes to `preserve-3d` under `overflow: hidden`, `opacity < 1`, `filter`, `isolation: isolate` and `clip-path`, but WebKit's geometry is flat under each one. The detector checks the used value.
- `perspective(200px)` on its own sets only `m34` and paints the same as its box. The own-perspective test is `m14`/`m24`/`m44 ≠ 1`, which is where perspective ends up once something turns the plane or lifts it in z.
- `backface-visibility: hidden` on `rotateY(180deg)` is painted by the flat render. A hidden back face that faces the viewer paints either way, so only a face turned away is flagged.

The result names only the outermost flagged element: a three.js CSS3DRenderer scene is reported as its `preserve-3d` scene div, not once per panel.

### Rulings

- **Private WebKit SPI is acceptable for `shot`** (Ben, 2026-11-06: "This isn't going in the App Store"). This lifts the 2026-08-28 ruling that kept `Rendering.live` — `_setWindowOcclusionDetectionEnabled:` — off every shipping path; see the correction in `2026-08-28-offscreen-window-host.md`. SPI stays isolated, guarded by `responds(to:)`, and covered by a test that goes red if it stops working.
- **Screen capture through the window server (ScreenCaptureKit) is out.** It needs Screen Recording permission, which an agent running a CLI cannot grant.

### What waits on what

Detection and the spike touch disjoint files and run in parallel. The decision waits on the spike; the build waits on the decision. `ND4YmR`'s fix is a separate decision; the spike only measures whether live hosting fixes it, because the answer shapes the build.

**Added after import (2026-11-06):** native form controls render faint, in AppKit's inactive-window style, because the page's window is never key. The compositor path won't fix that: the controls are already painted inactive before compositing. The spike measures a separate lever, a key-window override on the host window (question 7 in `B3dXgQ`).

## Tasks

Imported 2026-11-06; the tracker holds the current version (`job ls`).

```yaml
tasks:
  - title: True-3D shots
    desc: |
      Plan: project/2026-11-06-true-3d-shots.md. Answers job issue Ft2O4Q; touches ND4YmR.
    labels: [epic, shot]
    children:
      - title: Detect flattened 3D in a shot and say so
        ref: detect
        labels: [feature, shot]
        desc: |
          Why: `shot` silently draws CSS 3D wrong. It drops perspective foreshortening, does no depth sorting under `preserve-3d`, and ignores `backface-visibility: hidden`, because `WKWebView.takeSnapshot` repaints in software with each layer's transform reduced to 2D affine. The pixels also disagree with `getBoundingClientRect()`, so crops and verdicts on a 3D element can be wrong. That is a plausible wrong answer, which the project rules out (2026-08-28-agent-feedback-synthesis.md § Rulings, "Never a plausible wrong answer": a stderr note over a misleading success). A compositor capture may fix the pixels later (sibling spike), but detection is needed in every outcome: it is the fallback wherever that capture can't run, and possibly what selects it.

          What: when a shot's area (viewport, `--selector` element, `--rect`, or full page) contains an element whose flattened render would differ from the true 3D render, the library result records it, and the CLI prints a stderr note saying the shot draws CSS 3D flat, naming how many elements and a short selector for the first few, and pointing at Chrome or Ft2O4Q. Exit code stays 0 and the PNG is still written. The note is a correctness caveat, not a tip, so `--quiet` does not silence it. A sweep or `--tile` reports once per render, not once per file.

          What counts: flag only what flattening actually changes. A 2D transform (rotate, scale, skew, translate) is not flagged. Neither is a bare 3D rotation with no perspective anywhere above it and no `preserve-3d`: an orthographic projection is exactly what the flattened paint draws, and Chrome agrees. Flag: a transform with perspective terms of its own (`perspective()`); a 3D transform under an ancestor whose `perspective` is not `none`; `transform-style: preserve-3d` with 3D-transformed descendants; `backface-visibility: hidden` on an element whose transform has a 3D component. Read it from computed style (`matrix3d` components, `perspective`, `transform-style`, `backface-visibility`), checking only elements that intersect the shot area.

          Seams: the detector is a page-side helper beside the existing ones (Sources/SleepyHollow/Operations/SleepyHelpers*.swift, which run in Sleepy's isolated world). Its result rides on `ShotCapture`/`ShotImage` or the operation result — the builder's call; keep the wire type one shared `Friendly` struct. The CLI note belongs in Sources/sleepy/ShotCommand*.swift, following how `LoadCommand` reports page errors on stderr. Update the `shot` help text, the DocC, and project/recipes.md if it routes 3D questions.

          Out of scope: fixing the pixels (the spike and the build leaf), `pdf` (not measured), `contrast`/`overflow` verdicts (a follow-up can reuse the detector; note it rather than build it).

          Risks: false positives make agents ignore the note, so the no-flag cases need tests as much as the flag cases. Cost on huge pages: the walk must stay cheap (one pass, intersecting elements only).
        criteria:
          - A fixture with perspective-on-parent, perspective() on the element, preserve-3d depth and backface-visibility cases each triggers the note (golden test on stderr, exit 0, PNG written)
          - 2D transforms and a bare orthographic rotateY without perspective trigger nothing (test)
          - An element shot or --rect that excludes the 3D element triggers nothing (test)
          - The library result exposes the flagged elements for an embedder (unit test), with DocC
          - shot --help and DocC describe the caveat; --quiet does not silence it (test)
      - title: "Spike: compositor capture of a live hosted page"
        ref: spike
        labels: [spike, shot]
        desc: |
          Why: the only fix for flattened 3D is to capture what the compositor draws rather than what the software repaint draws. Window-server capture (ScreenCaptureKit) is ruled out because it needs Screen Recording permission. The candidate is public API: host the page in a live `OffscreenWindow` (`Rendering.live`, which uses the private `_setWindowOcclusionDetectionEnabled:`; SPI is approved for shot as of 2026-11-06), then render the web view's Core Animation layer tree with `CARenderer` into an off-screen Metal texture. Note that `CALayer.render(in:)` flattens 3D too, so it is not a candidate. The build leaf waits on this answer.

          The question: can a live hosted `WKWebView`'s layer tree be rendered by `CARenderer` with true 3D (perspective foreshortening, preserve-3d depth sorting, backface culling), and at what cost? Answer each, with figures and the command that reproduces them:
          1. Does it work? Does WebKit's UI-process layer tree carry real transforms and IOSurface-backed contents that `CARenderer` composites, or is it hosted remotely (a `CALayerHost` or context the renderer can't see into)? If it fails, say exactly where, and name any other route you found (e.g. an SPI snapshot that reads the compositor).
          2. Fidelity: the 3D fixture (Ft2O4Q's reproduction plus project/2026-11-06-true-3d-shots.md's cases) compared against Chrome or the expected geometry; a flat page compared pixel-for-pixel with `takeSnapshot` at the same scale.
          3. What it misses: video, WebGL/canvas, backdrop-filter, fonts that load late, and content outside the compositor's tiled coverage, which decides whether `--full-page` and `--rect` far below the fold can use it (scroll and stitch?).
          4. Readiness: how to know the layer tree has committed the current frame before rendering, so the capture isn't a stale frame. This is the no-fixed-delays rule from project/2026-08-29-woodcase-harness-plan.md.
          5. Cost: time per capture and memory, quiet and under the ambient load (check the load average and record it; no `yes` spinners on a loaded machine; see project/gotchas.md).
          6. Live hosting side effects: does it also fix ND4YmR (rAF, CSS transitions, Web Animations; that issue has a fixture), and does `--wait-for idle` still settle on a page with an infinite rAF chain (project/2026-08-28-offscreen-window-host.md says it won't)?

          Where the answer goes: a findings doc, project/2026-11-06-compositor-capture.md, following the house style of the other findings docs (every figure names its tool and flags). The probe goes in scripts/ so it can be re-run. Its code is otherwise disposable; it does not need to be shippable or TDD'd.

          Out of scope: changing `shot`'s shipping behavior, or files the detection leaf owns (SleepyHelpers*, ShotCommand*).
        criteria:
          - project/2026-11-06-compositor-capture.md answers all six questions with reproducible figures, or says plainly which could not be answered and why
          - The probe is re-runnable from scripts/
          - The doc ends with a recommendation for the decision leaf
      - title: "Decide: which capture path shot uses"
        ref: decide
        labels: [decision, shot]
        blockedBy: [spike]
        desc: |
          The question, for Ben, once the spike lands: what does `shot` render with? The options visible now:
          (a) the compositor path everywhere it can run (viewport, element, rect), with `takeSnapshot` only for what the compositor can't cover; the plan doc's stated preference if fidelity and reliability hold;
          (b) the compositor path only when detection flags 3D;
          (c) a flag (`--renderer compositor`) and detection's note pointing at it;
          (d) park it in project/backlog.md with what would un-park it, keeping detection as the answer.
          Also: does live hosting become the default host for one-shot verbs (which would fix ND4YmR but changes `--wait-for idle`), or stay per-operation?
          Record the ruling in project/2026-11-06-true-3d-shots.md and detail the build leaf from it.
        criteria:
          - The ruling is recorded in project/2026-11-06-true-3d-shots.md and the build leaf's description is rewritten from it
      - title: Build the chosen capture path
        ref: build
        labels: [feature, shot]
        blockedBy: [decide]
        desc: |
          Placeholder; detail it from the decision leaf. It closes Ft2O4Q (and ND4YmR if the decision includes live hosting by default), and must include a regression test that renders the 3D fixture and checks foreshortening, depth order and backface culling in the pixels. It also fixes brc0C (a full-page shot on a windowed host is clipped by the OffscreenWindow) if the chosen path takes full-page shots on a windowed host.
        criteria:
          - A perspective-transformed element renders foreshortened, matching Chrome (pixel test)
          - backface-visibility hidden hides a face turned away from the viewer (pixel test)
          - Ft2O4Q is closed against this leaf's tests
```

## Ruling on the capture path (2026-11-06, decision `BJkByM`)

Ben delegated the call ("I trust your recommendations"). It follows the spike's recommendation (`2026-11-06-compositor-capture.md`), in three independent pieces:

1. **Ship the key-window override.** The host window claims to be key, so native controls draw active and `:focus`, `:focus-visible` and `document.hasFocus()` behave as in a real browser. **Pin the accent and highlight colors** to the system defaults rather than following the machine's System Settings, so a shot doesn't depend on who ran it.
2. **Live hosting, with the window pinned to sRGB, becomes the default host for one-shot verbs**, not just `shot`. This fixes `ND4YmR` (frozen rAF, transitions and Web Animations) and the 1 Hz nested-timer throttle (likely `PFrL42`). We accept the costs: every verb's timing changes (pages animate, so a mid-animation shot can differ run to run; `--wait-for` is the answer), and it relies on the occlusion SPI.
3. **`shot` renders through the compositor (`CARenderer`) by default where it can run.** It falls back to `takeSnapshot` when the area holds `<video>`, and **the output names the renderer**. A shot taken with the fallback keeps the CSS 3D caveat (`YnX53e`). We accept the second SPI (`_doAfterNextPresentationUpdate:`), the per-capture layer re-parenting, slower 2× shots, and strips for 2× pages taller than 8,192 CSS px.

Piece 3 needs piece 2; piece 1 stands alone. Build leaves: the split of `8F71rl`.
