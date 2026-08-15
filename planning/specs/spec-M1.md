# M1: Mac window shell, menu bar, keyboard

**Status:** Ready for Implementation Plan
**Depends on:** F1 (workspace), F2 (design system), F3 (control client)
**Design authority:** `DESIGN.md` · **Design representation:** `design/mocks/html/m1-mac-shell.html`
**Practices:** `planning/practices/SWIFT_PRACTICES.md` (binding), `CODING_PRACTICES.md`,
`NEW_PROJECT_BEST_PRACTICES.md`

---

## Feature description

*(verbatim from `planning/features-to-triage/M1-mac-shell.md`)*

> # M1 — Mac window shell, menu bar commands, keyboard
>
> **Depends on:** F2, F3.
>
> The three-zone window every other Mac surface renders into: 33pt titlebar, 52pt unified
> toolbar, 256pt sidebar with inset-rounded selection at radius 8.
>
> - The sidebar's two groups (Running / Library) with live counts, and the at-rest readout
>   in its footer — child processes running against servers declared, plus the real
>   last-60s trace. **Only numbers the router observes**; no invented memory saving.
> - The complete menu bar: MCP Router / File / Edit / View / Window / Help, every command
>   reachable, with the shortcut map from DESIGN.md §8 bound and a visible accent focus
>   ring.
> - Window state restoration, and the scroll-edge effect where content meets the toolbar.
>
> Deep link: `design/mocks/prototype.html?only=mac`.

---

## The command inventory — the authoritative list

A11 below asserts the shipped menu bar against **this table**, not against the code's own
model. An inventory that defines itself is not an inventory; this is the external oracle, and
the test fails in both directions — a command here and missing from the menu bar, or a command
in the menu bar and missing here.

**Three of the four columns are that oracle; the fourth is a contract, and the difference is
load-bearing.** Menu, Command and Shortcut are facts a model cannot check about itself, and the
acceptance walk compares them against the running menu bar exactly as described above. The
availability column is a different kind of claim: it records the answer in
`MenuCommand.CommandContext.none` — no board installed, nothing selected, which is the world M1
itself shipped — and `MenuCommandTests` compares it against `MenuCommand.availability` in both
directions. It is **not** the availability of a build that has boards installed, and reading it as
one is a mistake this document has now caused twice.

`MenuCommand.availability(in:)` *computes* the live answer from the installed boards and the
current selection, so a hand-written column of live answers is a restatement of a rule that
already exists — and it went stale silently at M3 (Servers) and again at M4 (Skills) while
reading as authoritative. So `scripts/acceptance/mac-shell.sh` derives the live expectation by
compiling `MenuCommand.swift` and asking it, with the registry's installed set and no selection,
rather than reading this column. That leaves each oracle where it can be right: the table for
what exists and what it is bound to, the model for what it can do right now.

| Menu | Command | Shortcut | Availability in M1 (`CommandContext.none`) |
|---|---|---|---|
| MCP Router | About MCP Router | — | enabled |
| MCP Router | Settings | ⌘, | enabled |
| MCP Router | Hide MCP Router | ⌘H | enabled |
| MCP Router | Hide Others | ⌥⌘H | enabled |
| MCP Router | Show All | — | enabled |
| MCP Router | Quit MCP Router | ⌘Q | enabled |
| File | Add server… | ⌘N | surfaceAbsent |
| File | Add marketplace… | ⇧⌘N | surfaceAbsent |
| File | Pair iPhone… | — | surfaceAbsent |
| File | Export library… | ⌘E | featureUnbuilt |
| File | Close | ⌘W | enabled |
| Edit | Undo | ⌘Z | enabled |
| Edit | Redo | ⇧⌘Z | enabled |
| Edit | Cut | ⌘X | enabled |
| Edit | Copy | ⌘C | enabled |
| Edit | Paste | ⌘V | enabled |
| Edit | Select All | ⌘A | enabled |
| Edit | Find | ⌘F | surfaceAbsent |
| Edit | Reset server | ⌘R | surfaceAbsent |
| Edit | Remove server | ⌘⌫ | surfaceAbsent |
| View | Activity | ⌘1 | enabled |
| View | Servers | ⌘2 | enabled |
| View | Skills | ⌘3 | enabled |
| View | Discover | ⌘4 | enabled |
| View | Inbox | ⌘5 | enabled |
| View | Evals | ⌘6 | enabled |
| View | Cleanup | ⌘7 | enabled |
| View | Show sidebar | ⌃⌘S | enabled |
| Window | Minimize | ⌘M | enabled |
| Window | Zoom | — | enabled |
| Window | Bring All to Front | — | enabled |
| Help | MCP Router help | — | enabled |
| Help | What the router actually does | — | enabled |
| Help | Report an issue | — | enabled |

