# Feedback from embedding SleepyHollow in Woodcase's test harness

**Date:** 2026-08-29. **Source:** Woodcase commit `4764baf` ("Rebuilds the WebView test harness on SleepyHollow"), which replaced a 231-line `WKWebView` harness with `PageHost`, pinned to `35c1b0c`. Every one of Woodcase's 25 MAE snapshot rows came out byte-identical, so the library does the job; this is the list of what the first real embedding had to work around. Findings, not tasks — file the ones worth doing in `job`.

## 1. `WaitCondition` polls from the host and starves under a busy main actor

`WaitEngine` re-checks `.predicate(…)` (and the idle loop) from the host, on `@MainActor`, every 50 ms. In a process that saturates the main actor — Woodcase's parallel test suite, with renderer work on every core — the poll simply does not get scheduled: a page that set `window.__READY__` at 200 ms reported a 10 s timeout, and the two affected tests passed every time they ran alone. The harness had to abandon `WaitCondition` and keep its old page-side mechanism: a `setTimeout(check, 16)` loop *inside the page* that `postMessage`s once, received via `InjectedScript` + `messages(named:in:)` — one main-actor hop instead of N.

`SelectorWatch` already has the right shape (page-side `MutationObserver`, one push). Suggested: a predicate condition that is evaluated page-side and posts once (`WaitCondition.predicate` could compile to exactly that), or an explicit `WaitCondition.signal(messageName:)`. This is the one item that cost real time — it passes every test in isolation and only fails the full suite, which reads as flakiness in the consumer.

## 2. `Package.swift` understates the ArgumentParser floor

`sleepy` uses `@Option(defaultAsFlag:)`, which is swift-argument-parser 1.8+, but the manifest declares `from: "1.5.0"`. A consumer whose graph resolves 1.5–1.7 (Woodcase had 1.7.1) gets a compile error in a product it never asked for, because `swift build` builds every product in the graph. Raise the floor to `from: "1.8.0"`.

## 3. No file-access root on `LoadOptions`

`PageHost.load` calls `webView.load(URLRequest(url:))`. For a `file:` document that *does* reach relative subresources in sibling and parent directories (measured: `../js`, `../images`, `../../Fonts` and an `@font-face` `file:` URL all loaded), so Woodcase's `allowingReadAccessTo:` parameter became unused. But `WKWebView.loadFileURL(_:allowingReadAccessTo:)` grants more than that — `fetch()`/XHR against local files — and `LoadOptions` cannot express it. Worth a `LoadOptions.fileAccessRoot` if local-file pages matter. Also worth one sentence in the docs saying what a plain file load can and cannot reach.

## 4. No transparent-backdrop option

Woodcase's components are compared against a renderer output with a transparent background, so the WebKit view must not paint white. Getting that meant `host.webView.setValue(false, forKey: "drawsBackground")` — a private KVC key, on the `webView` the docs reserve for capture/find/cookie use. A `LoadOptions` flag (or a `ShotOperation` option) for opaque vs. transparent backdrop would retire the private key.

## 5. No public resize on `PageHost`

The viewport is fixed at `PageHost.init`. A component snapshot measures its content and re-captures at that height, which today means writing `host.webView.frame` directly and bypassing everything the host knows about its viewport. A `host.resize(to:)` — even one that just documents that the next shot uses the new size — would make this a supported path.

## 6. Getting pixels back means a PNG round trip

`ShotOperation.render(on:)`, the one that returns a `ShotCapture`, is internal; the public `execute(on:)` yields encoded `ShotImage`s, so an external caller decodes with `ShotCapture(decoding:)` to get a `CGImage`. Lossless, but a needless encode/decode on every snapshot. Making `render(on:)` public (or adding a `CGImage`-returning variant) would remove it.

## 7. Two behaviours worth documenting, not changing

