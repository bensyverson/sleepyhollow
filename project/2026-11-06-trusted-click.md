# Trusted click by default, and the step settle without a grace window

2026-11-06 · leaves `v8Wtvb` (trusted click) and `7mWLWK` (step navigation settle)

**Outcome.** `click`, `--click` and `ClickOperation` are now real input: the pointer moves to the target and the primary button goes down and up through the host's off-screen window, so the page sees `isTrusted` true and WebKit runs the default action, scripts on or off. The JavaScript click is gone; no measured case needed it. And a step that starts a navigation is now waited for on the navigation delegate's own signals (commit, or provisional failure) instead of a fixed 0.5 s window for the navigation to start.

## How it works

- **Click.** A page-side body finds the target and answers a viewport point: for `--selector`, the element's center after `scrollIntoView({block: 'center'})`, refused as `disabled`, `not-visible` (no box) or `covered` (what `elementFromPoint` plus the open-shadow-root descent finds there is not the element or inside it). For `--at`, the document point scrolled into view and hit-tested exactly as before, which is what `hit` reports. Then `TrustedInput.click(atViewport:)` sends `_simulateMouseMove:` and a `leftMouseDown`/`leftMouseUp` pair through `NSWindow.sendEvent(_:)`, and waits on `_doAfterProcessingAllPendingMouseEvents:`. Whether the page navigated is the host's ordered judgment, `PageHost.navigationStarted(sinceRequests:)`, for every click: the page-side submit watcher and link test are retired for click (they remain for `submit`).
- **Settle.** Before each step the runner reads `NavigationProgress` (policy decisions, commits, provisional failures). After a step that reports a navigation: was a decision asked for since then (ordered, via `navigationStarted`)? If not, nothing to wait for. If so, wait until a commit or a provisional failure is counted, then for `isLoading` false and `readyState` complete — all bounded by the load's budget.

## Measurements

All on this Mac (macOS 27, 2026-11-06), load average 4–70 from other agents' suites; each figure is reproduced by the command named.

### What a decided navigation reports — `SLEEPY_MEASURE=1 swift test --filter NavigationSignalMeasurement`

A link click in a bare `WKWebView`, every navigation-delegate callback recorded with `isLoading`:

| Target | Callbacks after the action decision | Ends in |
|---|---|---|
| `204 No Content` | didStartProvisional, response 204 | didFailProvisional, WebKitErrorDomain 102 |
| response policy `.cancel` | didStartProvisional, response 200 | didFailProvisional, WebKitErrorDomain 102 |
| `Content-Disposition: attachment`, allowed | didStartProvisional, response (canShow false) | **didCommit**, didFinish |
| held 1 s, then 200 | didStartProvisional at once, response after 1 s | didCommit, didFinish |
| `mailto:` / unknown scheme | didStartProvisional | didFailProvisional, NSURLErrorDomain -1002 |
| top-level `data:` URL | didStartProvisional, response | didFailProvisional, WebKitErrorDomain 102 |
| cross-site (127.0.0.1 → localhost), held 1 s | **`isLoading` false for 62–77 ms** after the decision, then didStartProvisional | didCommit, didFinish |
| same-site 302 to cross-site | second action decision for the redirect; `isLoading` never dips | didCommit, didFinish |

Every decided main-frame navigation ended in a commit or a provisional failure, so "commit or provisional failure" is a wait that always ends. In every case `isLoading` was still false when the click's evaluate returned.

### Why the 0.5 s grace lost (`7mWLWK`)

