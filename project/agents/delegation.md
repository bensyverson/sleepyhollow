<!-- agents:begin delegation@486ea0 -->
# Delegating to subagents

Read this before dispatching agents. Every rule here was paid for. `project/agents/jobs.md` covers the tracker the work is filed in; `project/agents/harness.md` covers the tool the agents run inside.

## What to delegate

- **Delegate a sub-problem that needs no user interaction**, has clear success criteria, takes multiple steps, and involves no design decisions.
- **Keep on the main thread** anything that is a design decision, a question for the user, a single tool call, or a chain of sequential dependencies.
- **Read across every open tree before dispatching**, not just the one `job orient` pointed at — sibling trees that aren't blocked are parallel work that doesn't announce itself.
- **Check a leaf's premise before you delegate it.** A leaf can dissolve on contact — the problem is already solved, or the plan moved past it — and an agent will build what it is told regardless.
- **Match the model to the failure-mode stakes, not to how mechanical the task looks.** Fail-closed wiring reads like plumbing and isn't.

## Carving the work

- **Fanning out is a decision, not a default.** A worktree stops one agent's red tests from breaking another's build; it does nothing about merge conflicts. A fan-out costs a brief, a worktree and an integration per agent, so small or contended work is faster serial.
- **Map the file surface of every candidate leaf before you dispatch anything.** Different files parallelize provably; the same file in distant regions usually applies but is not guaranteed; the same function or region is a genuine conflict.
- **Parallelize only the disjoint set and serialize the rest.** A carve that leaves most leaves serial is a normal outcome, not a failure.
- **For a contended file, carve the contention out before dispatching**, in this order of preference:
  - **Route each agent's additions into a new file of its own.** Same package, different files — it merges cleanly, and it works for additive work only.
  - **Pre-carve the shared seam** in one serial commit up front that creates the insertion points, then fan out. This is the general answer to a same-region collision.
  - **Reserve the file to a single writer**, and tell the others to code against its interface and describe the line they need instead of writing it. The cheapest single writer is the integrator: agents return the exact text as an *integration note* and it is applied at merge time — README rows, a one-line wiring call.
- **Tell every agent which files another agent owns and what not to build.** An unstated boundary is not a boundary.
- **One agent carries several leaves when they live in the same files** — merge cost, not task count, decides the split. Agents are assigned by file ownership; leaves are units of work.
- **Carving occasionally mints a new leaf for a piece of a task, but rarely** (`job split`). Prefer it to quietly widening one leaf's scope, and don't let the carve become a replan.

## Workflow

