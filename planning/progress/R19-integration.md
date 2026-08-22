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
everything else. R17 is the later decision, it reverses that delete, and two instruments behind it
settle the merge without any judgement of mine — **one instrument per side, not both instruments
for both sides.** Which one guards which half is the useful thing to write down, and it is what
this paragraph now says. *(It said something else, and something false, until gap-fix 1; the
withdrawn sentence and how it was disproved are in the closing section of this note.)*

**`parity-cli.sh` pins the node side.** Its fourth `cli-watch` scenario compares the manifest's
*shape* between the two binaries, `reason=yes` included. Put `delete next.servers[name]` back into
`src/watch.ts` alone and the scenario reddens with the mutation string `surface.tsv` records
verbatim, while the other three stay green. `IndexFailureRecordTests` stays **green** through that
same arm, and it could not do otherwise: it is a Swift test — `@testable import RouterCore`,
driving `WatchWorld.runner` and `ManifestIO` — and no path through it executes `src/watch.ts` at
all.

**`IndexFailureRecordTests` pins the Swift side.** Restore the effect of R19's `removeEntry` call
inside `WatchIndexing.swift`'s locked span and the suite fails with 11 issues. `parity-cli.sh` is
not what catches that one.

So the delete goes on **both** sides and the lock stays, each side held by the instrument that can
see it. The two are **complementary rather than redundant**, which is the argument for carrying
both: `parity-cli.sh` is differential — it diffs node's streams, exit code and files against
Swift's — so it reddens on a one-sided regression and would stay **green** if both sides regressed
together, because the two would still agree. `IndexFailureRecordTests` is absolute on the Swift
side and blind to node, so it cannot be fooled by agreement. Between them the both-at-once case
that the differential lane structurally cannot see is still caught.

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
**inside `parity-gate.sh` 4 runs of 4 at 19/21**. Reported, not chased; both parent items are Done
and this is not a licence to touch either one's code.

**A gate run is two draws, not one, and that is deliberate.** `parity-oauth.sh` executes twice
inside every full gate — once as the `suite` lane's citation of it, once as the `oauth` lane itself
— and between the two copies a `fail` wins. The mechanism is written down in
`scripts/acceptance/parity-suite.sh`, at the comment closing *"which is the right precedence for a
finding nobody can explain yet — DEF-033"*, and it is kept rather than deduplicated because on
20 Aug 2026 the two copies disagreed inside a single gate and a single run would have reported a
clean 82 of 83 with nobody the wiser. That is the piece the account above was missing: a clean
standalone run of this script would go unnoticed inside a gate, because the gate takes the worse of
two draws where a standalone run takes one. So part of "the gate supplies more of it" runs through
the harness rather than through the machine — **incomplete rather than wrong**, and now complete.

**The 4-of-4 does not reproduce.** This item's verifier ran the full gate three times on the merged
tree and got **red, green, green** — `control 16 of 16 proven` on both greens, no diverged row at
all. It also caught the two copies disagreeing *inside* one gate: the suite citation read 19 passed
2 failed while the oauth lane read 21 passed 0 failed, twenty minutes apart in the same run. The
failing check is a single unretried `grep -q '"authorized":true'` in `parity-oauth.sh` against a
value the Swift router reaches asynchronously — the shape of a check that loses under load, not one
that has found a divergence.

**Gate and machine are confounded in both datasets, and this note states no rate.** The verifier's
only red landed at load average 400 on 16 cores with its two greens at 175 and 23, and a full gate
costs eight to ten minutes of sustained load that a standalone run never generates — so the two
candidate causes move together in its runs and in the four recorded above, and neither set can
separate them. This cell of the record has now published a reproduction rate that the next
measurement contradicted, four times running, and the fifth is not written here. The confounding is
the finding. If anyone prices the row, the remedy is a bounded poll in place of that single `grep`,
not another census.

### The claim sweep's red is inherited, and it is not the claim it looks like

