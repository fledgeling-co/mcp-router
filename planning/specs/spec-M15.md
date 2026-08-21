# spec-M15 — Settings becomes its own window

| | |
|---|---|
| ID | M15 |
| Status | To Do |
| Category | mac · mock conversion |
| Depends on | M1 ✓ · M8 ✓ · M23 ✓ |
| Related | M17 (the Settings window is the tenth surface in its state count) · M18 (a sheet opened from a pane attaches here) |
| Brief | `planning/features-to-triage/M15-settings-window.md` |
| Source mock | `design/mcp-router-console.html` — which document is the design authority is M21's open question, recorded in §3.1 |
| Triage | 2026-08-22 · §2 is owner-facing · §3 is the pipeline record |

---

## 1 · Feature description (the brief, verbatim)

> # M15 — Settings becomes its own window
>
> **Depends on:** M1. **Supersedes:** the Settings half of M8.
> **Source:** `design/mcp-router-console.html`, PRD §9.5.
>
> M8 specifies Settings as a board in the console's source list. The mock moves it to a separate
> window, because that is what the platform does and because seven panes will not fit a board.
>
> ## What changes
>
> **A window, not a board.** Its own 33px titlebar, its own 200px source list, its own detail
> scroll. It is removed from the console's navigation list entirely, so the list now ends at
> Insights with the health card directly beneath.
>
> **Seven panes:** Router, Harnesses, Session analyst, Updates, Security, Advanced, Menu bar.
> Seven is past the point where a preferences tab bar works — the corpus puts the cut at five —
> which is what makes a source list correct here rather than merely available.
>
> **Minimise and zoom are greyed while close stays live.** This is the tell that identifies a
> macOS settings window at a glance, and it is present on every settings surface in the corpus
> pattern set. Build them as disabled controls that dim in place, not as hidden ones.
>
> **No Save button.** Every control applies on change, which is the platform convention and is
> already true of the controls M8 lists.
>
> **Reached from the app menu, `⌘,`, `⌘0`, or the Window menu**, where a tick tracks whether it is
> open. Escape closes it.
>
> ## Pane contents
>
> Each pane opens with its name and one line saying what it governs, then grouped inset cards:
> label left, control right on a shared axis, inset hairlines between rows.
>
> | Pane | What it governs |
> |---|---|
> | Router | endpoint, idle window, warm set, start at login, resolved child PATH (R6) |
> | Harnesses | adopt automatically, warn about duplicates, reconcile without asking (off by default), drift check interval |
> | Session analyst | on/off, primary and fallback model, which harnesses to read, frequency, notify |
> | Updates | app and skill check intervals, channel, what an update is allowed to do unattended |
> | Security | control token, trust decay policy, schema quarantine, retention window |
> | Menu bar | show the status item, what earns a badge, approve from the popover |
> | Advanced | log level and location, local store, reset, build identity |
>
> ## What is likely to go wrong
>
> **Two source lists sharing one row style.** The console's list and the settings list use the
> same row metrics and the same selection treatment. In the mock this was a real bug: the
> console's board switcher cleared the settings list's selection through an unscoped query, and
> the selected pane rendered with no fill. Each list owns its own selection and its own arrow-key
> traversal.
>
> **Whose chrome is it.** While Settings is frontmost it owns its own state; the console's
> toolbar subtitle and sidebar tallies are not Settings' to change.
>
> **Sheet attachment.** A sheet opened from a Settings pane — the analyst configuration, the PATH
> inspector — attaches to the Settings window, not to the console. The mock draws both windows in
> one page and cannot demonstrate this; the implementation has to get it right without that
> reference.
>
> Deep links: `?window=settings`, `?window=settings&pane=analyst`.
>
> ## Converting this to SwiftUI
>
> Use the **`Settings` scene**, not a hand-built `Window`. On macOS the standard settings window
> is what carries the disabled minimise and zoom, the correct titlebar height, and the `⌘,`
> binding, so building those by hand reproduces something the platform already gives. Confirm on
> the target macOS version that the scene disables both buttons; if it does not, disable them
> explicitly rather than hiding them.
>
> - The pane list is a `NavigationSplitView` whose sidebar is a `List` with `.listStyle(.sidebar)`.
>   Selection is the same accent fill at radius 8 the console's source list uses, so it comes from
>   the shared row view rather than a second implementation.
> - Each pane is its own `View` in `MCPRouterUI/Settings/`, and the seven are an enum so the count
>   is a compile-time fact rather than a list someone can forget to extend.
> - The grouped cards are `Form { Section { … } }` with `.formStyle(.grouped)`, which produces the
>   inset rounded card, the shared control axis and the inset hairlines without hand-drawing them.
> - No Save button means every control binds straight to the settings store.
>
> **The trap that produced a real bug in the mock:** two source lists sharing one row view. Give
> each list its own selection binding; a shared or global one lets the console's board switcher
> clear the settings pane selection.
>
> Acceptance: a structure dump of the Settings window contains seven pane rows, exactly one
> selected, and the pane body matching that selection (M23).

