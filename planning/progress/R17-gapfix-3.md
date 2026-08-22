# R17 gap-fix 3 — progress

**Branch:** `ai/r17`, base `13e728b` · **Delivered:** 2026-08-22 · **Scope held:** no code

Two files changed, eight lines in and eight out: `planning/evidence/R17-acceptance.md` and the
`D-r17-d` row in `ORCHESTRATOR.md`. `git diff --name-only` names nothing under `src/`, `app/` or
`scripts/`.

## Acceptance 1 and 2 — the two lines

`:472` read *"the declaration names all four uncovered sites, `src/index.ts` among them"*, split
across lines 472–473 by the file's wrap. It now reads **six**, and the whole sentence sits on one
line rather than being re-wrapped at the file's usual width:

```
472  reproduction — undeclared."* Correct as a fact and already stated: the declaration names all six uncovered sites, `src/index.ts` among them.
```

That is deliberate. The claim's four homes are what four consecutive passes have been chasing, and a
144-character line is the one shape a line-anchored reader cannot mis-report. The paragraph's
remaining four lines were re-wrapped to absorb the moved text; no other sentence in it changed.

`:647` read *"the declaration says which one save it covers and which four it does not"*. It now
reads:

```
647  read window, and the declaration says which one save on each side it covers and which six it does not.
```

Both counts now agree with the declaration itself. `surface.tsv:122` says *one save on each side is
what the declaration covers* and *SIX sites are left uncovered, not four*; `R17-acceptance.md:315`
and `:321-325` carry the node-four-plus-Swift-two breakdown that adds to six, and are unchanged.

## Acceptance 3 — a sweep that can read a wrapped corpus

The previous sweep was line-anchored, so it returned clean over a corpus that still held the claim:
`grep -c "all four uncovered sites"` found 0 where the phrase was present across a line break. The
replacement reads each file whole, collapses every whitespace run — newlines included — to a single
space, matches against that, and maps each hit's offset back to a line number in the original. It
runs over `git ls-files` rather than a hand-listed set of directories, and reports how many files it
could not decode instead of skipping them silently.

Nine patterns: three for the blocking claim, three for every other home of the count, and four
re-running gap-fix 2's classes, which had only ever been checked line-anchored.

