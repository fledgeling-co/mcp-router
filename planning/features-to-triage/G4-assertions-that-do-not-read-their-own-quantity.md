# G4 — assertions that do not read the quantity they are named for

**Class:** harness / instrument. **Status:** Untriaged, not dispatched.
**Source:** a cross-session exchange with the `egress` project on 2026-08-21, which arrived at the
generalisation from a defect in its own suite. Filed here because this repository has now found
three instances of the same shape and treated each as unrelated.

## The shape

An assertion is named for a quantity, and reads a different one. Its pass and its
cannot-discriminate are indistinguishable, so it is green in both cases and the green carries no
information about the thing in the name.

Three already found here, each filed separately and none recognised as the same defect:

| Instance | Named for | Actually read |
|---|---|---|
| `ledger-reconcile.py` check H, before the skip list | rows | rows it could parse — 23 four-cell register rows were dropped silently |
| G2's first acceptance test | readability | in-scope-ness — satisfiable by moving rows *out* of the reader's scope |
| R7's `no-harness-config-writes.sh` | any write anywhere under `app/Sources` | writes on the *same physical line* as the token, so a realistic applier walks through |
| `ledger-reconcile.py` check I | whether the two ledgers agree on an item's state | whether they agree on a state its classifier can name — and `\bverified\b` does not match "verify", so **`Ready to verify`, the state every item passes through on its way to Done, matched no pattern at all**. The currency check read nothing for the one moment the two files are most likely to disagree. Found 2026-08-21 when M23 became the only row in that state; fixed by adding the pattern ahead of `verified`. It reported `1 unread (M23)` rather than passing silently, which is the only reason it cost one line to find — and is the difference between this instance and the first one in this table |
| `ledger-reconcile.py` check H's skip list | the rows it could not read | the rows that were too **short** — it names every row with fewer cells than its header and silently drops every row with more. A nine-column item row misfiled into the four-column register was invisible to it, and stayed invisible while H's denominator line reported a clean 73. Found 2026-08-21 by adding check J, which reads the other direction; moving the one row it found took H and I from 73 examined to **74**, so this is the rarer case where a shape fix genuinely adds coverage rather than tidying. Distinct from `G2`'s 23 strays, which are too **short** and are outside all nine checks before and after any move |
| The reconciler's ten checks, against `ORCHESTRATOR.md`'s integrity | whether the memory of record is sound | whether its **rows** are sound. Two unresolved merge-conflict blocks sat committed in that file from the R7 merge until 2026-08-22, and **all ten checks passed over them** — J counts cells in rows, K counts ids in rows, and a conflict marker is neither, because it does not begin with a pipe. Found by R17's second verifier, not by the instrument. The orchestrator introduced them by resolving the other tracker file, checking **that** file for markers, then reading `git status`'s silence on unmerged paths as silence on markers. Check L reads **lines** rather than rows, which is the whole of the fix, and is armed against the pre-fix file |
| G3 gap-fix's acceptance criterion 3 | which side of the await the bound sits on | the resolved integer at `:87`, and nothing else. The mutation it names leaves the reap deadline on the requested 25 ms window, so **it could not take ten minutes whichever side the bound is on** — relaxing `:87` so execution reaches `:98` gives the test passing in 2.291 s and the run green. The 3.9-5.3 s red it does produce carries no information about the quantity the criterion is named for. **Written by the orchestrator**, in the brief for the item whose whole subject is assertions that cannot fail the way their name implies, and caught by that item's own verifier |

And the one from `egress` that produced the framing: a test named
`the_exchange_budget_has_measured_headroom_over_the_slowest_verb` reads `warm_worst * 4`. Cutting
`EXCHANGE_TIMEOUT` from 1500ms to 10ms — a 150× reduction — left 7 of 7 green. The budget appears
in the expression and does no work in it.

## Why it is worth a gate rather than vigilance

Every one of these was found by accident, by someone attacking something adjacent. None was found
by review, and all four survived readers who were specifically looking for weak assertions —
because the assertion reads plausibly and its subject is in its name.

The detection is mechanical and cheap: **identify the quantity in the assertion's name, perturb
that quantity by a large factor, and require red.** Anything that stays green is misnamed at best.
The manual version found the `egress` instance in about four minutes.

