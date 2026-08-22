# R17 gap-fix 4 — progress

**Branch:** `ai/r17`, base `0951650` · **Delivered:** 2026-08-22 · **Scope held:** no code

Three files: the `D-r17-d` row in `ORCHESTRATOR.md`, `planning/progress/R17-gapfix-3.md`, and a new
`planning/claim-sweep.py`. `git diff --name-only` names nothing under `src/`, `app/` or
`scripts/acceptance/`. `planning/evidence/R17-acceptance.md` is untouched — criterion 3 passed in
substance and re-wrapping its 144-character line is outside this pass's scope, though the sweep
script below is what would eventually make that line unnecessary.

## BL-1 — the row states no rate, because every rate so far has been refuted by the next one

`D-r17-d` had been rewritten three times, and each rewrite replaced a reproduction rate with
another one that the following measurement contradicted:

| Pass | The rate it put in the row | What the next measurement got |
|---|---|---|
| gap-fix 2 | about a quarter to a third of ~60 runs, flat | 0 of 40 serially, and 53 of 104 at four concurrent — refuting *flat* in both directions |
| third verification | 53 of 104 and 24 of 72 at four concurrent | 29 of 80 at four concurrent |
| gap-fix 3 | 29 of 80 at four concurrent | **0 of 80** at four concurrent, in a 408-invocation quiet-tree run |
| fourth verification | none — it asked for the rate to be dropped | this pass states none |

The row now carries all four sets **as history and labelled as history**, and states no condition at
all. It says why in its own voice — *a register row stating a rate is how each of the last three
passes inherited a number the next disproved* — and it names the variable the rates were tracking:
**total machine pressure, not this gate's own concurrency.** Every high rate was recorded while
other sessions were loading the box; the fourth verification's quiet tree is where four concurrent
copies produced nothing across 80 runs, and 8×, 16× and 32× produced one red in 288.

**One number was read rather than copied.** The fourth verification's headline is *368 gate
invocations*, and its own table sums to 408: 40 serial plus 80, 96, 96 and 96 concurrent. 368 is the
concurrent subtotal — 80+96+96+96 — with the serial 40 outside it. Both figures are right about
different populations and neither is a defect, but a total that does not match the table under it is
how the next pass inherits a wrong denominator, which is this row's entire failure mode. The row now
states 408 and says which part 368 counts.

What is *not* softened is the defect. One red on a git-clean, 24-file, fully tracked fixture
directory proves it, and the mechanism is cited unchanged: `parity-manifest-check.sh:431` and `:437`
pipe a `printf` of the list into `grep -qxF` per item and read **any** non-zero exit as *not found*,
with no way to separate a genuine miss from a `grep` that failed to spawn. `:189` is the same shape
for the cli list. Direction stays **false-RED**. The row closes on the operational line rather than
a recipe: read any manifest-check red seen while other work is running as unproven, and re-run it on
a quiet machine before acting on it.

That is the treatment `ORCHESTRATOR.md`'s fleet-level gate hazard row on `main` already uses, and
the row now matches it rather than diverging from it.

## BL-2 — the both-directions contradiction is proven once, not reproduced since

The row previously said the mechanism was *proven rather than suspected*, resting on ten fixture
names being reported simultaneously in both directions over an unchanging directory. It now says
**proven once and not reproduced since**, and calls the mechanism *the best-supported account rather
than a re-demonstrated one* — because the fourth verification's single red gave direction A only and
could not re-witness the contradiction.

**One difference between the two records is stated rather than quietly resolved.** The fleet hazard
row on `main` reads *not re-witnessed since the third verification*. Gap-fix 3 reported that it did
re-witness the shape — `servers` in both directions over 80 runs — so by that record it was seen
twice, not once. Neither pass's run can be replayed to settle which reading is right, so the row
carries both and names the discrepancy instead of picking one. Under BL-1's own logic, silently
adopting one number over the other is the error this pass exists to stop.

## BL-3 — there was no G5 merge

