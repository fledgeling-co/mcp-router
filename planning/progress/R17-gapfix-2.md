# R17 gap-fix 2 — progress

**Branch:** `ai/r17`, base `55075ed` · **Delivered:** 2026-08-22 · **Scope held:** no code

Four files changed, none of them source: `planning/evidence/R17-acceptance.md`,
`planning/features-to-triage/R19-a-stale-manifest-snapshot-clobbers-a-concurrent-write.md`,
`planning/parity/surface.tsv` and `ORCHESTRATOR.md`'s deferred register. `git diff --name-only`
names nothing under `src/` or `app/`, so the compiled-parse proof the work order rests on is
untouched by construction rather than by re-measurement.

One note on where the work order lives: `planning/features-to-triage/R17-gapfix-2.md` is on `main`
at `afc087f` and is not on this branch, whose HEAD merged `main` at `ccf01c7`. It was read with
`git show main:planning/features-to-triage/R17-gapfix-2.md`. Nothing was rebased.

## Acceptance 1 — the withdrawn clause is gone from `R17-acceptance.md:114`

The line read *"and R19's window is indifferent to whether a server is staged"*, five lines below
the paragraph recording that clause as broken. It now reads *"which is the pairing an R19-only
world predicts in reverse, three paragraphs up"*, which points at the correction at `:104-105`
instead of contradicting it. The surrounding paragraph was re-wrapped to the file's width; no other
sentence in it changed.

## Acceptance 2 — the uncovered list names six sites and drops the symmetry

The counts were measured from source before being written, not carried over:

```
$ grep -rn saveManifest src/          # production sites, excluding the definition and imports
src/watch.ts:292  src/index.ts:146  src/index.ts:186  src/control.ts:262  src/control.ts:432
$ grep -rn ManifestIO.save app/Sources/
AuthRoutes.swift:120  ServicePorts.swift:391  WatchIndexing.swift:187
```

Neither side has a second manifest writer: `grep -rn manifestPath app/Sources/ | grep -iE
'write|save|rename'` returns those three lines and nothing else, and the node search for a
`writeFile` against the manifest path returns nothing, so `saveManifest` is exclusive.

`R19.md` now states both inventories with the command each came from, and carries a six-row table
of what is uncovered and what each site faces on the other side. The table is what kills the
pairing claim: only `src/control.ts:432` and `AuthRoutes.swift:120` are a positional pair.
`src/index.ts:146` and `:186` have no `ManifestIO.save` twin, because Swift routes `index` and
`import` through `ManifestIndexer.record`, which re-loads at `ServicePorts.swift:381` and saves at
`:391` **per entry** where node loads and saves once per run. `surface.tsv`'s `cli-watch` note
carries the same six sites, and now names `AuthRoutes.swift:120` and `ServicePorts.swift:391`,
which appeared nowhere in it before.

Two changes inside the scoped files go slightly beyond the literal clause, and are called out here
rather than left for a reader to find. First, `R17-acceptance.md:315` attributed both
`src/index.ts:146` and `:186` to the `index` verb; `:146` is `cmdImport`'s adopt path, and the
register row `VER2-R17-3` turns on that distinction, so the verb is corrected and the six-site
total made explicit in the same sentence. Second, three places said the policy runs *over all five
sites* — `R19.md`'s acceptance 1, `R17-acceptance.md:325` and `surface.tsv` — where five is node's
count alone. All three now name both inventories. No new total was coined: writing *eight* into one
file while three others said five would have reproduced exactly the defect this pass exists to fix.

## Acceptance 3 — the grep, over everything that could hold either claim

Run from the worktree root over `planning/`, `docs/`, `app/`, `src/`, `scripts/`, `ORCHESTRATOR.md`,
`PRD.md` and `README.md`, excluding `.build`, `node_modules` and `.git`.

The verbatim check, four fixed strings, each returning grep exit 1:

```
$ for pat in "window is indifferent to whether a server is staged" \
             "indifferent to whether a server is staged" \
             "still carry the same" \
             "read-then-save window on both sides"; do
    grep -rn --exclude-dir=.build --exclude-dir=node_modules --exclude-dir=.git -F "$pat" \
      planning/ docs/ app/ src/ scripts/ ORCHESTRATOR.md PRD.md README.md
  done
### -F "window is indifferent to whether a server is staged"   no match (grep exit 1)
### -F "indifferent to whether a server is staged"             no match (grep exit 1)
### -F "still carry the same"                                  no match (grep exit 1)
### -F "read-then-save window on both sides"                   no match (grep exit 1)
```

A fixed-string grep only proves the sentence is gone, so both claims were also swept as concepts.
Claim A, `grep -rniE 'indifferen'`, returns five lines:

```
planning/evidence/R17-acceptance.md:100   sharper than indifference. A stale save can only erase…
planning/evidence/R17-acceptance.md:109   merely *indifferent* to staging when it is *anti-correlated*…
planning/evidence/R17-gapfix-review-fable.md:11   rather than indifferent to it.
planning/evidence/R17-gapfix-review-fable.md:37   "R19's window is **indifferent** to whether a server…
planning/plans/plan-M15.md:178            board-registry.sh's awk reader is indifferent to the wrap
scripts/acceptance/board-registry.sh:20   is indifferent to how the collection is wrapped
```

