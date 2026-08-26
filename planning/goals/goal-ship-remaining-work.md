# goal: ship-remaining-work

## Objective

Drive the mcp-router feature pipeline until every currently-triaged item is verified and merged and
every repository gate is green.

## The finish line was rewritten, and why

As given: *"perform ship-fleet until no more work remains."* Nothing can settle that. Taken
literally it means the reckoning's `broken 51 · unmeasured 17 · undecided 5 · unbuilt 1 ·
unjoined 113` all reach zero — 187 rows, of which the 113 `unjoined` are mostly an artifact of a
16% brief-to-registry join rate rather than work anybody would schedule. A run armed against it
would never stop, and would spend its final turns re-asserting that it was not finished.

What replaces it is verifiable by exit code and counts against an enumerated list: **every ledger
row that is To Do or Developer Review today reaches Done and merged, no `ai/*` branch is left
unmerged, and all five gates exit 0.** Work discovered along the way joins the list; work that
cannot be finished is parked with a reason rather than left ambiguous.

## Worklist — 8 items, enumerated so the finish can be counted

| ID | State today | What closing it means |
|---|---|---|
| G6 | Developer Review, `ai/g6`, 8 commits | verify in fresh context, then merge or gap-fix |
| G8 | To Do | only a header comment landed; the executable checks are unstarted |
| G9 | To Do | the 40-file absolute-path sweep, and the pre-commit `GIT_DIR`/`GIT_WORK_TREE` unset |
| G10 | To Do | run the shell lane against the app, and re-check every lane enrolled behind it |
| M30 | To Do, owner authorised | serve real capability documents from both routers, with parity vectors |
| M31 | To Do | state the disabled-primary semantics in DESIGN.md; sweep built surfaces reproducing it |
| M32 | To Do | the class, not the instance: an `extra` needs an oracle rather than only a citation |
| M33 | To Do | `make test` must say which build description it compiled; sweep branches whose green covered nothing |

Twenty briefs filed this session are **untriaged and deliberately outside this run's finish line**.
They are the next run's worklist. Triage may pull one in if it blocks a listed item; nothing else.

## Gates — each judged on exit code alone, measured 2026-08-26 before arming

| Gate | Command | Now |
|---|---|---|
| tests | `make test` | **0** |
| lint | `make lint` | **2** — carries the citation gate below |
| ledger | `python3 planning/ledger-reconcile.py` | **0** |
| citations | `python3 planning/citation-gate.py` | **1** — ratchet 1291 → 1333 |
| reckon | `reckon.py check planning/reckoning/<latest>/ledger.json` | **4** — 9 unclassifiable defect statuses |
| branches | no `ai/*` branch unmerged into main | **1** (`ai/g6`) |

Three of six are red today. That is deliberate: a gate set that is already green proves nothing
about a run, and each of these red gates names work on the list above.

`lint` subsumes `citations`, and both are listed on purpose — one gate one question. When lint goes
red the run needs to know whether it was the citation ratchet or something else, without reading
output.

## Gate correction, iteration 3 — recorded because it moved the finish line

Two gates as first written could not be satisfied by anything this run may legitimately do, which is
a defect in the gate craft rather than in the repo. Of the 42 bare citations over baseline, **9 live
in a +537-line uncommitted third-party edit** to `planning/test-campaign/RUN-2026-08-20.md` that this
brief forbids committing. An unsatisfiable gate stops carrying information, which is the failure this
project has now recorded three times.

**What changed, and what deliberately did not.** `citations` now judges the **blocking** classes —
`DRIFTED` and `ABSENT`, the pointers that resolve to the *wrong* text, which "the dangerous variety",
`planning/features-to-triage/G7-a-citation-that-does-not-resolve-where-it-is-read.md:75` at `afd823a`
names as the kind a reader believes. `lint` runs the whole of `make lint` and tolerates **only** the
citation ratchet's veto. The ratchet baseline is **untouched**, `make lint` by hand still shows the
debt, and it stays filed as owed work.

**Both replacements were proved to fail before being armed.** The blocking check exits 1 on a planted
false citation; the lint wrapper exits 1 on a planted style violation. The first attempt at the
citation control **did not fire** — it landed in `BARE` rather than `ABSENT` because the gate's
adjacency grammar could not parse the improvised form, which is the hole the gate itself prints. It
was re-planted in the documented form and then fired. A gate whose control does not fire proves
nothing, and would have been shipped had the first result been taken at face value.

## Blocked-item policy

An item blocked on something outside this repository is **parked with its reason in the ledger row**
and removed from the finish line, not retried. Two are foreseeable: `M30` touches a trust boundary
in two router implementations and may surface a decision only the owner can take; the citation
ratchet may need the owner's call between paying the debt down and raising the baseline, since the
ratchet's own rule is that a file's count may only fall.

## Resource ledger

- **Machine admission is the binding constraint.** `harbourmaster berths.py` has held
  `hard_gate: swap` at 0 berths for over an hour, with swap ~94% while ~49 GB is free. The owner's
  standing decision is **run one agent** under that condition. Do not exceed it while the gate stands.
- Four simulators are booted; the iOS lane owns `MCPRouter-Glass` and must not share.
- The codex lane is recorded **unavailable** in ORCHESTRATOR.md — do not probe it. Route out-of-family
  work to `agy`, then `grok`, then in-family with the downgrade logged.
- Concurrency cap: **1 agent** while the swap gate stands; up to 4 with inner waves of 3 once berths
  free, keeping the product under 16.

## Stop conditions

- All eight items Done-and-merged, all six gates exit 0 → finished.
- A gate fails identically three turns running → escalate once, then disarm as stuck.
- Iterations, deadline and stuck bound live in the state file and end the run on their own terms.

## Owner decisions taken at arming, 2026-08-26

- **The run may merge into main by itself.** Asked explicitly, marked as the irreversible path, and
  chosen: finished work lands on main unattended. This does **not** loosen what counts as finished —
  a branch still needs a fresh-context verify verdict on its ledger row before it may be merged, and
  a merge still runs the gates afterwards. What changed is that nobody has to be awake for it.
- **The guard is armed** with the stop hook and a raised block cap, scoped to this project.

## What the run must not do

- Merge a branch without a fresh-context verify verdict on its ledger row. Automatic merging was
  authorised for *finished* work; it is not authorisation to lower the bar for finished.
- Raise the citation ratchet to make lint green. The ratchet's rule is that counts may only fall;
  absorbing the debt is an owner decision, not a way past a red gate.
- Edit a test to make a gate pass.
- Commit the pre-existing uncommitted files that were dirty before this work began — the marketing
  sources, `docs/img/`, most of `planning/test-campaign/`, and `planning/reckoning/2026-08-24/`.
