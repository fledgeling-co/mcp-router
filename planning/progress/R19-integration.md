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
settle the merge without any judgement of mine — **each side is pinned by at least one instrument,
and `parity-cli.sh` reddens on either one-sided arm.** What each instrument *does* catch is the
useful thing to write down, and it is what this paragraph now says. What only it catches is not,
because the instrument set on this tree has never been enumerated. *(This paragraph has said
something false three times, once before each gap-fix, and every time it was an exclusivity claim
about instrument coverage rather than anything about the resolution itself. All three withdrawn
sentences and how each was disproved are in the closing sections of this note.)*

**`parity-cli.sh` pins the node side.** Its fourth `cli-watch` scenario compares the manifest's
*shape* between the two binaries, `reason=yes` included. Put `delete next.servers[name]` back into
`src/watch.ts` alone and the scenario reddens with the mutation string `surface.tsv` records
verbatim, while the other three stay green. `IndexFailureRecordTests` stays **green** through that
same arm, and it could not do otherwise: it is a Swift test — `@testable import RouterCore`,
driving `WatchWorld.runner` and `ManifestIO` — and no path through it executes `src/watch.ts` at
all.

**`IndexFailureRecordTests` pins the Swift side.** Restore the effect of R19's `removeEntry` call
inside `WatchIndexing.swift`'s locked span and the suite fails with 11 issues.

**`parity-cli.sh` reddens on that arm as well.** Arm by arm, with nothing said about what only each
instrument catches:

- **`parity-cli.sh` is differential** — it diffs node's streams, exit code and files against Swift's
  — so it reddens on a one-sided regression whichever side it is on, and the Swift arm produces the
  exact mirror of the node arm's diff on the same scenario row. On the **both-sides-at-once** arm it
  goes **green at 18 / 0, exit 0**, because two binaries that regress together still agree.
- **`IndexFailureRecordTests` is absolute on the Swift side and executes no node code**, so it
  reddens on the Swift arm and on the both-sides arm — 11 issues on each — and stays green through
  the node arm. Agreement between the binaries cannot fool it, because it never looks at the other
  one.
- **`parity-overlap.sh`, the lane R19 added itself, carries three assertions per row rather than
  one**: two absolute, one per side against `WANTED_ROWS="lifeline,slowfail"`
  (`scripts/acceptance/parity-overlap.sh:189`, compared at `:192-193` and `:194-195`), and one
  differential between the two sides (`:196`). The absolute pair is why it reddens on **all three**
  armed rows, the both-sides one included, where its output carries a `reference:` clause and a
  `swift:` clause and **no `disagree:` clause** — the two binaries agree there and it fails them
  both anyway. Its own comment at `:187-188` says so: *asserting it here means a watcher that went
  back to deleting it reddens this row too.*
- **`make test` catches none of these arms** and structurally cannot: it is `swift test` run in
  `app/` and executes no node code, so the node arm leaves it at **1728 tests in 216 suites,
  exit 0**.

That is the argument for carrying `parity-cli.sh` and `IndexFailureRecordTests` together: between
them every armed row below is red on at least one, the both-sides row included. It is not an argument
that either is the only instrument holding any cell, and this note makes no such claim. Three times
it did, and all three were false — each disproved by an instrument the record had not named, which is
exactly why the claim is unavailable here. Nobody has enumerated the instruments on this tree, and
each of the three passes turned up one more.

**The matrix, every cell measured** — three instruments against five arms. Arms restored from R19's
own code at `a27fd52`, each removed afterwards and each removal confirmed by blob hash rather than by
eye:

| arm | `parity-cli.sh` | `IndexFailureRecordTests` | `parity-overlap.sh` |
|---|---|---|---|
| none | green — 18 verbs agreed, 0 did not, exit 0 | green — 2 tests in 1 suite | green — 2 agreed, 0 did not, exit 0 |
| **A** node delete, `src/watch.ts:265` | **RED** — 17 agreed, 1 did not, exit 1 | green — 2 tests in 1 suite | **RED** — 1 agreed, 1 did not, exit 1 |
| **B** Swift `removeEntry` effect, `app/Sources/RouterCore/Watch/WatchIndexing.swift:209` | **RED** — 17 agreed, 1 did not, exit 1 | **RED** — 11 issues | **RED** — 1 agreed, 1 did not, exit 1 |
| **A+B** both arms at once | **green** — 18 verbs agreed, 0 did not, exit 0 | **RED** — 11 issues | **RED** — 1 agreed, 1 did not, exit 1 |
| both arms removed | green — 18 verbs agreed, 0 did not, exit 0 | green — 2 tests in 1 suite | green — 2 agreed, 0 did not, exit 0 |

