# G8 acceptance — the executable part

The brief's remaining scope was executable. What had landed before this branch was **ten lines of
header comment** in `scripts/acceptance/mock_fidelity.py` recording M16's cross-branch rule, with
nothing downstream depending on it — which reads as a standard to satisfy rather than a call to
make, and is this item's own subject committed by the item.

Three deliverables, each with the plant that reddened it.

## 1. `planning/role-intersection-gate.py` — the cross-branch check, runnable

`make role-intersection`. Derives the union of every active branch's `VOUCHED_CONTROLS` roles by
`ast.literal_eval` of each ref's copy of the file, then walks **every** fidelity surface against the
added set — including surfaces with zero diff on the gate file, because the quota rule keys on the
build node's role rather than on the edit.

Both sets are established before any question about their members:

| set | how it is established | today |
|---|---|---|
| branches | every local head not already merged into the base | 65 heads, 62 merged, 3 active |
| surfaces | the union of `planning/fidelity/*.ledger.md` across all those refs, deduplicated by blob | 6 measurements, 6 paths, 5 readable |

**The reading it takes, stated rather than assumed.** It reads the tracked ledgers, not the MEASURE
build's `planning/fidelity/dumps/` — which are untracked and whose build exits 3 on this machine. The
ledger records **paired** build nodes only, so this is narrower than the dump reading, and every run
prints each surface's own unpaired remainder (`structure-unpaired`, `extra`, `extra-cited`,
`unclassified`) as its uncovered set. Quietly substituting a narrower instrument is the defect; the
figures are printed instead.

That narrower reading still reproduces the brief's finding exactly. `callout` on `unreadable-note`
is a paired node, so it sits in `harnesses.ledger.md:155` and this gate reddens on it.

**Verdict on this tree: exit 3.** `planning/fidelity/popover.ledger.md` is an obituary — the fidelity
gate exited 3 on `#statusPopover has no '.v-ideal' block` and wrote *"This run did not produce a
table"*. A role sweep over it returns zero, and **a two-state gate reads that zero as a clean
surface**. Here it is `INCONCLUSIVE`. That is a true verdict about the corpus, not a broken gate.

