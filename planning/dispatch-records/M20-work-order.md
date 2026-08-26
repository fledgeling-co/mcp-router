# Work order — M20

Invoke **`ship-feature`** on M20 and take it as far as the two stop rules allow.

## Stop rules — both are hard

- **Stop before verify.** Run ship-feature through e2e-green, then report *ready to verify*
  and end your turn. A runner cannot verify its own build; the orchestrator spawns a fresh
  verifier.
- **Stop before merge.** Do not merge, rebase onto main, or push. The orchestrator serialises
  every merge.

## Where you are

Worktree `/Users/lukerhodes/Dev/mcp-router/.worktrees/M20`, branch `ai/m20`, cut from `main` at `87e16dc`.

`.claude/plugins/fledgeling-plugins` is a submodule and it is **uninitialised on purpose**. Do
not run `git submodule update --init` — it puts 546 MB of plugin skills where Claude Code loads
them and every runner dispatched into that tree has died on context. Read skills from the
plugin cache instead.

## Read these in full before writing anything

- `planning/features-to-triage/M20-menubar-status-notification.md` — the brief
- `planning/specs/spec-M20.md` — the spec
- `DESIGN.md` — design authority
- `design/mcp-router-console.html` — **the design of record**, settled 2026-08-22. Not
  `design/mocks/prototype.html`, which is the superseded prototype and is cited only for
  surfaces nobody has converted yet.
- `planning/practices/CODING_PRACTICES.md`, `planning/practices/SWIFT_PRACTICES.md`,
  `planning/practices/UI_VERIFICATION.md`

After any compaction, re-read all of them. The artifacts on disk are the memory, not this
prompt.

## Baseline, measured rather than remembered

`main` at `87e16dc`: `make lint` exit 0, swiftlint 0 violations over 549 files;
`ledger-reconcile.py` 0 across A–L; `reader-accounting.py` 0; `null-run-gate.py` 0 with 28
armed and 0 held. The Swift suite last measured **1725 tests in 215 suites** at `29d5111`;
nothing since touches Swift, so re-measure before you rely on it rather than quoting mine.

**Do not wait for `make all`.** It takes 30–40 minutes and two runners have already ended
their turn owing a commit because of it. Commit your work first, then run whichever gates your
change actually needs and amend. The orchestrator runs the whole-repo gate and hands you the
numbers.

## House rules that have cost this repo real time

- **Only test the screen you changed**, and only that screen. One app launch, one pass, quit.
  Do not boot a simulator per screen.
- A surface built from the console mock is converted under `M23`'s five measurement layers, not
  by eye. A screenshot comparison is not evidence.
- No number reaches the UI that the router does not observe. There is no fabricated metric
  anywhere in this product.
- Every dimension routes through `MetricToken` or it reddens
  `scripts/lint/no-raw-design-values.sh`.
- Browser work goes through `obscura` only. Read computed styles through longhands — `padding`
  and `borderRadius` return `0px` where the CSS sets real values, while `paddingTop` and
  friends are correct.

## Triage findings already on file for M20

These came out of triage and are not yours to rediscover:

To Do — triaged 2026-08-22. The app declares six command groups with no Router or Library menu and `⌘1`-`⌘7` over seven destinations; the mock wants nine, which waits on M22 and M15. The accelerator map disagrees three ways and the mock wins, recorded as an assumption. The status item has never been measured — `SURF-009` carries three `n/a` cases on a structural limit — and M23's harness is the route that reaches it. Eight assumptions, no essential question

## Deliver

Commit incrementally on `ai/m20`. Write your progress note to `planning/progress/M20.md`. When
you stop, say in a few lines what landed, what you measured, and anything you could not settle
— a parked item with a reason is worth more than a green nobody checked.
