# G2 — the ledger table holds two row shapes, and every reader silently drops one

**Category:** harness · **Found:** 2026-08-21, by two instruments failing identically
**Related:** G1 (gate hygiene), `planning/ledger-reconcile.py`

## What is wrong

`ORCHESTRATOR.md`'s main table declares a nine-column header — `ID · Title · Category ·
Deps · Mock (deep link) · Lane · Status · Branch · Outcome`. Interleaved through it, in
**seven separate runs**, are **23 four-column rows**: the `D-p6-*`, `D-i6-*`, `D-i5-*`,
`D-i4-*`, `D-p1-*`, `D-p5-*` deferred-child entries, plus `CUTOVER TARGET` and `RULE`.

They are not contiguous. Measured on `7c2c67a`:

```
full  141-151     SHORT 152        full  153-179
SHORT 180-181     full  182        SHORT 183-190
full  191-192     SHORT 193-194    full  195
SHORT 196-204     full  205-236    SHORT 324
```

A four-column row under a nine-column header is unparseable by construction. There is no
correct way to read its `Status`, because it has no cell there.

## Why it is a finding rather than a formatting nit

**Two unrelated readers independently invented the same blind spot, and neither mentioned
it.** `ledger-reconcile.py`'s check H guarded with `len(cells) < len(header): continue` — a
parser guard. A peer session's scanner matched ids with `[A-Z]{1,2}\d{1,2}` — a matcher,
which rejects `D-p6-a` for having no digit after its series letter. Different mechanisms,
different authors, and they excluded **the same 23 rows**.

That is the part worth keeping. Agreement between two independent instruments is normally
the strongest signal available. Here it was an artifact of the subject: a heterogeneous
table produces silent, *agreeing* subsets in readers that share no code, so the corroboration
that would ordinarily raise confidence is measuring the file's shape rather than its content.

Both instruments then reported a verdict over an unstated subset — 70 of 93 rows in one
case, roughly half in the other — and both printed clean.

## What has already been done

Not this item. `7c2c67a` made the omission **visible** rather than fixed: the reconciler now
prints `H examined N rows with a status cell; skipped K` on every run, names the skipped ids,
and exits **2** when `examined == 0`. That closes the silent-subset hazard, which was the
dangerous half. It does not make the rows readable.

## What done looks like

The 23 short rows live under a header that matches their shape — either moved into the
existing four-column deferred register below, or given their own headed table in place.
Either way, one table, one row shape, and a reader that does not have to invent an exclusion.

Re-run `python3 planning/ledger-reconcile.py` afterwards: `H examined` should rise to the
full row count and `skipped` should read 0, which is the acceptance test.

## Why it was not done on 2026-08-21

The runs are scattered across seven positions rather than contiguous, so the fix moves rows
rather than inserting a header. `ORCHESTRATOR.md` was being read by four live verify agents
and one runner at the time. Moving ~23 rows in a file agents are mid-read on buys nothing the
denominator line has not already bought, and risks a runner acting on a half-restructured
table. Deferred deliberately, not overlooked.

## Not in scope

The six-field `D-p*` rows' *content*, which is correct and well-sourced. This is about the
table they are in, not what they say.
