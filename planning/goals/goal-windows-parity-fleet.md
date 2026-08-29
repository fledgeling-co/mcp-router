# Goal — Windows feature and UI parity with the macOS client

**Slug:** `windows-parity-fleet` · armed 2026-08-30 · repo `C:\Dev\mcp-router` (Windows 11)

## Objective

Drive the 23 `WIN*` items to merged and verified on local `main`, running
`ship-fleet:ship-fleet` per wave. The mock HTML decides *what* is on a surface; Windows 11 Fluent
decides *how* it is drawn.

## Finish line

All three must hold. Nothing else counts as finished.

1. Every one of the 23 `WIN*` rows in `ORCHESTRATOR.md` reads **Done** (verified and merged to
   local `main`) or **Parked** with a written reason. "Dispatched" and "the runner returned" are
   not Done.
2. The Windows verification lane from WIN18 exists and exits 0 on `main`.
3. No ratchet or baseline was raised or waived to absorb a Windows gap.

## Worklist — 23 items, five waves

Wave order is the dependency graph and is not negotiable. **An item never starts before its
dependencies have merged, not merely finished.**

| Wave | Items | Gate on entry |
|---|---|---|
| W0 | WIN1 | Done — WinUI 3 chosen, probes recorded |
| W1 | WIN2, WIN17, WIN18 | nothing blocks these |
| W2 | WIN3, WIN20 | W1 merged |
| W3 | WIN4–WIN11, WIN13–WIN16 | WIN3 + WIN2 merged |
| W4 | WIN19, WIN21, WIN22, WIN23 | their named surface merged |

WIN18 is the highest-value item in the run: until it lands nothing else can be gated at all.

## Gates

| Name | Command | Question |
|---|---|---|
| `briefs` | `python3 planning/brief-target-gate.py` | do the briefs still declare targets, with `BROKEN_TARGET` at 0? |
| `ledger` | `python3 planning/goals/win-gates.py ledger` | are all 23 rows terminal? |
| `lane` | `python3 planning/goals/win-gates.py lane` | does WIN18's Windows lane exist and pass? |
| `branches` | `python3 planning/goals/win-gates.py branches` | is anything built but unmerged? |
| `liveness` | `python3 planning/goals/win-gates.py liveness` | is this run actually moving? |

`make lint` and `make test` are **deliberately absent** from that list. Every verification target
in the Makefile shells out to `xcodebuild`, and `make`, `swift`, `swiftlint`, `swiftformat` and
`xcodebuild` are all missing on this machine. A gate that shells to an uninstalled binary reports
the machine rather than the work, and reporting one green here would be a lie.

## Blocked-item policy

Park, with the reason written into the row — never silently skip, and never mark `n/a` something
that could have been reached. An item blocked on a decision goes to the owner as a decision, and
the fleet moves to the next ready item rather than stalling.

## What cannot be verified on this machine

Recorded here so no turn reports it as clean:

- **Cross-family verification is unavailable.** `codex`, `agy` and `grok` are not installed on
  Windows, and the `claude` CLI returns *"your organization has disabled Claude subscription
  access"*. Per item this is recorded **not-run**, never as a pass.
- **Campaign reconciliation cannot be completed.** `campaign.py check`, `strict-check.py` and
  `reckon` measure a macOS application that cannot be built or launched here. So ship-fleet's
  usual Phase 6 exit condition is unreachable on this machine. It is **owed to the Mac**, and this
  run finishes on the three criteria above instead.
- **Nothing Swift can be built.** The 16 Swift files on `ai/p4` (R26, the Mac fleet's unmerged
  item) stay unmerged from here; merging them unverified would break the repo's own rule that the
  compiler is the only thing that catches a union-resolved comma loss.

## Resources and bounds

- **Concurrency: 5 runner agents maximum.** A measured correctness limit, not a throughput
  preference — beyond it agents die silently at 180.0s with no error row anywhere.
- Failure is derived from *(agents started − agents returned)*, never from an error field: error
  counts read clean precisely when the harness killed the agent.
- `main` refuses direct commits; branch and merge. **Do not push** — the pre-push hook refuses and
  no standing permission exists.
- Never `git add -A`. A killed gate strands its mutation in the tree and `-A` adopts it.
- Wrapper exit codes lie here: `winget` exited 0 over a failed installer, `setup.exe modify`
  exited 0 over `Exit Code: 87`. Judge an install by an artifact on disk.
- Build lane: Visual Studio's `MSBuild.exe` (`-t:Restore,Build`) succeeds; `dotnet build` fails
  with `MSB4062`. They do not converge by installing more Visual Studio.
- Set `PYTHONIOENCODING=utf-8` before any repo Python gate or it dies under cp1252.

## Stop conditions

- All three finish-line criteria hold → done.
- 80 iterations, or the deadline, whichever first.
- The same failing fingerprint three times → escalate once, then disarm with the wall named.

## Cost rule

A wake must carry new information. Do not re-send an unchanged failing set; withhold a gate's
output when the failing set has not moved. The ledger at
`planning/goals/ledger-windows-parity-fleet.jsonl` answers "is it still going" without
interrupting the run.
