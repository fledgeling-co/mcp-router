# plan-M18 — thirteen sheets, one inventory, and the gate each decision gets

Spec: `planning/specs/spec-M18.md` · brief `planning/features-to-triage/M18-sheets-and-gates.md`
Design of record: `design/mcp-router-console.html` (settled 2026-08-22)
Plan size: **Large**. A new closed inventory type in `MCPRouterKit` that five per-board enums
collapse into, seven `.sheet(` call sites rewritten, three of them off `isPresented:`, one dead
enum deleted, one absent sheet drawn, a gate table that becomes data, and new fidelity surfaces
under M23's harness.

Baseline: `87e16dc` on `ai/m18`, worktree `.worktrees/M18`, tree clean apart from `WORK-ORDER.md`.

---

## 1 · Task

Make the sheet inventory a compile-time fact, make every sheet open from the thing that was
chosen, and make the gate each decision gets a declared property of that decision rather than a
habit spread across six files.

The item is **not** "draw thirteen sheets". Nine of the thirteen already have a host and eight of
those already have a sheet. What the build does not have is a single inventory, a typed gate
table, and a consistent reading of the brief's mechanics — and four of the thirteen cannot be
drawn at all yet, for reasons this plan names one at a time rather than as a total.

---

## 2 · Approach

Three layers, in dependency order, then two additions.

`MCPRouterKit/Shell/` gains `RouterSheet.swift`: the one inventory, the mock's thirteen mapped
onto it, and the gate table as data. It goes in Kit rather than UI because that is where every
other testable-without-a-host decision in this app already lives (`MenuCommand`, `Destination`,
`SettingsPaneCopy`), and because the gate table has to be assertable from `MCPRouterKitTests`.

`MCPRouterUI/Boards/` then loses its five per-board `Sheet` enums and its three `isPresented:`
presentations. **The conversion is not a rename.** All three `isPresented:` sites hold their
subject *by id* in the model and look it up fresh on every render — `InboxBoardModel.sheetItemID`
(`/// The item the review sheet is open for, held **by id** rather than as a captured value`, `InboxBoardModel.swift:118-121` at `706cefb`), `DiscoverBoardModel.sheetEntryID`
(`/// The entry the sheet is open for, held **by id**.`, `DiscoverBoardModel.swift:71-77` at `706cefb`) — with M5's reason written on both: *"a copy taken when the
sheet opened goes stale the moment the row does, and the sheet's action then disagrees with the
board about what has already happened."* A naive `.sheet(item:)` carrying a captured
`RegistryEntry` would satisfy the brief's letter and reintroduce exactly the bug those two
comments record closing. So the enum case carries **the id**, and the sheet body keeps the fresh
lookup.

Then the gate discipline is applied to the sheets that exist, and `official` is drawn.

**The analogue to follow is `MenuCommand`.** It is already the shape this item wants: a closed
enum in Kit, an `allCases` the tests compare against a document's inventory table in both
directions, and per-case derived properties (`menu`, `title`, `opensAFurtherView`) that make a
policy a compile-time consequence rather than a convention. `RouterSheet` is that pattern applied
to sheets; it does not re-derive it.

---

## 3 · What the mock draws, what the build has, and what can be drawn today

Measured on this worktree at `87e16dc`. This table is the item's spine and every later section
reads off it.

| # | Mock sheet | Host board | Built as | This item |
|---|---|---|---|---|
| 1 | `pair` | Inbox ✓ | `PairingSheet.swift` | re-house · gate |
| 2 | `reconcile` | Harnesses — **M22** | — | **parked** — no host |
| 3 | `quarantine` | Servers ✓ | `HeldChangeSheet` (`struct HeldChangeSheet: View {`, `ServerSheets.swift:134` at `706cefb`) | re-house · gate |
| 4 | `readme` | — **M19** | — | **parked** — no host, no renderer |
| 5 | `capability-delta` | Skills ✓ | `HeldVersionSheet` (`struct HeldVersionSheet: View {`, `SkillSheets.swift:31` at `706cefb`) | re-house · gate |
| 6 | `add-server` | Servers ✓ | `AddServerSheet` (`struct AddServerSheet: View {`, `ServerSheets.swift:45` at `706cefb`) | re-house · gate |
| 7 | `add-marketplace` | Skills ✓ | `MarketplacesSheet` (`struct MarketplacesSheet: View {`, `SkillSheets.swift:108` at `706cefb`) | re-house · gate |
| 8 | `recommendation` | Insights — **M22** | — | **parked** — no host |
| 9 | `queued-detail` | Inbox ✓ | `struct InboxReviewSheet: View {`, `InboxReviewSheet.swift:18` at `706cefb` | re-house · gate |
| 10 | `analyzer` | Insights/Settings — **M22** | — | **parked** — no host |
| 11 | `path` | Settings ✓ | — | **draw as a refusal** — §4.1, no observed data |
| 12 | `confirm-remove` | Servers ✓ · Cleanup ✓ | `RemoveServerDialog` (`struct RemoveServerDialog: View {`, `ServerSheets.swift:220` at `706cefb`) · `RemoveServerSheet` (`struct RemoveServerSheet: View {`, `CleanupSheets.swift:33` at `706cefb`) | re-house · gate · §4.2 |
| 13 | `official` | Discover ✓ | — | **draw**, minus §4.3 |

