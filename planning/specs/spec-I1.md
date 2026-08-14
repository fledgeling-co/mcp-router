# spec-I1 — iPhone: shell and pairing

**Status:** Ready for Work
**Depends on:** F1 (workspace), F2 (design system), F3 (control client). M6 is named in the brief
but is **not merged**; §Triage records how that is handled without waiting for it.
**Design authority:** `DESIGN.md` (root). **Design representation:** `design/mocks/i1-phone-pairing.html`
(12 sections, 30 frames, deep-linkable `?sec=X&appearance=light&motion=reduced`).
**Practices:** `planning/practices/SWIFT_PRACTICES.md`, `CODING_PRACTICES.md`,
`NEW_PROJECT_BEST_PRACTICES.md` — all binding.

---

## Feature description

Verbatim from `planning/features-to-triage/I1-ios-shell-pairing.md`:

> The companion's foundation. A tab bar (Discover / Triage / Queue / Library / Settings) and the
> pairing flow that connects it to a Mac.
>
> - Pairing by QR scan with a typed-code fallback, mirroring M6's Mac side and its expiry countdown.
> - Connection state is always legible: paired to which Mac, reachable or not. A phone that silently
>   fails to send is worse than one that says it cannot.
> - **The phone queues; it never installs.** This is a deliberate narrowing of "remote install" and
>   every surface must reflect it rather than implying otherwise.
> - iOS-native grammar throughout — this is not the Mac app's chrome on a phone.

The iOS target today is a single `FoundationView` that says the shell is not built yet. This item
replaces it with the real shell and the whole pairing flow, and stops exactly there: Discover,
Triage, Queue and Library are I2/I3's content and ship here as designed awaiting states, never as
fake rows.

**What this item does and does not ship.** It ships the entire phone-side pairing experience — every
surface, state and failure — against a `PairingService` protocol with a fixture. It does **not**
ship a network transport, because M6 owns the Mac endpoint and is unmerged; inventing a wire M6 must
then match is worse than publishing a contract M6 implements. §Pairing contract fixes that contract
concretely so "the seam" is a specification rather than a gesture, and §Deferred children names the
integration item and the two iOS platform requirements it inherits.

---

## Pairing contract

The QR payload and the service protocol, fixed here so M6 has something exact to implement and so
this item's decode path is testable end to end.

### QR payload

Compact JSON, UTF-8, carried in the QR. **Decoded as an envelope first, then a versioned body** —
which is what keeps "this is not our code at all" distinguishable from "this is our code from a
version we do not speak" (they have different copy and different recoveries).

| Field | Type | Meaning |
|---|---|---|
| `t` | string, exactly `"mcp-router-pair"` | Envelope discriminator. Anything else is **not a pairing code**. |
| `v` | integer | Payload version. This item speaks `1`. A known-envelope / unknown-`v` is **version mismatch**. |
| `code` | string | The 8-character code, canonical form (§A7). |
| `mac` | string | The Mac's display name, shown while verifying and after pairing. |
| `exp` | ISO-8601 instant | When the code expires. **This is the only source of an expiry the phone ever observes** (§A10). |
| `host` | string | Where the Mac is reachable. Carried, stored, never displayed. |
| `port` | integer | As above. |
| `fp` | string | The Mac's key fingerprint, for the transport M6 brings. |

Every field is required. A missing or wrong-typed field with a valid envelope and known version is
**malformed payload**, which is its own outcome and not silently tolerated.

**Replay.** A code pairs one device once; the Mac enforces single use and answers `alreadyUsed`. The
phone does not retain a scanned code after the attempt resolves.

### Service protocol

```
protocol PairingService: Sendable {
    func pair(using: PairingAttempt) async -> PairingOutcome
    func reachability(of: PairedMac) async -> ConnectionState
}
```

`PairingAttempt` is either `.scanned(PairingPayload)` or `.typed(PairingCode)` — the distinction the
honesty rule (§A10) turns on, carried in the type rather than in a flag someone can forget to set.
`PairingOutcome` is `.paired(PairedMac)` or one of the six failures in §A11. The fixture implements
every case.

---

## Acceptance criteria

Each is written so a single piece of typed evidence — a measurement, an exercised request, or a
red-green test — settles it.

### The shell

