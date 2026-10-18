# spec-WIN6 — the Windows Skills board

| | |
|---|---|
| ID | WIN6 |
| Status | **Developer Review** — built on `ai/win6`, gated, not verified. A runner cannot verify its own build |
| Category | windows · new surface · the largest board in the design of record |
| Depends on | WIN3 ✓ (the shell this board is drawn inside) · WIN2 ✓ (DESIGN.md §11–13) · WIN18 ✓ (`scripts/windows/verify.ps1`) |
| Blocks | WIN16 (the capability document panel; this board leaves it its seam) |
| Brief | `planning/features-to-triage/WIN6-windows-skills-board.md` |
| Source of layout, IA and vocabulary | `design/mcp-router-console.html` (`#b-skills`), cross-checked against the Mac's shipped M4 board (`app/Sources/MCPRouterUI/Boards/SkillsBoard.swift`, `SkillPresentation.swift`, `SkillCopy.swift`) |
| Source of the visual language | `DESIGN.md` §11 · §12 · §13 |
| Source of the wire shapes | `app/Sources/MCPRouterKit/Control/SkillModels.swift` — its header credits a path in no commit reachable from any ref (`src/skills.ts`, the TypeScript models were never merged); the Windows models transcribe the Swift, which is the real source |
| Triage | 2026-08-31 |

---

## 1 · What this item is

The Skills board inside `app/windows/MCPRouter.Shell`: a table of every skill the router knows —
Skill, Marketplace, Version, **Installed into**, Auto-update — where *Installed into* is a row of
per-harness slots rather than one value, plus the Marketplaces and Updates tabs, the skill
inspector, and the head actions `Run doctor`, `Add marketplace…`, `Update all · N`.

It is the first Windows board that talks to the router. The control client it introduces is a
real HTTP read path against the same control API the Mac's `LiveControlAPIClient` speaks: the
router's port (default 8879), reads unauthenticated, writes bearer-tokened. **Writes are not
built** — the board is read-only, for the same reason and in the same words as the Mac's M4.

## 2 · The two facts that shape everything else

### 2.1 The router serves no `/skills` route, and app-side work is forbidden from adding one

Measured: `isControlPath`, `src/control.ts:423` at `2f718779` serves `/servers`, `/usage`, `/sessions`,
`/registry/*` — nothing for skills or marketplaces. `src/skills.ts` has no commits on any branch;
commit `b9db114d` ("M4: revert the TypeScript router work — a merged gate forbids it") records
why: `StandingConstraintsTests.theReferenceIsUntouched` (A38) fails on **any** diff to `src/`.
The daemon work belongs to R2R/R4.

