# Feedback from an agent driving a WebGL scene (2026-11-06)

> **Triaged 2026-11-06.** § 1 is a case on issue `ND4YmR` plus leaf `29a1Y3` (say so when animation frames never ran); § 2 is question 8 of spike `B3dXgQ`, and if it holds it corrects `2026-08-20-wait-engine.md` ("page timers are not throttled" was measured on single timers only); § 3 is a case on `Ft2O4Q`, with a CSS3DRenderer fixture in leaves `YnX53e` and `B3dXgQ`. The `--live` suggestion is an option on decision `BJkByM`.

An agent building a three.js page (Gaussian splats through the Spark renderer, plus HTML placed in the scene with three.js's `CSS3DRenderer`) used `sleepy` to check renders. Three things cost it time. The first two add cases to existing issues; the third may be new.

## 1. requestAnimationFrame never fires (adds to `ND4YmR`)

A page that renders from `renderer.setAnimationLoop` (rAF underneath) never drew a frame. `sleepy eval <url> --js "return await new Promise(r => { let n = 0; const f = () => { if (++n < 10) requestAnimationFrame(f); else r(n); }; requestAnimationFrame(f); setTimeout(() => r({ n, timeout: true }), 5000); })"` answered `{"n":0,"timeout":true}`. Nothing says so: the shot is a clean capture of the page's pre-render state (a title card), and `console` is empty. For a WebGL page that is a plausible wrong answer.

## 2. Timers run at about 1 Hz (possibly new)

Falling back to a `setTimeout(…, 16)` loop gave about one frame a second: the page's own frame counter read `1 fps · worst 1000.0 ms`. That looks like background-timer throttling of a non-visible page. A `MessageChannel` ping-pong loop (post a message, render when 16 ms have passed, otherwise post again) is not throttled and gave 40–60 frames a second, enough to render the scene and capture it. The workaround spins a core, so it is only for captures.

If live hosting (the `ND4YmR` and `Ft2O4Q` spike) makes the page visible, both 1 and 2 probably go away together. If it doesn't, a `--live` (or similar) switch that a WebGL page can opt into would help, and so would a note when a shot is taken while rAF callbacks are pending but have never run.

## 3. CSS3DRenderer output is flattened (adds to `Ft2O4Q`)

`CSS3DRenderer` puts every element under a `perspective` parent with `matrix3d` transforms. In the shot, the HTML panels were missing from where they belonged, while `getBoundingClientRect()` reported them on screen (one at 866×318 CSS px in the middle of the viewport). A three-box fixture (flat, `translateZ(0)`, and `rotateX(50deg)` under `perspective: 600px`) showed the rotated box drawn as a squeezed rectangle with no foreshortening, as the plan describes. The agent switched to headless Chromium over the DevTools protocol for those captures. That also gave real GPU timings (ANGLE on Metal), which an offscreen WebKit host can't give at the moment. A CSS3DRenderer page is a good real-world case for the spike's fixture set.

Versions: `sleepy` from Homebrew on macOS 27.0, 2026-11-06.