`R17-gapfix-3.md` recorded the mid-pass reconciler red as *`ai/g5`'s tip became an ancestor of
`main` — another session's merge*. That is false, and the git state says so without ambiguity:

```
$ git merge-base ai/g5 main
2fbe0625c3ee42976d2b638531ca8cd0fe6ecba9
$ git branch --contains 2fbe062 --list main
+ main
$ git log --merges --format="%h %s" main -4
e121801 Merge M21: the palette becomes Patchbay, and the token layer is where it says it is
4429e36 Merge R7: the router now reads the file each harness actually reads
6d54ce2 Merge M23: the mock-to-SwiftUI contract, and eight bounces of learning how to check a check
3e0b6b8 Merge branch 'main' into ai/m23
$ git branch --merged main --list "ai/g5"
(no output)
```

`main`'s merge list holds M21, R7, M23 and G3 and no G5 anywhere in it.

`2fbe062` is a commit **on** `main`, timed 14:26:58. `ai/g5` was cut from it and had committed
**nothing** by the 14:33 reconciler run, so its tip *was* a `main` commit and
`git branch --merged main --list ai/*` listed it from the instant the branch was created. Nothing
named G5 has ever been merged.

The premise that makes this unreadable is at `ledger-reconcile.py:282`, whose `merged_branches`
docstring calls that listing *the hardest evidence an id is taken* — true of a branch with commits,
false of an empty one. This is the **check-E false-RED**, recorded on `main` as a dispatch hazard
and as `D-g4-b`, G4's twelfth instance, with the operating rule that a check-E finding naming a
branch created after this worktree's base is that rather than a defect, and should be confirmed from
`main` before it is acted on.

The gap-fix 3 runner's *conclusion* was right and was properly established — it restored
`ORCHESTRATOR.md` to `HEAD`, re-ran, got the identical finding, and diffed the file back byte for
byte. Only the cause was wrong. The correction is written into that doc as a marked block quoting
what it originally said, rather than by overwriting the sentence, because a progress doc that
silently changes its own account of a measurement is worth less than one that shows the change.

**The state has since moved again, which is the same lesson twice.** `ai/g5` took two commits at
14:40:51 and 14:48:55, so `2fbe062` is now `ai/g5~2`, the branch is no longer an ancestor of `main`,
and this pass's reconciler run reports `merged ai/*  26 branches` with check E clean — the red is
gone with no row having been written for it. A gate whose finding disappears because an unrelated
branch grew a commit was never reporting on this branch.

## BL-4 — the sweep is a committed script, and it is a fixed point under its own output

`planning/claim-sweep.py` is gap-fix 3's sweep, committed. It reads each tracked file whole,
collapses every whitespace run — newlines included — to one space, matches against that view, and
maps each hit back to a line number in the original, so a claim broken across a hard wrap is
visible. That is the defect that caused the fourth block: `grep -c "all four uncovered sites"`
returned 0 while the phrase sat in the file, split between `all four` and `uncovered sites`.

**The reason gap-fix 3's evidence did not reproduce is now a property of the script rather than an
accident of timing.** A pass that withdraws a claim must quote the claim to record the withdrawal,
and the sweep's own output echoes the text it matched — so pasting a clean sweep into a progress doc
makes the next sweep red on the paste. Measured: run without exclusions over the tree at base
`0951650`, gap-fix 3's own script returns **8 blocking hits, every one of them inside
`R17-gapfix-3.md`** — five prose quotations of the withdrawn claim, and three that are the pasted
report's own pattern labels at `:49`, `:50` and `:51`. Run without exclusions over this pass's tree,
with the script and this file tracked, it returns **20**. The gate reds on its own evidence, and
gets worse the more carefully a pass documents itself.

