# R17 gap-fix 4 — stop stating a rate that the next measurement keeps refuting

**Parent:** R17 · **Verdict:** Needs More Work, 2026-08-22 (fourth verification)
**Worktree:** `.worktrees/R17`, branch `ai/r17`, base `0951650`

## What passed

Criteria 1, 2 and 4. `:472` reads *"names all six uncovered sites"* on one 144-character line, and
six is substantively right — five node `saveManifest` sites, three Swift `ManifestIO.save`, one
covered on each side. `:647` reads correctly. Both inventories were re-derived from source by the
verifier rather than carried. Gates unmoved: `make test` **1686 in 210**, `make lint` **0 over
531**, `make parity` **358/358**, `parity-cli.sh` **18/0**, reconciler **0 across A–K**, and check
L is correctly absent from this base.

Criterion 3 passes **in substance** — the claim really is gone from every home. Its *pasted
evidence* does not reproduce, because the sweep was run before the file it reports on was
committed.

## BL-1 — `D-r17-d` states a condition three passes have now failed to reproduce

The fourth verification ran **368 gate invocations on a quiet tree**:

| Condition | Result |
|---|---|
| serial, idle | **0 of 40** — agrees with the row |
| 4 concurrent copies | **0 of 80** — the row says 29 of 80, and earlier 53 of 104 and 24 of 72 |
| 8 concurrent × 12 | **0 of 96** |
| 16 concurrent × 6 | **0 of 96** |
| 32 concurrent × 3 | **1 of 96** — `changes-none`, direction A only |

The fixture directory was git-clean throughout, 24 files. **So the defect is real** — one red on an
unchanged file proves it, and the mechanism is exactly as cited. **The condition is not.** Four
concurrent copies produced one red in 368 runs where the row predicts roughly a third.

The controlling variable is **total machine pressure**, not this gate's own concurrency: every high
rate was recorded while other sessions were loading the box. The row omits that, and it is written
where other work reads it as a recipe.

**This is the third time this cell has stated a reproduction rate that the next measurement
contradicted** — a quarter-to-a-third flat, then 53/104 and 24/72 at 4×, then 29/80 at 4×, now
0/80 at 4×. Each pass inherited a number and produced another.

**So stop stating a rate.** Record the defect, the mechanism, the direction, and the fact that the
rate is load-dependent and has not been stably reproduced — with all four measurement sets as
history rather than as a recipe. A row that says *we cannot yet state the condition* is worth more
than a fourth number.

The orchestrator's fleet-level hazard row in `ORCHESTRATOR.md` has already been corrected this way;
match it rather than diverging from it.

## BL-2 — the both-directions contradiction is not re-witnessed

`D-r17-d` says the mechanism is *proven rather than suspected*, on the strength of ten fixture
names being reported simultaneously in both directions. The fourth verification **could not
reproduce it** — its single red gave direction A only. The claim therefore rests on the third
verification's report and not on anything independently re-witnessed.

Say that. *Proven by one pass and not reproduced since* is a different and honest claim, and it is
the one the evidence supports.

## BL-3 — the progress doc asserts a merge that never happened

`planning/progress/R17-gapfix-3.md` records the mid-pass reconciler change as *another session
merged `ai/g5` into main*. It did not. `git merge-base ai/g5 main` is `2fbe062`, `ai/g5~1` **is**
that commit, and main's merge list holds M21, R7, M23 and G3 and **no G5 merge** — the branch was
empty and trivially an ancestor. The `G5` rows exist on `main` and in no worktree.

The runner's *conclusion* — that the finding was not this pass's — is right and was properly
established by its revert test. Only the cause is wrong. Correct it to what the git state shows,
and cite the known check-E false-RED, which is recorded on `main` as a dispatch hazard and as G4's
twelfth instance.

## BL-4 — the sweep's evidence predates the file it reports on

Either re-run the sweep against the committed tree and paste that, or note in the doc that the
pasted output predates its own file. **Consider committing the sweep as a script**: it is the only
thing that makes the 144-character line unnecessary, and four passes have now turned on whether one
reader could see one phrase.

## Acceptance

1. `D-r17-d` states the mechanism and direction, carries all four measurement sets as history, and
   **states no reproduction recipe** — matching `ORCHESTRATOR.md`'s corrected hazard row.
2. The both-directions claim is downgraded to *proven once, not reproduced since*.
3. The merge claim in `R17-gapfix-3.md` is corrected to the git state.
4. The sweep's evidence either reproduces against the committed tree or is labelled as predating it.
5. Gates unmoved at this base: `make test` **1686/210**, lint **0/531**, parity **358/358**,
   `parity-cli.sh` **18/0**, reconciler **0 across A–K** — A–L is unmeetable here and A–K is the
   correct claim.

## Scope

`ORCHESTRATOR.md`'s `D-r17-d` row, `planning/progress/R17-gapfix-3.md`, and optionally a committed
sweep script. **No code**, and nothing under `src/`, `app/` or `scripts/acceptance/`.
