# spec-M17 — four states on every surface, and chrome that follows them

| | |
|---|---|
| ID | M17 |
| Status | To Do |
| Category | mac · mock conversion |
| Depends on | M1 ✓ · M23 ✓ · M15 (its tenth surface) · M22 (two of its ten surfaces) |
| Related | M26 (the precedent for adjudicating one cell) · M28 / DEF-042 (four of its ten surfaces are on that docket) |
| Brief | `planning/features-to-triage/M17-surface-states.md` |
| Source mock | `design/mcp-router-console.html` — the design-authority question is M21's, recorded in §3.1 |
| Triage | 2026-08-22 · §2 is owner-facing · §3 is the pipeline record |

---

## 1 · Feature description (the brief, verbatim)

> # M17 — four states on every surface, and chrome that follows them
>
> **Depends on:** M1.
> **Source:** `design/mcp-router-console.html`, PRD §9.6.
>
> Ten surfaces — nine boards and the Settings window — each carry **ideal, empty, loading and
> error**. That is 40 cells, and all 40 are drawn in the mock with copy written for that surface.
>
> The count is the specification. A categorical instruction — "handle all states" — is
> satisfiable with one instance, and on one recorded build it was: six named states produced one.
> Track this as 40 cells and report the fraction built.
>
> ## The copy is per-surface, not per-template
>
> A shared empty state that says "No data" is the same as not having one. Each cell names its own
> situation:
>
> | Surface | empty | error |
> |---|---|---|
> | Servers | No servers adopted yet | Cannot reach the router |
> | Activity | Nothing has called a tool yet | The event stream dropped |
> | Harnesses | No AI harnesses found | Codex's configuration would not parse |
> | Skills | No skills installed | Doctor found 3 broken links |
> | Discover | No results for "kubernetes log tailing" | One index answered, the other did not |
> | Inbox | Nothing is waiting on you | postgres-mcp failed to install |
> | Insights | Not enough history yet | The primary analyst hit its usage limit, so the fallback ran |
> | Checks | Nothing here ships a check suite | 2 of 11 checks failed |
> | Cleanup | Everything installed has been used | The usage store only goes back 6 days |
> | Settings | Settings are unavailable while the router is stopped | The router sent a response this version does not understand |
>
> An error state says what happened, where, and what to do, and shows the evidence — the Servers
> error prints the `launchctl` output including the exit code and the log path.
>
> ## The chrome follows the state
>
> This is the half that gets missed. A window still counting eleven servers over an "adopted
> nothing yet" board is the populated app wearing the first-run screen, and a reader files it as
> a bug. Three things are bound to the state on screen:
>
> - the toolbar subtitle,
> - the sidebar tallies, which hide rather than showing a count the state does not have,
> - the health card, which cannot report "Router serving" over a board that says the router is
>   unreachable.
>
> ## A loading state is designed, not stubbed
>
> Determinate progress where a count is known (`7 of 11`), a live line naming what is being read,
> and skeleton rows matching the shape, size and ground of the content they replace. A skeleton
> of the wrong height guarantees a jump when the content lands.
>
> ## Two conditional states
>
> **Overflow** is exercised and must stay exercised: eleven upstreams in a 250px jack field, a
> seven-column table beside a 340px inspector, eighteen entries in a reconcile diff. **Disabled**
> is exercised on eleven rules. **Offline** is `n/a` — the router is loopback-only, so there is no
> network for the app to lose.
>
> ## Converting this to SwiftUI
>
> Model the state as an enum with an associated payload — `case ideal(Data)`, `empty`,
> `loading(Progress)`, `error(Failure)` — and switch on it in one `@ViewBuilder`. An enum makes
> the four-way exhaustiveness a compile error rather than a review comment, which is the whole
> reason the count is the specification.
>
> - The empty, loading and error bodies are the composable state containers F2 already asks for,
>   so a surface cannot ship populated-only by accident.
> - The copy lives in a `*Copy` enum per surface, which is what makes it assertable.
>   `M7DesignedStateTests` is the pattern: it already rejects short strings and placeholder text.
>   Extend that suite to all 40 cells rather than writing a second one.
> - Chrome that follows the state is a value read from the same enum — the toolbar subtitle, the
>   tally visibility and the health card each derive from it rather than holding their own copy of
>   the truth.
>
> Acceptance: a test enumerates 40 cells and fails on any whose copy is absent, shorter than the
> usable floor, or matches a placeholder pattern. A structure dump for one non-ideal state shows
> the tallies absent from the tree, not merely transparent (M23).

---

## 2 · Triage — 2026-08-22

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*