---

## 2 · Triage — 2026-08-22

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*

- **Where it shows up:** Settings *(customer-facing — becomes a window of its own instead of a place in the navigation list)*; the navigation list *(customer-facing — existing surface, loses a row)*; the app menu, the Window menu and the keyboard *(customer-facing — existing surfaces that change an item)*. Nothing internal or admin-facing changes.
- **What users will see — per surface:**
  - Settings (new window): its own title bar with minimise and zoom dimmed in place and close still live, a list of seven areas down the left — Router, Harnesses, Session analyst, Updates, Security, Menu bar, Advanced — and the chosen area's settings on the right in grouped cards, label left and control right on one shared line. No Save button; a control takes effect as you change it. Escape closes the window.
  - The navigation list: the Settings row goes, so the list ends at Insights with the health card directly beneath it.
  - The Window menu: a Settings item carrying a tick that tracks whether the window is open.
  - The keyboard: the two Settings shortcuts open the window rather than moving the selection in the list.
- **Behaviour changes:**
  - Anything Settings opens on top of itself belongs to the Settings window, not to the main one.
  - While Settings is in front, the main window's title area and its counts are left alone.
  - The four groups of settings the app has today keep working; they are re-housed among the seven areas rather than dropped.
- **Design reference:** the interactive console mock draws all seven areas and is the visual reference for this window, subject to the design-authority question recorded under M21.

**Assumptions**

