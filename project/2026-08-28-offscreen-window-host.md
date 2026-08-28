# The off-screen window host — what a window buys, and what it does not

**Date:** 2026-08-28. Measured by the `window` agent while building `OffscreenWindow` and `PageHost.ensureOffscreenWindow()`.

**Host:** Apple silicon Mac, one built-in Retina display (`NSScreen` frame 1680×1050 points, `backingScaleFactor` 2.0), macOS 26.5.2 (build 25F84), Swift 6.3.3, `arm64e-apple-macos14.0` test platform. Every figure below is reproduced by `swift test --filter OffscreenWindow` in the package root (run **without** `--quiet`; the figures are printed by the tests, prefixed `[offscreen]`). Figures marked *probe* came from a throwaway probe suite of the same shape, deleted after measuring; the recipe is given where it matters.

## The headline

**A window is necessary but not sufficient.** Parking a `WKWebView` in an off-screen `NSWindow` does *not*, on its own, make WebKit render the page: `requestAnimationFrame` stays frozen, CSS transitions do not advance, and `document.visibilityState` stays `"hidden"` — at every window ordering, and even for an on-screen window. What turns rendering on is the window **plus** opting the web view out of window-occlusion detection (`OffscreenWindow.Rendering.live`, a private WebKit selector — see "The one piece of SPI" below). With both, the hosted page runs rendering updates and animates on the wall clock (rate figures and their caveat below).

This corrects, for the hosted case only, the standing `gotchas.md` claim that "`requestAnimationFrame` never fires in a headless `WKWebView`". The windowless claim is unchanged and still true.

## (a) `requestAnimationFrame`

