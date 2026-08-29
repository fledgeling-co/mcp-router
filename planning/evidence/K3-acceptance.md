# K3 — the last seven inert surfaces, and the sixteen controls that say why they stay at zero

Brief: `planning/features-to-triage/eleven-surfaces-declare-controls-that-nothing-drives.md`.
Branch `ai/k3`, off `83e5380`. Every figure below is pasted from a run; nothing here is asserted by
hand.

J2 took the census from 6 to 29 of 141 and the inert set from eleven surfaces to seven. K3 takes the
seven and empties the fourth class over all of them. Three move off zero. Four cannot, and each of
those now carries a sentence per control saying what stops it — which is the half of the brief that
matters more, because the brief's own instruction is that a control removed from the denominator is
a control nobody will ever ask about again.

## What the brief asked for, and what each clause got

| Acceptance clause | Where it stands |
|---|---|
| Every declared control is driven or carries a stated reason | **Done for all seven.** SURF-005, SURF-008, SURF-009, SURF-010, SURF-011, SURF-025 and SURF-026 every one read `fully disposed`. Undisposed **24 → 4**, and the four left are SURF-007's three and SURF-028's one, neither of which was ever among the eleven |
| The census reports a non-zero actuated count per surface | **29 → 33 of 141.** SURF-005 0 → 1, SURF-008 0 → 2, SURF-025 0 → 1. Inert surfaces **7 → 4**. The remaining four are at zero because the build draws no control to press, not because nobody tried |
| Driving is proved by reading the state through a channel other than the one that struck | Every one of the four cases; the channel is named per case in `actuatesNote` and the rejected same-channel read is named beside it |
| Replacing a real handler with an empty closure turns the case red, watched rather than assumed | Four arms in `bin/arm-suites.py`, each removing the write and leaving every report the surface makes about it |
| A control whose only promised effect is navigation or a message is recorded as that | Unchanged: 81 message-only controls are their own class and are never counted as actuated. Sixteen further controls gained `controlsUnactuatable` reasons |

## 1 · The channel, per case

The bar is J2's and it is upstream's rule with `references/inert-ui.md`'s condition on top: only a
**passing** case at an **effect rung** moves the count, and the observable must be something the
handler was supposed to change, read through a different channel from the one that struck.

| Case | Surface | Control | Struck | Read back on | The same-channel read that was refused |
|---|---|---|---|---|---|
| CASE-0213 | SURF-005 | Install | `DiscoverBoardModel.install` | the declaration the recording client received — name, command and args — over two entries with different install blocks | `board.rows[0].installed == true`, which `markInstalled` writes from the board's own copy |
| CASE-0214 | SURF-008 | Install | `InboxBoardModel.accept` | the declaration the client received, and the `force` flag it carried | the sheet closing, `acceptState` clearing, the row leaving `rows`, the badge falling — all four |
| CASE-0215 | SURF-008 | Decline | `InboxBoardModel.decline` | the rows the board draws, as an ordered identity against the survivors, **and** the silence on the control API | `board.dispositioned[item.id] != nil`, the dictionary the call just wrote |
| CASE-0216 | SURF-025 | Rescan | `HarnessesBoardModel.load` | the row set a **different** second answer produced | `board.state` still being `.loaded`, which it was before the press |

Two of those are worth reading rather than skimming.

**CASE-0214 is the acknowledgement-only shape with four witnesses at once.** The Inbox's accept
clears `acceptState`, closes the sheet, drops the row and lowers the badge — and every one of those
comes from `record(.accepted(…))` *after* the router call, so every one of them happens identically
when nothing leaves the machine. Four plausible assertions, four greens, one control that told the
router nothing. The arm demonstrates it rather than describing it.

**CASE-0216 refuses a read that would have looked like the right one.** `Rescan`'s promise is a
fresh reading, and the obvious assertion is that a second request went out. The arm leaves the
request going out and throws the answer away, so a case built on the count alone stays green over a
board frozen on its first reading. The client therefore stages a second answer that *differs*, and
the row set is the observable. The count is still asserted — it is just not sufficient, and the case
says so.

