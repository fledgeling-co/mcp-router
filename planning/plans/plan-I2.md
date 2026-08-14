# plan-I2 — iPhone: Discover and detail

**Spec:** `planning/specs/spec-I2.md` (32 criteria, A1–A32).
**Design authority:** `DESIGN.md`. **Design representation:** `design/mocks/i2-phone-discover.html`.
**Practices:** `planning/practices/SWIFT_PRACTICES.md` (binding), `CODING_PRACTICES.md`,
`NEW_PROJECT_BEST_PRACTICES.md`.
**Branch:** `ai/i2`, worktree `.worktrees/I2`, rebased onto `main` @ `5b4215b`.

**Plan tier: Large.** Two data surfaces with nine states each, a new copy manifest, a new
persisted write port, a derivation layer that must not fabricate, and one modification to a
merged shared type. Sized Large because A1 and A7 are *negative* criteria over the whole
feature — they are only checkable if the derivation is a single funnel every rendered string
passes through, and that shape has to be designed in rather than discovered in gap-fix.

---

## 1 · What already exists, and what this plan may not touch

Read out of the tree, not assumed.

| Thing | Where | This plan's relationship |
|---|---|---|
| `RegistryEntry`, `RegistrySearchResponse`, `RegistryInstall`, `RegistryRequirement` | `Kit/Control/RegistryModels.swift` | **read-only.** Every field I2 renders already exists. |
| `ControlAPIClient.searchRegistry(query:limit:)` | `Kit/Control/ControlAPIClient.swift:134` | **called, not changed.** No new endpoint (A11). |
| `FixtureControlAPIClient.searchRegistry` | `Kit/Control/FixtureControlAPIClient.swift:250` | ignores `query` and always returns `registry-search.json`. Adequate for Default; **insufficient for Empty-on-query, Partial and truncation**, so this plan adds a test double (§6.1) rather than widening the shared fixture. |
| `registry-search.json` | `Kit/Control/Fixtures/` | **read-only.** 3 results, `merged: 5`, `warnings: []`, newest `updatedAt` 2025-11-19 (the field **Recently changed** ranks on), newest `pushedAt` 2025-11-28. |
| `PhoneShell.Tab.discover → AwaitingTab` | `UI/Phone/PhoneShell.swift:144` | **the one line this feature replaces** (A32). |
| `PhoneMetric` | `UI/Phone/PhoneMetric.swift` | **extended**, and it stays the only file under `Phone/` writing geometry (A31). |
| `PairingCopy` | `Kit/Pairing/PairingCopy.swift` | **read-only except**: `neverInstalls` is consumed verbatim (A20). `DiscoverCopy` is a *sibling*, never an extension (spec §Codebase grounding). |
| `ConnectionState` | `Kit/Pairing/PairingModels.swift:114` | **the one merged type modified**: `canQueue` added, `canSend`'s doc comment narrowed (A19). Additive. |
| `PhoneProminentButtonStyle` / `PhoneStandardButtonStyle` | `UI/Phone/PhoneButtonStyle.swift` | reused for the commit. |
| `PhoneSourceGuardTests` | `Tests/MCPRouterUITests/` | scans `UI/Phone/**`; the new files join its set automatically and must pass it (A31). |

**Out of bounds for this plan:** `src/*.ts`, `install.sh`, `ColorToken` (the missing
`--attnWash`/`--attnLine` stay reported, not added — spec §Out of scope), `Icon` (its inventory
is count-pinned by F2; `.discover` already exists), `BoardRegistry` (Mac-only), and any PATCH
path — **this feature performs no PATCH at all.**

---

## 2 · Architecture — one funnel, so the negative criteria are checkable