**Which cells are this branch's own, and which are carried.** The `parity-cli.sh` and
`IndexFailureRecordTests` columns for the **none**, **A**, **B** and **removed** rows were armed on
this branch across gap-fixes 1 and 2. The **A+B** row and the whole `parity-overlap.sh` column were
armed by the gap-fix 2 verifier and are carried here rather than re-run — sound only because that
verifier's tree carries this branch's code byte for byte. Compared as git tree objects between its
merged `8836525` and this branch's merged HEAD: `src` `7520bdc1…`, `app` `f12da552…`, `scripts`
`9f1bc1a9…` and `Makefile` `99efe9ff…` are equal on both. The reader was given a presence control
against `main`, which lacks R19's code, and reported all three directories differing there. The
verdict is `a40351d:planning/verification/R19-verdict.md`, cited by tree and path because
`planning/verification/` does not exist on this branch. The **none** row was re-measured here after
merging `main` and agrees with both columns.

The three measurements that carry the argument, verbatim from that verdict:

```
# arm A — parity-overlap.sh: node's side is short, and the two sides disagree
  FAIL overlap-watch-index  the overlapping writer's row did not survive —
       reference:[rows=lifeline, wanted lifeline,slowfail] disagree:[ts=lifeline swift=lifeline,slowfail]

# arm A+B — parity-overlap.sh: both sides short, and no `disagree:` clause at all
  FAIL overlap-watch-index  the overlapping writer's row did not survive —
       reference:[rows=lifeline, wanted lifeline,slowfail] swift:[rows=lifeline, wanted lifeline,slowfail]

# arm A+B — parity-cli.sh: the differential lane, green, because the two binaries agree
  ok   cli-watch  two upstreams failing at different points each leave a row (exit 0)
cli: 18 verbs agreed, 0 did not          ### exit 0
```

Both reds land on the same `cli-watch` scenario and name the same two servers, in opposite
directions. The node arm reads `manifest:[0a1,2 > deadcommand tools=0 reason=yes > refuseslist
tools=0 reason=yes]` — `diff` adding the Swift side's two rows, because node lost them. The Swift
arm reads `manifest:[1,2d0 < deadcommand tools=0 reason=yes < refuseslist tools=0 reason=yes]` —
`diff` deleting node's two rows, because Swift lost them. **The mirror image is what proves it is
the arm rather than the machine**, and it is also why that cell could never have been green: a
differential harness cannot do anything else with a one-sided regression.

So the delete goes on **both** sides and the lock stays, and each side is held by at least one
instrument that can see it. The pair is worth carrying for the both-at-once case rather than for a
division of labour, and that case is now measured rather than reasoned: with both sides regressed
together `parity-cli.sh` goes **green at 18 / 0**, exactly as this note predicted before anyone armed
it, and `IndexFailureRecordTests` reddens at 11 issues there because it never looks at node. A third
instrument reddens on that arm as well — `parity-overlap.sh`, above — so the pair is sufficient for
the both-at-once case and not necessary for it.

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
- **`parity-manifest-check.sh` went red once in 12 runs on an unchanged tree**, on 2026-08-23,
  naming a fixture that was tracked and present. Green on the other eleven, and the one mechanism
  worth guessing did not reproduce in 200 attempts. Full account in the gap-fix 3 section below. It
  is not this branch's and nothing here turns on it, but the message it prints — *stale manifest* —
  is one a reader could act on, so somebody who owns the acceptance harness should price a gate that
  can say that when it is not true.
- **The `LEDGER.md` bullet this section carried is closed, by `main`, twice over.** It said
  `planning/features-to-triage/LEDGER.md`'s R19 row read *thirteen lines* for a distance measured
  here as four. That was true when gap-fix 2 committed it and false 101 seconds later: `main`'s
  `1f5ad55` — *Correct thirteen to four, and record R19 gap-fix 2* — landed the correction and named
  the error as the orchestrator's. `main`'s `afdb500` has since replaced that row's text outright
  with *Needs More Work — verified `a40351d`, gap-fix 3 owed*, so the row now carries neither figure
  and none of the gate numbers the bullet vouched for. Both commits are ancestors of this merge.
  **Measured on this branch's merged tree, with the normaliser stated:** case-insensitive
  occurrences of the literal `thirteen` in `LEDGER.md` — occurrences rather than matching lines, and
  no wrap-joining because that file is one row per line — **2**, and neither is the withdrawn
  figure. One is the `G4-B` row's *thirteenth instance*; the other is a prose line, *Thirteen rows
  were added on 2026-08-21*, outside any table row. A case-sensitive **line** count returns **1** and
  misses the capitalised one, which is why the normaliser is written down rather than assumed;
  planting one more takes the count to 3. Cited by item id rather than by line, because a line into
  `LEDGER.md` goes stale mid-session — which is the concurrency hazard the bullet was filed under,
  demonstrating itself on the bullet's own subject inside one day.

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

