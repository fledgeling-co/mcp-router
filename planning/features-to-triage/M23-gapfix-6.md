# M23 gap-fix 6 — stop arming the marker route by route; enumerate its routes

**Parent:** M23 — The mock-to-SwiftUI conversion contract
**Status:** Untriaged · gap-fix, sixth pass
**Verdict that produced it:** Needs More Work, 2026-08-21, rung `effect-witness`
**Worktree:** `.worktrees/M23`, branch `ai/m23`, base `efa7a91`

## What holds

The engine is byte-identical to `17e90e8` and the three pass commits touch exactly the selftest and
the two ledgers. **The restoration verifies independently** — the worktree was pristine before the
verifier ran anything, `git diff HEAD` empty, no untracked files, no mutation marker anywhere under
`scripts/` or `app/`. That matters because a lane mutated this tree last pass.

BL-1's arm reproduces exactly: exit 1, 58 ok, **case 43 alone**. The `D-m23-ag` correction
reproduces at 57 ok / 2 FAIL with case 50 green.

**Case 48's restructure survives the attack, and so do its floors.** Census mutation reds at the
identity; deleting the identity gives green at `3 + 1 = 3`. And deleting the exclusion entirely
yields `3 + 0 = 3`, **which the identity accepts** — only `excl >= 1` reds it. So the floors carry
load too, which is more than the restructure claimed.

Gates: A 1 at 132 findings with the ledger byte-identical, B 3 with a ledger written, selftest 0
twice at 59, lint 0, `make test` 0 twice at 1615/202, reconciler 0 across A–K.

## The mechanism, named at last

Five passes have each armed the marker on the routes they knew about, and the next verification has
found more. That is not five failures; it is one method failing five times. **The marker is being
armed route by route against a route set nobody has enumerated.**

The verifier enumerated it, and the number is the brief: **a full marker trace across the suite
records eight emissions — five from `gate()`'s post-write site and three from
`write_unmeasured_report`.** `write_unmeasured_report` has **five callers**; four lose the marker
under mutation and two of those are already executed by the suite.

So this pass's job is not to close four findings. It is to enumerate every site the marker is
emitted from and every route that reaches each, assert per route, and **state the enumeration and
how it was established** — the same move that ended the property-vs-route bouncing at pass 3.

## The four measured instances

Three are one assertion away on fixtures that already exist.

1. **`os.path.normpath(report_path)` leaves all 59 green.** `D-m23-ap`'s closure pinned two
   spellings — absolute under `$SCRATCH`, and a bare relative name — and `normpath` is the identity
   on both. The arm is one character: spell case 51's existing relative `--report` as
   `./rel-ledger.md`, which is green on the shipped engine and reds case 51 alone under the mutation.
2. **Moving the marker out of `write_unmeasured_report` into the one call site case 49 drives leaves
   all 59 green.** Four of five callers lose it; two are already executed.
3. **`D-m23-ar` is mis-stated, and one grep from closed.** It says the route is driven by no case.
   Measured: **case 44's two invocations do drive stdout-dead/stderr-open**, `emit`'s fallback fires
   on both, and case 44 throws them away with `2>/dev/null`. Capture them plus one grep: green on
   the shipped engine, red on case 44 alone under the bare-print mutation. **The orchestrator
   recorded that row from the runner's report without testing it** — correct the row as part of
   closing it.

## The finding that is worth more than the four

**`mock-fidelity-gate.sh` lines 128–141 — the marker's only consumer — is reached by no case**, and
loosening its grep leaves all 59 green. The selftest *declares* that gap, and **its stated reason is
measurably false**: it says covering it "needs the MEASURE build and four rendered dumps, three
minutes and not hermetic".

The verifier built the harness that disproves it — a symlinked gate script, the `swift` stub
`build()` already writes, and a twelve-line `MeasureDump` stub — reaching the gate's decision in
**about a second**. On a fixture, that harness reproduces `D-m23-ap` by printing `NO ledger was
written by this run (exit 0)` over a table it had just written. It is preserved at
`/tmp/m23v6/keep/clean/`.

That is the finding the previous pass could only obtain by having a review lane mutate the tree
under test and running a three-minute live gate. **Adopt the harness**, so the gate script's console
decision is a fixture rather than a three-minute non-hermetic ordeal.

And then the general form, which is `D-m23-aw` and is this item's own defect one level up:
**nothing keeps the suite's declared blind spots true.** The selftest states in prose what it cannot
reach, one such declaration was measured false this pass, and **a bound that is wrong reads exactly
like one that is right.** The declarations are the last unchecked assertions in the file. Make at
least the reachability claims checkable, or delete the ones you cannot check rather than leaving
prose that reads as measurement.

## Acceptance

1. The marker's emission sites and the routes reaching each are **enumerated**, with the
   enumeration stated and its completeness argued from the code rather than from search effort.
   The verifier's trace — eight emissions, five plus three, five callers — is the floor, not the
   answer.
2. Each of the four instances closes, each watched red before green.
3. The hermetic gate harness is adopted so `mock-fidelity-gate.sh`'s decision is covered, and the
   selftest's false reachability declaration is corrected or removed.
4. `D-m23-ar`'s row states what was measured rather than what was reported.
5. Gates unmoved: A 1 at 132, B 3 with a ledger, selftest 0 at whatever the count becomes, lint 0,
   `make test` 0 twice at 1615/202, reconciler 0 across A–K.

## Scope

The selftest, and `mock-fidelity-gate.sh` only where point 3 requires it. **Do not change the
engine** — byte-identical is the standard this item has held for two passes and it is why the
verifier could attribute everything it measured.

`D-m23-at` … `D-m23-aw` are registered. `D-m23-av` (`rm -rf app/.build` returned `Directory not
empty` with a concurrent writer and the batch continued, so a remedy a note tells operators to run
has no exit check) is real and is not this pass's work.

## Lanes

Run **read-only from `/tmp` against a copy** — the standing rule, and the verifier followed it and
confirmed the worktree carried no mutation at any point. Gemini returned 2,828 B: one break
reproduced, one **refuted by measurement** (moving the obituary emit into a `finally` is caught by
case 51), and one design disagreement the engine documents. Codex down to 27 August; grok has failed
repeatedly.