**What this lane cannot claim.** The press is made at the model, because a SwiftPM test cannot
actuate a SwiftUI `Button`. A button rewired to an empty closure while its model method stayed
correct would fail nothing here. That wiring is the interactive-glass lane's claim, and it is why
every arm mutates the model method rather than the view.

## 2 · The arms — the write removed, the reporting left

    $ python3 planning/test-campaign/bin/arm-suites.py CASE-0213 CASE-0214 CASE-0215 CASE-0216
    arming 4 of 26 suite-backed cases

      ARMED  CASE-0213  installDeclaresTheRowThatWasPressed  mutated=red(1 test(s)) restored=green(1)
      ARMED  CASE-0214  inboxInstallDeclaresTheResolvedEntry  mutated=red(1 test(s)) restored=green(1)
      ARMED  CASE-0215  declineRemovesOneRowAndCallsNothing  mutated=red(1 test(s)) restored=green(1)
      ARMED  CASE-0216  rescanRedrawsFromTheSecondReading  mutated=red(1 test(s)) restored=green(1)

    armed 4 of 4 attempted · refused 0
    wrote planning/test-campaign/evidence/runs/arm-suites.0213-0216.log

Four of four bit. CASE-0215's mutation is the empty closure verbatim — `decline(_:)`'s body becomes
`_ = item`. The other three remove the write and leave everything the surface reports about it
standing, which is the same shape one level in: an empty closure that still tells the user it
worked.

**Two of the four had to be re-shaped before they would compile, and the first attempt is worth
recording.** Replacing `_ = try await client.add(declaration)` with `_ = declaration` leaves a
`do` block that throws nothing, so the typed `catch` binds `any Error` and
`installState = .failed(error)` stops type-checking. `arm-suites.py` classified both as
`build-failed` rather than counting them as caught defects, which is the classification working:
a mutation that does not compile reads exactly like a red. The mutations now remove the whole
`do`/`catch` and keep the reporting lines.

**One run was interrupted by the volume, and the tree was repaired rather than left.** The second
arming attempt hit `PermissionError: Operation not permitted` on `/Volumes/LLMs` **inside the
restore**, leaving `InboxBoardModel.swift` mutated and writing no log. The source was restored from
`git`, the partial log deleted, and the whole set re-run from a clean tree — the log cited above is
that run and no other. `git status` over `app/Sources/` is clean.

## 3 · The census, before and after

Before, at `83e5380`, on the unmodified tree — note the exit 1, which is not K3's and is fixed in §5:


      2 case(s) actuating a control their surface never declared — the registry and the case disagree about what the surface carries:
        · CASE-0207 actuates Servers — not among SURF-002's declared controls
        · CASE-0209 actuates kill the router underneath a running app — not among SURF-002's declared controls
    Cases:      17 of 132 case(s) name a control they actuate; 115 name none and cannot move any number below
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

After:

    Cases:      20 of 136 case(s) name a control they actuate; 116 name none and cannot move any number below
    Controls:   33 of 141 declared control(s) actuated by a passing effect-rung case, across 14 surface(s) that declare any
                86 of the 141 are message-only — the design's whole promised effect is a sheet, a panel or a notification appearing.
                Of the 108 not actuated, 81 are message-only and 27 promise a state change nothing has driven.
    Disposition: 33 actuated · 81 message-only · 23 with a stated reason · 4 UNDISPOSED — nobody has said anything about these.

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
      SURF-005   1 of  9 actuated · 3 message-only · fully disposed   Mac Discover board
            actuated: Install
            stated reason: 24h; 30d; 7d; Servers; Skills
      SURF-006   4 of  5 actuated · 1 message-only · fully disposed   Mac Checks board
            actuated: All; Not met; Not observed; Unstamped
      SURF-007   1 of  9 actuated · 6 message-only · 3 undisposed   Mac Cleanup board
            actuated: Read first…
      SURF-008   2 of  6 actuated · 4 message-only · fully disposed   Mac Inbox board and review sheet
            actuated: Decline; Install
      SURF-009   0 of  7 actuated · 6 message-only · fully disposed   Mac menu-bar popover and inbox band
            stated reason: Quit
      SURF-010   0 of  2 actuated · 1 message-only · fully disposed   Mac Pairing sheet
            stated reason: Can't scan? Type a code
      SURF-011   0 of 10 actuated · 7 message-only · fully disposed   Mac Settings board
            stated reason: Can't scan? Type a code; Reset history; Unpair
      SURF-025   1 of 11 actuated · 9 message-only · fully disposed   Mac Harnesses board
            actuated: Rescan
            stated reason: Scan again
      SURF-026   0 of  7 actuated · 2 message-only · fully disposed   Mac Insights board
            stated reason: Analyse now; Analyst cadence; Analyst model; Insights window; Second-opinion model
      SURF-028   2 of  8 actuated · 7 message-only · 1 undisposed   Mac capability document panel — three tabs over one package
            actuated: Capabilities; Changelog

      4 surface(s) declare controls that no passing effect-rung case actuates: SURF-009, SURF-010, SURF-011, SURF-026
      Reported, not blocked. The denominator is the finding; a gate that lands permanently red gets switched off.