- **A1** The app's root is a five-tab `TabView`: Discover, Triage, Queue, Library, Settings, in that
  order, with Settings last. Tab labels are sentence case and drawn from the design system's icon
  set, never unicode.
- **A2** The four non-Settings tabs each render their own **awaiting** state — an illustration, a
  headline and one sentence — using exactly the literals in §Shell copy matrix. None renders a row or
  a count. **No tab carries a badge at all**: a count is observed data this feature does not own, and
  inventing one is the fabricated-number failure `DESIGN.md` §6 forbids.
- **A3** No file this item adds or changes, **in either `MCPRouterUI` or the iOS app target**,
  hardcodes a colour, size, radius, **line height** or type size; every value is read from
  `ColorToken` / `TypeToken` / `MetricToken`. Evidence scans the source of both modules, not one.
- **A4** Indicator colours are used only for their documented meanings (`DESIGN.md` §2). Concretely:
  **reachable** may use `--live`, because a reachable Mac genuinely has the router process running,
  which is what `--live` means. **Not reachable is neutral** (`--t2` on `--f3`), *not* `--attn` —
  nothing is being asked of the user, the state recovers on its own, and `--attn` means "wants a
  human decision". `--attn` in this feature is reserved for the pre-scan caution, which is an
  actionable warning; `--fail` for camera-unavailable and pairing failures. **This corrects the
  design representation**, which painted the not-reachable banner in `--attn`.

### iOS-native grammar

- **A5** Every interactive element has a hit target of at least 44×44pt.
- **A6** Content respects the safe area; nothing this item draws is occluded by the home indicator or
  the status bar, and the tab bar is the system's, not a drawn substitute.
- **A7** Every control and every image that carries meaning has an accessibility label; decorative
  glyphs are hidden from assistive technology. Text scales with Dynamic Type rather than being fixed
  at a point size in a frame that clips it.
- **A8** Navigation and presentation are the platform's — `NavigationStack` for the pairing flow, a
  confirmation dialog for unpair — not a re-creation of Mac chrome.

### Pairing — direction and transport

- **A9** The **Mac issues the code and the phone consumes it**. No surface in this feature displays a
  code for the Mac to read. (This corrects the shared prototype, which had the phone displaying one.)
- **A10** Pairing is reached through the `PairingService` protocol in §Pairing contract, with a
  fixture implementing **every** outcome in A14. No live network client ships in this item.
- **A11** A pairing code is **8 characters in two groups of four**, drawn from **Crockford Base32**
  (`0-9`, `A-Z` minus `I`, `L`, `O`, `U`). Parsing is case-insensitive, tolerates the separating dash
  and surrounding whitespace, and **rejects** anything else. `I`/`L` normalise to `1` and `O` to `0`
  on input, per Crockford, so a user reading a screen cannot be defeated by glyph ambiguity.
- **A12** The QR payload is decoded **envelope first, then versioned body** (§Pairing contract),
  producing three *distinct* outcomes: not-a-pairing-code, version-mismatch, malformed-payload. There
  is no `try?`-and-default anywhere in the decode path, and no decode path whose failure mode is an
  empty result (`SWIFT_PRACTICES.md` §2).
- **A13** The commit control on typed entry is **disabled until all eight characters are present**,
  and disabled means dimmed in place with the control still visible (`DESIGN.md` §3.4).

### Pairing — the honesty rule

- **A14** A countdown is shown **only for `.scanned`**, where the payload carries `exp` and the phone
  has therefore observed it. `.typed` shows a working indicator and **no number**. Constructing the
  verifying state from a typed attempt and finding an expiry in it is a test failure.

### Pairing — every outcome

- **A15** Nine distinct outcomes are modelled and rendered, each with its own copy and its own
  recovery: not recognised, expired, already used, version mismatch, unreachable, refused, plus the
  three decode outcomes in A12. None collapses into a generic "pairing failed". Refused does **not**
  offer retry as its primary action — a refusal is a decision someone made at the Mac.
- **A16** Camera permission has **four** states, matching `AVAuthorizationStatus`: not-determined
  renders a pre-prompt explaining why the camera is wanted *before* iOS asks; denied renders an
  unrecoverable-in-app state whose primary action opens iOS Settings; **restricted** renders its own
  state whose primary action is the typed path, because a restricted user may be unable to change the
  setting and "Open Settings" would be a dead end; authorized renders the scanner. Every camera state
  also offers the typed path.
