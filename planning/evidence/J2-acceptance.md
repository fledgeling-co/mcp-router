# J2 — the control census gets a numerator, and four surfaces get a disposition

Brief: `planning/features-to-triage/eleven-surfaces-declare-controls-that-nothing-drives.md`.
Branch `ai/j2`, off `5ceef5d`. Every figure below is pasted from a run; nothing here is asserted by
hand.

## What the brief asked for, and what each clause got

| Acceptance clause | Where it stands |
|---|---|
| Every declared control is driven or carries a stated reason | Done for the three named surfaces and SURF-006, which read **fully disposed**. Seven surfaces still carry undisposed controls and the census prints that count on every run rather than reporting a clean partition |
| The census reports a non-zero actuated count per surface; the three named surfaces move off zero first | **6 → 29 of 141**; SURF-001 0 → 8, SURF-002 0 → 9, SURF-004 0 → 2, SURF-006 0 → 4. Inert surfaces 11 → 7 |
| Driving is proved by reading the state through a channel other than the one that struck | Every one of the nine cases; the channel is named per case in `actuatesNote` and the rejected same-channel read is named beside it |
| Replacing a real handler with an empty closure turns the case red, watched rather than assumed | Nine arms in `bin/arm-suites.py`, each an empty-closure seed on the specific handler |
| A control whose only promised effect is navigation or a message is recorded as that | 81 message-only controls are a class of their own in the census output and are never counted as actuated; three further controls carry `controlsUnactuatable` reasons that say why an absence-read or a missing control cannot be counted |

## 1 · The channel, per case

The census's rule is upstream's: only a **passing** case at an **effect rung** moves the count. The
bar J2 added on top is the one `references/inert-ui.md` states — the observable must be something
the handler was supposed to change, read through a different channel from the one that struck.

| Case | Surface | Controls | Struck | Read back on | The same-channel read that was refused |
|---|---|---|---|---|---|
| CASE-0195 | SURF-001 | the seven destinations + Settings | `ShellModel.select` | the restoration store — a scratch `UserDefaults` suite nothing in the test wrote, and the value a relaunch reads | `model.selection == .servers` — the property the call just wrote |
| CASE-0196 | SURF-002 | All · Running · Idle · Needs you | `board.filter` | the rows `rows(from:)` draws, both directions | `board.filter == .running` after the assignment |
| CASE-0197 | SURF-004 | All · Held | `board.filter` | the skills the board lists, against `held?.wantsMore` | as above |
| CASE-0198 | SURF-006 | All · Not met · Not observed · Unstamped | `board.filter` | the subjects the board lists, against the segment's own predicate | as above |
| CASE-0199 | SURF-002 | Keep warm | `setWarm` | the request bytes the recording client received | the row's own redraw, which happens either way |
| CASE-0200 | SURF-002 | Only load in named projects | `setProjects` | the request bytes, both directions | the picker's return value |
| CASE-0201 | SURF-002 | Reset | `reset` | the operation the client received (`reindex`, not a patch) | the mark clearing on the row |
| CASE-0202 | SURF-002 | Remove | `remove` | the operation the client received, both checkbox positions | the sheet closing and the selection dropping — the app's own report |
| CASE-0203 | SURF-002 | Accept the new text | `approveHeldChange` | the operation the client received | the sheet dismissal |

Three of those refused reads are the acknowledgement-only shape from `references/inert-ui.md` §3,
and CASE-0202's arm demonstrates it rather than describing it: with the write emptied, **the sheet
still closes and the selection still drops**. A case asserting either of those would have stayed
green over a control that told the router nothing.

## 2 · The arms — the empty closure, seeded and watched

`planning/test-campaign/bin/arm-suites.py` plants a named mutation in the **production** source the
case guards, runs that test alone, requires red, restores from bytes held in memory and re-runs to
prove the tree is green again. It classifies build-failure and ran-nothing separately, because
either would otherwise read as a caught defect.

