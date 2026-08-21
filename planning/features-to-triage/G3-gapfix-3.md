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

---

# Delivered — gap-fix 3

## The three shapes, each with its red and its green

Every one was found by a reader constructing source, and every one is pinned by a **one-token**
control: change the single token and the scan changes its answer. Both directions are in the tree.

| shape | before | control (one token changed) | after |
|---|---|---|---|
| `check: if awaitEvent(x) {` around a bare call | `3:BOUND` — a **miss** | label deleted → `3:UNBOUND` | `3:UNBOUND` |
| `await p.awaitReap(name: "own")` | `[]` — **no call site at all** | literal → identifier → `2:UNBOUND` | `2:UNBOUND` |
| `try await awaitEvent("reap at \(Task.currentPriority)") { … }` | `3:UNBOUND` — a **false fire** | `Task` → `Clock` → `3:BOUND` | `3:BOUND` |

**What each was.** `firstWord(of:)` returned `check`, so the `bodyKeywords` guard — added in round two
*because a lane broke exactly this* — never fired and a control-flow body read as the wrapper's
trailing closure. It now steps past a prefix that introduces a statement without being one, which
closed a `case`/`default` clause with it: `case .a: if awaitEvent(x) {` was the same miss through a
door nobody had opened, measured on the pre-fix scanner.

The second is one level up from where it showed. The delexer blanked comments and literals to the
same byte, and `awaitReap(name: "own")` therefore delexed to `awaitReap(name:    )` — the shape of
an unapplied method reference, which `callEnd` discards. **A comment is nothing and a literal is a
value**, and whitespace where a value stood is indistinguishable from absence. Literal bytes now
become `ScanByte.elided`, and so do non-ASCII code bytes, which was the same miss's other door:
`p.awaitReap(name: 名前)` was invisible for the same reason and is now a control.

The third ran the `escapes` test over the opener statement instead of over the callee receiving the
closure. An interpolation is code, so the word really was there. It now reads the owner of the brace.

## The directional claim, corrected

`G3-gapfix-2.md` said the remaining approximation's consequences "each fail toward a red on correct
source rather than toward a miss". That was **true of the three unreachable shapes it named and
false as a statement about the layer**, and the paragraph read as the second. A claim about which
way a residue fails decides whether the residue is tolerable, so the wording is corrected where it
was made, in the suite's doc comment, and in the register.

The corrected claim: **the layer fails both ways, and the direction is not predictable from it.**
The evidence is a count rather than an argument — of the twelve shapes measured against the
delivered scanner this pass, **eight fail toward a miss and four toward a red**:

- Blocking three: 2 misses, 1 false fire.
- The nine the lanes broke it with and this pass did not take (`D-g3-ah`): 6 misses, 3 reds.

A shape found in this layer is a defect until it is measured, not an inconvenience.

## Family C is stated, not closed

The count was one number over three populations of different kinds, and stating the split honestly
is the answer taken. `AwaitBoundControl`'s doc comment now reads:

- **Family A**, the lexical grammar — 19 controls, **closed**: a citable production list, one control
  per production.
- **Family B**, block structure — 12 controls, **closed**: brace nesting, which is what Swift uses.
- **Family C**, Swift's statement and trailing-closure grammar — 38 controls, **open**. `verdict`,
  `statement`, `firstWord`, `continuesStatement` and five keyword lists implement no grammar. Each
  control is a shape somebody wrote down, and the set of shapes somebody might write is exactly the
  open population the other two families escape. The count is a floor on coverage, not a bound on
  the space.

The mutation matrix is stated separately for the same reason: **69 controls, each seen to fail under
at least one of twelve single-mechanism mutations** proves that no mechanism in the code as written
is decorative. That is mutation adequacy of the implementation, and it is a different claim from
covering the grammar the implementation *should* have. Family C is where the two come apart, and
every defect of this round was in Family C.

`AwaitBoundScan` is now three files, split at that seam — the scan, the statement layer, and the
delexer — because the scan file passed SwiftLint's 400-line `file_length` default.

## `D-g3-q`: the derivation is withdrawn

Gap-fix 2 saw `PoolTests.swift:144` green 4 of 4 at 0% idle and derived a load-dependence from it.
The verifier ran the same mutation at 15.5% idle falling to 0.6% under 1-minute load 127 — *heavier*
contention than gap-fix 2 had — and got **both sites red 4 of 4**. Heavier load producing the site
that load was said to suppress refutes the explanation on its own terms. The register reverts to the
previous verifier's reading, and the deferral rests on **scope alone**, which was available the whole
time and needs no contested number: the remedy is `D-g3-g`, which is deferred, and the probe showing
`PROBE-EARLY-RETURN` 3 of 3 stands.

## The lanes