Gap-fix 1's own account of what it wrote, kept as the record of what it claimed: *not a hedge and
stronger than what it replaces — it names which instrument pins which side, and why the pair is
needed rather than either alone.* `parity-cli.sh` is differential and would stay green under a
simultaneous both-side regression, and `IndexFailureRecordTests` is the absolute check that catches
exactly that case on the Swift side. Read on this tree rather than taken on report:
`app/Tests/RouterCoreTests/IndexFailureRecordTests.swift` opens `@testable import RouterCore` and
drives `WatchWorld.runner` and `ManifestIO`, and
`scripts/acceptance/parity-cli.sh` runs both binaries into separate `MCP_ROUTER_HOME`s and `diff`s
the results, which is what makes it blind to a regression both sides share.

**The half of that which said *which* instrument pins which side was itself false, and gap-fix 2
withdrew it.** Read on this tree meant read: nothing was armed, and the exclusivity was reasoned
from the same differential property that refutes it. The section below carries the arm.

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

## Gap-fix 2 — the replacement claim was false too, and a static read is what let it through

**2026-08-22, on `ai/r19` at `8294df4`**, after a second **Needs More Work** verdict from a
fresh-context verifier in `.worktrees/R19V2` (`planning/verification/R19-verdict.md` there, written
against `f3a14b6`). Documents only again, and this time one file: this one.

**The verdict's three findings, and which were in scope.** **F1** is the blocking one and is the
whole of this pass: the false sentence at `8294df4:31-32`, replaced above with the matrix behind it.
**F2** — the worktree handed over dirty, a previous verifier's arming mutation live in it — is the
harness rather than this item: inherited rather than introduced, cleared by the verifier that found
it, and recorded below rather than chased. **F3** — a brief living untracked inside the tree it is
about — is recorded and left as it was, untracked and outside this commit. Neither non-blocking
finding names anything on this branch to change, which is why both are recorded rather than actioned,
and F2's remedy is a line in a brief rather than a line in this repository.

### The withdrawn sentence, with anchor, tree and line

- **Anchor:** `` `parity-cli.sh` is not what catches that one. `` — and, for the general form of the
  same mistake, `one instrument per side, not both instruments for both sides.`
- **Tree:** `8294df4`, where this file is blob `af1dcb98fcfeff3bf2ae95b348da74a69bb37f3f`. Re-read
  here rather than taken from the verdict; the blob is identical on the verifier's merged tree and on
  mine before this edit, so the finding survived both merges.
- **Line:** `:31-32` for the first anchor and `:17-18` for the second, both on `8294df4`. The
  corrected text is at `:33-120` above, with the matrix at `:70-76` — those four are lines into
  **this** file as gap-fix 3 commits it, which a reader can pin with
  `git log -1 --format=%H -- planning/progress/R19-integration.md` rather than assuming they still
  hold after the next edit.

The verifier ran the cell nobody had run: R19's Swift `removeEntry` effect restored inside
`WatchIndexing.swift`'s locked span, measured against **`parity-cli.sh`** rather than only against
`IndexFailureRecordTests`. It is red — 17 verbs agreed, 1 did not, exit 1 — on the same `cli-watch`
scenario the node arm reddens, carrying the mirror image of the node arm's diff. So the Swift side is
pinned by two instruments, `parity-cli.sh` reddens on a one-sided regression from either side, and
the sentence gap-fix 1 wrote to replace a false one was false in the same way about the other half.

**The document already contained its own refutation.** The falsifying clause sat at `8294df4:36-37`
— *`parity-cli.sh` is differential … so it reddens on a one-sided regression* — and the Swift arm is
a one-sided regression. One clause predicted the measurement, the sentence above it denied the
measurement, and the half that was right was the half already written down.

**That distance is four lines, and I measured it rather than transcribing it.** The verdict states it
twice and the two disagree: its opening paragraph says *four lines below*, its F1 says *thirteen*,
and this gap-fix's brief carried thirteen forward. On `8294df4` the false sentence ends at `:32` and
the falsifying clause opens at `:36` — four lines, or five counted from the false sentence's first
line at `:31`. Neither reading reaches thirteen. Recorded rather than quietly corrected, because a
figure nobody re-derived is this repository's `G4` class, and a gap-fix dispatched for an unarmed
claim is the wrong document to paste one into.

**A static read is what let a false claim through twice.**
`planning/features-to-triage/LEDGER.md`'s R19 row records gap-fix 1's replacement as verified
*statically* — read on the tree rather than taken on report, which is better than report and is not
arming. The first false sentence was disproved by an arm. The second was *reasoned* from the very
differential property that refutes it, with no arm run against it, so the reasoning ran the wrong way
and nothing was in place to stop it. **The matrix is what settled it**, and it settled it in one
session: the cell that had never been measured is the cell that carried the answer, and completing
the 2×2 cost less than either static read that preceded it.

