<!-- agents:begin delegation@08a7b3 -->
# Delegating to subagents

Every rule here was paid for. Five hold even if you read nothing else:

- **Commit before dispatching** — a worktree branches from local HEAD, so uncommitted work is invisible to the agent.
- **Agents never commit.** They return a branch, a report and a proposed commit message.
- **The integrator makes every commit on `main`:** `git merge --squash` the agent's branch and read the whole staged diff — that read *is* the code review.
- **Verify what comes back.** Require **deviations from the brief** and **"what in this brief is wrong?"** in every report; the pushback, not the typing, is usually the value.
- **Findings go back to their finder.** A small bug an agent reports in or near its own files is fixed by that agent, on its branch, before the merge — not filed. It holds the exact context; close more leaves than you open.

`project/agents/jobs.md` covers the tracker the work is filed in; `project/agents/harness.md` covers the tool the agents run inside.

## What to delegate

- **Delegate a sub-problem that needs no user interaction**, has clear success criteria, takes multiple steps, and involves no design decisions.
- **Keep on the main thread** a design decision, a question for the user, or a single tool call. **A chain of dependent leaves goes to one agent, in order, as far as a session allows** — not one agent per link.
- **If you can name the exact edit, make it yourself.** Writing the brief is the checkpoint: when its TASK paragraph names the edit, the brief costs as much as the work, and the agent adds a worktree and a first build on top. Batch such edits into one build on the main thread.
- **Read across every open tree before dispatching**, not just the one `job orient` pointed at — sibling trees that aren't blocked are parallel work that doesn't announce itself.
- **Check a leaf's premise before you delegate it.** Read its description, criteria and every note (`job show <id>`), never just its title, and settle any question its notes leave open with the user first. A leaf can dissolve on contact — the problem is already solved, or the plan moved past it — and an agent will build what it is told regardless. When `job orient` is too long to read whole, read the target and every task it points to before acting on any of them.
- **Match the model to the failure-mode stakes, not to how mechanical the task looks.** Fail-closed wiring reads like plumbing and isn't. Which tiers exist and which one the main thread keeps is a harness fact — `project/agents/harness.md`, Models.

## Carving the work

- **Fanning out is a decision, not a default.** A worktree stops one agent's red tests from breaking another's build; it does nothing about merge conflicts. A fan-out costs, per agent, a brief, a worktree and its first build, a suite run, and an integration with a full-diff review. Weigh every split against that, not against zero.
- **Let build cost set how wide you fan out.** Judge what one agent's first build in a fresh worktree costs — wall time, CPU, disk — and how builds slow each other when they overlap. Judge it from what you already know: the repo's `AGENTS.md` head, which states its build cost, or earlier agents' reports. Never run a build just to find out. Where builds are cheap, a wide fan-out is often the fastest plan. Where they are expensive, run fewer agents with more work each, and stagger them: dispatch the next one when the previous one's first build finishes, not after a fixed delay. If the head gives no figure, have the first agent report how long its first build took, and add that to the head.
- **Map the file surface of every candidate leaf before you dispatch anything.** Different files parallelize provably; the same file in distant regions usually applies but is not guaranteed; the same function or region is a genuine conflict.
- **Size each candidate leaf before you carve.** Estimate the context it must read, the files it changes, the builds it waits on, and whether it carries a decision for the user. Pack each agent to well under 40% of its context window: several small unrelated fixes can share one agent, and a hard area gets its own.
- **Carve into a roster of agents, not a list of leaves.** Group leaves by the files they own, then merge groups that share context (subsystem, docs, test suite) up to that budget. A leaf too small to pay for its own agent rides with a neighbor; issues are filed one per defect and grouped here, at claim time. Record the roster (agent → leaves, in order) as a note on the container.
- **Parallelize only the disjoint set and serialize the rest.** A carve that leaves most leaves serial is a normal outcome, not a failure.
- **For a contended file, carve the contention out before dispatching**, in this order of preference:
  - **Route each agent's additions into a new file of its own.** Same package, different files — it merges cleanly, and it works for additive work only.
  - **Pre-carve the shared seam** in one serial commit up front that creates the insertion points, then fan out. This is the general answer to a same-region collision.
  - **Reserve the file to a single writer**, and tell the others to code against its interface and describe the line they need instead of writing it. The cheapest single writer is the integrator: agents return the exact text as an *integration note* and it is applied at merge time — README rows, a one-line wiring call.
