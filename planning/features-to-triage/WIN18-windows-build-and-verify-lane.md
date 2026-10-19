---
status: completed
found-by: intake, measuring the repo's gate spine on Windows while scoping the parity work · 2026-08-30
registry-target: none
no-target-reason: the registry has since gained SURF-029 (WIN20's automation probe) and the windows-glass lane, so the original reason - that every lane runs under xcodebuild - is no longer true. It is still true that no requirement, case or surface records the Windows BUILD AND GATE SPINE itself; DEF-074's evidence names scripts/windows harness scripts in passing while being a defect about lifecycle, which is a mention and not a subject. Corrected 2026-09-03, we4.
---
# Windows work has no gate spine — every verification target in this repo runs under xcodebuild

- origin: intake, 2026-08-30, measured on this machine while scoping the Windows parity work
- audience: every Windows brief, none of which can be verified or merged without this
- platforms: windows, harness

## What and why

The repo's verification is `make`. Measured on this Windows machine on 2026-08-30: `make`, `swift`,
`swiftlint`, `swiftformat` and `xcodebuild` are all absent, and every verification target —
`lint`, `build`, `build-mac`, `build-ios`, `test`, `test-ios`, `test-ios-glass`, `parity`,
`mock-fidelity`, `acceptance` — resolves to `xcodebuild` against `app/MCPRouter.xcodeproj`. None can
run here, and none ever will: the macOS and iOS targets cannot be built on Windows at all.

The `lint` target has roughly forty members. About twenty-four are `python3 planning/*.py` and are
in principle portable. Fifteen were run here: five exit 0 and the rest fail on Windows-specific
causes rather than on findings — `WinError 2` where a gate shells out to a `.sh` member,
`WinError 216` where it invokes something not executable on Windows, `UnicodeEncodeError` under the
console's cp1252 codepage, and backslash path separators. Their own words for these outcomes are
`CONTROL FAILED`, `NOT A PASS` and `NO VERDICT` — which is correct behaviour and exactly the point:
they refuse to report a pass they did not measure.

The consequence is structural. **ship-fleet gates each item on `make lint && make test` before it
merges.** On Windows that gate cannot go green, so either no Windows item can ever merge, or the
gate gets bypassed — and bypassing it would manufacture the false green this repo's whole gate
design exists to prevent. Every other Windows brief is blocked behind this one in practice, even
where it is not blocked in principle.

This is not a request to weaken any gate. The macOS lane keeps everything it has. What is missing is
a Windows lane that can say something true about Windows work.

## Lane contract — the path and the exit code the fleet gates on

Added 2026-08-30 by the conductor, because the goal harness gates this run on the lane and the
runner was originally never told which path it checks. A correct lane landing at an unexpected
path would have left that gate red for the rest of the run — the gate deadlocking the very item
it exists to wait for.

**Canonical entry point:** `scripts/windows/verify.ps1`

- Exit **0** means: everything this lane can check on Windows passed.
- Exit **non-zero** means: something it can check failed. Print which.
- It must run from the repository root and take no required arguments.
- A gate it cannot run on Windows is printed as **NOT-RUN with the reason** and does **not**
  contribute to the exit code as a pass. A not-run gate must be visible in the output.
- It must print, at the end, the list of macOS guarantees it does **not** cover — so a green
  Windows run is never mistaken for a green repository.

`.sh`, `.py`, `.cmd` and `.bat` at that path are accepted too, and the gate also discovers
`scripts/verify-windows.*`, `scripts/windows/*lane*`, `scripts/verify.win.*` and
`planning/goals/win-lane.*`. Prefer the canonical path; the rest are a safety net rather than an
invitation.

Verify with `python3 planning/goals/win-gates.py lane`, which is the exact check the fleet runs.

## Acceptance sketch

- A Windows verification entry point exists that a runner can invoke, and it does not require `make`, since `make` is not present on Windows.
- It builds the Windows client and the TypeScript router, and runs whatever tests each has.
- The portable Python gates run on Windows and pass or fail on findings rather than on encoding, path separators or missing shells. Where a gate genuinely cannot apply on Windows, it says so explicitly rather than erroring.
- A gate that cannot run on Windows is reported as not-run, never as passed — the existing `NOT A PASS` and `NO VERDICT` behaviour is preserved rather than smoothed over.
- The lane states plainly which macOS guarantees it does *not* cover, so a green Windows run is never mistaken for a green repo.
- No existing macOS gate, baseline or ratchet is weakened, and no ratchet is raised to absorb a Windows gap.
- ship-fleet can gate a Windows item on this lane and merge on its exit code.

## Assumptions made writing this

- Assuming the Windows lane is a sibling of the Makefile rather than a rewrite of it, since the Makefile encodes real macOS knowledge that should not be disturbed.
- Assuming the portable gates are fixed for genuine cross-platform correctness rather than given Windows-only escape hatches, because an escape hatch is the cheapest class and would spread.
- Assuming CI is out of scope here; this is about a lane a runner on a Windows machine can invoke.
- Assuming the fifteen gates sampled are representative of the twenty-four; the remaining nine were not run.