- **Where it shows up:** every board in the app and the Settings window *(customer-facing — ten existing or newly-added surfaces, each gaining three more states)*; the window's title area, the counts beside the navigation rows, and the health card at the foot of the list *(customer-facing — existing chrome that starts following the board it is sitting over)*. Nothing internal changes.
- **What users will see — per surface:**
  - Each of the nine boards and the Settings window: three states written for that board rather than shared — a first-run screen naming what is missing on *that* surface, a loading screen with progress where a count is known, a line saying what is being read, and placeholder rows the same height as the real ones, and an error screen saying what happened, where, and what to do, with the evidence printed rather than summarised.
  - The window's title area: a subtitle that says what the board is currently doing, instead of one that describes a populated board over an empty one.
  - The counts beside the navigation rows: they disappear on a board whose state has no count, rather than showing a stale one.
  - The health card: it can no longer report the router as serving over a board that says the router cannot be reached.
- **Behaviour changes:**
  - Long names and crowded boards keep behaving as they already do — that case is exercised today and stays exercised.
  - Nothing about being offline changes: the router is on this machine only, so there is no network to lose.
- **Design reference:** the console mock draws all forty cells with its own wording for each; the mock is the source of the copy, subject to the design-authority question under M21.

**Assumptions**

- `[Experience]` Forty cells means four states across the nine boards the mock draws plus the Settings window — so this item lands after the two new boards and after Settings becomes a window, or its own count cannot be filled. *(the app has seven boards and a Settings board today, not nine and a window)*
- `[Experience]` The four states here are the four the mock draws. The nine states the design document asks of every data surface are not replaced by them and stay owed to each board's own item. *(a smaller countable set inside a larger uncounted one, rather than a contradiction)*
- `[Experience]` Every cell carries wording written for that board. A shared sentence used twice is a defect, not an economy. *(the failure this item exists to prevent — six named states once produced one)*
- `[Layout]` A loading screen's placeholder rows match the height of the rows they stand in for, so nothing jumps when the content lands. *(already the rule for the one board that got it right)*
- `[Layout]` On a board whose state has no count, the count beside its navigation row is genuinely absent rather than drawn transparent. *(a reader and a screen reader must agree)*
- `[Operations]` An error screen prints the evidence it has — the command's own output, its exit code and where the log is — rather than a summary of it. *(a paraphrase is how "this could not run" becomes "everything matched")*
- `[Data & scope]` Wording is fixed text shipped with the app; nothing here reads anything about a person or a company. *(no new visibility surface)*
- `[Compliance]` Four of the ten boards already carry a recorded disagreement between the older design and the build about columns the product cannot honestly fill. That disagreement is on your docket and this item does not settle it — those four cells are written against what the build honestly shows. *(the app does not display what the router does not observe)*

- `[Layout]` If the console mock is ruled an exploration rather than the authority, this item keeps its shape and re-sources its forty pieces of wording from the older prototype. The count is the specification either way. *(the structure survives the answer; only the words move)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage M17` before the planner picks this up.*

---

## 3 · Grounding record — pipeline note, not owner-facing

Measured on the main checkout at `7b730ee`, 2026-08-22.

### 3.1 Design authority

Recorded in full at `planning/specs/spec-M15.md` §3.1 and asked as a question at
`planning/specs/spec-M21.md` §2. It is not re-asked here: the four-state grid, the per-surface copy
rule and the chrome-follows-state rule survive either answer — only the wording of forty cells is
sourced from one mock rather than the other, and that is a substitution rather than a redesign.

### 3.2 The state count is genuinely contested, and both numbers are defensible

`DESIGN.md` §5 — *"Every data surface ships nine states, not one"* — lists Default, Empty, Loading,
Partial, Error, Success, Offline, Disabled, Overflow, and the campaign's `REQ-017` asserts against
that nine-state model. This brief asks for four across ten surfaces. No document in the repository
reconciles them.

They are not in conflict on inspection: the mock's four are a strict subset of the document's nine,
and the brief separately handles Overflow and Disabled as conditional states and declares Offline
`n/a` with the same reason `DESIGN.md` §5 gives. So the assumption above treats the forty cells as a
*countable floor* rather than a replacement, which keeps `REQ-017` true and gives this item the
compile-time exhaustiveness its brief argues for. Recorded as an assumption rather than a question
because both readings produce the same build.

### 3.3 What the built app has

- `app/Sources/MCPRouterUI/StateContainer.swift` already models the nine: `SurfaceState` with nine cases, plus `MessageState`, `SkeletonRows`, `OverflowRow`, `PopulatedBoard`, `DisabledAction`. **It is instantiated exactly once — in the `#if DEBUG` design gallery** (`Gallery/GallerySections.swift:232`). Every shipping board hand-rolls its own switch over its own load state.
- All eight boards do have real empty, loading and error bodies today — `ActivityBoard`, `ServersBoard`, `SkillsBoard`, `DiscoverBoard`, `InboxBoard`, `EvalsBoard`, `CleanupBoard`, `SettingsBoard`. So this item is not building unhappy paths from nothing; it is unifying eight hand-rolled switches, adding the two new boards' cells, and making the count assertable.
- `M7DesignedStateTests` is the pattern the brief names, and it covers **two boards** — Checks and Cleanup, roughly fifteen strings. Its `assertUsable` rejects an empty string, anything shorter than twelve characters, and six placeholder patterns; a separate test asserts every state sentence is distinct. Extending it to forty cells is the brief's own instruction and is the right shape.
- `*Copy` enums exist for Checks, Inbox, Activity, Servers, Discover, Library, Queue, Triage, Pairing and the sidebar readout. Two boards have none.