Every J2 mutation is the empty-closure shape rather than an inverted comparison. An inverted filter
still draws a *different* row set, so a case reading "the rows changed" survives it; a handler that
runs and changes nothing is the thing the census is a denominator for.

    $ python3 planning/test-campaign/bin/arm-suites.py CASE-0195 … CASE-0203
    arming 9 of 22 suite-backed cases

      ARMED  CASE-0195  eachSelectionReachesTheStore  mutated=red(1 test(s)) restored=green(1)
      ARMED  CASE-0196  eachServersSegmentFiltersTheTable  mutated=red(1 test(s)) restored=green(1)
      ARMED  CASE-0197  eachSkillsSegmentFiltersTheTable  mutated=red(1 test(s)) restored=green(1)
      ARMED  CASE-0198  eachChecksSegmentFiltersTheTable  mutated=red(1 test(s)) restored=green(1)
      ARMED  CASE-0199  warmSendsOnlyWarm  mutated=red(1 test(s)) restored=green(1)
      ARMED  CASE-0200  projectsSendsAnExplicitArray  mutated=red(1 test(s)) restored=green(1)
      ARMED  CASE-0201  resetReindexesAnIndexFailure  mutated=red(1 test(s)) restored=green(1)
      ARMED  CASE-0202  removeSendsKeepHistory  mutated=red(1 test(s)) restored=green(1)
      ARMED  CASE-0203  approveWritesAndKeepingDoesNot  mutated=red(1 test(s)) restored=green(1)

    armed 9 of 9 attempted · refused 0
    wrote /Volumes/LLMs/Dev/mcp-router/.worktrees/J2/planning/test-campaign/evidence/runs/arm-suites.0195-0203.log

Nine of nine bit. Each `mutated=red` is the case failing under an empty closure and each
`restored=green` is the same test passing again off the bytes held in memory, so the tree is proved
back before the next arm starts. `arm-suites.py` classifies a build failure and a run that executed
zero tests separately from a red, because both would otherwise read as a caught defect.

**A subset run no longer overwrites the full run's record.** Until this change every invocation
wrote `evidence/runs/arm-suites.log`, so the first J2 arming run took that file from
`denominator: 13, armed: 13` to `denominator: 9, armed: 9` — silently, well-formed, with CASE-0008
still citing it. A subset now writes `arm-suites.<span>.log` and the canonical name belongs to the
run that attempted every arm. That was found by doing it, and the clobbered file was restored from
`5ceef5d` before anything else was written.

## 3 · The census, before and after

Before, at `5ceef5d`, read with that tree's own copy of the script:

    Cases:      6 of 114 case(s) name a control they actuate; 108 name none and cannot move any number below
    Controls:   6 of 141 declared control(s) actuated by a passing effect-rung case, across 14 surface(s) that declare any
                86 of the 141 are message-only — the design's whole promised effect is a sheet, a panel or a notification appearing.
                Of the 135 not actuated, 81 are message-only and 54 promise a state change nothing has driven.

      SURF-001   0 of 20 actuated · 12 message-only · 8 driven only by a case below `outcome` or not passing   Mac shell — sidebar, title, menus
      SURF-002   0 of 23 actuated · 11 message-only   Mac Servers board
      SURF-003   3 of  3 actuated · 2 message-only   Mac Activity board
            actuated: Cancel; Reset history; Reset history…
      SURF-004   0 of 21 actuated · 15 message-only   Mac Skills board
      SURF-005   0 of  9 actuated · 3 message-only   Mac Discover board
      SURF-006   0 of  5 actuated · 1 message-only   Mac Checks board
      SURF-007   1 of  9 actuated · 6 message-only   Mac Cleanup board
            actuated: Read first…
      SURF-008   0 of  6 actuated · 4 message-only   Mac Inbox board and review sheet
      SURF-009   0 of  7 actuated · 6 message-only   Mac menu-bar popover and inbox band
      SURF-010   0 of  2 actuated · 1 message-only   Mac Pairing sheet
      SURF-011   0 of 10 actuated · 7 message-only   Mac Settings board
      SURF-025   0 of 11 actuated · 9 message-only   Mac Harnesses board
      SURF-026   0 of  7 actuated · 2 message-only   Mac Insights board
      SURF-028   2 of  8 actuated · 7 message-only   Mac capability document panel — three tabs over one package
            actuated: Capabilities; Changelog

      11 surface(s) declare controls that no passing effect-rung case actuates: SURF-001, SURF-002, SURF-004, SURF-005, SURF-006, SURF-008, SURF-009, SURF-010, SURF-011, SURF-025, SURF-026
      Reported, not blocked. The denominator is the finding; a gate that lands permanently red gets switched off.