**One thing scoped down rather than pasted, on a reason that was itself wrong.** The verdict's
ready-to-paste text says `parity-cli.sh` pins the node side *and it is the only instrument that
does*. This pass declined it and wrote *of the two instruments, it is the one that reaches the node
half*, on the ground that no arm had been run against `make test`'s 1728. **Declining was right and
the ground was wrong.** `make test` is `swift test` run in `app/`, so it executes no node code and
was never a candidate — it could have been ruled out by reading the `Makefile`, and when the gap-fix 2
verifier finally armed it, the node arm left it at 1728 in 216, exit 0. The instrument that actually
refutes *the only instrument that does* is **`parity-overlap.sh`**, a lane this item added itself and
ran green two rows below in its own gate table. So the paste would have written a third false
exclusivity, and the narrowed form escaped it on a mis-stated reason rather than on the real one.
Gap-fix 3 dropped the narrowed form too, because *of the two instruments* is still an exclusivity
over a set nobody has enumerated: the general claim at `:17-18` now says **at least** one instrument
per side, and `:36-64` states what each instrument catches and stops there.

**The error under-claims, which is why this is a correction rather than an alarm.** The record said
the Swift side had one guard; it has two. Nothing on this tree is less guarded than the note claimed
and no merge decision turned on the sentence. What it would have cost is a reader acting on it —
weakening `parity-cli.sh` to a node-only guard, or adding a third Swift instrument to close a
coverage gap that is not there — in the document whose whole subject is which instrument reaches
which half.

### What the verifier confirmed, and what it declined

**The records-only promise held at tree-hash exactness.** `src/`, `app/`, `scripts/` and `Makefile`
were compared as git tree objects between `eb3e42c` and `8294df4` — byte-identity for a whole
directory in one value — and all four matched. **Both instruments carried a presence control**, the
working tree's live arming mutation, and both fired: the diff instrument reported `Makefile` and
`WatchIndexing.swift` modified, the tree-hash instrument reported `app` differing. An absence check
with no control is an assertion, and this one was not. Re-run here after merging `main`, the same
three directories are still byte-identical to `eb3e42c` and `Makefile` is the only code-path delta.

**`scripts/acceptance/parity-gate.sh` was not run, and that trade is inherited deliberately.** It is
the instrument that would produce a fifth rate for the `control POST /servers/:name/auth` cell — the
gate runs `parity-oauth.sh` twice with a `fail` winning between the copies, DEF-033 — and that cell
has now had four successive measurements each contradict the rate published before it. The verifier
declined it and stated the cost; this gap-fix states the same cost rather than quietly buying the
figure: **no whole-parity coverage number of its own.** The row census comes from
`parity-manifest-check.sh` instead, and the two lanes this note's claims actually turn on,
`parity-cli.sh` and `parity-overlap.sh`, are run directly and green below. **No rate for arm 4 is
stated here either.** Gate and machine are confounded in both datasets; the confounding is still the
finding.

**All three of gap-fix 1's corrections to the first verdict were re-measured by the verifier and all
three hold** —
the sweep count of **7** with the normaliser named and all eleven hits listed by site, the
reconciler's check-E exit 1 as `main`'s branch staleness clearing on merge, and `make lint` running
whole rather than failing at `tools`. The verifier planted five instances in a
`git ls-files`-visible file to control the sweep, one of them split across a hard wrap to exercise
the normaliser's whole reason for existing, and got +5 exactly with the wrapped instance counted.
Nothing in that half of gap-fix 1 is disturbed, and neither is any gate figure.

### The handover was clean this time, and it is recorded rather than assumed

The previous verifier inherited this worktree **dirty** — an earlier session's Swift arming mutation
live and uncommitted in `app/Sources/RouterCore/Watch/WatchIndexing.swift`, which would have reddened
any gate run there for a reason nothing in the tree recorded. It pasted the patch into its verdict and
cleared it before gating, which is the right handling and the only reason the hazard is knowable.

Checked at the start of this session rather than at the end of it:

```
$ git status --porcelain          # before the merge, before any edit
?? GAPFIX-2-BRIEF.md
?? GAPFIX-BRIEF.md
?? VERIFY-BRIEF.md
```

Nothing tracked was modified and nothing was absorbed into this item's diff. The three untracked
files are briefs — the shape `planning/features-to-triage/G6-evidence-that-lives-in-tmp-is-not-evidence.md`
filed as its other half, a brief living inside the tree it is about. Left untracked and out of this
commit, as the previous verifier left the first of them. **This session introduced no leftover and
inherited none**; what it inherited was the three briefs. But two verifier worktrees have now carried
arming mutations between sessions, and a `git status` assertion at the top of a brief costs nothing —
the second consecutive note to say so, which is the argument for it being in the brief template
rather than in each note that noticed.

### The dissent that said ship it, recorded because it was close