Three sheets the build has that the mock draws nowhere, and which the inventory absorbs rather
than sits beside (spec §2, assumption 3): `ActivityResetHistorySheet` and Cleanup's
`ResetHistorySheet` (one kind, two hosts), `SkillProvenanceSheet` (`struct SkillProvenanceSheet: View {`, `CleanupSheets.swift:175` at `706cefb`),
and `DiscoverDetailSheet`.

### 3.1 One correction to spec §3.3

The spec's mapping table reads *"quarantine / capability-delta | `HeldChangeSheet` … — one sheet
where the mock has two"*. **The build has two.** `HeldChangeSheet` draws `ToolChangeCard` over
`SchemaDiff.compare(before:after:)` for a server's held tool changes — that is `quarantine`.
`HeldVersionSheet` draws `held.addedCapabilities` against the installed plugin version with
`SkillPresentation.capabilityDerivation` naming how the list was derived — that is
`capability-delta`, and it is the mock's row *"what the new version added, against what was
approved"* almost word for word. Triage read the two by name rather than by content. Recorded
here rather than edited into the spec, because it narrows nothing: both are re-housed either way.

---

## 4 · The three things that cannot be drawn as the mock draws them

Each is a measurement, not a preference, and each says what it beat.

### 4.1 `path` is drawn as an honest refusal: the router does not report the child PATH

The mock's sheet draws a resolved seven-directory `PATH`, six per-CLI found/not-found pills, and
a callout naming `~/.cargo/bin` as the directory the snapshot missed. Every one of those is a
statement about **the environment the router's children inherit**.

The router computes it — "env.PATH = augmentPath(env.PATH ?? '', env.HOME);", `src/pool.ts:168` at `706cefb` calls `augmentPath(env.PATH ?? '', env.HOME)` — and
**does not publish it.** `ControlAPIClient` (`func servers() async throws(ControlAPIError) -> ServersResponse`, `ControlAPIClient.swift:113-182` at `706cefb`) declares nineteen
methods; none returns a path, an environment or a resolved search list, and `ControlHandler`
(`if path == "/servers", request.method == "GET" {`, `ControlHandler.swift:42-69` at `706cefb`) routes `/servers`, `/registry/search` and their siblings and
nothing PATH-shaped. `RemoveServerDialog`'s own docstring states the constraint: *"the control API
does not send them, and the control API is the only channel this app is permitted to use."*

So the numbers cannot be drawn. Reading the app's *own* login-shell `PATH` produces a different
number under the same label — the app is a GUI process launched by Finder, the router is a
launchd agent, and the whole reason R6 exists is that those two environments differ. Hard-coding
the mock's seven directories is the same lie with less work.

**But the sheet is still built, as a refusal.** This repo has resolved exactly this situation
twice and both times it kept the surface and told the truth on it: `SURF-010` records the pair
sheet as *"a refusal"* and `CASE-0142`/`CASE-0143` **pass** against the honesty requirement
because of it, and `HeldVersionSheet` (`DisabledAction(`, `SkillSheets.swift:85-95` at `706cefb`) draws both of its offers dimmed
in place with `SkillPresentation.writesNotYetAvailable` as the reason, per `DESIGN.md` §3.4's
*"Disabled dims in place and never disappears."* `path` follows that precedent: the frame, the
title, what it will show, and one sentence saying the router does not yet report it.

**Rather than** parking the sheet entirely, which was this plan's first reading and which the
out-of-family review called an excuse against the repo's own two precedents — correctly. And
**rather than** adding the endpoint here: a new control route is not one file. It needs the Swift
handler, the node equivalent in `src/control.ts`, a wire type, a client method, a fixture, and it
has to pass `scripts/acceptance/parity-control.sh`, which gates the two router implementations
against each other. That is router work with its own parity surface, and it stays out of scope
(§12).

### 4.2 The 30-day undo is not a thing the router does

The gate table's second row asks for *"multi-select, named count, 30-day undo stated on the
surface"*, and the mock's `confirm-remove` body says *"The configuration is kept for 30 days, so
this is undoable from Edit."*

