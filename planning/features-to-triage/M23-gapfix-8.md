# M23 gap-fix 8 — one grep, in the file the last pass was raised to fix

**Parent:** M23 · **Verdict:** Needs More Work, 2026-08-21, rung `effect-witness`
**Worktree:** `.worktrees/M23`, branch `ai/m23`, base `cf7e5fc`

## What holds — do not redo any of it

**The engine change was the right call and the verifier established both horns itself** rather than
taking the disclosure: R5 reproduces 3/3 on the unmutated shipped engine from *outside* the suite,
driven only by argv and the state of fd 1, so nothing a selftest can write reaches it and the
brief's two instructions genuinely could not both be met.

**A 19-shape differential proves nothing else moved.** Across no-args, usage, missing manifest with
and without `--report`, missing dumps, dangling `--report`, report-is-a-directory, an unencodable
console, an unwritable ledger, unbuffered, stderr-dead and both-dead: exit code, stdout, stderr and
ledger are byte-identical between the two engine shas. Only the broken-stdout routes differ, and
exit stays 3 on every one. Both of the lane breaks that killed the first patch shape are dead
against the shape that shipped.

Case 68 red first at 67 ok alone and green after, twice. Gate B's recipe ran verbatim. Nine
evasions red. The seven-character bound is real **and shortest** — 6 collides on `'report'`, 4 on
`'mock'`. Gates all reproduce; `make test` is 1619/204 and lint 521 files because the merge brought
G3's tests, which is the merge and not a defect.

## BL-1 — the correction is applied in one of three places in its own file

`mock-fidelity-selftest.sh:1224` now says, correctly, that *"145 engine runs" was this file's own
wording for that trace and it is wrong: 145 is every python3 process the suite starts … and the
engine is 52 of them.*

The same file still says at **line 481** *a trace of the whole suite recorded 145 engine runs, 10 of
them with `--report`*, and at **line 1434** *a trace of the two emission lines across all 145 engine
processes the suite starts recorded zero hits here.* Both are false on the verifier's own trace.

The brief said correct all four in the same pass, and a `grep 145` over the one file in scope finds
all three sites. **This is `D-m23-bb`'s own defect — one fact under two wordings, the summary
contradicting the table — committed by the pass raised to fix it.** That is why the verifier called
it rather than filing it, and it is the whole of this pass.

## Also correct, since you are in the file

- **`D-m23-bk`: `D-m23-bc`'s diagnosis mis-names the over-counted process.** There is no `python3
  -c` in that suite. The 53rd is a `python3 -` stdin heredoc whose argv carries the engine path, so
  counting lines that *mention* the engine gives 53 while `argv[0]` gives 52. **The number 52 is
  right and the reason recorded for 53 is not** — this is the third correction to that one figure's
  reasoning, so state what was measured and how, not just the value.
- **`D-m23-bl`: `ORCHESTRATOR.md`'s `D-m23-bc` row still reads 53** after the union merge. It is
  main's row and the branch never saw it, so no runner could have corrected it in place — the same
  situation `D-m23-az` records for itself. Correct it here.
- **`D-m23-bm`: "six lines in `main()`" is 5 statements over 8 physical code lines**, plus 15
  comment and 2 re-indented, 25 added and 2 removed in one hunk, in a commit shared with the
  206-line selftest change. Understated rather than inflated, and worth restating accurately in the
  ledger rows that repeat it.

## Not this pass's work

`D-m23-bh` — the stated residual is narrower than the class that evades case 60: a single constant
that is not a substring of the marker, repaired at run time, evades every check and emits a real
second marker (`.replace`, `.lower`, reversal, `bytes.fromhex`, a Caesar shift). **Not blocking, and
the reason is on the record**: the file carries an explicit general concession that it cannot
enumerate every run-time assembly, both out-of-family lanes independently argued the same, and both
broke two of the verifier's own seven counter-examples. `D-m23-bi` (the R5 row names a case that
asserts the route is *not* entered — terse rather than false, and the prose below is explicit) and
`D-m23-bj` (the fix drops a true sentence and the traceback on the report-written route, while the
marker still reaches stderr) are registered and deferred.

## Acceptance

1. `grep -n 145 scripts/acceptance/mock-fidelity-selftest.sh` returns only statements that are true
   on the trace, or none.
2. The three corrections above land, each stating the measurement rather than the value alone.
3. Gates unmoved: A exit 1 at 132 with the ledger sha unchanged, B exit 3, selftest 0 twice at 68,
   lint 0, `make test` 0 twice at 1619/204, reconciler 0 across A–K.

## Scope

`mock-fidelity-selftest.sh` and register rows. **Do not change the engine again** — its change is
verified, bounded and attributable, and a second one would cost that.

Lanes read-only from `/tmp` against a copy. Codex down to 27 August; gemini's headless runs have
been auto-denied a tool permission twice, so send its packet inline; grok has failed repeatedly.
