# Plan — M1: Mac window shell, menu bar, keyboard

**Spec:** `planning/specs/spec-M1.md` (37 clauses, A1–A37)
**Branch:** `ai/m1` · **Worktree:** `.worktrees/M1`
**Tier:** Standard — one feature, three modules touched, no new dependency, no shared-surface edit.

---

## The shape of the change

The shell is **assembly over merged parts**, not new machinery. F2 shipped the tokens, the
control ladder, `selectionFill`, `focusRing`, `IconView` and the nine state containers; F3
shipped the typed client, the fixture double with a named scenario per state, and
`ServerStateTracker`. What M1 adds is the container, the navigation model, the command model and
the state derivations — plus the tests that make the 37 clauses checkable.

The split is forced by one fact: **`app/MCPRouter` is not a SwiftPM target**, so nothing in it
can be reached by `swift test`. Every clause that says "red-green test" therefore requires its
subject to live in `MCPRouterKit` or `MCPRouterUI`.

| Module | What goes there | Why |
|---|---|---|
| `MCPRouterKit` | `Destination`, `MenuCommand`, `ReadoutModel` — pure data and derivation | No UI framework (SWIFT_PRACTICES §8), so the parity tests can read it and the router's tests still import the kit |
| `MCPRouterUI` (`#if os(macOS)`) | `ShellWindow`, `Sidebar`, `Readout`, `ScaffoldPane`, `ShellModel`, scroll-edge | Already scanned by `no-raw-design-values.sh`; reachable by `MCPRouterUITests` |
| `app/MCPRouter` | the `App`, its `Scene`, `.commands` built from the model | Assembly only — nothing here is testable, so nothing decidable lives here |

---

## Phase A — the data models (`MCPRouterKit`)

Pure data, no SwiftUI. This is what makes A11–A13, A19–A21 testable.

**`Sources/MCPRouterKit/Shell/Destination.swift`**
The eight destinations, their group, their order, and their icon name. `CaseIterable` so the
sidebar cannot silently omit one and `allCases` is compiler-generated — the same reason
`ColorToken` is an enum. Groups are `Running` and `Library` as sentence-case literals, plus an
ungrouped tail. Carries the `⌘1`–`⌘7` index for the seven that have one; Settings has none
because it is `⌘,`.

**`Sources/MCPRouterKit/Shell/MenuCommand.swift`**
The command inventory from the spec, as data: menu, title, an optional
`Shortcut(key:modifiers:)` (a value type, *not* SwiftUI's `KeyboardShortcut`, so the kit stays
UI-free), whether it opens a further view (the ellipsis rule), and an `Availability` of
`.enabled`, `.surfaceAbsent` or `.needsServerSelection`. The two disabled reasons are strings on
the enum so no call site can invent a third.

`Space`, `Return` and `Esc` deliberately have **no** `MenuCommand`. A21 asserts that, and the
routing that lets a content surface claim them is Phase C.

**`Sources/MCPRouterKit/Shell/ReadoutModel.swift`**
The at-rest derivation, and the only place a displayed number is computed.

```
running  = servers.filter(\.isRunning).count      // observed
declared = servers.count                          // observed
```

Plus the trace: an array of `(timestamp, running)` samples appended on each poll, evicted at 60s
against an injected clock. Three rules that A15–A18 test directly:
- a failed poll appends **nothing** and evicts nothing — the previous samples stand;
- when the router is not running, `running` and `declared` are `nil`, not `0`;
- the window label reports the span it actually holds, so 20s of samples never says "last 60s".

No memory figure exists anywhere in this type, and there is nothing to compute one from.

**Tests (`MCPRouterKitTests`)** — `ShellDestinationTests`, `MenuCommandTests`,
`ReadoutModelTests`. `MenuCommandTests` carries the two parity tests that matter:
- against the **spec's inventory table**, parsed out of `planning/specs/spec-M1.md` the way
  `ControlCopyTests` walks up to find its mock — so the code cannot define its own oracle (A19);
- against **`DESIGN.md` §8**, parsed out of the document, compared both ways (A20).

`ReadoutModelTests` drives a fake clock across the 60s boundary: a sample at 59s survives, one at
61s is evicted, and a failed poll synthesises nothing.

## Phase B — the shell views (`MCPRouterUI`, `#if os(macOS)`)

