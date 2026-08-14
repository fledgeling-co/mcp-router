# I2 — iPhone Discover and detail · acceptance evidence

**Append only.** One row per surface: what was verified, how, at which commit, and the result.

Read this before testing anything. If a surface has a row here and `git diff <that SHA>..HEAD`
does not touch the files behind it, **that row is the evidence** — do not re-run it.

## How these were verified

Three lanes, and the split is deliberate.

- **macOS host (`make test`, SwiftPM).** The phone's views live in `MCPRouterUI`, which compiles
  for macOS, so state machines, band membership, copy placement, the plate's derivations, the
  commit's seven states and the queue's write semantics are all exercised without a simulator.
  **1157 tests / 144 suites**, of which 76 are this feature's.
- **iOS simulator (`make test-ios`, hosted XCTest).** Everything the host lane physically cannot
  measure: a 44pt touch target, a safe-area inset, the row's intrinsic height across the Dynamic
  Type range, and whether the capability plate is actually *on screen* rather than merely
  constructible. **23 iOS tests, one simulator, reused rather than booted.**
- **`scripts/acceptance/i2-phone-discover.sh`.** The item's own gate: the placeholder guard plus
  this feature's rendered assertions and nothing else. 11 assertions, green.

Appearance is never pinned. The harness leaves the interface style `.unspecified`, and a previous
run in this repo failed reporting `#ECECEE` — which was the light ground rendering correctly.

I1's shell, pairing and settings are merged and evidenced in `I1-acceptance.md`. **They were not
re-verified.** The only I1 surface this feature touches is the Discover tab's branch, and that
change is asserted directly (A32).

---

## Rows

| Surface | How verified | Commit | Result |
|---|---|---|---|
| Discover tab resolves to a board, not the awaiting placeholder (A32) | acceptance script's guard, reading the `awaitingKey` switch in `PhoneShell.swift`; plus `PhoneDiscoverTests.discoverIsWired` on the host | `02d124d` | pass — **guard proven red-green**: pointing `.discover` at `.triageAwaiting` blocks the run with exit 1 |
| Capability plate — drawn, above the commit, behind no disclosure (A12) | iOS sim, `testThePlateIsRenderedWithoutAnyDisclosure` — asserts the consequence sentence *and* the literal invocation are in the rendered accessibility tree with nothing expanded | `02d124d` | pass |
| Capability plate — the Smithery credential admits it carries no signal (A14) | iOS sim, `testTheSmitheryCredentialLineAdmitsItCarriesNoSignal` — the host is named and the "doesn't set this server apart" clause is on screen | `02d124d` | pass |
| Capability plate — copy survives xSmall and AX3 (A29) | iOS sim, `testThePlateCopySurvivesAccessibilitySizes` | `02d124d` | pass |
| Commit — 44pt on every state, including the two dimmed ones (A17, A29) | iOS sim, `testEveryDiscoverControlMeetsTheMinimumTarget` over five surfaces; the disabled states are measured, so a target that vanished when dimmed could not pass by absence | `02d124d` | pass |
| Commit — the narrowing renders on all seven states (A20) | iOS sim, `testEveryCommitStateRendersTheNarrowing` — asserted on the **rendered** tree, because a bar that holds the string and never draws it satisfies a manifest test and not the criterion | `02d124d` | pass |
| Commit — unreachable stays live and relabels (A18) | iOS sim, `testUnreachableRendersTheSaveLabel`; host `DiscoverCommitTests.unreachableStaysLive` | `02d124d` | pass — **mutation-proven**: binding the predicate to `canSend` turns it red |
| Row — height independent of the name (Overflow, A29) | iOS sim, `testRowHeightIsIndependentOfTheNameLength`, measured by `sizeThatFits` | `02d124d` | pass |
| Row — skeleton matches the row it replaces (Loading, A29) | iOS sim, `testSkeletonMatchesTheRowItReplaces` at xSmall / large / AX3 | `02d124d` | **pass (was red: the skeleton was 1.67pt shorter than the row, so the list stepped when results landed)** |
| Detail — never-paired does not claim the router is down | iOS sim, `testNeverPairedDoesNotClaimTheRouterIsDown` / `testUnreachableStillRendersTheOfflineNote` | `ada73c0`+ | **pass (was red: the offline note and the never-paired commit contradicted each other on one screen)** |
| Detail — no motion, and none is owed | read: the commit bar is a permanent `safeAreaInset(edge: .bottom)`, not a conditionally-inserted bar, so `DESIGN.md` §7's "commit bar entry — rise on transform" has no entry moment to animate. A30 is a constraint on motion, not a requirement to add some; there is none in the feature, so it is satisfied by construction | `ada73c0` | pass, declared rather than animated |
| Discover — nothing occluded by the status bar or home indicator (A29) | iOS sim, `testDiscoverStaysInsideTheSafeArea` | `02d124d` | pass |
| No rate, delta or percentage anywhere (A1) | host, `DiscoverHonestyTests.noRateOrDelta` over every string the feature can emit, plus a source scan of the views | `02d124d` | pass — **mutation-proven**: a `+12%` in one copy entry turns it red |
| Every numeric string traces to a named field (A7) | host, `countsTraceToTheirField`, `datesTraceToTheirField`, and the member-access scan | `02d124d` | pass |
| Two bands, membership by presence not by zero (A2) | host, `DiscoverBandTests.missingCountIsAbsent` | `02d124d` | pass — **mutation-proven**: dropping the `useCount != nil` filter turns it red |
| The window filters one band only (A4) | host, `mostUsedIgnoresTheWindow` — membership byte-identical across all four windows | `02d124d` | pass |
| The copy manifest is complete and its tokens enumerated (A28) | host, `DiscoverCopyTests` | `02d124d` | pass — **mutation-proven**: dropping one element group from `Key.allCases` turns it red |
| The queue write is real, idempotent, and fails loudly (A22) | host, `DiscoverCommitTests` — survives a relaunch, one row on a double enqueue, a refused write throws | `02d124d` | pass — **mutation-proven**: making a corrupt queue file decode to `[]` turns it red |

