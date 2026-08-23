# spec-M20 — menu bar, status item, and the notification banner

| | |
|---|---|
| ID | M20 |
| Status | **Developer Review** — gap-fix 1 ready to verify on `ai/m20`; gated at `8aecd90`, records committed after it, 2026-08-23 |
| Category | mac · mock conversion |
| Depends on | M1 ✓ · M8 ✓ · M11 ✓ · M14 ✓ · I6 ✓ · M23 ✓ · M22 (the View menu's nine boards) · M15 (Settings leaving the View menu for the app menu) |
| Related | M15 (Settings leaves the View menu for the app menu) |
| Brief | `planning/features-to-triage/M20-menubar-status-notification.md` |
| Source mock | `design/mcp-router-console.html` — the design-authority question is M21's, recorded in §3.1 |
| Triage | 2026-08-22 · §2 is owner-facing · §3 is the pipeline record |

---

## 1 · Feature description (the brief, verbatim)

> # M20 — menu bar, status item, and the notification banner
>
> **Depends on:** M1. **Related:** M8 (popover), M14 (menu items that lie), I6 (arrival
> notifications).
> **Source:** `design/mcp-router-console.html`, PRD §9.8.
>
> Three pieces of system chrome, drawn in full in the mock.
>
> ## The menu bar
>
> Nine menus: Apple, MCP Router, File, Edit, View, Router, Library, Window, Help. Every item is
> Title Case with its real accelerator right-aligned, and the ones this build cannot do are
> **dimmed in place with the reason in the shortcut column** rather than hidden — `Install
> Command-Line Tool · Installed` is the pattern. M14 is the failure this prevents: a shipped menu
> item that tells the user the app is not built.
>
> The Router menu is where the daemon's own verbs live — re-index, restart, wake, trip, reap,
> review held changes, reveal the log, stop. Stop Router has no accelerator, because its blast
> radius is every session on the machine.
>
> The View menu carries the nine boards with a tick on the current one; Settings is not in it,
> because Settings is a window and lives in the app menu (M15).
>
> ## The status item
>
> A template symbol that takes an **amber dot only while something wants a decision**. An icon
> that changes constantly is one the eye filters, and then it filters the one change that
> mattered.
>
> Its popover answers one question and closes: what is running now (four counts), what the phone
> queued, and the last six calls with their outcomes and durations. The queued item carries
> Approve, Review… and Not now inline. That inline band is the point of the popover — a decision
> that would otherwise need the main window takes one press.
>
> ## The notification banner
>
> The delivery mechanism for an analyst finding (PRD §6.4). One sentence carrying the finding and
> its evidence count, and three actions: Install, Details, Dismiss.
>
> **The accessibility constraint is load-bearing and easy to get wrong.** Buttons inside an
> `aria-live` region are flattened to plain text by assistive technology: the visual banner works
> perfectly, and the actions become unreachable for anyone not using a mouse. The announcement is
> a permanent, visually-hidden live region written into when the banner fires; the banner itself
> is a group whose buttons sit outside it. A time-limited action only mouse users can reach is a
> countdown, not an action.
>
> Deep links: `?popover=1`, `?notification=1`.
>
> ## Converting this to SwiftUI
>
> Three system APIs, one per piece.
>
> - **The menu bar** is `CommandGroup` and `CommandMenu` in the app's `commands` block. Items that
>   this build cannot perform use `.disabled(true)` and keep their shortcut label, which is how
>   they stay dimmed in place with the reason visible. M14 exists because an item that lies about
>   being available is worse than one that is dimmed.
> - **The status item** is `MenuBarExtra` with `.menuBarExtraStyle(.window)`, since the popover
>   holds a layout rather than a menu. The icon is a template symbol; the badge is a separate
>   overlay applied only when something wants a decision.
> - **The banner** is `UNUserNotificationCenter` with a category carrying three actions. The
>   actions are real notification actions, not buttons drawn inside the app — which also removes
>   the accessibility problem the mock had to solve in HTML, where buttons inside a live region
>   are flattened to plain text and become unreachable.
>
> The Approve / Review… / Not now band inside the popover is in-app UI and does need the
> accessibility work: announce the arrival through an accessibility notification, and keep the
> controls as real focusable buttons outside whatever announces.
>
> Acceptance: a structure dump of the popover shows three separately focusable controls in the
> queued-item band, and the disabled menu items appear in the tree with their reason (M23).

---

## 2 · Triage — 2026-08-22

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*

- **Where it shows up:** the menu bar *(customer-facing — existing surface, gains two menus and loses none)*; the small icon in the system menu bar and the panel it drops *(customer-facing — existing surface, its panel gains an inline decision band)*; the system notification a finding arrives in *(customer-facing — new)*. Nothing internal changes.
- **What users will see — per surface:**
  - The menu bar: nine menus rather than the six the app declares today, adding a Router menu holding the daemon's own verbs — re-index, restart, wake, trip, reap, review held changes, reveal the log, stop — and a Library menu. Every item is Title Case with its real shortcut on the right, and anything this build cannot do is dimmed where it stands with the reason in the shortcut column rather than removed. Stop Router has no shortcut, on purpose.
  - The View menu: the nine boards with a tick on the current one. Settings is not among them, because it becomes a window and lives in the app menu.
  - The menu-bar icon: it takes an amber dot only while something is waiting on a decision, and no other time.
  - Its panel: what is running now as four counts, what the phone has queued, and the last six calls with their outcomes and how long they took. The queued item carries Approve, Review… and Not now as three separate controls in a row, so a decision that would otherwise need the main window takes one press.
  - The notification: one sentence carrying what was noticed and how many pieces of evidence there are, with three actions — Install, Details, Dismiss.
- **Behaviour changes:**
  - The icon stops changing for things that do not need you. An icon that changes constantly is one the eye learns to ignore, and then it ignores the one change that mattered.
  - The three controls in the panel's decision band are each reachable by keyboard and are announced separately, rather than being read out as one run of text.
- **Design reference:** the console mock draws all nine menus, the panel and the notification; it is the visual reference, subject to the design-authority question under M21.

**Assumptions**

- `[Layout]` The board shortcuts follow the mock's current order — Discover first through Insights ninth — not the older order written in the product requirements. *(the mock was re-ordered on 2026-08-20 when the store moved to the top of the list, and the requirements were not updated with it)*
- `[Layout]` The nine-board View menu lands with the two new boards. Until they exist the menu carries seven, which is what it carries today. *(a menu item for a board that does not exist is exactly the failure a previous item was raised to fix)*
- `[Experience]` A menu item this build cannot perform stays visible, dimmed, with its reason readable. *(already how this app works, after an item found three menu items shipping dimmed and silent with no explanation at all)*
- `[Experience]` The notification's three actions are real system notification actions rather than controls drawn inside the app. *(the accessibility problem the brief describes is a web problem; on this platform it does not arise, and the actions stay reachable without a mouse)*
- `[Operations]` The finding a notification delivers is produced by the session analyst, which does not exist yet. This item builds the delivery — the category, its three actions and the wording — against a finding fired for a test, and the analyst supplies real ones when it ships. *(rather than deferring the whole banner until the analyst exists, which would leave the mock's own surface unbuilt indefinitely)*
- `[Operations]` The existing arrival notification, which carries Review and Decline, keeps its own category. The finding notification is a second one beside it, not a widening of the first. *(two different things arriving, two different sets of actions)*
- `[Experience]` The two addresses quoted at the end of the brief locate frames inside the mock; the app gains no way of being opened by one. *(nothing in the app reads an address today, and the same three words appear in three briefs with no item owning them)*
- `[Data & scope]` Nothing here changes who can see or do anything; every action is the same one already available in the main window. *(a shortcut to a decision, not a new permission)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage M20` before the planner picks this up.*

---

## 3 · Grounding record — pipeline note, not owner-facing

Measured on the main checkout at `7b730ee`, 2026-08-22.

### 3.1 Design authority

Recorded in full at `planning/specs/spec-M15.md` §3.1, asked at `planning/specs/spec-M21.md` §2. Not
re-asked here: menu inventory, disabled-with-reason, the status item's badge rule and the notification
actions are all platform and product decisions independent of the visual direction.

### 3.2 What the built app declares

`app/MCPRouter/MCPRouterApp.swift:86-137`, `struct ShellCommands: Commands`, declares **six**
`CommandGroup`s: `.appInfo` (About), `.appSettings` (Settings, `⌘,`), `.newItem` (Add server… `⌘N`,
Add marketplace… `⇧⌘N`, Pair iPhone…, Export library…), `after: .pasteboard` (Find `⌘F`, Reset server
`⌘R`, Remove server `⌘⌫`), `.sidebar` (a `ForEach` over seven destinations at `⌘1`–`⌘7`, then Show
sidebar `⌘⌃S`), and `.help` (three items).

There is **no Router menu and no Library menu**. `MenuCommand.swift` carries 26 fixed cases plus seven
generated destination cases, and `availability(in:)` returns `.enabled`, `.surfaceAbsent`,
`.featureUnbuilt` or `.needsServerSelection`. `exportLibrary` is hard-wired `.featureUnbuilt` at
`:366` — a genuinely unbuilt feature, dimmed everywhere, which is exactly the pattern the brief wants
generalised.

`MenuBarExtra` exists at `MCPRouterApp.swift:47-52` with `.menuBarExtraStyle(.window)`. Its label is
`MenuBarStatusItem.swift` — a fixed `square.stack.3d.up` template glyph plus a single attention dot,
never a count. Its content is `MenuBarPopover.swift`, drawing recent calls, attention rows and an
inbox band. So the icon's badge rule already matches the brief; what the panel is missing is the
four-count summary and the three-control decision band.

`UNUserNotificationCenter` is wired: `ArrivalNotifierFactory.swift` and
`InboxNotificationDelegate.swift`, installed at `applicationDidFinishLaunching`
(`MCPRouterApp.swift:171`). `InboxArrival.swift` declares `InboxNotificationAction` (`.review`,
`.decline`) and two categories — `inbox.arrival` with both actions and `inbox.arrival.many` with
`.review` only. That is I6's arrival path. **The analyst-finding notification with Install, Details and
Dismiss does not exist**, and neither does the analyst.

### 3.3 The briefs are stale against their own mock, and the requirements are staler

The mock's View menu reads `Discover ⌘1`, `Skills ⌘2`, `Servers ⌘3`, `Activity ⌘4`, `Harnesses ⌘5`,
`Checks ⌘6`, `Cleanup ⌘7`, `Inbox ⌘8`, `Insights ⌘9`, then Hide Inspector `⌥⌘I`, Hide Sidebar `⌃⌘S`,
Switch Appearance `⌃⌥A`. `PRD.md` §9.4 still lists `Servers ⌘1` through `Cleanup ⌘9`. The mock changed
at `6c513b0` (M24, 2026-08-20 08:52) — *"⌘1–⌘9 follow that order"* — after these briefs were written
at 00:28.

The mock's Router menu also keeps `Trip Selected Breaker ⌃T`, so the breaker survives as a verb in the
mock that replaces it as a drawing. Noted under M16 §3.2.

### 3.4 Prior measured findings this item stands on — cite, do not re-derive

- **M11** (merged `2a434b9`) measured the built app rather than reading it: `Add server…`, `Add marketplace…` and `Find` rendered *"`enabled=0` with an EMPTY `AXHelp` — dimmed and silent, permanently unusable with no explanation, since M3."* The fix wired the disabled state to the live help tag. This item must not regress it.
- **M14** (merged `7e7ed70`) separated a missing destination from an unbuilt feature with `.featureUnbuilt`, after the diagnosis inverted on measurement: on a clean Release build the scaffold symbols were zero and *"the single hit is `surfaceAbsent`'s live help tag"*. `mac-shell.sh` measured exit 0 over 39 assertions.
- Three of M14's deferred children are still open and land squarely on this item: `D-m14-a` (per-command unbuilt copy needs an associated value, which breaks equality at six sites), `D-m14-b` (`⌘E` is still bound to a permanently dimmed command), `D-m14-c` (`Export library…` keeps an ellipsis promising a view that does not exist — M1's call to change).
- `DEF-004` (fixed in test) — the no-install guarantee read only half of where the notification's buttons are stated. Same category machinery this item extends.

### 3.5 The status item has never been measured, and the reason is structural

`SURF-009` (*"Mac menu-bar popover and inbox band"*) carries **three `n/a` cases and no witness verdict
at all**: `CASE-0004`, `CASE-0006` and `CASE-0109`, each with the same stated reason — *"NSStatusItem
is not an AXPress target while MCPRouter is backgrounded; this campaign never activates, so the
popover cannot be opened or photographed."*

This matters for the brief's acceptance line, *"a structure dump of the popover shows three separately
focusable controls in the queued-item band"*. The accessibility lane cannot reach it. **M23's harness
can**: `MeasureDump` hosts a surface in an `NSHostingView` under a `.prohibited` activation policy and
writes a structure-and-geometry tree without the app ever coming forward. So the acceptance is
reachable through the M23 route and not through the campaign's, and the planner should route it there
rather than re-discovering the `n/a`.

### 3.6 What this item owes M23's gate

The nine open menus and the popover and the notification are eleven surfaces under M23's definition.
Each wants a `planning/fidelity/<surface>.layers.json`, a pairing file and a `Surface` case in
`MeasureDump`. The dimmed-with-reason assertion is a `structure` plus `copy` layer claim; the
three-focusable-controls assertion is `structure`.

### 3.7 Gate record

- Codebase grounding: `app/MCPRouter`, `app/Sources/MCPRouterKit/Shell`, `app/Sources/MCPRouterUI/Shell`, `design/mcp-router-console.html`, `PRD.md` §9.8, `planning/test-campaign/`, ORCHESTRATOR's deferred register.
- Out-of-family spec review: see §3.8 for which lane answered.
- Seven assumptions. The consequential one is building the notification's delivery ahead of the analyst that fills it, and it names what it beat.

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

- **Not accepted — the block on the accelerator map.** One lane argued the three-way disagreement between the brief, the product requirements and the mock leaves a runner unable to build the View menu and should be `Needs More Info`. Run the divergence test on it: the two readings differ only in which digit maps to which board, it is one table, and reversing it is a one-line edit that breaks nothing. It fails the essential bar's second limb — expensive to undo — so it is an assumption. Its rationale is strengthened rather than the verdict changed: the mock's order came from `6c513b0`, an owner-authored commit whose message states the intent (*"⌘1–⌘9 follow that order"*), and it postdates both the brief and the requirements section.
- **Accepted — M15 is a missing dependency.** Taking Settings out of the View menu and putting it in the app menu is M15's work, not this item's. Added to the header. Both lanes raised it independently.
- **Accepted:** adding two destinations before the boards behind them exist would ship menu items for boards that are not there, which is precisely the defect M14 was raised to fix and which this brief itself cites. That is why the nine-board menu waits on M22, and §2's second assumption already says so.
- **Accepted:** the query-string addresses in this brief are the mock's own state-driving parameters, not a product requirement. No parser exists in `app/Sources` and no brief owns one. Recorded here as it is under M15.