- `ColorTheme` defaults to `.light` and `PageHost` stamps `NSAppearance(named: .aqua)` on the view. A raw `WKWebView` inherits the system appearance, so a consumer moving from one to the other on a Mac in Dark Mode will see every baseline shift. The SleepyHollow behaviour is the deterministic one — say so in the docs so the shift is expected.
- `ShotScale` is explicit; a raw `takeSnapshot` inherits the display density. Woodcase pins `ShotScale(factor: 2)` and now fails loudly on a non-Retina Mac instead of silently producing 1× images. Also the better behaviour; also worth a sentence.

## What went right

`PageHost` + `LoadOptions` + `InjectedScript` + `ConsoleOperation` + `ShotOperation` mapped one-to-one onto the old harness's pieces, the windowless host snapshots without an `OffscreenWindow`, `document.fonts.ready` and a 150 ms settle carried over unchanged, and the result was pixel-identical on the first full run once the wait was page-side. The library is the right layer for this; nothing above is structural.

## Addendum, later the same day: what the suite-speed leaf found

**Source:** Woodcase commit `09a648a` ("Makes the WebView regression suite 2.3x faster without moving a pixel"), written up in Woodcase's `project/2026-08-29-test-suite-speed.md`. Ben asked mid-task whether the seconds were in SleepyHollow. **They are not:** `PageHost` creation is 14 ms and the shot pipeline 22 ms, both noise (`WOODCASE_TEST_PROFILE=1 swift test --filter WebViewRegression`, quiet machine). The seconds were the fixture pages' own 3.4 MB of JavaScript loaded into eleven cold hosts, and reusing hosts recovered 56 % of them without SleepyHollow changing — `PageHost` is already reuse-correct: `load` refuses only a *concurrent* load, and every piece of per-load state resets on navigation. Four changes would let the consumer's harness shrink further, in the order they would pay:

## 8. Budget is per-host, so a shared host needs a pool keyed by budget

`PageHost.budget` reads `options.budget`, fixed at `init`. A caller wanting a 2 s failure and one wanting 30 s cannot share a host, so Woodcase's harness keeps a pool keyed by budget — a data structure that exists only because of this. Suggested: `func load(_ url: URL, budget: TimeInterval? = nil)`, falling back to `options.budget ?? LoadOptions.defaultBudget`. Additive, and it collapses the pool to one host.

## 9. Hosts cannot share a resource or bytecode cache

Every `PageHost` gets `WKWebsiteDataStore.nonPersistent()` and its own content process, so two hosts share nothing. Measured value of a warm cache: **142 ms per page load** on a 3.4 MB-of-scripts page. Suggested: let `LoadOptions` optionally carry a `WKWebsiteDataStore` (and/or a shared `WKProcessPool`) so a caller running many pages can opt in, with today's per-host non-persistent store as the default. This is not test-only — `sleepy shot --sweep` and any batch verb pay the same cost per page.

## 10. Reinforces #1: a message-named wait condition

The same starvation described in #1 is why Woodcase still loads with `wait: nil` and keeps `readySignalScript` + `waitForSignal`. The smallest fix is `WaitCondition.message(name:)` — settle when the page posts to a named script-message handler — roughly 20 lines in `WaitEngine`. It would let the consumer delete two of its own pieces and stop documenting a reason to avoid a SleepyHollow feature.

## 11. No "has painted" signal, so consumers sleep a flat 150 ms

After `document.fonts.ready` the harness sleeps 150 ms to let a final paint land — 1.75 s of an 8.1 s suite, and a guess in both directions. SleepyHollow already has `IdleWatch`, and the CLI has `ObserveRendering`; a `PageHost` operation that resolves when the next paint has committed (`requestAnimationFrame` under `ensureOffscreenWindow()`, or a rendering-update observer) would replace the sleep with a condition. The constraint it must respect is the trap that makes it worth owning here rather than in each caller: a headless web view never runs `requestAnimationFrame` unless an operation opts into an offscreen window.

Items 8 and 9 are what Woodcase would use tomorrow; 10 and 11 would let its harness shrink.
