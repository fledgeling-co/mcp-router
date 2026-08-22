# plan-M15 — Settings becomes its own window

Spec: `planning/specs/spec-M15.md` · brief `planning/features-to-triage/M15-settings-window.md`
Design of record: `design/mcp-router-console.html` (settled 2026-08-22, `8863264`)
Plan size: **Large**. A new `Settings` scene, a new `MCPRouterUI/Settings/` directory with a
seven-case pane enum and seven pane views, the removal of a `Destination` case with eleven readers,
a new fidelity surface, and edits to two acceptance scripts, one lint allowlist and one design
document. Nineteen requirements across five layers.

Baseline: `8863264`, tree clean apart from `planning/test-campaign/` and `design/marketing-src/`,
neither of which this item touches.

---

## 1 · Task

Move Settings out of the console's source list and into a SwiftUI `Settings` scene: its own
titlebar with minimise and zoom dimmed in place, its own 200pt source list of seven panes, its own
detail scroll, no Save button, reached from `Settings…` in the app menu and `⌘,`. The console's
navigation list loses its ungrouped tail and ends at Cleanup. Nothing a person can set today stops
being settable.

The item is not "draw seven panes". It is three things that each have their own failure mode: a
**scene** the app has never declared, an **enum case removal** that eleven things read, and a
**content decision** about which of the mock's thirty rows the product can honestly draw.

## 2 · Approach

Four layers, in dependency order. `MCPRouterKit` gains the pane enum and every pane's copy, because
`SettingsPresentation` is already where this pane's assertions live and `app/MCPRouter` is not a
SwiftPM target. `MCPRouterUI/Settings/` gains the window body, the source list and the seven panes,
reusing `SettingsCard` / `SettingsRow` / `SettingsGroup` verbatim rather than authoring a second
card. `app/MCPRouter/MCPRouterApp.swift` gains a fourth scene and swaps its `.appSettings` item for
a `SettingsLink`. Then the destination removal, which is last because everything above must compile
first.

**The analogue to follow is the shipped Settings board itself.** `SettingsBoard.swift` already
solves this pane's hard parts — a derived metric enum that keeps `no-raw-design-values.sh` green,
`SettingsRow`'s skeleton at the populated row's exact height, `routerHelp`'s "read from the router,
not set here" precedent, and a `TokenStatus` with no field a secret could occupy. This item
re-houses that work; it does not re-derive it.

## 3 · Requirements & Decisions

### 3.1 Functional