The old settle waited up to 0.5 s for `isLoading` to turn true (or a document mark to vanish), then read the page. A navigation held *after* its start (the brief's suggested "commit held past 0.5 s with a FixtureGate") does **not** beat it: `isLoading` is true for the whole hold, measured above. What beats it is a gap between the decision and the start: a cross-site navigation leaves one open for 62–77 ms on this machine while WebKit swaps web content processes, and the old page's answers are not ordered with the new process's start, so a loaded machine stretches it past any fixed window. `StepNavigationSettleTests` holds the navigation *decision* for 1.5 s through a test seam (`PageHostDelegate.holdDecision`) to reproduce that gap on any machine: red on the old code for scripts on and off (the load read `/step-navigation.html`, title "Step navigation fixture"), green after.

### What a trusted click delivers — `SLEEPY_MEASURE=1 swift test --filter TrustedClickMeasurement`

Fixture `click-trusted.html`; `TrustedInput.click(atViewport:)` on a live host.

| Question | Synthesized click (before) | Trusted click (now) |
|---|---|---|
| `isTrusted` | false | **true**, on every event |
| Event sequence | pointerdown, mousedown, pointerup, mouseup, click | pointermove, pointerdown, mousedown, pointerup, mouseup, click |
| Button in a `rotate(30deg) scale(1.5)` container (`#spin`) | reached (dispatched at the element) | reached: WebKit's hit test is transform-aware |
| Button under a transparent sheet (`#under`) | reached (dispatched through the sheet) | **the sheet gets the click**; a `--selector` click is now refused as `covered` |
| Button under a `pointer-events: none` sheet | reached | reached |
| Button inside an open shadow root, by `--at` | reached (descent, then dispatch) | reached (WebKit's own hit test) |
| `--at 100.75,40.25` | pointer events keep the fraction, mouse events and click truncate to 100,40 | **identical**: same split, so `ClickFractionalPointTests` passes unchanged |
| `buttons` on pointerdown/mousedown | 1 | **0** — WebKit reads the system's real button state, and no real button is down |
| Focus after clicking a `<button>` | the button (`element.focus()` was called) | **`body`** — Safari does not focus a button on click; a text field or link still takes focus |
| `:hover` afterwards | unchanged | **the clicked element** — the pointer stays where it clicked |
| Two clicks back to back | `detail` 1, no dblclick | `detail` 1 each, no `dblclick` (each event says `clickCount` 1) |
| Checkbox, scripts **off** | toggled (dispatchEvent ran the default action) | toggled |
| Link, scripts on and off | navigated; judged by page-side link test / host count | navigated; judged by the host count |
| Windowless host | clicked (no window needed) | **refused**, usage error naming `.windowless`; no script click in its place |
| Time per click | 0–1 ms page-side | 0–8 ms including the land-wait |

## Decisions

1. **The JavaScript click is retired, not kept as a fallback.** No measured case needs it: transforms, shadow roots, fractions, `--no-js` and navigation reporting all work at least as well; the windowless host is refused as the brief requires, never faked.
2. **A covered element is refused, not clicked through.** A real click on `#under` lands on the sheet. Clicking the sheet while reporting `#under` would be a plausible wrong answer; the `covered` refusal names what is on top (`<div>`), exits 1 and, as a step, is retried until the budget — so a toast that fades is waited for, as Playwright does. This is the same rule `--hover` already follows.
3. **Navigation is judged by the host for every click.** The page's own word (a submit watcher and a link heuristic) cannot see a trusted event's default action, and the host's policy-decision count is ordered and needs no listener. A submit the page cancels asks for no decision, so it still reports `false` (`ClickOperationTests`).
4. **Visible differences an existing user may notice, all of them what a user's click does:** focus no longer lands on a clicked button; the pointer stays over what was clicked, so a `shot` after a click shows its `:hover` style; `buttons` reads 0 during the press. None changed an existing test's outcome. The second is a product question (below).
5. **The settle's red test needs a seam.** `PageHostDelegate.holdDecision` is `nil` in production and lets a test hold a navigation decision; no FixtureGate placement reproduces the losing gap, because a held response keeps `isLoading` true.

## Open question for Ben

**Should the pointer stay where a click left it?** Today it does, as with `--hover` and as after a user's click, so `sleepy shot <url> --click '#menu'` captures the menu with its hover style. The alternative is to move the pointer off the page after each click, so a capture after a click shows no hover. Recommendation: keep it — it is what the page does for a real user, and `--hover` elsewhere is the explicit way to put the pointer somewhere else.

## Existing tests

- `ClickOperationTests` "the synthesized click is honest about being untrusted" became "the click arrives trusted, and lands on the element", asserting `isTrusted` true: the behavior the leaf exists to change.
- Every other click test passed unchanged, including `ClickFractionalPointTests` (the truncation canary), `ClickPointTests` (shadow descent, document space, refusals), `GeometrySpaceTests`, `PageScriptsTests` (`--no-js` click), `NavigationStartTests` and `PasteboardIsolationTests` (a click that copies).