**29 → 33 of 141 actuated. Inert surfaces 7 → 4. Undisposed 24 → 4.** Twelve of the fourteen
surfaces that declare controls now read `fully disposed`; the exceptions are SURF-007 and SURF-028,
which were never among the eleven this brief names and are left as visible backlog with a count
attached.

## 4 · The four surfaces that stay at zero, and why that is the answer

Three defects and two refusals, all sixteen recorded in `inventory.json` under
`controlsUnactuatable` rather than trimmed out.

**DEF-063 · SURF-005.** The design puts two scoping controls on Discover and the build draws
neither. `Servers`/`Skills` filters the mock's registry on each row's `kind`; `RegistryEntry` has no
kind and the board searches one merged registry, so both halves would draw the same list.
`24h`/`7d`/`30d` scopes a Trending table the mock's own caption says ranks *by install velocity over
the window, not total*; the response carries `useCount`, one total, with no series behind it. The
build's one segmented control is `RegistryPresentation.Ordering`, which the mock does not draw — so
this is a divergence in both directions rather than an omission. `Install` is real and is CASE-0213.

**DEF-064 · SURF-010 and SURF-011.** Three controls, three different reasons, and only one is a gap
in the product. `Can't scan? Type a code` exists as copy and is drawn only by the phone's
`PairingFlowView`, so REQ-015's typed path is reachable from one device while the design puts the
affordance on the other. `Unpair` cannot be built as drawn: the control API has no devices endpoint,
which `SecurityPane` states in its own words before offering `Manage…` and `Forget the stored token`
instead. `Reset history` is the confirm button of a sheet the Settings window does not host — the
act ships, reaches the same endpoint from Activity and Cleanup, and is actuated on SURF-003 by a
passing case; what is absent is this surface's entry point.

**DEF-065 · SURF-026.** DEF-062's shape a second time. `Button(InsightsBoardCopy.analyseNow) {}` is
the whole of the analyst's action — an empty closure, `.disabled(true)`, with `analyseUnavailable`
as its help and its accessibility hint, which is `DESIGN.md` §3.4's dim-with-a-reason rather than an
inert control: the refusal is the product's, not the campaign's, and the reason is that `PRD.md` §6
specifies a session analyst and nothing under `app/Sources` implements one. Three further readouts —
`Analyst cadence`, `Analyst model`, `Second-opinion model` — have no counterpart at all.

**Two refusals, deliberately not defects.** `Quit` (SURF-009) is built: `MenuBarRouter.quit()`
terminates the app, and the only state it changes is the process ending, so there is no seam to
observe and nothing survives the act to assert on. In a SwiftPM test the shared application is nil
and the call is a silent no-op; on glass this campaign never activates MCPRouter, which is why
SURF-009 already carries three `n/a` cases and no build capture. `Insights window` (SURF-026) is
parked with its reasoning already in the board's own header comment: the window is fixed at 24 hours
because the call log rotates and what a router can answer for is whatever survived, so a control
offering seven days on a machine holding two would lie about its own range.

