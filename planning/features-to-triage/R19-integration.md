# R19 integration — a merge that needs a person, not a resolution

**Status:** Ready for AI · **Category:** router · Standard tier
**Parent:** R19 (verified **Done** 2026-08-22) · **Branch:** `ai/r19`, five commits
**Raised:** 2026-08-22 by the orchestrator, after aborting the merge deliberately.

## Why this is an item rather than a merge

R19 is verified Done. `git merge ai/r19` into `main` (at `54666f7`, which now carries R17)
conflicts in **`src/watch.ts`** and **`app/Sources/RouterCore/Watch/WatchIndexing.swift`**, and
**`planning/parity/surface.tsv` auto-merges clean** — which is the dangerous half.

**None of the conflicts is a logic conflict.** All three are records, and all three carry evidence
that took five verifications to make true. R19's base predates R17's merge, so where R19's side
"deletes" R17's comment it never made that choice — it simply never had the text. Taking either
side wholesale silently discards one of them, and the orchestrator aborted rather than guess.

## What the merge has to produce

### 1 · `src/watch.ts` — one conflict block

`HEAD` carries R17's ~40-line comment: the route account for why the failure row is now kept, the
owner's 2026-08-21 `namecheap`/`lifeline` measurement, and the *sufficient-not-exclusive* argument
against R19's own mechanism — **including the pre-registered prediction that an R19-only world
predicts the inverse of what was measured**, which is the strongest single piece of evidence R17
produced. `ai/r19` has none of it.

Keep it, updated to R19's world: the stale-save mechanism it describes is now **closed**, so the
paragraph arguing R19 as a live alternative becomes history rather than a standing caveat. Do not
delete the asymmetry argument — it is what makes R17's account survive R19.

### 2 · `WatchIndexing.swift` — two conflict blocks

Block 1 is two versions of the same doc comment. R19's is **correct about the mechanism now**
(*"re-read for every entry, inside the lock (X4b, closed by R19)"*); R17's carries the divergence
declaration and the five-versus-three inventory. Merge them: R19's mechanism, R17's inventory, and
the declaration **removed** rather than restated, because §3 below removes its subject.

Block 2 is R17's *the failure entry is KEPT* comment against R19's restructure. Keep R17's reason;
place it where R19 put the code.

### 3 · `surface.tsv` — the one git will not flag

The `cli-watch` note's **THIRD DIVERGENCE IS DECLARED HERE** section is false the moment R19 lands,
in three specific claims:

- *"node reads it once per run (`src/watch.ts:212`) and saves that same object at `:292`; Swift
  re-reads it per entry"* — R19 makes node re-read per entry too. **The divergence is closed by
  convergence.**
- *"On a fixture that overlaps a second writer Swift keeps both rows and node keeps one"* — no
  longer true.
- The six-site inventory citing `src/index.ts:146`, `:186`, `control.ts:262`, `:432`,
  `AuthRoutes.swift:120`, `ServicePorts.swift:391` — R19 puts all eight inside the lock and node's
  five writers collapse to three.

**Delete the declaration and say what replaced it**: the property is now held by
`scripts/acceptance/parity-overlap.sh`, R19's new lane, which this note said no scenario in the
harness could reach. That is the sentence worth writing — a declared-unreachable property became a
lane.

`surface.tsv` auto-merges, so **nothing will prompt you.** This is the whole reason the item exists.

## 4 · The gate nobody has run

**`parity-cli.sh` must be run on the merged tree.** R17 added a fourth `cli-watch` scenario that
projects the manifest's *shape*; R19 changed the node watcher underneath it. Those two have never
run together — R17's runs predate R19's code and R19's predate R17's scenario. Main reads
`parity-cli.sh` **18/17 verbs** depending on which branch you ask, which is itself a sign these two
inventories have not met.

Also run `parity-overlap.sh` and `parity-gate.sh` on the merged tree, and `make lint` and
`make test`. Baselines to beat, each measured on its own branch and **not on the merged tree**:
lint 0 over 533 (R19) / 531 (R17); `make test` 1687/210 (R19), 1686/210 (R17).

## Acceptance

1. The merge is committed with all three records carrying **both** branches' evidence, and the
   `surface.tsv` declaration deleted with its replacement named.
2. `parity-cli.sh` green on the merged tree, with the verb count stated and the four `cli-watch`
   scenarios named.
3. `parity-overlap.sh` green on the merged tree.
4. `make lint`, `make test`, `parity-gate.sh` and the reconciler run on the merged tree and pasted.
5. A one-paragraph note in `planning/progress/R19-integration.md` saying what each conflict
   resolution kept from which side and why.

## Do not

Re-verify R19 or R17. Both are Done, and their branches are not to be re-litigated — this item is
the join between them and nothing else. If the merged tree contradicts either verdict, that is a
finding to report, not a licence to change the code.