`planning/claim-sweep.py` exits 1 on **11 blocking-class hits**, and they are three patterns for
one claim: classes **A1 (5 hits), A2 (5) and A3 (1)**, all of them R17's withdrawn count of
manifest-writer sites sitting outside the lock. They live in four files — `ORCHESTRATOR.md`,
`planning/features-to-triage/G4-assertions-that-do-not-read-their-own-quantity.md`,
`planning/features-to-triage/R17-gapfix-2.md` and `planning/features-to-triage/R17-gapfix-3.md`.
The matched phrases are named by class id and not quoted here: the script's own docstring warns
that a progress doc pasting a sweep becomes the next sweep's corpus, this file is not in its
`RECORDS` exclusion, and quoting them would make this note hits twelve and thirteen.

**None of the four is a file this branch writes, so the hits are inherited rather than
introduced.** `git diff --name-only adfa923..eb3e42c` — the merge base against this tip — lists
twenty files and none of these four; all four blobs are identical between this tip and `adfa923`,
which is a commit on `main`; and running the three blocking patterns over `main`'s *current* copies
counts the same 11 — measured at `87f6f2e` and again at `4a56120`, twenty minutes later, because
`main` moved between the two. The last two checks are deliberately of different kinds for exactly
that reason: a blob comparison against `main`'s tip rots inside the hour, while *this branch never
wrote these files* does not.

**The wording a reader is most likely to reach for is a different claim, and it blocks nothing.**
That is classes **B1 and B2** — the withdrawn clause about R19's window and staging — hitting
twice, in `ORCHESTRATOR.md` and `R17-gapfix-2.md`, and `BLOCKING = ("A1", "A2", "A3")` in
`planning/claim-sweep.py` keeps both out of the exit code. Neither hit asserts the claim either:
both are the block reports that withdrew it, so deleting them would delete the record of the
withdrawal. Editing that wording would change nothing about the red and would cost the corpus its
own history — worth writing down, because this item's own brief pointed there.

The script is wired into no target — `git grep claim-sweep -- Makefile scripts` returns nothing —
so its exit code blocks nothing mechanically, and closing it means editing `ORCHESTRATOR.md` and
two other items' briefs while the orchestrator is writing `ORCHESTRATOR.md` concurrently. Follow-up
for the orchestrator, not this item. The cheaper fix is in the script rather than the corpus:
`RECORDS` excludes `planning/progress/R17-gapfix-*.md` but not the `planning/features-to-triage/`
copies of the same documents, and **7 of the 11 live in those two copies** — A1×1, A2×1, A3×1 in
`R17-gapfix-2.md` and A1×2, A2×2 in `R17-gapfix-3.md`, counted off the script's own per-class
output.

## The absence claim in the rewritten note, and the negative half of it

The new `cli-watch` text says there are **no uncovered manifest-writer sites left to enumerate**.
That is an absence claim, so it was measured with an instrument that can fail rather than by reading.
A brace-matched checker takes every `saveManifest(` and `ManifestIO.save(` call, blanks comments
first so a doc comment naming a function is not read as a call to it, and asserts each write falls
inside a lock block opened by `withExclusiveLock` / `ConfigMutationLock.withExclusiveLock` — or, for
one level of indirection, inside a helper every call to which is itself inside one.

**6 of 6 covered, exit 0.** `src/manifest.ts:190` in `manifestCommitter`, `src/watch.ts:265` in the
watcher's closure, `src/control.ts:465` on approve, `app/Sources/RouterCore/Auth/AuthRoutes.swift:173`
via `promote()`, `app/Sources/RouterCore/Watch/WatchIndexing.swift:209`,
`app/Sources/RouterCore/Service/ManifestIndexer.swift:186`. The three Swift sites were bare
filenames until gap-fix 1 and now carry their paths, for the reason given there: this repo has two
Swift modules and a filename alone sends a reader to the wrong one.

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
- **`parity-manifest-check.sh` does not resolve `file.swift:line` citations of source.** It reported
  *every cited test, script and row id resolves* while `surface.tsv` pointed at a comment line three
  above the call it named, and it still reports the same sentence now that the citation is corrected
  — so the sentence is true about the classes it checks and silent about this one. Whether source
  citations are worth resolving is somebody's to price; the class has now rotted once, and the
  correction in gap-fix 1 gives that row's Swift sites their paths and the rotted one its call text
  so a phrase search finds it when the line moves again.

## Gap-fix 1 — four record corrections, no code

