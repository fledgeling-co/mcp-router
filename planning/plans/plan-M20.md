# plan-M20 — menu bar, status item, and the notification banner

Spec: `planning/specs/spec-M20.md` · brief `planning/features-to-triage/M20-menubar-status-notification.md`
Design of record: `design/mcp-router-console.html` (settled 2026-08-22)
Plan size: **Large**. Two new top-level menus with fourteen new commands, a refusal type that
gains per-command copy, a thirteen-item title-case conversion that three oracles read, a popover
header and decision band, a second notification category with its own closed action set, and edits
to two design documents, one merged spec table and one acceptance script.

Baseline: `87e16dc`, tree clean apart from `WORK-ORDER.md`.

---

## 1 · Task

Three pieces of system chrome, drawn in full in the mock, converted to the three system APIs the
brief names: `CommandMenu` for the two new menus, the existing `MenuBarExtra` popover for the
decision band, and a second `UNNotificationCategory` for the analyst finding.

The item is not "add two menus". It is four things with separate failure modes:

1. **A refusal vocabulary that has outgrown one sentence.** `.featureUnbuilt` carries a single
   generic string because exactly one command has ever held it. Eight will after this. Its own
   doc comment names the moment and the tie-break: *"both are larger than the item that added the
   case, and both become worth doing the moment a second command takes it."* That is `D-m14-a`.
2. **An accelerator map that three documents disagree about**, plus a conflict the triage note did
   not reach: the mock binds `⌘R` to `Re-index Manifest` while `DESIGN.md` §8 binds it to
   `Reset the selected server`.
3. **An invariant this item deliberately widens.** `InboxBoundaryTests.nothingOutsideTheWindowInstalls`
   asserts that no path outside the window declares a server. The popover's `Approve` is a path
   outside the window that declares a server. It is amended in the open, with the notification
   half left strictly closed and given more coverage rather than less.
4. **A number the mock draws that the router does not observe.** `Resident 214 MB`.

## 2 · Approach

Everything decidable lands in `MCPRouterKit`, because `app/MCPRouter` is not a SwiftPM target and
a decision written beside a `Scene` has no evidence lane. `MCPRouterUI` gains placement only. The
one exception is the two new `CommandMenu` builders, which are assembly and whose *contents* come
from `MenuCommand.inMenu(_:)` exactly as the six existing groups do.

Four slices, committed separately, in dependency order: the menu bar, the popover, the
notification, then the conversion artifacts.

**Delivery record, added by gap-fix 1.** The first pass delivered Slice A only, and did not compile:
`MenuCommandAvailability.swift:110` held a bare `nil` in statement position, so no test in the suite
ever ran against it. Slices B, C and D produced no code, no tests and no artifacts — seven names this
plan promises each occurred in exactly one file, and that file was this one. Gap-fix 1 fixed the
keyword and built all three. Where this plan and what shipped differ, the difference is stated at the
step rather than left for a reader to find: step 12 gained a third condition (§5), step 13 took the
second string it offered and did **not** take its `(prominent)` (§5), and §3.6's chord arithmetic was
wrong in two ways (§3.6).

---

## 3 · Decisions

Four forks were referred before this plan was written. `codex` / `gpt-5.6-sol` is usage-limited
until 2026-08-27 and `grok-4.6` answered `402 Payment Required` with a zero-byte report — both
exactly as `spec-M20.md`'s own review record predicted. `agy` / `gemini-3.7-flash-high` answered
and **is the out-of-family gate**. `claude-fable-5` at high effort answered as a second reading on
the two forks where the Google lane recommended deleting a stated requirement. Both were briefed
adversarially and told that finding nothing is a failed review. Where they disagreed the
repository settled it.

### 3.1 The popover's `Approve` — build it, resolved-only, preference ON

**Google refused it outright**: keep `Review…` and `Not now`, on the ground that the popover row
shows a capability summary rather than the command line, args and env keys the review sheet shows.

**Not taken.** It deletes a requirement stated in the brief, in `spec-M20.md` §1 verbatim and in
`PRD.md` §9.8, and it fails the brief's own acceptance line — *"a structure dump of the popover
shows three separately focusable controls in the queued-item band"*. A reviewer refusing an owner's
stated requirement on risk grounds is arguing scope, which is the owner's axis, not a reviewer's.