After:

    Cases:      15 of 123 case(s) name a control they actuate; 108 name none and cannot move any number below
    Controls:   29 of 141 declared control(s) actuated by a passing effect-rung case, across 14 surface(s) that declare any
                86 of the 141 are message-only — the design's whole promised effect is a sheet, a panel or a notification appearing.
                Of the 112 not actuated, 81 are message-only and 31 promise a state change nothing has driven.
    Disposition: 29 actuated · 81 message-only · 7 with a stated reason · 24 UNDISPOSED — nobody has said anything about these.

      SURF-001   8 of 20 actuated · 12 message-only · fully disposed   Mac shell — sidebar, title, menus
            actuated: Activity; Checks; Cleanup; Discover; Inbox; Servers; Settings; Skills
      SURF-002   9 of 23 actuated · 11 message-only · fully disposed   Mac Servers board
            actuated: Accept the new text; All; Idle; Keep warm; Needs you; Only load in named projects; Remove; Reset; Running
            stated reason: Context menu → Keep warm; Context menu → Only load in named projects…; Keep serving the old text
      SURF-003   3 of  3 actuated · 2 message-only · fully disposed   Mac Activity board
            actuated: Cancel; Reset history; Reset history…
      SURF-004   2 of 21 actuated · 15 message-only · fully disposed   Mac Skills board
            actuated: All; Held
            stated reason: Keep the installed version; Never run; Promote the held update; Reveal repo in Finder
      SURF-005   0 of  9 actuated · 3 message-only · 6 undisposed   Mac Discover board
      SURF-006   4 of  5 actuated · 1 message-only · fully disposed   Mac Checks board
            actuated: All; Not met; Not observed; Unstamped
      SURF-007   1 of  9 actuated · 6 message-only · 3 undisposed   Mac Cleanup board
            actuated: Read first…
      SURF-008   0 of  6 actuated · 4 message-only · 2 undisposed   Mac Inbox board and review sheet
      SURF-009   0 of  7 actuated · 6 message-only · 1 undisposed   Mac menu-bar popover and inbox band
      SURF-010   0 of  2 actuated · 1 message-only · 1 undisposed   Mac Pairing sheet
      SURF-011   0 of 10 actuated · 7 message-only · 3 undisposed   Mac Settings board
      SURF-025   0 of 11 actuated · 9 message-only · 2 undisposed   Mac Harnesses board
      SURF-026   0 of  7 actuated · 2 message-only · 5 undisposed   Mac Insights board
      SURF-028   2 of  8 actuated · 7 message-only · 1 undisposed   Mac capability document panel — three tabs over one package
            actuated: Capabilities; Changelog

      7 surface(s) declare controls that no passing effect-rung case actuates: SURF-005, SURF-008, SURF-009, SURF-010, SURF-011, SURF-025, SURF-026
      Reported, not blocked. The denominator is the finding; a gate that lands permanently red gets switched off.

**6 → 29 of 141 actuated. Inert surfaces 11 → 7. Undisposed 47 → 24.** Four surfaces read *fully
disposed*: every control they declare is actuated, message-only, or carries a stated reason.

The `Disposition:` line and the per-surface `undisposed` count are J2's addition to the script. A
numerator alone says how many controls are proven and nothing about the rest; the fourth class is
the one worth a reader's attention, and it is printed on a green run as well as a red one.

The census also refuses two new contradictions at exit 1: a `controlsUnactuatable` entry naming a
control its surface never declared, and one excusing a control a passing case actually drives.