- **Tell every agent which files another agent owns and what not to build.** An unstated boundary is not a boundary.
- **When a running agent stops at a decision, resume it while its context is under about 40% full; past that, give the rest to a fresh agent** with a written summary of the state, the decisions made and what's left. Re-reading costs less than reasoning that loosens as context fills. The integrator holds itself to the same line: past 40%, write the handoff rather than start another wave.
- **Carving occasionally mints a new leaf for a piece of a task, but rarely** (`job split`). Prefer it to quietly widening one leaf's scope, and don't let the carve become a replan.

## Workflow

1. **Settle ambiguity with the user before dispatching**, and record each decision as a `job note` on the target leaf. An agent that returns with a flagged question instead of a guess is working correctly.
2. **Commit before dispatching.** A harness-made worktree branches from **local HEAD at dispatch**; a hand-made one branches from whatever you name in `git worktree add` — that is `main`, not `origin/main`. Either way the stale base is exactly your uncommitted work. (A remote agent clones from `origin` instead — see `project/agents/harness.md`.)
3. **One worktree per parallel agent**, so one agent's red tests can't break another's build. Run them in the background; the carve above, not the worktree, decides which of them run at the same time. To make one by hand: `git worktree add .claude/worktrees/<name> -b wt/<name> main`; to remove it after integration: `git worktree remove --force .claude/worktrees/<name>` and `git branch -D wt/<name>`.
4. **Book the work in `job` before you dispatch, and give each agent a unique `--as` and an absolute `--db`.** See `project/agents/jobs.md` for the identity rules, what an agent may and may not run, and the container-plus-work-leaves a fan-out mints.
5. **Agents don't commit; the integrator makes every commit that reaches `main`.** They return a summary, the worktree path and branch, **every new file listed by path** (`git diff` omits untracked files), and a **proposed commit message** for the integrator to edit — the agent knows what changed and why; the work itself travels back as a branch (step 7), so the report needs no pasted diff. Run `git -C <worktree> status --porcelain | grep '^??'` yourself; trust neither alone.
6. **Send small findings back before you integrate.** Read the report's loose ends first; each small one in or near the agent's files goes back to that agent to fix on its branch — a message restarts a finished agent, and its worktree must still exist. File a new leaf only for another surface or a decision for the user, with `--found-in` naming the agent's leaf; widen a running agent's leaf rather than minting a sibling.
7. **Integrate by squash-merging the agent's branch.** Snapshot its worktree as a bare commit object, which runs no hook and moves no branch — `git -C <worktree> add -A`, then `git -C <worktree> write-tree`, then `git -C <worktree> commit-tree <that tree> -p HEAD -m wip` — then on main `git merge --squash <the printed commit>` and resolve conflicts properly. (A `-c core.hooksPath=/dev/null` commit reads as a safety bypass and is refused; a commit through the hook reruns, in the worktree, tests the agent just ran.) Read the whole staged diff before committing: that reading *is* the code review, and it is the only place an agent's work gets one. Then commit through the hooks with a real message, starting from the agent's proposed one; the squash keeps `main` linear, and the snapshot is an unreferenced object that git collects. Commit each squash before starting the next — git refuses a second merge over a staged one. Where the repo's hook runs a slow suite, several squashes whose files don't overlap can defer it to the batch's last commit, if the repo offers a switch for that (its `AGENTS.md` head names it); that last commit then tests the combined tree.
8. **Then run the full suite once over the combined result (the pre-commit hook, where the repo has one), push, remove the worktrees and their branches, and close the leaves.** Verify load-bearing claims independently — agent reports and numbers can be subtly wrong. Weigh an agent's pushback rather than adopting it: telling an agent its brief is probably wrong primes it to manufacture criticism, and an agent without the full picture sometimes needs to be told to revise or redo the work.

