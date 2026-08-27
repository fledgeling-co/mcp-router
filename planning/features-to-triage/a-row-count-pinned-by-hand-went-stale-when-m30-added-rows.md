---
status: to-triage
found-by: P9's gap-fix, 2026-08-27; reproduced by the orchestrator the same day
---

# A row count pinned by hand went stale when M30 added rows, and `make parity-selftest` has been red since

`planning/parity/surface.tsv` carries `# rows: 95` on line 3. The file no longer holds 95 rows.
It was last changed by `b1160ef`, M30's document work, which merged during this session — so
`make parity-selftest` has exited **2** on clean `main` from that merge onward, and the orchestrator
that performed the merge did not notice because `parity-selftest` is not in the gate set it ran.

Reproduced on clean `main` at `c860ca2`: `make parity-selftest` exits 2.

## Why this is worse than one red gate

The failure is not confined to the selftest. `parity-manifest-check` exits 1 on the **unmutated**
tree, so `parity-manifest-selftest` prints *"NOT GREEN — every red below proves nothing"* and its
**35 reds become uninformative** — they cannot distinguish a mutation the check caught from noise
against an already-failing baseline. `make` then aborts there, so anything enrolled after it never
runs at all. One stale integer disables a mutation harness and hides everything downstream of it.

The gate's own words name the consequence: *"a case that stays green is a mutation the manifest
check cannot see, which means the coverage fraction can be moved without the gate noticing."*

## This is the third instance of one mechanism, in one day

- `mac-shell.sh` hand-named seven destinations; M22 shipped nine (`M35`).
- The campaign's surface list is hand-maintained and lost three shipped surfaces (`G18`).
- This: a row count pinned by hand, invalidated by rows added in the same repository.

Each is a duplicate of a fact the artifact beside it already states, kept in sync by whoever
remembers. `M35`'s gap-fix found the shape that generalises — **compile or derive a one-purpose
oracle from the thing itself, and let the consumer read its output** — and split *address* from
*expectation*: derive where a thing lives and what it is called, hand-write what it must do.

## What this item must NOT do

**Do not simply update the pin to the current count.** That restores green and re-arms the same
trap for the next person who adds a row, and the pin exists precisely because the count is
load-bearing — it feeds `PARITY_CUTOVER_TARGET`, which is an owner decision recorded at 82.
P9's runner declined to move it for that reason and was right to.

The question is whether this count should be pinned by hand at all, and if it must be, whether
adding a row without updating it should fail loudly at the point of the edit rather than silently
several gates later.

## The history, measured — this is a recurrence, and the pin has never worked

`git log -L3,3` on the file shows the pin **bumped five times**, once per change that touched it:

| commit | pin becomes |
|---|---|
| `6c4829e` | 83 |
| `ab2a64b` | 91 |
| `855179b` | 92 |
| `0eed681` | 94 |
| `ebe3165` | 95 |

**It was caught in advance once, and the catch did not survive.** R19's ledger row records, on
2026-08-22: *"the union with today's `main` puts 96 rows against `surface.tsv:3`'s `# rows: 94`
pin, so `parity-manifest-check.sh` exits 1 on the merged tree while both parents are green — a
merge-only break caught in advance for the first time."* That is the same failure, predicted
before it landed, by a runner reading two branches. It was then resolved the way every other
occurrence was resolved: by moving the pin.

**And the sharpest measurement is that the last bump was already wrong when it was written.**
`ebe3165` set the pin to **95**. At that same commit the file already held **97** data rows. So
the hand-update was stale by two the moment it was made, and `b1160ef` — the same item, minutes
later — inherited it. Nobody mistyped: the number is simply not derivable by the person editing
it, and five people in a row have proved that.

The gate's own message names the coupling that makes this more than a counter:

> the manifest holds 97 rows and pins itself at 95. … A row was added or removed. If that was
> deliberate, move the pin in the same change and **the cutover target is derived from this
> denominator and is pinned separately.**

So a coverage fraction that moves without the gate noticing is precisely what this file exists to
prevent, and the mechanism protecting it is a number a human retypes.

## Scope

- Establish what the pin is for and who owns the number, since it reaches an owner decision.
- Either derive the count, or make a mismatch fail where the rows are edited rather than
  downstream of three other gates.
- Restore `make parity-selftest` to green on `main`, and confirm `parity-manifest-selftest`'s 35
  reds become informative again.
- Arm it: add a row without touching the pin and show the failure name the file and the two
  numbers; restore and show green.
- State plainly whether `PARITY_CUTOVER_TARGET` is affected, because a coverage fraction that
  moved without the gate noticing is the thing this file is supposed to prevent.
