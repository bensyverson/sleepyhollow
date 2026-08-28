# Gotchas

Project-specific traps that cost real time and that no general rule predicts. Read at session start; append when you hit one.

- **Fix at the source when you can.** A gotcha is a bug report on our tooling, not a permanent fact — if it can be fixed in code, file it in `job` and fix it instead of recording it here.
- **Delete anything that becomes obvious, gets fixed, or stops recurring.** Keep this list short; a long list is one nobody reads.
- **Feedback about `AGENTS.md` itself** — a rule that was wrong, misread, or cost time — goes here too, prefixed `rule:`. It is harvested when the shared rules are reviewed.

Format: one dated H2 per entry, a bold headline, then what happened and what to do instead.

---

## 2026-08-20

**`swiftformat . --lint` silently lints nothing inside an agent worktree.** The repo `.swiftformat` excludes `.claude`; inside a worktree pass the config explicitly: `swiftformat . --lint --config .swiftformat`. Put this in every implementation brief.

**`swiftformat` (writing, not linting) also needs the sandbox disabled in a worktree.** `--lint` reads and works; the fixing pass reports `error: Failed to write file …` for every file, because the sandbox denies writes under `.claude/`.

**`requestAnimationFrame` never fires in a *windowless* `WKWebView`** — no window, no rendering update, no callback (measured; `setTimeout` is unaffected and fires on time). That is every verb's default, so a fixture that schedules anything through a rAF chain will hang until the budget: use `setTimeout` or a fetch completion. A view hosted by `PageHost.ensureOffscreenWindow()` is the exception — rAF fires at ~60Hz there and CSS transitions advance on the wall clock, but only because `OffscreenWindow` also turns off window-occlusion detection; the window alone changes nothing (measured 2026-08-28, `project/2026-08-28-offscreen-window-host.md`).

**Answer WebKit's delegate protocols with the exact SDK signature or you get no callbacks.** `WKUIDelegate`'s completion handlers are typed `@escaping @MainActor @Sendable`; a plain `@escaping (Bool) -> Void` compiles, produces only a "nearly matches optional requirement" *warning*, and then the dialog panels silently never fire. Treat that warning as an error.

**A Unix socket path over 103 bytes crashes `NWConnection`, and `NWListener` lies about it.** `NWConnection(to: .unix(path:))` traps (SIGTRAP inside Network.framework) when the path exceeds `sockaddr_un`'s `sun_path`, while `NWListener` happily reports `.ready` on a truncated path. `SessionRegistry.socketPath(for:)` now refuses such a path with a teaching error — keep any new socket path behind that check, and keep test registry roots short (the system temp directory already spends ~48 bytes).

**`WKWebView.takeSnapshot` rasterizes at the host Mac's screen backing scale factor, not 1 point = 1 pixel, even though the view is never attached to a screen.** Measured (`swiftc -typecheck` a probe, then real captures against `capture-tall.html`): a bare 1280×800-point viewport snapshot came back 2560×1600 pixels on a Retina host. `WKSnapshotConfiguration.snapshotWidth` does **not** fix this — it only relabels the returned `NSImage`'s logical size; the backing raster stays at the host's scale. Fix: re-render the `NSImage` into a fresh `NSBitmapImageRep` built at the exact target pixel size (`ShotOperation.pngData(rendering:atPixelSize:)`) before encoding to PNG. Without this, `sleepy shot`'s output pixel dimensions depend on which Mac ran the command — a determinism-by-construction violation (vision doc §5).

**WebKit tests are bounded by `TestSupport.WebKitGate` — route every WebKit test through `FixtureServer.withRunning` or it escapes the bound.** The old golden-test contention flakes (subprocess storms blowing 30s budgets, wait-family timeouts under parallel-agent load) were fixed 2026-08-20 by capping concurrent WebKit instances at the `withRunning` choke point; width and measurements live in `WebKitGate`'s DocC. What remains true: keep `--budget 60000` on golden subprocess invocations, keep wall-clock upper bounds generous, and a new test apparatus that spawns WebKit outside `withRunning` reopens the whole class.

**rule: the formatter overrules "no `.init()` shorthand".** `AGENTS.md` says to spell the type out; swiftformat's `redundantType` rule rewrites `static let x: AXState = AXState(…)` back to `= .init(…)` and then `--lint` fails until you accept it. The formatter is the pre-commit gate, so let it win and don't fight it file by file.

**`Process.waitUntilExit()` in a golden test hangs forever once the test has awaited a subprocess.** `SessionHelperProcess.kill()` used to SIGKILL the helper and then `waitUntilExit()`; in a test that had already `await`ed a `GoldenBinary.runOffPool` call, the wait never returned even though the helper was gone (`sample` showed 100% of samples parked in `-[NSConcreteTask waitUntilExit]`). NSTask's termination bookkeeping is not reliable across the queue hops a resumed continuation makes. Ask the question you actually have instead: `SessionHelperProcess.killAndAwaitDeath(_:)` signals, then polls `SessionRegistry.liveness(of:)` with `Task.sleep`. Never call `waitUntilExit` from a cooperative thread — that is also the rule `GoldenBinary.runOffPool` exists for.

**An `@Option`/`@Flag` read on an unparsed `ParsableArguments` traps.** `LoadFlagOptions()` compiles fine and then crashes the moment anything reads `flags.theme`: ArgumentParser's property wrappers are only valid after parsing. So a default parameter of `LoadFlagOptions()` is a landmine (`PageExecution` takes `LoadFlagOptions?` instead), and a unit test that needs an option group builds it with `try LoadFlagOptions.parse(["--theme", "dark"])`, never with the initializer.

**A helper spawned by `sleepy open` must ignore `SIGPIPE`.** `open` reads the helper's stdout for the readiness line and then exits, closing its end of the pipe; anything the helper wrote afterwards would kill it seconds after the session opened. `HostCommand.detachFromSpawner()` sets `signal(SIGPIPE, SIG_IGN)` right after announcing.


---

## 2026-08-28

**rule: "Modern Swift Regex, not the legacy APIs" does not apply in this package.** `Regex` and the `contains(_:)`/`firstMatch` family are `@available(macOS 13, *)`, and `Package.swift` sets the floor at macOS 12 — a regex literal in a library type fails to build three ways at once (availability, and `Regex` being non-`Sendable` in a `static let`). For a small lexical decision, hand-roll the scan; `@available` gating a core type is not worth it while the floor is 12.

**`#expect(aDouble == aCGFloat)` fails even when both are 2.0.** Swift's implicit `Double`/`CGFloat` conversion works in plain code (`ratio == window.backingScaleFactor` is `true` in a `print`) but not inside Swift Testing's macro: the same comparison in an `#expect` records `Expectation failed: (ratio → 2.0) == (window.backingScaleFactor → 2.0)`, in either operand order. Isolated and reproduced 2026-08-28 while measuring the off-screen window host. Convert explicitly — `#expect(Double(window.backingScaleFactor) == ratio)` passes — and treat any AppKit/CoreGraphics geometry value crossing into an `#expect` the same way.