## What is unresolved, and why this is Untriaged rather than Ready

Whether the name → quantity mapping is mechanisable at all. A gate that guesses the quantity from
the test name will mis-target, and a mis-targeted perturbation that stays green is a false finding
of exactly the kind this repository's `detector-defects` doctrine exists to refuse. Options, none
costed:

- Author-declared: each assertion names its quantity in a comment or attribute, and the gate
  perturbs what it is told. Honest, and it only covers assertions somebody annotated.
- Derived from the constant an assertion references, perturbing every named constant in scope and
  requiring at least one to turn it red. Mechanisable, noisier, and it catches the case above
  (`EXCHANGE_TIMEOUT` is in scope and unread).
- A one-off audit rather than a standing gate — cheaper, and it does not hold the line afterwards.

Triage should also decide whether this is one item or the *policy* half of `G1`, which already owns
soft-assertion findings (`D-r6-h`, `D-m27-b`, `D-r7-j`, `D-r7-k` are all this shape at the lane
level).

## A related instrument, recorded so it is not lost

The same exchange produced a discriminator worth having independently: **assert a relationship
between samples, not a bound on one.** A bound needs to know what the machine was doing; a
relationship does not, because both terms move together. Argmax position (warm-up puts it at index
0, contention is uniform), the count exceeding *k* × median (warm-up gives exactly 1), p99/p50 with
index 0 dropped, and the same vector run twice around a control workload you start and stop
yourself.

Its stated limit matters as much as the technique: it discriminates warm-up from contention and
**only** that. A mid-sequence peak means "not warm-up" and nothing more — a genuine regression
looks identical.

All of it is free once a timing test keeps its sample vector instead of reducing to `worst` and
`mean` and discarding the samples. None of it is available before that. This bears directly on
`G3`, whose subject is the only wall-clock assertion in this suite.







## The method note that came out of fixing the eleventh, and it generalises

G4's gap-fix rebuilt the absence sweep three times before it was right, and **neither wrong
version was caught by the absence check**. Both were caught by a *control asserting the corrected
figures are present*.

- Whitespace normalisation alone still leaves `over 27 # iterations` — a comment marker inside the
  wrapped phrase, which no amount of newline collapsing removes.
- An unqualified `*` strip turned `**Fifteen readers` into `*Fifteen readers`, so the corrected
  text stopped matching the pattern written to find it.

The general statement is the useful part, and it is the cleanest thing this item has produced:
**an absence check cannot detect its own blindness.** A clean result means either the claim is gone
or the reader cannot see it, and those are indistinguishable from the inside. A *presence* control
over the replacement text distinguishes them for free — if the corrected phrase is not found, the
reader is broken, whatever the absence check said.

That is worth carrying beyond this item. Every one of the four absence sweeps in this table
(instances 1, 4, 5, 10) would have been caught on its first run by a presence control over the
thing that should have been there.

## A thirteenth instance — M15's arm 6b, and this one was found on purpose

`no-raw-design-values.sh` is named for *no raw geometry literal survives in the design surfaces*.
It reads *no raw geometry literal survives in the directories currently listed in `GEOMETRY_DIRS`*.

M15's runner armed exactly that gap rather than stumbling into it: remove `Settings/` from
`GEOMETRY_DIRS`, and the same literal the rule exists to catch **passes clean**, while the scanned
count silently drops **84 → 74**. The gate prints its denominator, which is the only reason the
drop is visible at all — and nothing asserts that the denominator did not move.

This is the same shape as the ninth and twelfth, and it is the first found by somebody deliberately
aiming at it. It is also the cheapest to close of any instance in this table: a gate that prints a
count is one assertion away from a gate that defends it. **A scanned-file count that can fall
without failing is a coverage figure nobody is holding.**

Worth pairing with the eleventh when this item's gap-fix runs, because they are the same fix from
opposite directions — the census measured its base with the instrument inside the tree, and this
gate measures its subject with the tree adjustable underneath the instrument.

## A twelfth instance — the reconciler's check E, found the same afternoon