The first two are the withdrawal's own reasoning and its record. The two `R17-gapfix-review-fable`
lines are the Fable lane's archived output, preserved verbatim at `fe8d012`, quoting the claim in
order to refute it — the reason the fixed-string grep misses line 37 is the `**` around the word.
Those are left alone: a review record that no longer contains what the review broke stops being a
record. The last two are unrelated senses of the word. The assertion itself survives nowhere.

Claim B, `grep -rniE 'other four|those four|four (of the )?(saveManifest|ManifestIO|uncovered|sites|twins)|read-then-save'`, returns 32 lines. Three bear on the claim:

```
planning/evidence/R17-acceptance.md:315        …does not cover the other four `saveManifest` call sites
planning/evidence/R17-gapfix-review-agy.md:64  > "It does not cover the other four `saveManifest`…"
planning/evidence/R17-gapfix-review-fable.md:33 "It does NOT cover the other four `saveManifest`…"
```

`:315` is node's four, correctly scoped, and the same sentence now states the six-site total. The
other two are the archived review lanes quoting the claim under attribution. The remaining 29 are
other counts of four — `spec-G1.md`'s Mac launchers, `R8`'s zero-tool upstreams, `surface.tsv`'s
FOUR parity scenarios, `R17-gapfix.md:90`'s four BL-1 citation sites — none about manifest writers.

## Acceptance 4 — gates

| Gate | Result |
|---|---|
| `make test` | exit 0 — `Test run with 1686 tests in 210 suites passed`, `executed 1686 tests` |
| `make lint` | exit 0 — `Found 0 violations, 0 serious in 531 files`, `no-raw-design-values: clean` |
| `make parity` | exit 0 — `parity: 358 vector cases compared (floor 358)` |
| `parity-gate.sh` | exit 1, the branch's standing state — `manifest-check: 92 rows`, `divergences: 4 as declared, 0 stale`, `parity: 89 of 92 rows proven (4 of them by suite only), 1 blocked` |
| `ledger-reconcile.py` | exit 0 — `reconciled — no findings across A, B, B-range, C, D, E, F, G, H, I, J, K`, over `K examined 217 deferred-register rows` |
| `parity-cli.sh` | exit 0 — `cli: 18 verbs agreed, 0 did not`, all four `cli-watch` scenarios `ok` |
| `r6-child-path.sh` | exit 0 — `examined=6 failures=0` |
| `r7-harness-reconciliation.sh` | exit 0 — `r7-harness-reconciliation: pass` |

Two of those need their own sentence. The reconciler on this branch runs checks **A through K**;
check L was added on `main` at `afc087f` and is not in this worktree, so *0 across A–L* cannot be
claimed from here and is not. And `parity-gate.sh` exits 1 on this branch by standing state rather
than by regression — one blocked row, `pool-p4` and `pool-reap-traffic` on R2-R — which is what
`R17-acceptance.md` already records for it.

## Open — `parity-manifest-check.sh` is not deterministic

The gate's first stage reds on a different subject each run, and every subject it names has a row.
Over roughly 60 invocations today it exited 1 on about a quarter to a third of them, naming the
fixtures `add-refused`, `auth-start`, `servers`, `usage-reset` and `changes-pending`, the row ids
`div-r1-d3`, `div-r1-d3-control` and `control-auth-post`, the route `GET /registry/search`, and the
`usage` verb — three of those in one run:

```
  control.ts answers "GET /registry/search" and the manifest has no row for it
  src/index.ts dispatches "usage", which is neither a cli manifest row nor a declared alias.
  fixture "changes-pending" is on disk and has no manifest row
manifest-check: 3 problem(s).
```

`control-registry-search` is at `surface.tsv:50` and `fixture-add-refused` at `:75`. It reproduces
on `main`'s `surface.tsv` as well as on the edited one, so it is not this pass's. The two lists the
fixture comparison comes down to are byte-identical over 30 samples each, so the inputs are stable
and the flake is in the per-item comparison rather than in what it reads. Suspected and not proven:
every comparison pipes a `printf` of the list into `grep -qxF`, one subprocess per item over 92
rows, and reads a non-zero exit as *not found*. An instrumented copy saw no `grep` exit other than 1
in 40 runs, so the locus is narrowed and the mechanism is open. The direction is false-red, not
false-green. Registered as `D-r17-d` rather than fixed, since this item's scope carries no code.

## Register rows added

`D-r17-a` carries `VER2-R17-3`, `D-r17-b` carries `VER2-R17-4`, `D-r17-c` carries `VER2-R17-5`, each
stating the finding and marked *registered rather than fixed*. `D-r17-d` is the flake above, which
the work order did not ask for; it is registered because the register is where this repo keeps a
finding it is not acting on, and a gate that reds a third of the time with no record is what sends
the next runner chasing it. All four use the `D-<parent>-<letter>` form the reconciler excludes by
design, carry four cells, and contain no pipe character. `ledger-reconcile.py` reports 0 findings
with them in place.
