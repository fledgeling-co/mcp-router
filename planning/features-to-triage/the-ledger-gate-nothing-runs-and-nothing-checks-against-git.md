---
status: to-triage
found-by: Wave L, after four runners were dispatched at shipped work, 2026-08-29
registry-target: none
no-target-reason: the subject is the ledger files and their gate, which the campaign registry does not model — no case, requirement or defect covers a row whose status word disagrees with git
---

# The ledger gate nothing runs, and which checks the files against each other rather than git

- origin: M30 and M32 triage, both finding their own row stale · 2026-08-29
- audience: whoever schedules a fleet from ORCHESTRATOR.md
- platforms: n/a
- proposed-by-ai: true

## What and why

Four runners this session were dispatched at work already merged: M33, R30, M30 and M32. Each
read `Untriaged` or `To Do` in ORCHESTRATOR.md while its commits were ancestors of `main`. Two of
those dispatches cost a full wave slot before the runner discovered it and stopped.

`planning/ledger-reconcile.py` already holds the right check — check I, whose own text is *"the
fleet schedules from ORCHESTRATOR, so a row stale there dispatches a runner to rebuild shipped
work"*. Two things kept it quiet.

**It is in no Makefile target.** Not `lint`, not `all`, not `test`. Nothing invokes it, so it had
been red for an unknown period with nobody reading the output.

**Its checks compare the two files to each other.** A row is a finding when LEDGER and
ORCHESTRATOR disagree. When both are stale in the same direction they agree, and agreement is
indistinguishable from correctness. M30's LEDGER row demonstrates how far that can go: it opens
`Untriaged —` and ends, roughly 8,000 characters later, at `Verified DONE 2026-08-27 — MERGED to
main at 8ca250d`. The row contradicts itself and the gate reads only its leading token.

The instruments that would have caught it read git instead — `shipped-brief-gate.py` asks whether
a commit witnesses a terminal word, and R33's `carrier-parity-gate.py` re-measures from the diff
every run. The ledger has no such check.

## Acceptance sketch

- A row whose status says unstarted while its item's commits are ancestors of the integration
  branch is a finding, regardless of what the other file says.
- The check runs on a trigger somebody cannot forget, and the choice of trigger is stated.
- Turning it on does not land permanently red: the existing findings are either fixed first or
  carried with a recorded floor, because a gate that opens red is switched off within a week.
- A row whose leading status token contradicts its own body is a finding — that is a different
  defect from the two files disagreeing, and it is the one that hid here.

## Assumptions made writing this

- Assuming the git side is authoritative for lifecycle, since a commit reachable from the
  integration branch is a fact and a status word is a claim.
- Assuming this belongs beside the existing checks in `ledger-reconcile.py` rather than in a new
  instrument, because it shares their scan of both tables and a second copy would drift.