A1 ("no rate, delta or percentage anywhere") and A7 ("every numeric string maps to a named
`RegistryEntry` field") are claims about *everything rendered*. A test cannot chase them across a
view hierarchy. So the design constraint that shapes every file below:

> **No SwiftUI view under `Phone/Discover/` formats a number, a date or a count.** Views render
> `String`s that a `DiscoverPresentation` value already produced. Every numeric string in the
> feature is therefore emitted by one file, and A1/A7 become assertions over that file's output for
> an enumerated input set — plus a source-scan guard that no view calls a formatter.

This is the same argument `PhoneSourceGuardTests` already makes for geometry, applied to numbers,
and it is why the presentation layer is a value type rather than logic inside the views.

### File inventory

**New, in `MCPRouterKit`** (no SwiftUI — SWIFT_PRACTICES §8 keeps Kit importable by router tests):

| File | Contents |
|---|---|
| `Kit/Discover/DiscoverCopy.swift` | The copy manifest. `enum Key: String, CaseIterable`, `Entry`, `entry(_:)`, `narrowingKeys`. Exhaustive `switch` over the enum (A28). |
| `Kit/Discover/DiscoverPresentation.swift` | **The funnel.** `RegistryEntry` → rendered strings. Owns `useCountText`, `changedText`, `lastCommitText`, `truncationText`. The only file in the feature permitted to format. |
| `Kit/Discover/DiscoverBands.swift` | `Band` enum, `RecencyWindow` enum, band membership + ordering (A2, A4). Pure functions over `[RegistryEntry]`. |
| `Kit/Discover/CapabilityPlate.swift` | The five derivations (A13) as `PlateLine` values with `Severity`. Pure `RegistryInstall?` → `[PlateLine]`. |
| `Kit/Discover/DiscoverSurfaceState.swift` | The nine states as one enum per surface (list, detail), plus `WarningClass` (A25) and `CommitState` (the seven, A16–A21). |
| `Kit/Discover/CapabilityQueue.swift` | `QueuedCapability`, `protocol CapabilityQueueWriter`, and `FileCapabilityQueueWriter` (A22). |
| `Kit/Discover/DiscoverModel.swift` | `@MainActor @Observable`. Owns search text, window, results, state. Calls the client; never formats. |

**New, in `MCPRouterUI`** (all under `UI/Phone/Discover/`, all scanned by the source guard):

| File | Contents |
|---|---|
| `DiscoverScreen.swift` | `NavigationStack` root: search field, window control, band sections or flat list, the nine list states. |
| `DiscoverRow.swift` | One row: tile, name, description, the one figure. Height = `PhoneMetric.row` as a **minimum** (A29). |
| `DiscoverSkeletonRow.swift` | Loading, using the row's own height modifier (A24, DESIGN §5). |
| `DiscoverBandSection.swift` | Header, note, per-band empty state (A3, A5). |
| `DiscoverWindowControl.swift` | The four options; dims in place with its reason (A4, A10). |
| `CapabilityDetailView.swift` | Detail: artwork, name, description, chips, plate, commit. |
| `CapabilityPlateView.swift` | Renders `[PlateLine]` + the literal invocation in monospace (A12). |
| `QueueCommitBar.swift` | The seven commit states (A16–A21), each carrying `neverInstalls`. |

**Modified:**

| File | Change |
|---|---|
| `Kit/Pairing/PairingModels.swift` | `+ canQueue`, narrow `canSend`'s comment (A19). |
| `UI/Phone/PhoneShell.swift` | `.discover` resolves to `DiscoverScreen`; `awaitingKey` returns `nil` for it (A32). Injection point for the client, connection state and queue writer. |
| `UI/Phone/PhoneMetric.swift` | New named values (§5). |
| `app/project.yml` | Only if a new directory needs declaring; the target globs `Sources/**`, so verify before editing. |

### Delivered shape — where the build diverged from this inventory, and why

Three deviations, recorded here rather than back-fitted into the tables above, so the plan stays a
record of what was planned and this stays a record of what shipped.

1. **`DiscoverCopy.swift` is six files, and `Key` is a nested sum type rather than
   `enum Key: String, CaseIterable`.** One flat enum reached 47 cases, which put `entry(_:)` at
   cyclomatic complexity 47 against a cap of 10 — and the only ways to keep one file were a
   file-scope lint disable or a raised limit, both barred. `Key` now sums seven per-element
   sub-enums (`BandKey`, `WindowKey`, `UnitKey`, `ListKey`, `DetailKey`, `PlateKey`, `CommitKey`,
   `QueueFailureKey`), each with its own `entry` beside its own copy in
   `DiscoverCopyKeys/Controls/List/Detail/Commit.swift`. The property A28 turns on is unchanged:
   the `switch` is still exhaustive, so an unhandled key is still a build failure rather than a
   runtime nil. Each sub-enum keeps its `String` raw value (that is what `key.name` renders in a
   test failure); only the outer `Key` drops it, because a nested case has no single raw value.
   `DiscoverCopyTests` pins `allCases.count == 53` so a whole element type added to `Key` and
   omitted from `allCases` is caught rather than silently uncovered.
2. **`DiscoverModel.swift` is at `UI/Phone/Discover/`, not `Kit/Discover/`.** It is
   `@MainActor @Observable` holding `@Bindable` state for SwiftUI, and Kit is deliberately
   SwiftUI-free (SWIFT_PRACTICES §8) so the router tests can import it. Its testable half did move
   to Kit: state resolution is `DiscoverListState.resolve(response:query:)` in
   `DiscoverSurfaceState.swift`, so the nine-state decision is a pure function a Kit test asserts
   rather than a method only a view can reach.
3. **`DiscoverSkeletonRow` and `DiscoverWindowControl` are not their own files.** They are declared
   in `DiscoverRow.swift` and `DiscoverBandSection.swift`, beside the view each one mirrors —
   the skeleton is sized from the row's own type roles, and the control is only ever drawn as that
   section's header. The source-scan guards assert `files.count >= 6` rather than an exact count,
   so the inlining does not weaken them.

---

## 3 · Phase A — the Kit layer (no UI, fully testable)

Order matters: everything downstream reads these types.

**A.1 `DiscoverSurfaceState.swift`.** Three enums first, because they are the vocabulary.

```
enum DiscoverListState: Sendable, Equatable {
    case loading, defaultPopulated, emptyNoQuery, emptyQuery(String),
         partial([WarningClass]), error(ControlAPIError), offline(mac: String)
}
```
`success` is **absent by construction** — the list has no commit (spec state matrix). Detail's
`empty`, `loading` and `error` are likewise absent from `DetailState`, and each omission carries a
one-line comment naming A11 as the reason. A test asserts the case counts, so a later hand adding
a plausible case has to argue with a comment.

`WarningClass`: `officialDown, smitheryDown, githubLimited, unrecognised(String)`. Classified by
**prefix match** on the free-text wire strings, with the fragility stated in a doc comment (A25),
and `unrecognised` carrying the warning verbatim so nothing is dropped.

`CommitState`: the seven from the spec's commit table. `Sendable`, `Equatable`, `CaseIterable`
where the associated values allow, so the test can enumerate.

**A.2 `DiscoverCopy.swift`.** Every string from the spec's three matrices, keyed. `Key` is
`CaseIterable`; `entry(_:)` is an exhaustive switch with **no `default`** — a tenth key then fails
to compile rather than shipping blank (A28). Substitution follows `PairingCopy`'s established
shape (`{mac}`, `{count}`, `{query}`, `{window}`, `{name}`, `{reason}`), and `{reason}` renders
from a **closed enum**, never a passthrough of the router's error body (A28).
`narrowingKeys: Set<Key>` names the seven commit states (A20).

**A.3 `DiscoverPresentation.swift`** — the funnel.

- `useCountText(_ entry:) -> String?` → `"2,984 sessions on Smithery"` (A6). `nil` when
  `useCount` is nil — **never "0 sessions"**, which would assert a measurement (A2).
- `changedText(_:)` → a date from `updatedAt`. Copy never names *what* the stamp means; the
  band note does that once (A3, H5).
- `lastCommitText(_:)` → from `pushedAt`; `nil` → Detail renders the A26 fact line.
- `starsText(_:)`, `forksText(_:)` → `nil` when absent.
- `truncationText(shown:limit:)` → non-nil **only** when `shown == limit` (A8). `sources.merged`
  is never rendered.

Formatting uses `Foundation` locale-aware formatters; dates parse ISO-8601 and **fail to a `nil`
string rather than to `Date()`** — a fallback to "now" would display a date the router never
reported. There is no arithmetic between two entries anywhere in this file, and none between two
values of one field. That absence is what A1 asserts.

**A.4 `DiscoverBands.swift`.**

```
enum Band { case mostUsed, recentlyChanged }
enum RecencyWindow: CaseIterable { case anyTime, ninety, thirty, seven }   // anyTime default (A4)
```
`members(of:in:window:)` — `mostUsed` filters to `useCount != nil` then sorts desc; an entry
without the field is **absent, never zero** (A2). `recentlyChanged` filters to a parseable
`updatedAt`, applies the window, sorts desc. The window applies to `recentlyChanged` **only**; a
test asserts `mostUsed` membership is byte-identical across all four windows (A4).

**A.5 `CapabilityPlate.swift`.** `lines(for install: RegistryInstall?) -> [PlateLine]`, the five
derivations in the spec's table order, **accumulating** — a `stdio` entry needing a secret returns
both lines (A13). `plateSeverity` is `.attn` if any line is; the remote line names the host parsed
from `install.url` and is a **fact** line (A13). `install == nil` returns the single "neither index
says how this runs" line and is what `CommitState.noDescriptor` keys on (A17).

**A.6 `CapabilityQueue.swift`.**

```
struct QueuedCapability: Codable, Sendable, Identifiable, Equatable {
    let id: String            // RegistryEntry.id — the idempotency key
    let displayName: String
    let source: RegistryEntry.Source
    let install: RegistryInstall?
    let queuedAt: Date
}
protocol CapabilityQueueWriter: Sendable {
    func enqueue(_ item: QueuedCapability) async throws
    func contains(_ id: String) async -> Bool      // drives the "Queued" commit state
}
```
`FileCapabilityQueueWriter` is an `actor` writing JSON to the app container. Three criteria
(A22): survives relaunch; enqueueing the same `id` twice leaves one row; **a refused write
throws** — no `try?`, no silent success. That last one is I1's `PairingStorageFailureTests`
precedent and gets its own red-green proof (§6.3). `install` is stored so Triage can show what is
being reviewed; it is data at rest for a human to read, never executed by this app, and the phone
has no path that could execute it.

**A.7 `ConnectionState`** — additive:
```
/// Whether a surface that sends may commit **now**.
public var canSend: Bool { self == .reachable }
/// Whether a surface that queues locally may commit at all. Queueing succeeds with the Mac asleep.
public var canQueue: Bool { self != .neverPaired }
```
The comment narrowing is not cosmetic: A19 exists because the obvious implementation of A18 binds
to `canSend` and silently ships I1's disable-when-unreachable behaviour while looking right.

**A.8 `DiscoverModel.swift`.** `@MainActor @Observable`. Holds query, window, `[RegistryEntry]`,
`DiscoverListState`, `sources`, `warnings`. `search()` is `.task`-driven and debounced; it maps
`ControlAPIError.routerNotRunning` to `.offline` **before** any generic error path (A27,
SWIFT_PRACTICES §3). It formats nothing.

---

## 4 · Phase B — the views

Built after Phase A is green, so every view is assembling strings that already exist.

**B.1 `DiscoverRow`** — tile (`PhoneMetric.tile`/`tileRadius`), name (truncates on one line, A29 /
Overflow), description, and the one figure in **monospace** (A6, DESIGN §2). Height is
`.frame(minHeight: PhoneMetric.row)` — a *minimum*, so it grows with Dynamic Type; the skeleton
uses the identical modifier so nothing jumps (A29, A24). Stable identity is `entry.id`
(SWIFT_PRACTICES §4).

**B.2 `DiscoverBandSection`** — sentence-case header (DESIGN §3.2), the note as one quiet
secondary sentence (A3, DESIGN §6), and its own empty state when that band alone is empty (A5).

**B.3 `DiscoverWindowControl`** — a pop-up button (double chevron: it shows a value — DESIGN §3.6).
During search it **dims in place** with `windowDisabledInSearch` beside it, never hidden (A10,
DESIGN §3.4).

**B.4 `DiscoverScreen`** — searchable; empty query → bands, non-empty → one flat ranked list
(A10). Renders all nine list states from `DiscoverListState`. Both Empty states carry
`Icon.discover` at `PhoneMetric.emptyGlyph`, matching how `AwaitingTab` draws it (the accepted half
of the gate's M6 finding). Safe-area respected top and bottom (A29).

**B.5 `CapabilityPlateView`** — drawn above the commit, never behind a disclosure control (A12).
Amber lines carry their reason **in words**, so colour is never the only signal (DESIGN §2,
accessibility). Ends with the literal invocation in monospace — `command + args` joined for
`stdio`, the URL for remote — scrolling horizontally rather than wrapping mid-token (Overflow).
The border reads `PhoneMetric.tintedBorderOpacity`, as I1 does, because `--attnWash`/`--attnLine`
are still absent from `ColorToken` and adding them is a shared-surface change this feature reports
rather than makes.

**B.6 `QueueCommitBar`** — one prominent accent action per view and this is it (DESIGN §3.4).
Verb-first, no ellipsis (A16). Label switches on `CommitState`: **"Send to Mac"** when reachable,
**"Save for your Mac"** when not (A18). Disabled only for `neverPaired` and `noDescriptor`, dimming
in place with the reason above it (A17). All seven states render
`PairingCopy.neverInstalls` verbatim (A20). No copy promises an automatic send (A21).

**B.7 `CapabilityDetailView`** — pushed from a row; performs no fetch (A11). Fact chips are
exactly `source`, `archived`, `stars`-where-present; **`verified` is never rendered** (A15). The
`installed` flag renders as the name match it is: "A server called {name} is already declared on
{mac}" (A23). Long name wraps to two lines in the title, truncates in the collapsed nav bar.

**B.8 `PhoneShell` wiring (A32).** `.discover` resolves to `DiscoverScreen`, and `awaitingKey`
returns `nil` for `.discover` so the awaiting branch cannot be re-entered. The shell gains the
client, connection state and queue writer, defaulted to the fixture/in-memory implementations so
existing previews and the macOS host tests keep constructing it unchanged. **This is the criterion
that makes the feature real rather than a compiling type**, and it is verified behaviourally in
Phase 6, not by the compiler.

**Motion (A30):** transform and opacity only; honours `accessibilityReduceMotion`; the commit bar
rises on transform (DESIGN §7); nothing fades from 0 on entry.

---

## 5 · `PhoneMetric` additions (A31)

Every new geometry value lands here with its DESIGN.md trace, and nowhere else:
`detailTile: 64` / `detailTileRadius: 14` (DESIGN §4 detail tiles), `plateRadius` (concentric with
`cardRadius` per DESIGN §2), `chipHeight`, `chipRadius`, `bandHeaderSpacing`, `plateLineSpacing`,
`invocationPadding`. `PhoneSourceGuardTests` fails the build if any lands in a view instead.

---

## 6 · Phase C — tests

### 6.1 Test double

`DiscoverTestClient` in `Tests/MCPRouterUITests/`, conforming to `ControlAPIClient`, returning a
caller-supplied `RegistrySearchResponse` and recording the `(query, limit)` it was asked for. It
exists because the shared `FixtureControlAPIClient` ignores `query` and has empty `warnings` — it
cannot produce Empty-on-query, any Partial, or truncation. Widening the shared fixture would change
a merged surface other features assert against; a local double does not.

### 6.2 The suites

| Suite | Covers | Shape |
|---|---|---|
| `DiscoverCopyTests` | A28, A20 | Every `Key` has non-empty copy; pinned literals for all three matrices; `narrowingKeys` covers seven; every `{token}` in a template is enumerated. |
| `DiscoverHonestyTests` | **A1, A7** | Renders every string the feature can emit over an enumerated entry set × states; asserts none matches `%`-suffix or a delta pattern; asserts every numeric substring traces to a named field. Plus a source scan: no view under `Phone/Discover/` calls a formatter. |
| `DiscoverBandTests` | A2, A4, A5 | Missing `useCount` → absent, not zero; `mostUsed` identical across all four windows; window filters `recentlyChanged` only; per-band empty. |
| `CapabilityPlateTests` | A12–A15 | The five derivations; accumulation (stdio + secret + archived → three lines); severity precedence; remote names the host; `verified` never rendered. |
| `DiscoverStateTests` | A24–A27 | Nine states per surface, or a named structural absence; the three warning classes by prefix; an unknown warning renders verbatim; `routerNotRunning` → Offline, not a generic error. |
| `CommitBehaviourTests` | A16–A21 | Seven states; **live and relabelled when `.notReachable`**; disabled only for the two cases; `canQueue`/`canSend` are distinct; no copy promises an automatic send. |
| `CapabilityQueueTests` | A22 | Survives relaunch; double-enqueue idempotent; **a refused write throws and never renders success**. |
| `DiscoverAccessibilityTests` | A29, A31 | 44pt on the hosted tree; row grows with Dynamic Type xSmall–AX3; new files pass the source guard. |
| `DiscoverShellTests` | A32 | `.discover` resolves to `DiscoverScreen`, and `awaitingKey` is `nil` for it. |

### 6.3 Red-green proofs (SWIFT_PRACTICES §7)

A test that has never failed is not known to work. Three guards get a deliberate break, watched
red, restored, and recorded in the evidence file:

1. **A1/A7 honesty scan** — add a `"+12%"` string to a copy entry; the scan must go red.
2. **A18 commit liveness** — bind the button to `canSend`; `CommitBehaviourTests` must go red.
   This is the exact regression A19 exists to prevent.
3. **A22 refused write** — wrap the writer's throw in `try?`; the queue test must go red.

---

## 7 · Phase D — gates

`make all` (build, typecheck, SwiftLint, SwiftFormat, `swift test` with the non-zero-count check
from SWIFT_PRACTICES §7). Then the in-family completeness critic. Then Phase 6 acceptance.

**Acceptance scope (testing etiquette).** I1's shell and pairing are merged and evidenced —
**not re-verified**. This feature changes exactly one destination, so the pass drives **the
Discover tab and its detail push, and nothing else**. One simulator boot, one pass, quit. Never a
parallel Xcode build — I1 recorded the simulator being OOM-killed by exactly that. Skips are
reported by name in `planning/evidence/I2-acceptance.md`, which is read **before** anything is
launched and appended to, never rewritten.

`codex: usage limit → claude (downgrade)` — account-limited to 20 Aug 2026, and `codex exec`
**exits 0 on that limit**, so no gate is keyed on an exit code. All three out-of-family gates run
in-family with a fresh adversarial `claude -p` opus-5 reviewer, and the weakness is recorded
alongside the evidence.

---

## 8 · Criterion → work traceability

| Criteria | Landed by |
|---|---|
| A1, A7 | `DiscoverPresentation` (the funnel) + `DiscoverHonestyTests` + the source scan |
| A2, A4, A5 | `DiscoverBands`, `DiscoverBandSection`, `DiscoverWindowControl` |
| A3, A6, A8 | `DiscoverCopy` notes, `DiscoverPresentation` |
| A9, A10 | `DiscoverScreen` searchable + `DiscoverWindowControl` dim-in-place |
| A11, A15, A23, A26 | `CapabilityDetailView` |
| A12, A13, A14 | `CapabilityPlate` + `CapabilityPlateView` |
| A16–A21 | `QueueCommitBar`, `CommitState`, `ConnectionState.canQueue` |
| A22 | `CapabilityQueue` + `FileCapabilityQueueWriter` |
| A24, A25, A27 | `DiscoverSurfaceState`, `WarningClass`, `DiscoverModel` error mapping |
| A28 | `DiscoverCopy` exhaustive switch + three-way assertion |
| A29, A30, A31 | `PhoneMetric`, row/skeleton min-height, motion modifiers, source guard |
| A32 | `PhoneShell` wiring + behavioural acceptance |

---

## 9 · Risks

1. **The funnel leaks.** A view formats a count directly and A1/A7 pass anyway because the test
   only reads the presentation layer. Mitigated by the source scan being *part of* the honesty
   suite, not a separate optional check.
2. **`canSend` is used by reflex.** The single likeliest defect in this feature, and the reason
   A19 is a criterion. Mitigated by red-green proof 2.
3. **The fixture's newest `updatedAt` (2025-11-19) is outside every offered window.** With `anyTime`
   as the default (A4) the first render is populated; any *other* default would ship a designed-in
   empty band. Tests must not "fix" this by widening the fixture — the fixture is the recorded
   truth, and A5's per-band empty state is exactly what it exercises. The stamp that matters is
   `updatedAt`, because that is the field **Recently changed** ranks on; the fixture's 2025-11-28 is
   a `pushedAt` on a different entry and does not bear on this risk either way.
4. **Detail's three structurally-absent states** read as an oversight to a later reviewer.
   Mitigated by each omission carrying a comment naming A11, and by a test asserting the case
   counts.
5. **Simulator contention.** Other runners hold worktrees in this repo. One boot, one pass, quit.

## 10 · Deferred children (reported, not registered)

Feature ids are the orchestrator's to allocate; these are requests.

- **A registry snapshot store** on the router — the only thing that would make a real trend band
  computable, and the precondition for the brief's third band.
- **A `sort` parameter on `/registry/search`** — would let a band make an index-wide claim honestly
  instead of being scoped to the results shown (H4).
- **Fix the `installed` display-name collision** in `src/control.ts:486-489` — it false-positives on
  a shared last path segment and misses on case. A23 keeps the copy honest meanwhile.
- **Flush-on-reachable** — no item owns it; A21 keeps the copy from promising it.
- **`--attnWash` / `--attnLine` in `ColorToken`** — a shared design-token change, already reported
  by I1, still absent.