**Denominators, each with its reader named.** `B1..B6` for the branch side, `S1..S3` for the surface
side, and per surface two independent counts side by side: `grep` (line-anchored, what a `grep` sees)
and `wrap` (whole file, whitespace collapsed, `claim-sweep.py`'s reader). They agree at 40/16/0/28/32/3
today because the ledger is generated and does not wrap; the run prints a `**` warning on the row if
they ever disagree, and names the collapsed figure as the complete one. Every intersection row prints
its `file:line` site, because a bare count is what let two parties report *verified* over disjoint
subsets.

## 2. `planning/sweep-control-gate.py` — a presence control on every absence sweep

In `make lint`, eight seconds, hermetic. Discovers sweeps across the whole tracked script corpus with
four named readers, requires a disposition for each, and **runs** the declared controls rather than
believing the registry at `planning/sweep-controls.json`.

```
D0   108  tracked .py/.sh files, vendor/ excluded
D1    85  carrying 1+ marker(s)
D2    58  carrying 2+ marker(s)  <= the threshold
D3    18  carrying 3+ marker(s)
D4     1  carrying 4+ marker(s)
D5    58  discovered as absence sweeps
```

The count at every threshold is printed so the choice of two is visible rather than buried — one
marker alone catches 85 of 108 and would mean nothing.

The registry is a **ratchet**, for `citation-gate.py`'s reason: demanding all 58 grow a runnable
control this week either never goes green or gets softened until it means nothing. So **3 control ·
55 grandfathered · 0 undisposed**, never blended into one figure, and the gate blocks on what is new.
**Grandfathered is a backlog with a number on it, not a pass, and the gate says so on every run.**

Three controls are declared and run: `citation-gate.py --control`, `role-intersection-gate.py
--control-only`, and this gate's own. `claim-sweep.py` is grandfathered with an accurate reason — it
carries the wrap-tolerant reader a control produced but exposes no flag that re-runs it, so its proof
lives in a docstring rather than in an exit code. That is the obvious next entry to promote.

## 3. Every sweep names the normaliser that produced its count

No count in either script is printed bare, and every discovered file names which of `V1..V4` fired on
it. Five sweeps over one phrase in one file returned four answers and only the widest was complete, so
a bare integer from an unnamed reader is an assertion wearing a measurement's clothes.

## Proof that each check can fail

Plant, watch it redden, restore byte-identically, report the hash. An assertion nobody has watched
fail is not known to bite, and this item exists because of exactly that.

| # | plant | before | after plant | restored |
|---|---|---|---|---|
| A | `("board-action", "leaf")` added to `VOUCHED_CONTROLS` on `ai/g8` — a role present on `harnesses` and absent from `main`'s table | `harnesses` CLEAR, `B6` = 0 added | **`harnesses` EXPOSED**, `B6` = 1, three sites printed at `:27`, `:28`, `:127` | `mock_fidelity.py` back to `cacb2947…`, byte-identical to the pre-plant copy |
| B1 | a new tracked sweeping script `planning/PLANT-sweep.py` | 0 UNDISPOSED, exit 0 | **exit 1**, `1 UNDISPOSED`, named with its markers `V2,V3,V4` | removed from the index and the tree |
| B2 | `citation-gate.py`'s declared control rewritten to exit 7 | 3 controls passing, exit 0 | **exit 1**, `FAIL … control exited 7` | `sweep-controls.json` back to `885abffc…`, byte-identical |

**All three of the role gate's exit codes are proved reachable inside the hermetic control**, and this
is not decoration: on the real corpus **exit 1 cannot be observed however much exposure a plant
creates**, because `popover`'s 3 dominates. A findings code that has never been produced is not known
to work, so the fixture produces each of 0, 1 and 3 by filtering its own surfaces.

## The controls, and why they are hermetic

Nothing is planted in this corpus. `G4`'s seventeenth item: a control quoted inside the document it
guards is found by the naive matcher instead of the planted instance, and then passes for the wrong
reason and passes silently.

**Role gate — hermetic**, a throwaway repository with five planted answers, each required exactly:

```
ok    baseline   want CLEAR        got CLEAR
ok    edits      want EXPOSED      got EXPOSED
ok    obituary   want INCONCLUSIVE got INCONCLUSIVE
ok    silent     want EXPOSED      got EXPOSED
ok    `silent` reads EXPOSED with the union and CLEAR without it, so the answer depends on
      the union rather than on the ledger alone
ok    `silent` has zero diff on scripts/acceptance/mock_fidelity.py and is still EXPOSED
ok    exit 0 / 1 / 3 are each reachable
```

`silent` is M22: a branch with **zero diff on the gate file** whose ledger uses a role another branch
adds. It must read EXPOSED. The fail-if-agree row is what stops the fixture proving nothing — an
instrument that answers the same with and without the union has demonstrated nothing.

**Role gate — live presence control**, planted into the parameter rather than into the corpus, so no
string is left for a later sweep to trip over:

```
sees  harnesses  planting role='board-action'   moved its intersection 0 → 3 row(s)
sees  insights   planting role='analyst-panel'  moved its intersection 0 → 1 row(s)
sees  readme     planting role='badge'          moved its intersection 0 → 4 row(s)
sees  servers    planting role='board-subtitle' moved its intersection 0 → 2 row(s)
sees  settings   planting role='board-subtitle' moved its intersection 0 → 1 row(s)
quiet planting role='__role_that_cannot_exist__' matched 0 rows on all 6 surfaces
```

This is what makes today's headline zero a measurement. `B6` is **0** on this tree because M16, M19
and M22 are all merged — the gate's answer is an absence, and an absence check cannot detect its own
blindness.

**Sweep gate — its own control** plants a sweep that must be discovered, a non-sweep that must not,
and a control command that exits 1 that must be reported failing. That third one is the one that
matters: a control-runner that cannot report a failure is a decoration, and executing is this gate's
only advantage over the written rule.

## What is left open

* **The unpaired remainder.** `harnesses` alone carries `structure-unpaired 15 · extra-cited 88 ·
  unclassified 36` with no `role=` anywhere tracked. Closing it needs the MEASURE build's dumps;
  `make mock-fidelity SURFACE=servers` exits 3 today (known-inherited).
* **`popover` has never been measured.** Until it produces a table the role gate stands at 3 and
  stays out of `make all` — wiring a permanent 3 into `all` would mean softening it within the week.
* **55 grandfathered sweeps.** A visible backlog with a count that may fall, not an amnesty.

## Hashes at the close

```
3581db8d…  scripts/acceptance/mock_fidelity.py   (header now points at the check)
971c3df3…  planning/role-intersection-gate.py
425caa8d…  planning/sweep-control-gate.py
885abffc…  planning/sweep-controls.json
```