The verifier's severity call went out of session. Two lanes were down — `codex`/`gpt-5.6-sol` on a
usage limit to Aug 27, `grok`/`grok-4.6` on an exhausted balance, both with no output file — so the
only out-of-family lane that answered was `agy`/`gemini-3.7-flash-high`, and **it said Done** with a
non-blocking erratum, on the ground that an under-claim leaves the tree strictly safer than stated
and no downstream decision turns on the sentence. The in-family `claude-fable-5` lane independently
said Needs More Work. The verifier reported that split the unflattering way round — the lane that
agreed with it was the in-family one — and took the red anyway, because an erratum in a verification
file does not change *this* file, and this file is what merges to `main` and becomes the standing
answer to *will `parity-cli.sh` catch a Swift-side regression here?* Nothing in the measurement was
disputed by either read; only the severity was.

### Gates after this gap-fix

Measured on the merge of this branch with `main` at `01b6ef9` — *M20 and R19 both Needs More Work;
two gap-fixes dispatched*, which is this item's own verdict as a subject line. The merge resolved
nothing by hand: `git diff-tree --cc --name-only -r` prints no files for it, against the control of
`327f38f`, this item's own merge, which prints the four it really did resolve. The only code-path
delta the merge carries is **`Makefile`**, twelve lines from main's `50f3e8f`, adding
`reader-accounting.py` and `null-run-gate.py` to the `lint` recipe — so `lint`'s gate count moved and
`src/`, `app/` and `scripts/` did not.

| gate | result |
|---|---|
| `make lint` | **exit 0** — 0 violations, 0 serious in **552 files**. `tools:` printed its version line, so the prerequisite passed rather than being skipped. Main's two new gates ran on this branch for the first time and both are green: `reader-accounting.py` at **20 raw-input readers over 28 discarding iterations, 51 drop sites**, 3 recording their drops, 16 declaring them and **1 recorded as a known gap rather than fixed**; `null-run-gate.py` at **28 assertions armed, 28 changed verdict** under a poisoned or null input, **0 held green** |
| `make test` | **exit 0** — 1728 tests in 216 suites passed, 10.4s. Unchanged from the pre-merge figure, which is what a merge carrying no code but `Makefile` should do |
| `scripts/acceptance/parity-cli.sh` | **exit 0** — 18 verbs agreed, 0 did not; all four `cli-watch` scenarios green, the fourth included. This is the matrix's **none** row re-measured here rather than inherited from the verdict |
| `scripts/acceptance/parity-overlap.sh` | **exit 0** — 2 agreed, 0 did not; `overlap-watch-index` at `rows=lifeline,slowfail`, neither binary rewrote `servers.json` |
| `scripts/acceptance/parity-manifest-check.sh` | **exit 0** — 94 rows, consistent with `control.ts`, `index.ts`, `router.ts` and the fixture directory; every cited test, script and row id resolves |
| `planning/ledger-reconcile.py` | **exit 0** — *reconciled, no findings across A–L*; 103 rows in each file, 32 merged `ai/*`. The `E — G4-B (ai/g4b)` finding this branch reads pre-merge is gone, exactly as the brief predicted: branch staleness, cleared by the merge |
| `planning/claim-sweep.py` | **exit 1** — 11 blocking hits, A1×5 + A2×5 + A3×1, in the same four files, none of which this branch writes |
| `scripts/acceptance/parity-gate.sh` | **not run — deliberately.** Reasons and cost above |

Every gate ran twice. The first pass piped its output and lost the exit codes — `zsh` does not
populate `PIPESTATUS` — so each was re-run without a pipe. The two passes agree on every figure, and
the exit codes above come from the pass that could report them, not from reading a summary line and
inferring what the script must have returned.

**The claim sweep's output is byte-identical before and after this edit but for one line number** —
this file's own pre-existing non-blocking `A5` hit moving from `:82` to `:110` as the text above it
grew. Zero new hits in any class, blocking or not, from a rewrite that had to quote two withdrawn
sentences: `diff` over the two runs prints that single line and nothing else, and every
re-run after the later edits is byte-identical to the first post-edit one. Same check gap-fix 1 ran, same reason — a correction
that has to quote a withdrawn sentence must not become a fresh instance of one.

### Where `main` was, for the next reader

`main` read **`01b6ef9`** when this gap-fix started, three commits on from the `e8935f2` the second
verifier merged. The tips this item's records **name** are `54666f7`, `43e4199`, `adfa923`,
`bc39aa1`, `87f6f2e`, `4a56120`, `e8935f2` and this one, each confirmed here as an ancestor of
`01b6ef9`; the first verifier logged two more without naming them, so eight is a floor rather than a
census. **R16, R18 and R21 wait on this merging**, which
is why a second false record here would have cost three items rather than one, and why two false
sentences were worth a pass each rather than an erratum.

