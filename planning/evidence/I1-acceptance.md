# I1 — iPhone shell and pairing · acceptance evidence

**Append only.** One row per screen: what was verified, how, at which commit, and the result.

Read this before testing anything. If a screen has a row here and
`git diff <that SHA>..HEAD` does not touch the files behind it, **that row is the evidence** —
do not re-run it. This file exists because I1 restarted its UI verification from zero on four
consecutive runs, each time re-proving screens nothing had changed.

## How these were verified

Two lanes, and the split is deliberate rather than convenient.

- **macOS host (`make test`, SwiftPM).** The phone's views live in `MCPRouterUI`, which compiles for
  macOS, so state machines, copy placement, colour-token semantics and the source guards are all
  exercised without a simulator. 559 tests, of which 103 are this feature's.
- **iOS simulator (`make test-ios`, hosted XCTest).** Everything the host lane physically cannot
  measure: a 44pt touch target, a safe-area inset, the system tab bar, Dynamic Type at an
  accessibility size, and the **generated** `Info.plist`. Asserting any of those on macOS would be a
  green light for a claim nobody measured. 11 tests, one simulator boot for the whole pass.

Appearance is never pinned in an assertion. `DESIGN.md`'s light appearance is authored, and a
previous run failed reporting `#ECECEE` — which was the light ground rendering correctly.

---

## Rows

| Screen / surface | How verified | Commit | Result |
|---|---|---|---|
| Shell — five tabs, order, Settings last | iOS sim, `testShellRendersFiveSystemTabs` — reads the hosted `UITabBar`'s items, so it proves the *system* tab bar rather than a drawn substitute | `a960957` | pass |
| Shell — no badges on any tab | iOS sim, `testTabBarCarriesNoBadges` — asserts `badgeValue == nil` on every item; plus a host-side source guard that no badge modifier appears | `a960957` | pass |
| Shell — Discover / Triage / Queue / Library awaiting states | macOS host, `PhoneCopyTests` — each tab's manifest entry is pinned, rendered and found in the mock. No row, no count, no fabricated number | `a960957` | pass |
| Every control — 44pt minimum target | iOS sim, `testEveryControlMeetsTheMinimumTarget` — walks the hosted view tree and measures `accessibilityFrame.height` on every element carrying `.button`, across four surfaces | `a960957` | **pass (was red: 24.0pt on 4 surfaces)** |
| Settings — paired Mac, all nine states | iOS sim, `testEveryPairedStateRendersItsCopy` — constructs each state and finds its manifest copy in the rendered labels | `a960957` | **pass (was red: reachable rendered an off-spec sentence)** |
| Settings — row height independent of Mac name (Overflow) | iOS sim, `testRowHeightIsIndependentOfNameLength` — long name vs short, measured to 0.5pt | `a960957` | pass |
| Settings — skeleton matches the row it replaces (Loading) | iOS sim, `testSkeletonMatchesTheRowItReplaces` — measured equal, so the board does not jump when data lands | `a960957` | pass |
| Settings — safe area | iOS sim, `testContentStaysInsideTheSafeArea` — nothing drawn is occluded by the status bar or home indicator | `a960957` | pass |
| Connection banner — three states, three sentences | macOS host, `ConnectionStateTests.vocabulary` — each state's sentence pinned to the manifest and distinct from the other two | `a960957` | **pass (was red: reachable interpolated the Mac name)** |
| Connection banner — indicator colour semantics (A4) | macOS host, `PhoneIndicatorTests` — `--live` only on reachable, not-reachable neutral, `--attn` never used for it | `a960957` | pass |
| Commit affordance — disabled before the tap, reason above (A21) | macOS host, `ConnectionStateTests.commitBlockedBeforeTheTap` — reason and waiting note asserted together | `a960957` | pass |
| Typed entry — commit disabled until 8 characters (A13) | macOS host, `PhoneFlowTests` — 0–7 disabled, 8 enabled | `a960957` | pass |
| Pairing — nine distinct outcomes (A15) | macOS host, `PairingBehaviourTests` — each renders its own headline/advice/action; refused's primary action is not retry | `a960957` | pass |
| Pairing — the honesty rule (A14) | macOS host — constructing verifying from `.typed` and finding an expiry is a test failure | `a960957` | pass |
| Camera — four permission states (A16/A17) | macOS host, via the `CameraAuthorizing` fixture — no device, no `AVFoundation` in the test | `a960957` | pass |
| Camera — purpose string in the **generated** Info.plist (A18) | iOS sim, `testGeneratedInfoPlistCarriesTheCameraPurposeString` — reads `Bundle.main`, the artifact that actually ships | `a960957` | pass |
| Scanner — metadata output only, no frames (A19) | iOS sim, `testScannerAddsOnlyAMetadataOutput` — inspects the configured session, which a symbol list cannot prove; plus the host-side source guard | `a960957` | pass |
| Dynamic Type — no clipping at accessibility sizes (A7) | iOS sim, `testTextIsNotClippedAtAccessibilitySizes` | `a960957` | pass |
| The narrowing, where permission is decided (A26) | iOS sim, `testNarrowingIsRenderedWherePermissionIsDecided` — measured from the rendered hierarchy, not from the manifest describing it | `a960957` | pass |

## Red-green proving pass

A guard never seen red is a decoration. Each was deliberately broken, the failure observed, and the
mutation reverted (`SWIFT_PRACTICES.md` §7, plan step 11).

| Guard | Mutation | Observed failure |
|---|---|---|
| A3 — no raw geometry in a Phone view | `.padding(.horizontal, PhoneMetric.section)` → `23` in `PhoneShell.swift` | `PhoneShell.swift writes a raw geometry value: .padding(.horizontal, 2 — name a PhoneMetric` |
| A27 — manifest ↔ mock parity | "arrive now" → "land now" in the reachable copy | `.settingsReachable.body sentence is not in the mock` **and** `.bannerReachable.body sentence is not in the mock` |
| A19 — no frame capture or upload | added `AVCaptureVideoDataOutput()` to `QRScannerView.swift` | `QRScannerView.swift references AVCaptureVideoDataOutput` |
| A18 — camera purpose string | deleted `NSCameraUsageDescription` from `project.yml` | `project.yml does not declare NSCameraUsageDescription` |

The two on-device failures in the row table above were **genuine product defects seen red before the
fix**, which is stronger evidence than an induced break: the measurement failed on real code, not on
a mutation written to make it fail.

### A note on one mutation that first read as a pass

The A27 mutation initially passed, which briefly looked like a hole in the guard. It was not — the
`perl` substitution lacked `/g` and rewrote only the doc comment, leaving the `Entry` body intact, so
the guard was never actually challenged. Re-run with `/g`, it failed on both entries. Recorded
because "the gate passed my mutation" is exactly the observation that should be chased to the ground
rather than written up as a limitation.

## Gate output at `a960957`

```
swiftformat/swiftlint: Found 0 violations, 0 serious in 176 files
no-raw-design-values: scanning 21 files — clean
make test:      Test run with 559 tests in 85 suites passed — executed 559 tests
make test-ios:  ** TEST SUCCEEDED ** — executed 11 iOS tests
make build-mac: ** BUILD SUCCEEDED **
make parity:    358 vector cases compared (floor 358)
```
