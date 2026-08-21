# Backlog

Work consciously decided against, so it doesn't vanish into silence. One
dated H2 per item: what it is, why it's parked, and what would un-park it.
Nothing here is scheduled or blocking; active work lives in `job`.

## 2026-08-20 — Auto-wait for the session act verbs

The one-shot step runner auto-waits for each step's selector before acting
(the wave-2 wait-vs-steps ruling; see the correction block in the vision
doc's "One-shot flows compose by flags"). The session verbs `sleepy
click|fill|submit` deliberately do **not**: they answer immediately, and a
missing selector is a clean negative (exit 1). Parked because auto-waiting
there means threading a wait budget through the operations themselves
(they ship over the session socket and must carry their own deadline —
a live session has no load in flight to borrow one from), which is real
API surface for a need nobody has demonstrated yet. Un-parked by: an agent
flow that genuinely needs to act on a late element in a live session and
can't express it with `sleepy eval` polling first.
