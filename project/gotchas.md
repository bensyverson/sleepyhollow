# Gotchas

Project-specific traps that cost real time and that no general rule predicts. Read at session start; append when you hit one.

- **Fix at the source when you can.** A gotcha is a bug report on our tooling, not a permanent fact — if it can be fixed in code, file it in `job` and fix it instead of recording it here.
- **Delete anything that becomes obvious, gets fixed, or stops recurring.** Keep this list short; a long list is one nobody reads.
- **Feedback about `AGENTS.md` itself** — a rule that was wrong, misread, or cost time — goes here too, prefixed `rule:`. It is harvested when the shared rules are reviewed.

Format: one dated H2 per entry, a bold headline, then what happened and what to do instead.

---

## 2026-08-20

**`swift package` commands fail inside Claude Code's sandbox.** SwiftPM applies its own `sandbox-exec`, which the session sandbox refuses (`sandbox_apply: Operation not permitted`), and the user-level caches under `~/Library` are unreadable. Run `swift build` / `swift test` / `swift package …` with the sandbox disabled.

**Agents can't mark `job` criteria — only `job done` sets them.** Briefs ban agents from running `done`, and `job` has no standalone criterion-marking verb, so criteria stay pending until the integrator closes the leaf with `--criterion <label>=passed`. Write briefs so agents note "criteria factually met" and leave marking to the main thread.

**`swiftformat . --lint` silently lints nothing inside an agent worktree.** The repo `.swiftformat` excludes `.claude`, and worktrees live under `.claude/worktrees/`, so a bare lint there reports success while checking zero files. Inside a worktree, pass the config explicitly: `swiftformat . --lint --config .swiftformat`. Put this in every implementation brief.

**rule: the delegation guide's "push before dispatching" doesn't apply to this harness.** `project/agents/delegation.md` says worktrees branch from the last pushed commit on origin/main; Claude Code's worktree isolation actually branches from the *local HEAD* at dispatch time (verified: with no remote configured at all, agents received exactly the commit that was HEAD when dispatched). Commit before dispatching; pushing is backup, not a spawn requirement.

**`swiftformat` (writing, not linting) also needs the sandbox disabled in a worktree.** `--lint` reads and works; the fixing pass reports `error: Failed to write file …` for every file, because the session sandbox denies writes under `.claude/`. Same fix as `swift build`: run it with the sandbox off.

**Wall-clock assertions inflate 2–3× in the full suite.** Every WebKit test is `@MainActor` and Swift Testing runs suites in parallel, so ~130 tests contend for one actor: a load measured at 1.5 s with `--filter` measured 4.2 s in the full run, and tight bounds (`elapsed < 2.3`) fail only there. Assert *lower* bounds tightly (they are contention-proof), keep upper bounds generous (< 10 s), and when a test must prove *when* something settled, use the page's own late element as the clock instead of `Date()`.

**`requestAnimationFrame` never fires in a headless `WKWebView`** — no window, no rendering update, no callback (measured; `setTimeout` is unaffected and fires on time). A fixture that schedules anything through a rAF chain will hang until the budget. Use `setTimeout` or a fetch completion.

**Answer WebKit's delegate protocols with the exact SDK signature or you get no callbacks.** `WKUIDelegate`'s completion handlers are typed `@escaping @MainActor @Sendable`; a plain `@escaping (Bool) -> Void` compiles, produces only a "nearly matches optional requirement" *warning*, and then the dialog panels silently never fire. Treat that warning as an error.

**A Unix socket path over 103 bytes crashes `NWConnection`, and `NWListener` lies about it.** `NWConnection(to: .unix(path:))` traps (SIGTRAP inside Network.framework) when the path exceeds `sockaddr_un`'s `sun_path`, while `NWListener` happily reports `.ready` on a truncated path. `SessionRegistry.socketPath(for:)` now refuses such a path with a teaching error — keep any new socket path behind that check, and keep test registry roots short (the system temp directory already spends ~48 bytes).

**`WKWebView.takeSnapshot` rasterizes at the host Mac's screen backing scale factor, not 1 point = 1 pixel, even though the view is never attached to a screen.** Measured (`swiftc -typecheck` a probe, then real captures against `capture-tall.html`): a bare 1280×800-point viewport snapshot came back 2560×1600 pixels on a Retina host. `WKSnapshotConfiguration.snapshotWidth` does **not** fix this — it only relabels the returned `NSImage`'s logical size; the backing raster stays at the host's scale. Fix: re-render the `NSImage` into a fresh `NSBitmapImageRep` built at the exact target pixel size (`ShotOperation.pngData(rendering:atPixelSize:)`) before encoding to PNG. Without this, `sleepy shot`'s output pixel dimensions depend on which Mac ran the command — a determinism-by-construction violation (vision doc §5).

**WebKit tests are bounded by `TestSupport.WebKitGate` — route every WebKit test through `FixtureServer.withRunning` or it escapes the bound.** The old golden-test contention flakes (subprocess storms blowing 30s budgets, wait-family timeouts under parallel-agent load) were fixed 2026-08-20 by capping concurrent WebKit instances at the `withRunning` choke point; width and measurements live in `WebKitGate`'s DocC. What remains true: keep `--budget 60000` on golden subprocess invocations, keep wall-clock upper bounds generous, and a new test apparatus that spawns WebKit outside `withRunning` reopens the whole class.
**rule: the formatter overrules "no `.init()` shorthand".** `AGENTS.md` says to spell the type out; swiftformat's `redundantType` rule rewrites `static let x: AXState = AXState(…)` back to `= .init(…)` and then `--lint` fails until you accept it. The formatter is the pre-commit gate, so let it win and don't fight it file by file.

**`git` also needs the sandbox disabled, not just SwiftPM.** Any git command that reads config (`commit`, `merge`, …) dies on `unable to access '~/.gitconfig': Operation not permitted` under the session sandbox. Same fix as `swift build`; put it in every implementation brief's environment facts.

**Every `job` write on a claimed task needs `--as <claimant>`, not just claim/release.** A bare `job note <id>` against a task claimed `--as jars` fails with "task is claimed by jars". Briefs that show `job note` without the identity are wrong.