- `[Layout]` Seven areas exactly, in the order the mock lists them. *(the mock draws seven and no more)*
- `[Layout]` Today's four groups — router connection, menu bar, warm set, control token — are re-housed among the seven rather than removed. *(nothing a person can set today stops being settable)*
- `[Layout]` The mock's own list, not the brief's sentence, sets the order; the two disagree about where Menu bar sits. *(the drawn artifact beats the prose describing it)*
- `[Experience]` The addresses quoted at the end of the brief locate a frame inside the mock; the app gains no way of being opened by one. *(nothing in the app reads an address today, and adding one opens a way in that nothing else needs — rather than building it alongside the window)*
- `[Experience]` A control naming a capability this product does not have is not built, even where the mock draws it. *(the app does not show what it cannot observe; the same rule already removed a graded-evaluation column from four boards)*
- `[Data & scope]` Settings stay per-person on this Mac and nothing about who can see or change them moves. *(no sharing surface exists today and this item adds none)*
- `[Operations]` With the router stopped the window still opens and says so, rather than refusing to open. *(the mock draws exactly that state for it)*
- `[Layout]` Every dimension the brief quotes is read from the app's own named measurements rather than typed into the view. *(a raw number in a board or shell file already fails the build gate, and the brief quotes several)*
- `[Operations]` The seven areas' own empty, loading and error wording is M17's to count; this item builds the window and its ideal state. *(one surface, two items, and M17 owns the count)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage M15` before the planner picks this up.*

---

## 3 · Grounding record — pipeline note, not owner-facing

Measured on the main checkout at `7b730ee`, 2026-08-22. Source reading unless marked otherwise.

### 3.1 The design-authority question this item inherits

Every M15–M22 brief cites `design/mcp-router-console.html`. The repository has not reconciled that
document with the one it calls the design of record, and the disagreement is quotable in both
directions:

- `DESIGN.md:8` — *"The reference implementation is `design/mocks/prototype.html`."* `ORCHESTRATOR.md:18`
  repeats it as the design authority row.
- `planning/test-campaign/` records the owner settling it: DEF-016's closure reads *"Closed 20 Aug
  2026, on the owner's decision that `design/mocks/prototype.html` remains the design of record for
  the Mac console"*, DEF-012 repeats the same decision, and `campaign.json`'s `designOfRecord` field
  is `design/mocks/prototype.html`.
- `PRD.md` §9.1 asserts the opposite — *"This supersedes the Instrument Panel direction recorded in
  `DESIGN.md` … until it is re-authored, the mock and this section are the authority and `DESIGN.md`
  is historical. Resolving that is tracked as M21."*
- `design/mcp-router-console-spec.md:3` says the console mock was *"built from `PRD.md`, deliberately
  ignoring the project's existing `DESIGN.md` and `design/mocks/prototype.html` per the brief"*.

**Neither the owner's DEF-016 decision nor the campaign names the console mock at all**, so the two
records do not actually contradict each other on their face — they were written about different
artifacts and never joined up. M21 is the only item that asks for the join. It is raised there and
is not re-asked here, because M15's substance survives either answer: a settings window reached from
the app menu is macOS platform correctness (`DESIGN.md` §3 rule 9, §8's `⌘,` row), not a property of
either visual direction.

### 3.2 What the built app has today

| The brief says | The build has |
|---|---|
| a Settings window | `Destination.settings` — a sidebar board. `app/Sources/MCPRouterKit/Shell/Destination.swift` has 8 cases and `settings` is the ungrouped tail |
| the `Settings` scene | absent. `app/MCPRouter/MCPRouterApp.swift:27-65` declares three scenes — `WindowGroup`, `MenuBarExtra`, and a `#if DEBUG` design gallery. Its line 21-22 comment already names this as the line M8 would change |
| seven panes | four groups in `app/Sources/MCPRouterUI/Boards/SettingsBoard.swift:116/157/176/205` — `.router`, `.menuBar`, `.warmSet`, `.controlToken` |
| `⌘,` opens the window | `MenuCommand.swift:250` binds `,`; `ShellCommandRouter.swift:105-108` maps it to `.select(.settings)`, so it moves the sidebar selection |
| `?window=settings` deep links | no URL handling of any kind. `onOpenURL`, `URLComponents` and `queryItems` return nothing across `app/Sources`; the `?pane=` strings in `Destination.swift:70-71` and `EvalsBoard.swift:22-23` are comments describing the mock |
| the pane list is seven | the mock agrees — `data-pane` in `design/mcp-router-console.html` yields exactly `router, harnesses, analyst, updates, security, menubar, advanced` |

**The brief's own two orderings disagree.** Its prose reads *"Router, Harnesses, Session analyst,
Updates, Security, Advanced, Menu bar"* and its table puts Menu bar before Advanced. `PRD.md` §9.5 and
the mock both put Menu bar sixth. Assumption above takes the mock.

### 3.3 Removing `settings` from the destination list is not a one-line deletion

Four things read that enum and each is a real edit: the digit accelerators are generated by
`ForEach` over the destinations in `MCPRouterApp.swift`'s sidebar command group (today `⌘1`–`⌘7`
over seven, with `settings` excluded already); frame restoration persists the `rawValue`; M6's
invariant `BoardRegistry.installed == Set(Destination.allCases)` is asserted by test; and
`ShellCommandRouter` routes `.settings` to a selection. The planner should treat this as the item's
riskiest edit rather than as removal of a row.

### 3.4 What the campaign already measured on this surface — cite, do not re-derive

