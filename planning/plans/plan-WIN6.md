# plan-WIN6 — the Windows Skills board

**Spec:** `planning/specs/spec-WIN6.md` · **Brief:**
`planning/features-to-triage/WIN6-windows-skills-board.md` · **Mock:** `design/mcp-router-console.html`
`#b-skills` · **Size:** Standard (one board, its client, its model, its tests; no router work).

## 0 · The constraints this plan is built under

- A38: `src/` is untouched. The board consumes `GET /skills` and `GET /marketplaces` and
  renders the 404 as version skew when the daemon has no route — the Mac's M4 posture.
- The board is read-only. Writes are disabled in place with the Mac's `writesNotYetAvailable`
  reasoning; nothing here edits harness directories.
- Tests are plain net8.0 (no WinUI reference): every decision lives in `MCPRouter.Shell.Model`,
  the view only draws.
- Modelled on `app/Sources/MCPRouterKit/Control/SkillModels.swift`, `SkillPresentation.swift`,
  `SkillCopy.swift`, `LiveControlAPIClient+Absent.swift` — the same decisions, not a re-derivation.

## 1 · Slices, in dependency order

### S1 · Wire models (`MCPRouter.Shell.Model/Skills/SkillModels.cs`)

Port of `SkillModels.swift`: `SkillPresence`, `SkillClientStatus`, `SkillClient`,
`SkillSource` (closed `kind` discriminator: `plugin` / `standalone`; an unknown kind throws
`JsonException` — never a `default` guess), `PluginOrigin`, `HeldVersion` (+ `WantsMore`),
`SkillProvenance`, `Skill` (+ `NeedsAttention`), `SkillsResponse` (+ `SlotClients`,
`UnsupportedClients`), `MarketplaceSource`, `Marketplace`, `MarketplacesResponse`.
`System.Text.Json` with snake_case policy; `null` tolerated where the Swift decodes tolerate it;
a missing `skills`/`marketplaces` key decodes as empty (M4's red-green case).

### S2 · Presentation decisions (`Skills/SkillPresentation.cs`)

Port of `SkillPresentation.swift` + `SkillCopy.swift`, only what this board draws: subtitle,
`observationFooter`, version cell (unversioned in body face; held as `a → b`), source line,
slot states + `SlotLabel`, client sentences, `PartialNote`, held title/body, empty copy,
auto-update item (on / off / n/a / not-shown + reasons), updates-tab classification, and
**`UpdatableCount`** — the Update-all set: `held != null && !held.WantsMore`, held items
excluded. Two platform word substitutions: "this PC" for "this Mac" (spec §3.7).

### S3 · Control client (`Control/`)

- `SkillsControlApi.cs`: `ISkillsControlClient` (`SkillsAsync`, `MarketplacesAsync`) and
  `SkillsControlError` with the Mac's taxonomy and copy — `RouterNotRunning` ("MCP Router is not
  running…"), `Unauthorized`, `Server`, `MalformedResponse` ("the router may be newer or older
  than this app"), `Transport`.
- `LiveSkillsControlClient.cs`: `HttpClient` GETs; ctor takes `HttpMessageHandler` so tests
  inject canned responses. Mapping: connect failure → `RouterNotRunning`; **404 →
  `MalformedResponse("this router has no /skills endpoint")`** (version skew, the Mac's
  `skillsRead` rule); 401 → `Unauthorized`; other non-2xx → `Server`; body that fails decoding →
  `MalformedResponse`. Reads carry no Authorization header (the router requires the token on
  writes only — `src/control.ts`).
- `FixtureSkillsControlClient.cs`: the mock's drawn board as fixture data (trawl CC·CX·CR·GR,
  design-review held 2.4.0 wanting network access, ux-craft, acceptance-e2e, create-mac-icon,
  graphify standalone; three marketplaces; one unreadable client for the Partial state).

### S4 · State machine (`Skills/SkillsBoardModel.cs`)

`SkillsBoardModel.Snapshot(clientResults)` → one record carrying: load state (loading /
populated / empty / version-skew / failed / offline / partial flags), tab counts (Installed /
Marketplaces / Updates), `UpdateAllCount`, the held banners, per-row cells (version, source,
slots, auto-update). Exhaustive switch — a new state stops the build rather than drawing blank.