Asked to **break** the scanner rather than review it, which has now produced a defect on every round
of this item. Both lanes that delivered found real ones, and **two of them were regressions this
pass had just introduced** — reading the escape from the brace's owner fixed the interpolation false
fire and lost two shapes the whole-opener word search had covered.

| lane | family | outcome |
|---|---|---|
| `gemini-3.7-flash-high` | Google | **Delivered** at 33 KB, after one failed launch: headless mode auto-denied a tool permission and produced nothing. Re-run with `--disable-slash-commands` and an explicit "answer from this message alone", it returned 8 findings; all 8 reproduced, 3 taken |
| `claude-fable-5` at high | Anthropic, substituting for codex | **Delivered** at 8.6 KB, where 33 KB produced nothing last pass. 8 findings, 6 reproduced (2 were the `.init` defect gemini also found), 2 taken |
| `gpt-5.6-sol` | OpenAI | **Down** to 27 August, per the brief. Not attempted |
| `grok-4.6` at xhigh | xAI | **Down**, as the brief predicted. At the 8.6 KB packet it emitted 481 bytes of narration — "I'll load the voice skill and the scanner source first" — over ten minutes and produced no finding before its alarm. Reported once and not retried |

**Taken:** `_Concurrency.Task { }` and `Task.detached(operation: { })`, the two regressions;
`awaitEvent(.init("x")) { }` reading as a declaration; a receiver's dot at the end of a line putting
the opener span below the receiver; and the qualification test reading past whitespace, since
`collapsed` turns that line break into a space. `keep(Task { })` is a sixth that neither lane named
and only the union of the two owner positions catches.

**Not taken, with directions, as `D-g3-ah`:** a bare `awaitReap(…)` with no receiver; explicit
generic arguments on the call; a typealiased `Task`; an accessor or nested declaration inside a wrap;
a closure stored rather than run; an escaping closure inside the wrapper's own argument list — six
misses. `Self.awaitEvent(…)`, `awaitEvent(setup: { () })` and a backticked wrapper — three reds on
correct source. The last six are unreachable with the signatures as they stand.

## Gates

Each to a full log, `tail` reading the log.

| gate | exit | evidence |
|---|---|---|
| `make test` | **0** | `1587 tests in 199 suites passed after 7.126 seconds` |
| `make test` | **0** | `1587 tests in 199 suites passed after 12.513 seconds` |
| `make lint` | **0** | `Found 0 violations, 0 serious in 500 files` |
| `make parity` | **0** | `358 vector cases compared (floor 358)` |
| `make acceptance-r6` | **0** | `examined=6 failures=0` |
| `python3 planning/ledger-reconcile.py` | **0** | `reconciled — no findings across A, B, B-range, C, D, E, F, G, H, I, J, K`, check K examining 172 register rows |
| assigned mutation | **2** | `failed after 13.189 seconds with 1 issue` at `PoolReapingTests.swift:98:29`, *timed out after 10.0s waiting for: `own` to be reaped under the arming it just made* |

The mutation needed the local capture `D-g3-af` records — written as the brief specifies it, it does
not compile. `UpstreamPoolReaping.swift` was restored from a `cp` backup and `git diff app/Sources/`
is empty.

**Two of four `make test` runs went red, and saying only that two passed would be this item's own
shape.** `CallbackLifecycleTests.swift:238` (*the callback listener was cancelled before it bound*)
and `ControlStreamTests.swift:72` (`arrival < lastSent`, two timestamps that round to the same
second). Both are in files this item does not touch, both are `D-g3-c`'s class, and both are now
recorded under `D-g3-s` as its fourth and fifth measured instances. **`make test` is still not
deterministically green on this machine**, and nothing in this item's scope changes that — the
scope was the pool suites.

## Machine

1-minute load average **421**, idle **0.0%** for the whole pass, two sibling runners live.
**The timings above are not representative and are not offered as comparisons**: the assigned
mutation's 13.189 s sits against 10.589 s measured on the runner's machine last pass and 10.836 s on
the verifier's at load 127. What the numbers establish is the exit code and the named line, not the
duration.

## Left undone, and why

- **`D-g3-af` and `D-g3-ag`** are registered and out of scope by the brief. `D-g3-ag` gained a
  measurement while a control file was being split — the two cited limits are SwiftLint's own
  `file_length` and `type_body_length` defaults, which `.swiftlint.yml` does not configure — but the
  older comments still cite them without a source.
- **`D-g3-ah`'s nine shapes** are measured and left. Six are unreachable with today's signatures;
  the typealiased `Task` and the stored closure cannot be reached by a text scan at all, which is
  `D-g3-z`'s argument for a compile-time witness.
- **`D-g3-a` … `D-g3-z` stay deferred**, except `D-g3-q`'s wording, which B1 required.
- **The two flakes above** are `D-g3-c`'s classification work, not this pass's.