**2026-08-22, on `ai/r19` at `eb3e42c`**, after a **Needs More Work** verdict from a fresh-context
verifier in `.worktrees/R19V` (`planning/verification/R19-verdict.md` there). The verifier merged
`main` into `eb3e42c` cleanly, re-measured every gate on the merged tree and agreed with all of
them — lint 0 over 552, `make test` 1728 in 216, `parity-cli` 18 verbs 0 disagreed with all four
`cli-watch` scenarios green, `parity-overlap` 2 of 2, the reconciler clean across A–L — and
confirmed that its merged tree's `src/`, `app/`, `scripts/`, `Makefile` and `planning/parity/` were
byte-identical to `eb3e42c`. This gap-fix breaks that for `planning/parity/surface.tsv` alone, by
one line of citation, and for nothing under `src/`, `app/`, `scripts/` or `Makefile`. **No code
changed here, and no gate logic.** What was wrong was what two sentences said and what two accounts
left out.

### The sentence that was measurably false

The `src/watch.ts` resolution paragraph used to close:

> `IndexFailureRecordTests` asserts the row survives a watch run, and `parity-cli.sh`'s fourth
> `cli-watch` scenario compares the manifest's *shape* between the two binaries, `reason=yes`
> included. **A merged tree that kept R19's delete on the node side would have failed both.** So the
> delete goes and the lock stays.

The verifier armed it and the bolded half is false. With the node delete restored, `parity-cli.sh`
reddens on the fourth scenario with `surface.tsv`'s recorded mutation string verbatim and the other
three stay green — and `IndexFailureRecordTests` **passes**, 2 tests in 1 suite. It is a Swift
test; nothing in it executes `src/watch.ts`. The verifier then ran the negative half, restoring the
Swift-side deletion's effect inside `WatchIndexing.swift`'s locked span, and that suite failed with
11 issues — so it is not merely insensitive, it is sensitive to the *other* side.

The rewritten paragraph is not a hedge and is stronger than what it replaces: it names which
instrument pins which side, and why the pair is needed rather than either alone — `parity-cli.sh`
is differential and would stay green under a simultaneous both-side regression, and
`IndexFailureRecordTests` is the absolute check that catches exactly that case on the Swift side.
Read on this tree rather than taken on report:
`app/Tests/RouterCoreTests/IndexFailureRecordTests.swift` opens `@testable import RouterCore` and
drives `WatchWorld.runner` and `ManifestIO`, and
`scripts/acceptance/parity-cli.sh` runs both binaries into separate `MCP_ROUTER_HOME`s and `diff`s
the results, which is what makes it blind to a regression both sides share.

The tree's own declarations already had this right, which is the sting: `surface.tsv`'s
`overlap-watch-index` row records the node arm as producing a **disagreement between the binaries**
— a differential effect, not a Swift-side one. One narrative sentence overstated what the rows
recorded accurately.

### The citation that had rotted three lines

`planning/parity/surface.tsv`'s `cli` / `cli-watch` / `watch` row cited `WatchIndexing.swift:206`
for the Swift watcher's manifest save. On this tree `:206` is a comment — *stage `lifeline` as well
and its row starts disappearing* — and the `try? ManifestIO.save(…)` it meant is at **`:209`**. All
three Swift sites in that pairing were bare filenames, and this repo has two Swift modules; the
verifier looked in `MCPRouterKit` first because nothing said `RouterCore`. Fixed by giving all
three their repo-relative paths and giving the one that rotted its call text as well, so the next
reader can find it by phrase when the line moves again. The same three were bare filenames in this
note's own six-site list and now carry their paths too — the numbers there were already right, the
module was not stated, and fixing one copy while leaving the other reads as arbitrary. The node
sites were correct everywhere. **Each of the six was re-read on this tree before the edit**,
including `ManifestIndexer.swift:186` and `AuthRoutes.swift:173`, which resolve — and which sit
under `Service/` and `Auth/`, not the `Indexing/` and `HTTP/` a reader might guess.

`parity-manifest-check.sh` reports every cited test, script and row id resolving while this citation
was three lines stale, so it does not resolve `file.swift:line` citations of source. Recorded below
as somebody's to price.

### Two accounts that were incomplete rather than wrong

