# R33 — acceptance evidence

Branch `ai/r33`. All figures below were produced by the commands named, at `9e49397` unless the
row says otherwise, and the captured output is in `planning/evidence/R33/`.

## Gates

| Gate | Command | Exit | Log |
|---|---|---|---|
| whole lint, 27 members | `make lint` | **0** | `planning/evidence/R33/make-lint-summary.txt` |
| swiftlint, inside lint | — | 0 violations, 0 serious in **708** files | same log |
| carrier parity | `python3 planning/carrier-parity-gate.py` | **0** | `carrier-parity-gate.txt` |
| carrier parity, armed | `bash scripts/acceptance/carrier-parity-selftest.sh` | **0**, 8 arms | `carrier-parity-selftest.txt` |
| green streak, armed | `bash scripts/acceptance/green-streak-selftest.sh` | **0**, 10 arms | `green-streak-selftest.txt` |
| green streak, read | `make green-streak` | **2**, and 2 is the correct answer | `green-streak.txt` |
| carrier census | `bash scripts/acceptance/carrier-census.sh` | **0**, 42 landings | `carrier-census.txt` |
| surface census | `bash scripts/acceptance/surface-census.sh` | **0**, `total 105` | `surface-census.txt` |
| sweep control | `python3 planning/sweep-control-gate.py` | **0** — 104 discovered, all disposed, 30 controls run | in `make lint` |
| reader accounting | `python3 planning/reader-accounting.py` | **0** — 19 record, 39 declare, 2 recorded gaps | in `make lint` |

`make green-streak` exiting **2** is the deliverable rather than a failure: no whole-gate run has
ever been recorded, so the streak is *unmeasured* rather than zero, and the script says which of
those two it is. That is why it is out of `lint` and out of `all` — putting it in would make the
honest state a red build, and the pressure would land on the instrument rather than on the runs.

## Why the lint capture is a summary

`make lint` prints 1467 lines and 32 of them carry a bare `path:line` out of the gates' own
findings text. `citation-gate.py` blocks a newly tracked file holding bare citations above a
baseline of zero, so **committing the raw capture turns a green lint red on the act of recording
it** — the gate is right, and the log is not the place to fix it. The committed file is the
per-member verdict lines, with the producing command written into its own header and the run's own
exit code recorded at capture. `planning/evidence/R30/make-lint-summary.txt` is the same shape for
the same reason.

## `make test` was not run, and the reason is measurable

`git diff --stat main...HEAD -- app/Sources app/Tests src` is **empty**. No compiled source
changed; the diff is 8 new files under `planning/` and `scripts/`, three registry rows and a
Makefile target. The standard is the one ORCHESTRATOR.md already applies to `M6` — *"M6's diff
over RouterCore, MCPRouterCLI and src/ is empty, verified rather than taken on report."*

## Against the acceptance sketch, clause by clause

**1. "The current parity figure reported against the 82-of-83 target, derived rather than quoted."**
**Cannot be met as written, and saying so precisely is the delivery.**
`planning/parity/cutover-readiness.md` §1–2. The census is **105** rows and the target of **82** was
decided against **83**, so `target_derived` is **104**, the gate finds the pin and the census
disagree, and it withholds the distance on purpose. There is no 83 to be 82 of. No numerator is
invented, `PARITY_CUTOVER_TARGET` is not re-pinned, and `surface.tsv` is untouched — the 22-row
growth is an owner decision and `REQ-020` reserves the cutover to them.

Two things are separated there that are easy to blend. The manifest records **92 `proven` + 12
`proven-by-suite` = 104 of 105**, with the one blocked row being the standing exclusion itself —
but that is a statement about the manifest, not about the two routers agreeing today. **No
whole-gate run was taken**: this worktree has no `node_modules` (linked at preflight), no
`dist/index.js` until the build for lint, and no Swift build, so a run would have exited 2, and an
exit 2 is not a parity figure.

**2. "The green-streak condition given a definition somebody can check."** Done —
`planning/parity/green-streak.md`. A whole-gate pass is one `parity-gate.sh` invocation over all
sixteen lanes that exits 0 or 1 and **never 2**, reports 0 DIVERGED, reports no blocked row beyond
the standing exclusions, and reports `proven` at or above `PARITY_CUTOVER_TARGET`. Exit 0 is
unreachable by construction and the definition is written knowing it.

The cold port-reuse path is defined from what the lanes do rather than from the phrase: every lane
binds a **fixed** port (`8957`–`8959`, `8961`–`8969`, `8992`–`8998`), so a cold port-reuse run is
one begun within 60 seconds of the previous run's exit, in a scratch `HOME` carrying nothing from
it. That definition is proposed and marked as proposed.

**The bound is left `unset`.** `R4-C1` requires the number stated *before* the runs it is judged on,
so a script choosing one afterwards would be picking the formulation that makes the answer green.

**3. "A reader can see, per merged item, which router carries it and whether it is reachable."**
Done — `cutover-readiness.md` §3, and the gate prints the same table on every run. Reachability is
derived, not asserted: `MCPR_ROUTER="${MCPR_ROUTER:-swift}"`, `docs/install.sh:39` at `83e5380`. A
fresh install selects Swift, so R28, R30, R31 and R32 answer on it and R29 does not. **R33's own
measurement points the other way and both are right** — those launchd agents predate `R4-C1`. What
is installed on a given machine is not a fact this repository holds, and neither the ledger nor the
gate pretends otherwise.

**4. "Something fails when a feature is merged into one implementation and not the other without
that being recorded."** Done and in `make lint` —
`planning/carrier-parity-gate.py` at `64ecf8e328c15e20a62db5d9649f5cfc2b8ef1ab` (historical source). Every landing at or after `afaad59` that touched one
implementation and not the other needs a row in `planning/parity/carriers.tsv` at `64ecf8e328c15e20a62db5d9649f5cfc2b8ef1ab` (historical source) carrying a reason,
and the carrier is **re-measured from the landing's own diff** on every run, so a row that
disagrees with the tree is a finding rather than a record. Five in the window, five dispositioned.
30 one-sided landings before the pin print as a stated backlog with a count, never as a pass.

**5. "No cutover is performed."** Held. Nothing points the installer anywhere, nothing deletes
`src/*.ts`, and the target is not moved.

## Two findings worth carrying

**The re-dispatch brief's line number is off by two.** `target_derived=$((total - excluded))` is at
`scripts/acceptance/parity-gate.sh:402` at `83e5380`, not 404. Corrected in ORCHESTRATOR's R33 row.

**A merge-commit census would have missed R30.** `516be61` carries the subject `Merge ai/r30:
ingest what Claude acquires, copy-verify-remove, reversibly` and has **one parent**. `git log
--merges` does not select it, so the obvious census would have been blind to one of the four items
R33 is about. The walk is first-parent, which also takes the root commit `dc63c60` — the landing
that introduced the TypeScript router, 7 files under `src/`, which the first per-commit form of the
census skipped because a root commit has no `^1`.

## What is not established

- **That a real `parity-gate.sh` run produces the summary shape the recorder parses.** The two
  recorder arms are built from the gate's own format strings, not from a live run.
- **That the cold port-reuse definition is what the owner meant.** It is derived from the fixed
  ports and from `G3`'s measured `listen EADDRINUSE`, and is marked proposed.
- **That the census classifies every landing correctly.** The path sets are hand-written and
  probed — a set matching no tracked file exits 2 as a stale anchor — but there is no independent
  oracle for the classification itself.
- **Anything about the 30 pre-pin one-sided landings** beyond their count.
