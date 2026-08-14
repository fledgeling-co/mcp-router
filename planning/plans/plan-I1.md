# plan-I1 — iPhone: shell and pairing

**Spec:** `planning/specs/spec-I1.md` · **Design:** `DESIGN.md`,
`design/mocks/i1-phone-pairing.html` · **Branch:** `ai/i1` · **Worktree:** `.worktrees/I1`

**Plan tier: Standard.** One platform, one new module directory in each of two existing targets, no
schema migration, no change to any surface another runner owns. It is not Small because the copy
manifest and the four source-scanning guards are real design work rather than mechanical additions.

---

## Task

Replace the iOS target's placeholder `FoundationView` with the five-tab shell and the whole pairing
flow, built against a `PairingService` protocol and a fixture. Ship every state in
`spec-I1.md` §State matrix and §Shell copy matrix, with the copy manifest that makes placement
testable.

## Approach

Three layers, split on the line `SWIFT_PRACTICES.md` §8 already draws:

| Layer | Module | Why there |
|---|---|---|
| Logic, models, copy | `MCPRouterKit` | No UI frameworks, so the router's own tests can import it — and so every pairing outcome is testable without a view. |
| Views | `MCPRouterUI` | The shared presentation layer both apps link. Compiled for macOS too, so the phone's views are exercised on the macOS test host without a simulator. |
| Device-bound code | `MCPRouterIOS` | `AVFoundation` only. Everything it does is behind a protocol declared in the kit. |

The one rule that shapes the file layout: **anything a test needs to reach must not require a
simulator.** That is why camera authorization and the pairing transport are both protocols in the
kit with fixtures, and why the only code in the app target is the two `AVFoundation` adapters.

## Prerequisites

- `make test` green at baseline — confirmed, 237 tests executed, exit 0.
- Read: `app/Sources/MCPRouterKit/Control/ControlTokenStore.swift` (the store shape to copy),
  `app/Tests/MCPRouterKitTests/ControlCopyTests.swift` (the copy-parity pattern to extend).

---

## Steps

### 1. `PairingCode` — the Crockford Base32 code (A11)

`app/Sources/MCPRouterKit/Pairing/PairingCode.swift`

A value type wrapping eight canonical characters. `init?(_ text: String)` accepts any case, an
optional single `-` between the groups, and surrounding whitespace; normalises `I`/`i`/`L`/`l` → `1`
and `O`/`o` → `0`; rejects `U` and every character outside the alphabet; rejects any length but
eight after normalisation. `formatted` renders `XXXX-XXXX`.

Boundary tests, not middle ones: seven characters, nine characters, exactly eight; `U` present;
lower case throughout; dash absent, dash present, dash in the wrong place; leading and trailing
space; empty string.

### 2. `PairingPayload` — envelope, then versioned body (A12)

`app/Sources/MCPRouterKit/Pairing/PairingPayload.swift`

Decode in two passes, because the two failures have different copy and different recoveries:

1. **Envelope** — `t` must be exactly `mcp-router-pair`. Anything else, or unparseable JSON, is
   `.notAPairingCode`.
2. **Version** — `v` is a closed enum. A recognised envelope with an unknown `v` is
   `.versionMismatch`. A closed set on the wire is a closed set in Swift (§2 of practices), so this
   is an enum whose decode fails, not a `String` with a `default:`.
3. **Body** — every field in the spec's table is required. A missing or wrong-typed field is
   `.malformedPayload`.

No `try?`, no default fallback, and no path whose failure mode is an empty value. `exp` decodes to a
`Date` through an explicit ISO-8601 strategy rather than the default, which does not parse the
format.

### 3. Models (A15, A20, A22)

`app/Sources/MCPRouterKit/Pairing/PairingModels.swift`

- `PairedMac` — name, `pairedAt`, `lastSeen: Date?` (**optional, and that is the Partial state**),
  plus `host` / `port` / `fingerprint`, which are stored and never rendered.
- `PairingAttempt` — `.scanned(PairingPayload)` / `.typed(PairingCode)`. The honesty rule reads the
  case, so it cannot be lost the way a boolean flag can.