One row per command, deliberately: a compound row ("Cut / Copy / Paste") cannot be parsed
unambiguously, and an oracle a test has to guess at is not an oracle. `MenuCommandTests` parses
this table out of this file and compares it against `MenuCommand.allCases` in **both**
directions.

**Six titles here are title case against `DESIGN.md` §6, and that is the kit winning.** `Hide
Others`, `Show All`, `Close`, `Select All`, `Minimize` and `Bring All to Front` are items **macOS
contributes itself** — the app does not build them and cannot rename them. The strings above were
measured from the running menu bar rather than guessed, and `DESIGN.md`'s own precedence rule
settles the conflict: where the document and the macOS 27 kit disagree, the kit wins. Writing
`Minimise` here would have produced an inventory that can never match the menu bar it describes.

**Fourteen of the thirty-three are the system's**, marked by `MenuCommand.isSystemProvided`. That
matters for how A19 is checkable: macOS also contributes items this inventory does **not** list —
Services, Close All, Delete, Writing Tools, AutoFill, Start Dictation, Emoji & Symbols, Show Tab
Bar, Show All Tabs, Enter Full Screen, Minimize All, Zoom All, Fill, Center, Move & Resize, Full
Screen Tile, Remove Window from Set, Arrange in Front, the tab commands, the Window menu's list of
open windows (including the Debug-only design gallery), and the whole Apple menu. All of those
were enumerated from the running app. So A19's two directions are asymmetric on purpose:
*completeness* is checked over the whole inventory, and *no extras* is checked over the commands
the **app declares**, with the system's contributions excluded by name rather than by tolerance.

`…` marks a command that opens a further view; its absence means the command commits now
(§3.4). Three disabled reasons exist and no fourth may be invented at a call site:
`surfaceAbsent` → "This part of the app isn't built yet.", `featureUnbuilt` → "This feature
hasn't been built yet." and `needsServerSelection` → "Select a server first." M1 uses only the
first and the second; the servers board switches these to the third or to enabled.

**M14 added the second, and the row it changed is `Export library…`.** The two were one case until
then, which is how `Pair iPhone…` came to tell the user the app was not built for two items after
M6 shipped the pairing sheet that command opens: with a single refusal meaning "no", nothing could
distinguish *this build has no board for that destination* from *the product has no such feature*,
so a command kept the answer it was given at M1 and no test could see it had stopped being true.
**`Pair iPhone…`'s row above is deliberately unchanged** — this column is the answer in
`CommandContext.none`, where no board is installed, so `surfaceAbsent` is still what it reports;
what changed is the answer with the Inbox board installed, which is not what this column records.

**What that switch cost, recorded here because the table is where the next reader will look.**
M11 measured the built app with all eight boards installed and found `Add server…`, `Add
marketplace…` and `Find` dimmed and carrying no reason at all. The rule was right and both tests
of it passed: `MenuCommand.availability(in:)` returned `.enabled` for each, and `SkillsMenuTests`
had asserted exactly that since M4. What no test covered was **which context the menu item asked**
— `CommandItem` read `MenuCommand.availability`, the `.none` shorthand, so the whole live-context
mechanism reached the disabled *reason* through `ShellMenuReasons` and never reached the disabled
*state*. Two contexts, one menu, and §3.4 broken in both directions: a command whose surface had
shipped was permanently unusable, and silent about why. The item now resolves its availability
from the live context, the reason walker clears an annotation that has stopped being true, and
`ShellIntegrationTests.commandItemsReadTheLiveContext` fails if either regresses.

---

## Acceptance criteria

The oracle for every later stage. Evidence must be a measurement, an exercised interaction, or
a red-green test — never "it looks right". An *exercised interaction* means the built app is
launched and driven through the accessibility tree, which is the lane
`scripts/acceptance/shells.sh` already establishes with a real pixel sample and a real AX walk.