### 3.4 The ten surfaces do not all exist

The mock's source list is Discover, Skills, Servers, Activity, Harnesses, Checks, Cleanup, Inbox,
Insights — nine — under four sentence-case headers (Store, Routing, Maintenance, Attention). The
build has seven boards plus a Settings board. **Harnesses and Insights are M22; the Settings window is
M15.** Two of this item's ten surfaces and the tenth do not exist yet, which is why the dependency row
above names both. The brief declares only `Depends on: M1`.

The mock's own state table marks Activity's loading cell `—`, so the "40 of 40" claim has a dash in
it. Not a blocker: the gate counts what the mock draws.

### 3.5 The briefs are stale against their own mock

`design/mcp-router-console-spec.md` and `PRD.md` §9.3 describe three source-list headers — Routing,
Library, Attention. The mock now draws four, and its board order and accelerators changed with it:
its View menu runs Discover `⌘1` through Insights `⌘9`, where `PRD.md` §9.4 still lists Servers `⌘1`.
The mock changed under M24 on 2026-08-20 at `6c513b0`, after these briefs were written at 00:28 the
same day. Take the mock, not the prose describing it.

### 3.6 What is already measured — cite, do not re-derive

- `D-m23-g` (ORCHESTRATOR.md) — *"The error state's primary action is state-action-disabled where the mock draws it enabled"*, filed against **M17** by name. This item owns it.
- `DEF-015` (closed) — three Mac boards laid out wider than their window and clipped both edges in silence. That is the overflow state the brief says *"is exercised and must stay exercised"*; it was fixed, and the fix is what must stay.
- `DEF-014` (closed) — Cleanup had no reachable empty state because a fixture ignored the scenario. `DEF-034` (fixed in campaign) — Cleanup's skill half could not be drawn by any build. Both are reachability, not copy: a state nothing can render is a state nothing can check.
- `DEF-016` (closed) — Activity's `Reset history…` was specified and never drawn; closed on the owner's decision that `prototype.html` remains the design of record.
- `SURF-003` carries an `unoracled` witness verdict, and the reason is a fixture gap this item inherits: *"the design of record documents Activity's EMPTY state … and the build was photographed with 12 recorded calls. Those are two different states of the same surface, so a difference between them is not evidence about either."* Rendering each state deliberately is exactly what M23's harness does, which is the route out.
- `M26` (Done) is the precedent for adjudicating a single cell of this item's own table: the Checks row was settled by the owner keeping the built board and amending the mock.

### 3.7 What this item owes M23's gate

Ten surfaces means ten `planning/fidelity/<surface>.layers.json` manifests, ten pairing files, and ten
`Surface` cases in `app/Sources/MeasureDump/main.swift`, which declares `case servers` today. The gate
exits 3 on a missing manifest, which is correct and is not a pass. The brief's acceptance line — *"a
structure dump for one non-ideal state shows the tallies absent from the tree, not merely
transparent"* — is a `structure` layer assertion and `MeasureDump` already takes a `--state` argument
and refuses an unreadable one with exit 3.

This is the largest instrument bill in the programme and the planner should size it as such.

### 3.8 Gate record

- Codebase grounding: `app/Sources`, `design/`, `DESIGN.md`, `PRD.md`, `planning/fidelity/`, `planning/test-campaign/`.
- Out-of-family spec review: `agy` / `gemini-3.7-flash-high`, read-only, across all eight verdicts. `codex` down until 2026-08-27. Disposition in §3.9.
- Eight assumptions, none reversing a decision recorded in the tree. The nine-versus-four count was tested for divergence and produces the same build either way, so it is an assumption rather than a question.

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

- **Not accepted — the block.** One lane argued this item is unbuildable without M21, on two grounds. Both were tested and neither holds. **The state-model ground:** `SurfaceState` already has nine cases and the mock's four are a strict subset of them, so the four-cell gate can be written without deleting the other five, and the sketch under either reading is the same build — which is the divergence test failing, so it is an assumption rather than a question. **The census ground:** needing ten surfaces is a dependency on M15 and M22, both already in the header, not a dependency on which document is authoritative.
- **Accepted — the exposure, which neither the brief nor my first draft stated.** Under M21 answer (b) the forty cells' wording is sourced from a mock ruled an exploration, and this item re-keys to the prototype. The structure survives; the copy does not. Recorded as the last assumption in §2 rather than as a block, because the item is buildable either way and the count is the specification under both.
- **Accepted:** the dependency on M15 and M22 was confirmed independently by both lanes, one of them noting that the brief's own copy table contains Harnesses, Insights and Settings rows while its declared dependency is `M1` alone.
