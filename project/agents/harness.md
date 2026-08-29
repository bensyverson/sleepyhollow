<!-- agents:begin harness@ea582f -->
# Harness facts

Facts about the tool an agent runs *inside*, not about this project — they are identical in every repo, which is why they are not in `project/gotchas.md`. One section per harness; today there is only Claude Code. Read this the first time a call fails with a permission error or a refusal you did not expect: none of these failures names the harness, which is exactly what makes them expensive.

## Claude Code

### The Bash sandbox

Bash calls are sandboxed by default. The sandbox denies reads of the user's home outside a short allowlist, denies writes outside the repo and `$TMPDIR`, and refuses to listen on or connect to a local port. So these fail sandboxed: any toolchain whose caches live under `~/Library` or `~/go` (Go, SwiftPM), every `git` command that reads `~/.gitconfig`, `psql` over its unix socket, anything that binds a port, `curl localhost`, and a tool installed outside the allowlist (`sleepy` is on `$PATH` but its directory is unreadable).

Recognise the messages — each reads like a broken install, a corrupt config or a dead server:

- `fatal: unable to access '…/.gitconfig': Operation not permitted` — git
- `open …/Library/Caches/go-build/…: operation not permitted`, or `package fmt is not in std` — Go
- `sandbox_apply: Operation not permitted` — SwiftPM applying its own sandbox inside the session's
- `connection to server on socket "/tmp/.s.PGSQL.5432" failed: Operation not permitted` — psql
- `command not found` for a binary that is on `$PATH` — its directory is unreadable

The fix is always the same: re-run **that one call** with the sandbox disabled and leave everything else sandboxed. Never invent cache or `HOME` redirects to make a toolchain work in-sandbox — verified 2026-08-28 in this repo, `GOCACHE`/`GOTELEMETRYDIR` only moves the denial to the module cache, and `GOPROXY=off` does not help because the denial is the cache, not the network. File edits and `job` run fine sandboxed.

### `$TMPDIR`

`$TMPDIR` names a *different directory* in each mode — `/tmp/claude-501` sandboxed, the real per-user temp dir with the sandbox off (both verified 2026-08-28). A file written in one mode is invisible in the other, and the name may already hold a stale file from an earlier session; that has appended a days-old report to a `job` task twice. Write scratch to an absolute path, never `$TMPDIR/<short name>`. Parallel agents share one scratchpad directory, so prefix every file with your leaf id (`abc12-commitmsg.txt`) and read back any file before you pass it to `-F`.

### No keyboard

The `!` runner and `ssh -t` give a command no TTY: stdin reads EOF. A tool with a typed-confirmation guard prints its prompt and aborts, and `sudo` over ssh fails with `a terminal is required to read the password`. Ask the user to run it in a real terminal and paste the output. Never wrap it in `script` or a pseudo-TTY — that guard exists so a human is at the keyboard.

### Worktree isolation

An agent given its own worktree runs under a second check, on top of the sandbox, that every command stays in that worktree. Some isolation modes refuse a command they cannot verify — *"this command is too complex to verify that it stays inside the worktree"* — which reads like a sandbox denial and invites `dangerouslyDisableSandbox`; that does not help. Split it into plain calls and use the `Write` tool for file bodies rather than `cat > file <<EOF`. How much trips it varies by mode: at its strictest `&&`, `;`, loops and heredoc-plus-command are all refused; on 2026-08-28 here only a `for` loop was, while `&&`, `;`, a pipe and a heredoc all ran. Two neighbours have their own messages: pointing git at the shared checkout (`git -C /path/to/main …`) is refused, and so is writing to a shared-checkout path — the tool tells you to edit the worktree copy.

Four more. A worktree lives under `<repo>/.claude/worktrees/<name>`, so any tool config that excludes dot-directories excludes the whole worktree — a linter or formatter run there reports success having checked zero files; pass the config explicitly. The shell's cwd resets between calls, so nothing carries over from an earlier `cd` — every path in a brief is absolute. The worktree branches from **local HEAD at dispatch**, not from `origin/main`, so commit before dispatching; a *remote* agent (`isolation: remote`, or a session on another machine) clones from `origin`, so push before dispatching one of those. And gitignored files do not exist in a worktree — `.jobs.db`, `local/`, dev databases — so pass every such path absolute, and never "fix" a missing one by re-initialising it.

### Models

The main thread runs the top tier; subagents run Opus — judgment calls, contended seams, anything fail-closed — or Sonnet for mechanical, well-specified edits. Never give an agent the main thread's tier: the integrator's read of the merged diff is the expensive step, so that is where the top tier is spent. Which tier is which changes with the lineup; check before assuming.

### Long-running processes

A backgrounded process is reaped when the session ends, so a server meant to outlive it must be detached (`nohup … >/dev/null 2>&1 & disown`). Never clean up with `pkill -f <pattern>`: the pattern matches other agents' processes and the shared dev server in the main checkout, which then goes down silently. Kill by port (`lsof -ti :<port> | xargs kill`) or by pid. `go run` execs a compiled binary from a temp path, so a `pkill -f` on the source pattern misses the process actually holding the port, and you keep talking to a stale server.
<!-- agents:end harness -->
