---
reckon-sources: [REQ-040, DEF-011, DEF-048, CASE-0355, CASE-0356]
---

# The remaining-work gate fails every run on words nobody taught it

- origin: reckon exit 4, reproduced on every run this session · 2026-08-26
- audience: Whoever reads the remaining-work report and needs its gate to mean something
- platforms: n/a
- proposed-by-ai: false

## What and why
The remaining-work reckoning refuses to pass because the defect register uses twelve different words for
a defect's state and the reckoning understands only three of them. The nine it does not understand cover
thirty rows, and each is placed in the most pessimistic category by a fail-closed default rather than by
anything the register actually said. So the report is simultaneously too gloomy about those thirty rows
and unable to certify itself, every single run.

Fail-closed is the right default and should stay. The defect is that nobody has reconciled the two
vocabularies, so the gate has been red for so long that its redness carries no information: a reader
cannot tell this standing condition from a new problem.

## Acceptance sketch
- Every word the defect register uses for a state is one the remaining-work reckoning can classify.
- Rows land in their category because the register said so, not because a default guessed.
- The reckoning's gate passes when nothing is genuinely wrong, so that a failure means something again.
- A state word nobody has taught the reckoning is still reported rather than silently absorbed.

## Assumptions made writing this
- Assuming the vocabularies should be reconciled rather than the gate relaxed, since the fail-closed
  default is what stops a guess being recorded as a finding.
- Assuming words distinguishing where a defect was fixed carry real meaning worth preserving, rather than
  being collapsed into a single closed state.

---

**RESOLVED 2026-08-27, and recorded here rather than deleted.** The gate exited 4 on every run
when this was filed, on defect statuses its vocabulary could not classify. Measured today on
`main` at `d8b4959`: `reckon.py check planning/reckoning/2026-08-27/ledger.json` exits **0** over
337 rows. The 32 statuses were remapped to lead with a verb the tool classifies, in the same
session that filed this. No id allocated — it closed before it was scheduled.


---

## WE3 ADJUDICATION, 2026-09-03 — **(B), resolved. The row is scheduled by its citations, not by its subject.**

The finding closed on 2026-08-27 and the RESOLVED block above is accurate: the fix was a remap of
this repository's own defect statuses, entirely in the register, with `reckon.py` untouched.
**(B)** — naming the reckoning did not put the defect inside it.

Re-checked this session rather than taken from the note: `planning/defect-status-vocabulary-gate.py`
exits 0 over the register, and the reckoning's own ledger at `planning/reckoning/2026-09-03/`
classifies every defect row without falling back to its pessimistic default.

**Why it is still on the schedule.** This file's frontmatter carries only `reckon-sources` — no
`status` at all — and its five citations include DEF-011 (`partially-fixed`, still broken) and
DEF-048 (`superseded`, waived). `reckon` classes a brief by the state of what it cites, so the row
follows DEF-011 rather than its own subject. That is the reckoning working as designed; the row
leaves the list when DEF-011 does.

No status word written. The note above says "no id allocated — it closed before it was scheduled",
and `shipped-brief-gate` R6 would refuse a terminal word over DEF-011 in any case. Recorded rather
than forced.
