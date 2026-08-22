# R19 integration — progress

**Branch:** `ai/r19` · **Merge:** `327f38f`, `git merge main` with `main` at `adfa923` ·
**Delivered:** 2026-08-22 · **Scope held:** the join between R19 and R17, and nothing else

Neither branch is re-litigated here. R19's code and R17's code both stand; what this item settles is
what the records say once the two are in one tree, and what the gates say when they are run together
for the first time.

## What each resolution kept, from which side, and why

**`src/watch.ts`** — R19's lock structure, R17's kept row, R17's account.

R19's commit closure carried the base's `delete next.servers[name]` forward into the locked span. It
never chose that against R17; R19's base predates R17's merge, so it inherited the delete along with
everything else. R17 is the later decision, it reverses that delete, and two things behind it settle
the merge without any judgement of mine: `IndexFailureRecordTests` asserts the row survives a watch
run, and `parity-cli.sh`'s fourth `cli-watch` scenario compares the manifest's *shape* between the
two binaries, `reason=yes` included. A merged tree that kept R19's delete on the node side would
have failed both. So the delete goes and the lock stays.

R17's ~40-line comment is placed where the delete used to be, above the `failed` loop, with one
paragraph rewritten. The paragraph arguing R19 as a live alternative mechanism is now history: R19
landed in the same commit that carries this comment, so the stale save it describes is closed and
the two accounts no longer compete for the same observation. **The asymmetry argument and the
pre-registered prediction are kept verbatim in substance** — a stale save can only erase a row
written by someone else during the window, so an R19-only world predicts staged `namecheap` keeps
its row and unstaged `lifeline` loses one, which is the opposite of what was measured. That is what
makes R17's account survive R19 rather than merely fit beside it, and deleting it would have thrown
away the strongest single thing R17 produced.

**The watcher's own commit closure survives, minus the delete**, and it is now byte-for-byte
`manifestCommitter`'s policy written out rather than called. Collapsing the two was the one call in
this item where I could name what each option loses, so it went to a second model rather than to my
own preference: keeping the closure was the answer, on the ground that collapsing it is a refactor
neither branch made and a merge is the wrong commit to smuggle one into. It would also have moved
node's writer count from three to two, and `surface.tsv`, this file and R19's own progress note all
quote that census. The closure carries a comment saying it is a duplicate and why it was left.

**`app/Sources/RouterCore/Watch/WatchIndexing.swift`** — R19's mechanism, R17's inventory, R17's
declaration removed.

The header takes R19's version of the X4b paragraph, because R19's is the one that is correct about
the mechanism now: the re-read is per entry *and inside the lock*, which is the deferred child D-w3
closing rather than the window merely narrowing. R17's inventory is kept as the history it now is —
the two sides were five `saveManifest` sites against three `ManifestIO.save` sites and were not a
pairing — and then says what is true on this tree, which is that they are three against three and
pair verb for verb. R17's divergence declaration is **removed rather than restated**, because §3
below removes its subject.

The second Swift block is the mirror of the node one. R17 deleted the `removeEntry` helper; git
auto-merged that deletion and left R19's call to it sitting inside the locked span, so the merged
tree did not compile until the call went. Removing it is the same decision the node side forced, and
R17's reason is placed inside the lock where R19 put the code.

**`planning/parity/surface.tsv`** — the file git merged clean, and the reason this was an item.

The `cli-watch` note's `A THIRD DIVERGENCE IS DECLARED HERE` section is deleted. It was false in
three ways the moment R19 landed: node no longer reads the manifest once per run, so the divergence
is closed by *convergence* rather than by a fix; a fixture overlapping a second writer no longer
keeps both rows on one side and one on the other; and the six-site inventory it enumerated is now
zero uncovered sites, because R19 put every writer on both sides inside the lock.

**What replaced it is named, and it is the sentence worth writing:** the property the note said no
scenario in this harness could reach is now held by `scripts/acceptance/parity-overlap.sh`, R19's
own lane, whose two `overlap` rows keep two writers live at the same moment. A declared-unreachable
property became a lane.

## Two more records the merge falsified, which the item did not list

The item named three. There were five.

