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