1. **Settle ambiguity with the user before dispatching**, and record each decision as a `job note` on the target leaf. An agent that returns with a flagged question instead of a guess is working correctly.
2. **Commit before dispatching.** A harness-made worktree branches from **local HEAD at dispatch**; a hand-made one branches from whatever you name in `git worktree add` — that is `main`, not `origin/main`. Either way the stale base is exactly your uncommitted work; pushing is backup, not a spawn requirement.
3. **One worktree per parallel agent**, so one agent's red tests can't break another's build. Run them in the background; the carve above, not the worktree, decides which of them run at the same time. To make one by hand: `git worktree add .claude/worktrees/<name> -b wt/<name> main`; to remove it after integration: `git worktree remove --force .claude/worktrees/<name>` and `git branch -D wt/<name>`.
4. **Book the work in `job` before you dispatch, and give each agent a unique `--as` and an absolute `--db`.** See `project/agents/jobs.md` for the identity rules, what an agent may and may not run, and the container-plus-work-leaves a fan-out mints.
5. **Agents don't commit.** They return a summary, the worktree path and branch, and **every new file listed by path** (`git diff` omits untracked files); the work itself travels back as a branch (step 6), so the report needs no pasted diff. Run `git -C <worktree> status --porcelain | grep '^??'` yourself; trust neither alone.
6. **Integrate by merging the agent's branch.** Wip-commit its worktree with hooks off — `git -C <worktree> add -A`, then `git -C <worktree> -c core.hooksPath=/dev/null commit -m wip` — then on main `git merge --no-ff --no-commit <the agent's branch>` (`wt/<name>` for a worktree you made; ask the agent for the name of one the harness made) and resolve conflicts properly. Read the whole staged diff before committing: that reading *is* the code review, and it is the only place an agent's work gets one. Commit each merge before starting the next — git refuses a second merge over a staged one.
7. **Then run the full suite once over the combined result, commit, remove the worktrees, and close the leaves.** Verify load-bearing claims independently — agent reports and numbers can be subtly wrong. Weigh an agent's pushback rather than adopting it: telling an agent its brief is probably wrong primes it to manufacture criticism, and an agent without the full picture sometimes needs to be told to revise or redo the work.

## Traps

- **The agent shell's cwd resets between calls, and where it starts depends on who made the worktree** — the worktree itself when the harness made it, possibly the main checkout when you made it by hand. So every path in a brief is absolute or `git -C <worktree>`.
- **Never prefix a command with `cd /path/to/main/checkout &&`.** That prefix silently retargets the MAIN checkout — mutating tracked files there, or making `go test` quietly test main's code so wrong-reason-green tests read as passes.
- **Gitignored files don't exist in a worktree** — `.jobs.db`, `local/`, dev databases. Pass every such path absolute, and never "fix" a missing one by re-initialising it.
- **Parallel agents share one scratch directory.** Prefix every scratch file with your leaf id (`kdrp5-commitmsg.txt`), and read back any file before you pass it to `-F`; a generic name is clobbered without warning.
- **Restate anything the agent cannot proceed without.** A leaf description the agent can't read is not a brief; load-bearing instructions go in the prompt or a committed file.
- **Keep the sync preamble in every prompt** (`git merge --ff-only main`, falling back to `git rebase main`); it makes a missed commit survivable. A clean base report may only describe state *after* syncing, so it isn't evidence of a clean spawn.
- **Don't take the work back with `git apply`.** It is atomic and prints per-file "Applied cleanly" right up to the moment it discards everything, and a partial `-3` leaves a half-applied tree; merge the branch instead (step 6).
- **Parallel migrations use placeholder numbers** (`900_`, `901_`), renumbered sequentially at integration with the placeholder comment stripped. Never let a placeholder reach a persistent dev DB. Safe only where the migration runner records one row per version rather than a high-water mark; check before relying on it.
- **The pre-commit hook must never recurse into `.claude/worktrees/`** — a running agent's half-written file will fail the main thread's unrelated commit. If you add a check to the hook, check whether it recurses; skipping dot-directories is what the Go toolchain itself does.
- **Subagent isolation is not airtight.** An agent given a worktree can still write to absolute paths in the main checkout; brief it to stay in its cwd.
- **A permission denial or a "too complex to verify" refusal is a harness fact, not a project one.** They are in `project/agents/harness.md`; point agents at it rather than re-deriving them per repo.

## Briefing template

Every prompt carries this boilerplate; each line was paid for.

```
You are working in worktree <abs path> on leaf <id>. Identity: --as <name>.
Sync first: git merge --ff-only main (if it fails, git rebase main) — as separate calls.
Jobs DB: always pass --db <abs path>/.jobs.db. Claim: job claim <id> --as <name>.
HARNESS: read project/agents/harness.md — sandbox, $TMPDIR and worktree isolation.
Split compound commands into plain calls and use the Write tool for file bodies.
Do not cd into the main checkout. Do not commit. Do not run job done.

TASK: <goal, in one paragraph>
VERIFIED FACTS: <real counts, timestamps, invariants that must hold — not just the goal>
DO NOT BUILD: <explicit exclusions>; <files owned by other agents>
TDD: red first; if a new test is green on first run, say so — that is a claim about rigour.

Your report must include:
1. A summary of what changed and why — not the diff; the branch carries it.
2. Every new file, by path.
3. Whether the suite passed and which command you ran.
4. The worktree path and its branch name.
5. DEVIATIONS from this brief, and why.
6. WHAT IN THIS BRIEF IS WRONG? Answer explicitly. Briefs contain errors at a rate that makes this the cheapest check available; if a seam does not work the way this describes, say so rather than working around it. Fix minor bugs as you encounter them, and report the major ones.
```
<!-- agents:end delegation -->