So the script declares a small excluded set — the R17 gap-fix progress docs, the archived lane
reviews, and itself — **lists them by name with no counts, and does not scan them**. Names only is
what makes the output identical whether or not it has been pasted into one of those files, so the
evidence below reproduces exactly. The cost is stated in the script's own docstring rather than
hidden: a genuine re-assertion inside one of those records would not be seen. They are records of
what was withdrawn; a claim asserted as current belongs in an evidence, spec or declaration file,
and all of those are scanned.

The fixed point was checked rather than asserted: the sweep was run with this file holding a
placeholder, its output pasted in, and the sweep run again — `cmp` reports the two byte-identical.
That is the property gap-fix 3's evidence lacked. Its output was captured before its own file was
committed, so it described a corpus that no longer existed by the time anyone read it.

**Writing this doc found a second instance of the same defect, one layer in.** The BL-3 correction
above is a markdown blockquote, so the sentence it quotes carries a `>` between its lines — and a
`>` separates two words exactly as a hard wrap does. Probed with the withdrawn claim inside a
blockquote, `A1` fired on the part that fitted within one line and `A2` did not fire across the
marker at all. Collapsing whitespace is not enough when the corpus is markdown, because markdown
puts non-whitespace characters at the front of a continued line. The script now treats a blockquote
marker opening a line as whitespace, and the same probe reports both classes.

The limit that remains is stated rather than fixed: **list bullets, numbered-list markers and table
pipes can separate words the same way and are not stripped**, because only the blockquote marker was
measured. Adding the fix changed nothing in the corpus — the output below is byte-identical before
and after it — so it buys future coverage rather than closing a live miss.

Run against the committed tree, with this file tracked and in place:

```
scanned 1114 tracked files (157 skipped as non-text)
excluded 6 as records of a withdrawn claim, listed by name and not scanned:
      planning/claim-sweep.py
      planning/evidence/R17-gapfix-review-agy.md
      planning/evidence/R17-gapfix-review-fable.md
      planning/progress/R17-gapfix-2.md
      planning/progress/R17-gapfix-3.md
      planning/progress/R17-gapfix-4.md

A1  all four uncovered              0 hit(s)
A2  four uncovered sites            0 hit(s)
A3  which four it does not          0 hit(s)
A4  any 'four' near sites/saves     14 hit(s)
      ORCHESTRATOR.md:254   four sites
      ORCHESTRATOR.md:256   four sites
      ORCHESTRATOR.md:261   four sites
      planning/evidence/M14-acceptance.md:161   four rotted test sites
      planning/evidence/M23-acceptance.md:406   four sites
      planning/evidence/P2-acceptance.md:71   four splits: `ImportConfigWriter
      planning/evidence/R17-acceptance.md:315   four `saveManifest` call sites
      planning/evidence/R17-acceptance.md:324   four and two are uncovered
      planning/evidence/V1-review.md:150   four sites
      planning/features-to-triage/R17-gapfix.md:90   four sites
      planning/plans/plan-M14.md:4   four rotted test sites
      planning/plans/plan-M14.md:48   four rotted test sites
      planning/plans/plan-M15.md:191   four sites
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
B1  withdrawn clause (verbatim)     0 hit(s)
B2  withdrawn clause (concept)      0 hit(s)
B3  symmetry claim                  0 hit(s)
B4  'still carry the same'          0 hit(s)

