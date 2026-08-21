# M23 gap-fix 5 — one grep, on the fixture that already exists

**Parent:** M23 — The mock-to-SwiftUI conversion contract
**Status:** Untriaged · gap-fix, fifth pass
**Verdict that produced it:** Needs More Work, 2026-08-21, rung `effect-witness`
**Worktree:** `.worktrees/M23`, branch `ai/m23`, base `ec9e215`

## Read this first

The fourth pass's work is **sound and was re-measured in full**. All 20 hand-written cases
discriminate — the verifier mutated for each rather than reading them. Case 51's arm reproduces
exactly: marker moved before `write_report` gives exit 1, 58 ok, **one FAIL, case 51 alone**,
restored byte-identical. Pass A's validation claim was independently re-derived: the pre-arm
coverage union never executes the report block's `except Inconclusive` arm, the post-arm does, and
those four lines are the *only* difference in either direction — the arm reached exactly the branch
nothing reached. Scope was respected exactly: the selftest and `ORCHESTRATOR.md` only, engine and
gate script byte-identical to the branch base.

**And the declared blind spot was honest.** The pass said the nine hand-written blocks were where
its mechanical sweep could not see. The verifier confirmed the bound was accurate — and then found
the blocker inside it. Its words: *"The disclosure was the finding."* That is the pass working, not
failing, and this brief is one assertion long because of it.

## BL-1 — the marker's delivery is unarmed, and the gate then denies its own ledger

Move `emit(REPORT_MARKER + report_path)` out of the report block to just before `if blocked:`,
after the whole console loop, guarded by `if report_path and run.report_written:`. Change nothing
else. Measured: **selftest exit 0, 59 cases, all three exits observed — zero cases move.**

Driven against case 43's own fixture (clean scratch root, `PYTHONIOENCODING=ascii`, `--report` at a
writable path), engine run as a separate process and the ledger read back from the filesystem:

- exit 3, and `write_report` **succeeded** — the file on disk carries this run's table, with the
  planted `STALE-FROM-AN-EARLIER-RUN` gone;
- the marker appears on **neither** stream;
- so `mock-fidelity-gate.sh`'s literal grep fails and the gate prints **`NO ledger was written by
  this run (exit 3)`** — over this run's real table.

The shipped engine on identical input puts the marker on line 1 and the gate says `ledger written
to <path>`.

**Why the suite cannot see it.** Case 51's three invocations are writable-and-healthy (the loop
never raises, so the marker lands either way), no-`--report` (unreachable either way), and
unwritable (returns from `except Inconclusive` before the loop). Cases 43 and 44 assert exit and
ledger content and say nothing about the marker. So the suite pins the marker's presence on success
and its absence on a failed write, and pins **nothing** about its delivery when a *later* print
raises — which is the one property the engine's own docstring claims for it: *"a console that
cannot encode the report still delivers it on stderr."*

**The fix is one grep on a fixture that already exists**: add
`grep -qF "mock-fidelity: report written to $LEDGER43" <<<"$out43"` to case 43's conjunction.

**The counter-weight, which the verifier stated rather than buried.** This is the *under*-claim
direction, and the engine calls under-claiming "the safe direction". But that allowance is scoped to
both streams being gone; here stderr is available and the marker still vanishes, so what breaks is
the docstring's stated fallback property rather than a tolerated direction. Blocking because it is
the same mechanism, the same class, and the same one-assertion distance as the finding the fourth
verdict bounced this item for.

Found by asking the Google lane to **break** rather than review — it named the deferred-marker
family, though its concrete placement was inert (it put the `emit` before the line that raises).
Moving it to the placement its own reasoning described is the break.

## Acceptance

1. The mutation above turns case 43 red. Watch it fail, then restore.
2. `D-m23-aj`: case 48's fifth conjunct sits in an `&&` chain whose preceding conjuncts pin
   comparisons, census and excluded as string equalities, so it is reachable only when it reduces to
   `3 = 3` and short-circuits before it whenever a value differs. Measured under both of the case's
   own mutations: the literals caught each and the conjunct was **never evaluated**. The case is
   armed; the identity is decorative. Make it load-bearing or remove it — a conjunct that cannot
   discriminate is this item's defect in miniature.
3. `D-m23-an`: **the register is now false about the tree.** `D-m23-ag` says cases 44 and 50 pass no
   `--report` and that reverting the write-before-print ordering leaves them green. Case 44 now
   passes `--report`, asserts both ledgers, and goes red under that revert alongside 43 — measured.
   The row arrived on main after this branch's base, so no runner could have marked it. Correct it
   and `D-m23-ah` at merge.
4. Gates unmoved: A exit 1 at 132 findings with the ledger unmoved, B exit 3 with a ledger written,
   selftest 0 at 59 twice, lint 0, `make test` 0 twice (now **1615/202** — the merge brought R14 and
   R15's tests), reconciler 0 across A–K.

## Scope

`mock-fidelity-selftest.sh`, and this item's briefs and register rows. **Do not change the engine.**
Its behaviour is correct and was witnessed at `effect-witness` — the ledger read back off the
filesystem by a separate process.

`D-m23-ak` (the sweep's five passes are preserved as outputs, not as code, so the conclusions cannot
be re-derived without rebuilding the instrument — the coverage half was re-derived independently and
agrees exactly), `D-m23-al` (573/72 holds under an AST statement walk skipping `except` handlers;
coverage.py gives 629/82 and the ten-statement gap is entirely unreached `except` arms, so the
published figure under-reports unexercised error handling), `D-m23-am` (the subprocess-timeout
handler is the largest contiguous never-executed region and no case makes a shelled-out tool time
out) and `D-m23-ao` are registered and are **not** this pass's work.

## Lanes

Codex is down until 27 August. The Google lane found BL-1's family by being asked to break the
artifact; grok was not run and has failed repeatedly this session. Ask each lane to break rather
than review — that phrasing has now produced the blocking finding on two consecutive passes of this
item.
