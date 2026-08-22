# M18 — acceptance evidence

Append-only, per `planning/practices/UI_VERIFICATION.md` rule 2. A row whose commit is untouched
by `git diff <SHA>..HEAD` for that screen's files **is** the evidence; read this before testing
anything.

Base: `87e16dc` on `ai/m18`.

| Screen / claim | How verified | Commit | Result |
|---|---|---|---|
| The inventory matches the mock | `RouterSheetTests.inventoryMatchesTheMock` — parses `id="sh-*"` out of `design/mcp-router-console.html` and compares both directions | `a9dcb71` | see §Gates |
| Thirteen drawn, sixteen kinds | `RouterSheetTests.buildOnlyKindsAreDistinguishable` | `a9dcb71` | see §Gates |
| Every kind is hosted or owned | `RouterSheetTests.everyKindIsHostedOrOwned` | `a9dcb71` | see §Gates |
| Gate table complete, nothing downgraded | `SheetGateTests` ×6 | `a9dcb71` | see §Gates |
| **Accept held changes opens quarantine** | `SheetGateRoutingTests.acceptHeldChangesOpensQuarantine` — model seam | `a9dcb71` | see §Gates |
| **Remove opens confirm-remove, both hosts** | `SheetGateRoutingTests.removeFrom{Servers,Cleanup}OpensConfirmRemove` | `a9dcb71` | see §Gates |
| **Approve queued install opens queued-detail** | `SheetGateRoutingTests.approveQueuedInstallOpensQueuedDetail` | `a9dcb71` | see §Gates |
| **Reset history opens its sheet, both hosts** | `SheetGateRoutingTests.resetHistoryFrom{Cleanup,Activity}` | `a9dcb71` | see §Gates |
| **Trip breaker opens nothing** | `SheetGateRoutingTests.tripBreakerOpensNothing` | `a9dcb71` | see §Gates |
| Pairing close stops the ticker | `SheetGateRoutingTests.closingPairingStopsTheTicker` | `a9dcb71` | see §Gates |
| Discover's sheet does not leak a row id | `SheetGateRoutingTests.closingDiscoverClearsBoth` | `a9dcb71` | see §Gates |
| `EvalsBoardModel` has no sheet | the deletion is the test — it does not compile if a reader survives | `a9dcb71` | see §Gates |

## Rendered checks — owed, not done

Two surfaces are newly drawn (`OfficialMarkSheet`, `ChildPathSheet`) and four destructive buttons
changed how they get their colour. Those are rendered claims and want rendered evidence — a
`proctor` pass on the Discover board and the Settings window, backgrounded, one launch, per rule 1.

**Not run in this session, and the reason is the machine rather than the change.** Load average
sat between 122 and 288 across 16 cores throughout, `harbourmaster`'s ceiling was 3 with all three
berths held by other fleets, and a single `swift build` queued for more than ten minutes. Launching
the app on top of that would have been slow and would have competed with the gate runs that matter
more. Recorded as owed rather than claimed: an unrun check and a passed one must not look the same.

The button-role change additionally has a claim worth measuring rather than reading:
`ColorToken.failInk` on `--raised` should clear the contrast floor where `ColorToken.fail` did not.
`ContrastFloorTests` proves the palette can; whether this call site does is what M23's `tokens`
layer would answer, and that is the fidelity surface work §Deferred names.

## Gates

Recorded in `planning/progress/M18.md` §Gates with the command and its exit, not summarised here.