Three findings decided it, and the third is the one that dissolved the case for a safe default:

- The capability line is **derived from the registry entry** — the same machine-readable source the
  sheet reads — not copy. The gap is narrower than stated: command line, args, env keys.
- The recorded doctrine against a one-press install is `InboxArrival.swift`'s, and it is about a
  **notification**: *"the least deliberate press available on a Mac … it appears over whatever the
  user was doing, unrequested."* A popover the user opened, prompted by a dot that appears only
  when a decision is pending, is the opposite case. The argument does not transfer.
- **Defaulting the preference OFF buys nothing it appears to buy.** Accepting is irreversible on
  both paths; an extra click does not make it reversible, it adds disclosure before the same
  irreversible press. The safety control that does work is *resolved-only enablement*, and that
  ships whatever the default is.

So: three controls; `Approve` enabled only where the item resolved; gated by the Settings toggle
the mock itself draws, defaulting **ON** as the mock draws it. The mock's switch states are
deliberate rather than uniform — measured, 17 drawn on and 2 drawn off, and one of the two off is
`Reconcile without asking`, the mock's other gate-removing switch.

**Recorded against it, and it is real:** the popover satisfies `PRD.md` §9.7's gate
(*"the Mac shows tools and capability summary and asks"*) but not `spec-M18.md` §1's quotation of
it (*"the Mac shows **the tools** and asks"*). Two owner documents, two wordings. This build takes
the PRD's. Listing tool names in the row when the count is small would close it, and that is the
owner's call rather than this item's.

### 3.2 The fourth count — there is no honest one, so three ship

`Resident` cannot ship. The precedent is already in the tree and is quoted rather than re-derived:
`SettingsPresentation.WarmSet` carries *"**No megabyte figure, and the type has no field for one.**
`residentMb()` exists in `src/pool.ts` and has zero callers: it never reaches `describe()` and
never reaches the wire."* Measured again here — `src/pool.ts:472`, three references, all inside its
own body.

Both lanes independently rejected substituting a number to fill the grid slot. `inFlight` reads 0
almost always; `held` duplicates the attention band directly beneath it. A quantity chosen because
a layout has four cells is the fabricated metric the house rule names.

**Three counts ship — `Running now`, `Declared`, `Tools`** — in the mock's vocabulary and the
mock's label-above-value shape. `Counts` gains `declared` and keeps `idle`, because `ReadoutModel`
and the toolbar subtitle both still derive from it.

### 3.3 `Install…`, not `Install`

Both lanes agree bare `Install` must not ship; they disagree about what replaces it. Google said
`Details` / `Dismiss` only, calling an ellipsis "the exact deception M14 was raised against".

**That misreads M14**, whose defect was an item claiming to be *available* when it was not. This
design system has an explicit, tested rule — `DESIGN.md` §3.4, *"`…` means 'opens a further view';
its absence means 'commits now'"* — and the app already trains it on `Add server…`, `Pair iPhone…`
and `Settings…`. Under that grammar the label that lies is `PRD.md` §6.4's literal `[Install Now]`,
which promises commits-now and would either lie or break the no-install-from-a-notification rule.

The failure asymmetry settles the residual doubt: the worst misreading of `Install…` is *expected
an install, got a review with the evidence and an install button* — the safe direction. The
dangerous misreading is impossible, because no case in the action set installs.

`Install…` and `Details` are **not** duplicates: they land on the same board with different focus,
the way `AttentionCause.opensHeldChangeSheet` already distinguishes two band rows.

### 3.4 Title Case in the menu bar

Converted, and `DESIGN.md` §6 gains the exception explicitly. The brief, `PRD.md` §9.8, the mock
and Apple's HIG all say title-style capitalization for menu items; `DESIGN.md`'s own precedence
rule — *"where this file and Apple's macOS 27 UI kit disagree, the kit wins"* — already carries six
title-case exceptions for kit-provided strings, recorded in `spec-M1.md` with that reasoning. The
losing option buys one uniform rule in the document; it costs a menu bar in which `Hide Others`
sits directly above `Add server…`.

`SkillPresentation.marketplacesAction` is shared between the menu item and two in-board buttons.
Buttons stay sentence case (§6 governs them), so the menu item stops sharing the string and takes
its own title. `ActivityResetEntryPointTests` pins the button label and stays green.