The gate-race account now names **DEF-033** — `parity-oauth.sh` running twice per full gate with a
`fail` winning between the copies — which is why the gate reddens this row more readily than a
standalone run does, and why a clean single run inside a gate goes unnoticed. And it now carries the
verifier's three full gate runs, **red, green, green**, against the four-of-four recorded here.

**Arm 4 is recorded as confounded and is not re-measured.** The verifier's only red landed at load
average 400 with its greens at 175 and 23, and a gate run generates eight to ten minutes of load a
standalone run does not, so gate and machine move together in its dataset and in this one. Four
successive measurements of this cell have each contradicted the rate the one before it published.
No fifth rate is stated. The verifier reported the confounding instead of chasing it, which is the
right call, and this note follows it.

### What the claim sweep's 11 hits actually are

Corrected above. In short: the 11 blocking hits are classes **A1–A3**, one claim of R17's, in four
files this branch never writes; the wording this item's own brief pointed at is **B1/B2**, which
`BLOCKING = ("A1", "A2", "A3")` excludes from the exit code and which appears only inside the
reports that withdrew it. One count in the verdict is off and is corrected here: **7 of the 11**
sit in the two `planning/features-to-triage/R17-gapfix-*.md` copies that `RECORDS` does not
cover, not 4 — A1×1, A2×1, A3×1 in `R17-gapfix-2.md` and A1×2, A2×2 in `R17-gapfix-3.md`, counted
off the script's own per-class output on this tree.

### Gates after this gap-fix

Documents only, so `make test` and the parity lanes are unmoved from the table above and were not
re-run. The gates that read the two edited files were, and `make lint` was run because the brief
predicted it would not.

| gate | result |
|---|---|
| `make lint` | **0 violations, 0 serious in 552 files**, exit 0 |
| `scripts/acceptance/parity-manifest-check.sh` | exit 0 — **94 rows**, consistent with `control.ts`, `index.ts`, `router.ts` and the fixture directory; every cited test, script and row id resolves |
| `planning/claim-sweep.py` | **exit 1, 11 blocking-class hits** — the same 11, the same four files, the same per-class counts |
| `planning/ledger-reconcile.py` | **exit 1** — one finding, `E`, and it is `main`'s drift rather than this edit's |

**`make lint` ran rather than failing at `tools`.** The gap-fix brief expected the prerequisite to
bite because a fresh worktree has no `node_modules` and no `dist/index.js`; this one has both, so
`make tools` printed its version line and lint ran whole. Recorded because the brief offered
running the components directly as the fallback and it was not needed.

**The claim sweep's output is byte-identical before and after this edit but for one line number.**
Diffed the two runs: the only difference is the pre-existing non-blocking `A5` hit in this file
moving from `:62` to `:82` as the text above it grew. Zero new hits in any class, blocking or not,
from either edited file — which is the check worth running when a correction has to describe a
withdrawn claim without becoming a fresh instance of it.

**The reconciler's exit 1 is not this edit's and not this branch's.** It reads
`planning/features-to-triage/LEDGER.md` and `ORCHESTRATOR.md`, neither of which this gap-fix
touches and neither of which appears in `git diff --name-only adfa923..eb3e42c`. Its finding is
`E — a branch merged into main with no row in either file: G4-B (ai/g4b)`: `ai/g4b` landed on
`main` after `adfa923`, so this tip's copies of both files predate the row that would answer for
it. The verifier read exit 0 on the *merged* tree, which is the same fact from the other side. It
resolves on merge and needs nothing here.

### Where `main` was, for the next reader

`main` read **`87f6f2e`** when this gap-fix started and **`4a56120`** — *G4's twenty-third: an
assertion that keeps passing after its claim goes false* — about twenty minutes later, while the
gates above were running. That is the sixth and seventh tip this item has seen, after `54666f7`,
`43e4199`, `adfa923`, `bc39aa1` and the two the verifier logged. The blocking-pattern count over
`main`'s four claim-sweep files was re-run against `4a56120` and still reads 11, so that check
survived the move; the reconciler's `E` finding is what did not, and it is recorded above as
main's rather than this branch's. The moving target is a dispatch property rather than any runner's
problem — this is the third consecutive item to log it, and a gap-fix asked to gate the tree
nobody will merge cannot win the race by running faster either.
