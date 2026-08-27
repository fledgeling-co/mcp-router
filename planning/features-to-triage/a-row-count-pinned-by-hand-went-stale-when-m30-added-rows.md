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