| view | rAF ticks in 300ms |
| --- | --- |
| windowless (today's every verb) | 0 |
| hosted, `Rendering.hidden`, any ordering | 0 |
| hosted, `Rendering.live` | 12 |

The fixture (`Tests/TestSupport/Fixtures/animation.html`) calls its first tick directly, so its counter reads `1` when no frame ever ran; the table subtracts that. Reproduce: `swift test --filter OffscreenWindow`, lines `[offscreen] rAF ticks in 300ms …`.

The rate is contended, not fixed. With a 500ms window during development: 34 and 18 on two `--filter OffscreenWindow` runs (nine WebKit instances live), and **4** inside the full `swift test --quiet` (the whole suite, twelve instances — `WebKitGate`'s width). Treat ~60Hz as a ceiling a busy machine will not reach; the tests assert only frozen-or-running, and no test here should ever depend on a frame *rate*.

## (b) CSS transitions

A 6s linear `opacity` transition, read through `getComputedStyle`. The page reports its own elapsed time alongside the opacity, because a 300ms `Task.sleep` is 300ms on an idle machine and several times that under the full suite — what matters is whether the transition tracked *the clock it actually had*:

| view | measured | a wall-clock transition would be at |
| --- | --- | --- |
| windowless | opacity 0.0 after 444ms | 0.074 — it never started |
| hosted, `Rendering.live` | opacity 0.053167 after 319ms | 0.053167 — exact |

So the hosted transition runs on the wall clock: not throttled, and not a catch-up jump. Reproduce: the `a CSS transition advances…` test, line `[offscreen] linear opacity transition …`.

## (c) Density: `backingScaleFactor`, `takeSnapshot`, and `contentsScale`

| configuration | window `backingScaleFactor` | page `devicePixelRatio` | raw `takeSnapshot` pixels for a 1280×800-point view |
| --- | --- | --- | --- |
| windowless | — | 2 | 2560×1600 |
| hosted | 2.0 | 2 | 2560×1600 |
| hosted, `wantsLayer` + `layer.contentsScale = 1` | 2.0 | 2 | 2560×1600 |
| hosted, `wantsLayer` + `layer.contentsScale = 3` | 2.0 | 2 | 2560×1600 |

**`wantsLayer` + `layer.contentsScale` does not change WebKit's rendering density.** Setting it on the web view *and* on the window's content view leaves both the page's `devicePixelRatio` and the raw snapshot raster exactly where they were. This is the honest answer the `shot --scale` recommendation asked for (`project/2026-08-28-shot-scale-flag.md`, "Force the source density"): **option 1 as written there does not work**, and `--scale` cannot be built on `contentsScale`.

What *does* move the page's density is `-[WKWebView _setOverrideDeviceScaleFactor:]` — private, and measured (*probe*): setting it to 1 or 3 changes `window.devicePixelRatio` to 1 or 3 in both hosted and windowless views, with `window.innerWidth` unchanged at 1280, which is exactly the "denser raster, same breakpoints" semantics `--scale` wants page-side. But the raw `takeSnapshot` raster stayed 2560×1600 in all four cases — it tracks the *host screen's* scale, and nothing here moved it. So on this 2× host the 2× pixels are already there (as the `--scale` doc says), and the open question — whether a 1× host can be made to produce 2× pixels — is **not answered** by the window host. That decision belongs with `--scale`; the honest fallback remains that doc's option 2, refuse rather than fake it.

Probe recipe: with the web view in an `OffscreenWindow`, call the selector through `NSSelectorFromString("_setOverrideDeviceScaleFactor:")` (`unsafeBitCast` to `@convention(c) (AnyObject, Selector, CGFloat) -> Void`), load, then read `window.devicePixelRatio` and `webView.takeSnapshot(configuration:)`'s `representations.first`.

## (d) Ordering — the answer is "it does not matter for rendering"

The brief expected ordering to be the lever. It is not. Measured across `unordered` (never ordered in), `orderBack(nil)` and `orderFrontRegardless()`:

| ordering | `NSWindow.isVisible` | `occlusionState` contains `.visible` | rAF ticks / 300ms |
| --- | --- | --- | --- |
| unordered | false | false | 0 |
| back | true | false | 0 |
| frontRegardless | true | false | 0 |

Ordering moves `isVisible` and nothing else. Also measured and equally ineffective (*probe*): `NSApplication.shared.finishLaunching()`; pumping the AppKit run loop (`RunLoop.main.run(mode:before:)` in a loop) instead of `Task.sleep`, in case the missing event loop was starving occlusion notifications; the `.accessory` activation policy instead of `.prohibited`; and an **on-screen** borderless window at `alphaValue = 0` ordered front. In every one of those the page stayed hidden and `occlusionState` never became `.visible`.

`OffscreenWindow` therefore defaults to `Ordering.back` — the least intrusive ordering that still puts the window in the window list, so `NSWindow.isVisible` is `true` for the AppKit printing paths `pdf` pagination will go through. The enum is kept because that claim about printing is *not yet measured*; leaf 25Mev should confirm which ordering `NSPrintOperation` needs.

> **Corrected 2026-08-28 by leaf 25Mev.** Printing does not need `isVisible`, or any particular ordering: all six `(Ordering, Rendering)` pairs print byte-identical PDFs, and so does a web view in no window at all. See the printing addendum at the end of this document; `PDFOperation` asks for `Ordering.unordered`. `OffscreenWindow`'s default stays `.back`, now justified only as "in the list, out of the way".

## The one piece of SPI

`-[WKWebView _setWindowOcclusionDetectionEnabled:]` — sent `NO` once, right after the view is put in the window — is what makes the hosted page render. `WKWebView` derives page visibility from its window's `occlusionState`, and the window server will never call a window parked off every display "visible", so there is no public way out of it. This is the same lever WebKit's own test runner pulls to host a web view off-screen.

It lives in exactly one place, `OffscreenWindow.disableWindowOcclusionDetection(on:)`, guarded by `responds(to:)` so a future macOS that drops the selector degrades to `Rendering.hidden` behaviour rather than crashing — and the rAF test goes red, which is the correct alarm. `NSWindow` has no equivalent: `_setWindowOcclusionDetectionEnabled:`, `_setOcclusionState:` and `_setAllowsWindowOcclusion:` are all absent from `NSWindow` on this OS (*probe*, `NSWindow.instancesRespond(to:)`).

**This is a decision the main thread should ratify.** Shipping private API is a standing maintenance and fragility cost. The alternative is to ship the window without it, which serves `pdf` (a window is all `NSPrintOperation` needs) and leaves the time-series spike impossible — a hosted page that still cannot animate. The build here takes the SPI, isolated and guarded; reverting it is deleting one function and one `if`.

## (e) `document.visibilityState`

`"hidden"` windowless; `"hidden"` hosted with `Rendering.hidden`; `"visible"` hosted with `Rendering.live`. It is a faithful mirror of WebKit's page activity state, which is why it is asserted as its own test — it is the cheapest one-call check of whether a host is live.

## Hosting does not change the pixels

A `shot --full-page` of `capture-tall.html` came back **byte-identical** (82,445 bytes, 1280×3016) windowless and hosted, and an element capture below the fold still works hosted — so a view whose frame is resized past its window's content rect is *not* clipped by the window, and `OffscreenWindow.resize(to:)` is a convenience for AppKit paths that consult the window, not a requirement for capture. Measured with a throwaway suite calling `ShotOperation(fullPage: true)` on both hosts (*probe*).

Byte-identical also says the useful thing: for a static page, hosting changes nothing an existing verb outputs. It is animation and printing that need it.

## What this means for the callers

- **`pdf` pagination (25Mev).** Done, and the answer is in the printing addendum below: a window to be modal *for* is the only requirement, ordering and rendering make no difference, and `PDFOperation` takes `ensureOffscreenWindow(ordering: .unordered, rendering: .hidden)`.
- **`shot --scale`.** The window does not help. `contentsScale` is a dead end (measured); `_setOverrideDeviceScaleFactor:` moves the page's `devicePixelRatio` but not the snapshot raster on this host. Design `--scale` on the existing normalization plus, if the density must be forced, a second SPI decision — and keep the "refuse rather than fake it" fallback.
- **The time-series spike.** Now possible: a hosted, live page animates on the wall clock at ~60Hz. Note the consequence — an infinite rAF chain is genuine activity, so `--wait-for idle` over a live hosted page will not settle. Hosting stays opt-in per operation for exactly this reason.

## Nothing visible, proved

`OffscreenWindowTests` asserts during a real load and snapshot: `window.screen == nil`; the window's frame intersects no `NSScreen.screens` frame; every *visible* `NSApp` window is off every screen; `NSApp.isActive == false`; `NSApp.activationPolicy() == .prohibited`, set before the first window exists. The policy is set once per process in `OffscreenWindow`, and no code path calls `makeKeyAndOrderFront` or `NSApp.activate`.

## Addendum, 2026-08-28: what printing actually needs

Measured by the `pdf` agent (leaf 25Mev) while rebuilding `PDFOperation` on `NSPrintOperation`. Same host as above. Reproduce the ordering matrix with the throwaway probe recipe below; the surviving assertions are in `CapturePDFOperationTests` (`swift test --filter PDFOperation`, without `--quiet`, lines prefixed `[pdf]`).

### The window matters less than the section above expected

The fixture is `print-paginated.html` (19 sized blocks plus two `.no-print` banners), printed at Letter through `WKWebView.printOperation(with:)` driven by `runModal(for:delegate:didRun:contextInfo:)`:

| rendering | ordering | `NSWindow.isVisible` | result |
| --- | --- | --- | --- |
| `hidden` | `unordered` | false | 15,207 bytes, 5 pages, body text present, `.no-print` absent |
| `hidden` | `back` | true | 15,207 bytes, 5 pages, identical |
| `hidden` | `frontRegardless` | true | 15,207 bytes, 5 pages, identical |
| `live` | `unordered` | false | 15,207 bytes, 5 pages, identical |
| `live` | `back` | true | 15,207 bytes, 5 pages, identical |
| `live` | `frontRegardless` | true | 15,207 bytes, 5 pages, identical |

**All six are byte-identical.** Ordering does not matter to printing, and neither does `Rendering` — the SPI is not on `pdf`'s path at all. One more configuration, measured because it is the honest control: a web view in **no window at all**, printed modally for an *unrelated* off-screen window hosting a plain `NSView`, produced the same 15,207 bytes and 5 pages.

> **Correction to "(d) Ordering", above.** That section says `Ordering.back` is the default so that "`NSWindow.isVisible` is `true` for the AppKit printing paths `pdf` pagination will go through", and flags the claim as unmeasured. It is now measured and it was wrong: printing needs no visible window, and `Ordering.unordered` prints the same bytes. The same over-claim is in `OffscreenWindow`'s own DocC — "`NSPrintOperation` … refuses a view that has none". What actually needs a window is `runModal(for:…)`, whose parameter is a window; the *view* need not be in it, because `printOperation(with:)` paginates in the web content process rather than through AppKit's drawing of the view.

`PDFOperation` therefore asks for `ensureOffscreenWindow(ordering: .unordered, rendering: .hidden)`: the least intrusive pair, a window that never enters the window list, and no private API on the `pdf` path. `OffscreenWindow`'s own defaults are unchanged (`.back`, `.live`), which is what a rendering caller wants.

### `NSPrintOperation(view:)` is the wrong constructor

Building the operation as `NSPrintOperation(view: webView, printInfo:)` — the shape the field report used — paginates **the right number of entirely blank sheets**: 5 Letter pages whose `PDFDocument.string` is the empty string. The page lives in another process, so AppKit's own drawing pass has nothing to draw. `WKWebView.printOperation(with:)` (public, macOS 11+) asks the web content process to lay itself out for paper and is the only path that produces text.

### `didRun:` arrives on a background thread

`runModal(for:delegate:didRun:contextInfo:)` finishes on a secondary `NSThread` (`-[NSConcretePrintOperation _continueModalOperationToTheEnd:]`), so an `@objc` callback that inherits `@MainActor` isolation from its class traps in `swift_task_checkIsolated` — `EXC_BREAKPOINT`, no message, exit 133, and no `Fatal error:` line anywhere in the test output. The crash report is the only thing that names it. The callback in `PrintRunner` is `nonisolated` and hops back to the main actor; its selector is pinned with `@objc(printOperationDidRun:success:contextInfo:)`.

### Margins: the page wins, and `NSPrintInfo` is only the fallback

Content inset measured as the first page's text bounding box relative to its media box (`PDFPage.selection(for:)` over the media box, then `PDFSelection.bounds(for:)`):

| fixture | `NSPrintInfo` margins | pages | content inset (left, top) |
| --- | --- | --- | --- |
| no `@page` rule | 0pt | 5 | 0.0, 3.7 |
| no `@page` rule | 72pt | 6 | 72.0, 75.7 |
| `@page { margin: 1.25in }` | 0pt | 3 | 90.0, 93.7 |
| `@page { margin: 1.25in }` | 72pt | 3 | 90.0, 93.7 |

So a `@page` rule **replaces** the `NSPrintInfo` margin rather than adding to it, and a document with no rule takes whatever `NSPrintInfo` says. The only thing our number decides is what an unstyled page gets.

**Ruling: `PDFOperation` sets all four `NSPrintInfo` margins to zero and says so in `--help`.** The rule a caller has to learn is then one sentence — *the page decides the margins* — with no inset a stylesheet author cannot see or cancel. The cost is that a page with no `@page` rule prints edge to edge; the fix is one line of CSS (`@page { margin: 0.5in }`), and it is visible in the document rather than hidden in the tool. `--margin <pt>` was therefore **not** built: it would be a second way to say something CSS already says, and it can only ever affect pages that said nothing. Un-park it if real pages turn up that must be printed with margins and cannot be edited.

### Probe recipe

A throwaway `@Suite` (deleted after measuring) that, for each `(Rendering, Ordering)` pair, builds a `PageHost`, calls `ensureOffscreenWindow(ordering:rendering:)`, loads `print-paginated.html`, runs `PDFOperation()`, and prints `PDFDocument`'s page count and `string`. The margin table came from the same suite building `NSPrintInfo` by hand at each margin value and driving `host.webView.printOperation(with:)` through a copy of `PrintRunner`.