1. A `Settings` scene exists and `⌘,` opens it. *(brief; `DESIGN.md` §8)*
2. Minimise and zoom are dimmed in place, close is live. *(brief)*
3. Escape closes the window. *(brief)*
4. Seven panes, in the mock's order: Router, Harnesses, Session analyst, Updates, Security,
   Menu bar, Advanced. *(spec §2 assumption 1 and 3 — the mock's `data-pane` order, not the
   brief's prose)*
5. Exactly one pane is selected; the detail body matches it. *(brief's acceptance line)*
6. The settings source list owns its own selection, independent of the console's. *(brief)*
7. The console's navigation list no longer carries Settings. *(brief)*
8. Today's four groups — router facts, menu bar, warm set, control token — are all still reachable.
   *(spec §2 assumption 2)*
9. With the router stopped the window opens and says so. *(spec §2 assumption 7; mock's `v-empty`)*
10. Every control applies on change; there is no Save button. *(brief)*
11. A sheet opened from a pane attaches to the Settings window. *(brief; no sheet ships here — see
    §8)*

### 3.2 UI/UX

12. Titlebar 33pt (`MetricToken.titlebar`), source list 200pt, detail scrolls independently.
13. Source-list rows use the console's row metrics and its accent fill at radius 8, from a shared
    row view rather than a second implementation. *(brief)*
14. Each pane opens with its name and one line saying what it governs, then grouped inset cards:
    label left, control right on a shared axis, inset hairlines between rows.
15. Sentence case throughout; no case transform. *(`DESIGN.md` §3.2)*
16. The window title is `Settings`. *(`DESIGN.md` §3.7)*

### 3.3 Constraints and decisions

17. **Every dimension routes through `MetricToken` or a derivation of it.** The brief quotes 33pt,
    200pt and radius 8; `scripts/lint/no-raw-design-values.sh`'s geometry rule fails on a non-zero
    literal in `.frame(width:…)`, `.padding(`, `cornerRadius:`, `lineWidth:`, `spacing:` or
    `radius:`. *(spec §3.7, accepted from the out-of-family review)*
18. **The source list is `DESIGN.md`'s 256pt, and the mock's 200 is a declared disagreement.**
    Not "we could not derive 200". A settings source list *is* a sidebar, `DESIGN.md` §2 specifies
    `Sidebar 256pt`, and `MetricToken.sidebar` is that value — so using it is following the design
    authority for geometry, which decision 23 keeps with `DESIGN.md` until M21 moves it. The mock
    draws 200 and its own `mac-craft:metrics` block carries `sidebar 256px` and **no 200 of any
    name**, so the mock disagrees with itself as well as with the document. `DesignTokenParityTests`
    compares `MetricToken`'s name set against §2's table for **exact equality in both directions**
    (`DesignTokenParityTests.swift:118-126`), so a `settingsSidebar` case without a new §2 row
    reddens it, and authoring that row is M21's substance.
    The third option — `.navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)` — was
    weighed and loses twice: three geometry literals where the rule permits none, and a range is
    three numbers picked by eye where the complaint was one.
    The 56pt difference is declared in the fidelity manifest's `note` and reported by the geometry
    layer on every run. If it reads badly on glass, that is a finding with a number attached and an
    owner, which is a better position than a token invented to make it disappear.
19. **`⌘0` is not built.** `Destination.selectionDigit`'s own docstring already rejects a second
    shortcut for Settings — *"giving it a digit too would put two shortcuts on one command, which is
    how a menu bar starts teaching two different habits for the same thing"* — and `DESIGN.md` §8 is
    where a chord is granted, not a `switch`. §8 currently states eight bindings and
    `MenuCommandTests.designSectionEightParses` pins that count; a ninth row is a `DESIGN.md` edit
    plus a test edit for a shortcut the repo has already argued against. M20 owns the accelerator
    map (`⌘1`–`⌘9` in the mock's store-first order) and is where `⌘0` belongs if it is wanted.
    Surfaced as a narrowing in §11.
20. **No Window-menu item is declared.** `MCPRouterApp.swift:57-60` records the precedent: a
    `Window` scene "is listed in the Window menu under its own title, which is macOS contributing an
    entry rather than the app declaring a command", and `mac-shell.sh` excludes `Design system` by
    name for exactly that. Declaring a second Settings command would put two items with two
    spellings in two menus. Whether AppKit lists the Settings window at all is **measured** at
    step D3, not assumed.
21. **No URL handling.** `?window=settings` and `?window=settings&pane=analyst` are the mock's own
    navigation; nothing in `app/Sources` reads a URL. *(spec §2 assumption 4; recorded across M15,
    M16 and M20)*
22. **The panes' unhappy-path wording is M17's.** This item ships the ideal state and the
    router-stopped state. *(spec §2 assumption 9)*
23. **The shipped `ColorToken` / `MetricToken` values stay `DESIGN.md`'s.** The console mock is the
    design of record for *what is drawn*; re-pointing the palette at its values is M21's whole
    substance and would fail `DesignTokenParityTests` today. The mock decides structure, order and
    copy here; `DESIGN.md` still decides the numbers and the hues.

## 4 · The content decision — what the product may honestly draw

This is the item's largest decision and the one `SURF-011` was already pointing at. The campaign
recorded a content divergence between the build and `prototype.html` *"needing an owner decision,
not a styling defect"*; the console mock is a **third** content set, and applying the honesty rule
to it — spec §2 assumption 5, `DESIGN.md` §6, `SWIFT_PRACTICES.md` §5 — removes most of it.

Measured against the wire and the source, 2026-08-22: the control API owns `/servers`, `/usage` and
`/registry` only (`ControlPaths.isControlPath`, `ControlToken.swift:13-19`). `ServersResponse`
carries `port`, `idleMs`, `since`, `pendingAuth` and `servers[]` and nothing else
(`Models.swift:114-121`). There is **no analyst** anywhere in the product, **no update checking**,
**no start-at-login or `SMAppService`**, **no activation-policy control**, **no harnesses endpoint**
on the control API, and **no rotate endpoint** — `SettingsBoardModel.forget()`'s own docstring says
so. The mock's error state quotes `GET /control/settings → 200`, a route that does not exist.

| Pane · mock row | Verdict | Why |
|---|---|---|
| Router · Endpoint (+ Copy) | **Build** | `RouterFacts.endpoint`, observed port. Copy is an app affordance |
| Router · Idle window | **Build read-only** | `idleMs` is observed and not writable; `routerHelp` already says where it is set |
| Router · Warm set | **Build read-only** | `WarmSet` counts it; the switch is on each server's row. `Choose…` opens M18's sheet, not this item's |
| Router · Start at login | **Omit** | No login-item mechanism exists in either target |
| Router · Child PATH | **Omit** | R6 resolves it router-side; `/servers` carries no PATH field, so the app cannot observe it |
| Harnesses · all four | **Omit** | No harnesses endpoint; `WatchAdoption` / `HarnessReconciliation` are RouterCore and CLI-driven. The pane states where they are configured |
| Session analyst · all six | **Omit** | The product has no analyst in any form |
| Updates · all four | **Omit** | No update checking; no version comparison; `1.4.0 · up to date` would be two invented facts |
| Security · Control token | **Build** | `TokenStatus` + `Forget the stored token`. Not `Rotate…` — there is no rotate endpoint |
| Security · Hold schema changes | **Omit as a control** | The behaviour ships (`pendingChange`, `heldChanges`), the *setting* does not |
| Security · Paired devices | **Build read-only** | `PairingRecordStore` observes them. `Manage…` routes to Inbox, which is the mock's own `data-act="board:inbox"` |
| Security · Keep call history for | **Omit** | No retention window exists; `remove(keepHistory:)` is per-server |
| Menu bar · Show in the menu bar | **Build** | `shell.isMenuBarVisible`, the shipped toggle |
| Menu bar · Show the Dock icon | **Omit** | No activation-policy control exists |
| Menu bar · Approve from the popover | **Omit** | The popover ships; the preference does not |
| Advanced · Router log | **Build read-only path, no size** | The path derives from `RouterTokenFile`. `4.2 MB` needs a `stat`, which A36's boundary rule forbids in a gated directory and §6 forbids as an unobserved number |
| Advanced · Configuration | **Build** | Path derived; `11 servers` is `servers.count`, observed |
| Advanced · Rebuild the tool cache | **Omit** | `reindex(_:)` is per-server; there is no bulk re-index endpoint |
| Advanced · Restore direct configuration | **Omit** | No such endpoint |
| Advanced · build identity footer | **Build** | Through the one channel `MCPRouterApp.swift` already owns for `Bundle` (A36) — passed into the scene, never read in `Settings/` |

**What a pane with nothing left to build draws.** Not an empty pane, and not the mock's controls
rendered inert. It draws its name, its one line, and **one sentence saying what governs the thing
and where it is set today** — the shape `SettingsPresentation.routerHelp` already ships and M8
approved: *"Read from the router, not set here… Change these in ~/.claude/mcp-router/servers.json
and restart the router."* That satisfies `DESIGN.md` §6 (nothing invented) and §5 (says what
happened and what to do), keeps the seven-pane count real rather than decorative, and is copy — the
cheapest thing in the item to reverse when the capability lands.

The losing option, drawing the controls anyway, is better at matching the mock pixel for pixel and
is forbidden by §6 and by the spec's own assumption 5. The other losing option, cutting to four
panes, contradicts assumption 1 and breaks M17's ten-surface count. Neither names an axis that is
the owner's, so it is decided here and recorded rather than asked.

## 5 · Every reader of `Destination.settings`

Eleven, not four. Each is a real edit; none is optional.

| # | Reader | What it does today | Becomes |
|---|---|---|---|
| R1 | `MCPRouterKit/Shell/Destination.swift:54` | `case settings`, plus five exhaustive switches (`title`, `group`, `selectionDigit`, `badgeSource`, `iconName`) | case deleted; each switch loses its arm. The doc comment "The eight places" becomes seven |
| R2 | `Destination.group` / `inGroup(_:)` | `.settings` is the only `nil`, the ungrouped tail | `group` becomes non-optional `DestinationGroup`; `inGroup(_:)` takes a non-optional. Dead optionality is not left behind — M22 reworks the groups next and inherits a clean type |
| R3 | `MCPRouterUI/Shell/Sidebar.swift:118-123` | an ungrouped `Section` with no header | deleted; the list ends at the Library group, and `Readout` sits directly beneath it — which is the mock's own arrangement |
| R4 | `MCPRouterUI/Shell/ScaffoldPane.swift:53-55` | `BoardRegistry.installed` names eight | names seven. `board-registry.sh`'s awk reader is indifferent to the wrap; the count check in `mac-shell.sh` derives rather than pins |
| R5 | `MCPRouterUI/Shell/ShellWindow.swift:217-218` | `ContentZone.board`'s `case .settings: SettingsBoard(shell:)` | arm deleted; the switch stays exhaustive with no `default` |
| R6 | `MCPRouterUI/Shell/ShellCommandRouter.swift:105-108` | `case .settings: .select(.settings)`, with the comment naming this as the line M8 would change | `case .settings: .openSettingsScene` (§6, step C2) |
| R7 | `MCPRouterUI/Icon.swift:47` | `case .settings: "gearshape"` | **kept** — `Icon.settings` is `Icon`'s own case and the settings source list still needs a gear. `Destination.iconName`'s `settings` arm goes; the `Icon` case does not |
| R8 | `ShellRestoration` / `Destination.restoring` | persists and restores the `rawValue` | **the code does not change and the behaviour does.** At `8863264` a stored `"settings"` restores to `.settings`, because the case exists; after R1 the same stored value restores to `.activity`, because `restoring`'s `guard let` fails. The observation flips without a line of `ShellRestoration` moving, which is exactly what that path was written for, and is why acceptance criterion 8 is falsifiable at base rather than already true |
| R9 | `Tests/MCPRouterKitTests/ShellDestinationTests.swift:12,54,65` | `inGroup(nil) == [.settings]`, a round-trip list, `settings.selectionDigit == nil` | `inGroup` assertion re-pointed at the group split; `.settings` dropped from the round-trip list; the digit assertion deleted with its subject |
| R10 | `Tests/MCPRouterUITests/ActivityBoardContractTests.swift:190-203` and `ShellScaffoldRetirementTests.swift:33-52` | two exact set equalities naming eight, plus `installed == Set(Destination.allCases)` | the two literals lose `.settings`. **The `allCases` invariant is not relaxed** — it is what proves the removal was complete rather than partial |
| R11 | `Tests/MCPRouterUITests/SettingsAndMenuBarTests.swift:18-23`, `ShellCommandRouterTests.swift:39,42,65,151-152` | assert Settings is an installed board and `⌘,` moves the selection | re-pointed at the scene (§9) rather than deleted, so M8's clauses keep an evidence lane in their new form |

Two more that are not Swift and are the ones a source-only sweep misses:

| # | Reader | Breaks how |
|---|---|---|
| R12 | `scripts/acceptance/mac-shell.sh:276, 324, 718, 1013` | walks `Activity Servers Skills Discover Inbox Checks Cleanup Settings` three times, asserts the window title is one of those eight, and calls `select_and_check Settings`. All four sites drop Settings; line 718's `select_and_check Settings` is replaced by `select_and_check Skills`, so the block still exercises four destinations |
| R13 | `scripts/acceptance/m6-inbox-pairing.sh:204` | the same eight-name loop | drops Settings |

`scripts/acceptance/m8-settings-menubar.sh` is a fourteenth reader and is handled separately at
step D4: it presses the Settings row in the sidebar (`:106`) and reads the pane out of the main
window. Its A2, A30 and warm-set checks move to the new window; its menu-bar and quarantine checks
are untouched.

## 6 · How the scene is opened, and why not through the router

`ShellCommandRouter.perform` is a static function taking an optional `ShellModel`. A SwiftUI
`Settings` scene has no opener reachable from there: `EnvironmentValues.openSettings` needs a view
inside a scene, and a menu command is outside every scene — which is the same `@FocusedValue`
problem `ShellCommandRouter.swift:12-21` already measured and recorded. `SettingsLink` is the
documented API for exactly this position, so the item declares it and keeps the inventory where it
already is:

- `MenuCommand.settings.title` becomes **`Settings…`**. `DESIGN.md` §3.4 makes the ellipsis mean
  "opens a further view", and a window is one. `opensAFurtherView` is derived from the title, so it
  flips for free. `ShellCommandRouter.swift:100-102`'s comment — *"No ellipsis: Settings is a
  sidebar destination in this build"* — is the sentence this item makes false, and it is replaced
  rather than left.
- `ShellCommands` keeps `CommandGroup(replacing: .appSettings)` and renders a
  `SettingsCommandItem(.settings)` — a new view in `MCPRouterUI` that reads its title, shortcut and
  disabled reason from `MenuCommand` exactly as `CommandItem` does, and whose body is a
  `SettingsLink`. `MCPRouterApp.swift` still names no operation.
- `ShellCommandRouter.Operation` gains `case openSettingsScene`, and **its `perform` arm is not a
  no-op**. An earlier draft of this plan made it one, on the reasoning that `SettingsLink` performs
  the actuation and the value need only keep the mapping falsifiable. The out-of-family review was
  right to reject that: an arm that does nothing cannot fail, the test over it asserts that a
  command maps to inaction, and `ShellCommandRouter` becomes structurally unable to open Settings
  from anywhere else — the menu-bar popover, an error banner, a future onboarding path.

  The opener is **injected, from the one place that can reach it.**
  `EnvironmentValues.openSettings` is genuinely unreachable from a `Commands` builder, which is the
  same `@FocusedValue` fact `ShellCommandRouter.swift:12-21` measured. It is perfectly reachable
  from a *view inside a scene*, and `ShellWindow` already installs exactly this kind of capability
  at `:74-78`:

  ```swift
  .onAppear { ShellMenuReasons.provideContext { … } }
  ```

  So `ShellWindow` gains a second line beside it — `ShellCommandRouter.provideSettingsOpener(open)`,
  reading `@Environment(\.openSettings)` — and `perform`'s arm calls it. The private
  `NSApp.sendAction(Selector(("showSettingsWindow:")))` route the review proposed is **not** taken:
  it is an undocumented selector that was spelled `showPreferencesWindow:` two releases ago, and
  `SWIFT_PRACTICES.md` §6 forbids a symbol that exists in neither this repo nor a pinned dependency.

  The clause is now behaviourally testable rather than grep-testable: a test installs a recording
  opener, calls `perform(.settings, on: model)`, and asserts it fired — red against an arm that does
  nothing. E3's grep survives as the *second* half, proving the menu item is a `SettingsLink` rather
  than a hand-rolled button.

## 7 · Steps

### Phase A — the model (`MCPRouterKit`)

**A1 · `Shell/SettingsPane.swift`** *(create)* — `public enum SettingsPane: String, CaseIterable,
Sendable, Identifiable` with `router, harnesses, analyst, updates, security, menuBar, advanced` in
that order, each carrying `title`, `subtitle` (the one line under the name) and `iconName` in the
`Destination.iconName` shape. `CaseIterable` for the reason `Destination` is: the seven are a
compile-time fact, and an exhaustive switch over them fails to compile when one is added.
*Reference:* `Destination.swift:43-153`. *Fulfils:* 4, 5.

**Icons: four of the seven have no case, and none is added.** The mock's source list draws
`#i-servers`, `#i-harness`, `#i-bolt`, `#i-download`, `#i-shield`, `#i-menubar`, `#i-sliders`.
`Icon` carries `servers`, `bolt` and `shield` exactly; it has no `harness`, `download`, `menubar` or
`sliders`, and its count is asserted as `spriteSymbols (21) + drawnReplacementsForUnicode (1)`
against **the prototype's** sprite (`DesignSystemTests.swift:19-33`). Adding four cases re-bases
that inventory from the prototype's sprite to the console mock's, which is the same whole-document
decision as the palette and belongs to M21. So the panes reuse existing cases —
Router `.servers`, Harnesses `.layers`, Session analyst `.bolt`, Updates `.tray`, Security
`.shield`, Menu bar `.list`, Advanced `.settings` — and the four unmatched mock symbols are
**declared** in the fidelity manifest's note beside the 200pt width, with M21 as owner. `.settings`
keeping a caller after `Destination.settings` goes is what closes R7.

**A2 · `Shell/SettingsPaneCopy.swift`** *(create)* — every pane's card headers, row labels, helper
sentences and the "where this is set today" sentence for the three panes §4 empties. Verbatim from
the mock where the row is built; authored to §6's rules where it is not. Kept out of
`SettingsPresentation.swift` because that file is already at its useful size and `SettingsPane`'s
copy is a different subject; both stay in `MCPRouterKit` so `SettingsPresentationTests` can reach
them. *Fulfils:* 14, 15, and §4's whole table.

**A3 · `Shell/SettingsPresentation.swift`** *(modify, additively)* — `labelColumnWidth`,
`RouterFacts`, `WarmSet`, `TokenStatus`, `routerHelp` and the token strings are all kept unchanged
and re-used by the new panes; `paneTitle` / `paneSubtitle` become the window's rather than a
board's. **`Group` (`:225-230`) is not deleted here.** It is superseded by `SettingsPane`, but
`SettingsBoard.swift` still references it and does not go until D0, so deleting it in phase A breaks
the build for the whole of B and C. It goes with its last caller.

### Phase B — the window (`MCPRouterUI/Settings/`)

**B1 · `Settings/SettingsMetrics.swift`** *(create, copied from `SettingsBoard.swift:12-34`)* — the
existing derivations verbatim, plus two:

- `sourceListWidth` = `MetricToken.sidebar.leadingScalar`, the documented **256**, per decision 18.
  Any arithmetic that lands on 200 — `256 - 56`, `256 * 0.78` — is a literal wearing a token's
  clothes, which is the same defect one level of indirection down. The manifest's `note` records
  the mock's 200 against the build's 256, alongside the four unmatched source-list symbols from A1,
  with M21 as owner. Reporting a real difference is what the conversion contract is for.
- `titlebarHeight`: `MetricToken.titlebar.leadingScalar` — 33, which the mock and `DESIGN.md`
  already agree on, so this one is a token read and nothing more.

*Fulfils:* 12, 17, 18.

**B2 · `Settings/SettingsWindow.swift`** *(create)* — `NavigationSplitView` whose sidebar is a
`List(selection:)` over `SettingsPane.allCases` with `.listStyle(.sidebar)` and
`.navigationSplitViewColumnWidth(SettingsMetrics.sourceListWidth)`, detail is the pane body in a
`ScrollView`. **The selection binding is this window's own** — never `ShellModel`'s, never a shared one. That is
requirement 6 and it is the mock's own recorded bug.

**It persists, and bare `@State` is the wrong owner.** A `Settings` scene's window is destroyed on
close, so `@State` resets the pane to Router on every `⌘,` — which is not how a settings window on
this platform behaves, and it is a *regression* against the board, where the selected destination
survived because `ShellRestoration` held it. So the pane is stored the way the destination is:
`ShellRestoration` gains `settingsPaneKey = "shell.settingsPane"`, `restoredSettingsPane()` falling
back to `.router` for an absent or unknown value exactly as `Destination.restoring` does, and
`save(settingsPane:)`. That also gives it the evidence lane a scene-local `@State` has none of —
`ShellTestSupport.scratchStore()` — which is the argument `ShellRestoration.swift:64-67` already
makes about the menu-bar preference.

**Arrow-key traversal** is the brief's explicit requirement, and is *expected* to come free from
`List(selection:)` with `.listStyle(.sidebar)`. Expected is not measured: it is read back at D3
alongside the other platform behaviours, and if the list does not traverse, `.focusable()` plus an
explicit `.onMoveCommand` ships. *Reference:* `ShellWindow.swift:26-58`, `Sidebar.swift:108-126`.
*Fulfils:* 5, 6, 12, 16, and the brief's traversal clause.

**B3 · `Settings/SettingsPaneRow.swift`** *(create)* — one source-list row, mirroring
`SidebarRow`'s metrics, accent fill and radius exactly. It does **not** reuse `SidebarRow`: that
type takes a `Destination` and a `BadgeSource`, neither of which a pane has, and widening it to a
protocol to serve two lists is more coupling than two small views. What is shared is the metric and
colour reads, which is what requirement 13 is about. Recorded here because the brief asks for a
shared row view and this is a deliberate departure from it. *Fulfils:* 13.

**B4 · `Settings/Panes/*.swift`** *(create, seven files)* — `RouterPane`, `HarnessesPane`,
`AnalystPane`, `UpdatesPane`, `SecurityPane`, `MenuBarPane`, `AdvancedPane`. Each is
`SettingsPaneHeader` + `SettingsGroup`/`SettingsCard`/`SettingsRow` from `SettingsBoardParts`, built
to §4's verdict column. The three panes §4 empties draw header + the one governing sentence.
`Form { Section }` with `.formStyle(.grouped)` is **not** used, against the brief: the shipped
`SettingsCard` already produces the inset card, the shared axis and the inset hairlines, it is
already token-derived and lint-clean, and swapping in a system form style would re-open every
geometry assertion M8 closed. *Fulfils:* 8, 10, 14, and §4.

**B5 · `Settings/SettingsWindowModel.swift`** *(create, copied from `SettingsBoardModel.swift`)* — the
token store, `routerHome`, `tokenPath`, `tokenHelp`, `load`, `forget`, unchanged. Renamed with the
file.

**One instance per window, and the window is destroyed on close**, so `load()` re-reads the keychain
on every `⌘,`. That is the board's behaviour too — `SettingsBoard` constructs its model in `init`
and `ContentZone` rebuilds it on every destination switch — so it is not a regression, and it is
cheap: one `SecItemCopyMatching`. Recorded because the review raised it and because it is the kind
of thing that stops being cheap the moment a pane adds a second read. *Fulfils:* 8.

**B6 · `Settings/SettingsParts.swift`** *(create, copied from `Boards/SettingsBoardParts.swift`)* —
`SettingsGroup`, `SettingsCard`, `SettingsRow` and `WarmChips`, re-pointed at
`Settings/SettingsMetrics.swift`. **The original stays** until D0.

**Phases A and B are additive by construction, and that is the point.** Everything up to here
compiles alongside the shipped Settings board with the board untouched: two card implementations
and two metric enums exist briefly, and `boardFileListIsComplete` plus the new
`settingsFileListIsComplete` both stay green because each pins its own directory. The alternative —
moving files as they are written — is what makes the tree red for two phases, which is exactly the
window in which a runner starts weakening tests to see whether anything else is wrong.

**B7 · the router-stopped state** — the window opens, the source list is live, and every pane whose
content comes from the router draws `ControlAPIError`'s headline and advice verbatim, the way
`SettingsBoard.routerGroup:117-133` already does. Panes that draw nothing from the router (Menu bar)
stay live. This is the mock's `v-empty` read honestly: the mock refuses the whole window, the build
does not, because the menu-bar preference is genuinely still editable. *Fulfils:* 9.

### Phase C — the scene (`app/MCPRouter`, `MCPRouterUI/Shell`)

**C1 · `MCPRouterApp.swift`** — add a fourth scene:

```swift
Settings {
    SettingsWindow(model: model, buildIdentity: BuildIdentity(bundle: .main))
}
```

and replace `CommandGroup(replacing: .appSettings) { item(.settings) }` with
`CommandGroup(replacing: .appSettings) { SettingsCommandItem(.settings) }`. `BuildIdentity` is
constructed here because `MCPRouterApp.swift` is the one file permitted to name `Bundle` (A36), and
is passed in as a value. **`SettingsWindow` has exactly one initializer** —
`init(model:buildIdentity:store: (any ControlTokenStore)? = nil)`, mirroring
`SettingsBoard.init(shell:store:)`'s existing shape — so the scene and the measurement harness (E1)
construct it the same way and differ only in the store they pass. The comment at `:20-24` and the one at `:99-102` both describe the old
arrangement and are rewritten.

**C2 · `Shell/ShellCommandRouter.swift`** — `Operation` gains `case openSettingsScene`;
`shellOperation`'s `.settings` arm returns it; `perform` gains the documented no-op arm; the
`:105-107` comment is replaced with why the actuation is `SettingsLink`'s.

**C3 · `Shell/SettingsCommandItem.swift`** *(create)* — the `SettingsLink` wrapper reading title,
shortcut and reason from `MenuCommand`. In `Shell/` rather than `Settings/` because it is a menu
item, and because `ShellTestSupport.shellFiles` is pinned to that directory's listing.

**Whether it needs `.keyboardShortcut(",")` at all is measured, not assumed.** A `Settings` scene
in the `.appSettings` position may carry `⌘,` implicitly, and applying it a second time is how a
menu item ends up double-bound. `mac-shell.sh`'s A20 walk already reads `cmdchar` and `cmdmods` off
the running menu bar, so the answer is a reading rather than a guess: build it without the modifier
first, read the item back, and add the modifier only if the reading is empty. Either way the
inventory row and the menu bar must agree on `⌘,`, which is what `MenuCommandTests` and A20 both
check.

**C4 · `MCPRouterKit/Shell/MenuCommand.swift`** — `.settings`'s title becomes `Settings…`.
No other arm changes: `menu`, `isSystemProvided`, `shortcut` and `availability` are all already
right for a command that opens a window.

**C5 · `planning/specs/spec-M1.md`** — the inventory row `| MCP Router | Settings | ⌘, | enabled |`
becomes `| MCP Router | Settings… | ⌘, | enabled |`. This is the external oracle both
`MenuCommandTests` and `mac-shell.sh` parse; editing it is part of the change, not a follow-up.

### Phase D — the removal and the gates

**D0 · the removal, as one atomic step.** Everything the old surface owns goes together, because
each of these is another's last caller and no ordering among them leaves the tree green:

- delete `Boards/SettingsBoard.swift`, `Boards/SettingsBoardModel.swift`,
  `Boards/SettingsBoardParts.swift`;
- delete `SettingsPresentation.Group` (A3's deferred half);
- delete `ContentZone.board`'s `case .settings` arm (R5) and `Sidebar`'s ungrouped `Section` (R3);
- delete `case settings` from `Destination` and its five switch arms (R1), make `group`
  non-optional (R2), and drop it from `BoardRegistry.installed` (R4).

Within D0 the tree does not compile, and that is accepted rather than worked around: a phase is the
unit that must compile, not a step. What makes it safe is that the compiler *is* the checklist —
`Destination`'s own doc comment claims a case cannot be added without every exhaustive switch
failing until it is handled, and the same guarantee runs in reverse here. Start from R1; the error
list is §5's table, and anything in the errors that §5 does not name is a reader nobody found.

R6 landed in C2 and R7 is a deliberate non-edit — `Icon.settings` keeps its case and gains
`SettingsPane.advanced` as its caller, so `IconTests` and the sprite-count assertion are untouched.

**D2 · `scripts/lint/no-raw-design-values.sh`** — add
`"$ROOT/app/Sources/MCPRouterUI/Settings"` to `GEOMETRY_DIRS` (`:127-131`). Without this the
geometry-literal rule and A36's one-channel rule **silently stop applying** to code that is under
them today: `SettingsBoard.swift` lives in `Boards/`, which is listed, and the new directory is not.
The script's `[ -d "$dir" ]` guard only fails for a *listed* directory that is missing, so this gap
is invisible. The comment at `:123-125` already says "Each board directory joins as it ships"; this
is that.

**D3 · measure the four platform behaviours** before writing any workaround for them. Each is a
`(measured: …)` claim in the completion note, and each has a fallback that ships only if the
measurement says it must. `DESIGN.md`'s own precedence rule is why this is a measurement rather
than a decision: where the document and the kit disagree, the kit wins, so what the kit actually
does has to be read rather than assumed.

| Behaviour | How it is measured | Fallback if absent |
|---|---|---|
| minimise and zoom dimmed | `axkit dump` over the Settings window's `AXMinimizeButton` / `AXZoomButton` `AXEnabled` | `.windowMinimizeBehavior` / explicit disable on the `NSWindow`, never hiding them (`DESIGN.md` §3.4) |
| Escape closes | drive `Esc` at the window and read whether it goes away | `.onExitCommand` on the window root. No conflict with `keysReservedForContent`, which governs *menu commands* |
| the Window menu lists it | `axkit menu` for a `Window / Settings` item | if present, add `Settings` to `mac-shell.sh`'s `system-items.txt`. Safe because the app's own item is now `Settings…`, so the exclusion matches only the system entry. If absent, that is reported, not built around — decision 20 |
| the source list traverses on ↑/↓ | move focus to the list over the accessibility plane, send arrow keys, read `AXSelectedRows` | `.focusable()` plus an explicit `.onMoveCommand` on the list. The brief asks for this in the same sentence as the independent selection, and `List(selection:)` is only *expected* to provide it |

**D4 · `scripts/acceptance/m8-settings-menubar.sh`** — the pane checks move from the main window to
the Settings window: open it, dump it, and re-run A2's placard checks, the four group headers, the
row labels, the `/mcp` endpoint check, the no-megabyte check, the no-token check and the warm-set
check against the new dump. The window-title check at `:156-158` keeps asserting `Settings` — it
just reads a different window. The menu-bar and quarantine halves are untouched.

**D5 · `scripts/acceptance/mac-shell.sh` and `m6-inbox-pairing.sh`** — R12 and R13.

### Phase E — the fidelity surface (M23's harness)

**E1 · `app/Sources/MeasureDump/main.swift`** — `Surface` gains `case settings` (`:24`).
`MeasuredSurface`'s stored `board: ServersBoardModel` (`:165`) is concrete and `render()`'s
signature (`:213`) is hardcoded to it, so the model construction moves inside the per-surface arm
rather than being built unconditionally at `:200-203`. The `.settings` arm renders
`SettingsWindow(model: shell, buildIdentity: .measured, store: InMemoryTokenStore())` — **the
in-memory store, not the
default `KeychainTokenStore()`**, because `MeasureDump` is an unsigned SwiftPM executable with no
keychain access group and `SecItemCopyMatching` returns `-34018` there, which the Makefile already
documents at `:16-22` for the iOS lane. `Arguments`, the refusal path, the settle spin and the dump
write are already surface-generic and need no edit.

**E2 · `.measured(…)` annotations** on the window, the source list, each row and each pane's header,
cards and rows, plus one `.measureSurface("settings.\(state)")` at the window root. Innermost
`measured`, outermost `onPreferenceChange` — the order is load-bearing and `Measured.swift:304-308`
says why.

**E3 · `planning/fidelity/settings.layers.json`** *(create)* — `surface: "settings"`,
`mock: "design/mcp-router-console.html"`, **`section: "swin"`** (the mock models Settings as
`<div class="swin" id="swin" data-state="ideal" role="dialog">` at `:1513`, not as a
`<section class="board">`; `mock-affordances.py:181` matches any element by `id`, so no engine change
is needed), `pairing: "planning/fidelity/settings.pairing.tsv"`, `states: ["ideal", "empty"]`, the
same eight `layers` entries as `servers.layers.json` with `font-weight-face` `required: false` and
its substitute citation, and four `floors`.

**The floors are recorded, not chosen, and that is the mechanism rather than a hole in it.**
`servers.layers.json`'s own note states it: they *"are the census sizes measured on the run that
wrote them, and they are a ratchet"*. No fixed bound is available before the surface exists — a
census size is a property of the finished window. What makes them a gate is the direction: they are
taken from the first run whose structure layer is clean, they only ever rise, and
`Context.__init__` exits 3 for a floor below 1 or non-integer. A floor lowered later to make a run
green is the failure this shape has to be watched for, and the plan says so here so a reviewer of
the diff knows to look.

`loading` and `error` are **omitted from `states` and recorded in the manifest's `note`** with M17
as owner. M23's A6 is the precedent: an unaudited state is inventoried with a reason, never dropped
in silence. Listing them without building them would make every run exit 1 on absent affordances,
which reports a scope boundary as a defect.

**E4 · `planning/fidelity/settings.pairing.tsv`** *(create)* — one row per mock affordance,
`state \t affordance \t node \t citation`. Every row §4 marked **Omit** gets `node = -` plus a citation.

**The citation is the wire fact, not this plan.** An earlier draft cited §4's own table, and the
out-of-family review was right that this is circular: M23's bar is *"A citation is external and
**pre-existing** … a justification composed during the audit is motivated classification wearing a
citation's clothes"*, and a plan written for this item is neither external nor pre-existing. So each
omitted row cites the artifact that already said the capability is absent, all of which predate this
item: `ControlToken.swift:13-19` (the control API owns three paths), `Models.swift:114-121`
(`ServersResponse` carries five fields), `SettingsBoardModel.swift:71-72` (*"There is no rotate
endpoint and this is not one"*), `SettingsPresentation.swift:100-105` (no megabyte figure, and no
field for one), `DESIGN.md` §6 (numbers the router does not observe are never displayed), and — for
the analyst, updates and login-item rows — the absence itself, recorded as the grep and its date.
An absence is admissible as a citation only when the search that established it is named, so each
of those rows carries the pattern searched and the directories covered rather than the word "none".

**E5** — run `./scripts/acceptance/mock-fidelity-gate.sh settings` and record its exit. Nothing in
the gate, the engine or the selftest is hardcoded to `servers` beyond a default argument, so no
script edits are needed. `make mock-fidelity SURFACE=settings` is the wrapper.

## 8 · Parity inventory — the Settings board's behaviours, re-housed

This routes a shipped surface through a new path, so every load-bearing behaviour of the old one is
marked rather than assumed to survive.

| Behaviour (old path) | Disposition |
|---|---|
| `RouterFacts.endpoint` composes from the **observed** port via `LoopbackAddress` | **keep**, verbatim |
| `sinceDisplay` refuses to draw a start time or a pid the router does not serve | **keep** |
| `WarmSet` has no field a megabyte figure could occupy | **keep** |
| `TokenStatus` has no field the token could occupy — the enforcement is structural | **keep** |
| `TokenStatus.forgetIsProminent` — one prominent accent action, only while `.rejected` | **keep**; it is now one per *pane*, and Security is the only pane with a prominent action |
| The offline branch renders `ControlAPIError`'s headline and advice with **no action button**, recorded in spec-M8 as a deliberate §5 deviation | **keep**, and the deviation is re-recorded in spec-M15 §2 so it does not read as new |
| `SettingsRow(value: nil)` skeleton at the populated row's exact height | **keep** |
| Path values truncate from the **left** and carry the full value in `.help` and `.accessibilityValue` | **keep** |
| The board installs no `ScrollView` of its own, because the shell's outer one is the scroller | **port, inverted.** The Settings window has no shell around it, so the window **does** own its detail `ScrollView`. `ShellWindow.boardsThatScrollThemselves` no longer has an opinion about Settings, and `mac-shell.sh`'s "exactly one content-zone scroll area on all eight panes" check (`:869-889`, `:1152-1156`) now covers seven and is not a claim about this window |
| `Show in Servers` selects `.servers` on the shell model | **port.** It now has to cross a window boundary: the button selects on `ShellModel` as before, and the console window comes forward. Whether it *does* come forward is measured at D3's lane, not assumed |
| The pane reads the shell's existing poll and starts none of its own | **keep** — the scene is handed the same `ShellModel` |
| `⌘,` reaches Settings | **port** (§6) |
| The Settings row announces itself selected in the sidebar | **drop with rationale** — there is no such row. Its evidence moves to the source list's own one-selected assertion |

## 9 · Test strategy

**Seams, agreed here so nothing is tested at an unconfirmed one.** Five, all existing:

1. **`MCPRouterKit` value types** — `SettingsPane`, the copy enums, `SettingsPresentation`,
   `MenuCommand`. Reached by `MCPRouterKitTests`, no UI stack. The highest seam for requirements
   4, 15 and the copy half of §4.
2. **`MCPRouterUI` model and source-level gates** — `MCPRouterUITests`, which already greps declared
   source files for boundary and colour violations and asserts registry membership. The seam for
   §5's removal and for §6's actuation grep.
3. **`ShellRestoration` over a scratch `UserDefaults` domain** — `ShellTestSupport.scratchStore()`.
   The seam for R8.
4. **`MeasureDump` + `mock-fidelity-gate.sh settings`** — the only seam that reads a *rendered*
   settings window. Structure, geometry, copy, breadth and type-metrics all close here.
5. **`m8-settings-menubar.sh` over the accessibility plane** — the only seam that reads the running
   app's real window chrome, which is where D3's three measurements and the window title live.

**A seam this item does not have, stated as the finding it is:** there is no seam at which "a sheet
opened from a Settings pane attaches to the Settings window" (requirement 11) can be exercised,
because no pane opens a sheet after §4. The requirement is real and untestable here; it becomes
M18's, which owns the sheets, and is recorded in spec-M15 rather than tested vacuously.

### Unit and contract coverage

- `SettingsPaneTests` — the seven cases, their order, and that the order equals the mock's
  `data-pane` sequence read from `design/mcp-router-console.html` at test time. **The expected value
  comes from the mock, not from a literal in the test**, so the assertion cannot agree with the code
  by construction. Same mechanism as `MenuCommandTests.inventory()`.
- `SettingsPaneCopyTests` — every pane has a non-placeholder title, subtitle and, where §4 empties
  it, a governing sentence. Reuse `M7DesignedStateTests.assertUsable`'s bar: rejects empty, under
  twelve characters, and six placeholder patterns.
- `SettingsHonestyTests` — the §4 table as assertions: no pane's copy contains a byte-size unit, a
  version string, a model name, or the words `analyst`, `Rotate`, `Start at login`. This is the test
  that fails if a later runner re-adds the mock's rows from the mock.
- `MenuCommandTests.ellipsisRule` — the `opening` set gains `Settings…`; the inventory both-ways
  test picks up C5 automatically.
- `ShellCommandRouterTests` — `operation(for: .settings) == .openSettingsScene`;
  `MenuCommand.settings.opensAFurtherView == true`; the `perform` assertion at `:151-152` is
  **replaced**, not deleted, by E3's grep.
- `ShellDestinationTests`, `ActivityBoardContractTests`, `ShellScaffoldRetirementTests` — R9, R10.
  `installed == Set(Destination.allCases)` stays.
- `ShellIntegrationTests.settingsFileListIsComplete` *(new)* — the directory pin for
  `app/Sources/MCPRouterUI/Settings/`, in the shape `boardFileListIsComplete` already uses. Without
  it a file added to the new directory escapes every source-level gate, which is the exact escape
  that test's docstring was written about after `ServerInspectorSections.swift`.
- `ShellTestSupport.settingsFiles` *(new)* — and enrolment in the four suites that read
  `boardFiles + shellFiles`: `ShellAppearanceTests`, `ActivityBoardRulesTests`,
  `ServersBoardSurfaceTests`, `ShellScaffoldRetirementTests`.

### The affected-test sweep

Mechanical, over every name this branch changes or inverts. The hits are: `ShellDestinationTests`,
`ActivityBoardContractTests`, `ShellScaffoldRetirementTests`, `SettingsAndMenuBarTests`,
`ShellCommandRouterTests`, `MenuCommandTests`, `SettingsPresentationTests`, `ShellIntegrationTests`,
`ShellAppearanceTests`, `ActivityBoardRulesTests`, `ServersBoardSurfaceTests`, plus
`mac-shell.sh`, `m6-inbox-pairing.sh` and `m8-settings-menubar.sh`. Each is updated to the new
contract and run. A spec asserting the behaviour being removed is part of this diff; leaving one
`fixme`'d against the old world is shipping a broken test.

### Regression discrimination

Three guards are added whose whole job is to catch drift, so each is deliberately broken, seen red,
and restored, per `SWIFT_PRACTICES.md` §7:

- `SettingsPaneTests`' mock-order assertion — reorder two `SettingsPane` cases, watch it fail.
- `SettingsHonestyTests` — add `Version 1.4.0` to a pane's copy, watch it fail.
- `settingsFileListIsComplete` — add an unlisted file to `Settings/`, watch it fail.

### Falsifiability at the base commit

Each acceptance criterion below names an observation that fails at `8863264`. Two are worth stating
because they are the ones that could be written un-falsifiably: "the Settings window exists" fails
today because `MCPRouterApp` declares three scenes and none is `Settings` — checkable by grep and by
`axkit`'s window list. "Seven pane rows, one selected" fails today because
`mock-fidelity-gate.sh settings` exits **3** at the missing manifest, which is the correct answer
and not a passing one (spec §3.5).

## 10 · Acceptance criteria

- [ ] `axkit` reports a second window titled `Settings`, opened by the app-menu item, with its
      minimise and zoom buttons reporting `AXEnabled 0` and close reporting `AXEnabled 1`.
- [ ] The Settings window's structure dump contains seven pane rows, exactly one reporting itself
      selected, and a detail body whose measured nodes match that pane — the brief's own acceptance
      line, closed through `mock-fidelity-gate.sh settings`.
- [ ] `mock-fidelity-gate.sh settings` exits **0**, or exits 1 with a ledger in which **every**
      finding is one of the divergences the manifest's `note` declares (the 200pt source list, the
      four unmatched source-list symbols). A finding outside that list is a defect, not an
      allowance. A 3 is a blocker naming the layer that could not run, never an implied pass.
- [ ] Selecting a second pane changes the detail body and leaves the console window's selection
      untouched — driven over the accessibility plane with both windows open.
- [ ] `Esc` at the Settings window closes it and leaves the console window open.
- [ ] With the router stopped, the window opens, the seven rows are live, and the router-fed panes
      draw `ControlAPIError`'s headline and advice verbatim.
- [ ] The console's accessibility tree carries seven destination rows and no `Settings` row, and its
      window title is never `Settings`.
- [ ] A `UserDefaults` domain holding `shell.selectedDestination = "settings"` restores to Activity
      rather than to nothing.
- [ ] Every group and row the shipped Settings board draws is present somewhere in the new window:
      `Endpoint`, `Home`, `Idle reaper`, `Counting since`, the menu-bar toggle, `Kept resident`,
      `Token`, `Read from`, `Forget the stored token`.
- [ ] `make lint` is green with `Settings/` inside `GEOMETRY_DIRS`, and
      `no-raw-design-values.sh`'s file count has **risen** — a count that did not move means the
      directory was added and nothing was scanned.
- [ ] `make all` green, including `mock-fidelity-selftest`.

## 11 · Scope-narrowing check

Compared against the brief and the eight triage assumptions. Three narrowings, each surfaced in
`spec-M15.md` as its own line for the owner to reverse:

1. **`⌘0` is excluded** (decision 19). The brief lists it as one of four routes in. Nothing in the
   triage assumptions covers it. Reply to keep it excluded, or it gets planned into M20's
   accelerator map.
2. **No Window-menu item is declared** (decision 20). The brief asks for "the Window menu, where a
   tick tracks whether it is open". What macOS contributes is taken and measured; what the app
   declares is nothing.
3. **Thirteen of the mock's thirty rows are not built** (§4). Assumption 5 covers this — *"A control
   naming a capability this product does not have is not built"* — and this plan is where it is
   applied row by row, which is the first time the count is visible. Reply to keep them out, or the
   ones with a capability behind them get planned in.

Nothing else in the brief or the assumptions is unaccounted for. Assumption 6 (settings stay
per-person on this Mac) adds no work. Assumption 8 (dimensions from named measurements) is
requirement 17. Assumption 9 (M17 owns the state count) is decision 22.

## 12 · Out of scope

- URL handling of any kind. *(decision 21)*
- The panes' loading and error bodies. *(decision 22 — M17)*
- Any sheet a pane would open: the analyst configuration, the PATH inspector, the warm-set chooser,
  the rotate dialog. *(M18)*
- Re-pointing `ColorToken` / `MetricToken` at the mock's values, or re-authoring `DESIGN.md` §2 to
  carry a 200pt row. *(decision 18, 23 — M21)*
- The Harnesses and Insights boards the mock's own navigation list carries. *(M22)*
- Filling the Servers fidelity ledger further, or auditing a third surface. *(M23 owns the shape)*

## 13 · Gate record

- **Codebase grounding.** Source read across `app/MCPRouter`, `app/Sources/MCPRouterKit/Shell`,
  `app/Sources/MCPRouterUI/{Shell,Boards,Measure}`, `app/Sources/MeasureDump`,
  `app/Sources/RouterCore/Control`, `app/Tests/{MCPRouterKitTests,MCPRouterUITests}`,
  `scripts/acceptance`, `scripts/lint`, `Makefile`, `planning/fidelity`, and the mock's Settings
  markup at `design/mcp-router-console.html:1511-1745`.
- **Mechanical path check.** Every backtick-quoted path verified present, except those marked
  *create*.
- **Out-of-family review.** Ran on one lane and is recorded in §14 with its disposition.
  `codex` / `gpt-5.6-sol` is down until 2026-08-27 and was not attempted; `grok-4.6`'s balance is
  exhausted and it was not attempted; `agy` / `gemini-3.7-flash-high` answered. `claude
  --model claude-fable-5 --effort high` was started in parallel as a second reading and never
  returned, so the gate stands on a single family and has no second reading behind it.

## 14 · Out-of-family review — record and disposition

`agy` / `gemini-3.7-flash-high` was handed the brief, the spec and this plan in `/tmp/m15`, briefed
adversarially over seven questions — completeness, silent shrinkage, testability, ordering, parity,
technical soundness, and the better approach it would take — and told that finding nothing is a
failed review. It returned 14,833 bytes. Every one of the seven sections came back **FAILED**, and
the overall verdict was **REJECT**, with nine numbered findings.

The in-family second reading, `claude-fable-5` at high effort, was launched against the same packet
at the same moment and was still running with a zero-byte output when the planning session ended. It
contributed nothing and is not part of this record.

**The planning session ended mid-disposition.** Findings 1–6, 8 and 9 were dispositioned into the
plan above; the planner's next step was §11's narrowings, §8's parity rows and this record, and it
did not reach them. So §11 and §8 are as they were before the review, and the second list below is
what a runner still has to treat as open.

### Dispositioned into the plan

| # | Severity | Finding | Disposition |
|---|---|---|---|
| 1 | Critical | Deleting `Boards/SettingsBoard.swift` in B6 breaks `ShellWindow.swift` for all of B and C, until R5 lands in D1 | **Accepted.** B6 became additive — `Settings/SettingsParts.swift` is *copied* and the original stays — and every deletion moved into the new **D0**, one atomic step whose error list is §5's table |
| 2 | Critical | Deleting `SettingsPresentation.Group` in A3 breaks `SettingsBoard.swift` immediately, before B6 removes it | **Accepted.** A3 is now *modify, additively*; `Group` goes with its last caller in D0 |
| 3 | High | `perform(.openSettingsScene)` as a documented no-op leaves the router structurally unable to open Settings, and a test over it asserts a command maps to inaction | **Accepted for the no-op, overruled on the remedy.** The arm now calls an opener injected by `ShellWindow` from `@Environment(\.openSettings)`, beside the `ShellMenuReasons.provideContext` line already at `:74-78`, and the clause is behaviourally testable. The review's `NSApp.sendAction(Selector(("showSettingsWindow:")))` is **not** taken: it is an undocumented selector spelled `showPreferencesWindow:` two releases ago, and `SWIFT_PRACTICES.md` §6 forbids a symbol present in neither this repo nor a pinned dependency |
| 4 | High | Acceptance criterion 3 accepts exit 1; E3's floors are calibrated after the first run; E4's omitted rows cite this plan's own §4 | **Accepted, in three parts.** Criterion 3 now allows exit 1 only where **every** finding is a divergence the manifest's `note` already declares. E3 states that the floors are a recorded ratchet taken from the first structurally-clean run, names the failure mode (a floor lowered later to make a run green), and points at `servers.layers.json`'s own note for the precedent. E4's citations move to external, pre-existing artifacts — `ControlToken.swift:13-19`, `Models.swift:114-121`, `SettingsBoardModel.swift:71-72`, `SettingsPresentation.swift:100-105`, `DESIGN.md` §6 — with an absence admissible only when the search that established it is named |
| 5 | Medium | 256pt source list against the brief's 200 is a 28% distortion, and citing the fidelity manifest to ratify it corrupts the gate | **Overruled, with the reason rewritten into decision 18.** A settings source list is a sidebar, `DESIGN.md` §2 specifies `Sidebar 256pt`, and the mock's own `mac-craft:metrics` block carries `sidebar 256px` and no 200 of any name — so the mock disagrees with itself. The review's third option, `.navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)`, was weighed and loses twice: three geometry literals where `no-raw-design-values.sh` permits none, and a range is three numbers picked by eye where the complaint was one. The 56pt gap is declared in the manifest `note` and reported on every run |
| 6 | Medium | `@State` selection resets the pane to Router on every `⌘,`, a regression against the board | **Accepted.** The pane persists through `ShellRestoration` — `settingsPaneKey = "shell.settingsPane"`, `restoredSettingsPane()` falling back to `.router`, `save(settingsPane:)` — which also gives it the `ShellTestSupport.scratchStore()` evidence lane a scene-local `@State` has none of |
| 7 | Medium | "The five panes §4 empties" contradicts §4, which empties three; and four undeclared narrowings | **Accepted in part.** The count is corrected to three at all three sites. The four §11 declarations were the planner's next step and were never written — see below |
| 8 | Low | C1 constructs `SettingsWindow(model:buildIdentity:)` while E1 constructs `SettingsWindow(model:store:)` | **Accepted.** C1 now declares one initializer, `init(model:buildIdentity:store: (any ControlTokenStore)? = nil)`, and E1 renders `SettingsWindow(model: shell, buildIdentity: .measured, store: InMemoryTokenStore())` |
| 9 | Low | Criterion 8 already passes at `8863264`, so it proves nothing | **Accepted, and the row was wrong rather than the criterion.** R8 now records that at `8863264` a stored `"settings"` restores to `.settings` because the case exists, and after R1 the same value restores to `.activity` because `restoring`'s `guard let` fails. The observation flips without a line of `ShellRestoration` moving |

Three unnumbered findings were also taken. **Arrow-key traversal**, which the brief asks for in the
same sentence as independent selection, gained a paragraph at B2 and a fourth row in D3's
measurement table, because `List(selection:)` providing it is expected rather than measured.
**Repeated keychain reads** on a window destroyed at close are recorded at B5 as matching the
board's own behaviour rather than as a regression. And the review's third suggested approach, an
environment-injected store for pane selection, is taken in the shape this repo already uses —
`ShellRestoration` rather than a new environment value.

### Findings that stand, un-acted

Recorded rather than folded in, because the planner did not reach them and this is a record of what
the review found rather than a second planning pass.

- **§11 never gained the four narrowings the review asked for.** It still reads *"Three
  narrowings"*. The four are: `Form { Section }` with `.formStyle(.grouped)` is refused at B4 with
  reasons but is not declared as a departure from the brief; `SettingsPaneRow` duplicates rather
  than shares the console's row view, reasoned at B3 and undeclared; functional requirement 11
  (sheet attachment) is untestable because no sheets are built, and §12 assigns the sheets to M18
  while §11 carries no line for the dropped requirement; and §11 says *"the eight triage
  assumptions"* where **`spec-M15.md:23-31` lists nine** — verified here, and `spec-M15.md:227`
  repeats the miscount, so both files are wrong by one.
- **Three §8 parity rows the review named are still missing.** Router · Endpoint's **Copy**
  affordance, which §4 builds and §8 does not inventory; `forget()`'s async transition, disabled
  state and failure presentation, where §8 tracks only `TokenStatus.forgetIsProminent`; and the
  window's initial accessibility focus, which has no replacement for the dropped sidebar-selection
  announcement.
- **Security · Paired devices crosses a window boundary and §8 does not say so.** §4 builds
  `Manage…` routing to Inbox (`data-act="board:inbox"`); §8 inventories the crossing for `Show in
  Servers` alone.
- **Two §4 omissions the review called unforced, left as they were.** Advanced · Router log's
  `4.2 MB` — the review's position is that reading the app's own log file needs no sandbox escape,
  against §4's A36 and §6 reasoning. And Security · Hold schema changes, omitted as a control while
  `pendingChange` and `heldChanges` ship, with no §11 line.
- **Two §9 tests the review called vacuous are unchanged.** `SettingsHonestyTests` asserts only the
  absence of forbidden strings, which an empty view passes; `SettingsPaneCopyTests` asserts a
  length above twelve characters and nothing about meaning.
- **The menu-architecture half of finding 3 was answered only in part.** The review's claim is that
  a `SettingsLink` inside `CommandGroup(replacing: .appSettings)` breaks native `NSMenuItem`
  target-action validation, highlighting and key-equivalent dispatch. The plan keeps
  `SettingsCommandItem` and adds a C3 note to *measure* whether `⌘,` arrives implicitly before
  applying it a second time, which addresses double-binding but not validation. D3's lane is where
  a reading would settle it.
