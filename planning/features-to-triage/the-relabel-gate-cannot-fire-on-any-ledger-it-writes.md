---
status: to-triage
found-by: armed on the repository's own ledgers during the 2026-08-27 investigation
---

# The remaining-work gate against re-labelling cannot fire on any ledger it writes

- origin: session investigation, armed against `planning/reckoning/2026-08-27T1520/ledger.json` · 2026-08-27
- audience: whoever relies on the reckoning to refuse a requirement that was promoted by typing
- platforms: n/a
- proposed-by-ai: false

## What and why

The reckoning carries a guard added specifically to stop a requirement being moved to `observed`
without a case behind it. Its own comment records why: a campaign once moved eight requirements
from unmeasured to observed inside one session with no case having run in between, and the gate
exited 0. The guard reads `backed_by`, the list of passing cases that cite the requirement,
computed from the campaign rather than from the requirement's own word.

The guard cannot fire. `reckon.py:811` writes `sorted(backing.get(id, [])) or None`, so a
requirement with zero backing cases is written as `None` rather than as an empty list.
`reckon.py:1301` then reads `None` as "this ledger predates the field" and continues, which is a
deliberate and correct allowance for older ledgers — but because the writer never produces an empty
list, every zero-backing row takes that exit. The refusal below it is unreachable for any ledger
this version writes.

Armed on the real transition, using this repository's own two ledgers with `REQ-021` forced to
`unmeasured` in the earlier one:

| `backed_by` on the newer ledger | result |
|---|---|
| `None`, which is what the writer emits for zero backing cases | `ratchet: clean`, exit 0 |
| `[]`, which is what the guard's text expects | `RATCHET REQ-021 moved from unmeasured to observed with no passing case citing it`, exit 3 |

The logic below the branch is correct and the message is the right one. Only the value never
arrives in the shape that reaches it.

This is not hypothetical here. `REQ-021` through `REQ-025` currently sit `verified-done` in the
newest ledger with zero backing cases, while `campaign.py check` names all five as requirements no
case traces to. Two instruments disagree about the same five rows, and the one that is wrong is the
one whose exit code the goal harness gates on.

The instrument is `reckon` 1.7.0 in `fledgeling-plugins`, not this repository. A change belongs
upstream, because a gate that behaves one way here and another way everywhere else stops being
evidence of anything.

## Acceptance sketch

- A requirement recorded `observed` with no passing case citing it is refused, on a ledger the tool
  wrote itself rather than only on a hand-edited fixture.
- A ledger genuinely written before the field existed is still let through, so the allowance the
  branch was built for survives the fix.
- The distinction between "no backing cases" and "this field was never computed" is representable,
  rather than collapsing into one value.
- The check is watched to fail on both sides before it is trusted, in the same way this brief
  arrives with it armed.
- This repository's five affected requirements are re-classed by whatever the corrected gate says.

## Assumptions made writing this

- Assuming the fix belongs upstream in `fledgeling-plugins` rather than in a local wrapper, since a
  locally-patched gate is not the gate the rest of the estate runs.
- Assuming the correct remedy is to distinguish the two conditions rather than to write `[]`
  unconditionally, because writing `[]` on an old ledger would fail every first comparison and
  report the ledger's age as a defect in the project.