### Chrome and tokens

| # | Clause | Evidence type |
|---|---|---|
| A1 | The window is a three-zone shell whose titlebar, unified toolbar and sidebar measure **33 / 52 / 256**, and each rendered measurement is asserted **against `MetricToken`'s own value** rather than against a copied number — so changing the token moves the assertion | measurement of rendered frames compared to `MetricToken.titlebar/.unifiedToolbar/.sidebar`, plus A3's gate proving no literal was written |
| A2 | Sidebar selection is a **flat inset rounded fill** at `selectionRadius` / `selectionInset` with accent text — never a full-bleed bar (§3.1) | measurement against the tokens + red-green test |
| A3 | No file added by this item writes a raw colour, size, radius or font size. The gate scans `MCPRouterUI`, `app/MCPRouter` and `app/MCPRouterIOS`; anything this item adds to `MCPRouterKit` is **data only** and renders nothing, which is asserted separately by the kit's no-UI-import rule | `no-raw-design-values.sh`, extended with the sidebar-row check in A4 |
| A4 | The sidebar row's **content frame** is `MetricToken.tableRows` — not a literal and not a repurposed inset — and every destination row renders at **one** height, which is one of `DESIGN.md` §2's documented sidebar row sizes (`rows 24/32/40`), parsed out of the document. The rendered 32 is AppKit's own sidebar inset around a 24pt content frame, not a number this item chose | red-green test that the content frame reads the token + exercised AX measurement that all destination rows share one height and that it is in §2's documented set |
| A5 | Both appearances render: every token the shell uses resolves to its authored light value under a light appearance and its dark value under dark, and light is never an inversion (§2) | red-green test over the shell's token set in both appearances + a rendered light-appearance pixel sample |
| A6 | The four indicator colours are used **only** for their stated meanings. Nothing in the shell is accent, live, attention or fail decoratively (§2) | red-green test enumerating every indicator-coloured element in the shell and its justification, failing on an unclassified use |
| A7 | Every string the shell renders takes a role from the eight-role ladder, and monospace appears **only** on instrument data — counts, durations, the loopback address — never on prose (§2) | red-green test over the shell's type roles |
| A8 | Liquid Glass appears on floating chrome only — menus. The window's content is **opaque**, and there is no glass on glass (§3.3) | red-green test on the material of the window's own background |
| A9 | The toolbar carries borderless monochrome symbols, at most three groups and one trailing primary action, and its **title names the view, not the app** (§3.7, §3.4) | red-green test + AX assertion that the toolbar title equals the selected destination's name |
| A10 | The cursor is the arrow throughout app chrome; no shell element sets a pointing-hand (§3.8) | red-green test over the shell's cursor declarations |

### The sidebar and the at-rest readout