`ConfigWriter.backUp` (`private static func backUp(path: String, fileSystem: FileSystem, now: Date) throws {`, `ConfigWriter.swift:84-101` at `706cefb`) copies the file aside and then keeps
`backupsKept` of them. `ConfigWriter.swift:28` — **`backupsKept = 5`**. Five writes, not thirty
days: six edits in an afternoon and the first backup is gone. The node router
(`if (existsSync(DEFAULT_CONFIG_PATH)) {`, `src/index.ts:136-140` at `706cefb`) writes one backup at install and prunes nothing. Neither number reaches
the app: there is no control-API method that reports a backup count, an age or a retention
policy, so even *"the last five writes are kept"* would be the app quoting a router constant it
cannot read.

So the surface states what is true and testable instead — the copy is written against
`ConfigWriter`'s actual behaviour and the sheet does not promise a window it cannot honour. A
promise about recoverability is the worst class of fabricated claim available here, because
someone acts on it.

**Multi-select is not built either**, and that half is scope rather than honesty:
`CleanupBoardModel` removes one candidate by name (`RemoveServerSheet`'s `let name: String`), and
adding a multi-select removal to Cleanup is a Cleanup-board feature with its own write path. It
is surfaced in §11 as a narrowing against the brief's gate table rather than absorbed silently.

### 4.3 `official` is drawn without the publisher grid

The mock's sheet is mostly a **definition** — what the mark asserts, and what it does not tell
you. That is product copy, not a measurement, and it is drawn verbatim.

Its middle section is not. *"Publishers currently matching, in this catalogue"* draws eight
publisher cards with per-publisher counts (`Anthropic · 12 servers · 4 skills`), and
`RegistryEntry` (`public struct RegistryEntry: Codable, Hashable, Sendable, Identifiable {`, `RegistryModels.swift:28-62` at `706cefb`) **has no publisher field**. What it has is
`source: .official | .smithery | .both`, which is which index supplied the row, not who published
it. Deriving a publisher from `name` does not work either: the fixture's three entries are
`github`, `deepwiki` and `ai.smithery/Hint-Services-obsidian-github-mcp`, so a namespace parse
would invent an ownership claim the index never made — which is precisely the claim the sheet
exists to explain the app *does not* invent.

The section is omitted and declared as a divergence in the fidelity manifest with M22/registry
ownership, so it is visibly owed rather than quietly dropped.

---

## 5 · The shape of the inventory

`app/Sources/MCPRouterKit/Shell/RouterSheet.swift`, three types.

**`RouterSheet`** — one enum, and the boards cannot hold a foreign case.

```swift
public enum RouterSheet: Equatable, Sendable {
    case servers(Servers), skills(Skills), cleanup(Cleanup)
    case inbox(Inbox), discover(Discover), activity(Activity)

    public enum Servers: Equatable, Sendable, Identifiable {
        case addServer, heldChange(server: String), removeServer(server: String)
    }
    // … one nested group per host
}
```

Each board model types its `sheet` as the nested group — `var sheet: RouterSheet.Servers?` — so
its host switches **exhaustively with no `default:` arm**, and `inboxBoard.sheet = .addServer`
does not compile rather than failing at runtime. The inventory is still one type, which is the
brief's clause; the groups are its cases, not siblings of it.

This is the third shape considered and the first that gets all three properties. A flat
`RouterSheet` with one host per board needs a `default:` arm, and the out-of-family review was
right that a `default:` turns "this board cannot present that" from a compile error into a
runtime view — a real loss. A flat enum with **one** exhaustive host is worse still here: only
`ServersBoard` and `SkillsBoard` take a `ShellModel`, so a single host would have to thread the
shell into `CleanupBoard`, `InboxBoard`, `DiscoverBoard` and `ActivityBoard`, coupling four
boards the repo has deliberately kept shell-free. Nesting costs nothing and gives up neither.

**`RouterSheet.Kind: String, CaseIterable, Sendable`** — the inventory, flattened for comparison
against the mock. Sixteen cases: the mock's thirteen plus `resetHistory`, `skillProvenance` and
`registryDetail`. `RouterSheet.kind` projects into it. A test compares `Kind.allCases` against the
mock's `id="sh-*"` set in both directions, so a fourteenth sheet drawn in the mock reddens the
build and a case added here without a mock sheet does too. Three kinds have no `RouterSheet` case
— `reconcile`, `readme`, `recommendation`, `analyzer` — and `Kind.owner` names who closes each.
`confirmRemove` maps from **two** `RouterSheet` cases, `.servers(.removeServer)` and
`.cleanup(.removeCandidate)`: one decision type, two subjects, stated here so it does not read as
drift.

**`SheetGate` — and the gate is routed through, not merely declared.** This is the review's
sharpest finding and it changes the design rather than the prose. A gate table sitting in Kit
that no call site consults is an inert lookup table: `SheetGateTests` would pass at 100% while a
button somewhere called `board.remove(name)` directly, and nothing would go red. So:

- `SheetGate.Action: CaseIterable` — the brief's seven rows plus `resetHistory`, which is
  destructive, is drawn twice in the build, and which the brief's table does not cover. Marked as
  the build's own row rather than smuggled in as the brief's.
- `SheetGate.gate(for:) -> Gate`, one of `.none(reason:)`, `.sheet(Kind)`, `.menuItem(accelerator: nil)`.
- **Each board model gains `request(_ action:)`**, which consults the gate and sets its own nested
  `sheet`. The destructive call sites stop assigning `sheet` directly and call `request` instead.
  A destructive action that bypasses the gate is then a call site that does not exist, and the
  acceptance-line test asserts at the board-model seam — press the action, observe the sheet the
  gate named — rather than asserting the table against itself.

There is no transient case on `Gate`, and there is no toast anywhere in the tree (§6), so a
transient gate is unrepresentable. That is a structural guarantee rather than a test, and it is
recorded as one; the *test* that can actually fail is that no `Action` above a one-child blast
radius resolves to `.none`, which is what a later downgrade would trip.

---

## 6 · The gate discipline, applied

Measured across the eight sheets today.

- **`role: .destructive` appears nowhere on the Mac.** Two hits in the whole tree, both on the
  phone (`Button(PairingCopy.entry(.unpairConfirm).actionLabel ?? "Unpair", role: .destructive) {`, `PairingFlowView.swift:349` at `706cefb`, "role: .destructive,", `PairedMacSettingsView.swift:374` at `706cefb`). `RemoveServerDialog`
  paints its Remove with `.foregroundStyle(ColorToken.fail.color)` (`ServerSheets.swift:274` at `706cefb`),
  which the brief names directly: *"a destructive alternative takes `.destructive` rather than a
  red foreground colour, so the platform styles it."*
- **Filled-primary counts disagree between two sheets doing the same job.**
  `RemoveServerDialog` makes Cancel `ProminentButtonStyle` + `.defaultAction` and Remove quiet —
  correct. Cleanup's `RemoveServerSheet` (`// Cancel leads, and the destructive button is never the default (§9).`, `CleanupSheets.swift:93-105` at `706cefb`) makes **neither**
  prominent, so a destructive sheet ships with no primary and no default action at all. The rule
  applied uniformly: Cancel is the filled primary and takes `.defaultAction`; the destructive
  action is a quiet text button with `role: .destructive`. That is `DESIGN.md` §3.4's *"Destructive
  is never the default"* and the brief's *"never a second filled one"* meeting in one shape.
- **Thirteen keyboard shortcuts over eight sheets**, and the coverage is uneven — `HeldChangeSheet`
  and `AddServerSheet` carry none. Every sheet gets exactly one `.defaultAction` and one
  `.cancelAction`, from the button roles.
- **There is no toast anywhere.** Fifteen occurrences of the word in `app/Sources`, every one of
  them a comment saying macOS does not toast a click. So the acceptance line is true today; the
  test is a drift guard, and per `SWIFT_PRACTICES.md` §7 it is deliberately broken once, watched
  go red, and restored, with that recorded in the evidence ledger.

**`SheetFrame` is not unified in this item.** It lives in `ServerSheets.swift:283` at `706cefb` and only the
Servers sheets use it; Cleanup, Skills, Inbox, Activity and Discover each hand-roll an equivalent
`VStack`+`padding`+`frame`. Unifying them changes the measured geometry of five surfaces at once,
which is an M23 fidelity change wearing a refactor's clothes, and it is not what the acceptance
line asks for. Surfaced in §11.

---

## 7 · Steps

Ordered so that **every phase compiles**. The first plan deleted the model enums in one step and
the view switches in another, which leaves four board views switching on a type that no longer
exists — caught by the out-of-family review. Phase B is per-board and atomic instead.

### Phase A — the inventory (`MCPRouterKit`)

A1. `app/Sources/MCPRouterKit/Shell/RouterSheet.swift` — `RouterSheet` with its six nested groups,
    `Kind`, `Kind.owner`, `SheetGate` with its eight actions and `gate(for:)`. Compiles alone;
    nothing references it yet.
A2. `app/Tests/MCPRouterKitTests/RouterSheetTests.swift`: `Kind.allCases` against the mock's
    `id="sh-*"` set both ways, parsed from `design/mcp-router-console.html` rather than pasted;
    every `RouterSheet` case projects a `kind` and a stable `id`; the four unhosted kinds have an
    owner and no case.
A3. Gate-table tests: every `Action` has a gate; no action above a one-child radius resolves to
    `.none`; the two rows whose host is not built (`reconcile` → M22, Stop Router → M20) carry
    their owner. These prove the table is *complete*; A3 is not the acceptance line on its own —
    B6 is the other half.

### Phase B — the conversion (`MCPRouterUI`), one board at a time

Each step retypes one model's `sheet`, rewrites that board's `.sheet(` modifier and its host
switch, and updates that board's assignment sites **in the same commit**, so the tree builds
between steps.

B1. **Servers** — `ServersBoardModel.Sheet` → `RouterSheet.Servers`; `ServerSheetHost` switches
    exhaustively; `serversBoard.sheet = nil`, `ShellModel.swift:341-344` at `706cefb`, `ShellCommandRouter.swift:150,235`,
    `board.sheet = .heldChange(server: server.name)`, `ServerInspector.swift:114` at `706cefb`, `board.sheet = .removeServer(server: server.name)`, `ServerInspectorSections.swift:155` at `706cefb`, `ServersBoard.swift:85,162`
    follow.
B2. **Skills** — same, plus `model?.skillsBoard.sheet = .marketplaces`, `ShellCommandRouter.swift:157` at `706cefb`, `SkillsBoard.swift:79,141,168`,
    `board.sheet = .heldVersion(skillID: skill.id)`, `SkillInspector.swift:203` at `706cefb`.
B3. **Cleanup** and **Activity** — same. `resetHistory` is one `Kind` with a case in each group.
B4. **Inbox** — both presentations at once. `.sheet(isPresented:)` × 2 → one `.sheet(item:)` over
    `RouterSheet.Inbox`, whose `.queuedItem(id:)` case carries the id and whose body keeps
    `board.sheetItem()`. `sheetItemID` becomes derived from `sheet` so there is one source of
    truth; `escape()` and `commitDefaultAction()` follow. `.pairPhone`'s dismissal routes through
    `session.close()` — `PairingSessionModel` is a `let` whose ticker outlives the view
    (`/// The pairing sheet's presentation.`, `InboxBoard.swift:47-56` at `706cefb`), and a bare `sheet = nil` would leave it running.
B5. **Discover** — `.sheet(isPresented:)` → `.sheet(item:)` over `RouterSheet.Discover`, with
    `.registryDetail(id:)` keeping `board.sheetEntry()`, and `.officialMark` added in the same
    step so the switch is exhaustive from the moment it exists. `OfficialMarkSheet` and
    `ChildPathSheet` are created here rather than in a later phase — the review found that
    deferring them leaves either a build failure or a known runtime hole across two phases.
B6. **Route the destructive actions through the gate.** Each model gains `request(_ action:)`;
    the destructive call sites call it instead of assigning `sheet`. Then the acceptance-line
    tests, at the board-model seam: for each gate-table row with a built host, invoking the action
    opens the sheet the gate names.
B7. `EvalsBoardModel`: delete `Sheet` and `var sheet` outright — never assigned, never presented,
    and `EvalsBoard.swift` has no `.sheet(` at all.

### Phase C — the gate discipline

C1. `RemoveServerDialog` and Cleanup's `RemoveServerSheet`: `role: .destructive`, one filled
    primary on Cancel, `.defaultAction` / `.cancelAction` on both.
C2. `RemoveServerSheet`'s consequence copy rewritten against `ConfigWriter`'s real behaviour
    (§4.2), living in `CleanupPresentation` beside `consequenceUnavailable`.
C3. Every remaining sheet audited for exactly one `.defaultAction` and one `.cancelAction`.
C4. A guard that no sheet action carries a bare `.foregroundStyle(ColorToken.fail…)` in place of
    a role.

### Phase D — content for the two new sheets

D1. `OfficialMarkSheet` body: the definition and the "what it does not tell you" section verbatim
    from the mock; the publisher grid omitted per §4.3. Entry point is the mock's own quiet
    `What is official?` control in Discover's controls row
    (`<button class="btn quiet" data-act="sheet:official" aria-label="What official means">`, `design/mcp-router-console.html:2851` at `706cefb`) — **not** the Publisher segmented filter beside it,
    which the build does not have and which is Discover scope.
D2. `ChildPathSheet` body: the refusal, per §4.1. Copy in `MCPRouterKit` so it is assertable
    without a host. It attaches to the **Settings** window, which is the brief's one requirement
    with no reference to build against.

### Phase E — the fidelity surfaces (M23's harness)

E1. `MeasureDump.Surface` gains a case per covered sheet, each arm building its own model inside
    its own arm as `MeasuredSurface` already requires (`main.swift:169-215`).
E2. `planning/fidelity/<surface>.layers.json` + `.pairing.tsv` per surface, following
    `settings.layers.json`'s declared-divergence discipline: every citation opens `Dn · `, every
    divergence names an owner, and the note states what is **not** enforced.
E3. Scope: the gate table's built rows — `quarantine`, `confirm-remove` on **both** its hosts
    (the review found gating Cleanup's and not Servers' arbitrary, and it is), `queued-detail` —
    plus the two sheets this item newly draws, `official` and `path`. Six surfaces. The remaining
    hosted sheets' surfaces are owed and named in §12: a manifest written without running its gate
    is the stale-ledger failure `mock-fidelity-gate.sh` opens by warning about.

---

## 8 · Parity inventory — what the five per-board enums did

Every behaviour of the collapsed enums, marked keep / port / drop.

| Behaviour | Where | Disposition |
|---|---|---|
| `id` disambiguates one sheet from another so SwiftUI re-presents | all five | **port** — `RouterSheet.id` keeps the same `"kind:subject"` shape |
| `heldChange(server:)` keyed by name | `public enum Sheet: Equatable, Sendable, Identifiable {`, `ServersBoardModel.swift:29-31` at `706cefb` | **keep** |
| `provenance(skillPath:)` keyed by **path, not name** — clients symlink skills, so a name is neither unique nor stable | "/// What `Read first…` opens.", `CleanupBoardModel.swift:107-113` at `706cefb` | **keep**, with its reason carried onto the new case |
| `removeServer` exists on two models with two subjects (a declared server, a cleanup candidate) | Servers + Cleanup | **keep both**, as two `RouterSheet` cases under one `Kind` |
| `resetHistory` on two models | Activity + Cleanup | **keep**, one case, two hosts |
| `EvalsBoardModel.Sheet.recheckAll` | `public enum Sheet: Equatable, Sendable, Identifiable {`, `EvalsBoardModel.swift:53-57` at `706cefb` | **drop** — never assigned, never presented, no `.sheet(` on that board |
| `sheetItemID` / `sheetEntryID` as the sheet's identity | Inbox, Discover | **port** — becomes the associated value; the fresh-lookup accessor stays |
| `pairing.isOpen` as a second presentation flag | `/// The pairing sheet's presentation.`, `InboxBoard.swift:47-56` at `706cefb` | **port** — `.pairPhone` case, `close()` on dismiss |

---

## 9 · Test strategy

**Seams, agreed here so the worker never tests at an unconfirmed one.**

- `MCPRouterKitTests` — `RouterSheet`, `Kind`, `SheetGate`, and every new copy string. No host, no
  render. This proves the table is *complete*.
- `MCPRouterUITests` — board models: `request(_:)` opening the gate's sheet, `escape()`,
  `commitDefaultAction()`, and the by-id lookup surviving a poll that changes the row. **This is
  where the acceptance line is proved**, because a gate asserted only against itself is a table,
  not a gate. Existing files extended rather than new ones invented:
  `ServersBoardSurfaceTests`, `InboxBoardTests`, `DiscoverBoardTests`, `CleanupRowActionsTests`,
  `ActivityResetEntryPointTests`.
- `mock-fidelity-gate.sh <surface>` — structure, geometry, copy and token layers for the six
  surfaces in E3. Not in `make all`; run directly, and its exit read as 0/1/3 rather than
  collapsed.
- **No UI-driven launch of the app for anything the model can answer.** `UI_VERIFICATION.md`
  rule 2: only the screen that changed, once, backgrounded, and the ledger at
  `planning/evidence/M18-acceptance.md` read first.

**Unit and contract coverage.**

1. `Kind.allCases.count == 16`, and its `rawValue` set equals the mock's `id="sh-*"` set plus the
   three build-only kinds — computed by parsing the mock, not pasted.
2. Every `SheetGate.Action` has a gate; none above a one-child radius is `.none`; the two unhosted
   rows carry an owner.
3. Every `RouterSheet` case projects a `kind` and has a distinct, stable `id`.
4. **For each gate-table row with a built host: invoking the action on its board model opens the
   sheet the gate names.** Five rows today — accept held changes, remove capabilities, approve a
   queued install, trip breaker/wake now (which opens nothing, and the test asserts that it opens
   nothing and the state changes), reset history.
5. A board model cannot hold another board's sheet — a compile-time fact under §5's nesting, so
   it is recorded as such rather than tested.
6. Each destructive sheet has exactly one filled primary and it is not the destructive action.
7. Inbox and Discover: open the sheet, mutate the underlying row, assert the sheet's subject
   reflects the mutation — the regression B4/B5 are written to avoid.
8. `EvalsBoardModel` has no `sheet` member — the deletion is the test.
9. The Cleanup removal copy states `ConfigWriter`'s real behaviour and contains no "30 day".
10. `ChildPathSheet` states the refusal and draws no directory list.

**Regression discrimination.** Tests 4, 7 and 9 are drift guards, so each is broken deliberately,
watched go red, and restored — recorded in the evidence ledger with the command run.
`SWIFT_PRACTICES.md` §7: *"A test that has never failed is not known to work."*

**Falsifiability at the base commit.** Every acceptance criterion below fails at `87e16dc` except
where marked. Two are marked and neither is counted as work: AC7 (no transient message) passes
today and is a guard, and AC4's `capability-delta` half passes because §3.1 found the sheet
already there.

---

## 10 · Acceptance criteria

1. One `RouterSheet` in `MCPRouterKit`; no free-standing per-board `Sheet` enum remains in
   `MCPRouterUI`. *(false at `87e16dc`: five of them)*
2. All seven `.sheet(` call sites use `item:`. *(false: three use `isPresented:`)*
3. `EvalsBoardModel.Sheet` is gone. *(false: it exists and is dead)*
4. The mock's thirteen ids each map to a `Kind`, and each `Kind` is hosted or carries an owner.
   *(false: no mapping exists)*
5. Every row of the gate table declares its gate, and **every row whose gate is a sheet has a test
   in which invoking that action opens that sheet**. Rows whose gate is `.none` or `.menuItem`
   are tested for that instead — the first wording of this criterion said every row "names the
   sheet it presents", which is not true of those two and was caught in review. *(false: no gate
   table, and no action routes through one)*
