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

The 23 short rows live in the four-column deferred register, whose header already exists and
already holds 96 rows. One table, one row shape.

### The acceptance test, and the one it replaces

The first version of this brief asked for **"`H examined` rises to the full row count, and
`skipped` reads 0"**. That is self-contradicting, and `dev-09` caught it before anyone
implemented against it.

Trace the numbers. H reads the nine-column table: today 93 rows, 23 skipped, 70 examined. Move
the strays out and that table holds 70 rows and H skips none — so **`examined` stays at 70 and
cannot rise.** `examined` only rises if the rows are parsed *in place*, which is the fix this
brief rules out.

Worse, the half that does pass is the half that means least. **`skipped: 0` is satisfiable by
moving rows out of the reader's scope rather than by making them readable.** The number goes
right and the coverage is unchanged — the same move as marking a case `n/a` to lift a pass rate,
landing in the one file whose purpose is catching that.

So the test is a **conservation check**, which deletion cannot satisfy:

- the register table holds **96 + 23 = 119** rows, re-measured at implementation time rather than
  taken from this brief;
- each of the 23 ids is findable there by name;
- the nine-column table's row count falls by exactly 23, and no row's *content* differs from what
  `git show` has today.

### Which checks read the register table — measured, not assumed

`dev-09` asked the question this brief could not answer from outside the script. Measured on
`d8dca4d`:

| Reader | Reads the register table? |
|---|---|
| A, B, C, G (`table_ids` / `named_ids`) | **Yes** — `R11`, `R12`, `R13` and `M5-a` all live there and are checked |
| F (`describes`) | **Yes**, same rows |
| H (`status_rows`) | **No** — it requires a `status` column and the register has none |

And for the 23 strays specifically, every one returns **False** from `table_ids`, `named_ids`
*and* `describes`. They are outside all nine checks **today, before any move**.

That is deliberate rather than a gap. The id pattern excludes `D-<parent>-<letter>` children
because they are deferred *notes*, not allocations — the thing A, B, C and G exist to protect is
id allocation, and a note that never claims an id cannot collide with one. `ledger-reconcile.py`
says so at its `SERIES` definition.

### The rule was true, load-bearing, and invisible

The `D-<parent>-<letter>` exclusion is correct and it lived **only** in `ledger-reconcile.py`'s
`SERIES` definition. The author of that line forgot it was a stated exclusion rather than an
accident, and had to re-derive it by measurement — which is the whole test for whether a rule is
written somewhere a reader meets it. Someone opening `ORCHESTRATOR.md` sees 23 rows that look
like every other row and no indication that none of them is checked.

Same defect as `LEDGER.md`'s old header claiming ids were "allocated here and nowhere else" while
three branches existed that it had never heard of: true, load-bearing, and stated where nobody
reads it. Fixed by putting it in both places in the file itself — above the ledger table and
above the register — rather than only in this brief, which is also a place people do not read
until they are already implementing.

### Three mechanisms, not three instances

Worth separating, because the third is the one that ships. All three of tonight's findings were
about a denominator, but they failed differently:

1. **Dropped** — a reader silently discarding rows it could not parse, and reporting over the
   remainder.
2. **Corroborated** — two independent readers agreeing *because* of that same drop, so the
   agreement measured the file's shape rather than its content.
3. **Gamed** — an acceptance test satisfiable by shrinking the denominator rather than filling
   it.

The first two produce a wrong number, which someone eventually notices. The third produces a
**green**, which nobody does.

**Which makes the honest statement of this item:** moving the rows does not change their
coverage, and must not be described as though it does. What it fixes is a table whose header
lies about the shape of a quarter of its rows — the condition that made two unrelated readers
invent the same silent exclusion. If a later item wants those 23 rows *checked* rather than
merely well-shaped, that is a separate predicate over the register table, and it should be filed
as its own item rather than smuggled into this one's acceptance.

## Not in scope

The six-field `D-p*` rows' *content*, which is correct and well-sourced. This is about the
table they are in, not what they say.