So live, against the router a user runs today, `GET /skills` answers **404**, and this board
renders the version-skew state — exactly the Mac's shipped behaviour, where
`LiveControlAPIClient+Absent.swift` maps that 404 to `malformedResponse` ("this router has no
/skills endpoint") and M4's commit states the consequence: *"against the router a user runs today
this board renders the version-skew Error state. That state was designed for exactly this and is
now load-bearing rather than hypothetical; the populated board is reachable in Debug through the
fixture lane."* Windows takes the same path, including the Debug fixture lane.

### 2.2 The board is read-only, and that is a security decision, not a missing feature

The Mac's `SkillCopy.writesNotYetAvailable` states the reason: "Changing what is installed
arrives with the item that can do it safely — these files are open in your other apps while this
one is running." A read-modify-write against harness directories the client applications hold
open can rewrite a user's whole plugin list and look exactly like "nothing is installed". Every
write control on this board — install-into switches, auto-update, Update all, Add marketplace,
Remove, Update now — is disabled **in place**, with that reason discoverable (§5 Disabled, §11
rule 4). The brief's own assumption agrees: installation goes through the control API, never the
client writing harness config files directly.

## 3 · The decisions

### 3.1 HELD-FOR-REVIEW is modelled as data, not as a style

`HeldVersion` carries `addedCapabilities`; the rule is `wantsMore ⇔ addedCapabilities is
non-empty` (the Mac's `SkillModels.swift`). Consequences, each a named decision in
`SkillPresentation.cs` and covered by tests:

- A held row's version cell reads `2.3.1 → 2.4.0`, in the instrument (Consolas) face.
- The held banner names **what the new version asks for**, verbatim from
  `addedCapabilities` — "The new version asks for network access the installed one never had.
  It is downloaded, not live." with the capability words in the banner body. It never says
  only "held".
- The Updates tab marks a wants-more row **"Held for review"** and a no-added-capability row
  **"Promotes on its own"**.
- **`Update all · N` counts the updatable set, which excludes held items.** The mock's head
  draws `Update all · 4` over four Updates rows, one of them held-for-review; the brief's
  acceptance clause — "Update all acts on the updatable set and does not silently include held
  items" — outranks the drawing, so N counts rows where a newer version exists **and** asks for
  nothing more. On the fixture board that is 3, not the mock's 4. This is the one place this
  surface deliberately diverges from the mock's arithmetic, and it is a security clause doing
  its job.
- `See what changed…` is **disabled in place** with `AutomationProperties.HelpText` naming
  WIN16, which builds the capability document panel (the brief's own assumption: the diff is
  WIN16's panel, not a separate view). The banner body already says what the version asks for;
  the button does not pretend to open a panel that does not exist, and can never commit an
  update, because it does nothing.

### 3.2 Slots: one row, many harnesses, and an unknown that is not an absence

The slot set is **the clients the router reports**, never a hardcoded five. `SkillClient`
carries `supportsSkills` (clients without a skills mechanism are listed in the inspector with
why, not filtered out) and `status`; a client whose directory could not be read renders an
**unknown** slot — never an empty one, because an empty slot asserts a skill is absent somewhere
nobody managed to look. The table renders each slot as a lettered chip; every chip is an
automation element named from the on-screen vocabulary — "Claude Code: installed" / "Cursor: not
installed" / "Grok: could not be read, so this is unknown" — so WIN20's plane can measure the
board's central idea at all.

Slot letters come from the Mac's shipped `slotLabel` mapping (`claudeCode`→CC, `codex`→CX,
`cursor`→CR, `opencode`→OC, else the display name's first two letters), which postdates the
mock: the mock's legend says CU for Cursor, the shipped design of record says CR. **CR wins**;
§6's one-name-per-state rule takes the newer source, and the divergence is recorded here rather
than re-spelled.

### 3.3 Auto-update lives on the marketplace, and the cell can say "not shown"

A skill's auto-update setting is its **marketplace's** `autoUpdate` flag (the Mac's
`SkillCopy.autoUpdateItem`). The cell has four renderings, and collapsing any two of them would
assert something nobody read: **On**, **Off**, **n/a** (standalone skill or local-directory
marketplace — there is nothing to fetch), and **Not shown** (the marketplace record did not
load, which is a different fact from off).

### 3.4 States — §5's nine, all named

| State | Where it draws |
|---|---|
| Default | the populated table, via the Debug fixture lane today, via live data the day the router serves skills |
| Empty | "No skills installed yet" + the Mac's `emptyDetail`, with the mock's two actions (Add a marketplace… → WIN7's, disabled with reason; Find skills already on this PC → disabled: the scan is the router's) |
| Loading | skeleton rows at the real row height, never a spinner over a blank pane |
| Partial | a client's directory unreadable → `partialNote` naming the client, the consequence, the path and the reason; marketplace list failed while skills loaded → auto-update cells say "Not shown" |
| Error | version skew (404): "this router has no /skills endpoint — the router may be newer or older than this app"; server errors and decode failures name what happened and how to fix it |
| Offline | connect refused / token file absent → headline "The router isn't running" + the Mac's verbatim advice line + a Retry action (the §3.7 wording; earlier drafts of this row paraphrased copy that does not ship) |
| Disabled | every write control, disabled in place with `writesNotYetAvailable` or its specific reason |
| Success | **not reachable — the board is read-only** (§2.2). Recorded, as the Mac's M4 recorded it, rather than pretended |
| Overflow | long names and paths truncate with the full value in the tooltip and inspector; rows never change height |

### 3.5 Run doctor and Add marketplace… reach their surfaces

`Run doctor` navigates to the **Checks** destination — doctor reports onto the Checks board
(`CommandCatalog` already assigns it there), and navigation is something the shell can genuinely
do today. `Add marketplace…` (head action and empty-state action) is disabled in place naming
WIN7, exactly as `file.addMarketplace` and `library.addMarketplace` already do in the menu — the
board does not draw a button that does something different from its menu twin.

### 3.6 The command catalog's two WIN6 rows stop lying

`library.updateSkills` and `library.exportLibrary` say "WIN6 builds it" and WIN6 has now built
what it can: reads. Their reasons are updated to the true wait — the board's writes and export
wait on the router's skills routes (§2.1) — with WIN6 remaining the owning item, so the menu
does not promise an action this item has landed unshippable. No test is altered: the catalog
change is the product decision, made here and recorded.

### 3.7 Words are the Mac's, two platform words aside

Every state sentence crosses verbatim from `SkillPresentation.swift` / `SkillCopy.swift` — the
observation footer, the held title/body, the partial note, the inspector's client sentences —
because §6 gives one name per state across both devices. Two deviations, both the same kind:
the mock's empty-state action says "Find skills already on this Mac" and the Mac's
needs-attention filter says "since this Mac first saw it"; this board says **"this PC"**, because
a Windows surface naming a Mac is a defect no vocabulary rule can outweigh.

## 4 · What is built

- `MCPRouter.Shell.Model/Skills/` — `SkillModels.cs` (the wire shapes, decoded with
  System.Text.Json, closed on the `kind` discriminator: an unknown kind fails decoding rather
  than being guessed at), `SkillPresentation.cs` (every decision, no UI framework in sight),
  `SkillsBoardModel.cs` (the load-state machine: client results in, one snapshot out).
- `MCPRouter.Shell.Model/Control/` — `SkillsControlApi.cs` (the read boundary and the error
  taxonomy with its user copy), `LiveSkillsControlClient.cs` (real `HttpClient` reads; 404 →
  version skew; connect-refused → router not running), `FixtureSkillsControlClient.cs` (the
  fixture board the Debug lane serves).
- `MCPRouter.Shell/Views/SkillsBoard.xaml(.cs)` — the board: head, tabs, table, held banner,
  marketplaces cards, updates table, inspector.
- `ShellWindow`: the skills destination constructs the board; the other nine still construct
  `BoardPlaceholder`. `App`: a `--fixture-skills` launch flag, honoured in Debug only, so a
  release build can never draw fixture data.
- Tests in `MCPRouter.Shell.Tests` for the models, the presentation decisions (including the
  Update-all exclusion), the client's status-code mapping, and the state machine.

## 5 · What is NOT-RUN, and why

| What | Why |
|---|---|
| The populated board against live router data | No `/skills` route exists; A38 forbids adding one app-side (§2.1). The read path is real and tested against canned statuses; the day the daemon ships, the board consumes it unchanged |
| Every write: install into a harness, auto-update, Update all, Add/Remove marketplace | Read-only board (§2.2) — the Mac's shipped M4 posture, with the same stated reason |
| The self-test capture of this board | Needs an interactive window station; this session is Session 0 (spec-WIN3 §7 gap 1, unchanged) |
| Cross-family review | `codex`, `agy`, `grok` absent on this machine; recorded not-run, never a pass |
| `make lint` / `make test` | Absent on Windows; the lane is `scripts/windows/verify.ps1`, which is the conductor's to run |

## 6 · What this item does not do

- No Discover, no store browsing, no marketplace management writes, no capability document
  panel (WIN16's), no checks data in the inspector (WIN8's Checks board owns that; the mock's
  "12 of 12 passed" row is omitted rather than drawn from data nothing serves).
- No changes to `src/` (A38), no harness config file access, no skill filesystem reads — the
  client sees the router only.
- No keyboard-model changes (WIN21's), no filters/search (the design of record's board carries
  three tabs and no search field; the Mac's filters are its own surface decision).