6. Each destructive sheet: one filled primary, not the destructive action, which carries
   `role: .destructive`. *(false: `RemoveServerDialog` uses a colour; Cleanup's has no primary)*
7. No destructive gate resolves to a transient message. *(**true at `87e16dc`**, and structural
   rather than tested — `Gate` has no transient case and the tree has no toast. The failable half
   is criterion 5's `.none` check)*
8. `official` is drawn from Discover and states nothing the registry does not report.
   *(false: absent)*
9. `path` is drawn from Settings as a refusal, with §4.1's reason on the surface. *(false: absent)*
10. `mock-fidelity-gate.sh` returns 0 for each of E3's six surfaces, or 1/3 with the finding read
    rather than paraphrased.
11. `make lint` exit 0; swiftlint 0 violations; the Swift test count does not fall.

---

## 11 · Scope-narrowing check

Compared against the brief, the gate table and spec §2's ten assumptions. The last four were
added after the out-of-family review found §11's first version incomplete.

- **Multi-select removal on Cleanup** — the gate table's second row asks for it; this plan does
  not build it (§4.2). It is a Cleanup write-path feature, not a sheet.
- **The 30-day undo window** — the gate table and the mock both state it; the router does not do
  it (§4.2). The surface states what is true instead. A correction rather than a narrowing.
- **`SheetFrame` unification** — the brief's mechanics imply one sheet shape; this plan keeps six
  (§6).
- **Four of thirteen sheets** — spec §2's fifth assumption parks `pair`'s transport, and the
  header parks four more on M19/M22. `path` is no longer among them (§4.1).
- **Seven of fifteen fidelity surfaces** — spec §3.5 asks for one per sheet; E3 builds six.
- **`Stop Router` has no gate this item can build** — the brief's seventh row wants a menu item
  with no accelerator, and there is no Router menu: `MenuCommand` declares six menus and
  `MenuCommand.allCases` has no router-stop case. M20 owns it. The row exists in `SheetGate` with
  its owner so the table is complete; the command does not.
- **`resetHistory` is an eighth gate row the brief does not have.** Added rather than omitted: it
  is destructive, it is drawn twice in the build, and a gate table that skipped it would be an
  inventory with a hole in exactly the place this item exists to close.
- **Servers' `confirm-remove` fidelity surface** — E3's first version gated Cleanup's remove sheet
  and not Servers', which is arbitrary for one `Kind` with two hosts. Both are in E3 now.
- **Keyboard shortcuts are not reduced.** Recorded because the review read §6's "thirteen
  keyboard shortcuts over eight sheets" as thirteen custom accelerators being stripped. They are
  not: the thirteen are the existing `.defaultAction`/`.cancelAction` occurrences in the build,
  the coverage is uneven, and C3 raises it to one of each on every sheet. Nothing is removed.

---

## 12 · Out of scope

- The pairing transport (`DEF-001`) — this item builds the panel and its wording only.
- `readme` and its Markdown renderer (M19); `reconcile`, `recommendation`, `analyzer` and their
  boards (M22); the Router menu that would host Stop Router (M20).
- A control-API endpoint for the child environment (§4.1) — router work with a parity surface of
  its own (`scripts/acceptance/parity-control.sh`), not a one-file addition.
- A `publisher` field on `RegistryEntry`, and Discover's Publisher segmented filter (§4.3, D1).
- Multi-select removal on Cleanup (§4.2).
- Fidelity surfaces for `pair`, `add-server`, `add-marketplace`, `capability-delta`,
  `skill-provenance`, `reset-history` and `registry-detail` — owed, and owed visibly rather than
  declared clean.

---

## 13 · Gate record

- Codebase grounding: `app/Sources/MCPRouterUI/Boards`, `app/Sources/MCPRouterKit/Control`,
  `app/Sources/RouterCore/Config`, `app/Sources/MeasureDump`, `src/pool.ts`, `src/index.ts`,
  `design/mcp-router-console.html`, `planning/fidelity/settings.layers.json`, `DESIGN.md` §3 §5
  §6 §8 §9, `planning/specs/spec-M18.md`, `planning/specs/spec-M23.md`.
- Mechanical path check: every backticked path in this plan resolved against the worktree.
- Out-of-family plan review: recorded in §14.

---

## 14 · Out-of-family review — record and disposition

Three lanes attempted, in the order `references/second-opinion-lanes.md` sets.

- **codex `gpt-5.6-sol`** — recorded down until 2026-08-27 at triage (`spec-M18.md` §3.7) and not
  re-attempted, per the rule that a lane known down is reported rather than retried into the
  ground.
- **grok `grok-4.6` at xhigh** — attempted, refused with `API error (status 402 Payment Required):
  Grok Build usage balance exhausted` and wrote a zero-byte report. Lane failure, same as at
  triage.
- **agy `gemini-3.7-flash-high`** — **answered.** The Google family, so the gate ran out of family
  and this is not a downgrade.

Briefed adversarially over seven questions at once, told to refute, and told that finding nothing
is a failed review. Verdict: **AMEND**, seven findings.

### Accepted, and the plan changed

- **The gate table was inert.** Its sharpest finding: `SheetGate` as first planned was a lookup
  table in Kit that no call site consulted, so `SheetGateTests` would pass at 100% while a button
  called `board.remove(name)` directly and nothing went red — *"a purely decorative test artifact
  that provides zero compile-time or runtime protection against un-gated destructive execution."*
  §5 now routes destructive actions through `request(_:)` and §9's acceptance test moved to the
  board-model seam.
- **AC5 was false for two of its own rows.** It read "every row names the sheet it presents",
  which cannot be true of `.none` and `.menuItem`. Reworded in §10.
- **AC7 was a tautology dressed as a test.** Asserting an enum lacks a case it does not have is a
  compiler fact. §10 now states it as structural and names the failable half.
- **`default: UnhostedSheet` gave up compile-time exhaustiveness.** Accepted; §5's nested groups
  fix it, and the reviewer's own second suggestion is what the nesting is.
- **Phase B did not compile.** Deleting the model enums before rewriting the views leaves four
  board views switching on a deleted type. §7's Phase B is per-board and atomic now.
- **`OfficialMarkSheet` was circular between B5 and D1.** Both sheets are scaffolded in B5.
- **`path` was an excuse.** Accepted, and this is the disposition worth reading twice: full
  parking was inconsistent with the repo's own two precedents for a surface over a mechanism that
  is not there — `SURF-010`'s pair sheet and `HeldVersionSheet`'s dimmed offers. §4.1 now builds
  it as a refusal.
- **§11 was incomplete.** Stop Router, `resetHistory`'s absence from the gate table, and Servers'
  ungated `confirm-remove` surface are all named now; the third became a fix rather than a
  disclosure.

### Rejected, with reason

- **"13 custom keyboard accelerators silently stripped."** Misread. The thirteen are the
  `.defaultAction`/`.cancelAction` occurrences in the *build*, not accelerators in the mock, and
  C3 raises coverage to one of each on every sheet. Nothing is removed. Recorded in §11 so the
  next reader does not have to re-derive it.
- **"Add the minimal `GET /env/path` endpoint — it is trivial."** Rejected on measurement rather
  than on scope. It needs the Swift handler, the node equivalent, a wire type, a client method, a
  fixture, and it must pass `scripts/acceptance/parity-control.sh`, which gates two independent
  router implementations against each other. The reviewer offered a second option in the same
  row — draw the sheet with an honest status card — and that one is taken.
- **"Show counts grouped by `source` instead of publisher."** Rejected by the repo's own note:
  "/// never off `sources.official`, which is a pre-merge, pre-slice count of a different", `RegistryPresentation.swift:198` at `706cefb` says a figure must come *"never off `sources.official`, which
  is a pre-merge, pre-slice count of a different set."* The count exists and does not mean what
  the grid would claim.

### Confirmed rather than found

The stale-subject reasoning in §2 was checked and upheld — *"passing only the ID in the enum case
and forcing the sheet view to resolve `model.sheetItem(id)` guarantees that SwiftUI's observation
system tracks live state"*. Recorded because it is the one place this conversion could have
regressed a bug the repo had already closed twice.