- **A17** Camera authorization is reached through a protocol with a fixture, so all four states are
  exercised without a device and without `AVFoundation` in the test.
- **A18** `NSCameraUsageDescription` is declared in `app/project.yml` for the iOS target and is
  present and non-empty in the **generated** `Info.plist`. Without it, requesting camera access traps
  at runtime; asserting the generated artifact rather than the source is what catches a
  regeneration that drops it.
- **A19** The scanner reads QR metadata only. No frame is written to disk and nothing in this item
  uploads an image — verified structurally against the source, not asserted in prose.

### Paired state and connection

- **A20** `ConnectionState` has exactly three cases — reachable, not reachable, never paired — with
  one vocabulary reused on every surface that offers to send.
- **A21** I1 ships the connection banner and a **reusable disabled-commit affordance** as components
  with their own tests: given not-reachable, the commit is disabled and the reason renders directly
  above it. I1 ships no sending surface of its own — Queue is I3's — so this criterion is settled at
  component level, and I3 wires it. **The disabled commit and the waiting copy are not in tension:**
  the control that sends *now* is disabled, and the copy states that queued items go on their own
  when the Mac returns. Both are asserted together.
- **A22** The paired record persists in the **Keychain** with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never `UserDefaults`, never a plist, never a
  file beside the app.
- **A23** A **missing** Keychain item renders **never paired**, not an error — on a new device after
  a restore, the item is absent rather than corrupt. The Error state is reached only from an
  *observed* failure (a Keychain status other than not-found, or a decode failure of a record that
  was present), and its copy describes what was observed without guessing a cause.
- **A24** No log line ever contains a pairing code, a paired key, `host`, `port`, `fp`, or a whole
  pairing record. Shape only, checked against a collecting sink rather than asserted.
- **A25** Unpair is destructive and gets a **named-consequence** confirmation stating what stops
  working and what survives. It is never the default button, and Cancel is a separate control.

### The narrowing

- **A26** The sentence "This app queues items for review on your Mac. It cannot install, update or
  remove anything — that happens only at your Mac." exists once as a single constant and is rendered
  by **both** the never-paired Settings surface and the pairing-success surface. Asserted as
  "this surface in this state renders this constant" (A27), not as a substring search.

### States, copy and motion

- **A27** Every user-facing string in this feature lives in one **copy manifest** keyed by
  *surface × state*, and is asserted three ways: the literal is pinned, the manifest entry is what
  the view for that surface and state actually renders, and the same string is found in
  `design/mocks/i1-phone-pairing.html`. Rewording any one of the three without the others fails the
  build. A manifest entry with no rendering surface, or a surface state with no manifest entry, is
  itself a failure — that is what makes A26's placement claim testable.
- **A28** The Settings paired-Mac surface ships **all nine** `DESIGN.md` §5 states with real copy on
  every unhappy path, per §State matrix. A skeleton row matches the populated row's height exactly.
- **A29** Motion animates transform and opacity only, honours `accessibilityReduceMotion`, and
  **never animates opacity from 0 on entry**. Reduce Motion removes the animation and never the
  state change.

---

## Shell copy matrix (A2)

| Surface | State | Headline | Sentence |
|---|---|---|---|
| Discover | awaiting | "Nothing to browse yet" | "Browsing arrives in a later update. Pairing and your library are here now." |
| Triage | awaiting | "Nothing to triage yet" | "Capabilities you have not decided on will collect here once browsing arrives." |
| Queue | awaiting | "You have not sent anything yet" | "Items you send to your Mac appear here with what happened to them at the Mac." |
| Library | awaiting | "Your library lives on your Mac" | "What is installed there will be listed here, read-only." + the A26 narrowing constant |

Library is the surface most likely to be mistaken for an install surface, so it carries the
narrowing sentence as well as the two surfaces A26 requires. None of these four names a Mac, because
three of them are reachable before any Mac is paired and naming one there would be a fabrication.

---

## State matrix — Settings, paired Mac (the feature's data surface)

Real copy, unhappy paths included. Every string is a copy-manifest entry (A27).