```
scanned 1117 tracked files (157 skipped as non-text)

A1  all four uncovered              0 hit(s)
A2  four uncovered sites            0 hit(s)
A3  which four it does not          0 hit(s)
A4  any 'four' near sites/saves     19 hit(s)
      ORCHESTRATOR.md:254   four sites
      ORCHESTRATOR.md:256   four sites
      ORCHESTRATOR.md:261   four sites
      planning/evidence/M14-acceptance.md:161   four rotted test sites
      planning/evidence/M23-acceptance.md:406   four sites
      planning/evidence/P2-acceptance.md:71   four splits: `ImportConfigWriter
      planning/evidence/R17-acceptance.md:315   four `saveManifest` call sites
      planning/evidence/R17-acceptance.md:324   four and two are uncovered
      planning/evidence/R17-gapfix-review-agy.md:64   four `saveManifest` call sites
      planning/evidence/R17-gapfix-review-fable.md:33   four `saveManifest` call sites
      planning/evidence/V1-review.md:150   four sites
      planning/features-to-triage/R17-gapfix.md:90   four sites
      planning/plans/plan-M14.md:4   four rotted test sites
      planning/plans/plan-M14.md:48   four rotted test sites
      planning/plans/plan-M15.md:191   four sites
      planning/progress/R17-gapfix-2.md:95   four (of the )?(saveManifest
      planning/progress/R17-gapfix-2.md:98   four `saveManifest` call sites
      planning/progress/R17-gapfix-2.md:106   four BL-1 citation sites
      scripts/acceptance/mock_fidelity.py:1036   four sites
A5  every 'uncovered site' home     2 hit(s)
      planning/evidence/R17-acceptance.md:318   **six** uncovered sites
      planning/evidence/R17-acceptance.md:472   six uncovered sites
A6  N sites left uncovered          2 hit(s)
      planning/features-to-triage/R19-a-stale-manifest-snapshot-clobbers-a-concurrent-write.md:52   **Six sites are left uncovered
      planning/parity/surface.tsv:122   SIX sites are left uncovered
A7  declaration + a count           12 hit(s)
      ORCHESTRATOR.md:261   declaration is one
      app/Scripts/enum-layout-stamp.py:62   declaration and its cases can share one
      app/Sources/RouterCore/Discovery/HarnessWiring.swift:266   declaration order, so two
      app/Tests/MCPRouterKitTests/RegistryCapabilityTests.swift:302   declaration reads under the same one
      app/Tests/MCPRouterUITests/CleanupRowActionsTests.swift:63   declaration to the next one
      planning/evidence/M23-gapfix-6.md:135   declaration and it was the false one
      planning/evidence/M5-acceptance.md:210   declaration correctly at five
      planning/evidence/R17-acceptance.md:289   declaration cannot afford. The two
      planning/evidence/R17-acceptance.md:472   declaration names all six
      planning/evidence/R17-acceptance.md:490   declaration is one
      planning/evidence/R17-acceptance.md:647   declaration says which one
      scripts/acceptance/m2-activity.sh:62   declaration is one
B1  withdrawn clause (verbatim)     5 hit(s)
      planning/progress/R17-gapfix-2.md:17   indifferent to whether a server is staged
      planning/progress/R17-gapfix-2.md:64   indifferent to whether a server is staged
      planning/progress/R17-gapfix-2.md:65   indifferent to whether a server is staged
      planning/progress/R17-gapfix-2.md:71   indifferent to whether a server is staged
      planning/progress/R17-gapfix-2.md:72   indifferent to whether a server is staged
B2  withdrawn clause (concept)      3 hit(s)
      planning/evidence/R17-gapfix-review-fable.md:37   R19's window is **indifferent
      planning/progress/R17-gapfix-2.md:17   R19's window is indifferent
      planning/progress/R17-gapfix-2.md:84   R19's window is **indifferent
B3  symmetry claim                  2 hit(s)
      planning/progress/R17-gapfix-2.md:67   read-then-save window on both sides
      planning/progress/R17-gapfix-2.md:74   read-then-save window on both sides
B4  'still carry the same'          2 hit(s)
      planning/progress/R17-gapfix-2.md:66   still carry the same
      planning/progress/R17-gapfix-2.md:73   still carry the same

blocking classes A1+A2+A3 total: 0
```

`A1`–`A3` are the blocking classes and are empty. `A5` and `A6` are the point of the pass: all four
homes of the count now say six, and the two the earlier pattern missed — `**six**` behind markdown
emphasis at `:318`, and *SIX sites are left uncovered* in the other word order at `surface.tsv:122`
and `R19*.md:52` — are visible only because the pattern was widened to reach them.

The 19 `A4` hits were each read. Two are the count correctly scoped to node's own inventory
(`R17-acceptance.md:315` and `:324`, the second of which is the node-four-plus-Swift-two breakdown);
two are a different four altogether — the BL-1 citation sites, at `R17-gapfix.md:90` and
`ORCHESTRATOR.md:261`; two are the archived `agy` and Fable lanes quoting the old claim under
attribution; three are gap-fix 2's own progress doc, including its record of the pattern it ran. The
remaining ten are unrelated counts — M14's rotted test sites, V1's `JSNumber` guards, plan-M15's
window destinations, P2's lint splits, M23's `Context.__init__` sites, G3's shape census.
`B1`–`B4` survive only in gap-fix 2's progress doc, which records what it withdrew, and in
`R17-gapfix-review-fable.md:37`, the archived lane quoting the clause in order to refute it.

## Acceptance 4 — gates, measured at this base

Every figure below was produced in this worktree on `ai/r17` at `13e728b` with the edits in place;
none is carried.

| Gate | Result |
|---|---|
| `make test` | exit 0 — `Test run with 1686 tests in 210 suites passed`, `executed 1686 tests` |
| `make lint` | exit 0 — `Done linting! Found 0 violations, 0 serious in 531 files`, `no-raw-design-values: clean` |
| `make parity` | exit 0 — `parity: 358 vector cases compared (floor 358)` |
| `parity-cli.sh` | exit 0 — `cli: 18 verbs agreed, 0 did not`, all four `cli-watch` scenarios `ok` |
| `ledger-reconcile.py` | exit 0 at 14:23 — `reconciled — no findings across A, B, B-range, C, D, E, F, G, H, I, J, K`, `K examined 217 deferred-register rows`. Exit 1 when re-run at 14:33, for a reason outside this branch — below |

### The reconciler went red under us, and the cause was neither this branch nor a merge

The clean run above is real and is the first of two. Ten minutes later the same command exited 1:

```
E. a branch merged into main with no row in either file (the id is spent and both files say it is free)
   G5 (ai/g5)

1 of 10 checks found something. Which file is right is a judgement about what shipped; fix it by hand.
```

Between the runs the merged-branch line went `merged ai/*  26 branches` to `27`, and `ai/g5`
appeared in that listing. `main` gained two commits in that window, at 14:22:37 and 14:30:07. Check E
compares branches merged into `main` against the rows in this branch's `ORCHESTRATOR.md` and
`LEDGER.md`, neither of which carries a G5 row at base `13e728b`.

> **Corrected by gap-fix 4 (BL-3). There was no G5 merge.** This paragraph originally read that
> `ai/g5`'s tip *became an ancestor of `main` — another session's merge, in a shared object store
> this worktree reads but does not own*. The conclusion that paragraph supported — that the finding
> was not this pass's — is right, and the revert test below establishes it properly. The **cause**
> was wrong, and the git state says so plainly: `git merge-base ai/g5 main` is `2fbe062`, a commit
> **on** `main` timed 14:26:58; `ai/g5` was cut from it and had committed **nothing** by 14:33, so
> its tip *was* a `main` commit. `git branch --merged main --list ai/*` therefore listed it from the
> instant it was created, and `main`'s merge list holds M21, R7, M23 and G3 and **no G5**. What made
> that unreadable is the premise at `ledger-reconcile.py:282`, whose docstring calls that listing
> *the hardest evidence an id is taken* — true of a branch with commits, false of an empty one. This
> is the **check-E false-RED**, recorded on `main` as a dispatch hazard and as `D-g4-b`, G4's twelfth
> instance: *a check-E finding naming a branch created after this worktree's base is this, not a
> defect* — confirm from `main` before acting on one. The state has since moved on again, which is
> the same lesson twice: `ai/g5` took two commits at 14:40:51 and 14:48:55, so `2fbe062` is now
> `ai/g5~2`, the branch is no longer an ancestor of `main`, and it no longer appears in that listing
> at all.

That it is not this pass's was measured rather than argued. With `ORCHESTRATOR.md` restored to `HEAD`
and the edit reverted, the reconciler prints the identical finding:

```
K examined 217 deferred-register rows in both files

E. a branch merged into main with no row in either file (the id is spent and both files say it is free)
   G5 (ai/g5)
```

The working file was restored byte for byte afterwards, `sha256
5531bd859eb4b5fd91d2bc33974907e983f287bc491dc8b4c13ce44236a05763` before and after. Check K — the
one this pass's edit could reach — examines 217 register rows and finds nothing in every run.

Check L does not exist on this base: `grep -nE '\("L"\|check L' planning/ledger-reconcile.py` returns
nothing, and the reconciler's own summary line stops at K. *0 across A–L* is unmeetable here and is
not claimed.

Two method notes. `make test` was run twice — once before the `ORCHESTRATOR.md` edit and once after
everything, and the table reports the second. And the first gate chain wrote to `/tmp/g-*.log`, which
another session on this machine already uses: `/tmp/g-gate.log` held a different repo's build output.
That chain was killed and re-run into `/tmp/r17gf3/`, so no figure above shares a path with anything
outside this worktree.

## `D-r17-d` corrected — the rate was wrong and the mechanism is now proven

> **Superseded by gap-fix 4.** Everything below is this pass's measurement and stands as history.
> What does not stand is reading either column as a condition: the fourth verification ran 368
> invocations on a quiet tree and got **0 of 80 at four concurrent** against the 29 of 80 recorded
> here, plus 0 at 8× and 16× and 1 of 96 at 32×. The controlling variable is total machine pressure
> rather than this gate's own concurrency, and the row now states no rate at all. *The mechanism is
> proven rather than suspected* is likewise downgraded there to **proven once and not reproduced
> since** — the fourth verification's single red gave direction A only and could not re-witness the
> both-directions contradiction.

The row claimed a flat *about a quarter to a third of runs*. The third verification refuted that and
replaced it with something stronger, and this pass re-measured the shape rather than carrying it:

| | third verification | gap-fix 3 |
|---|---|---|
| serial, branch `surface.tsv` | 0 of 40 | 0 of 40 |
| serial, main's `surface.tsv` | 0 of 40 | not re-run |
| four concurrent copies, branch | 53 of 104 | 29 of 80 |
| four concurrent copies, main | 24 of 72 | not re-run |

So the red is concurrency-conditional rather than flat, and the concurrent figure on main settles the
reproduces-on-main half properly. The rates differ between the two passes — 51% against 36% — which
is what a contention-dependent race looks like; the two conditions do not.

The mechanism is proven rather than suspected. Across the third verification's runs the gate reported
ten fixture names *in both directions* — each of `add-refused`, `added`, `approve`, `auth-start`,
`patch-response`, `removed`, `server-placarded`, `server-tools`, `servers` and `unauthorized`
appearing both as *on disk and has no manifest row* and as *carries a row, which is not on disk*.
This pass reproduced the shape independently over 80 runs, with `servers` in both directions:

```
direction A (on disk, no row):    approve  approve-conflict  auth-start  changes-none
                                  patch-response  server-pending-change  server-tools  servers
direction B (row, not on disk):   added  reindex-held  removed  server-placarded  servers  unauthorized
in both:                          servers
```

The fixture directory is 24 files, all git-tracked, `git status --porcelain` empty over it for the
whole run. Two mutually exclusive findings about one unchanging file cannot both be true, and cannot
come from the inputs, so they come from the comparison: `parity-manifest-check.sh:431` and `:437`
pipe a `printf` of the list into `grep -qxF` per item and read any non-zero exit as *not found*. It
is not confined to the fixture loop — the cli check at `:189` is the same shape, and named
`src/index.ts dispatches "serve"` for the verifier and `"tools"` here, with the control, authserver,
mcp and oauth comparisons built the same way. The direction stays false-RED.

Recorded, not fixed: this item's scope carries no code. The row keeps its four cells and no pipe
character, and the reconciler reports 0 findings with it in place.
