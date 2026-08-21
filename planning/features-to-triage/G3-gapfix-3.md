# G3 gap-fix 3 — the residue fails toward misses, and the third model has no grammar

**Parent:** G3 — `make test` is not deterministically green
**Status:** Untriaged · gap-fix, third pass
**Verdict that produced it:** Needs More Work, 2026-08-21, rung `metamorphic`
**Worktree:** `.worktrees/G3`, branch `ai/g3`, base `e8c20e0`

## What holds, and must not be reopened

The verifier re-measured everything and it stood: `make test` 0 twice at 1587/199, lint 0 over 497
files, parity 358/358, `acceptance-r6` clean, and the assigned mutation redding at **10.836 s**
under load 127 against the runner's 10.589 s. It built `Delexer` and `AwaitBoundScan` standalone
and walked the four trees itself — exactly 5 call sites, all bounded, no unreadable file. It
confirmed `PrimitiveBodyTests.swift:140` was a **real** miss rather than self-inflicted, and that
criterion 3's deletion is honest rather than convenient.

The rebuild was the right call and the delexer is not in question. Three of the four blockers below
live in the layer the rebuild deliberately did not replace.

## B1 — a correction that does not reproduce

`D-g3-q`'s deferral rests on: gutting both accessors reds only `PoolReapingTests.swift:101`, with
`PoolTests.swift:144` load-dependent. The verifier ran it **4 of 4 red on both sites**, at 15.5%
idle falling to 0.6% and 1-minute load 127 — *heavier* contention than the runner's, so the
load-dependence explanation fails on its own terms.

The register now asserts one site fewer than the previous verifier measured and derives a narrower
deferral from it. Withdraw that derivation. Either re-establish it with evidence that survives
someone else's machine, or restore the previous verifier's reading and defer `D-g3-q` on scope
alone — which was always available and needs no contested measurement.

**The orchestrator relayed this correction into the ledger and a commit message as established
fact.** That is corrected on main; do not carry the old wording forward.

## B2 — the residue fails toward misses, not toward reds

The brief claims the remaining approximation "each fail toward a red on correct source rather than
toward a miss". Two counterexamples, each pinned by a **one-token control**:

**A statement label before a control keyword.** `check: if awaitEvent(x) {` reads the enclosed call
as BOUND; delete the label and identical source reads UNBOUND. `firstWord(of:)` at
`PoolAwaitBoundTests.swift:295` returns `check`, so the `bodyKeywords` guard at `:255` — added in
round two *precisely because a lane broke this* — never fires, and a control-flow body reads as the
wrapper's trailing closure. Labels are legal on `if`, `while`, `for`, `switch` and `do`.

**A labelled string-literal final argument.** `await p.awaitReap(name: "own")` produces **no call
site at all**. The delexer blanks the literal to spaces, `lastMeaningful(before: close - 1)` at
`:182` walks back over them onto the label's `:`, and `callEnd` discards the call as an unapplied
method reference. Replace the literal with an identifier, or drop the label, and the call is seen.
Unreachable with today's two signatures and silent the moment one gains a labelled string parameter.

And one false fire in the same layer: the word `Task` **anywhere in the opener statement, including
inside a string interpolation**, reddens a correct wrap. `try await awaitEvent("reap at
\(Task.currentPriority)") { … }` reads UNBOUND; swap `Task` for `Clock` in the same line and it
reads BOUND. The `escapes` test at `:259` runs on the opener statement rather than on the callee
actually receiving the closure.

Fix all three, and correct the brief's directional claim — a claim about which way a residue fails
is load-bearing, because it decides whether the residue is tolerable.

## B3 — the population is three models, not two

Family A (lexical grammar, 19 controls) and Family B (block structure, 12) rest on closed, citable
production lists. That argument is sound and the 53 arithmetic checks out.

Family C — 22 controls — is `verdict` / `statement` / `firstWord` / `continuesStatement` plus four
hand-written keyword lists. Its population is exactly *shapes somebody might write*: the open set
the completeness argument set out to escape. The doc comment on `AwaitBoundControl` enumerates only
A and B; the ORCHESTRATOR row presents all 53 as one claim across three families.

The 34-of-34 matrix proves each **implemented** mechanism is load-bearing — mutation adequacy of the
code as written. That is a different claim from covering the grammar the code **should** implement,
and B2 shows the difference is where the defects are.

Either give Family C a closed model, or state the split where the claim is made. **Stating the split
is an acceptable answer** — an honest bound beats a claim that reads wider than it is. What is not
acceptable is leaving one number standing for three populations of different kinds.

## B4 — five register ids occur twice

`D-g3-g` … `D-g3-k` each appear twice inside ORCHESTRATOR.md's Deferred children section on this
branch, at lines 567-571 and 618-622, and **three carry materially different rows** (`g`, `i`, `k` —
verified by whole-row comparison). Introduced by this pass's own merge `e4cb050` and shipped at
`cbc6a81`. `main` has one of each, so the merge cannot remove them.

**`ledger-reconcile.py` now has check K**, which catches exactly this and would refuse the merge.
Run it before you report ready. Check K found two more on main while it was being written —
`D-p1-a` and `D-p1-e`, each with a register row and a stray copy in the item table — and those are
merged into one row each on main already; do not re-split them.

## Acceptance

1. Each of B2's three shapes flips: both misses go red, the false fire goes green. Add all three to
   the controls in both directions.
2. The brief's directional claim about the residue is corrected to match what B2 measured.
3. Family C either gains a closed model or the claim states its split. Whichever, the ORCHESTRATOR
   row stops presenting 53 as one population.
4. `D-g3-q`'s deferral no longer rests on a measurement that does not reproduce.
5. `ledger-reconcile.py` exits 0 on the branch — check K included.
6. Everything in *What holds* stays holding: gates green, the assigned mutation redding inside the
   bound, exactly 5 call sites all bounded.

## Scope

`PoolAwaitBoundTests.swift` and its control files, `PoolTestSupport.swift`, this item's briefs and
register rows. `D-g3-a` … `D-g3-z` stay deferred except `D-g3-q`'s wording, which B1 requires.
`D-g3-aa` … `D-g3-ac` are B2's three shapes and are **in scope**. `D-g3-ad` is B4. `D-g3-ae` is B3.
`D-g3-af` (the assigned mutation as specified does not compile — it needs a local capture before the
`Task`, or it fails with *explicit use of self is required*) and `D-g3-ag` (two cited length limits
that no config or document states) are registered and **not** this pass's work.

## Lanes

Codex is down until 27 August. Gemini delivered on a break-it prompt at 26 KB; fable produced
nothing after ten minutes at 7% idle and the same size, reported as not delivered rather than as a
lane defect — try it at a smaller packet. Grok has failed repeatedly including at 3.7 KB, so do not
budget on it. **Ask each lane to break the scanner rather than review it**; that phrasing has
produced a defect every time it was used on this item.
