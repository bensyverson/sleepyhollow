<!-- agents:begin jobs@5ae563 -->
# Working in `job`

Jobs is the tracker: where work is filed, how big a unit of work is, and what a fan-out mints before it launches. `project/agents/delegation.md` covers *running* agents; this file covers the tracker they claim from. `job <verb> --help` is the authority on flags — this file is the house convention around them.

## The tree

- **Every task has a parent.** `job add <parent> "<title>"`, never `job add "<title>"` — a bare add mints a new root, and `ls`, `status` and `orient` render roots as peers of whole projects, so a one-file fix draws the weight of an entire plan.
- **If no existing root fits the work, ask before creating one.** Run `job ls` first and pick the root whose subject actually contains the work; `job move <id> under <parent>` fixes a misfile.
- **All work happens on leaves.** If a parent has work of its own, model that work as a leaf child. Closing the last open child auto-closes the parent, and `claim` warns when that is pending — read the ack.
- **Criteria are the leaf's definition of done**: short checkable sentences, attached with `--criterion` on `add`, `edit` or an imported plan. They start pending, and `done` refuses to close over a pending one (`--all-passed`, `--all=<state>` and `--force-close-with-pending` override).
- **Mark a criterion with `job edit <id> --set-criterion "<label>=passed"`**, or at close with `job done <id> --criterion "<label>=passed"`. `edit` is not claim-guarded, so marking one never needs the claim.
- **`blockedBy` orders the frontier; it does not lock a task.** `next`, `orient` and `claim --next` skip a blocked leaf, but `job claim <id>` on one still succeeds — dispatching blocked work is a decision, not something the tool will stop. Declare a block with `job block add <blocked> by <blocker>`.
- **Discovered work goes in an issue-tree, not the plan.** A root created with `--kind issue` (or converted with `job kind <root> issue`) is skipped by `next`, `orient` and `claim --next`, so a bug found mid-plan doesn't derail it; `job issue "<title>"` files into it and records provenance from your live claim. Pass `--issues` to those verbs to work that kind instead.
- **`decision` is a reserved label**: `job label add <id> decision` makes the task a `Decision:` line in `job status` until it closes. That is where a question the plan is waiting on belongs.
- **A plan is a dated doc under `project/` carrying a fenced YAML `tasks:` block**, loaded with `job import <file>` — `--dry-run` first, `--parent <id>` to nest it under existing work. `job schema` prints the grammar: `desc`, `labels`, `criteria`, `ref`/`blockedBy`, `foundIn`, `kind`, `children`.

## The session loop

- **Open every session with `job orient` (no arguments).** It picks the next available leaf, renders its whole root tree with notes folded on and criteria as a checklist, and exits 0 with `target: null` when nothing is available. `job status` is the wider view: counts, identity, one row per root.
- **`job claim <id>` prints the full briefing**, so no follow-up `show` is needed. Claims last 30m and any write by the holder extends them; `job claim <id> 2h` for longer work, `job heartbeat` only during a genuine pause.
- **Claiming focuses that leaf's root** — one focus per tree kind — which scopes bare `next`, `claim --next` and `orient` to that tree. `job focus <id>` sets it explicitly; `job focus --release` clears it.
- **Note as you go, not only at the end.** A note is where a finding outlives the session: `job note <id> -F <file>`. At least one substantive note per leaf.
- **Read the leaf's own history before anything expensive to change** — schema, a wire format, a public interface. `job show <id>` carries what `orient` elides.
- **Close with `job done <id> -F <file>`**, marking criteria in the same call. `--claim-next` closes and takes the next leaf in the same root atomically.

## Identities

- **The main thread uses the database's default identity** — no `--as`. `job init --as <name>` records it: the name of whoever runs the session — an assistant's own name, not the account it runs under. `init` refuses without `--as` (or `--strict`, which records no default). `job gitignore` writes the `.gitignore` entries; `init` prints them only when the repo is missing one.
- **Every subagent passes `--as <name>`, unique per agent, on every call**, plus an absolute `--db /abs/path/.jobs.db`. `.jobs.db` is usually gitignored, so it does not exist inside a worktree and a relative path fails there. Never "fix" that with `job init`; it creates a second, empty database.
- **`note`, `done` and `release` on a claimed task must carry the claimant's identity.** A bare `job note <id>` against a task claimed `--as jars` fails with "task is claimed by jars"; a brief that shows `job note` without the identity is wrong.
- **Agents `claim`, `note` and `release`. They never run `done`, and never commit.** They hand the work back; the integrator runs the suite, commits, and closes the leaves.

## Filing work

- **A leaf is a unit of WORK, grouped by the surface and the files it touches** — not one leaf per complaint. A review round of twenty-five items is not twenty-five leaves; "the form's typography, spacing and badge column" is one leaf, not four.
- **Per-leaf overhead is roughly fixed** — a brief, a worktree, an integration, a file-contention negotiation. Keep a leaf separate when it carries a genuine decision, a different risk profile, or a distinct blocker; "it was a different sentence in the feedback" is none of those.
- **Check an incoming item against what already exists before filing it.**
- **A fan-out mints a container leaf plus a leaf per unit of work BEFORE dispatch.** Work that runs only inside an agent harness is invisible while it runs and leaves no durable notes where the rest of the project's history lives.
- **Leaves are units of work; agents are assigned by file ownership.** It is not one leaf per agent — if three leaves touch one file, one agent takes and claims all three. Merge cost decides the split, not task count.
- **A leaf that turns out to be several is subdivided with `job split <id> "<a>" "<b>"`** — it must have no children yet, and it auto-closes once the new ones do. Carving work into new leaves mid-flight is rare; prefer it to quietly widening one leaf's scope.
- **An ephemeral verifier that reports back and stops needs no leaf**; its verdict lands as a note on the container.
- **Work decided against goes to `project/backlog.md`, not into a leaf.** Nothing there is scheduled or blocking; `job` holds active work only.
- **A leaf's description is not a brief.** An agent that cannot read the tracker cannot read what is in it — restate anything load-bearing in the prompt or a committed file.

## Messages

- **Pass every body with `-F <file>`, not inline `-m`** — the shell interprets `-m` first. `-F -` reads stdin. It works on `note`, `done`, `add`, `edit`, `claim`, `release`, `cancel` and `issue`; on `add` and `edit` it is the description, everywhere else the message or reason.
- **Write the file first, read it back, then pass it.** When a scratch directory is shared across parallel agents, prefix the filename with the leaf id so two agents can't collide.

## See also

- `project/agents/delegation.md` — what to delegate, worktrees, integration, and the briefing template.
<!-- agents:end jobs -->