## Gap-fix 3 — the register changed, because the defect was the paragraph and not the sentence

**2026-08-23, on `ai/r19` at `2793574`**, after a third **Needs More Work** verdict from a
fresh-context verifier in `.worktrees/R19W` — `a40351d:planning/verification/R19-verdict.md`, cited
by tree and path because `planning/verification/` does not exist on this branch. Documents only
again, and one file again: this one.

### Three passes, three claims about the instrument set, all three false

| pass | the claim it wrote | what disproved it | shape |
|---|---|---|---|
| before gap-fix 1 | *a merged tree that kept R19's delete on the node side would have failed **both*** | the node arm leaves `IndexFailureRecordTests` **green** — 2 tests in 1 suite | over-claimed the pair |
| before gap-fix 2 | `parity-cli.sh` *is **not what catches** that one* | `parity-cli.sh` reddens on the Swift arm too — 17 / 1, exit 1 | false negative about one |
| before gap-fix 3 | what `IndexFailureRecordTests` ***uniquely*** holds is the both-sides-at-once case | `parity-overlap.sh` reddens on that arm as well, on **both** sides, with no `disagree:` clause | false exclusivity |

The brief calls all three exclusivities; two of them are, and the first is an over-claim in the other
direction. **What they share is the shape rather than the direction**: each states something about
the *whole* set of instruments that catch an arm, from a sample of two. And each was killed by an
instrument the paragraph had never named — a *different* one every pass. Two of the three were
refutable without arming anything: the second by this note's own differential clause four lines
below it, the third by `parity-overlap.sh`'s own comment at `:187-188`.

**So the sentence was not repaired.** A third repair in the same slot is a fourth guess at the size
of a set nobody has enumerated, and the base rate on this paragraph for that guess is 0 for 3. The
register changed instead: it now states what each instrument **does** catch and stops there.
`parity-cli.sh` differential and green at 18 / 0 on the both-sides arm; `IndexFailureRecordTests`
absolute on Swift, blind to node, red at 11 issues on two arms; `parity-overlap.sh` red on all three
armed rows; `make test` red on none of them and structurally unable to be. **Four instruments named
where the graded text named two**, and no claim anywhere that any of them is the only one.

### The verdict's ready-to-paste text was declined again, and this is the second pass running to do it

Its option (b) reads *the both-sides-at-once case is `IndexFailureRecordTests`'* and closes *it is
the **strongest** guard here rather than the narrowest*. A possessive and a superlative are the same
move as *uniquely* — both rank over the set, and the set is what this branch does not have. Every
**number** in (b) is used; its framing is not. The last pass declined a paste for a reason that was
itself wrong (above); this one declines for the reason the verdict itself supplies, which is that
three passes have each turned up an instrument the last one missed.

**One correction to the verdict, in its favour.** It describes `parity-overlap.sh` as *absolute, not
differential*, citing `:189-195`. Read on this tree, the row carries **three** assertions: two
absolute at `:192-193` and `:194-195`, and one differential at `:196`. Both readings predict the
both-sides arm reddening; only the three-assertion reading also explains the `disagree:` clause in
the verdict's own **arm A** output, which an absolute-only lane could not emit. The paragraph above
states the three, so the same evidence is now explained by the description that produced it.

### The exclusivity sweep, its normaliser, its sites and its control

Run over the resolution section before and after the edit. **Normaliser:** take the section's lines,
join hard wraps with a single space, collapse runs of whitespace, then match
`\b(uniquely|unique|only instrument|the only|solely|exclusively|no other|nothing else|alone)\b`,
case-insensitive. Sites are listed rather than merely counted, because a count whose sites nobody can
re-derive is not a measurement anyone else can check.

| run | range | hits | sites |
|---|---|---|---|
| before | `:12-68` | **2** | `alone` — *back into `src/watch.ts` alone*, an arm description; `uniquely` at `:39`, the blocking finding |
| after | `:12-120` | **2** | `alone` — the same arm description, unmoved; `the only` — *it is **not** an argument that either is the only instrument holding any cell*, a denial |
| control | `:12-120` + one planted claim | **3** | the two above, plus the plant |

The before-run reproduces the verifier's count of 2 with the same two sites, so the instrument agrees
with the one that found the defect. `uniquely` is gone. The surviving `the only` is a sentence
denying the property, kept in that wording deliberately: rephrasing to dodge a sweep the document
itself runs would leave the sweep green and the reader worse off.

**The range is the resolution section, and the whole file is a different number.** Swept end to end
this note returns **37** hits, because the three gap-fix sections quote every withdrawn sentence on
purpose — the register rule governs what the document *claims*, and a quotation of a claim under
withdrawal is not one. Stated rather than left for a later reader to discover, because a count taken
over the wrong population is how the figure this pass corrects in `LEDGER.md` went wrong in the
first place.

### Which measurements are this branch's, and which are carried