### 3.5 `⌘R` stays bound to `Reset server`

The mock binds `⌘R` to `Re-index Manifest`. `DESIGN.md` §8 binds it to *"Reset the selected
server"*, and §8 was re-authored **from** the mock under M21 on 2026-08-22 — so it is the later
reading of the same source, and it is the document `MenuCommandTests.designSectionEightParses`
holds the model against. `DESIGN.md` wins where it and the mock disagree.

### 3.6 A command that can never fire carries no accelerator

The repo already decided this, at length, on `⌘E`: *"the app was claiming a system combination for
a command that can never fire, since `exportLibrary` is `.featureUnbuilt` in every context … The
day export ships, §8 is the place that grants it a key, not this switch."*

Applied here it settles **seven** of the mock's ten new chords without a judgment call: **a command
that is `.featureUnbuilt` in every context gets no shortcut.** It is granted in `DESIGN.md` §8 rather
than in a `switch`.

**Corrected in gap-fix 1, and the original wording was wrong twice.** It said *nine of ten* and
*"Only `Wake Selected Server` can fire"*. Neither holds. `Reveal Router Log in Finder` is `.enabled`
outright and `Review Held Changes…` answers `.needsServerSelection`, so **three** of the twelve
commands these menus declare can fire, not one. Against the ten chords the mock draws: seven sit on
commands that can never fire and this rule refuses them; `⌃W` is granted; `⌘1` is View's `Discover`
re-drawn and is settled by §3.7; and `⌥⌘Q` on `Review Held Changes…` was refused by **no stated
rule at all** — the command fires, so this rule never reached it.

§8 now carries a second limb for it, measured rather than argued: `⌥⌘Q` is AppKit's own
`Quit and Keep Windows` (`NSAlternateQuitMenuItem`) in this app's own menu bar, so the chord could
never reach a review sheet. The nine that *is* right is the number of the twelve declared commands
that are `.featureUnbuilt` — an availability count, which settles nothing about a key.

### 3.7 No command is declared twice