| State | Rendered copy |
|---|---|
| **Default** | Row: mac name · `paired 12 Aug · last seen just now`. Banner: "Reachable — items you send arrive now." |
| **Empty** | "No Mac paired yet" / "Pair with the Mac running MCP Router to send it capabilities to review." / action **Pair Mac** |
| **Loading** | Skeleton at the populated row's exact height + "Checking whether your Mac is reachable." |
| **Partial** | Row subtitle reads `paired 12 Aug · last seen unknown`; banner: "Reachable, but it hasn't reported since this app opened, so \"last seen\" is unknown rather than guessed." |
| **Error** | "Can't read this phone's pairing" / "The stored pairing couldn't be opened, so this phone can't reach your Mac. Pair with your Mac again to fix it." / action **Pair Mac** |
| **Success** | Row becomes `paired just now · last seen just now`; banner "Paired. Items you send arrive now." In place, no toast. |
| **Mac unreachable** | "Can't reach it right now. It may be asleep, on another network, or MCP Router may not be running. Anything you send waits here until it's back." |
| **Disabled** | Commit dims in place; reason sits directly above it, and the note below states that queued items send themselves when the Mac returns. |
| **Overflow** | A long Mac name truncates with an ellipsis; the row height does not change and the full value is available on the detail view. |

**On the name of the offline state.** `DESIGN.md` §5 defines Offline as "the router is not running —
say so and offer to start it", which is a statement about the machine the router is on. The phone is
not that machine and cannot start the router remotely, so this feature renders the ninth state as
**Mac unreachable** rather than claiming to be the canonical Offline state, and the phone genuinely
cannot tell asleep from another-network from router-not-running — so the copy names all three rather
than guessing one. A DESIGN.md carve-out making this explicit is a shared-surface change this item
**reports rather than makes**.

### Pairing failure copy (A15)

| Outcome | Headline | Advice | Primary action |
|---|---|---|---|
| Not recognised | — (inline, adjacent to the field) | "That code isn't one your Mac is showing. Check it against your Mac and type it again — the code changes when it expires." | Pair Mac |
| Expired | — (inline) | "That code has expired. Your Mac is already showing a new one — type that, or scan it." | Scan instead |
| Already used | "That code has already been used" | "Each code pairs one device once. Ask your Mac for a new one — MCP Router → Settings → Pair iPhone." | Scan a new code |
| Version mismatch | "<mac> is running an older MCP Router" | "That version pairs differently, so this app can't complete it. Update MCP Router on your Mac, then pair again." | Try again |
| Unreachable | "Can't reach <mac>" | "The code is fine, but nothing answered. Your Mac may be asleep, on another network, or MCP Router may not be running there." | Try again |
| Refused | "<mac> declined the pairing" | "Someone dismissed the request at the Mac. Start pairing again there if that wasn't intended." | Back to Settings |
| Not a pairing code | — (inline) | "That isn't an MCP Router pairing code. Scan the code your Mac is showing under Settings → Pair iPhone." | Scan again |
| Malformed payload | — (inline) | "That code couldn't be read. Ask your Mac for a new one and scan it again." | Scan again |

---

## Triage — 2026-08-14

### Codebase grounding

| Question | Answer, from the tree |
|---|---|
| Where does the iOS app start? | `app/MCPRouterIOS/MCPRouterIOSApp.swift` — one `WindowGroup` holding `FoundationView`, a placeholder that states it is one. This item replaces that body. |
| What is already shared? | `MCPRouterKit` (no UI frameworks, by rule) and `MCPRouterUI` (SwiftUI, linked by **both** apps). `RouterCore` is linked by neither. |
| Is there any pairing code? | None. `RouterTokenFile` explicitly documents that on iOS no token file exists and "the phone reaches the Mac by pairing, which the inbox items own". That comment is the seam this item builds. |
| Is there a token store to reuse? | Yes — `ControlTokenStore` with `KeychainTokenStore` / `InMemoryTokenStore`. The pairing record is richer than a token, so it gets its own store built to the same shape rather than being crammed into the token's. |
| How do existing tests pin copy? | `ControlCopyTests` asserts literals **and** finds them in the design mock. A27 extends that pattern with the surface × state key the flat version lacked. |
| Does the iOS target declare any usage strings? | No. Its entitlements file is deliberately empty and its `Info.plist` carries no purpose strings, so A18 adds the first one. |
| How are tests counted? | `make test` refuses a zero-discovery listing and reads the executed count from the xUnit report. Not routed around. |

### Assumptions — recorded, and each one falsifiable