---

## Gate results on this tree

| Gate | Command | Exit | Result |
|---|---|---|---|
| lint | `make lint` | 0 | 0 violations over 362 files, all four linters run |
| test | `make test` | 0 | 1157 tests / 144 suites |
| test-ios | `make test-ios` | 0 | 23 iOS tests, one simulator |
| parity | `make parity` | 0 | 358 vector cases (floor 358) |
| build-mac | `make build-mac` | 0 | `** BUILD SUCCEEDED **` |
| acceptance | `scripts/acceptance/i2-phone-discover.sh` | 0 | 11 assertions, one simulator, nothing else driven |

## Mutations, red-green

Five guards were deliberately broken, watched go red, and restored. Each filter was first
confirmed to match exactly one test — a `--filter` that matches nothing exits 0 and proves nothing.

| # | What was broken | Guard that caught it |
|---|---|---|
| M1 | `+12%` appended to a band header's copy | `noRateOrDelta` |
| M2 | `CommitState.resolve` bound to `canSend` instead of `canQueue` — A19's exact defect | `unreachableStaysLive` |
| M3 | an unreadable queue file decoded to an empty queue | `corruptQueueIsNotEmpty` |
| M4 | the `useCount != nil` filter removed, so a missing count ranks at zero | `missingCountIsAbsent` |
| M5 | one element group dropped from the hand-written `Key.allCases` | `everyElementKeyIsReachable` |
| M6 | `.discover` pointed back at an awaiting key | the acceptance script's placeholder guard |
| M7 | the offline note's condition widened back to include `.neverPaired` | `testNeverPairedDoesNotClaimTheRouterIsDown` — and the failure message captured the contradiction verbatim: *"The router isn't running on Luke's MacBook Pro."* and *"No Mac paired yet, so there's nowhere to send this."* in one rendered tree |

**A trap worth recording.** M7 was reverted with `git checkout -- <file>`, which restored the file
to `HEAD` — and the fix under test was **uncommitted**, so the revert discarded the fix along with
the mutation. The acceptance run immediately afterwards was still green, because the guard's
subject had gone back to the state the guard was written against. Mutating an uncommitted file
needs the fix committed first, or the revert has to be a re-application rather than a checkout.

## Declared, not fixed

- **No phone surface scales with Dynamic Type, and this feature cannot fix it.** `TypeToken.font`
  is `Font.system(size:weight:)`, which is a **fixed** font, so the row measures the same height at
  xSmall and at AX3. That is F2's shared ladder and it is shared with every Mac surface too;
  `DESIGN.md` §2 fixes the eight sizes deliberately, so changing it is a design decision rather
  than a bug fix. A29's Dynamic Type clause is therefore **not** satisfied, and the test says so in
  its own doc comment rather than asserting either direction — asserting "grows" would fail
  everywhere, and asserting "does not grow" would pin the gap shut. Reported as a deferred child.
- **I1's `testTextIsNotClippedAtAccessibilitySizes` overrides Dynamic Type through the UIKit trait
  collection**, which measurably does not reach the SwiftUI view — this feature's first attempt did
  the same and reported an identical height at every size. That test still asserts something real
  (the copy renders), but it is not varying what its name implies. Not this feature's file; reported.
- **`--attnWash` / `--attnLine` are still absent from `ColorToken`.** I1 reported this and it has
  not landed; the plate reads `PhoneMetric.tintedWashOpacity` as I1 does rather than growing a
  shared token surface from inside a feature.
