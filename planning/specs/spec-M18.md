# spec-M18 — twelve sheets, and the gate each decision gets

| | |
|---|---|
| ID | M18 |
| Status | Ready for AI |
| Category | mac · mock conversion |
| Depends on | M1 ✓ · M8 ✓ · M23 ✓ · M15 · M19 · M22 — five of the thirteen panels have no host surface until those three land |
| Related | M15 (a sheet opened from a Settings pane attaches to that window) · M19 (owns the readme sheet's contents) · M22 (owns the reconcile sheet's board) · DEF-001 (the pairing transport the pair sheet needs) |
| Brief | `planning/features-to-triage/M18-sheets-and-gates.md` |
| Source mock | `design/mcp-router-console.html` — the design-authority question is M21's, recorded in §3.1 |
| Triage | 2026-08-22 · §2 is owner-facing · §3 is the pipeline record |
| Plan | `planning/plans/plan-M18.md` (committed: `706cefb`, tier: Large) |

---

## 1 · Feature description (the brief, verbatim)

> # M18 — twelve sheets, and the gate each decision gets
>
> **Depends on:** M1. **Related:** M8 (quarantine is one of the twelve).
> **Source:** `design/mcp-router-console.html`, PRD §9.7.
>
> A sheet carries one decision together with the evidence for it. Twelve are drawn.
>
> | Sheet | The decision | The evidence it shows |
> |---|---|---|
> | pair | trust a phone | QR, typed fallback, expiry, and what pairing grants and does not grant |
> | reconcile | remove duplicate entries from a harness config | full unified diff of the real file, before/after counts |
> | quarantine | let a changed tool be callable again | schema diff *and* description diff, with why it was held |
> | readme | install or update a capability | rendered README, changelog, capability list (M19) |
> | capability-delta | accept a version that asks for more | what the new version added, against what was approved |
> | add-server | add an upstream by hand | the command as typed, resolved against the child PATH |
> | add-marketplace | trust a source of skills | origin, owner, what it will be allowed to write |
> | recommendation | act on an analyst finding | the grep hits with file and line, and the four-step judgement chain |
> | queued-detail | approve what the phone queued | tool list, capability summary, who queued it and when |
> | analyzer | choose which model reads your sessions | the five CLIs, their sign-in state, per-store consent |
> | path | understand where children look for binaries | the resolved login-shell PATH, directory by directory (R6) |
> | confirm-remove | remove an installed capability | what is being removed and the undo window |
>
> ## Friction scales with blast radius
>
> The recurring failure is one feedback mechanism serving every action: a three-second toast
> behind a command that stops every job on the host. **A row whose gate is a toast is a defect,
> and so is a gate that exceeds the blast radius.**
>
> | Action | Blast radius | Gate |
> |---|---|---|
> | Remove duplicates from a harness config | someone else's file | diff, counts, "Open the file instead", named-consequence button |
> | Remove selected capabilities | installed capability | multi-select, named count, 30-day undo stated on the surface |
> | Accept held schema changes | a tool regains callability | both diffs, and the reason it was held |
> | Disable a server | one server stops answering | quiet destructive-red text button, never the primary |
> | Trip breaker / wake now | one child process | none — reversible in one press, and the state is visible |
> | Approve a phone-queued install | executable code on this Mac | the phone queues; the Mac shows the tools and asks |
> | Stop Router | every session loses its tools | menu item, no accelerator |
>
> Reversible actions are not confirmed. Undo beats "are you sure", and the 30-day window on
> Cleanup is stated on the surface rather than in a preference nobody reads.
>
> ## Sheet mechanics
>
> A sheet drops from its window's titlebar and is modal to that window only. It has at most one
> filled primary; a destructive alternative is a quiet red text button, never a second filled
> one. Return activates the default; Escape cancels. A sheet opened from the Settings window
> attaches to the Settings window.
>
> ## Converting this to SwiftUI
>
> Attach each sheet with `.sheet(item:)` on the view that owns the decision, so the sheet belongs
> to its window. A sheet presented from a Settings pane attaches to the Settings window; the mock
> draws both windows in one page and cannot demonstrate that, so it is a requirement the
> implementation has to meet without a reference.
>
> - `item:` rather than `isPresented:` — the sheet's content comes from the value that opened it,
>   which removes the class of bug where a sheet opens showing the previously selected row.
> - The twelve sheets are one enum, so the inventory is a compile-time fact.
> - `confirmationDialog` is not a substitute for the gated sheets in the table above. A dialog
>   cannot show a diff, and the diff *is* the gate for reconcile, quarantine and capability-delta.
> - Return activates the default button via `.keyboardShortcut(.defaultAction)`; Escape cancels
>   via `.cancelAction`. Both are free from the button roles, and a destructive alternative takes
>   `.destructive` rather than a red foreground colour, so the platform styles it.
>
> Acceptance: every row of the gate table has a test naming the sheet it presents, and no
> destructive action's gate resolves to a transient message (M23).