**`scripts/acceptance/parity-overlap.sh` asserted the pre-R17 manifest contents.** R19's lane
asserts the row set after the overlap equals `lifeline` exactly. It was written when the watcher
deleted a failed server's row, so the staged `slowfail` left nothing behind. R17 keeps that row, so
the set is now `lifeline,slowfail` and the lane went red on its first run against the merged tree —
**with both binaries agreeing and `lifeline` present on both**, which is to say the property the
lane exists for held and only its expected literal was stale. The expectation is updated and kept
**exact** rather than loosened to a containment check, and the comment says why the set is two names.

**The same lane's recorded arm in `surface.tsv` moved.** The `overlap-watch-index` row records that
arming node with the pre-R19 stale snapshot leaves the manifest EMPTY. Re-measured on this tree, the
same arm leaves it holding `slowfail` alone, because the stale snapshot now carries the failure row
instead of deleting it. `lifeline` is still lost, so the verdict is unchanged and the leftovers are
not; the row now carries both measurements and says which tree each came from.

## The gate nobody had run

`parity-cli.sh` **green, 18 verbs agreed, 0 did not**, on the merged tree. Main reads 18 or 17
depending on which branch is asked; measured here it is 18. The four `cli-watch` scenarios are
*nothing staged takes the fast path*, *a staged server is indexed, adopted and unstaged*, *an
unparseable ~/.claude.json writes nothing*, and R17's *two upstreams failing at different points each
leave a row* — the fourth being the one that had never run against R19's watcher. It compares
streams, exit code, `servers.json`, the remaining `~/.claude.json` and the manifest's shape, and all
four agree.

**R17's mutation proof still holds against R19's code**, which is worth more than the green run. Arming
the node watcher alone with the delete reproduces `surface.tsv`'s recorded string verbatim —
`manifest:[0a1,2 > deadcommand tools=0 reason=yes > refuseslist tools=0 reason=yes]` — while the
other three scenarios stay green, so the projection is still measuring the row and not the fixture.

## Gates, measured on this tree

| gate | result |
|---|---|
| `make lint` | **0 violations over 552 files**, exit 0 (baselines 533 on R19, 531 on R17; `main` at `43e4199` read 549) |
| `make test` | **1728 tests in 216 suites passed**, exit 0 (baselines 1687/210 on R19, 1686/210 on R17; `main` read 1725/215) |
| `parity-cli.sh` | 18 verbs agreed, 0 did not — exit 0 |
| `parity-overlap.sh` | 2 agreed, 0 did not — exit 0 |
| `parity-gate.sh` | **exit 1**, one diverged row, below |
| `planning/ledger-reconcile.py` | exit 0 — *reconciled, no findings across A–L*; 95 LEDGER rows, 95 ORCHESTRATOR rows, 29 merged `ai/*` branches |
| `planning/claim-sweep.py` | **exit 1**, 11 blocking-class hits, all inherited from `main`, below |

R17's `IndexFailureRecordTests` — *a failed index leaves a record* — passes on this tree, against
R19's locked watcher. That is the direct evidence that the Swift resolution is the right one rather
than merely a plausible one.

`parity-manifest-check.sh` inside the gate reads **94 rows, consistent with `control.ts`, `index.ts`,
`router.ts` and the fixture directory; every cited test, script and row id resolves** — which is what
checks the citations in the rewritten `cli-watch` note. The census is 94 because R19 adds the two
`overlap` rows to the base's 92, and R17 added none.

### The one red in `parity-gate.sh`, and why it is not this item's

`control POST /servers/:name/auth` — *2 of 21 checks disagreed: swift reports the server as
authorized; GET /servers/:name's auth sub-object*. Every other lane is proven, `overlap` at 2 of 2
and `cli` at 10 of 10, and `divergences: 4 as declared, 0 stale`.

This is the load-dependent race both parent items already recorded, in nothing this merge touches.
R19's own note has it at 19 of 21 on two standalone runs and the first gate run and 21 of 21 on the
second; it also records that R17's verifier measured the same 19 of 21 on `main` on 2026-08-22, and
`control.ts`'s own comment says which side loses the race is a property of the machine that day.
Measured here on a quiet tree: **standalone `parity-oauth.sh` 3 runs — 19/21, 21/21, 21/21**, and
**inside `parity-gate.sh` 4 runs of 4 at 19/21**. That split is itself worth recording: the row is
mostly green run alone and was red on every gate run here, so whatever the race turns on, the gate
supplies more of it than a standalone run does. Reported, not chased; both parent items are Done and
this is not a licence to touch either one's code.

