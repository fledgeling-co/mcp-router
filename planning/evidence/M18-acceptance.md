# M18 — acceptance evidence

Append-only, per `planning/practices/UI_VERIFICATION.md` rule 2. A row whose commit is untouched
by `git diff <SHA>..HEAD` for that screen's files **is** the evidence; read this before testing
anything.

Base: `87e16dc` on `ai/m18`.

| Screen / claim | How verified | Commit | Result |
|---|---|---|---|
| The inventory matches the mock | `RouterSheetTests.inventoryMatchesTheMock` — parses `id="sh-*"` out of `design/mcp-router-console.html` and compares both directions | `a9dcb71` | **pass** |
| Thirteen drawn, sixteen kinds | `RouterSheetTests.buildOnlyKindsAreDistinguishable` | `a9dcb71` | **pass** |
| Every kind is hosted or owned | `RouterSheetTests.everyKindIsHostedOrOwned` | `a9dcb71` | **pass** |
| Gate table complete, nothing downgraded | `SheetGateTests` ×6 | `a9dcb71` | **pass** |
| **Accept held changes opens quarantine** | `SheetGateRoutingTests.acceptHeldChangesOpensQuarantine` — model seam | `a9dcb71` | **pass** |
| **Remove opens confirm-remove, both hosts** | `SheetGateRoutingTests.removeFrom{Servers,Cleanup}OpensConfirmRemove` | `a9dcb71` | **pass** |
| **Approve queued install opens queued-detail** | `SheetGateRoutingTests.approveQueuedInstallOpensQueuedDetail` | `a9dcb71` | **pass** |
| **Reset history opens its sheet, both hosts** | `SheetGateRoutingTests.resetHistoryFrom{Cleanup,Activity}` | `a9dcb71` | **pass** |
| **Trip breaker opens nothing** | `SheetGateRoutingTests.tripBreakerOpensNothing` | `a9dcb71` | **pass** |
| Pairing close stops the ticker | `SheetGateRoutingTests.closingPairingStopsTheTicker` | `a9dcb71` | **pass** |
| Discover's sheet does not leak a row id | `SheetGateRoutingTests.closingDiscoverClearsBoth` | `a9dcb71` | **pass** |
| `EvalsBoardModel` has no sheet | the deletion is the test — it does not compile if a reader survives | `a9dcb71` | **pass** |

## Gate results — gap-fix 1, 2026-08-22

Every row above ran and passed. `swift test` exit 0, **1757 tests in 219 suites**, 0 issues, green
on two consecutive runs. `swift build` exit 0. `make lint` exit 0.

Four of the guards were **broken deliberately and watched go red** before being restored — the
table in `planning/progress/M18.md` §The drift guards have been seen to fail names which break
produced which failure. `SWIFT_PRACTICES.md` §7: a test that has never failed is not known to work.

| Claim | How verified | Commit | Result |
|---|---|---|---|
| A disabled primary is distinguishable from a live one | `ButtonPaletteTests.theTwoStatesAreDistinguishable`, seen to fail | `d79a605` | **pass** |
| The disabled tier claims the WCAG 1.4.3 exemption by name | `ButtonPaletteTests.theDisabledTierClaimsItsExemption`, seen to fail | `d79a605` | **pass** |
| A disabled control surrenders the reserved accent hue | `ButtonPaletteTests.disabledSurrendersTheReservedHue`, seen to fail | `d79a605` | **pass** |
| No hardcoded colour, size or radius in the new sheets | `scripts/lint/no-raw-design-values.sh` — clean over 127 files | `21e9bd7` | **pass** |

## Rendered checks — owed, not done

Two surfaces are newly drawn (`OfficialMarkSheet`, `ChildPathSheet`) and four destructive buttons
changed how they get their colour. Those are rendered claims and want rendered evidence — a
`proctor` pass on the Discover board and the Settings window, backgrounded, one launch, per rule 1.

**Still not run, and now the reason is scope rather than the machine.** The gap-fix session got
build, test and lint green; it did not launch the app. What a rendered pass would add over what is
already asserted: that `@Environment(\.isEnabled)` actually updates the nested `View` at runtime,
and that the two new sheets lay out. The first was addressed by construction rather than by
measurement — the environment is read from a real `View`, where it is unambiguously supported,
instead of from a `ButtonStyle` — but *construction is an argument, not an observation*, and
`GAPFIX-BRIEF.md` asked for a measurement. Recorded as owed: an unrun check and a passed one must
not look the same.

The button-role change additionally has a claim worth measuring rather than reading:
`ColorToken.failInk` on `--raised` should clear the contrast floor where `ColorToken.fail` did not.
`ContrastFloorTests` proves the palette can; whether this call site does is what M23's `tokens`
layer would answer, and that is the fidelity surface work §Deferred names.

## Gates

Recorded in `planning/progress/M18.md` §Gates with each command and its exit.

## Gate results — gap-fix 4, 2026-08-29

Tree `d56b3aa`, worktree `.worktrees/K1`. Each command with its own exit code, captured
separately rather than through a pipe.

| Gate | Exit | What it measured |
|---|---|---|
| `swift build` | 0 | at `83e5380`, the base |
| `swift test` | 0 | 2100 tests / 267 suites. Three full runs; one red on `CallbackLifecycleTests.aListenerBindsOnce`, the R5 loopback flake, green in three isolated runs and in both full runs either side |
| `make lint` | 0 | the whole target, 26 members, in this worktree — it carries `node_modules` symlinked to the main checkout and a `dist/` built here, and the target needs both |
| `planning/evidence/M18-gapfix-2/arm-guards.sh` | 0 | **13 of 13 arms bit**, tree clean after every arm |
| `planning/evidence/M18-gapfix-3/shortcut-lines.py` | 0 | 439 files; 18 sheet views, agreeing with `SheetShortcutScan` for the first time |
| `… --self-test` | 0 | armed both ways, population moves by two |
| `python3 planning/citation-gate.py` | 0 | control 0 · blocking 0 · ratchet 0 |

Findings, repairs and what stayed open are in `planning/progress/M18.md` §Gates — gap-fix 4.