The **A+B** row and the whole `parity-overlap.sh` column come from the gap-fix 2 verdict rather than
from a campaign here, on the brief's instruction. What makes that transferable is stated at the
matrix above and re-derived here: `src`, `app`, `scripts` **and** `Makefile` are equal as git tree
objects between the verifier's merged `8836525`, the graded `2793574` and this branch's merged
`2c80e33` — `7520bdc1…`, `f12da552…`, `9f1bc1a9…`, `99efe9ff…`. **There is no code-path delta at all
this time**, not even the `Makefile` one the last two passes carried, because `2793574` already had
main's `50f3e8f`. Presence control on that reader: the same command form against `main`, which lacks
R19's code, reports all three directories differing. `main` moved **22 commits** past the merge base
and **11 past the verifier's**, and the nine files this merge brings are `ORCHESTRATOR.md`,
`LEDGER.md`, four new triage briefs and two reckoning artifacts — no `src/`, `app/`, `scripts/` or
`Makefile` among them.

Per the brief: **`parity-gate.sh` was not run**, and no rate is stated for arm 4. That cell has
contradicted its own published rate four times; the cost of the trade is the same one gap-fix 2
stated — no whole-parity coverage number of this pass's own, with the row census coming from
`parity-manifest-check.sh` instead.

### The handover, and the briefs still living in the tree

```
$ git status --porcelain          # before the merge, before any edit
?? GAPFIX-2-BRIEF.md
?? GAPFIX-BRIEF.md
?? GAPFIX-NEXT.md
?? VERIFY-BRIEF.md
```

Four now, where gap-fix 2 inherited three. Nothing tracked was modified, nothing was absorbed into
this commit, and all four are left untracked and outside it. **Checked rather than assumed:**
`git log --all -- <brief>` returns **0** commits for `GAPFIX-BRIEF.md`, `GAPFIX-2-BRIEF.md` and
`GAPFIX-NEXT.md`, so no pass on this item has ever committed one.

**The hazard is not hypothetical, and the check that proves it is the same one.** The same command
against `VERIFY-BRIEF.md` returns **2** commits — `c49d674` *SCRATCH: merge main 28d0528 into G5
gap-fix 3 tip …* and `3e63811` *Verify G5 gap-fix 3: Needs More Work …*. Neither is an ancestor of
`main` and `main:VERIFY-BRIEF.md` does not exist, so nothing has reached the trunk; but a verify
brief has twice been committed into the tree it was written about, on another item. That is
`planning/features-to-triage/G6-evidence-that-lives-in-tmp-is-not-evidence.md`'s shape with a
landing rather than a near miss, and it is the strongest argument yet for the standing ask — one
line in the brief template — which gap-fix 2 also made.

### Gates after this gap-fix

Measured on `2c80e33`, the merge of this branch with `main` at `9d4da76`. Every gate ran without a
pipe, so each exit code is the process's own — `zsh` does not populate `PIPESTATUS`, and a summary
line read out of a pipe is an inference rather than a status.

**Every gate ran twice, once before the edit and once after**, and the two passes agree on every
figure and every exit code. The before-pass is what establishes that the merge was green before this
note was touched; the after-pass is what the table reports.

| gate | result |
|---|---|
| `make lint` | **exit 0** — 0 violations, 0 serious in **552 files**; `tools:` printed `Version: 2.45.4 · swiftlint 0.65.0 · swiftformat 0.62.1`, so the prerequisite passed rather than being skipped. `reader-accounting.py`: **20 raw-input readers over 28 discarding iterations, 51 drop sites**; 3 accounting, 16 declaring, **1 known gap**, **0 unaccounted**. `null-run-gate.py`: **28 assertions armed, 28 changed verdict**, **0 held green**, 0 blocked, 4 populations named as not armed |
| `make test` | **exit 0** — **1728 tests in 216 suites** passed; 11.0s on the after-pass, 13.5s on the before-pass, the difference being machine load rather than anything in the tree |
| `scripts/acceptance/parity-cli.sh` | **exit 0** — **18 verbs agreed, 0 did not**; all four `cli-watch` scenarios green, the fourth included. The matrix's **none** row, re-measured here |
| `scripts/acceptance/parity-overlap.sh` | **exit 0** — **2 agreed, 0 did not**; `overlap-watch-index` at `rows=lifeline,slowfail`, neither binary rewrote `servers.json` |
| `scripts/acceptance/parity-manifest-check.sh` | **exit 0** — **94 rows**, consistent with `control.ts`, `index.ts`, `router.ts` and the fixture directory; every cited test, script and row id resolves. **It went red once tonight in 12 runs**, spuriously; recorded below rather than dropped |
| `planning/ledger-reconcile.py` | **exit 0** — *reconciled, no findings across A–L*. **107 rows in each file**, 32 merged `ai/*`. One non-fatal warning, inherited and not this branch's: `LEDGER.md odd number of backtick quotes (1683) — check D may be stripping more than one quoted span` |
| `planning/claim-sweep.py` | **exit 1** — **11 blocking hits, A1×5 + A2×5 + A3×1**, across `ORCHESTRATOR.md`, `G4-assertions-that-do-not-read-their-own-quantity.md`, `R17-gapfix-2.md` and `R17-gapfix-3.md`, none of which this branch writes |
| `scripts/acceptance/parity-gate.sh` | **not run — deliberately.** Cost stated above |

