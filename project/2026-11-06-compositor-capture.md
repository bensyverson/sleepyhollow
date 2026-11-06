# Compositor capture: CARenderer draws a live page in true 3D

**2026-11-06 — findings for the spike leaf `B3dXgQ` (True-3D shots, `DG1Jbo`); feeds the decision leaf `BJkByM`.** Plan: [2026-11-06-true-3d-shots.md](2026-11-06-true-3d-shots.md). Questions 8 and the CSS3DRenderer case were added mid-spike from [2026-11-06-webgl-scene-feedback.md](2026-11-06-webgl-scene-feedback.md).

**Host:** MacBook Air (M1, 8 cores, 16 GB), built-in Retina display (2560×1600, backing scale 2, Display P3), macOS 27.0.1 (26A434), Xcode SDK 27.2, Swift 6.4.2. The load average is printed with every figure; it ran from 160 down to 5 over the session (other agents' suites), and the cost table says which figures are quiet.

**Probe:** `scripts/compositor-probe.sh <mode>` (sandbox off; WebKit cannot start inside it). It compiles `Sources/SleepyHollow` together with `scripts/compositor-probe/*.swift` into one binary, so it drives the real `PageHost`, `ShotOperation` and wait engine, and writes its PNGs to `.build/compositor-probe/out/`. Fixtures are in `scripts/compositor-probe/fixtures/`. Every figure below names its mode; `PROBE_WINDOW_SRGB=1` and `PROBE_RENDER_CS=p3` are the two switches it reads. The capture itself is `scripts/compositor-probe/CompositorCapture.swift`, about 100 lines.

## The headline

**Yes: on this macOS, `CARenderer` renders a live hosted `WKWebView`'s layer tree with true 3D**: perspective foreshortening, `preserve-3d` depth sorting and backface culling, matching hand-computed geometry and `getBoundingClientRect()` to about one pixel. WebKit composites in the UI process here, so the layers under `WKWebView.layer` are real `CALayer`s with real 4×4 transforms and `IOSurface` contents. No `CALayerHost` stands in the way, except for video.

It is not free of caveats, and four of them decide the build:

1. **Video is missing** (a remote-hosted layer CARenderer cannot see into), and the capture does not say so. That would be a plausible wrong answer.
2. **The host window's color space must be pinned to sRGB.** Otherwise WebKit paints its tiles in the display's Display P3 and saturated colors shift by up to 29 levels against `takeSnapshot`. With it pinned, a flat page matches `takeSnapshot` to anti-aliasing (0.02% of pixels off by more than 8).
3. **Readiness needs a second SPI**, `-[WKWebView _doAfterNextPresentationUpdate:]`. Without it 13 of 20 captures showed the previous frame; with it, 20 of 20 were current.
4. **`CARenderer.layer =` takes the layer out of the window.** The capture has to move the web view's backing layer into a wrapper and put it back. That works, but it is a hack on AppKit's layer ownership.

Two findings stand on their own and could ship without the compositor path. **A key-window override fixes the faint native controls** (question 7). **Live hosting fixes `ND4YmR` and the 1 Hz timer throttle** (questions 6 and 8).

## The cause of flat shots: confirmed, with one correction

The plan reasoned that `takeSnapshot` repaints in software with each transform reduced to 2D affine. The pixels agree. Case A (below) comes out as a rectangle squeezed to the projected width (x 64–203 against a true 72–216). Case C comes out as a rectangle scaled by cos 45° in y. `translateZ` moves nothing, and the back face paints in DOM order. The source is still not traced, but every symptom matches an affine projection and no other.

The correction: **`takeSnapshot` does not read the compositor even on a live hosted view.** In `t3d` and `flat` mode the snapshot is taken from the same live host as the compositor capture and is still flat. Its pixels on a flat page are identical, windowless or live (`flat`, control line: max Δ 2, 0 pixels Δ>2). Live hosting alone fixes nothing in `shot`.

A second difference turned up that the plan did not predict. **`takeSnapshot` drops `backdrop-filter`**, while the compositor draws it (question 3). So the software paint is wrong for more than 3D.

## 1. Does it work?

**Yes.** `scripts/compositor-probe.sh tree` dumps the layer tree under `WKWebView.layer` after a commit. Abridged, for the 3D fixture:

```
NSViewBackingLayer "WKWebView"
  CALayer
    WKCompositingLayer "drawing area root"
      … "frame scrolled contents" › "content root" › "RenderView"
        WKCompositingLayer "TileGrid container"
          WKCompositingLayer "tile at 0,0"  contents=CAIOSurface scale=2.0
        WKCompositingLayer "Page TiledBacking containment"
          WKCompositingLayer "…DIV class='stage'"   sublayerTransform m34 -0.00167   (perspective: 600px)
            WKCompositingLayer "…DIV id='a'"        3D transform (m13 0.766)
          CATransformLayer "preserve-3d: …flipper"
            WKCompositingLayer "…id='b-front'"      single-sided
            WKCompositingLayer "…id='b-back'"       3D transform, single-sided
          WKCompositingLayer "…DIV id='c'"          3D transform (m34 -0.00177)       (perspective() in the transform)
```

CSS `perspective` becomes `sublayerTransform.m34 = -1/600`, `preserve-3d` becomes a `CATransformLayer`, and `backface-visibility: hidden` becomes `isDoubleSided = false`. Those are Core Animation's own 3D primitives, and `CARenderer` honors them. Contents are `CAIOSurface` objects (`CFCopyTypeIDDescription`), which an in-process `CARenderer` composites. The web process paints them; the UI process only owns the tree.

**How the capture works** (`CompositorCapture.capture`):

1. Wait for `_doAfterNextPresentationUpdate:` (see question 4).
2. Make a wrapper `CALayer` sized to the output pixels, with `sublayerTransform = scale(s, s, 1)`. Move `webView.layer` into it. `CARenderer.layer =` would detach the layer from its superlayer anyway (measured: `superlayer` reads `nil` afterwards), so the capture takes control of that and puts it back.
3. `CATransaction.flush()`. Without it the first render came back blank white (exploratory probe).
4. `CARenderer(mtlTexture:options:)` into a `.bgra8Unorm` `.shared` texture, with `beginFrame` / `addUpdate` / `render` / `endFrame`. An empty command buffer on the renderer's own queue, `waitUntilCompleted`, serves as the GPU fence.
5. Re-insert the backing layer at its old index, flush, read the texture back, and flip the rows (Core Animation draws bottom-left-origin).

Gotchas: the scale must go on a wrapper, not on the web view's layer. A *negative* y-scale to flip the image would also flip every face's winding and invert backface culling, so the flip is done on readback.

**Other routes measured:**

- `-[WKWebView _windowSnapshotInRect:withOptions:]` (SPI, `spi` mode) returns an `NSImage` (not a `CGImageRef`; calling it as one crashes) of 2000×520 pixels, **fully transparent**. The window server holds nothing for a window parked off every display. Dead.
- `WKSnapshotConfiguration` on macOS has no SPI beyond `snapshotWidth` (`spi` mode lists the selectors). There is no `afterScreenUpdates`, and no compositor-reading flag.
- `_takeSnapshotOfNode:completionHandler:` and `_takePDFSnapshotWithConfiguration:completionHandler:` exist; both are named for the paint paths, so they were not pursued.
- `CALayer.render(in:)` is ruled out by the brief: it flattens 3D too.

## 2. Fidelity

### The 3D fixture (`t3d` mode, `fixtures/t3d.html`, 1000×260)

Four cases, one solid color each, found by color in the output. The expected geometry was derived by hand (perspective divide about the perspective origin; the derivation for A is below). WebKit's own `getBoundingClientRect()` agrees with the hand figures to 0.1 px. Figures are CSS px at 1×. "Column" is the height of the shape's leftmost and rightmost columns, and "row" the width of its top and bottom rows, sampled 3 px inside the edge.

| case | expected | compositor | takeSnapshot |
| --- | --- | --- | --- |
| A. `perspective: 600px` parent, `rotateY(-50deg)` | x 72.0–216.3, y 10.9–197.1; left column 140.2, right 186.2 | x 72–215, y 11–196; columns 140 / 184 | x 64–203, y 24–183; columns 160 / 160 (a rectangle) |
| B. `backface-visibility: hidden` flip card | green front only | green front only; orange back absent | **orange back** over the whole card, mirrored |
| C. `perspective(400px) rotateX(45deg)` | x 493.9–750.1, y 54.4–169.9; top row 192.8, bottom 256.2 | x 495–748, y 55–168; rows 194 / 252 | x 497–746, y 59–148; rows 219 / 219 (a rectangle) |
| D. `preserve-3d`, red `translateZ(60px)` first, yellow `translateZ(-60px)` later | red x 766.0–899.3; red wins the overlap | red x 766–898; overlap at (856,104) is **red** | red x 776–895; overlap is **yellow** (DOM order) |

The derivation for A: the element's center and the perspective origin coincide at the stage center, (110, 80) inside a stage at page (24, 24). An edge at x = ±110 rotates to x′ = ±110·cos 50° = ±70.7 and z′ = ±110·sin 50° = ±84.3 (the right edge comes toward the viewer). It projects with scale 600 / (600 − z′), which is 1.1635 on the right and 0.8768 on the left, giving x = 216.3 and 72.0 and half-heights of 93.1 and 70.1. C and D follow the same way.

The 2× run matches to the pixel at double the figures (for example, A's columns are 280 / 370). Shot PNGs: `t3d-{compositor,snapshot}-{1,2}x.png`.

### CSS3DRenderer (`css3d` mode, `fixtures/css3d.html`, 1000×500)

This is the DOM three.js's `CSS3DRenderer` builds, written by hand: a `perspective: 500px` viewport, a `preserve-3d` camera element with `translateZ(500px) matrix3d(camera inverse, z −1000) translate(500px, 250px)`, and panels placed with `translate(-50%,-50%) matrix3d(world)`. It reproduces the field report exactly:

| panel | expected (= `getBoundingClientRect`) | compositor | takeSnapshot |
| --- | --- | --- | --- |
| blue, 400×200, facing the camera at the origin | x 400–600, y 200–300 (half size: z = −500) | x 400–599, y 200–299 | x 300–699, y 150–349: **double size**, overflowing its true box |
| green, 300×200, `rotateY(40deg)` at world x 700 | x 823.8–871.6, y 194.7–305.3; left column taller | x 824–870, y 195–304; columns 108 / 92 | **absent** |

So "panels missing from where they belonged while `getBoundingClientRect` reports them on screen" is the affine flattening: `translateZ` and the camera's z-translation are dropped, so every panel is drawn at its unprojected size, and one placed off-axis lands outside the viewport.

### A flat page against `takeSnapshot` (`flat` mode, `fixtures/flat.html`, 800×500)

The page has text in three faces, a gradient, rounded bordered cards with a shadow, an opacity group and an image, and nothing composited (`tree flat.html` shows two tiles and no other layer).

| host window color space | scale | pixels Δ>2 | Δ>8 | Δ>32 | max Δ |
| --- | --- | --- | --- | --- | --- |
| inherited (Display P3) | 1× | 8.34% | 7.18% | 0 | 21 |
| inherited (Display P3) | 2× | 8.30% | 7.17% | 0 | 29 |
| `window.colorSpace = .sRGB` (`PROBE_WINDOW_SRGB=1`) | 1× | 1.03% | 0.02% | 0 | 14 |
| `window.colorSpace = .sRGB` | 2× | 1.07% | 0.02% | 0 | 30 |

With the inherited space, every differing pixel is a saturated color (`flat-diff-1x.png`). Text is identical. The opacity card reads (145, 207, 178) in the compositor capture against (132, 206, 178) in the snapshot, and the snapshot is the right one: #2a7 at 0.55 over #fafafa is (131, 206, 178). Changing the *renderer's* color space to P3 (`PROBE_RENDER_CS=p3`) changes nothing. Pinning the *window's* color space removes it. The likely reading, not traced: WebKit paints tiles in the window's color space (the P3 display's, even for a window on no screen), and the surface is not tagged so that `CARenderer` converts it back. What remains after pinning is anti-aliasing at glyph and corner edges.

Pinning the window's color space also moves `takeSnapshot` on a hosted view. On the controls page, hidden-hosted against windowless differs in 0.51% of pixels by more than 32 with sRGB pinned, against 0 with the inherited space (`controls` mode under `PROBE_WINDOW_SRGB=1`). Whichever renderer ships, its host window's color space is part of the output and must be fixed, not inherited from whatever display the Mac has.

## 3. What it misses

`media` mode, `fixtures/media.html` at 900×420, 2×, waiting for `body[data-ready]` (the video has played past 0.1 s, the late font has loaded). The probe writes a magenta H.264 movie with AVFoundation, so no binary file lives in the repo.

| content | compositor | takeSnapshot |
| --- | --- | --- |
| `<video>` (playing, `currentTime` 0.24 s) | **missing**: white | present (232, 49, 247) |
| WebGL canvas | present (134,400 of 134,400 px) | present |
| 2D canvas | present | present |
| `backdrop-filter: invert(1)` | **correct**: the covered black stripe reads white | **missing**: the stripe stays black |
| a font injected 300 ms after load | correct block glyphs, 17,694 px of ink | identical |

- **Video is a remote layer** (presumably a `CALayerHost` for the GPU process's video layer; the tree under a playing video was not dumped). `CARenderer` draws nothing there and raises no error. A build must detect `<video>` in the shot area and fall back to `takeSnapshot` or say so. Silent omission breaks the "never a plausible wrong answer" ruling.
- **Late fonts** are a readiness question, not a compositor one. Once the page says it is ready and a presentation update has landed, the glyphs are there.
- **Full page and far `--rect`** (`fullpage` mode, `capture-banded.html`, 12,982 px tall). Growing the web view's frame to the document height, as `ShotOperation` already does for `--full-page`, makes WebKit tile *all* of it: 78 tiles with contents, the lowest edge at 12,982 pt. The 1× capture shows all 13 bands correctly, in 467 ms with the footprint at 189 MB. Growing the window too makes no difference. A `scrollTo(0, 9200)` is followed as well: the capture's top row is band 9. So no scroll-and-stitch is needed for coverage. One limit remains: **Metal textures stop at 16,384 px**, so a 2× capture of a page taller than 8,192 CSS px must be rendered in strips (render the wrapper with a translated `sublayerTransform`, one texture per strip). That part was not built.

## 4. Readiness

`readiness` mode: the page's swatch color is changed by an evaluate, then the capture runs at once, 20 times per arm.

| before rendering | current frame | previous frame | other |
| --- | --- | --- | --- |
| nothing | 2 | 13 | 5 |
| `await _doAfterNextPresentationUpdate:` | **20** | 0 | 0 |

`-[WKWebView _doAfterNextPresentationUpdate:]` (SPI, the hook WebKit's own layout tests use before reading pixels) calls back once the UI process has applied a layer-tree commit that includes everything the page did before the call. That is the happens-before the no-fixed-delays rule asks for. It costs 0.3–0.6 ms on a quiet page (bench, "commit"). It completes on a page that is busy animating because a live page commits every frame. A hidden page was not tried, because the compositor path is live by construction. Page-side readiness (fonts, images, `--wait-for`) stays the wait engine's job; this hook only closes the gap between "the DOM is ready" and "the layers show it". The guard for the build: `responds(to:)` plus a red test, as for the occlusion SPI.

## 5. Cost

`bench 20` mode: 20 captures of a 1280×800 live page (`t3d.html`) per arm, after one warm-up of each. Times are medians, with p90 in brackets. "Readback" is the probe's naive row-flip copy in an unoptimized (`-Onone`) build, so it is an upper bound.

| load average | scale | compositor total | commit / render / readback | takeSnapshot (`ShotOperation.render`) | footprint |
| --- | --- | --- | --- | --- | --- |
| 5.8 (quiet) | 1× | 17.9 ms (18.4) | 0.3 / 8.3 / 9.2 | 14.1 ms (14.6) | 79 → 76 MB |
| 5.8 (quiet) | 2× | 47.0 ms (48.6) | 0.3 / 9.3 / 37.4 | 7.7 ms (8.3) | 75 → 88 MB, peak 104 |
| 50 | 1× | 50.5 ms (61.4) | 0.5 / 30.5 / 19.4 | 30.8 ms (63.5) | 79 → 76 MB |
| 50 | 2× | 131 ms (258) | 0.6 / 34.6 / 89.7 | 14.5 ms (20.9) | 76 → 88 MB |

The render itself costs 8–9 ms quiet at either scale. Nearly all the gap at 2× is the readback, which an optimized build would shrink: a blit to a buffer, and a flip done by drawing rather than by copying rows. The first capture in a process is slow: 359 ms render at load ~100 (`t3d`, first line). That is the Metal and Core Animation renderer cold-starting, so a session amortizes it and a one-shot `sleepy shot` pays it once. The footprint grows by about 10 MB at 2× for the texture and the readback buffers, and does not grow across 20 captures. A 1× full-page capture of 12,982 px peaked at 189 MB.

## 6. Live-hosting side effects

`anim` mode: `ND4YmR`'s fixture verbatim, read after `body[data-done]` (1 s on the page's clock).

| host | rAF frames | transition | Web Animation |
| --- | --- | --- | --- |
| windowless (today) | 0 | `matrix(1, 0, 0, 1, 0, 0)` | running, `currentTime` 0 |
| hosted, `Rendering.hidden` | 0 | same | same |
| hosted, `Rendering.live` | **59** | `matrix(1, 0, 0, 1, 200, 0)` | **finished, 300** |

**Live hosting fixes `ND4YmR` completely.** These figures match Chrome's in that issue (60 frames, 200 px, finished at 300).

**`--wait-for idle` still settles on an infinite rAF chain** (`idle` mode, `raf-forever.html`): windowless in 1,012 ms with 0 frames, live in 598 ms with 31 frames drawn. **The claim in [2026-08-28-offscreen-window-host.md](2026-08-28-offscreen-window-host.md) that it "will not settle" is wrong**, and so is the same sentence in [2026-09-26-idle-page-throttling.md](2026-09-26-idle-page-throttling.md) § What does not work and in `OffscreenWindow.Rendering.live`'s DocC. `IdleWatch` defines idle over resource entries, fetch, XHR and images. A frame is none of those, so a page that only animates is idle. (Not corrected in place here: those docs and that DocC belong to the decision and build leaves; flagged for the coordinator.)

A live page is visible to WebKit, so it is also not throttled to the background band. The `holdingForeground` workaround (2026-09-26) should be unnecessary on that path. That follows from the mechanism and was not measured.

## 7. Inactive-window controls

`controls` mode, `fixtures/controls.html` at 520×260, 2×: text inputs (one focused from script), checkboxes, radios, a select, two buttons and a range. "Accent px" counts saturated blue pixels. Facts come from the page: `document.hasFocus()`, `:focus` and `:focus-visible` on the focused input, `visibilityState`, and focus events.

| host window | accent px | `hasFocus()` | `:focus` / `:focus-visible` | `visibilityState` | vs windowless |
| --- | --- | --- | --- | --- | --- |
| windowless (today) | 0 | false | false / false | hidden | — |
| hidden | 0 | false | false / false | hidden | identical |
| live | 0 | false | false / false | visible | identical |
| live + first responder | 0 | false | false / false | visible | identical |
| **hidden + `KeyClaimingWindow`** | **11,748** | **true** | **true / true** | hidden | 2.8% of px Δ>32 |
| live + `KeyClaimingWindow` | 11,748 | true | true / true | visible | same as above |
| either + `KeyClaimingWindow` + first responder | 11,748 | true | true / true | — | same as above |

**Reproduced:** windowless, the checked checkbox and radio are gray, the "Default" submit button is gray, the range fill is gray, the focused input has no focus ring, and its selected text is gray (`controls-windowless-2x.png`). `:focus` is *false* even though `document.activeElement` is the input, because the page does not have focus.

**The fix works:** `KeyClaimingWindow`, an `NSWindow` subclass returning `true` from `isKeyWindow` and `isMainWindow` (`ProbeHost.swift`), makes WebKit draw the controls active: blue accent, blue focus ring, blue default button, highlighted selection (`controls-hidden-key-2x.png`). WebKit notices **without any become-key notification**, because the override is in place before the view enters the window, and WebKit reads `isKeyWindow` when it does. It works **with or without `Rendering.live`**, so it is **independent of the compositor path and could ship on its own**. Making the web view first responder adds nothing.

Side effects: `document.hasFocus()` becomes true, and `:focus` and `:focus-visible` now match the focused input. That is what a real foreground browser reports, so the windowless values are the odd ones out. No `window` `focus` or `blur` event fired in any configuration. The input's own `focus` event fires on its `focus()` call in every windowed host, active or not.

Two cautions for a build:

- **Active controls draw in the host Mac's accent and highlight colors** from System Settings. The selection here is green because that is this Mac's highlight color. Inactive controls are gray on every Mac. Switching to active makes `shot` output depend on a per-user setting unless the build pins them, for example through `NSAppearance` or the `AppleAccentColor` / `AppleHighlightColor` defaults in the process's own domain (not measured).
- **Focus rings may animate.** The only region where the compositor and `takeSnapshot` disagreed on this page (0.17% of pixels, max Δ 109) is the focused input's ring. Not investigated.

## 8. Timers: nested timers are throttled to 1 Hz on a hidden page

Coordinator addition. `timers 10` mode, `fixtures/timers.html`: one loop per page, 10 s, ticks timestamped with `performance.now()`. The first gap over 100 ms is reported as a tick index. Two runs, at load 41 and at load 47; the figures agree.

| host | `setTimeout(tick, 16)` chain | `setInterval(tick, 16)` | `MessageChannel` ping-pong |
| --- | --- | --- | --- |
| windowless (today) | 1.9–2.0 Hz: gaps of 16–17 ms for 9 ticks, then **1,000 ms** from tick 10 on | 1.6–1.7 Hz: 1,000 ms from tick 6 | 62.3–62.5 Hz, max gap 22 ms |
| hosted, `Rendering.hidden` | 1.9–2.0 Hz, 1,000 ms from tick 10 | 1.7 Hz, 1,000 ms from tick 7 | 62.4 Hz |
| hosted, `Rendering.live` | 50.2 Hz: 16–17 ms for 9 ticks, then **20 ms** | 50.1 Hz, 20 ms | 62.5 Hz |
| live + `KeyClaimingWindow` | 50.2 Hz, 20 ms | 50.1 Hz, 20 ms | 62.5 Hz |

**The hypothesis is confirmed.** A hidden page's *nested* timers (a chain past nesting level ~5, or an interval past ~5 repeats) are aligned to one second. A `MessageChannel` is not a timer and escapes. It is not CPU throttling: the channel loop runs at full rate on the same page. The 2026-08-20 wait-engine probe saw unthrottled timers because it timed single, un-nested ones, which this throttle does not touch. Live hosting lifts the 1 s alignment. What remains is a 20 ms (50 Hz) floor on nested timers that a key window does not change. A 50 Hz WebGL loop is enough to render and capture.

**What it implies for the wait engine.** `PredicateWatch` re-checks with a `setTimeout(check, 16)` chain. On every windowless page, after the first ~10 checks (~170 ms) it re-checks once a second. A predicate that becomes true later is seen by the page-side watch up to a second late. On a responsive host, the 250 ms host-side backstop catches it first. Under a busy main actor, the very case the page-side watch was built for (2026-08-29 Woodcase finding 1), the latency approaches a full second. A `MessageChannel`-driven or `MutationObserver`-driven re-check would avoid it, as would live hosting. Not changed here; the premise in `2026-08-20-wait-engine.md` is the coordinator's to correct.

## What the brief and plan got wrong

- **"CARenderer is the right route" holds**, but it is not the public-API path the plan described. It needs a second private selector for readiness (`_doAfterNextPresentationUpdate:`), and it needs to detach the web view's layer from AppKit's tree for every capture. Both are measured and work. Both are fragility the decision should price in.
- **"Live hosting is the fix"** is incomplete for color: the host window's color space is part of the output and must be pinned.
- **"`--wait-for idle` will not settle on a live page with an infinite rAF chain"** is wrong (question 6).
- **"Page timers are not throttled in this WebKit"** (wait-engine doc) is wrong for nested timers on a hidden page (question 8).
- **"The compositor paints only around the viewport"** (plan, § Direction) does not bite. Grow the view and WebKit tiles the whole document; the real limit is the 16,384 px texture size at 2×.
- The plan's "What the compositor won't fix: native controls painted inactive" is right. The key-window override is the separate lever, and it works.

## Recommendation for `BJkByM`

**Ship in three independent pieces, in this order:**

1. **The key-window override, now, on its own.** It is a public-API subclass with no SPI, works on today's windowless-equivalent hidden host, fixes the faint controls, and makes `:focus` and `hasFocus()` truthful. It needs the accent and highlight colors pinned for determinism (one small follow-up measurement).
2. **Live hosting as the default host for one-shot verbs**, with the host window's color space pinned to sRGB. This closes `ND4YmR` and lifts the 1 Hz nested-timer throttle that broke the WebGL agent. It does not break `--wait-for idle` (measured), and it retires the foreground hold on that path. The cost is one SPI that is already approved and guarded.
3. **The compositor path as `shot`'s default renderer where it can run** (option (a)). That means viewport, element and `--rect` shots, plus full-page shots up to the texture limit (strips beyond it). The plan's stated preference holds on the evidence: the geometry is right to a pixel on every 3D case, a flat page matches `takeSnapshot` to anti-aliasing once the color space is pinned, it draws `backdrop-filter` that `takeSnapshot` drops, and it costs about 18 ms at 1× and under 50 ms at 2× quiet. **The exception is video:** when the shot area contains a `<video>` with a decoded frame, fall back to `takeSnapshot` (and, if 3D is also present, print the detection leaf's note). Name the renderer in the output, as the plan asks.

Not option (b) (compositor only when 3D is detected): two renderers chosen per page by a heuristic would flip anti-aliasing and `backdrop-filter` with one `translateZ`, and the compositor is the more correct of the two even on flat pages. Not (c) (behind a flag): the correct renderer should not be opt-in. Not (d) (park it): it works.

**Build-leaf must-haves the spike did not build:** strips for 2× captures over 16,384 px; `<video>` detection and fallback; an optimized readback; a red test for each SPI (`_setWindowOcclusionDetectionEnabled:`, `_doAfterNextPresentationUpdate:`); and a regression test on `t3d.html` and `css3d.html` geometry. The probe's fixtures and expected figures are ready to become that test.