**`ShellModel.swift`** — `@MainActor @Observable`. Holds the `any ControlAPIClient`, the
`ServerStateTracker` (**poll-only; stream nil** — the call stream is M2's), the selected
`Destination`, sidebar visibility, the scroll-edge flag and the current `ReadoutModel`. Refreshed
in `.task`, never in `body` (SWIFT_PRACTICES §4).

**`Sidebar.swift`** — the groups, the rows, the badges, the readout. Row height is
`MetricToken.tableRows`; selection uses F2's `selectionFill`; the label is the only element
allowed to truncate, and the badge is tabular and never shrinks (A14). Badges come only from
`needsAttention` and `neverUsed`; Skills and Inbox have none, and a test fails if one appears.

**`Readout.swift`** — the populated form, the skeleton at its own geometry, and the compact
failure form that renders `ControlAPIError.headline` **unchanged** (A28). No paraphrase, no
invented sentence.

**`ScaffoldPane.swift`** — the honest per-destination placeholder, in the F1 voice.

**`ScrollEdge.swift`** — `onScrollGeometryChange(for: Bool.self)` (macOS 15, which is the
package's floor) mapping `contentOffset.y > 0` to the separator. Derived, so A34's unit half is
real; the exercised half is in Phase D.

**`ShellWindow.swift`** — `NavigationSplitView`, sidebar column pinned to
`MetricToken.sidebar`, the toolbar carrying the destination's name as the window title (A9), and
the content zone. Opaque content, glass only on menus (A8).

**Tests (`MCPRouterUITests`)** — the ten `SurfaceState` renderings, the control state matrix
(A27), the token/appearance assertions (A5–A7), motion and the three accessibility settings
(A30, A31).

## Phase C — assembly and keyboard routing (`app/MCPRouter`)

`MCPRouterApp.swift` becomes the scene plus `.commands`, built by walking `MenuCommand.allCases`
— so the menu bar is generated from the model rather than hand-written, which is what makes A19
a real check rather than a coincidence. `CommandGroup(replacing:)` for the standard groups,
`@SceneStorage` for the destination and sidebar visibility (A32), and the AppKit frame autosave
name set through a small `NSViewRepresentable` bridge (A33).

Keyboard routing (A21): the shell installs no handler for `Space`, `Return` or `Esc`, and the
content zone is given first responder ahead of the sidebar for bare keys. Proved by a test
surface in `MCPRouterUITests` that claims all three and receives them.

The `FoundationView` scaffolding F1 shipped is replaced by the real shell; the Debug-only design
gallery `Window` scene stays exactly as it is, because `shells.sh` asserts it is Debug-only in
both directions.

## Phase D — the gates

**`scripts/lint/no-raw-design-values.sh`** gains the A36 boundary check: `URLSession`,
`Process`, `NSTask`, `FileManager`, `Socket` and `NWConnection` are forbidden anywhere in the
shell's files. A dependency graph cannot see a direct call; a source grep can. It follows the
existing script's house rules — an empty file list is a hard failure, never a silent pass.

**`scripts/acceptance/shells.sh`** gains the exercised half of the UI clauses, in the lane it
already established:
- the AX tree carries every destination, both group headers, the readout label (A35);
- the menu bar carries all six menus and the inventory's commands; the disabled ones report
  themselves disabled **and carry their reason** (A19, A22);
- ⌘2 is sent and the sidebar row reports itself selected *and* the toolbar title follows (A23);
- the window is moved and resized, quit, relaunched, and the frame and destination compared
  (A32, A33);
- a scroll is driven and the separator asserted (A34);
- a light-appearance pixel sample (A5).

Its existing exit-code discipline is preserved: 2 for an environment that cannot run the check,
1 for a failed assertion. Collapsing those is how a missing permission gets reported as a broken
app.

## Phase E — proving the gates

Every drift guard added here is **deliberately broken once and watched go red**, then restored,
per SWIFT_PRACTICES §7 — a test that has never failed is not known to work. The ones that matter
most are the two parity tests (they are the oracle for A19 and A20), the readout's eviction
boundary, and the "counts are absent, not zero" assertion, which is the one guarding the
product's central honesty rule.

---

## Order, and what is risky

A → B → C → D → E, because each is the previous one's oracle. The three places this is most
likely to go wrong, named up front:

1. **`NavigationSplitView` will not simply be 33/52/256.** The titlebar and toolbar heights are
   AppKit's, and the sidebar column needs pinning. A1 measures the rendered frames, so a
   mismatch surfaces as a failing test rather than as a drifted window — but expect this to take
   iteration rather than one pass.
2. **Menu generation from a model fights `CommandGroup`'s shape.** SwiftUI's command groups are
   position-based, not list-based. The model may need a per-menu builder rather than one loop.
3. **The exercised keyboard assertions depend on Accessibility being granted.** `shells.sh`
   already distinguishes "blocked" from "failed"; every new assertion must keep that
   distinction or a permission problem will read as a broken shell.

## What this plan does not do

No inert action buttons — offline and unauthorised render their condition and advice with no
control, per the spec's stated deviation 1. No daemon lifecycle, no pairing, no sheets, no
inspector, no menu-bar extra, no board. No edit to `DESIGN.md`, `ColorToken`, `MetricToken`,
`SurfaceState` or `ServersBoardCopy`. No change to `install.sh` or to any `src/*.ts`.

---

## Revision — 2026-08-14, after the out-of-family plan gate

The gate returned **REJECT with 14 HIGH findings**, most of them technically specific and
correct. The corrections below supersede the phases above where they conflict.

### The design errors it caught

**1 · `ServerStateTracker` cannot drive this surface, and M1 must not use it.**
`pollLoop()` is `if let response = try? await client.servers()` — every `ControlAPIError` is
discarded — and with `stream == nil` the phase never leaves its initial `.disconnected`. A shell
built on it therefore cannot tell loading from a successful zero-server poll from offline from
unauthorised, which is precisely what A18, A26 and A28 require. **`ShellModel` owns its own poll
loop directly against `ControlAPIClient`**, keeping the typed error, and the tracker is left to
the boards that want call-record merging. This stays inside A36: the client is still the only
channel.

*This is a defect in merged code, not only an M1 problem — every surface that must render §5's
failure states will hit it. Reported to the orchestrator rather than fixed here, because
`ServerStateTracker` is F3's shared surface.*

**2 · The plan's own text contradicted the implementation on eviction.** It said a failed poll
"evicts nothing"; A16 requires eviction at 60s regardless. `ReadoutModel.applying(_ error:at:)`
as written evicts and appends nothing, which is correct — the plan text was wrong and is
corrected here: **a failed poll appends no sample and still ages the window**, so a minute of
failures leaves an empty trace rather than a frozen one.

**3 · Commands cannot reach the window's model by walking a list.** SwiftUI's `CommandsBuilder`
cannot `ForEach` top-level menus, and `CommandGroup(replacing:)` replaces placements rather than
whole menus. The supported bridge from a menu command to the active scene is
`.focusedSceneValue` plus `@FocusedValue`. Phase C uses that; the menu bar is written as six
explicit builders whose *contents* are driven by `MenuCommand.inMenu(_:)`, which keeps the model
authoritative for titles, shortcuts and availability without pretending the structure is
dynamic.

**4 · The Debug gallery adds a Window-menu item.** A `Window` scene contributes its own entry, so
"exactly the inventory" is false in a Debug build. A19 is scoped to **commands the app declares**;
system-contributed window entries are excluded explicitly, and the exclusion is named in the test
rather than left as a tolerance.

**5 · "Installing no handler" is not routing.** `onKeyPress` only fires for a focused view, and a
focused sidebar row can consume `Space` or `Return` first. A21's honest claim is narrower: the
shell declares no shortcut and installs no shell-level handler for the three keys, and a focused
content surface receives them. The test surface proves that, and nothing claims a routing
mechanism the framework does not have.

**6 · `contentOffset.y > 0` is not a valid top test.** Content insets and rubber-banding put the
resting offset off zero. The scroll-edge flag compares against the scroll view's **resting
baseline captured on first geometry change**, not against a literal zero.

**7 · `@SceneStorage` is not a guaranteed quit/relaunch store.** Apple documents no persistence
timing and destroys it with the scene. A32's exercised half therefore asserts restoration through
the mechanism that does guarantee it — `UserDefaults` written on `scenePhase` change for the
destination, and AppKit frame autosave for the frame — with `@SceneStorage` used only for
per-scene state within a run.

### What the gate correctly showed is not provable as scoped

**Rendered-geometry clauses cannot be met from a SwiftPM test target.** SwiftUI's view tree is
opaque; `MCPRouterUITests` cannot measure a selection inset, a badge displacement, a focus-ring
width or a skeleton's height. And nothing in SwiftUI *sets* the AppKit titlebar and toolbar
heights — 33 and 52 are the system's values, which `DESIGN.md` recorded rather than chose.

So A1, A2, A4, A14, A24 and A29 split in two, and each half says what it can actually prove:

- **Token-level, in unit tests:** the view reads `MetricToken.sidebar` / `.tableRows` /
  `.selectionRadius` / `.selectionInset` / `.focusRing` rather than a literal, and the raw-values
  gate proves no literal was written.
- **Rendered, in `scripts/acceptance/shells.sh`:** element frames read from the **accessibility
  tree** (`AXPosition`, `AXSize`) of the running app, which is a real measurement lane the repo
  already owns, plus the existing pixel sampler for colour.

A claim that a rendered inset was measured from a SwiftPM test would be false, and is withdrawn.

**A27 is re-scoped, and the gap is reported rather than fixed.** It required default / hover /
focus-visible / active / disabled on every control. F2's merged `ProminentButtonStyle` and
`StandardButtonStyle` carry only a pressed scale and a disabled tier — no hover, no
focus-visible. Adding those means editing the **shared** design system, which this runner is
directed not to do. A27 therefore covers only controls M1 itself ships, and the shared gap is
reported to the orchestrator as a change for F2's owner.

**A3's lint extension is wider than stated.** The existing script catches component colours and
numeric font sizes but not `.frame(height: 24)`, `.padding(8)` or `cornerRadius: 8`. The
extension adds those, scoped to the shell's own files so no merged gate changes meaning.

### Sequencing, corrected

The gate is right that the order was backwards: gates written in D and broken in E means the
oracle does not exist while its subject is built. Corrected order — **each unit lands with its
test and its red-green proof in the same step**, and the exercised acceptance assertions land
with the view they exercise. There is no separate "prove the gates" phase, because a gate proven
a phase later is a gate that was decoration while the code was being written.

---

## Revision — 2026-08-14, after F4 merged

The plan gate's finding 1 above — *"`ServerStateTracker` cannot drive this surface, and M1 must
not use it"* — was correct when it was written and is **now obsolete**. It is superseded here
rather than deleted, because the reasoning is what makes the change checkable.

F4 shipped the fix the finding asked for. `LoadState` is now `.loading` / `.loaded` / `.failed`
/ `.stale`, `pollLoop()`'s `try?` is gone so the typed `ControlAPIError` survives, and a tracker
constructed with no stream reports `StreamCondition.notConfigured` instead of pinning at
`.disconnected`. Every distinction A18, A26 and A28 need is therefore expressible through the
tracker, and the justification for a second poll loop has expired with it.

**`ShellModel` now reads the router through `ServerStateTracker` and owns no loop of its own.**
Two independent pollers against one router is the duplication the tracker exists to remove, and
it is how the shell and the boards would come to disagree about what is running.

### The one judgment the shell adds, and why it is not the tracker's

`.stale` is the case F4 made expressible and the case that needed a decision: an earlier poll
succeeded, the refresh has since broken, and the servers behind it are real. The shell splits
the two halves rather than taking the state whole:

- **Badges keep those servers.** `needsAttention` and `neverUsed` are properties of the declared
  configuration. They were genuinely observed and nothing about a failed refresh unobserves them.
- **The readout counts go absent.** "3 running" is a present-tense claim about a router that is
  not currently answering. Rendering the last known figure as though it were current is a quieter
  lie than a zero, but the same kind, and A18 forbids it.

`ShellIntegrationTests.staleKeepsBadgesAndDropsCounts` asserts both halves in the same state, so
neither can be satisfied by dropping the other.

### The guard that was inverted

`theTrackerIsNotUsed` — a source grep asserting the shell did **not** construct a tracker — has
become `theTrackerIsTheOneReader`, asserting it does, and that no `Task.sleep` has grown back
beside it. Both directions were proven by mutation on 2026-08-14: retaining the counts on
`.stale` failed the readout assertions, and re-growing a sleep in `run()` failed the grep.

### What did not change

`ReadoutModel` gained an `applying(_ servers: [MCPServer], at:)` overload, because
`LoadState` carries `[MCPServer]` rather than a whole `ServersResponse` — deliberately, since a
`.stale` snapshot corrected by call records is no longer any single response. The
`ServersResponse` overload delegates to it; nothing in the derivation ever read `port`, `idleMs`,
`since` or `pendingAuth`. A36 is unaffected: the tracker speaks the same loopback control API
through F3's client, and the shell still opens no socket, no file and no process.