---

## 2 · Triage — 2026-08-22

**Ready for Implementation Plan**

**Sentinel review:** S2 — Approve with assumptions. Governance-adjacent: three of these panels are the
only thing standing between an automatic action and someone else's configuration file, and one of
them puts executable code on this Mac.

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*

- **Where it shows up:** Servers, Skills, Discover, Inbox, Cleanup, Harnesses, Insights and the Settings window *(customer-facing — existing and newly-added surfaces that gain panels)*; the Router menu *(customer-facing — one item keeps its lack of a shortcut on purpose)*. Nothing internal changes.
- **What users will see — per surface:**
  - Servers: panels for adding a server by hand with the command shown as it will actually run, for letting a changed tool be callable again with both what changed in it shown side by side, and for removing a server with what is being removed named.
  - Skills: panels for trusting a new source of capabilities, for reading a capability's documentation before installing it, and for accepting a version that asks for more than the one you approved.
  - Discover: a panel explaining what the official mark does and does not claim.
  - Inbox: panels for trusting a phone, and for approving what the phone has queued with its tool list and who queued it.
  - Cleanup: a panel for removing installed capabilities with the number named and the thirty-day undo window written on the panel itself.
  - Harnesses: a panel showing the whole difference this app proposes to write into another tool's configuration file, with counts before and after and a way to open the file instead.
  - Insights: panels for choosing which model reads your sessions, and for acting on something it noticed with the evidence and the reasoning shown.
  - Settings: a panel showing where the app looks for the programs it runs, directory by directory. It belongs to the Settings window, not the main one.
- **Behaviour changes:**
  - How much a panel asks of you scales with what the action touches. Nothing that can be undone in one press asks for confirmation, and nothing that stops every session on the machine is confirmed by a message that disappears.
  - A panel has one filled main action. A destructive alternative is quiet red text, never a second filled button.
  - Return does the default thing, Escape cancels.
- **Design reference:** the console mock draws every panel; it is the visual and copy reference, subject to the design-authority question under M21.

**Assumptions**

