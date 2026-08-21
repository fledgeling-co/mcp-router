# M23 gap-fix 7 — the enumeration's sixth row is false, and the engine says so

**Parent:** M23 · **Verdict:** Needs More Work, 2026-08-21, rung `effect-witness`
**Worktree:** `.worktrees/M23`, branch `ai/m23`, base `d6861e9`

## What holds

Engine and gate script byte-identical to `17e90e8`; the pass touched the selftest, two ledgers and
one evidence file. **All eleven arms reproduce exactly** — every ok-count and every red set. **The
trace reproduces on every load-bearing number**, re-taken by the verifier with its own
`sitecustomize.py`, engine unedited and sha-verified after. **The zero-coverage claim is true**:
per-line tracing shows the pre-pass suite invoked the gate script exactly once and every line of
128–141 had zero coverage, which is why two lanes independently exploited it. Selftest 0 twice at
67; lint 0; gate A exit 1 at 132 with the ledger sha identical either side.

## BL-1 — R5 is reachable with a report path

The table's sixth row says `R5 — unreachable with a report path`, argued: *with `--report` given,
`gate()` either returns 3 from R1–R4 without raising, or reaches the report block, after which
`run.report_written` is true before anything downstream can raise.*

**The disjunction is sound about `gate()`'s interior and silent about `main()`**, which runs
`sys.stdout.flush()` *after* `gate()` returns and before `return code`. On the shipped engine, no
mutation, deterministic 3/3:

```
python3 scripts/acceptance/mock_fidelity.py <missing-manifest> <dumps> --report LED > >(:) 2>ERR
```

`gate()` returns 3 from R1 having written the obituary and emitted the marker. `main()` then
flushes a stdout whose reader is gone, `BrokenPipeError` escapes into the handler with
`run.report_written` False and `run.report_path` set, and **R5 executes with a real path** — the
obituary written a second time, the marker emitted a second time. The ledger a reader opens then
says `gate: BrokenPipeError` where the first write said `manifest: no artifact at …`: **the true
cause replaced by a downstream symptom, in the artifact whose subject is honest reporting.**

`PYTHONUNBUFFERED=1` does not fire it — the same buffering discriminator case 44 already
documents, on a fixture case 44 already builds and has only ever pointed at the success route.

**The engine's own comment above that line reads:** *"The last thing that can raise, and it raises
after every boundary inside `gate()` has been left."* The completeness argument was derived from
this file and did not read it.

Narrowness, stated: through `mock-fidelity-gate.sh` stdout goes to `tee`, which holds the pipe
open, so `make mock-fidelity` cannot reach this. The defect is in the claim and in direct
invocations.

**Why it blocks**: this pass exists because five passes each armed the marker on the routes they
knew about. Its brief asked for an enumeration whose completeness is *argued from the code rather
than from search effort*. One of six rows is argued from the code and the argument is wrong, with a
counter-example needing no mutation — the same failure one level up, one assertion from closed on a
fixture that already exists.

## Acceptance

1. Case 44's existing fixture drives the R5 route: assert the ledger names the **original** cause,
   not `BrokenPipeError`, and that the marker is emitted once rather than twice. Red before green.
2. The route table's sixth row states what was measured. If R5 is now reachable, it owns a case.
3. `D-m23-ba`: case 60's enumeration is evadable three ways, **all of them a new emitter** — a
   split-literal concatenation byte-identical to the constant, `globals()["REPORT_MARKER"]` (absent
   from the escape list), and a sibling module, each leaving all 67 green. What case 60 does catch
   was measured: a third `emit` site, a local alias, and the dropped `run.report_path` store, each
   redding case 60 alone. The engine today contains none of the dynamic-access spellings and imports
   only stdlib, **so the enumeration is sound now and it is the guard that is one-directional**.
   Widen the escape list, derive the spelling count from the AST's string constants with implicit
   concatenation and `BinOp` folding, and assert the engine imports nothing outside stdlib.

## Three numbers of ours that are wrong, and one gate nobody can run

- **`D-m23-bb`: "five of the eleven arms were invisible to the shipped suite" is nine.** Against the
  pre-pass 59-case suite, a1–a5 and a8–a11 all ran 59 ok with 0 FAIL; only a6 and a7 were visible.
  **The evidence file's own table says exactly this** — five rows reading "all 59 green" plus four
  reading "invisible" — so the summary sentence, the ORCHESTRATOR row and the LEDGER row contradict
  the table beneath them. The error **understates** the pass.
- **`D-m23-bc`: "145 engine runs" counts every `python3` process.** 145 total, of which 52 are the
  engine plus one `python3 -c`; the engine ran **53** times, 10 with `--report`. Every emission
  figure the conclusion rests on is right; only the population is over-counted 2.7×. `D-m23-az`
  repeats it, and that row is the orchestrator's.
- **`D-m23-bd`: gate B is in every brief's standing gate list and its recipe exists nowhere.** Named
  once at `M23-gapfix-2.md:121` and carried forward as "B 3 with a ledger written" through four
  briefs with no surface, command or fixture recorded. The verifier constructed an equivalent and
  says plainly that is not the same as reproducing it. **Record the recipe or stop listing the
  gate** — a gate in a standing list that nobody can run is a claim, not a check.

Correct all four in the same pass that closes BL-1; three of them are ours rather than the runner's.

## Scope

The selftest, and the route table's wording. **Do not change the engine** — byte-identical is the
standard that lets a verifier attribute what it measures, and it has held for three passes.
`D-m23-be` (a `make test` red at `OAuthWireTests.swift:263`, a cancellation-timing test under
another session's concurrent builds — G3's class) and `D-m23-bf` (the selftest's `# NN` labels are
names, not execution ordinals, so label 60 is the 50th case to run and every verifier of this item
has had to reconstruct the ordering by hand) are registered and not this pass's work.

## Lanes

Read-only, from `/tmp`, against a copy. Both lanes independently found two of `D-m23-ba`'s three
evasions and no fourth class. Codex down to 27 August; grok has failed repeatedly. Ask each to
**break** rather than review.