## 4 · DEF-062 — the finding the denominator produced

Trying to actuate SURF-004's declared controls found four with nothing to press.

`app/Sources/MCPRouterUI/Boards/SkillSheets.swift` declares three buttons and all three are
`Button("Done") { board.sheet = nil }`, so the sheet a user opens to decide about a held update can
only be dismissed. The design of record's capability-delta sheet offers a two-way decision —
`Promote 2.3.0` and `Keep 2.2.0`, recorded as `Promote the held update` and `Keep the installed
version` in `evidence/design-controls.json` under state `sheet:capability-delta`. `SkillsBoardModel`
carries no write at all. `Never run` is a filter chip the design draws and
`SkillPresentation.Filter` (`all | held | local | needsAttention`) has no case for; `Reveal repo in
Finder` appears nowhere under `app/Sources/`.

This is the shape `references/inert-ui.md` names as the census's own limit: *no amount of testing
the build reveals what the build lacks.* It surfaced only because the surface had a denominator and
J2 tried to fill it. SURF-004 therefore reaches 2 of 21 and the four are recorded under
`controlsUnactuatable` rather than trimmed out of the denominator, since a control removed from the
denominator is a control nobody will ever ask about again.

## 5 · What this does not claim

- **The in-process lane cannot prove a different board was drawn.** SwiftUI's view tree is opaque to
  a SwiftPM test and `ContentZone`'s switch is unreachable from it, so CASE-0195 proves the
  selection took and persisted, not that the destination rendered. Destination collapse is
  CASE-0001's claim, on glass, and that case is **FAILING** (DEF-058, DEF-059) — so it counts
  nothing here, which is the census behaving correctly.
- **`controlsUnactuatable` is prose.** The census checks that a reason names a declared control and
  that it does not excuse a control a passing case actually drives; it cannot check that the
  sentence is true. That is why the class is printed as its own number beside the actuated count
  rather than folded into it.
- **Twenty-four controls across seven surfaces remain undisposed** and the census says so on every
  run. J2 moved the three named surfaces plus SURF-006; the rest is visible backlog with a count
  attached rather than an amnesty.
- **The vendored instrument still cannot print this.** `vendor/test-campaign/` pins 0.9.2, which has
  no census at all; `bin/control-census.py` prints it from the same registry by the same rules and
  should be deleted when the pin passes 0.11.0 (G28's note, unchanged).

## 6 · Gates

| Gate | Exit | What it read |
|---|---|---|
| `make lint` (24 members) | **0** | swiftformat 0/75, swiftlint 0 violations over 707 files, and every python gate including `sweep-control` CLEAN at 93 discovered sweeps all disposed, 22 controls run and passing |
| `make test` | **0** | `discovered 2091 test ids` · `executed 2091 tests` · `Test run with 2091 tests in 266 suites passed`. Main's baseline is 2084 in 264; the two new suites are the 7 tests and 2 suites of difference |
| `swift test --filter` on the three cited suites | **0** | `Test run with 21 tests in 3 suites passed` |
| `arm-suites.py` × 9 | **0** | `armed 9 of 9 attempted · refused 0` |
| `control-census.py` | **0** | the two blocks above |

**One flake, established as not this branch's.** The first `make test` run failed on
`CallbackLifecycleTests`' *a listener binds once — reuse is refused rather than quietly racing*,
`Caught error: the callback listener was cancelled before it bound` — a loopback bind under a load
average of ~40 per core while three other fleet runners built. It passes alone and it passes in the
full run repeated on a quiet machine, and this branch changes no file under `RouterCore/`
(`git status` names 0). Recorded rather than dropped, because a flake nobody wrote down is a flake
somebody rediscovers.

**One pre-existing arm is broken and was not fixed here.** `CASE-0032`'s mutation anchor in
`Sources/RouterCore/Pool/UpstreamPoolReaping.swift` appears **0** times, so a full
`arm-suites.py` run reports it REFUSED. It predates this branch and belongs to whoever owns that
file; J2 selected its nine by id rather than editing an arm it does not own.
