<!-- agents:begin delegation@89d0e0 -->
# Delegating to subagents

Read this before dispatching agents. Every rule here was paid for.

## What to delegate

- **Delegate a sub-problem that needs no user interaction**, has clear success criteria, takes multiple steps, and involves no design decisions.
- **Keep on the main thread** anything that is a design decision, a question for the user, a single tool call, or a chain of sequential dependencies.
- **Assign by files, not one agent per task.** Isolation by file ownership is what makes the merge easy, so bundle tasks that touch the same files into one agent, and consider decomposing a task that spans many files into pieces handed to the agents already working there.
- **Read across every open tree before dispatching**, not just the one `job orient` pointed at — sibling trees that aren't blocked are parallel work that doesn't announce itself.

## Workflow

1. **Settle ambiguity with the user before dispatching**, and record each decision as a `job note` on the target leaf. An agent that returns with a flagged question instead of a guess is working correctly.
2. **Commit AND push.** A worktree branches from the last *pushed commit* on `origin/main`, not from your working tree — so the stale base is exactly your unpushed distance, and it grows during a session. Push before dispatching and again before any later wave.
3. **One worktree per parallel agent**, so one agent's red tests can't break another's build. Run in the background, in parallel where file sets are disjoint. Say what NOT to build and which files another agent owns. A worktree needs a commit to branch from; before the first commit, or for a docs-only wave, disjoint directories in the main tree work — the isolation that matters is file ownership.
4. **Unique `--as` identity per agent, and an absolute `--db`.** `.jobs.db` is usually gitignored, so it does not exist in a worktree — pass `--db /abs/path/.jobs.db` on every call. The agent claims its own leaf (`job claim <id> --as <name>`), notes progress, and releases it (`job release <id> --as <name>`) when finished; agents `claim` and `note`, never `done`. They hand the work back to the integrator, who closes leaves after the suite passes and the commit lands.
5. **Agents don't commit.** They return a diff, a summary, and **every new file listed by path** (`git diff` omits untracked files). Run `git -C <worktree> status --porcelain | grep '^??'` yourself; trust neither alone.
6. **Integrate, run the full suite once over the combined result, commit, push, then close leaves.** Verify load-bearing claims independently — agent reports and numbers can be subtly wrong.

## Traps

- **In a worktree, never prefix a command with `cd /path/to/main/checkout &&`.** The agent shell's cwd resets between calls, and that prefix silently retargets the MAIN checkout — mutating tracked files there, or making `go test` quietly test main's code so wrong-reason-green tests read as passes. Use paths relative to the worktree, or `git -C <worktree>`.
- **Gitignored files don't exist in a worktree** — `.jobs.db`, `local/`, dev databases. `job` resolves `--db` relative to cwd and fails loudly there; never "fix" it with `job init`, which creates a second empty database. Same for any tool flag that takes a local path: pass it absolute.
- **Restate anything the agent cannot proceed without.** A leaf description the agent can't read (see above) is not a brief. Load-bearing instructions go in the prompt or a committed file.
- **Keep the sync preamble in every prompt** (`git merge --ff-only main`, falling back to `git rebase main`); it makes a missed push survivable. A clean base report may only describe state *after* syncing, so it isn't evidence of a clean spawn.
- **`git apply` is atomic and prints per-file success right up to the moment it discards everything.** Read the exit status; any error line invalidates every success line above it. A `-3` CONFLICT leaves the tree partially applied; a hard error aborts all of it. Verify by grepping for a symbol the patch adds, not by `git status` (which shows the union of every agent's edits). Where several agents touch one shared file, resolve and `git add` it FIRST.
- **Parallel migrations use placeholder numbers** (`900_`, `901_`), renumbered sequentially at integration with the placeholder comment stripped. Never let a placeholder reach a persistent dev DB. Safe only where the migration runner records one row per version rather than a high-water mark; check before relying on it.
- **The pre-commit hook must never recurse into `.claude/worktrees/`** — a running agent's half-typed file will fail the main thread's unrelated commit. If you add a check to the hook, check whether it recurses. Skipping dot-directories is what the Go toolchain itself does, which is why `go vet ./...` and `go test ./...` never had the problem.
- **Subagent isolation is not airtight.** An agent given a worktree can still write to absolute paths in the main checkout; brief it to stay in its cwd.

## Briefing template

Every prompt carries this boilerplate; each line was paid for.

```
You are working in worktree <abs path> on leaf <id>. Identity: --as <name>.
Sync first: git merge --ff-only main || git rebase main.
Jobs DB: always pass --db <abs path>/.jobs.db. Claim: job claim <id> --as <name>.
Do not cd into the main checkout. Do not commit. Do not run job done.

TASK: <goal, in one paragraph>
VERIFIED FACTS: <real counts, timestamps, invariants that must hold — not just the goal>
DO NOT BUILD: <explicit exclusions>; <files owned by other agents>
TDD: red first; if a new test is green on first run, say so — that is a claim about rigour.

Your report must include:
1. The diff and a summary.
2. Every new file, by path.
3. Whether the suite passed and which command you ran.
4. WHAT IN THIS BRIEF IS WRONG? Answer explicitly. Briefs contain errors at a rate that makes this the cheapest check available; if a seam does not work the way this describes, say so rather than working around it. Fix minor bugs as you encounter them, and report the major ones.
```

Honest caveat on item 4: telling an agent its brief is probably wrong primes it to manufacture criticism. Keep this in mind as you’re integrating its changes, and use your judgment. The agent may not have the full picture, so you may sometimes need to push back on its feedback and ask it to revise or redo work.
<!-- agents:end delegation -->
