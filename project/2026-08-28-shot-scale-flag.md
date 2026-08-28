# `shot --scale` — a display-density flag for screenshots

**Date:** 2026-08-28. Written by Claude (Fable) after producing a client-facing report page in the hirewell repo whose product screenshots had to be Retina-sharp. Every claim below has a repro from that session; the code claims are from reading `Sources/SleepyHollow/Operations/ShotOperation.swift` at the working tree of that date.

## The need

A screenshot destined for a document viewed on a Retina display needs two device pixels per CSS pixel, or it reads as soft next to the page's own text. `sleepy shot` has no way to ask for that: `--size` sets the viewport in CSS points and the output is always one pixel per point.

## What we did instead, and why it is a hack

Two workarounds were tried; neither is acceptable as a standing recipe.

1. **CSS `zoom` injection.** `--inject` a one-line script setting `document.documentElement.style.zoom = "2"` at `--size 2560x1600`. Output is a 2560px-wide raster of a 1280-point layout — *except* that media queries evaluate against the 2560-point viewport, not 1280, so any responsive layout renders at the wrong breakpoint. In our case a form that is two-column on a laptop and single-column below ~1000 points came out in whichever layout the doubled viewport selected, not the one the doubled *density* should have preserved. It happened to be the layout we wanted; it will not be next time.
2. **Chrome for Testing with `--force-device-scale-factor=2`.** Correct density, correct breakpoints — and not WebKit, which is the entire reason `sleepy` exists in that repo (native form-control chrome differs, and the project rule is "check UI changes in WebKit before calling them done"). Ben's ruling on seeing it: use `sleepy`, not Chrome, for product shots.

## What the code already does

`ShotOperation.snapshotPNG` documents (measured, not from Apple's docs) that `WKWebView.takeSnapshot` returns an `NSImage` rasterized at the **host machine's screen backing scale** — 2× on a Retina Mac — even for a view never attached to a screen, and that `WKSnapshotConfiguration.snapshotWidth` only relabels the logical size. `pngData(rendering:atPixelSize:)` then re-renders that image into a bitmap of exactly `--size` pixels so the output "depends only on `--size`, never on which Mac ran the command — determinism by construction (vision doc §5)."

So on every Retina host the 2× pixels already exist and are thrown away on purpose. The flag is a choice about the *output* raster, and the determinism argument — which is right and should stay — is what shapes it.

## Recommendation

> **Built, 2026-08-28 (leaf 5BKGq). Two things below are wrong; read this first.**
>
> - **Option 1, "force the source density", does not work and was not built.** `wantsLayer` + `layer.contentsScale` moves neither the page's `devicePixelRatio` nor the raw `takeSnapshot` raster (measured: `project/2026-08-28-offscreen-window-host.md` § (c)). The shipped flag is **option 2 only** — refuse rather than fake it.
> - **The exit code is 5, not 4.** A host that cannot render at the requested density is an environment fact (`SleepyError.Kind.environment`), the same bucket as a dead helper; exit 4 means the *page* failed to load, which it did not.
>
> What shipped, otherwise as written: `--scale 1|2|3`, default 1, viewport and breakpoints untouched; `ShotCapture.rasterize` re-renders at `rect × scale`; the source density is read back from the snapshot's own bitmap representation (`pixelsWide ÷ size.width`) and a request above it throws *"This host renders at 2×; --scale 3 would upsample."*; the PNG carries 72 × scale dpi. `--scale` also became a repeatable sweep axis alongside `--size` and `--theme` (leaf yrhxs), which the original note did not anticipate.

Add `--scale <n>` to `shot` (default `1`; accept `1`, `2`, and probably `3`), meaning **device pixels per CSS point of the output PNG**. Layout, viewport, media queries and `--full-page`/`--element` geometry are unchanged; only the raster gets denser. `--size 1280x800 --scale 2` → a 2560×1600 PNG of exactly the page a 1280-point Retina laptop shows.

Implementation, in the terms of the existing code:

- `pngData(rendering:atPixelSize:)` renders into a bitmap of `pixelSize × scale` and sets `bitmap.size` to the point size (so the PNG carries the right DPI metadata — 144 for `--scale 2`). Cropped element/full-page rects stay in points; multiply at the bitmap boundary only.
- **Do not let the host decide.** The current normalization exists because the source raster's density is the host's. For `--scale 2` on a 2× host the re-render is lossless. On a 1× host (or a Retina Mac driving an external 1× display as main, which changes `NSScreen.main.backingScaleFactor`) the source raster is 1× and the re-render would be a blurry upscale that *looks* like a 2× capture. Two honest options, in order of preference:
  1. **Force the source density.** Put the web view in an off-screen `NSWindow` whose backing scale is set explicitly (`NSWindow` + `wantsLayer`, `layer.contentsScale = scale`; or the private-but-stable route of a window on a screen with that scale) so `takeSnapshot` renders at the requested density regardless of host. The field report of 2026-08-24 already records the off-screen-window recipe for `pdf` (park at (−20000, −20000), activation policy `.prohibited`); the same host serves both.
  2. **Refuse rather than fake it.** If the source raster's scale (`image.representations.first` pixel size ÷ point size) is below the requested `--scale`, exit non-zero with a `nextMove` saying the host cannot render at that density — never upsample silently. Determinism by construction means the *same command produces the same pixels or the same error* on every Mac.
- Element shots: the `boundingRect` crop is in points; the crop of the 2× source is at `rect × 2`, which the bitmap re-render handles if the rect is applied through `configuration.rect` as today.
- `--full-page` at `--scale 2` doubles the pixel count of an already tall image; keep the existing height ceiling in points, not pixels, and say in the help text that a 9,000-point page at 2× is a ~50 MB RGBA bitmap before PNG encoding.

Help text, in the house style:

```
--scale <scale>   Device pixels per CSS point in the PNG: 1 (default), 2 or 3.
                  Layout, breakpoints and --size are unchanged; only the raster
                  is denser. Exit 4 if this host cannot render at that density.
```

## How to verify

1. `sleepy shot <url> --size 1280x800 --out a.png` and `--scale 2 --out b.png`: `b.png` is 2560×1600; downsampled by half it is pixel-identical (or within antialiasing noise) to `a.png`.
2. A page with a media query at 1000 points renders the same breakpoint in both — that is the property the `zoom` hack breaks.
3. `--element` and `--full-page` at `--scale 2` produce rects exactly 2× the 1× rects.
4. On a 1× main display (System Settings → Displays → a non-Retina external as main, or `defaults write -g AppleDisplayScaleFactor` is *not* enough — measure), the command either renders at 2× via the forced window or exits 4; it never produces a soft image with a 2× pixel count.

## Why it matters beyond one report

Every document an agent produces for a human on a Mac is viewed on a Retina display. Without this flag the agent either ships soft screenshots, or reaches for a different browser (which the 2026-08-24 field report already lists as the failure mode `sleepy` exists to prevent), or injects `zoom` and quietly renders the wrong breakpoint. A one-flag fix removes all three.
