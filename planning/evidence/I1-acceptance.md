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

---

# Gap-fix pass — 2026-08-14, at `11034c1`

Rebased onto `main` (`4a6d1dc`) first. **`git diff 036fd34..main -- app/` is empty**, so nothing
`main` merged touched a file behind any row above: every row at `a960957` / `639d0d7` stands, and
none of those screens was re-tested. The two diagnostics the orchestrator recorded when the wave was
stopped — a missing `PairingCopy.Key.bannerReachable` and `PhoneProminentButtonStyle` out of scope —
were **stale**: both are present and correct, and `639d0d7` ("the two defects the on-device suite
found") is the commit that added them. Confirmed by a clean build, not by reading.

## What changed, and therefore what was tested

Two `try?` sites were discarding a Keychain failure. Only the surfaces behind that change were
exercised; every other screen cites its row above.

| Screen / surface | How verified | Commit | Result |
|---|---|---|---|
| Pairing — refused Keychain write does not render as paired | macOS host, `PairingStorageFailureTests.refusedSaveIsNotSuccess` — a store whose `save` throws drives the model; the step must be `.pairedNotStored`, not `.paired` | `11034c1` | **pass (was red: rendered `.paired`)** |
| Pairing — a successful write still reaches paired | macOS host, `successfulSaveIsStillSuccess` — the negative above cannot pass by breaking the happy path | `11034c1` | pass |
| Pairing — not-stored copy is honest | macOS host, `notStoredCopyIsHonest` — says the pairing worked, says a new code is needed, and is not the success sentence | `11034c1` | pass |
| Pairing — not-stored surface **renders** its manifest copy (A27 leg 2) | iOS sim, `testStorageFailureSurfacesRenderTheirCopy` — read from the rendered accessibility tree, not from the manifest describing it | `11034c1` | pass |
| Pairing — not-stored surface, 44pt targets (A5) | iOS sim, `testEveryControlMeetsTheMinimumTarget` — surface added to the measured set | `11034c1` | **pass (was red: 20.3pt with `.buttonStyle(.plain)`)** |
| Pairing — "Pair again" re-asks the camera (A16) | macOS host, `restartRechecksTheCamera` — a denied camera must reach `.cameraBlocked(.denied)`, never `.scan` | `11034c1` | **pass (was red: `.scan`)** |
| Unpair — a refused clear is reported, not discarded | macOS host, `refusedClearIsReported` — `unpair()` returns `.failed` on a throwing store and `.cleared` on a working one | `11034c1` | **pass (was red: reported `.cleared`)** |
| Unpair — failure copy states the Mac is still paired, guesses no cause | macOS host, `unpairFailedCopyIsHonest` | `11034c1` | pass |
| Unpair — failure block **renders** its manifest copy (A27 leg 2) | iOS sim, `testStorageFailureSurfacesRenderTheirCopy` — the block in the shape the settings screen constructs it | `11034c1` | pass |
| A24 — a refused write logs shape, never the record | macOS host, `refusedWriteLogsNoSecret` — against a collecting sink, with a store that throws an error **whose description is a credential** | `11034c1` | **pass (was red: `fp=`, `host=`, `port=` all reached the log)** |

## Red-green proving pass

Five mutations. Each was applied, the failure observed, and the mutation reverted.

| Guard | Mutation | Observed failure |
|---|---|---|
| Save failure is not success | restored `try? await store.save(mac)` | `a failed write rendered as .paired(...) rather than as its own state` |
| A27 mock parity, new entry | "survive closing the app" → "survive quitting the app" | `.pairedNotStored.body sentence is not in the mock` **and** the pinned-literal test |
| Unpair reports its failure | `catch` returns `.cleared` | `Expectation failed: await failing.unpair() == .failed` |
| A5 on the new surface | `PhoneProminentButtonStyle()` → `.plain` | `pairing/notStored: a control is 20.333333333333343pt tall, under the 44pt floor` |
| A16 on the recovery path | `restart()` sets `.scan` instead of `await start()` | `restart dropped a denied-camera user onto a dead scanner: .scan` |
| A24 bound on the log | `logSafe` → `"\(error)"` | `'SHA256:5f2b9c0e' reached a log line: … fp=SHA256:5f2b9c0e host=192.168.1.24 port=7333` |

The last one is the one worth reading. The critic found the original A24 test **vacuous** — the
injected error had no stored properties, so `\(error)` rendered `"WriteRefused()"` and the guard
would have held even if production logged the whole record. The error now carries the credential, so
the assertion can fail; the mutation above proves it does.

## The completeness critic

**`codex: usage limit → claude (downgrade).`** The out-of-family lane is account-limited until
20 Aug 2026 and was verified unavailable by the orchestrator, so the Phase D critic ran in-family:
a fresh `claude -p` opus-5 reviewer at high effort, briefed to refute and told that finding nothing
would be a failed review rather than a pass. **This is the weaker arrangement** — Claude auditing
Claude — and it is recorded here so the weakness travels with the evidence.

It returned **8 ACCEPT / 6 REJECT**, and every accept was a real defect. All eight are fixed in
`11034c1`; the rejects were argued rather than waved through. The accept worth naming: the new test
file was **untracked**, so the whole fix would have committed with no tests at all while `make test`
still reported a rising count.

## Known limits of this pass

Stated rather than left for the next runner to rediscover.

- **The `unpairFailure` lifecycle is not covered by a test.** Clearing it on re-pair and on a new
  pairing attempt is three assignments inside SwiftUI `@State`, which no host test can reach. The
  *decision* it renders (`store.unpair()`) is proven red-green, and the block it renders is proven
  on the simulator; the three assignments are proven by reading. A model seam would make it
  testable and is not worth a refactor of a working screen at this size.
- **`make test` is flaky on this machine, for reasons outside I1.** `CallbackListenerTests` and
  `CallbackHostileInputTests` (R5, merged) intermittently fail with
  `POSIXErrorCode(rawValue: 48): Address already in use` and a failed loopback connect. Cause: five
  `defer { Task { await listener.stop() } }` teardowns, which do not await the listener's shutdown,
  so a socket can outlive its test — visible only when another fleet runner's suite runs
  concurrently. **I1's own 112 tests pass with zero flake in isolation**
  (`swift test --filter "Phone|Pairing|Connection|Verifying"`). Reported for R5's owner; not fixed
  here.

## Gate output at `11034c1`

```
swiftformat:    0/180 files require formatting, 58 files skipped
swiftlint:      Found 0 violations, 0 serious in 178 files
no-raw-design-values: clean          no-wire-codable: clean
make test:      Test run with 566 tests in 86 suites passed — executed 566 tests
make test-ios:  ** TEST SUCCEEDED ** — executed 12 iOS tests (one simulator, reused, no new boot)
make parity:    358 vector cases compared (floor 358)
```

