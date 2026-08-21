# M23 gap-fix 4 — one arm, on the closure this pass shipped

**Parent:** M23 — The mock-to-SwiftUI conversion contract
**Status:** Untriaged · gap-fix, fourth pass
**Verdict that produced it:** Needs More Work, 2026-08-21, rung `effect-witness`
**Worktree:** `.worktrees/M23`, branch `ai/m23`, base `668c0f8`

## Read this first: everything held except one arm

This is not a fourth instance of the mechanism that produced the first three verdicts. The
method change worked. The verifier measured every property rather than reading it:

- **BL-1's partition holds within `main()`.** `run = Run()` is the only statement before the
  `try` and assigns three constants; the handler and its final flush are both wrapped. Both
  named routes reproduce at exit 3, and so do two of the verifier's own — stdout closed with
  `>&-`, and both descriptors closed.
- **BL-2's enumeration is complete today, measured not read.** Exactly four `.pairs` attribute
  reads, all four inside the allowlist, none outside a function body, and none of `getattr(`,
  `vars(`, `__dict__`, `attrgetter`, `__getattribute__`, `locals(`, `globals(` present.
  Reverting `layer_copy` to `ctx.pairs` gives exactly 20 paired strings, 16 findings, 132 total
  — the runner's numbers, independently reproduced.
- **BL-3 checks out across all eight layers.** The axis-stripped dump exits 3 naming
  `structure`.
- **The panel refusal was demonstrated, not accepted**: building `claims` from `pairs.items()`
  turns case 34's fixture from exit 1 with the collision finding into exit 0 `present 5 · clean`
  — the duplicate-id defect reopening exactly as the runner argued.
- Gate A exit 1 at 132 findings from freshly rendered dumps, ledger byte-identical; selftest 59
  cases exit 0 twice; lint 0; `make test` 1603/200; reconciler 0 across A–J. 4,174
  Default_Ignorable codepoints re-derived, 0 survive.

Settled at `effect-witness`: the MEASURE product was built, `MeasureDump` opened real windows
and wrote four dumps totalling 73 nodes, the engine ran as a separate OS process, and for the
`D-m23-y` test the ledger path was made a directory so no write could occur — the gate printed
`mock-fidelity-gate: no ledger was written by this run (exit 3)` and the filesystem was read
back from outside the process.

## The one blocking finding

**Case 51 does not arm the mechanism that closes `D-m23-y`.**

The case is named *"the engine claims a written report only when it wrote one"*. Move
`emit(REPORT_MARKER + report_path)` from after `write_report` to before it, and both of its
assertions still pass — and so do the other 58. The selftest reports 59 cases and all three
exits observed.

Measured on an isolated copy: with the emit moved, a run whose report write raises prints
`mock-fidelity: report written to <path>` once and exits 3; the shipped engine prints it zero
times on the same input. `mock-fidelity-gate.sh` greps for exactly that string to decide
whether to say `ledger written to`, so that one reordering restores `D-m23-y` — the sentence
naming the artifact printed over an earlier run's table — **with the gate fully green**.

Why it cannot discriminate, which is the part that matters: the case's first invocation points
`--report` at a writable path, where the write succeeds whichever side of it the marker sits
on; the second passes no `--report`, so `if report_path:` is false and the marker is
unreachable either way. **The only configuration in which the two orderings differ is a
`--report` path whose write fails, and no case drives it.** Case 33 raises inside
`measuring("context")` and returns 3 before the report block ever runs.

Case 33 already builds a `chmod 500` directory. **The missing arm is a third invocation of a
fixture that already exists.**

The behaviour is correct and was witnessed on the live gate. What fails is the check written to
keep it correct — which is the thing this item exists to prevent, and it is the second instance
in this pass of the defect the runner reported against itself.

## Acceptance

1. Moving `emit(REPORT_MARKER + …)` before `write_report` turns case 51 red. Watch it fail,
   then restore.
2. The case drives a `--report` path whose write fails — the third invocation of case 33's
   existing `chmod 500` fixture — and asserts the marker is absent while the exit is 3.
3. `D-m23-ag`: cases 44 and 50 assert only the exit code, so BL-1's report-ordering half is
   unarmed on the broken-pipe route. Case 43 already asserts both halves for the unencodable
   console. Arm 44 or 50 the same way, or state why one route's arming covers the other.
4. `D-m23-ah`: case 48's second want reads the exclusion rather than the comparison count, so
   it survives the mutation the case is named for. Its first want does pin both numbers and
   does go red, so the case is armed by one of its two assertions — make the second read the
   quantity its name claims, or delete it.
5. **A sweep for the same shape across the other 56 cases.** Three have now been found: the
   runner's own, case 51, and case 48's second want. State how you searched rather than
   asserting the rest are clean — the shape is *an assertion satisfied by something that
   survives the mutation*, and it has appeared three times in two passes.
6. `D-m23-y`'s register row still reads as open; apply the closure mark. `D-m23-aa` stays open
   and `D-m23-x` stays deferred — both correctly reported.

## Scope

The selftest, and `mock-fidelity-gate.sh` only if point 3 requires it. **Do not change the
engine's behaviour** — every property it was bounced for now holds and was witnessed. This is
an arming pass.

`D-m23-ac` … `D-m23-ai` are registered. Take none of them except where points 3 and 4 name
them. In particular `D-m23-ac` and `D-m23-ad` — the AST guard attributing reads only to
functions, and its three-spelling escape list missing four — are real and are **not** this
pass's work: today's engine has exactly four `.pairs` reads and all four are inside the
allowlist, so the enumeration is correct now and it is the guard that does not generalise.

## One operational fact that changed

**The codex lane is down until 27 August** — usage limit, reported by this verification. It is
the default out-of-family lane in every brief in this repo. Substitute the Google family first
and then xAI, and keep any grok packet small: grok is **packet-size limited, not down**, having
returned 1,051 bytes at exit 0 for a 1,174-byte prompt after returning nothing at 16.5 KB and
64 KB.

The Google lane earned its place on this verification: it named two evasion families the
verifier had not found, and one factual error the verifier refuted by measurement — it claimed
`async def` evades the AST walk, and the walk checks `AsyncFunctionDef`, so an async reader
goes red. Its first answer was also a hallucination about a decorator that is not on `main()`.
Both facts belong in the record: the lane is worth running and its output is worth checking.
