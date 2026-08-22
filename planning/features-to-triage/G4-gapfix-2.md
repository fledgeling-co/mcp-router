# G4 gap-fix 2 — the item that catches unwritten records shipped one

**Parent:** G4 · **Verdict:** Needs More Work, 2026-08-22 (second verification) · **Branch:** `ai/g4` @ `27417a9`

## What passed, and it is everything substantive

**The block is closed and re-derives exactly.** The verifier reconstructed the base from
`git archive 72958de` with the gate under `gate/` so `ROOT` puts `planning/` and `scripts/` in
scope and the instrument out of it, and reproduced **both** columns from the same instrument moved
in and out of its own denominator. Its oracle rung is **differential measurement with an armed
control** — it armed its own sweep against a synthetic residue before trusting its clean sheet.
**No claim in that verification rests on reading the runner's account.**

The `test-campaign/` separation is right: none of the 12 excluded files is a `.py`, the census
globs `*.py` only, and the verifier's own `make all` rewrote the same 12 (`3a6881a…` → `664c50c…`).
Nothing of the runner's was left uncommitted.

**And acceptance criterion 5's check-E clause is now met on its own terms.** `ai/g5` has since
committed (`64e1631`), so `git merge-base --is-ancestor ai/g5 main` is false, check E cannot fire
on it, and the reconciler is **0 across A–L, exit 0** from this worktree. The criterion was the
orchestrator's defect when written; it is simply satisfied now. That it changed without anyone
editing anything is `D-g4-b`'s own point, made by events.

## The block — §6 is a placeholder, and the orchestrator committed it unread

`planning/progress/G4-gapfix.md:269` is the literal string **`GATES_PLACEHOLDER`**.

The runner exited while `make all` was still running, having said it would fill in §6 and commit
once it landed. **The orchestrator committed its work on its behalf and did not read the file it
was committing.** That is this item's own defect class — a record asserted without its content
being checked — inside the item built to catch exactly that, and the responsibility for it is the
orchestrator's rather than the runner's.

Two things follow, and the second is the one that matters:

1. **Acceptance criterion 5 asks for gates "measured at this base and pasted", and the record
   pastes nothing.**
2. **`D-g4-b` in §7 cites §6 for a claim that measures false.** It reads *"§6 records it doing more
   than moving: it is now the sole reason `ledger-reconcile.py` exits 1."* §6 records nothing, and
   the reconciler exits **0**. A record citing unwritten content, in support of a claim that
   measures false, is the sharpest possible instance of this item's subject.

## Also — a miscount in the census correction

§1 says *"The other four moved the same way"* where its own table shows **five** non-bold figures
moving: 274, 91, 64, 7, and 19-silent. It changes no census figure. It should not stand in this
item.

## Acceptance

1. §6 is written from a **measured** run and pasted verbatim — not summarised, not described.
2. `D-g4-b`'s §7 sentence is repointed or deleted. The reconciler exits 0; whatever the row says
   must be true of what is measurable today, and if the claim depended on a transient condition,
   say that rather than restating it.
3. "The other four" becomes "five".
4. Gates unmoved at this base, pasted: `make lint` **0**, `make test` **1684 in 209**, reconciler
   **0 across A–L**, and `make all` red at `parity-selftest` **as at the base** — established in
   the first verification and confirmed in the second; do not re-litigate it, but say it still
   holds.

Use a **wrap-tolerant sweep with a presence control** on the two corrected figures. This item's own
gap-fix shipped two broken sweeps that its absence check passed; do not make it three.

## Register, do not fix

**`D-g4-d`** stands as registered: the tsv's `accounting_tree` row says *fifteen* rows would point
at absent files where it is fourteen, and the same wrong number is a comment at
`null-run-gate.py:131`. Correcting one leaves them out of step; correcting both edits a gate this
item was told not to touch, **and that gate's 28 arms are this item's own evidence**.

## Scope

`planning/progress/G4-gapfix.md` — §6, one sentence in §7, one word in §1. **Nothing else.** No
gate logic, no census re-measurement, no tsv edit.
