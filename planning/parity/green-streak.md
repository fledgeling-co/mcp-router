# The green streak, defined so somebody can check it

`R4-C2` — retiring `src/*.ts` — is **Held**, and the hold is recorded in one phrase:
*owner: not on a green streak*. `REQ-020` says the same thing from the other side: the installer
flips and the TypeScript tree retires *"once parity is 82 of 83 and the owner decides"*.

`R4-C1`'s brief is the sharper statement of it, and it is the one this file answers:

> the deletion waits on one of: a captured reproduction of `DEF-033`, at which point it is a bug
> to fix rather than an unknown; or **a bound somebody states before the runs happen — a number of
> consecutive whole gates including the cold port-reuse path — and then meets.**

Two things were true of that until now. It is the right condition. And **nothing in this repository
could tell you whether it held**, because no run of the parity gate was recorded anywhere, so
"consecutive" had no sequence to count over and "whole gate" had no definition to test a run
against.

This file supplies the definition and the sequence. **It does not supply the bound.** The number of
consecutive passes is a decision, it is the owner's under `REQ-020`, and `R4-C1` is explicit that
stating it *before the runs happen* is what makes it evidence rather than a search for a
formulation under which the answer comes out green.

---

## What counts as one whole-gate pass

One invocation of `scripts/acceptance/parity-gate.sh` with `PARITY_LANES` **unset**, so all sixteen
lanes are dispatched, which:

1. **exits 0 or 1, never 2.** Exit 2 is the gate saying a lane could not run, and a skipped lane is
   not a pass. This is the gate's own distinction — *"Distinct because a skipped lane is not a
   pass"* — and the streak inherits it rather than restating it.
2. **reports 0 DIVERGED.** Any row where the two routers disagreed on the wire ends the streak.
3. **reports no blocked row other than the standing exclusions the manifest itself names.** Today
   that is exactly one: `fixture/fixture-registry-search`, carrying `accepted-uncomparable` in its
   owner column. A row that becomes blocked for any other reason ends the streak.
4. **reports `proven` at or above `PARITY_CUTOVER_TARGET`.** The target is read from
   `PARITY_CUTOVER_TARGET=82`, `scripts/acceptance/parity-gate.sh:381` at `83e5380`, and is a
   decision rather than a measurement. See the drift note below before reading that number.

**Exit 0 is unreachable and clause 1 is written knowing it.** The gate exits 1 while any row is
blocked, and one row is permanently blocked by the owner's own 2026-08-16 decision. A definition
demanding exit 0 would be a definition that can never be met, which is the defect `R4-C1` already
corrected once in `spec-R4.md`'s *"exits 0 — 81 of 81"*.

## The cold port-reuse path

`R4-C1` names it and does not define it, so here is a definition, derived from what the lanes
actually do rather than from the phrase.

Every lane in this harness binds a **fixed** port: `8957`–`8959` for registry, `8961`–`8962` for
authserver, `8963`–`8964` for fixture, `8965` divergence, `8966` pool, `8967`–`8969` oauth,
`8992`–`8993` and `8998` mcp, `8994` cli, `8995` log, `8997` install. None of them searches for a
free port. So two whole-gate runs in succession contend for the same sockets, and `G3` measured
what that produces: `make test` red 1 run in 5 on `listen EADDRINUSE`, *"a port-reuse collision
under load, not a fixed sleep"*.

**A cold port-reuse run is a whole-gate run begun within 60 seconds of the previous whole-gate
run's exit, in a scratch `HOME` carrying nothing from it.** Cold is about the state — no warm
pool, no cached index, no credential left over. Port-reuse is about the sockets — the previous
run's are still in `TIME_WAIT` and this run must bind them anyway.

That is the path a real cutover would take on the day somebody re-runs the gate to check a fix, and
it is the one condition under which this harness has a measured failure mode. A streak of runs
spaced comfortably apart does not speak for it.

**This definition is proposed, not decided.** It is derived from the fixed-port allocation across
the lane scripts and from `G3`'s measured red; it is not something the owner has said. If it is
wrong it should be corrected here, and the point is that it is now the kind of thing that *can* be
corrected, because it is written down as a testable predicate rather than carried in a phrase.

## What ends a streak

A recorded run that is not a pass, by any of the four clauses. Nothing else — not time, not a merge,
not a change to an unrelated part of the tree. Recording only the passes and calling the result a
streak is the failure this whole file exists to prevent, so `green-streak.tsv` takes every run and
`green-streak.sh` counts back from the newest.

`install-launchd-watch` is the cautionary case and `R4-C1` cites it: a term that agreed **1 in 6**
with the losing side alternating. A run that is green because it was run again is not evidence, and
a ledger that holds only the green ones cannot tell the two apart.

## The bound, and why this file leaves it empty

`green-streak.tsv` carries `# bound:` and it is `unset`. While it is unset, `green-streak.sh`
measures and reports the current streak and states plainly that no bound has been decided, so
`R4-C2` stays held. It does not choose a number, and it does not read "the streak is long" as
"the condition is met".

Setting it is one edit by the owner, and `R4-C1`'s condition is that the edit happens **before**
the runs it will be judged on.

## A prior question the streak does not settle

`PARITY_CUTOVER_TARGET=82` was decided on 2026-08-16 against a census of **83** rows. The census
is now **105** — `bash scripts/acceptance/surface-census.sh` prints `total 105`, exit 0 — so
`target_derived=$((total - excluded))`, `scripts/acceptance/parity-gate.sh:402` at `83e5380`,
derives **104**, the two disagree, and the gate takes its drift branch and **withholds the distance
to the target on purpose**.

So clause 4 above is checkable and the phrase *"82 of 83"* is not: there is no 83 to be 82 of any
more. The gate is right to withhold rather than re-derive, the 22-row growth is an owner decision,
and nothing here re-pins it.