`SURF-011` (*"Mac Settings board"*) fails both witness passes, and the structural verdict states
M15's premise directly: *"Settings is a board in the sidebar on both sides, so the separate-window
direction in PRD §9 is not yet built and is correctly absent here."* The `raster-visual` verdict
records a content divergence against `prototype.html` — the design carries Updates, Paired devices
and a Danger section, the build carries Menu bar, Warm set and Control token — and calls it *"a
content divergence needing an owner decision, not a styling defect."* Cases `CASE-0009`, `CASE-0016`
and `CASE-0111` all pass against the board as it stands. Nothing measures window chrome, because
there is no window.

That divergence is a third content set alongside the console mock's seven panes. The assumption
above resolves it in one direction — nothing settable today stops being settable — which is the
option that cannot lose a working control whichever mock wins.

### 3.5 What M23 gives this item, and what the item still owes

`scripts/acceptance/mock-fidelity-gate.sh <surface>` exits 0, 1 or 3 and drives eight layers. It
works today for `servers` only. Before it says anything about Settings this item must add
`planning/fidelity/settings.layers.json` (states, floors, the eight layers), a
`settings.pairing.tsv`, and a `Surface` case in `app/Sources/MeasureDump/main.swift`, which currently
declares `case servers` and nothing else. Without those three the gate exits 3 at the missing
manifest — which is the correct answer, not a passing one.

The brief's acceptance line — *"a structure dump of the Settings window contains seven pane rows,
exactly one selected, and the pane body matching that selection"* — is a `structure` layer assertion
and is reachable through that harness. `MeasureDump` renders headless under a `.prohibited`
activation policy, so it reaches a window the campaign's own accessibility lane could not.

### 3.6 Gate record

- Codebase grounding: source read across `app/Sources`, `app/MCPRouter`, `design/`, `PRD.md`, `DESIGN.md`, `planning/test-campaign/`.
- Out-of-family spec review: `agy` / `gemini-3.7-flash-high`, read-only, over all eight verdicts at once. `codex` is down until 2026-08-27 and was not attempted. Disposition in §3.7.
- Assumptions review: eight assumptions above, none reversing a decision recorded anywhere in the tree.

### Out-of-family review — record and disposition

Three out-of-family lanes were attempted for the required review. `codex` / `gpt-5.6-sol` is recorded
down until 2026-08-27 and was not attempted. `grok-4.6` refused with `API error (status 402 Payment
Required): Grok Build usage balance exhausted` and wrote a zero-byte report. `agy` /
`gemini-3.7-flash-high` timed out on its first invocation with `Error: timeout waiting for response`
and a zero-byte report, and **answered on one retry** — so the out-of-family gate did run, on the
Google family, and is not a downgrade. A fourth lane, `claude-fable-5` at high effort, was started in
parallel as the in-family fallback and also answered; it is recorded as a second reading rather than
as the gate, and where the two disagreed the repository settled it.

Both lanes were briefed adversarially over all eight verdicts at once, told to refute, and told that
finding nothing is a failed review. Verdict: **AMEND** from both. The dispositions that touch this
item are below; the full set is repeated in each spec it changes.

- **Accepted — every dimension a brief quotes must land in `MetricToken`.** `scripts/lint/no-raw-design-values.sh` runs a geometry-literal rule over `MCPRouterUI/Shell`, `Activity` and `Boards`, failing on any non-zero literal in `.frame(width:|height:|minWidth:|minHeight:|maxWidth:|maxHeight:)`, `.padding(`, `cornerRadius:`, `lineWidth:`, `spacing:` or `radius:`. The brief's `33px` titlebar, `200px` source list and radius 8 are exactly that shape, so a runner following the brief literally reddens `make lint`. Verified in the script; recorded as an assumption below rather than left for the planner to discover.
- **Accepted — the deep links are an orphan requirement across three briefs, not one.** M15, M16 and M20 each quote query-string addresses; no parser exists and no brief owns one. Already resolved for this item at §2's fourth assumption, and now recorded on M16 and M20 as well.
- **Not accepted for this item:** neither lane argued M15 is exposed to M21's answer, and both agreed its structure is direction-independent.