| # | Clause | Evidence type |
|---|---|---|
| A11 | The sidebar carries exactly two named groups in order — **Running** (Activity, Servers, Skills) and **Library** (Discover, Inbox, Evals, Cleanup) — plus an ungrouped **Settings** | red-green test over the destination model |
| A12 | Group headers are **sentence case**, never tracked uppercase, and no uppercasing transform is applied anywhere in the shell (§3.2) | red-green test on the literal strings and on the absence of a case transform |
| A13 | Badges derive only from what the router reports: Servers = count where `needsAttention`, Cleanup = count where `neverUsed`. **Skills and Inbox carry no badge** — Skills has no endpoint at all, and Inbox means the *phone's review queue* (§9), which M6 owns and which the router does not serve today. `heldChanges` is **not** an inbox: it is a server's held tool-surface change and is already counted by `needsAttention` on the Servers badge | red-green test per derivation against fixtures, plus a test that fails if a badge is introduced for a destination with no router-observed source |
| A14 | A four-digit badge does not change a row's height or move its icon; the **label** truncates and the badge does not | measurement at a forced overflow |
| A15 | The readout shows child processes running against servers declared, both from the router's `/servers` response, and **no figure appears that the router does not measure** — in particular no memory saving anywhere | red-green test over the derivation + a test asserting no fabricated metric renders |
| A16 | **Liveness is specified, not implied.** The readout refreshes on a stated cadence (`ServerStateTracker`'s poll interval); each sample is timestamped; samples older than 60s are evicted; and a poll that fails leaves the previous samples in place rather than inventing a zero | red-green test driving a fake clock across the window boundary, asserting eviction at 60s, a retained sample at 59s, and no synthesised sample across a failed poll |
| A17 | The trace names the window it actually holds: with fewer than 60s of samples it reports the window it has rather than claiming a full minute | red-green test at a partial sample count and at a full one |
| A18 | When the router is not running the counts are **absent, not zero** — a zero is an observation and the router made none | red-green test on the `offline` scenario asserting no count renders |

### The menu bar and the keyboard

| # | Clause | Evidence type |
|---|---|---|
| A19 | The menu bar carries exactly six menus and its commands equal **the command inventory table above**, in both directions — a command in the table and absent from the menu bar fails, and so does the reverse (§3.9) | red-green test against the inventory as an external fixture + AX walk of the running app's menu bar |
| A20 | Every shortcut in `DESIGN.md` §8 that is a ⌘-combination is bound to the menu item the inventory names, with the key and modifiers the document states | red-green test that **parses §8 out of `DESIGN.md`** and compares in both directions, the way `DesignTokenParityTests` does for tokens |
| A21 | **The shell routes the three bare keys rather than declining them.** `Space`, `Return` and `Esc` are not consumed by the shell; a content surface can claim each and receive it. M1 ships the routing and proves it with a test surface that claims all three | red-green test: a test surface installed in the content zone receives each of the three, and the shell is shown not to swallow them |
| A22 | A command whose surface is not yet installed is **present, disabled, and carries its stated reason** — never hidden (§3.4) | red-green test on the reason string + AX assertion that the item exists, reports itself disabled, **and carries the reason** |
| A23 | ⌘1–⌘7 and ⌘, change the **selected destination**, not merely the title: the sidebar row reports itself selected and the toolbar title follows it | exercised interaction asserting the row's selected state *and* the title |
| A24 | Keyboard focus is visible, accent-bound and 2pt | measurement of the rendered ring against `MetricToken.focusRing` and `ColorToken.accent` |
| A25 | Tab order is **`DESIGN.md` §8's — sidebar → table → inspector** — for the elements that exist. M1 has no table and no inspector, so it ships sidebar → content and the order is asserted as a *prefix* of §8's, with the content zone's own children appended by the surface that owns them. The shell never places a chrome element between sidebar and content | red-green test asserting the shell's order is a prefix of §8's and that nothing is interposed |

### States, motion, and the boundary

| # | Clause | Evidence type |
|---|---|---|
| A26 | The shell renders **all nine `DESIGN.md` §5 states plus `unauthorized`**, each driven by a named `FixtureControlAPIClient` scenario, each asserting a specific observable rather than that it merely rendered | one test per state |
| A27 | Every control the shell ships carries **default / hover / focus-visible / active / disabled** (§5) | red-green test per control per state |
| A28 | The offline and unauthorised copy is `ControlAPIError`'s **verbatim**, in the app itself — one wording per state (§6). The readout's compact form renders `headline` unchanged; it does not paraphrase | red-green test asserting equality with the error's own strings, an AX assertion that the **running app** carries them, and their presence in `m1-mac-shell.html` |
| A29 | The readout's loading state is a **skeleton at the readout's own geometry**, never a spinner. Pane-level skeletons are not M1's: the boards own their row geometry | red-green test comparing the skeleton's height to the populated readout's |
| A30 | Motion is springs, not durations; interruptible; transform and opacity only; never opacity-from-zero on entry. Row selection is **immediate with no transition on the fill**; a badge count change is a **scale bump with no colour flash** | red-green test per moment |
| A31 | `accessibilityReduceMotion`, `accessibilityReduceTransparency` and `accessibilityDifferentiateWithoutColor` are all honoured, and each removes the effect **without removing the state change or the information** (§7) | red-green test per setting |
| A32 | The selected destination and the sidebar's visibility survive quit and relaunch; a stored destination this build no longer has falls back to Activity rather than a blank pane | exercised interaction (set, quit, relaunch, assert) + red-green test on the unknown-value fallback |
| A33 | The window **frame** survives quit and relaunch, restored by AppKit's frame autosave | exercised interaction: move and resize the window, quit, relaunch, compare the frame — not merely that an autosave name is set |
| A34 | The scroll-edge separator is **absent at scroll offset 0 and present above it**, and the transition is exercised against a real scrolling window rather than only a derived Boolean | red-green test on the derived state at the threshold **plus** an exercised scroll on the running app with a rendered assertion |
| A35 | Every destination row, badge, group header and the readout carry an accessibility label a screen reader reads | AX walk of the running app |
| A36 | The shell reaches the router **only** through F3's client and its SSE stream, both of which speak the same loopback control API. It opens no socket, no file and no process of its own | red-green test + a **source-level gate** in the lint script forbidding `URLSession`, `Process`, `FileManager` and raw socket use anywhere in the shell's files — a dependency graph cannot see a direct call |
| A37 | Every state above renders with **no router running**, against the fixture double | the suite passing on a machine with no daemon |

**Explicitly out of scope for M1.** The boards that fill the content zone — Activity (M2),
Servers (M3), Skills (M4), Discover (M5), Inbox (M6), Evals/Cleanup (M7), Settings (M8). Also:
the menu-bar extra (`NSStatusItem`) and its popover, any sheet, the inspector, daemon
lifecycle, pairing, and any change to the TypeScript router or `install.sh`.

---

## Triage — 2026-08-14

**Ready for Implementation Plan.** Revised after an out-of-family spec review returned REJECT
with 12 HIGH findings; every one is addressed above or recorded below as a stated deviation.

### Grounding — what already exists

`MCPRouterUI` carries the tokens bound to SwiftUI, the control ladder, `selectionFill`,
`focusRing`, `IconView` over a closed symbol set, and the nine `SurfaceState` containers.
`MCPRouterKit` carries `MetricToken`, `ControlAPIClient`, `FixtureControlAPIClient` with a named
scenario per state, and `ServerStateTracker`. The shell is assembly over these.

**The tracker, and the single-channel question.** `ServerStateTracker` merges a `GET /servers`
poll with `ControlEventStream`. That stream is F3's SSE client for `/usage/stream` — the **same
loopback control API**, not a second channel. M1 nonetheless constructs the tracker
**poll-only**, with the stream left nil: the readout needs running counts, which the poll
carries, and the call stream is what M2's Activity board is for. That keeps M1's surface area
smaller and makes A36 a narrow claim rather than a broad one.

### Where the code goes, and why

`app/MCPRouter` is **not a SwiftPM target**, so nothing there can be reached by `swift test` —
a shell whose logic lived there would fail every clause that says "red-green test". So:

- **`MCPRouterKit`** — the destination model and the menu command model, as pure data. No UI
  framework, so §8's separation holds and the parity test can read them.
- **`MCPRouterUI`**, under `#if os(macOS)` — the shell's views and state derivations. Covered by
  the raw-values gate, which already scans that directory.
- **`app/MCPRouter`** — assembly only: the `App`, its `Scene`, and `.commands` built from the
  model.

### Stated deviations from DESIGN.md, and why

**1 · No inert action buttons (§5 offline and empty).** §5 wants the offline state to "say so and
offer to start it", and F3 already ships `actionLabel` "Start the router" and "Re-pair…". The
control API exposes **neither operation** — starting the daemon is process lifecycle and
re-pairing is a flow M6/M8 own. A button that does nothing when pressed is worse than no button
and fails §5 more badly than omitting it. **M1 therefore renders the condition and the advice
with no action control**, and the two actions arrive with the items that can perform them. This
is a deliberate, recorded deviation rather than an oversight, and it is the first thing worth a
human's opinion.

**2 · Overflow's inspector half (§5).** §5 requires a truncated value to be available in full "in
the inspector". M1 ships no inspector. A14 therefore covers truncation and the full value on the
accessibility label; the inspector half is inherited by the surface that ships one.

**3 · Sidebar row sizes (§2).** §2 documents `rows 24/32/40` inside the sidebar cell, and
`MetricToken` reads only a cell's leading scalar, so 32 and 40 are unreadable to the parity
check. M1 uses **one** row size and takes it from `MetricToken.tableRows` (24, the documented
dense-list row) rather than inventing a literal or repurposing a horizontal inset as vertical
padding. Tokenising 32/40 is a shared-surface change, reported below and not made here.

### Assumptions recorded — autonomous run, no human to ask

1. **The app is "MCP Router", not "Conduit".** `prototype.html` says Conduit throughout;
   `DESIGN.md`'s precedence rule makes the prototype stale where it disagrees, and both the brief
   and `CFBundleName` say MCP Router.
2. **Settings is a sidebar destination and ⌘, selects it.** The prototype puts it in the sidebar;
   `DESIGN.md` is silent. M8 may move it to its own scene, which is a one-line change.
3. **A disabled command reads "This part of the app isn't built yet."** A disabled macOS menu
   item shows its reason in a help tag and nowhere else, and in a shell-only build the true
   reason is that the surface is absent. A state-shaped reason would be a lie; hiding the command
   would break §3.9. **M14 narrowed this**: that sentence is now `surfaceAbsent`'s alone, meaning
   this build has no board for that destination. A command whose *feature* has never been built
   reads "This feature hasn't been built yet." instead, and in M1's shell-only world
   `Export library…` is the one command that does.
4. **The trace is the app's own record of the router's polls.** The router publishes no history
   of running counts, so the 60s window is what the app was told, timestamped and evicted per
   A16. A17 requires it to name the window it actually holds.

### Open questions — raised, not guessed

**Q1 · §8's `Space` has no operation behind it.** §8 binds Space to "toggles the selected row's
breaker", but `ServerPatch` is exactly `projects · warm · idleMs · placard` and
`ControlAPIClient` carries **no start and no stop**. The breaker is a readout of a child process
the *router* starts when an agent calls a tool. Either Space toggles `warm` — a real mutation,
but a different sentence, and the lever would not move when pressed — or the router needs an
operation it does not have (R3), or §8 is aspirational here. M1 routes Space to the content zone
(A21) and binds nothing, so whichever answer lands, M3 can take it.

**Q2 · §8's `⌘R` "Reset the selected server" has no exact operation either.** The nearest is
`reindex`, which re-reads a server's tool surface; `resetUsage` is global and clears counters for
everything. Equating "reset" with "reindex" is an interpretation, not a fact, so M1 does **not**
make it: ⌘R is present, disabled, and its binding to a concrete operation is M3's to settle.

**Q3 · The offline and empty states ship without their action** — see stated deviation 1. Worth a
decision, because the alternative is for M1 to grow daemon lifecycle.

### Deferred children discovered

| Title | Suggested deps | Why it is not M1 |
|---|---|---|
| Menu-bar extra: status item, popover, attention pip | M1, M2 | A second window class with its own Liquid Glass surface and lifecycle. The brief's "menu bar" is the six-menu command surface. |
| Router lifecycle: start and stop the daemon from the app | M1, R4 | What "Start the router" needs to stop being an inert label. Process management, not a control-API call. |
| Sidebar row-height tokens in `DESIGN.md` §2 | — | 24/32/40 live inside another cell's prose and are invisible to the parity check; they want their own rows, as the control ladder and the 56pt servers row already got. |
| Resolve §8's `Space` and `⌘R` against the control API | M1, R3 | Q1 and Q2 above. |

### Shared-surface changes wanted and deliberately skipped

- **`DESIGN.md` §2 chrome table** — sidebar rows 24/32/40 want their own rows so `MetricToken`
  can carry them. Not made: `DESIGN.md` is the shared design authority every runner reads.
- **`ColorToken` / `MetricToken` / `SurfaceState` / `ServersBoardCopy`** — untouched. The shell
  reads what F2 merged rather than adding a parallel set.

### Harness note carried into the plan

Browser measurement is unavailable on this machine for the HTML representation:
`document.fonts.size` reads 0 under Obscura and every font stack — including bare `sans-serif` —
measures zero-width text, so advance widths there are meaningless. Confirmed on the merged,
already-accepted `f3-connection-states.html` as well as this item's sheet, so it is an engine
property rather than a defect in either file. It costs M1 nothing: the shell is a native app and
its evidence lane is the Swift suite plus `scripts/acceptance/shells.sh`, which samples real
pixels by window id and walks the real accessibility tree. **No clause above is evidenced by a
browser screenshot.**