- `[Layout]` **Thirteen panels, not twelve.** The mock draws one the brief does not list — the explanation of what the official mark asserts — and the mock is the inventory. *(the drawn artifact beats the prose describing it; it was added on 2026-08-20, after the brief was written that morning)*
- `[Experience]` Two links in the mock lead nowhere — the changelog link and the install link inside another panel open no panel at all. They are reported as faults in the mock rather than built as two more panels; the changelog is a tab of the documentation panel. *(building a panel for a broken link would invent a surface nobody designed)*
- `[Experience]` The panels the app already has — add a server, remove a server, accept held changes, sources of capabilities, review what the phone queued, a capability's origin, reset history, pairing — are re-housed into the single inventory rather than left beside it. *(one inventory, so a panel cannot be added without the count moving)*
- `[Experience]` Every panel is opened by the thing that was chosen, so it cannot open showing the previously selected row. *(the app already does this on four of its seven panels and does not on three)*
- `[Operations]` The panel for trusting a phone cannot be finished by this item: the pairing exchange it needs does not exist yet and is recorded as an open fault of its own. This item builds the panel and its wording; the exchange behind it stays that fault's. *(a panel over a mechanism that is not there is the honest refusal the build already shows)*
- `[Operations]` The panel that writes into another tool's configuration shows the real file's differences, never a summary. *(the difference is the gate; a summary is not one)*
- `[Compliance]` Removing a server by keyboard stays unconfirmed and undoable, as the design document requires. The panel that names a count and states the undo window before removing installed capabilities is informing rather than asking, which is that same rule applied. Where the build already confirms a server removal it stays, because that was a deliberate fix with its reason recorded. *(the design document and the build disagree on this one action, and the disagreement was chosen rather than drifted into)*
- `[Compliance]` Nothing here is confirmed by a message that disappears, and nothing reversible is confirmed at all. *(the brief's own rule, and the app's undo-over-confirm contract)*
- `[Compliance]` Approving what a phone queued stays a decision taken on this Mac. The phone queues and never installs. *(a written design principle, and an item that would have contradicted it was retired rather than routed around)*
- `[Data & scope]` No panel changes who can see or share anything; every one of them acts on this Mac for the person using it. *(no sharing surface exists in this product)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage M18` before the planner picks this up.*

---

## 3 · Grounding record — pipeline note, not owner-facing

Measured on the main checkout at `7b730ee`, 2026-08-22.

### 3.1 Design authority

Recorded in full at `planning/specs/spec-M15.md` §3.1, asked as a question at `planning/specs/spec-M21.md` §2.
Not re-asked here: a sheet's gate, its inventory and its blast-radius table are product decisions that
survive either visual direction. Only the drawing changes.

### 3.2 The mock draws thirteen sheets, and two of its own links are dead

Counted by `id="sh-*"` in `design/mcp-router-console.html`: `add-marketplace`, `add-server`,
`analyzer`, `capability-delta`, `confirm-remove`, **`official`**, `pair`, `path`, `quarantine`,
`queued-detail`, `readme`, `recommendation`, `reconcile` — thirteen. The brief names twelve;
`design/mcp-router-console-spec.md` (written 2026-08-20 21:56, after the brief at 00:28) says
thirteen and names `official`. It arrived with M24 at `6c513b0`, whose commit message describes it:
*"A `What is official?` control opens a sheet defining it as a claim about the publisher."*

Two `data-act="sheet:…"` values resolve to no sheet id at all — `sheet:changelog` and
`sheet:install-server`. The mock's own `openSheet(id)` returns early on a missing element, so both are
silent no-ops. `changelog` is already a tab of the `readme` sheet, so the correct reading is a wrong
link rather than a fourteenth sheet.

### 3.3 What the built app has

Seven `.sheet(` call sites. **Four use `item:`** — Activity, Servers, Skills, Cleanup, with
`ActivityBoard.swift:61` carrying the reason in a comment: *"`item:` rather than `isPresented:` so the
enum is the single source of truth."* **Three use `isPresented:`** — `InboxBoard.swift:26` (review),
`InboxBoard.swift:31` (pairing), `DiscoverBoard.swift:32` (detail). Those three are the class of bug
the brief names.

There is no single sheet enum. Each board model carries its own: `ServersBoardModel.Sheet`
(`addServer`, `heldChange`, `removeServer`), `SkillsBoardModel.Sheet` (`heldVersion`,
`marketplaces`), `CleanupBoardModel.Sheet` (`removeServer`, `resetHistory`, `provenance`),
`ActivityModel.Sheet` (`resetHistory`), and `EvalsBoardModel.Sheet.recheckAll` — **which is never
assigned and never presented anywhere**, so it is dead code today.

Mapping the thirteen onto what exists:

| Sheet | Built as |
|---|---|
| pair | `PairingSheet.swift`, opened from Inbox |
| add-server | `AddServerSheet` (`ServerSheets.swift:45`), `⌘N` |
| add-marketplace | `MarketplacesSheet` (`SkillSheets.swift:108`), `⇧⌘N` |
| quarantine / capability-delta | `HeldChangeSheet` (`ServerSheets.swift:134`) drawing `ToolChangeCard` over `SchemaDiff.compare(before:after:)` — one sheet where the mock has two |
| queued-detail | `InboxReviewSheet.swift:18` |
| confirm-remove | `RemoveServerDialog` (`ServerSheets.swift:220`) and `RemoveServerSheet` (`CleanupSheets.swift:33`) — two, both presented as sheets rather than dialogs |
| path | partially, as `SkillProvenanceSheet` (`CleanupSheets.swift:175`) — a capability's origin, not the resolved search path |
| readme · reconcile · recommendation · analyzer · official | absent |

`confirmationDialog` appears once in the whole tree and it is on the phone
(`Phone/PairingFlowView.swift:344`). `alert(` appears nowhere. So the brief's rule that a dialog is
not a substitute for a gated sheet is already how the Mac app is built.

### 3.4 What the campaign measured — cite, do not re-derive

Only `pair` has direct evidence, and it is the important kind:

- `DEF-001` — **open** — *"Neither the phone nor the Mac implements a pairing transport. The phone stores a paired-Mac record for a Mac it never contacted."*
- `SURF-010`'s witness verdict fails structurally and lexically: *"The design's sheet is a working pairing exchange … The build's sheet carries the same title, 'Pair iPhone', the same Done action, and nothing else from that list. Its whole body is a refusal … it is the surface where that defect is most visible to a user."*
- `CASE-0010` and `CASE-0110` fail against the pairing contract; `CASE-0142` and `CASE-0143` **pass** against the honesty requirement, because the refusal is truthfully stated. Two requirements, opposite verdicts, same sheet.

So the pair sheet's gate is buildable and its content is not, and the assumption above says which half
this item owns. `DEF-011` (fixed in part) is the only other hit — Cleanup's per-row removal *"opens
the dialog rather than removing, because the one destructive act on this board is never one click"* —
which is the confirm-remove gate already behaving as the brief requires.

**Nothing at all is recorded for the other ten sheets.** Reconcile, quarantine, readme,
capability-delta, add-server, add-marketplace, recommendation, queued-detail, analyzer and path
return no defect, case or witness row under those names. State that as an absence rather than reading
silence as agreement.

### 3.5 What this item owes M23's gate

Thirteen sheets are thirteen surfaces under M23's own definition — *"every board, every state of every
board, every sheet, the Settings window and each of its panes"*. Each needs its own
`planning/fidelity/<surface>.layers.json`, its pairing file and a `Surface` case in `MeasureDump`,
which declares `case servers` today. The brief's acceptance — *"no destructive action's gate resolves
to a transient message"* — is a `breadth` and `copy` layer assertion over the gate table, and the gate
table is the row shape M23 built.

### 3.6 Gate record

- Codebase grounding: `app/Sources`, `design/mcp-router-console.html`, `planning/test-campaign/`, `DESIGN.md` §9, `PRD.md` §9.7.
- Out-of-family spec review: see §3.7 for which lane answered.
- Nine assumptions. The two consequential ones — thirteen rather than twelve, and the pair sheet's transport staying `DEF-001`'s — each name what they beat.

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

- **Accepted — three missing dependencies, all real.** The `readme` panel's contents are M19's; the `path` panel attaches to the Settings window, which is M15's; and `reconcile`, `recommendation` and `analyzer` open from the Harnesses and Insights boards, which are M22's. Five of the thirteen panels have no host surface until those three land. The header now names all three.
- **Accepted — a live contradiction with the design document, recorded rather than resolved silently.** `DESIGN.md`:400 says `⌘⌫` removes the selected server *"(undoable, never confirmed)"* and §9 states the app's contract as *"Undo over confirm"*. The build confirms: `ServersBoardModel.Sheet.removeServer` presents `RemoveServerDialog`, and `MenuCommand.swift:265` binds `⌫` to that command. The campaign records the confirming behaviour as a deliberate fix — `DEF-011`'s note reads *"Removal opens the dialog rather than removing, because the one destructive act on this board is never one click."* So the build and the design document disagree, and the build's side was chosen on purpose. This item codifies the build. Recorded as an assumption in §2 rather than a question, because the decision was already taken and written down; it is flagged here so the planner does not read `DESIGN.md`:400 as licence to delete the dialog.
- **Reconciled, not a contradiction:** one lane read `confirm-remove` as contradicting undo-over-confirm outright. It does not — the brief's own row for it is *"what is being removed and the undo window"*, which informs rather than asks, and the Cleanup gate is *"multi-select, named count, 30-day undo stated on the surface"*. That is §9's rule applied, not broken.
- **Accepted:** the off-by-one — thirteen drawn against twelve named — and the two dangling actions were confirmed independently. Both were already §2's first two assumptions.