**One label divergence, recorded and not filed.** SURF-025's `Scan again` is the design's name for
the rescan control in `board:empty`, where it calls it `Rescan` in `board:ideal`. The build draws a
single header action outside the state switch, so it is on screen in the empty state too and reads
`Rescan` there. One control, drawn once, actuated by CASE-0216 — a copy difference rather than a
missing control.

## 5 · Found by running the census: two cases that read as registry contradictions

`control-census.py` exits **1** on `83e5380` and has since J5 merged, over two cases neither of
which is wrong:

    · CASE-0207 actuates Servers — not among SURF-002's declared controls
    · CASE-0209 actuates kill the router underneath a running app — not among SURF-002's declared controls

CASE-0207 presses **SURF-001's** sidebar row to reach the Servers board, and is filed against the
board it then reads — its own `actuatesNote` says so. The census had no way to express that, so a
correct case and a correct registry disagreed. `actuatesSurface` is added: a case may name the
surface whose control it pressed, and the name must still be declared there, so a stray is still a
stray and a surface declaring no controls is still refused.

CASE-0209's actuation is on the **world** rather than on the app — the router process is killed
underneath a running window — and its note already said so. It named that as a control anyway. The
field is removed and the note keeps the record; the case now names no control, which is the truth.

Neither change moves the actuated count: `Servers` was already actuated on SURF-001 by CASE-0198.
What it moves is the exit code, from 1 to 0, so a contradiction introduced later is visible again.

## 6 · What this does not claim

- **The in-process lane cannot press a button.** Every arm mutates the model method the button's
  closure calls. A `Button` rewired to `{}` with a correct model behind it fails nothing here.
- **`controlsUnactuatable` is prose.** The census checks that a reason names a declared control and
  does not excuse one a passing case drives; it cannot check that the sentence is true. Sixteen new
  sentences are sixteen new claims, and they are printed as their own number beside the actuated
  count for exactly that reason.
- **Four surfaces are fully disposed at zero actuated.** That is not the same as a working surface.
  SURF-009, SURF-010, SURF-011 and SURF-026 declare 26 controls between them, 16 message-only and
  10 with a stated reason, and the census still lists all four as declaring controls nothing drives.
- **Two surfaces outside the eleven still carry undisposed controls.** SURF-007's three and
  SURF-028's one were never in this brief's set and are untouched.
- **The vendored instrument still cannot print this.** `vendor/test-campaign/` pins 0.9.2, which has
  no census; `bin/control-census.py` prints it from the same registry by the same rules and should
  be deleted when the pin passes 0.11.0 (G28's note, unchanged).

## 7 · Gates

| Gate | Exit | What it read |
|---|---|---|
| `make lint` (26 members) | **0** | swiftformat clean, swiftlint `Found 0 violations, 0 serious in 710 files`, and every python gate — including `sweep-control` at 100 discovered sweeps with **0 undisposed**, and `evidence-citation` at `UNTRACKED 0 · MISSING 0` over 395 occurrences |
| `make test` | **0** | `Test run with 2104 tests in 268 suites passed`. Main's baseline is 2100 in 267; the four new tests and one new suite are the difference |
| `swift test --filter BoardWriteActuationTests` | **0** | `Test run with 4 tests in 1 suite passed` |
| `arm-suites.py` × 4 | **0** | `armed 4 of 4 attempted · refused 0` |
| `control-census.py` | **0** | the two blocks in §3. It was **1** on `83e5380` for the reason in §5 |

Not this branch's: one `OAuthWireTests:263` timing flake in the full run — *the group's 50ms budget
expired* — which passes alone (`Test run with 18 tests in 5 suites passed`) and is one of the three
load flakes this fleet already has on record.

## 8 · The arm log

`planning/test-campaign/evidence/runs/arm-suites.0213-0216.log` holds the whole record — the
mutation applied per case, the filtered run's verdict and test count under it, and the same run
after restore. It is the file the four cases cite and it is the run quoted in §2, not a
re-transcription of one.