### The claim sweep's red is inherited

`planning/claim-sweep.py` exits 1 on 11 blocking-class hits, in `ORCHESTRATOR.md`,
`G4-assertions-that-do-not-read-their-own-quantity.md`, `R17-gapfix-2.md` and `R17-gapfix-3.md`.
None is a file this item touches. The withdrawn wording those hits are for is R17's, and this note
does not quote it — the script's own docstring warns that a progress doc pasting a clean sweep
becomes the next sweep's corpus hit, and `planning/progress/R19-integration.md` is not in its
`RECORDS` exclusion. Counted with a whitespace-collapsing grep across three revisions, that wording
appears **0 times on `a27fd52` (R19's tip), once in each of `ORCHESTRATOR.md` and the G4 brief on
the `main` that was merged, and the same once on the merged tree** — so the merge carries the hits
in from `main` unchanged rather than reintroducing them. Two of the four sit under
`planning/features-to-triage/`, which the script's `RECORDS` exclusion does not cover; it excludes
`planning/progress/R17-gapfix-*.md` only.

## The absence claim in the rewritten note, and the negative half of it

The new `cli-watch` text says there are **no uncovered manifest-writer sites left to enumerate**.
That is an absence claim, so it was measured with an instrument that can fail rather than by reading.
A brace-matched checker takes every `saveManifest(` and `ManifestIO.save(` call, blanks comments
first so a doc comment naming a function is not read as a call to it, and asserts each write falls
inside a lock block opened by `withExclusiveLock` / `ConfigMutationLock.withExclusiveLock` — or, for
one level of indirection, inside a helper every call to which is itself inside one.

**6 of 6 covered, exit 0.** `src/manifest.ts:190` in `manifestCommitter`, `src/watch.ts:265` in the
watcher's closure, `src/control.ts:465` on approve, `AuthRoutes.swift:173` via `promote()`,
`WatchIndexing.swift:209`, `ManifestIndexer.swift:186`.

**Both negative halves were run.** Moving node's watch save outside its closure takes the checker to
5 of 6, exit 1; moving Swift's outside its block does the same. In both arms the naive control that
must *not* notice — `grep -c withExclusiveLock` on the same file — still returns 2 and 1
respectively, so a presence check passes exactly where the real one fails. That is the gap the
instrument exists to cover, and it was demonstrated rather than asserted.

The two arms in §"The gate nobody had run" and the two in `surface.tsv`'s re-measurement were run on
copies or restored with `cp` from a pristine snapshot; `git diff HEAD -- src/watch.ts` is empty and
the working tree holds only the two intended files.

## What is left open, and for whom

- **`parity-gate.sh` is red on `control/POST /servers/:name/auth`.** Pre-existing, race-dependent,
  recorded on both parent branches, and untouched by this merge. It is the orchestrator's call
  whether the merge to `main` waits on a green gate run for a row that has never been reliably green.
- **`main` moved twice during this item, and the second parent is not the commit this item was
  briefed against.** The brief names `54666f7`; it read `43e4199` when this session started, and by
  the time `git merge main` ran it was `adfa923` — one commit further, *A measurement that moved a
  file aside and never moved it back*, which touches nothing under `src/`, `app/Sources/RouterCore/`,
  `scripts/acceptance/parity-*` or `planning/parity/`. **`git rev-parse 327f38f^2` is `adfa923`, and
  that is what every figure below the line was measured against.** By the end of the session `main`
  was `bc39aa1`, whose own message reads *main's make lint is red, and both causes are G4's doctrine
  broken by G4's gates* — so the orchestrator's merge will be onto a tree this item has not gated.
- **The duplicated commit closure in `src/watch.ts`** is a one-line item for someone: collapse it
  into `manifestCommitter` and move the census in the two files that quote it. Deliberately not done
  inside a merge.
- **`R19.md`'s arm table records `reference:[rows=(none), wanted lifeline]`** for the stale-snapshot
  arm. On this tree the same arm reads `rows=slowfail`. R19's note is a record of R19's branch and is
  not rewritten here; `surface.tsv` carries both measurements, which is where a reader of the merged
  tree will look.