**One gate went red once and could not be made to do it again, so it is recorded rather than
dropped.** On the after-edit pass `parity-manifest-check.sh` exited **1** with a single problem —
*the manifest carries fixture row "reindex-held", which is not on disk* — at a one-minute load of
**415**. `app/Sources/MCPRouterKit/Control/Fixtures/reindex-held.json` is tracked, was present
throughout, and `git status --porcelain` showed only this pass's two edited files and the four
untracked briefs at every point. It has been green on every other run: the before-edit pass, an
immediate re-run, and **10** consecutive runs after that — **1 red in 12** tonight, all twelve on
the same tree.

**The mechanism is unidentified, and the obvious guess did not reproduce.** The check builds its
on-disk list with `find "$FIXTURE_DIR" -name '*.json' -exec basename {} .json \;`, which forks once
per fixture; a fork that failed under load would drop a name silently and produce exactly this
message. Run 200 times at a load of about 402, that command returned all **24** names **200 times
out of 200**. So the fork-starvation story is a hypothesis this pass tried to arm and could not, and
it is stated as an unresolved observation rather than as a cause. What it is *not* is this branch's:
the change here is markdown and this gate reads no markdown. It is written down at all because the
red names a **stale manifest**, which is a conclusion someone could act on — and on this evidence
the manifest was not stale.

**The claim sweep's output is byte-identical before and after this edit but for one line number** —
this file's own pre-existing non-blocking `A5` hit moving from `:110` to `:162` as the text above it
grew. `diff` over the two runs prints that single line and nothing else, so a rewrite that had to
quote three withdrawn sentences added **zero** hits in any class, blocking or not. The scanned
population is unchanged at 1185 tracked files, because this pass adds no file. Same check as
gap-fixes 1 and 2, same reason: a correction that quotes a withdrawn sentence must not become a
fresh instance of one.

**The reconciler's row count moved and it is `main`'s, not this branch's.** Gap-fix 2 recorded 103
rows in each file; the gap-fix 2 verifier measured 106 on its merged tree; this merge reads **107**.
The merged-branch count is 32 at all three. No claim of this item's turns on the figure, and gap-fix
2's 103 is left as written because it was correct for the tree it names — the number tracks `main`'s
row growth, and reading a difference here as drift on this branch would be the error.

**Load averages, recorded so nobody has to guess whether a green was bought quiet.** One-minute load
at lane start: `make lint` 430 · `make test` 451 · `parity-cli` **492** · `parity-overlap` **557** ·
`parity-manifest` 544 · reconciler and sweep 542. This machine was carrying a fleet. The four
`cli-watch` verdicts were identical here at **492** and in the gap-fix 2 verdict at **13** and at
**54** — 13 to 492 is a factor of 37, and all three points agree. That does not clear the
`parity-gate.sh` arm-4 confounding, which is a different lane on a different row; it does mean the
`cli-watch` scenarios this note's claims rest on have not shown load sensitivity across any range
yet measured.

### Where `main` was, for the next reader

`main` read **`9d4da76`** — *M16 Done, and the status field that never advanced* — when this gap-fix
started, and the merge is `2c80e33`. That is **22 commits** past the merge base `01b6ef9` and **11**
past the `f4fe03a` the gap-fix 2 verifier merged, none of them touching `src/`, `app/`, `scripts/` or
`Makefile`: `git diff --stat 01b6ef9 main -- src app scripts Makefile` prints nothing. Two of those
commits are this item's own paperwork — `1f5ad55` corrected the thirteen and `afdb500` set the R19
row to *Needs More Work … gap-fix 3 owed* — and both are ancestors of the merge.

**`main` will have moved again by the time this is read**, which is the standing condition on this
branch rather than a complaint: three verifiers and three gap-fixes have each merged a different
`main`, and every figure above is stamped with the merge it was measured on for exactly that reason.

**R16, R18 and R21 wait on this merging.** Three passes have now been spent on one paragraph of a
zero-code-delta note. What each bought is a measurement the tree did not have: the Swift arm against
`parity-cli.sh`, the both-sides arm against all three lanes, and `parity-overlap.sh`'s three
assertions read out of the script rather than inferred from its name. What none of them bought is an
enumeration of the instruments on this tree — so the paragraph no longer spends a claim on one.