## Traps

- **The agent shell's cwd resets between calls, and where it starts depends on who made the worktree** — the worktree itself when the harness made it, possibly the main checkout when you made it by hand. So every path in a brief is absolute or `git -C <worktree>`.
- **Never prefix a command with `cd /path/to/main/checkout &&`.** That prefix silently retargets the MAIN checkout — mutating tracked files there, or making `go test` quietly test main's code so wrong-reason-green tests read as passes.
- **Gitignored files don't exist in a worktree** — `.jobs.db`, `local/`, dev databases. Pass every such path absolute, and never "fix" a missing one by re-initializing it.
- **Parallel agents share one scratch directory.** Prefix every scratch file with your leaf id (`kdrp5-commitmsg.txt`), and read back any file before you pass it to `-F`; a generic name is clobbered without warning.
- **Restate anything the agent cannot proceed without.** A leaf description the agent can't read is not a brief; load-bearing instructions go in the prompt or a committed file.
- **Keep the sync preamble in every prompt** (`git merge --ff-only main`, falling back to `git rebase main`); it makes a missed commit survivable. A clean base report may only describe state *after* syncing, so it isn't evidence of a clean spawn.
- **Don't take the work back with `git apply`.** It is atomic and prints per-file "Applied cleanly" right up to the moment it discards everything, and a partial `-3` leaves a half-applied tree; merge the branch instead (step 7).
- **Parallel migrations use placeholder numbers** (`900_`, `901_`), renumbered sequentially at integration with the placeholder comment stripped. Never let a placeholder reach a persistent dev DB. Safe only where the migration runner records one row per version rather than a high-water mark; check before relying on it.
- **The pre-commit hook must never recurse into `.claude/worktrees/`** — a running agent's half-written file will fail the main thread's unrelated commit. If you add a check to the hook, check whether it recurses; skipping dot-directories is what the Go toolchain itself does.
- **Subagent isolation is not airtight.** An agent given a worktree can still write to absolute paths in the main checkout; brief it to stay in its cwd.
- **A permission denial or a "too complex to verify" refusal is a harness fact, not a project one.** They are in `project/agents/harness.md`; point agents at it rather than re-deriving them per repo.

## Briefing template

Every prompt carries this boilerplate; each line was paid for.

```
You are working in worktree <abs path> on leaves <id>, <id>, … in this order. Identity: --as <name>.
Sync first: git merge --ff-only main (if it fails, git rebase main) — as separate calls.
Jobs DB: always pass --db <main checkout's abs path>/.jobs.db — never the worktree's copy.
Claim each for longer than your builds and test runs take: job claim <id> 2h --as <name>.
Release your claims when you report: job release <id> --as <name>.
HARNESS: read project/agents/harness.md — sandbox, $TMPDIR and worktree isolation.
Split compound commands into plain calls and use the Write tool for file bodies.
Do not cd into the main checkout. Do not commit. Do not run job done.
Never git stash: every worktree shares one stash stack.
Never change product behavior or appearance to make a test, probe or capture pass;
report the conflict instead.
A duration that spans a machine sleep is not a hang: check whether the machine
slept before reporting anything as slow.

TASK: <goal, in one paragraph>
VERIFIED FACTS: <real counts, timestamps, invariants that must hold — not just the goal>
DO NOT BUILD: <explicit exclusions>; <files owned by other agents>
TDD: red first; if a new test is green on first run, say so — that is a claim about rigor.

Your report must include:
1. Per leaf: what changed and why, and whether its criteria pass — not the diff; the branch carries it.
2. Every new file, by path.
3. Whether the suite passed and which command you ran.
4. The worktree path and its branch name.
5. A proposed commit message: a subject completing "This commit…" (present-tense verb first), a body that says why.
6. DEVIATIONS from this brief, and why.
7. WHAT IN THIS BRIEF IS WRONG? Answer explicitly. Briefs contain errors at a rate that makes this the cheapest check available; if a seam does not work the way this describes, say so rather than working around it. Fix minor bugs as you encounter them, and report the major ones.
```
<!-- agents:end delegation -->