Check E is named *"a branch merged into main with no row in either file"*. It reads **refs that
are ancestors of `main`, compared against whatever ledger files this particular checkout happens
to hold**. Two independent gaps between the name and the reading, and on 2026-08-22 they fired
together:

1. **A branch with no commits is an ancestor of main**, so `git branch --merged main` lists it the
   instant it is created. `ai/g5` was cut from `2fbe062` and had committed nothing; `git rev-parse`
   confirms its tip *is* a main commit. Nothing merged, and E called it merged.
2. **It mixes live repository state with branch-local file state.** The `G5` row exists on `main`
   and in no worktree, because every worktree is on an older base. So E read a *global, current*
   branch list against a *local, stale* ledger and reported the disagreement as a defect.

Reproduced deliberately: the reconciler exits 0 from `main` and exits 1 on `E — G5 (ai/g5)` from
`.worktrees/R17`, on the same commit of the script, at the same moment.

**This is the instance with the widest blast radius, because every runner runs the reconciler from
a worktree.** R17's gap-fix 3 runner hit it, and its diagnosis — *another session merged `ai/g5`
into main* — was the natural reading and wrong. It then did the right thing anyway: restored
`ORCHESTRATOR.md` to `HEAD`, re-ran, got the identical finding, and proved the edit was not the
cause. A check whose false positive reads as *somebody else broke main* costs more than one whose
false positive reads as noise.

Direction is false-RED, so it costs attention rather than correctness — the same direction as
`D-r17-d`, and the same underlying error as the ninth instance: **a figure read from one scope and
named for another.** Registered as `D-g4-b`, widened from the live-count half the G4 verifier
first found. Not fixed here: five runners are reading that file.

## An eleventh instance — this item's own census, found by its own verifier

The census that is this item's headline deliverable counted **the instrument into its own
denominator**. Run the shipped detector against `git archive 72958de` with the gate placed outside
`planning/` and `scripts/`, and the base tree reads **15 readers over 22 discarding iterations and
34 drop sites** — not the 19/27/48 reported. Copy `reader-accounting.py` into that base tree and
the reported column reappears exactly, which is what proves the mechanism rather than merely
suggesting it: the four readers and fourteen drop sites the gate itself contributes were counted as
pre-existing.

*"Nineteen readers in this repository"* is commit `5a9569c`'s subject line and §1's headline. The
quantity in its name is **readers that existed before this item**; the quantity it reads is
**readers present when the detector ran**, which includes the detector.

Unlike the ninth and tenth, this one **is** on the reachable side — and the after column caught it
without being asked: `unresolved 67` is the verifier's measured 55 plus the 12 the three new files
contribute, with the per-file breakdown identical across both runs for the other eighteen files.
The accounting was sound; the *baseline* it was compared against was not.

Which is the general lesson worth keeping: a before-and-after census is two measurements, and the
gate only governs one of them. **Measure the base with the instrument outside the tree**, or the
improvement includes the improver.

## A tenth instance, found 2026-08-22 by R17's third verification

An absence sweep named for *"this claim survives nowhere in the corpus"* that reads *"this claim
survives on no single line"*. R17 gap-fix 2's criterion 3 asked for a grep proving a withdrawn
claim was gone. The grep returned clean. The claim is still there:

```
grep -c "all four uncovered sites" planning/evidence/R17-acceptance.md   →  0
re.findall(r'all\s+four\s+uncovered', open(path).read())                →  1
```

The file is hard-wrapped, and the wrap falls between `all four` and `uncovered sites`. Every
line-anchored reader is blind to it, and a clean exit from one is indistinguishable from an absence.

This is the sharpest instance in the table, because the assertion was **written specifically to
catch a claim that had already survived two corrections** — and it is the fourth consecutive pass
to block on that claim. The first three were diligence: a correction landing in some of a claim's
homes. This one is the instrument: a sweep that could not read one of the homes at all.

It also lands on this item's *unreachable* side, like the ninth. Nothing is dropped and nothing is
vacuous — the grep read every line it was given and answered honestly about lines. The quantity in
its name is *occurrences in the corpus* and the quantity it reads is *occurrences within a line*.
Same shape as instances 2, 3, 7 and the `egress` one.