The mock's Library menu re-draws `Browse the store… ⌘1` (View's `Discover`) and `Add Marketplace…`
(File's). Neither is re-declared. `MCPRouterApp.swift` records the measured cost of doing it:
declaring `Settings…` beside the one macOS contributes put **two items with one spelling and one
chord** in the app menu, measured over the accessibility plane on 2026-08-22.

### 3.8 The View menu keeps the mock's absolute digits

Per `spec-M20.md` §2 assumptions 1 and 2: the mock's order wins, and the two boards that do not
exist take no digit. `⌘5` and `⌘9` are unbound until M22 ships Harnesses and Insights, so nothing
a user has learned moves when it does. The **View menu is ordered by digit**; the **sidebar keeps
its groups and its order**, because restructuring those is M22's — `Destination.swift` says so in
`group`'s own comment. The divergence between the two orders is declared, and it closes when M22
lands rather than being carried indefinitely.

---

## 4 · The command inventory this item adds

Availability is the answer in `CommandContext.none`, which is the column `spec-M1.md`'s table
records.

| Menu | Command | Shortcut | Availability | Why |
|---|---|---|---|---|
| Router | Re-index Manifest | — | featureUnbuilt | `/servers/:name/reindex` is per-server; there is no manifest-wide route |
| Router | Restart Router | — | featureUnbuilt | no control-API route |
| Router | Wake Selected Server | ⌃W | needsServerSelection | `patch(warm: true)` — the one Router verb that can fire |
| Router | Trip Selected Breaker | — | featureUnbuilt | no route, and M16 retires the breaker |
| Router | Reap Idle Children | — | featureUnbuilt | no control-API route |
| Router | Review Held Changes… | — | needsServerSelection | selects the server and opens the held-change sheet |
| Router | Reveal Router Log in Finder | — | enabled | `SettingsPresentation.Files.logPath` + `NSWorkspace.selectFile` |
| Router | Stop Router | — | featureUnbuilt | no route. No accelerator regardless — `PRD.md` §9.7 |
| Library | Update All Skills | — | featureUnbuilt | no route |
| Library | Run Doctor | — | featureUnbuilt | no route |
| Library | Run All Checks | — | featureUnbuilt | the Checks board runs one subject at a time |
| Library | Export Library… | — | featureUnbuilt | unchanged; moves from File to Library per the mock |

Twelve rather than the mock's fourteen: §3.7 drops the two duplicates. `Export Library…` moves
menus and keeps its ellipsis — `D-m14-c` calls that ellipsis a promise of a view that does not
exist, and assigns the call to M1 rather than here; the mock now agrees with keeping it, which is
recorded and leaves the deferred item open.

`Stop Router` having no accelerator is the brief's own instruction and `PRD.md` §9.7's gate row,
not a consequence of §3.6.

---

## 5 · Steps

### Slice A — the menu bar

1. `CommandAvailability` gains a per-command reason. The tie-break its own comment states is taken:
   **reason resolution moves onto `MenuCommand`**, not an associated value, because an associated
   value changes every `==` against the case at six sites. `CommandAvailability.reason` stays as
   the generic fallback so nothing that reads it today changes meaning; `MenuCommand.reason(in:)`
   is what the menu reads. Closes `D-m14-a`.
2. `CommandAvailability` gains `badge` — the short form for the shortcut column. `NSMenuItemBadge`
   (macOS 14+, deployment target is 15.0) is the native API for right-aligned trailing text in a
   menu item, which is where the brief and `PRD.md` §9.8 put the reason.
3. `MenuBarMenu` gains `.router` and `.library`, in bar order between View and Window.
4. `MenuCommand` gains the twelve cases of §4, their titles, menus, availability and the one chord.
5. Title Case over the thirteen app-declared titles (§3.4).
6. `Destination.selectionDigit` takes the mock's map; `MenuCommand.allCases` and the View group
   order by digit (§3.8).
7. `ShellCommands` gains two `CommandMenu` builders. `ShellCommandRouter` gains the three routes
   that do something and no-ops the rest, exactly as it does today.
8. `ShellMenuReasons` writes `item.badge` beside the tool tip and the accessibility help, and
   clears it where there is none — the same write-only-when-different discipline, for the same
   measured reason (-1728 under concurrent AX reads).
9. Documents, in the same change: `DESIGN.md` §6 (the menu-bar case exception), `DESIGN.md` §8
   (`⌃W`, and the board digits §8 has never stated), `spec-M1.md`'s inventory table.
10. `scripts/acceptance/mac-shell.sh`: six app menus becomes eight, and the two new names join the
    expected list.

### Slice B — the popover

11. `MenuBarPresentation.Counts` gains `declared`; the header renders three label-above-value cells
    in the mock's vocabulary (§3.2).
12. `InboxBand.Row` gains `isApprovable` — resolved **and** the preference on. Distinct from
    `isReviewable`, because the two answer different questions and collapsing them is how the
    Approve button would appear on a row whose entry could not be read.

    **Built with a third condition: nothing the entry asks for is still blank.** The band has no
    requirement fields, and `RegistryCapability.declaration(for:values:)` does not refuse an entry
    with unmet requirements — it drops the empty values and sends the rest. So without this, pressing
    Approve on an entry wanting an API key would send a credential-less declaration to the router,
    which is the failure `RegistryCapability.action`'s own comment records having already found once
    as dead code: *"reveal the fields, press Add with every box empty, and a credential-less
    declaration reached the router."* Such a row keeps `Review…`, which is where the fields are.
    It bites on a **recorded** fixture entry rather than only in a constructed test:
    `smithery:deepwiki` asks for an `Authorization` header, and the rendered dump shows its row
    carrying `Review…` and `Not now` while the row beside it carries all three.
13. `MenuBarInboxBand` draws three controls: `Approve` (prominent), `Review…`, `Not now`. `Not now`
    is `InboxCopy.declineAction`'s new spelling — one wording per state, §6 — or a second string if
    the board's own button must keep `Decline`; the board is checked before choosing.

    **The board was checked and the second string is what shipped.** `InboxBoardRow.swift:121`,
    `InboxReviewSheet.swift:198` and `InboxConformanceTests.swift:243` all read the shared constant,
    and the mock spells this state three ways across three surfaces — `Not now` in the popover
    (`:1488`), `Not for me` on the board's own row (`:3274`), `Not now` again in the recommendation
    sheet (`:4197`). Re-spelling the shared constant would have made the board and the sheet say
    `Not now`, which is neither what they say nor what the mock draws for them. So
    `InboxCopy.Band.declineAction` is a second string and the divergence is the design of record's.

    **`(prominent)` was NOT taken, and this is the one place in the item where the mock loses.**
    `ProminentButtonStyle` would put two to four accent-filled controls in the smallest surface in
    the app — the band caps at three rows and the footer's `Open MCP Router` already holds this
    view's prominent slot. `DESIGN.md:212` binds that budget to a live accessibility deviation
    rather than to taste: `--on-accent` on `--accent` is a recorded contrast shortfall that
    `LightAppearanceTests.darkOnAccentDeviationIsPinned` measures every run, and *"exposure is
    bounded by §3 rule 4 — one prominent accent-filled action per view."* The same passage names
    the substitute — *"distinguished by shape and position too, never by colour alone"* — so
    `Approve` takes the mock's leading position with the standard fill. Declared as `D2` in
    `planning/fidelity/popover.pairing.tsv`, where the conversion gate reads it.
14. `ShellModel` gains `approveFromOutside(itemID:)`, which resolves the item and calls the board's
    existing `accept(_:)`. No second install path.
15. `SettingsPresentation` gains the preference — label, help, key, default `true` — and
    `ShellRestoration` its accessor, both following `menuBarVisible` exactly. The Menu bar pane
    gains the row.
16. `InboxBoardModel.review(itemID:)`'s comment and
    `InboxBoundaryTests.nothingOutsideTheWindowInstalls` are **amended in the open** (§3, item 3):
    the notification half stays absolutely closed and gains the finding actions; the popover's
    `Approve` is named as the one outside-the-window install, with its two conditions.

### Slice C — the notification

17. `AnalystFinding` — the value a finding is, with its evidence count. No analyst; this is the
    shape the analyst fills.
18. `FindingNotificationAction { install, details, dismiss }` — a **second** closed set beside
    `InboxNotificationAction`, which is left byte-identical so its own enforcement keeps meaning
    exactly what it meant.
19. `FindingNotificationCategory` + `FindingAnnouncement` + `FindingNotificationRoute`, following
    `InboxNotificationCategory`'s shape: the category's buttons are stated once and the notifier
    builds `UNNotificationCategory` from that list rather than restating it.
20. `UserNotificationArrivalNotifier.categories()` registers both families.
21. `InboxNotificationDelegate` resolves a response against both action sets and routes.
22. Copy in the Kit, from the mock's own sentence and `PRD.md` §6.4, minus the `[Install Now]`
    literal (§3.3).

### Slice D — conversion artifacts

23. `MeasureDump.Surface` gains `popover`; `planning/fidelity/popover.layers.json` and
    `popover.pairing.tsv` are authored, with every divergence of §3 declared and numbered.
24. `planning/evidence/M20-acceptance.md` — the ledger `UI_VERIFICATION.md` §2 requires.

---

## 6 · Test strategy

Every clause below is a unit test in the Kit unless it names another lane. The Kit is where the
decisions are, which is what makes them testable without a UI stack.

| # | Clause | Lane |
|---|---|---|
| A1 | Eight menus, in bar order, and every one has commands | `MenuCommandTests` |
| A2 | The inventory and `MenuCommand.allCases` match in both directions | `MenuCommandTests`, against `spec-M1.md` |
| A3 | Every `.featureUnbuilt` command names **what** is unbuilt, and no two share a sentence by accident | `MenuCommandTests` |
| A4 | No command that is `.featureUnbuilt` in every context carries a shortcut (§3.6) | `MenuCommandTests` |
| A5 | Every ⌘-chord in `DESIGN.md` §8 is bound; no chord is bound twice | `MenuCommandTests` |
| A6 | App-declared titles are Title Case; the six kit strings are unchanged | `MenuCommandTests` |
| A7 | The View menu is in digit order and `⌘5`/`⌘9` are unbound | `MenuCommandTests` |
| A8 | The badge is present exactly where a command is unavailable | `MenuCommandTests` |
| B1 | `Counts.declared` equals the server count; no memory field exists on the type | `MenuBarPresentationTests` |
| B2 | `isApprovable` is false for an unresolved row and false with the preference off | `InboxBandTests` |
| B3 | The band exposes three controls, each separately focusable | `MeasureDump` structure layer |
| B4 | The preference round-trips through a scratch defaults domain and defaults `true` | `SettingsAndMenuBarTests` |
| C1 | No case of either action set installs; the exhaustive switch proves it | `InboxAnnouncementTests` |
| C2 | The buttons macOS is handed equal the buttons the value promises, for every category in both families | `InboxAnnouncementTests` |
| C3 | `Install…` carries the ellipsis and `Details`/`Dismiss` do not | `InboxAnnouncementTests` |
| C4 | A finding response routes to the finding's route and never to the arrival's | `InboxArrivalTests` |
| D1 | No path outside the window installs anything **except** popover `Approve` on a resolved item with the preference on — and no notification path ever does | `InboxArrivalTests`, amended |

Each of A3, A4, B2, C1 and D1 is a drift guard, so each is broken deliberately and seen red before
it is trusted (`SWIFT_PRACTICES.md` §7), and that is recorded in the evidence ledger.

**That sentence was false when the first pass wrote it, and it is true now.** The verification pass
found no evidence ledger, and `scripts/red-green.py` had 53 mutation sites of which not one named a
menu command, a band control or a notification family — so nothing had been broken and nothing had
been seen red. The trap that made it look otherwise is worth naming: that file's own `"M20"` is the
**twentieth mutation id** in its `M01…M59` namespace, on `ServerStateTracker.swift`, present unchanged
at this item's branch point. A grep for the item id reports these guards armed when they are not.

Gap-fix 1 closed it durably rather than by running a probe: `scripts/red-green.py` gained
`M20-A3`, `M20-A4`, `M20-B2`, `M20-C1` and `M20-D1` — ids outside that namespace so the collision
cannot recur — and each was run. All five report **KILLED**, each naming the clause it killed.
`planning/evidence/M20-acceptance.md` §7 carries the five runs verbatim with their durations.

---

## 7 · Acceptance criteria

1. The menu bar carries eight app menus; every command in the inventory is in it and nothing else
   the app declares is.
2. Every disabled item is dimmed in place, carries its reason in the accessibility tree, and shows
   the short form in the shortcut column.
3. `⌘R` still resets the selected server.
4. The popover's queued-item band shows three separately focusable controls in a structure dump.
5. No number the popover renders is absent from the wire.
6. Both notification families register the buttons their values name, and no action installs.
7. `make lint` exit 0, swiftlint 0 violations; the Swift suite green with no drop in test count.

## 8 · Out of scope

- The session analyst (`PRD.md` §6.2–§6.3). This item builds delivery only.
- Harnesses and Insights, and the sidebar's regrouping — M22.
- Exposing `residentMb()` on the control API — router work.
- Retiring the breaker — M16 owns `Trip Selected Breaker`'s fate.
- `Export Library…`'s ellipsis — `D-m14-c` assigns it to M1.
- A URL parser for `?popover=1` / `?notification=1` — `spec-M20.md` §2 assumption 7.

## 9 · Gate record

- Codebase grounding: `app/MCPRouter`, `app/Sources/MCPRouterKit/Shell`,
  `app/Sources/MCPRouterKit/Inbox`, `app/Sources/MCPRouterUI/Shell`,
  `app/Sources/MCPRouterUI/Boards/InboxBoardModel.swift`, `app/Sources/MeasureDump`,
  `app/Tests`, `src/pool.ts`, `src/control.ts`, `design/mcp-router-console.html`, `DESIGN.md`,
  `PRD.md` §6.4 / §9.4 / §9.7 / §9.8, `scripts/acceptance/`, `planning/fidelity/`.
- Out-of-family review: `agy` / `gemini-3.7-flash-high` — answered, and is the gate.
  `codex` / `gpt-5.6-sol` — usage-limited until 2026-08-27, zero-byte report.
  `grok-4.6` — `402 Payment Required`, zero-byte report. Second reading: `claude-fable-5` at high
  effort, recorded as in-family and not as the gate.
- Four forks referred, four dispositioned in §3. Two of the Google lane's verdicts were **not
  taken**, both because they deleted a requirement stated in three owner documents; the reasoning
  is in §3.1 and §3.3 rather than in a note that says a lane was consulted.
- One decision is left for the owner and is not blocking: the `Approve from the popover` default.
  This build ships it ON as the design of record draws it; flipping it is one constant.