### S5 · The view (`MCPRouter.Shell/Views/SkillsBoard.xaml` + `.cs`)

- Head: title, subtitle, actions — Run doctor (→ `SelectDestination("checks")`), Add
  marketplace… (disabled, HelpText names WIN7), Update all · N (disabled: writes;
  HelpText = the read-only reason).
- Selector ( Installed · N / Marketplaces · N / Updates · N ) — `NavigationList`/`RadioButtons`-free:
  a `SelectorBar`-style `ItemsControl` of `ToggleButton`s? No — **`Pivot`-free plain `Selector`
  is not themable here; use three `RadioButton`s in a single `RadioButtons` group** styled by
  theme resources only, one checked at a time, names matching the tabs' words.
- Installed tab: held banner(s) + table (Skill, Marketplace, Version, Installed into, Auto-update)
  + slots legend + observation footer. Rows: full row selectable → inspector.
- Marketplaces tab: one card per marketplace (name, source line, freshness/supply pills as text,
  auto-update line + reason, Browse in the store… → discover; Remove… / Update now / trust
  buttons disabled with reasons).
- Updates tab: table (Skill, Installed, Available, What changed, disposition).
- Inspector: selected skill — Read me… / Changelog disabled with reasons; Installed into rows
  with disabled `ToggleSwitch`es (state = slot; HelpText = reason or the unknown sentence);
  provenance; the "why there is no use, by version" section; no checks row (WIN8's).
- Loading: 6 skeleton rows at row height; Error/Offline/Empty: centred card per §3.4.
- Every control: `AutomationProperties.Name` from the on-screen words; `AutomationId` unique;
  theme-resource brushes only; nothing below 12px regular; Consolas for instrument values.

### S6 · Shell wiring

- `ShellWindow.ShowDestination`: `skills` → `new SkillsBoard(...)`; the other nine unchanged.
  `ShellWindow` gains an optional `ISkillsControlClient` (default: live, built from
  `http://127.0.0.1:8879`).
- `App`: `--fixture-skills` parsed like `--selftest`; honoured only under `#if DEBUG` (a
  release build logs and ignores it).
- `CommandCatalog`: `library.updateSkills` / `library.exportLibrary` reasons updated to the
  read-only truth (spec §3.6). No other catalog change.

### S7 · Tests (`MCPRouter.Shell.Tests`)

- `SkillModelsTests`: happy decode from wire JSON; unknown `kind` throws; missing keys → empty;
  presence map incl. `unreadable`; held round-trip.
- `SkillPresentationTests`: version cell rules; slot states + labels; subtitle; partial note;
  client sentences; auto-update four cases; **update-all excludes held** (the red-green
  security test: a wants-more held version never counts, adds nothing to N).
- `SkillsControlClientTests`: via a stub `HttpMessageHandler` — 200 decodes; 404 → version-skew
  wording; 401 → Unauthorized; 500 → Server; thrown `HttpRequestException` → RouterNotRunning;
  invalid JSON → MalformedResponse; no Authorization header on reads.
- `SkillsBoardModelTests`: loading → populated; 0 skills → empty; 404 → version-skew state;
  connect failure → offline; unreadable client → partial flag + note present; tab and
  update-all counts on the fixture board (Installed 7 · Marketplaces 3 · Updates 4 · Update all 3).

## 2 · Test strategy

Model layer: xUnit in `MCPRouter.Shell.Tests` (plain net8.0), run with `dotnet test` — the same
invocation `verify.ps1` already enrols. Client mapping: canned `HttpMessageHandler` responses —
real HTTP status handling, no network. View: covered by the shell's self-test captures only
when an interactive session exists — recorded NOT-RUN here, never as a pass.

## 3 · Order of work

S1 → S2 → S3 → S4 (each with its tests, `dotnet test` green) → S5 → S6 → build the Shell with
MSBuild (Restore then Build, two invocations) → `dotnet test` full suite → run the repo's
portable gates the lane runs where they touch this work → commit named paths on `ai/win6`.

## 4 · What this plan deliberately leaves

Everything in spec §5 and §6: writes, live populated data, WIN16's diff panel, WIN8's checks
row, filters/search, keyboard changes, and any change to `src/`.
