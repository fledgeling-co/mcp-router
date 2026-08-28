---
status: to-triage
found-by: reckon 1.7.0, 2026-08-29
---

# A defect status nobody taught the gate is still classified by a guess

- origin: reckon 1.7.0, `DEF-011` and `DEF-048` · 2026-08-29
- audience: whoever schedules from the broken list and needs each row to be there for a stated reason
- platforms: n/a
- proposed-by-ai: true

## What and why

Two defects carry a state word the reckoning cannot classify. `DEF-011` is
`partially-fixed · in-campaign` and `DEF-048` is `superseded · by-def-055`. Both are counted as
**broken** by a fail-closed default rather than by anything the registry said — reckon says so in its
own output, and puts the placement on itself rather than on the register.

Fail-closed is right and should stay: guessing done is the one error here that cannot be recovered
from. The defect is that the two vocabularies drifted apart again. A previous pass reconciled them by
remapping every status to lead with a verb the tool classifies, and that remap held — the rest of the
broken defects lead with `open` and land where the register put them. Nothing prevented two new words
being minted afterwards, so the reconciliation was a one-time edit rather than a property anything
maintains.

The cost is small in rows and real in reading. A row placed by a default looks exactly like a row
placed by a measurement, and both of these are rows where somebody already knows more than the class
says: one is partly fixed, the other is superseded by a defect that is itself open.

## Acceptance sketch

- A defect state word the reckoning cannot classify is refused where it is written, not absorbed at
  reckoning time.
- Every broken row can say whether it is broken because the register said so or because a default
  decided, and a reader can tell those apart.
- "Partly fixed" and "superseded" survive as distinctions rather than being flattened into open, since
  each changes what somebody would pick up.
- A newly minted state word is reported as an unknown word with its row count, rather than silently
  taking the pessimistic class.

## Assumptions made writing this

- Assuming a guard on the register is the fix rather than a second remap, because the last remap
  worked and did not hold.
- Assuming the pessimistic default stays; the ask is that it be visible when it fires, not that it be
  relaxed.
- Assuming this is distinct from the earlier vocabulary brief, which was resolved by that remap and
  covers the words it fixed rather than the absence of anything preventing new ones.
