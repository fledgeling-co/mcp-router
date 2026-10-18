---
status: in-progress
delivered-on: ai/wa4-registry-vocabulary
reckon-sources: [REQ-040, CASE-0355, CASE-0356, DEF-011, DEF-048]
found-by: reckon 1.7.0, 2026-08-29
checked-2026-09-03-wc1: the work IS on main - cae59b10, merged at 8828d0ee, `defect-status-vocabulary-gate.py` in `make lint` and exit 0 here. It stays in-progress for two separate reasons and neither is an oversight. (1) NO LEDGER ROW NAMES THIS BRIEF, so `shipped-brief-gate.py` has no witness to read and the merge is invisible to it - R5 cannot report it either. (2) Even with a row, R6 would refuse a terminal word: the brief cites DEF-011, which is `partially-fixed`, and reckon reads a declared status ahead of the evidence. Writing `completed` here would take a still-broken row off the total.
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

---

**DELIVERED 2026-09-02 on `ai/wa4-registry-vocabulary`, NOT YET MERGED, and recorded here rather
than deleted.** The frontmatter says `in-progress` rather than `completed` on purpose:
`planning/shipped-brief-gate.py` refuses a terminal word that no `LEDGER.md` row and no commit on
`main` witnesses, and it is right to - *a brief leaves the remaining-work set on a merge somebody
can point at*. Whoever merges this branch allocates the LEDGER id and flips the word; no ledger id
is taken here, because five other runners are live off the same `main` and the allocation is a
read-modify-write on one file.

Both halves the brief asked for landed, and the acceptance sketch is answered clause by clause.

*A state word the reckoning cannot classify is refused where it is written.*
`planning/defect-status-vocabulary-gate.py`, in `make lint` beside `registry-drop-gate.py`, both
the check and its `--selftest`. `REQ-040` states the property, `CASE-0355` and `CASE-0356` observe
it.

*Every broken row can say whether the register placed it or a default did.* Every status in both
registry files now classifies, so no row is placed by the default at all — the gate prints the
class each word in use will produce, on every clean run.

*"Partly fixed" and "superseded" survive as distinctions.* `DEF-011` is `partially-fixed` and stays
`broken`; `DEF-048` is `superseded` and moves to `waived`, which is `reckon`'s ruling that a row
owes nothing rather than a record of a repair, with its successor `DEF-055` **open**. Everything
the qualifiers carried moved into a new `resolution` field on each row and none of it was dropped.

*A newly minted word is reported with its row count rather than silently taking the pessimistic
class.* That is the gate's failing output, and the pessimistic default is untouched — the ask was
that it be visible when it fires, not that it be relaxed.

**The assumption the brief made was right and is worth recording as measured.** It assumed a guard
on the register rather than a second remap, *because the last remap worked and did not hold*. The
remap here is the third; the guard is what makes it the last one that has to be done by hand.

**WHAT THIS DOES NOT SETTLE.** The asymmetry is `reckon`'s own: its fixed and open sets are matched
against a status's **leading token** while its partial, waived and not-owing sets are matched
against the **whole string**, which is why `fixed · in-campaign` classified and
`superseded · by-DEF-055` did not. That is not fixed here — `reckon` is in `fledgeling-plugins`, a
different repository. The gate models the asymmetry by hand, and its `--agree` arm compares word
lists against the running `reckon.py` but **not** branch structure, so a change to which set is
read which way would leave `--agree` reporting no drift. Held across reckon 1.9.3 and 1.9.4, both
read; the gate prints the limit on every clean run.

Evidence: `planning/evidence/wa4-registry-vocabulary.md`, transcript at
`planning/evidence/wa4-gate-transcript.txt`.


---

## WE3 ADJUDICATION, 2026-09-03 — **(B), delivered and merged. This row is on the list for a reason that is not about the work.**

Re-checked independently of the `checked-2026-09-03-wc1` line above and it holds:
`planning/defect-status-vocabulary-gate.py` is on `main`, is in `make lint`, and both the check
and its `--selftest` exit **0** on this tree. The vocabulary held under three defect additions
this session (DEF-500, DEF-501, DEF-502), each of which had to choose a status word the gate would
accept — which is the property this brief asked for, exercised rather than asserted.

`reckon.py` is vendored and this row does not need it edited. The whole of the fix is a guard on
this repository's own register, which is where it landed. **(B).**

**Why the row is still scheduled, and neither reason is the work.** (1) No `LEDGER.md` row names
this brief, so `shipped-brief-gate` has no witness to read and the merge is invisible to it. (2)
R6 would refuse a terminal word regardless, because the brief cites DEF-011, which is
`partially-fixed` and correctly still counted broken. Writing `completed` here would take a
still-broken row off the total, which is the failure the gate exists for.

**No LEDGER id allocated here**, for the reason the note above already gives and this session can
confirm from the other side: allocation is a read-modify-write on one file while another runner is
live in a worktree this one cannot see. That is the integrator's move, not a runner's.

The limit the delivery recorded stands unchanged after this session's reading:
`reckon`'s fixed and open sets match a status's **leading token** while its partial, waived and
not-owing sets match the **whole string**, the gate models that asymmetry by hand, and `--agree`
compares word lists rather than branch structure. Nothing here moves it.
