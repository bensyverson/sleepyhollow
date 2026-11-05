<!-- agents:begin planning@dd6905 -->
# Planning

A Jobs plan is a Markdown file which carries prose and a YAML block in `job schema` format. Anytime you need to take on a substantial amount of work that may stretch beyond one session, create a plan.

Typically, a plan is stored as a dated doc under `project/`. The prose at the top holds what spans leaves: the goal, the architecture, the order and its reasons, the decisions that bind several leaves. The `tasks:` block carries the same plan but staged for work; each leaf holds what one piece of work needs, on its own.

## Writing a good plan

**A leaf restates what it needs; links are for depth.** Agents will sometimes see leaves in isolation, so don’t assume the implementing agent will understand the surrounding context. If there’s necessary background, restate the substance in a sentence or two, then link to the section or leaf directly.

A plan is read one leaf at a time, by agents arriving with fresh context, through `job orient` and `job claim`. Those show the leaf (its description, criteria and notes), not the doc it came from, so as far as the agent doing the work can tell, the leaf is the plan. `project/agents/jobs.md` covers the tracker's mechanics and how big a leaf is; this file covers what goes in one.

**Write the leaf you would want to receive if you were the one building it: rich enough to help you understand the problem, flexible enough to give you trust and autonomy.**

## What a leaf should carry

First, a clear, descriptive title.

In the description, prose, typically a few short paragraphs; it needs no heading per element. Roughly in this order:

- **Why.** The goal it serves, what it unblocks, and who or what is waiting on it. This is what lets an agent make good calls in the cases the description doesn't name.
- **What.** The outcome: the behavior, artifact or answer that exists when it's done, described from the outside.
- **Already decided.** The rulings that bind it, restated and each linked to the doc that made it, so nobody reopens them by accident.
- **Seams.** The packages, files, interfaces or neighboring leaves it touches, so the agent knows where to look and what not to break.
- **Out of scope.** Where the edge is, especially where another leaf picks up.
- **Open questions.** What the leaf must settle, and which of those are the agent's call and which the user's.
- **Risks.** What could make it harder than it looks, or dissolve it entirely.
- **How, only when it earns its place.** Include an approach when it wouldn't be obvious to a capable agent, or when there is a known preference or decision about the implementation ("pure Go, so the binary stays static"; "extend the existing parser rather than adding a second"). Name the approach and its reason in a sentence and leave the code to the builder. Implementation blocks, type definitions and function signatures don't belong in a leaf: they are decided before anyone has touched the problem, they go stale as soon as the code moves, and they turn the builder into a typist.

## Writing the `tasks:` block

- **Write every description as a block scalar, `desc: |`.** A plain scalar folds its lines and breaks on a colon followed by a space; a block keeps paragraphs and needs no quoting. Inside it, a blank line separates paragraphs.
- **The leaf's elements map to fields.** Why, what, decided, seams, scope, open questions, risks and how go in `desc`; criteria in `criteria:`; order in `blockedBy`, only when the order is real, pointing at a `ref` rather than a title, since titles get edited; a pending choice gets `labels: [decision]`. `job schema` is the grammar.
- **Criteria are checkable sentences about behavior**, each naming the evidence that will show it: a test, a live run, a screenshot, a report. "Works well" is not a criterion.
- **A stage's own definition of done is a leaf**, usually the eval or demo that closes it, carrying the stage's criteria. A parent closes itself when its last child does, so criteria that live only in the prose never get checked.
- **Only the first `tasks:` block in a file is imported**, so keep examples out of the plan doc.
- **Import is a one-time copy.** Afterward the tracker is the plan: change a leaf with `job edit`, not the YAML. Above the block, note that it was imported, the date and the parent id, so a reader knows where the current version lives. Detail placeholder leaves with `job edit -F`; put genuinely new work in a new dated doc and load it with `job import --parent <id>`.

## Not every leaf is code

- **A leaf is any unit of work with an outcome: web research, a spike, a smoke test, a proof of concept, a measurement, a design pass.** In an uncertain plan these are often the most valuable leaves, because they buy the information later leaves depend on.
- **An investigation's outcome is an answer, not an artifact.** State the question, what each plausible answer would change in the plan, how much effort it deserves, and where the finding goes (a dated doc, a decision). A spike's criteria say what was learned and where it was recorded, not that code shipped; its code is disposable unless the leaf says otherwise.

## Honest uncertainty

- **Detail tracks confidence, not position in the plan.** Staged work doesn't always run in order. Give full detail to whatever you are confident about, wherever it sits; that may be a handful of leaves or the entire plan.
- **Leave later choices to the work that informs them.** When a leaf depends on what an eval, a spike or the user's reaction will show, keep the choice open and say so: name it, the options you can see, and what would decide between them. A plan that settles everything up front is pretending, and its later leaves get built as written after the premise has moved.
- **Give a pending choice its own leaf.** A choice the plan waits on is a `decision`-labeled leaf stating the question, the options and what waits on it; a choice that needs information first gets a research or spike leaf ahead of it.
- **An uncertain leaf still meets a minimum:** why it exists, what is known, what is open, and links to the doc sections that bear on it. Detailing it once the uncertainty resolves is often a leaf of its own ("Detail the next stage from the evals").

## Before import

- **Read each leaf as its builder.** Could a capable agent with fresh context, the leaf and the repo do this well, without the planning conversation? If it would need that conversation, the leaf is missing something.
- **`job import --dry-run`, import, then read `job orient` as a newcomer would.** That is the view every later session gets.
- **Check the sizing against `project/agents/jobs.md`:** a leaf is a unit of work grouped by surface, not one per idea.

## Keeping a plan true

- **When a finding changes a leaf's premise, edit its description** (`job edit <id> -F <file>`) and note why. A note appended under a stale premise doesn't reach the next reader, who acts on the description.
- **A ruling that binds more than one leaf goes in the design doc**, and the leaves point to it.
<!-- agents:end planning -->