**Cheap general remedy, worth stating because it costs nothing**: an absence assertion over prose
normalises whitespace across newlines before matching, or reads whole files. A presence assertion
does not need this — a hard wrap can hide a match, so it can only ever turn a true finding into a
false clean, which is the direction that matters.

## A ninth instance, found 2026-08-22, and it is the orchestrator's

A dispatch brief's gate line is named for *the base this branch was cut from* and read from
*whichever report was last in front of the author*. Four occurrences in one morning:

| Stated in the brief | Measured at the base |
|---|---|
| `make test` 0 at **1686/210** | **1684 in 209** — the 1686 is `ai/r17`'s, and that branch is 16 commits ahead of main |
| lint 0 over **531 files** | **530** |
| `scripts/acceptance/no-raw-design-values.sh` | the script is `scripts/lint/no-raw-design-values.sh` |
| `reconciler 0 across **A–L**` | the base carries **A–K**; check L landed on main afterwards |

It belongs in this table because it is the same shape as everything above it and not because it
is embarrassing: the number is *plausible*, its subject is *in its name*, and a green reading
against it proves nothing about the base the brief actually named. Two runners hit it
independently and both spent attention proving the orchestrator wrong — G4's own runner reported
the two-test gap as unexplained, because the brief had told it to expect more than exists.

**Neither mechanism this item builds would catch it**, which is worth saying plainly: nothing is
dropped and nothing is vacuous. It is instance 2/3/7's kind — a real quantity read from the wrong
place — and it lands on the wrong side of this item's own boundary. The remedy is procedural and
sits in `ORCHESTRATOR.md` as a dispatch hazard: run the gate line against the stated base and
paste what it returns, rather than carrying a figure across branches.

---

## Triage — 2026-08-22

**Verdict: Ready for AI.** Standard tier. Harness-only; depends on nothing.

### The open question is answered, and the answer is that the mapping is *not* mechanisable

This brief was Untriaged because it could not say whether name → quantity could be derived without
annotation. Referred to the Google lane (`agy`, `gemini-3.7-flash-high`) with all eight instances
and the three options. Verdict on the question as asked:

> No. Heuristic or NLP mapping from test identifiers to arbitrary in-scope constants yields
> ambiguous bindings and false positives on auxiliary constants, directly violating your
> zero-false-finding doctrine.

So **option B is refused on the repository's own detector-defects doctrine**, which is what this
brief suspected and could not settle. Option A is honest and starts at zero coverage; option C
holds no line. None of the three is worth building.

### The shape that replaces them

The lane declined the framing rather than the question, and the substitute is better because it
does not need to know the quantity at all. Two mechanisms:

1. **Raw-input accounting as a structural invariant.** Every reader, parser and matcher returns
   `(matched, dropped)`, and `dropped` must be empty unless a skip is declared explicitly. This is
   not a new idea here — `ledger-reconcile.py` already *prints* `examined N` and a skip list, and
   that printed line is the only reason instances 1, 4 and 5 were ever found. The work is turning a
   convention that one script follows into a contract every reader satisfies and a gate that fails
   when it does not.

2. **A null-run gate.** Execute each assertion against an empty fixture, an inverted state, or
   poisoned input. **An assertion that passes on a null or poisoned input is provably vacuous**, and
   that is a deterministic property of the assertion rather than an inference about its name.

Between them these reach instances 1, 4, 5 and 6 — every silent-drop and partial-match case in the
table — with no annotation, no name parsing, and no class of false finding on correct code. That
last property is the one that made the original three options unbuildable here.

### What the shape does not reach, stated rather than implied

Instances 2, 3, 7 and the `egress` one are not silent-drop defects: each reads a real quantity that
is the wrong one, and each would survive both mechanisms. Half of this brief's own table is
therefore out of scope for its own fix. That is worth building anyway — four of eight, mechanically
and permanently, beats eight of eight by vigilance — but the item must not be reported as closing
the class.

`G1` keeps the soft-assertion findings at lane level (`D-r6-h`, `D-m27-b`, `D-r7-j`, `D-r7-k`).
This stays a separate item: G1 owns assertions that are too weak, and this owns readers that cannot
account for their own input. Those want different gates.
