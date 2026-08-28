---
status: to-triage
found-by: tailings 0.1.0 over this session's transcript, 2026-08-29
---

# Upstream: tailings reports three findings its own rows contradict

- origin: triaging the tailings run over this session, and checking each row against its data · 2026-08-29
- audience: maintainers of the shared session-audit instrument, and anyone triaging its output here
- platforms: n/a
- proposed-by-ai: true

## What and why

The run over this session produced 105 rows, 11 of them at the top band. Three of the rows that
reached a reader's attention did not survive being checked, and in each case the evidence that
would have suppressed them was already in the row.

**A laundering shape the probe cannot substantiate.** Two gates — the pool-mutation gate's
selftest and the acceptance-lanes script — were reported as going red and then green with only
their own input edited. Both rows carry an empty edited-file list and a flag saying the change
was reverted, so the probe names no edited input at all; the transition was a legitimate repair
in which the gate's own logic was the defect. The shape it hunts for is real and worth hunting,
but a row that cannot name the edited input is an accusation with its evidence missing.

**A conversational figure reported as a durable claim.** A number was flagged as appearing in a
durable claim with no earlier tool result behind it. Checked during triage, that figure appears
in no written record in the project — only inside the audit's own output — so the claim was
made in conversation. A chat sentence and a committed record are not the same severity, and the
top band is defined by the difference.

**A cross-reference row that names a duplication it never looked for.** A test fixture builder
was reported as referenced only by its own test and possibly duplicating an existing module. It
is a fixture builder written for one feature's suite, it is used by the suites it was written
for, and the tree holds no other builder of its shape. The row's suggestion was checked in
minutes; the probe did not check it at all.

This is worth work rather than a shrug because the instrument will keep running over every
session. A class of finding that a reader learns to discount spends exactly the attention it
was built to save.

## Acceptance sketch

- A row claiming an input was edited names the edited file. A row whose evidence set is empty
  is not reported at the band reserved for substantiated findings.
- A red-then-green transition caused by changing the gate's own logic is distinguishable in the
  output from one caused by moving an input.
- A figure that appears only in conversation is not reported as a durable-artifact claim; the
  durable bands are reserved for claims found in written records.
- A helper used by test suites is not reported as referenced only by its own test, and a
  duplication claim is made only after looking for the duplicate.
- The three findings above stop being reported on a re-run over this same transcript, while a
  seeded genuine instance of each shape is still reported.

## Assumptions made writing this

- Assuming this is fixed in the shared instrument and re-pulled rather than patched in this
  tree, following the route already taken for the citation probe's basename false positive.
- Assuming the laundering probe is unbacked here rather than wrong in principle: the shape is
  worth detecting, and this session simply contains a legitimate exception it cannot see.
- Assuming the remaining rows of the cross-reference class were not re-read one by one. An
  earlier triage of this instrument dropped a bulk re-read of that class as a code-review
  subject; this brief asks only that each row carry the check it implies.
