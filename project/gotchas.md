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

**Answer WebKit's delegate protocols with the exact SDK signature or you get no callbacks.** `WKUIDelegate`'s completion handlers are typed `@escaping @MainActor @Sendable`; a plain `@escaping (Bool) -> Void` compiles, produces only a "nearly matches optional requirement" *warning*, and then the dialog panels silently never fire. Treat that warning as an error.
