# Sleepy Hollow feedback from the viewer-polish session — 2026-08-30

Compiled for the Sleepy Hollow project from one day of heavy real-world use in
Woodcase: three agents authored or exercised ~50 browser tests against the
SleepyHollow package (`PageHost`, `LoadOptions`, `evaluate`, `ViewportSize`), and
the integrator drove the `sleepy` CLI for ~10 design-review screenshots. Sources:
each agent's report (leaves ShaCv/lzM1z, lS7YE, J1bCy, vWhGP/Qe32p, tree jdVsK)
and the session's shot workflow.

## What worked — keep this

- **`PageHost` + `LoadOptions(size:wait:budget:)` + `evaluate(_:in: .page)` is the
  right primitive set.** Every suite needed nothing else. 8 new browser tests
  against a live in-process server ran in ~2.7–2.9 s; 36 tests across six suites
  in 4.6 s; **zero flakes across the whole day**, including heavy suites run
  back-to-back and under parallel build load.
- **`evaluate` accepting a multi-statement body with `return` carries the whole
  testing style.** Agents pushed entire probes into the page — hit-test scans,
  bounding-rect geometry, composed diagnostic report strings — and got one string
  back. One agent's headline diagnosis ("presentation drew a 400 px artboard at
  20 px") came from a single `evaluate` returning a sentence. A
  single-expression API would have made these tests far worse.
- **Returning a diagnostic string beats returning a bool**: probes that answer
  `'front-truncated'` or `'scale 0.05, wanted 1.8 (…)'` made red runs
  informative. Worth showcasing in the docs as the house pattern.
- **`wait: .load` against a port-0 server** reliably gated page-ready state; no
  polling hacks, no spurious timeouts.
- **CLI:** `sleepy shot URL --size WxH --out f.png` is a one-liner per
  design-review shot, fast enough to retake freely; `--selector` cropped a single
  component correctly on the first try.

## Friction, in rough priority order

1. **No way to load a page with JavaScript disabled.** `LoadOptions` carries
   `size`, `theme`, `jar`, `scripts`, `dialogs`, `wait`, `budget`, `steps` —
   nothing for scripting. Progressive enhancement was a first-class acceptance
   criterion here, and "the page works with JS off" is exactly the claim a
   browser could settle; instead it was proven over `URLSession`, which tests the
   server's markup, not the browser's rendering of it. `LoadOptions.scripting:
   .off` would have turned a 133-line HTTP-level suite into three real browser
   tests.
2. **No keyboard act verb.** `click`/`fill`/`submit` exist; `press` does not.
   Every keypress in this repo is a hand-copied *untrusted*
   `KeyboardEvent` dispatch, now duplicated across four test files — and nothing
   built this way can ever exercise an `isTrusted` check or a real default
   action. `PageHost.press(_:)` would delete the duplication and raise fidelity.
3. **Two helpers every bench hand-writes belong in the package.** Five copies of
   the same 6-line `ask()` (decode `evaluate`'s JSON-text return) and of the same
   polling `waitFor(_:_:within:)` now exist in this one repo. An `evaluate`
   overload returning a decoded value, plus a built-in `waitUntil`, would delete
   all of them.
4. **A thrown JS body is indistinguishable from an empty answer.** A syntax
   error or an unsupported selector inside the evaluated body surfaces as `""`,
   so the failure reads as a mismatch against empty string. A typed error that
   survives into the test's failure message would have saved a debugging cycle.
5. **`evaluate` cannot tell a navigation from a same-document swap.** The
   client-side-navigation leaf's entire subject was "did the page reload?"; the
   only probe available was a self-stamped `window` marker, which silently fails
   for *back* navigations because WebKit's bfcache restores the document with its
   JS heap (recorded as a Woodcase gotcha). A `navigationCount` or an awaitable
   navigation event would make in-place-navigation testing a plain assertion.
6. **CSS transitions do not advance in the headless host.** An `opacity`
   transition never reached its end state in 30 s, in either direction — a
   property of a non-painting renderer, not of the page under test. It silently
   invalidates any test asserting an animated end state and deserves a loud
   paragraph in SleepyHollow's own docs; the workaround (assert the class change
   plus the stylesheet's transition rule) works but is discoverable only the
   hard way.
7. **No viewport resize after load.** Wanted for proving a `resize` listener
   refits content; there is no way to change `ViewportSize` on a live page.
8. **Point-clicks under CSS transforms are a trap** (adjacent, possibly out of
   scope): `MouseEvent.clientX` is an integer, so a click computed in fractional
   layout points on a sub-1-scaled canvas truncates into the wrong box.
   `sleepy`'s selector-based `click` sidesteps it, but there is no "click this
   document point" verb that accounts for a transformed ancestor, and nothing in
   the API warns about the truncation. Two Woodcase agents lost about an hour to
   it between them; the helper that solves it is quoted in Woodcase's
   `project/gotchas.md` (2026-08-30) if a `clickAt` verb ever wants a reference.
9. **Cosmetic:** `CFPasteboardSetExpirationDate returns error: Pasteboard
   already has contents.` is logged to stderr during clipboard-touching suites
   and reads like a failure in an otherwise clean `--quiet` run.
10. **CLI wishes:** no way to express hover/focus states or run an interaction
    before capture (verifying a hover-color fix and a client-side mode was
    impossible in a static shot — apps whose state lives in the URL shoot fine,
    anything else cannot be staged); a `--selector` crop captures at 1× CSS
    pixels, so judging sub-pixel work needs an external upscale — a
    `--scale`/`--zoom` flag would remove that step; and `--size` vs the
    misremembered `--viewport` suggests accepting both.

## Reproduction pointers

Concrete call sites for every item live in Woodcase at `9e9854c`:
`Tests/WoodcaseViewerTests/Viewer{Selection,Navigation,Presentation,Chrome,Keyboard}BrowserTests.swift`
(the `Bench` structs are the duplicated-helper exhibit), `ViewerScriptlessNavigationTests.swift`
(the JS-off workaround), and `project/gotchas.md` (bfcache and integer-clientX
entries, both dated 2026-08-30).
