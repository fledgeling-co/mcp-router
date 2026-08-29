# Cutover readiness — what is derivable today, and what is not

`R33` asks for the current parity figure *"reported against the 82-of-83 target, derived rather
than quoted"*. **It cannot be, and saying so precisely is the answer rather than a failure to
produce one.** This file says what is derivable, what is not, and why each is which.

Everything below was measured on `83e5380`, 2026-08-29.

---

## 1. There is no "82 of 83" to report against any more

`PARITY_CUTOVER_TARGET=82`, `scripts/acceptance/parity-gate.sh:381` at `83e5380`, was decided by
the owner on 2026-08-16 against a census of **83** rows, with `fixture-registry-search` named as
the standing exclusion.

The census is now **105**:

```
$ bash scripts/acceptance/surface-census.sh
total   105
group   authserver   8      group   fixture     24      group   overlap   2
group   cli         10      group   install      5      group   pool      6
group   control     17      group   log          1      group   state     1
group   divergence  26      group   mcp          5
exit 0
```

`target_derived=$((total - excluded))`, `scripts/acceptance/parity-gate.sh:402` at `83e5380`,
therefore derives **104**, against a pinned target of **82**. The gate compares the two, finds they
disagree, and takes its drift branch:

> the distance to that target is NOT stated, because the target and this census disagree and the
> distance is arithmetic on the target.

**That withholding is correct and is not worked around here.** A ratio of any current figure to 82
would be a fraction of a denominator nobody chose: the target was set against a surface that has
since grown by 22 rows, and re-deriving it silently is the one move `parity-gate.sh` says in its
own header it will not make — *"a drift here is a claim that needs an owner, not a measurement this
run is entitled to overturn"*. The owner held the pin at 82 once already, on 2026-08-23, with the
derived figure at ~91. This item does not re-open that.

So: **no numerator is invented and the target is not re-pinned.** The 22-row growth is an owner
decision and `REQ-020` reserves the cutover to them.

## 2. What IS derivable, and what it is a statement about

Two things, and they are different claims:

**The manifest's own recorded verdicts.** 105 rows: **92 `proven`**, **12 `proven-by-suite`**, **1
`blocked`** — and that one blocked row is `fixture/fixture-registry-search`, carrying
`accepted-uncomparable` in its owner column, which is the standing exclusion itself. So the
manifest records 104 of 105 rows as provable with nothing outstanding but the exclusion.

**That is a statement about the manifest, not about the two routers agreeing today.** `proven` in
the manifest is what a lane established when it last ran. The live figure comes from
`parity-gate.sh` reconciling this run's lane results against the manifest, and **no whole-gate run
was taken for this item**: this worktree has no `node_modules`, no `dist/index.js` and no Swift
build, so a run would have exited 2 on environment, and an exit 2 is not a parity figure. Quoting
the manifest's numbers as though a gate had just produced them is exactly the substitution this
file exists to refuse.

`planning/parity/green-streak.tsv` is where a live figure would be recorded, and it holds zero runs
today. That is the honest state of the streak as well as of the figure.

## 3. Which router carries each merged item, and whether it is reachable

Measured from each landing's own diff by `scripts/acceptance/carrier-census.sh`, dispositioned in
`planning/parity/carriers.tsv`, and re-measured on every `make lint` by
`planning/carrier-parity-gate.py`.

The five items delivered for the 2026-08-28 goal:

| Item | Landing | Touched | Carrier | Reachable on a default install |
|---|---|---|---|---|
| R28 — the extension store | `784dde9` | 12 Swift, 0 TS | swift-only | yes |
| R29 — session push, tool-list reload | `b80c638` | 0 Swift, 6 TS | typescript-only | **no** |
| R30 — ingest | `516be61` | 16 Swift, 0 TS | swift-only | yes |
| R31 — cache invalidation | `567b5a1` | 14 Swift, 0 TS | swift-only | yes |
| R32 — the Desktop entry | `034251b` | 6 Swift, 0 TS | swift-only | yes |

"Reachable on a default install" is derived, not asserted: `MCPR_ROUTER="${MCPR_ROUTER:-swift}"`,
`docs/install.sh:39` at `83e5380`. A fresh install selects the Swift binary, so the four Swift
items answer on it and R29 does not.

**The reachability column and R33's own measurement point in opposite directions, and both are
right.** R33 measured launchd agents running `node dist/index.js` on 2026-08-28, which is the
inverse: R29 answers there and the other four do not, which is why `GET /caches` returned 404 while
`GET /sessions` returned 200. That machine's agents were installed before `R4-C1` pointed the
installer at Swift and have not been reinstalled since. **What is installed on a given machine is
not a fact this repository holds**, and neither the ledger nor the gate pretends otherwise. What
the repository can say is which binary a fresh install selects, and it says exactly that.

Whichever binary is installed, **the split is real in both directions**: one of the five items is
unreachable on any given install, and which one depends on the install rather than on the code.

## 4. What is now armed against this happening again

`planning/carrier-parity-gate.py`, in `make lint`. Every landing on the first-parent line at or
after `afaad59` — the goal that produced these five items — that touched one implementation and not
the other needs a row in `planning/parity/carriers.tsv` giving its carrier and a reason. The
carrier is re-measured from the diff on every run, so a row that disagrees with the tree is a
finding rather than a record.

It does **not** require parity, and it never says one-sidedness is a defect. Each item was built
where its subject lives; `R4-C1` pointed the installer at Swift and deliberately kept the
TypeScript tree as the harness's reference; `REQ-020` reserves the retirement. What was missing was
never the porting — it was that nobody had to say the split existed.

29 one-sided landings sit before the pin. They are printed as a stated backlog on every run, with a
count, and never as a pass.

## 5. What this item did not do

No cutover. No re-pin of `PARITY_CUTOVER_TARGET`. No edit to `surface.tsv`. No live parity figure,
because no whole-gate run was taken. No bound set on the green streak — that number is the owner's
under `R4-C1`'s own condition that it be stated *before* the runs it is judged on.