- `PairingOutcome` — `.paired(PairedMac)` plus the eight failures.
- `ConnectionState` — `.reachable` / `.notReachable` / `.neverPaired`.
- `SettingsSurfaceState` — the nine states, so the surface is driven by a value a test constructs
  rather than by a pile of optionals.

### 4. `PairingService` + fixture (A10)

`PairingService.swift`, `FixturePairingService.swift`. The protocol from the spec, and a fixture
whose scenario enum has one case per outcome — the shape `FixtureControlAPIClient` already
established, so a reader who knows one knows the other.

### 5. `PairingRecordStore` — Keychain (A22, A23)

`app/Sources/MCPRouterKit/Pairing/PairingRecordStore.swift`

Built to `ControlTokenStore`'s shape: a protocol, a Keychain implementation, an in-memory double.
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

The load path returns a three-way result, and **this is the step the out-of-family gate corrected**:

| Keychain result | Surface state |
|---|---|
| `errSecItemNotFound` | **never paired** — a restore to a new device leaves the item absent, not corrupt |
| success, decodes | paired |
| success, fails to decode, or any other status | **error**, whose copy describes what was observed and names no cause |

### 6. Camera authorization (A16, A17)

`app/Sources/MCPRouterKit/Pairing/CameraAuthorization.swift` — a four-case enum mirroring
`AVAuthorizationStatus` (`notDetermined` / `authorized` / `denied` / `restricted`), a
`CameraAuthorizing` protocol, and a fixture. **`restricted` gets the typed path as its primary
recovery**, because a restricted user may be unable to change the setting and "Open Settings" would
be a dead end.

`AVFoundation` appears only in `app/MCPRouterIOS/LiveCameraAuthorization.swift`.

### 7. The copy manifest (A27)

`app/Sources/MCPRouterKit/Pairing/PairingCopy.swift`

Keyed by **surface × state**, not a flat list — that key is what lets a test assert *placement*
rather than mere existence, which is the hole the gate found in the flat version:

```
enum PairingCopy {
    enum Surface: String, CaseIterable { case discover, triage, queue, library,
                                              settingsUnpaired, settingsPaired,
                                              scan, typedEntry, verifying, outcome, unpair }
    struct Entry: Sendable, Equatable { let headline: String?; let body: String;
                                        let actionLabel: String? }
    static func entry(_ surface: Surface, _ state: String) -> Entry?
    static let all: [(Surface, String, Entry)]
}
```

`neverInstalls` is a single `static let` (A26). Every string in both spec matrices becomes an entry.

### 8. Views — `app/Sources/MCPRouterUI/Phone/`

`PhoneShell.swift` (the five-tab `TabView`, Settings last, no badges), `AwaitingTab.swift`,
`ConnectionBanner.swift`, `SendCommitBar.swift`, `PairedMacSettings.swift` (the nine states),
`PairingFlowView.swift` (`NavigationStack`), `TypedCodeField.swift`, `CameraPermissionStates.swift`,
`UnpairConfirmation.swift`.

Every view takes its state as a parameter and reads its strings from `PairingCopy`. Colours, sizes,
radii and line heights come from the tokens — no literal anywhere (A3).

`#if os(iOS)` guards only what genuinely does not exist on macOS
(`.navigationBarTitleDisplayMode`); the view bodies themselves stay cross-platform so the macOS test
host exercises them.

Motion: the verifying indicator animates transform only, is wrapped in a Reduce Motion check, and
**never starts from opacity 0** (A29).

### 9. The iOS app target

`MCPRouterIOSApp.swift`'s body becomes `PhoneShell`. `LiveCameraAuthorization.swift` and
`QRScannerView.swift` are added — the scanner uses `AVCaptureMetadataOutput` with
`metadataObjectTypes = [.qr]`, which reads codes without a video data output, so there is no frame
buffer to persist (A19).

`app/project.yml` gains `NSCameraUsageDescription` for the iOS target only:

> "MCP Router uses the camera once, to read the pairing code shown on your Mac. Nothing is recorded."

### 10. Tests

`app/Tests/MCPRouterKitTests/` — `PairingCodeTests`, `PairingPayloadTests`, `PairingStoreTests`,
`PairingOutcomeTests`, `PairingCopyTests`, `CameraAuthorizationTests`, `PairingLogRedactionTests`.
`app/Tests/MCPRouterUITests/` — `PhoneShellTests`, `PhoneStateTests`, `PhoneSourceGuardTests`.