1. **M6 is not waited for.** Building the transport as a protocol plus a fixture is what F3 did for the
   control client, and it lets I1 land complete and testable now. §Pairing contract makes the seam a
   published contract rather than a placeholder, so M6 implements against something exact. If M6
   lands with a different handshake, the protocol changes and the surfaces do not.
2. **The payload shape is this item's to define**, since M6 does not exist to define it. Versioned, so
   M6 can disagree cheaply, and the version is checked after the envelope so a mismatch is a designed
   outcome rather than a crash.
3. **Crockford Base32 for the code alphabet.** The design representation's specimen codes
   (`K7QN-4FMB`, `K7QN-4FMD`) contain no `I`, `L`, `O` or `U`, so the mock is already consistent with
   it. A free alphabet makes a typed fallback a user cannot reliably type, which is its only job.
4. **`ThisDeviceOnly` Keychain accessibility**, so a pairing credential does not travel in a backup to
   a device the user never paired.
5. **Views live in `MCPRouterUI`**, so the phone's views are testable on the macOS test host. Only
   genuinely device-bound code (the `AVFoundation` camera) sits in the iOS target behind a protocol.
6. **No badges anywhere** (A2) — the alternative reading of the tab bar needs observed data this
   feature does not have.

### Specification Sentinel — product / UX / compliance review

**Accepted and folded into the criteria above.**

- *A pairing code is a credential.* Anyone holding it can queue executable capabilities onto a
  laptop. The scan surface states the caution **before** the camera is useful, and A26 restates the
  narrowing at the moment permission is granted — the one moment the user is thinking about what they
  allowed.
- *Four camera states, not two.* Collapsing not-determined into denied loses the pre-prompt that
  earns the yes; collapsing restricted into denied offers a recovery the user may be unable to take.
- *"Pairing failed" is the failure mode of failure modes.* A15 forces nine, because a user told
  "pairing failed" retries the thing that cannot work — version mismatch and already-used are both
  unfixable by retrying.
- *The countdown is the honesty trap.* Genuinely observed after a scan, genuinely not after typing.
  A14 makes showing it on the typed path a test failure rather than a taste argument.
- *Unpair needs a named consequence.* `DESIGN.md` §9 prefers undo over confirm, but unpairing revokes
  a credential and is not undoable, so it earns the dialog — with the consequence stated rather than
  "Are you sure".

**Considered and deliberately not done.**

- **Notifications.** They belong to I3, and the shared prototype paints their switch track in
  `--live`, which is decorative use of an indicator colour. Out of scope and reported.
- **A live pairing network client.** Would require inventing M6's endpoint. Deferred child instead.
- **`NSLocalNetworkUsageDescription`.** Correctly identified by the out-of-family gate as required
  for the eventual transport — and deliberately **not added here**, because this item opens no
  socket and `SWIFT_PRACTICES.md` §6 requires declaring nothing the target does not use. Adding a
  purpose string for a capability nothing exercises is the unused-declaration failure that rule
  exists to prevent. It is recorded as a binding requirement on the integration child instead,
  together with the `localNetworkDenied` state it needs, so it arrives with the code that uses it.
- **Biometric gating on unpair.** `DESIGN.md` §9 scales friction to blast radius; re-pairing is
  available, so this does not reach it.

### Out-of-family spec gate — codex `gpt-5.6-sol`, effort `max`

Verdict **REJECT**, 3 high / 8 medium / 1 low / 1 confirmation. All 13 addressed above:
accepted in full — 3, 4, 6, 7, 8, 9, 10, 11, 12, 13; accepted in part — 1 (contract published, seam
kept), 5 (iOS-grammar criteria added as A5–A8; the DESIGN.md type-ladder question reported as a
shared-surface change rather than made); **remedy rejected with cause** — 2 (see
`NSLocalNetworkUsageDescription` above). Finding 13 additionally *confirmed* both factual claims
(Crockford's excluded set and normalisation; `ThisDeviceOnly` versus backup migration) and corrected
the restore copy, which is now A23.

---

## Out of scope

Discover content (I2); Triage / Queue / Library content (I3); notifications (I3); the Mac's pairing
side and its inbox (M6); any live network transport; any change to `install.sh` or `src/*.ts` (R4);
shared design tokens, base elements, or `DESIGN.md` itself.