blocking classes A1+A2+A3 total: 0
```

`A1`–`A3` are the blocking classes and are empty, and this time the corpus that produced them
includes the files this pass wrote. Two counts moved for a stated reason rather than a substantive
one: `A4` reads 14 where gap-fix 3 read 19, and `B1`–`B4` read 0 where it read 5, 3, 2 and 2. **Every
one of those 17 hits sits in the four records this script now excludes and gap-fix 3 scanned, and
none was removed from the tree** — a 0 there means *not scanned*, not *gone*. `A5` and `A6` still show all four homes of the count saying six, and `A7`
still shows `R17-acceptance.md:472` reading `declaration names all six`.


## Gates — measured on this tree, with every run reported

| Gate | Result |
|---|---|
| `make lint` | exit 0 — `Done linting! Found 0 violations, 0 serious in 531 files`, `no-raw-design-values: clean` |
| `make parity` | exit 0 — `parity: 358 vector cases compared (floor 358)` |
| `parity-cli.sh` | exit 0 — `cli: 18 verbs agreed, 0 did not`, all four `cli-watch` scenarios `ok` |
| `ledger-reconcile.py` | exit 0 — `reconciled — no findings across A, B, B-range, C, D, E, F, G, H, I, J, K`, `K examined 217 deferred-register rows` |
| `planning/claim-sweep.py` | exit 0 — `blocking classes A1+A2+A3 total: 0` |
| `make test` | **run 1 exit 2**, `Test run with 1686 tests in 210 suites failed after 9.137 seconds with 1 issue`. **Run 2 exit 0**, `Test run with 1686 tests in 210 suites passed after 5.912 seconds` |

Check L does not exist on this base — `grep -nE '\("L"\|check L' planning/ledger-reconcile.py` returns
nothing and the reconciler's summary stops at K — so *0 across A–L* is unmeetable here and A–K is
what is claimed.

**Check E is clean this time, and that is the BL-3 correction confirming itself.** The reconciler
reports `merged ai/*  26 branches` where gap-fix 3's red run reported 27. Nothing was written to
make that happen: `ai/g5` simply took two commits and stopped being an ancestor of `main`.

### The `make test` red, named rather than re-rolled away

Run 1 failed at `OAuthWireTests.swift:263`, *a waiter that is cancelled is resumed rather than
stranded* — `Expectation failed: await finished.value`, one issue in 1686 tests across 210 suites.
The test sleeps a fixed 3 s at `:262` before cancelling and asserting the waiter finished.

It is **already registered twice**, in a file this pass does not touch: `D-g3-s` lists
`OAuthWireTests.swift:263` by file and line as one of its fixed-sleep flakes, and `D-m23-be` records
this exact test going red once before with the same reading — *a cancellation-timing test on a
machine concurrently running another session's Swift builds*. This pass changed no code at all; its
whole diff is one register row, two progress docs and one new Python script, and
`git diff --name-only` names nothing under `src/`, `app/` or `scripts/acceptance/`.

**The two runs are reported as two events and deliberately not as a rate**, because turning *1 red
in 2 runs* into a reproduction figure is precisely the mistake this pass exists to stop. The load
figures are the point instead. Run 1 sat inside a gate chain that opened at a 1-minute load average
of **625** and closed at **330** with the 5-minute average reading **1015**; run 2 was bracketed
directly, **813** before and **869** after. Both were on a box with several other sessions building
Swift, and the fourth verification's finding —
that total machine pressure is the controlling variable — applies to this red as much as to the
manifest-check one.

The test and suite counts are unmoved at **1686 in 210** in both runs, which is the figure the work
order asks for.

**One thing this pass did not do, because it is outside the stated scope:** `D-g3-s` keeps a running
instance count and today's red is another one, but the scope names only the `D-r17-d` row in
`ORCHESTRATOR.md`, so `D-g3-s` was left alone. The orchestrator may want to fold it in.

## The sweep was proven able to fail

A gate whose pass and whose cannot-run look alike is not a measurement, so the sweep was mutated
rather than trusted. A two-line file was planted in a scanned directory carrying the withdrawn claim
**split across a line break** — the exact shape that defeated `grep -c` and caused the fourth block:

```
The declaration names all four uncovered
sites, which is the withdrawn claim.
```

The sweep reported `blocking classes A1+A2+A3 total: 2` and **exit 1**.

A second probe put the same claim inside a blockquote, which is the shape the BL-3 correction above
is written in:

```
> The declaration names all four uncovered
> sites, which is the withdrawn claim.
```

Before the blockquote fix that probe reported **1**, `A1` only — the cross-line class silently
missed. After it, **2** and exit 1. Both probes were then removed from the index and the disk, and
`git status` returns to the four intended paths.