Four of these are **source-scanning guards**, and each states the failure it catches:

| Guard | Reads | Fails when |
|---|---|---|
| No hardcoded values (A3) | every `.swift` this item adds, in **both** modules | a hex literal, or a numeric literal in a `font`/`padding`/`cornerRadius`/`lineSpacing`/`frame` modifier |
| Camera purpose string (A18) | `app/project.yml` | the key is absent or its value is empty |
| No image persistence (A19) | the iOS target's sources | `AVCaptureVideoDataOutput`, `writeTo`, `UIImageWriteToSavedPhotosAlbum`, or an upload symbol appears |
| Copy manifest completeness (A27) | the manifest and the mock | an entry is missing from the mock, or a surface state has no entry |

**A18 is checked twice on purpose.** The unit test reads `app/project.yml`, which is tracked and
always present; a `make` check reads the **generated** `Info.plist` after `make generate`, because
the failure worth catching is a regeneration that drops the key. The generated plist is gitignored,
so it cannot be the only check — and project.yml alone cannot prove what was generated.

### 11. Red-green proving pass (`SWIFT_PRACTICES.md` §7)

Every guard above exists to catch drift, so each is deliberately broken, seen to fail, and restored.
Recorded in the spec's completion note with the observed failure message. A guard never seen red is
a decoration.

---

## Edge cases

- A code typed with `I`, `L` or `O` — normalised, not rejected; the user reading a screen is not
  punished for a font's ambiguity.
- A QR that is a URL, or any other app's code — `.notAPairingCode`, with its own copy.
- A payload whose `exp` is already in the past — `.expired`, reached without a network call.
- `lastSeen == nil` on a reachable Mac — the Partial state; the field says "unknown" and the banner
  explains why rather than filling it in.
- A Mac name long enough to wrap — truncates; the row height is asserted equal to the short-name row.
- Reduce Motion on during verification — the indicator holds position, the state still changes.

## Acceptance criteria → evidence

| Criterion | Evidence |
|---|---|
| A1, A2 | `PhoneShellTests` — five tabs in order, Settings last; four awaiting entries render the manifest literals; no badge modifier in the shell source |
| A3 | source-scanning guard over both modules, seen red |
| A4 | token-usage assertion: `--live` only on reachable, `--attn` only on the caution, not-reachable neutral |
| A5–A8 | hit-target and safe-area assertions on the rendered views; accessibility labels present on every control; Dynamic Type not fixed |
| A9 | no surface constructs a code for display — source guard plus the absence of any code-generating API |
| A10 | fixture implements every outcome; a test enumerates `PairingOutcome`'s cases against the fixture's scenarios so a new outcome with no fixture fails |
| A11 | `PairingCodeTests`, boundary values |
| A12 | `PairingPayloadTests` — three distinct outcomes, each asserted separately |
| A13 | commit disabled at 0–7 characters, enabled at 8 |
| A14 | constructing verifying from `.typed` and finding an expiry fails the test |
| A15 | every outcome renders its own headline/advice/action from the manifest; refused's primary action is not retry |
| A16–A18 | four camera states exercised through the fixture; purpose string checked in project.yml and in the generated plist |
| A19 | source guard, seen red |
| A20, A21 | `ConnectionState` three cases; commit disabled + reason above + waiting note asserted together |
| A22, A23 | store tests: not-found → never paired, decode failure → error |
| A24 | collecting log sink contains no code, key, host, port or fingerprint |
| A25 | unpair confirmation states consequence; not the default; Cancel separate |
| A26 | manifest placement test — the constant is rendered by both required surfaces |
| A27 | manifest completeness guard, both directions |
| A28 | nine states constructed and rendered; skeleton height equals populated row height |
| A29 | motion honours Reduce Motion; no entry animation starts at opacity 0 |

## Verify

`make all` (tools, lint, build mac + ios, test, parity). Report the output rather than asserting it.

## Out of scope

Everything in the spec's Out of scope, plus: no change to `MCPRouterUI`'s existing shared components
(a shared change is reported, not made), and no change to `DESIGN.md`.
