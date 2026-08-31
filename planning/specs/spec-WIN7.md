# spec-WIN7 — the Windows Discover board

| | |
|---|---|
| ID | WIN7 |
| Status | **Developer Review** — built on `ai/win7`, gated, not verified. A runner cannot verify its own build |
| Category | windows · new surface · the store board inside the WIN3 shell |
| Depends on | WIN3 ✓ (the shell, `BoardHost`, the Discover destination row) · WIN18 ✓ (`scripts/windows/verify.ps1`) · WIN2 ✓ (DESIGN.md §11–13) |
| Blocks | WIN16 (capability document panel lists this board among its deps) |
| Brief | `planning/features-to-triage/WIN7-windows-discover-board.md` |
| Mock | `design/mocks/mac-surfaces.html` §4 (brief's named mock) |
| Design of record | `design/mcp-router-console.html` §DISCOVER (`:2830`) — outranks the mock per DESIGN.md §1 |
| Presentation of record | `app/Sources/MCPRouterKit/Registry/*`, `MCPRouterKit/Discover/DiscoverCopy*`, `DiscoverBands.swift`, `MCPRouterUI/Boards/DiscoverBoard*` — the Mac's settled decisions, taken over rather than re-derived |
| Data endpoint | `GET /registry/search` on the loopback control API (`src/control.ts:856`), served by `src/registry.ts` |
| Triage | 2026-08-31, by the WIN7 runner (fleet item; no separate triage session) |
| Cross-family spec review | **NOT-RUN.** `codex`, `agy`, `grok` and the `claude` CLI lane are absent on this machine (ORCHESTRATOR.md, "Windows fleet"). Recorded as not-run, never as a pass. |

---

## 1 · What this item is

The Discover destination in the Windows shell stops being a placeholder and draws the merged
official-registry + Smithery catalogue, read live from the router's `GET /registry/search` on
127.0.0.1. It is the first Windows surface to talk to the router, so it also lands the small real
control client the shell has so far deferred (spec-WIN3 §3.5, §6: "no control API client" was a
WIN3 scope line, not a product one).

Two bands, never one ranked list. No install affordance on a row. A rate-limited or unreachable
registry draws as itself. Every state draws.

## 2 · The two bands, and why Trending is not one of them

The brief: *"Implement two separate bands, never one ranked list — editorial and measured are
different claims. A trending row carries a window AND a signed delta, or it is not drawn as
trending."* Both clauses are implemented as stated, and the second one decides the band names:

**Measured fact: nothing in this product keeps a history of either index.** `/registry/search`
serves `useCount` (cumulative Smithery sessions — `src/registry.ts:48`) and `stars` (current
GitHub counts, day-cached in `github-cache.json`, one freshness stamp, overwritten on refresh).
No window, no delta, no prior observation exists anywhere on the wire or on disk. **A trending
row therefore cannot be drawn, and none is**: no code path in this board produces a signed delta,
so the brief's conditional resolves to its second branch for every possible row. The mock's
trending rows (`+218%`, `+64%`, `−8%`, window `7d ⌄`) are the stale drawing; DESIGN.md §6's table
already rules on exactly this — *"Discover, trend and velocity … the refusal wins and the drawing
is stale"* — and names the sentence the surface states instead
(`RegistryPresentation+Notes.swift:83`).

The bands are the design system's own (`DiscoverBands.swift`), taken over with their copy so §6's
one-name-per-state rule holds across platforms:

| Band | Claim | Honest over |
|---|---|---|
| **Recently changed** | editorial — recency, "the only thing 'new' means here" (console `:2886` says exactly this of its featured hero) | rows with a parseable change stamp; scoped by the window control |
| **Most used** | measured — `useCount`, drawn with its unit and its index ("N sessions on Smithery") | rows carrying a session count; the window never reaches it |

An entry lacking a band's field is **absent from that band, never ranked at zero** — absence says
"not measured", zero says "measured, and none". Band-empty-within-results is its own state with
its own copy (the design system's `bandEmpty*` sentences), never the whole-board empty.

The `trendingNote` — *"No trend or velocity figure is shown. Measuring one needs a history of
these indexes over time, which the router does not keep yet."* — is drawn in the board's notes
always, as the Mac board draws it.

## 3 · No install affordance on a row

The brief's security property, implemented structurally: **a row has no install action, no
button, and no gesture that installs.** Tapping a row (or pressing Enter on it) opens the detail
dialog; the only Add control in the entire board lives inside that dialog. The Mac states the
reason in its own board model (`DiscoverBoardModel.commitDefaultAction`): *"A list row that
installs is exactly the one-click path from a ranking to executing someone's code that this board
is shaped to refuse."* Windows 11's card idiom invites an inline primary action; the invitation is
declined.

The detail surface is a `ContentDialog` — the Windows modal idiom for open-a-thing-from-a-list —
carrying: name and provenance, the sanitised description, the entry's figure with its unit and
index, the date with its meaning, the archived warning when present, the capability statement
(read from the install block: argv tokens one per element in the instrument face, or the remote
host alone), the requirement fields when the entry asks for values, and the Add action.
`spec-WIN16` may later absorb this into the capability document panel; the brief's assumption
records that destination, and until WIN16 lands this dialog is the detail surface — the same role
the Mac's own `DiscoverDetailSheet` plays on macOS. Nothing is stubbed against WIN16: every field
the dialog draws is read from the search response in hand.

The Add action is the board's **one** accent-filled control (§11 rule 4). In the dialog it sits
leftmost — the Windows "do it" position — with Close rightmost. A destructive action would never
be default and none is offered here. Disabled Add states dim in place with a discoverable reason
(already added · no install block · required values empty · in flight).

Install is the real boundary: `POST /servers` with the control token from
`%USERPROFILE%\.claude\mcp-router\control.token` (`MCP_ROUTER_HOME` honoured) as a bearer header.
The token is read into the header and never logged, printed, or stored by this board. `force` is
never sent — a registry row must never be able to adopt (overwrite) a declaration the user
already trusts. A 422 (the router's first-index failure) is surfaced as the router's own message
with no auto-retry; a 409 reads as already declared.

## 4 · Categories, and the refusal of invented ones

The brief: *"Browse by category reaches a filtered view."* The mock draws chips — All, Design,
Research, Testing. **Neither index publishes a topic, kind, or category.** `/v0/servers` and
Smithery's `/servers` carry no such field, and deriving one by keyword would be classification
inferred and presented as data — the same move the design of record refuses on licence and
capability fields. The console's own Kind chips (Servers / Skills / Plugins) name populations
`/registry/search` does not serve; the design of record's `documentFacts` comment states the
general rule (*"each is omitted when it was not observed"*).

What the data does carry, and what ships:

- **The bands are the browse structure** — the design system's own answer (`DiscoverCopyList`:
  "clear the search to browse the bands"), each band a real category of claim (§2).
- **A publisher filter — All publishers / Official registry / Smithery** — the one real
  partition the wire carries (`source`, refined by provenance from the `id` prefix, never by the
  `source` label alone — the `smithery:github` fixture proves the label can lie). Selecting one
  filters both bands; the filter's scope is stated beside it, and a scoped band that empties
  within existing results says so rather than borrowing the whole-board empty.
- **The search field**, a real query to both indexes, reaching the same filtered view.

## 5 · The states (DESIGN.md §5, the acceptance sketch's named worst state)

| State | Draws |
|---|---|
| Loading | skeleton rows at the real row geometry, never a spinner over a blank pane, plus the design system's slow-search sentence (this board's loading can genuinely take minutes: two index calls at 12 s timeouts plus star enrichment) |
| Populated | both bands, their notes, and the board's notes footer |
| Partial — rate-limited or an index down | **the named worst state, drawn as itself**: the warning band renders what happened and what is missing ("Showing Smithery only.", "Repository details are incomplete."), classified from the router's `warnings[]`; a degraded search that returned *nothing* draws partial — never the empty state, so a rate limit can never wear "nothing found"'s clothes |
| Stale | last good reading kept on screen with a banner naming the live failure; a refresh that did not complete is not evidence the catalogue moved |
| Empty, no query | "Nothing came back from either index." + Try again |
| Empty, with query | "No server matches …" + Clear search |
| Band empty within results | each band's own sentence; the windowed Recently changed empty offers Any time |
| Disconnected (router not running) | its own pane, never a generic error: the router is **local** on Windows, so the copy is adapted from the phone's and says so; offers Try again; starting the router is WIN23's surface and is not faked here |
| Failed | the reason rendered from a closed enum, never the router's free-text body interpolated |
| Overflow | names truncate; full value in the dialog; rows never change height |

Every control carries default / hover / focus / disabled. Every state with a colour carries a
word beside it (§6 via §12 — on Windows the success/critical hues are the same luminance, so the
word is the only channel some users have).

## 6 · Windows floor compliance (§11–§13)

- Sentence case everywhere, a gate over every string the board draws (§11 rule 2).
- No `TextFillColorTertiary` on text that has to be read (§12's finding); hierarchy from weight
  and position on `TextFillColorSecondary`.
- Figures, dates, argv and the port are instrument data in Consolas (§12); prose never.
- Monogram plates drawn locally — **no remote artwork**; `iconUrl` is attacker-chosen and fetching
  it would be a second channel off the loopback boundary (the Mac's `remoteArtworkRefusal`,
  taken over verbatim as this board's rule).
- Icons are Segoe Fluent Icons through `FontIcon`/`SymbolIcon`, monochrome, `Foreground`-drawn.
- Arrow cursor everywhere; the hand appears nowhere (§11 rule 8).
- Focus visuals are the platform's high-visibility pair, never accent-bound (§11 rule 11).
- The accent appears once: the dialog's Add (§11 rule 4, Windows order). Provenance marks carry
  words, never colour alone (§11 rule 12).
- Rows are `ListView` items — the platform's own selection backplate and keyboard model; bands
  are two lists, never one.
- Motion: none authored. WinUI's defaults only (§13: "avoid custom animations where possible").
- Keyboard: Tab within the board, F6 between pane and board (the shell's), Enter opens the
  focused row's detail, Esc dismisses the dialog; the search field is reachable and labelled.

## 7 · The control client

`MCPRouter.Shell.Model` (plain net8.0, headless-testable — the tests cannot load WinUI) gains a
`Registry/` folder: wire models matching `/registry/search` exactly, the presentation port
(sanitising, provenance, dates, figures, bands, notes, states), the install capability
(statement, action, declaration), and `RegistryClient` over `HttpClient`. Reads need no token
(the router only gates mutating methods — `src/control.ts:464`). The port is the router's own
config value: top-level `port` in `servers.json` when present, else 8879; host 127.0.0.1. The
board fetches on load and on debounced query change, generation-guarded so a superseded response
— success or failure — never repaints a newer query, and marshals to the UI thread through the
`DispatcherQueue`.

## 8 · What this item does not do

- No harness/plugin/skill catalogue rows: `/registry/search` serves servers, and the board will
  not dress one population as three.
- No router lifecycle (WIN23), no capability document panel (WIN16), no packaging (WIN19).
- No re-skinning the shell: WIN3's chrome, keyboard and title rules are inherited untouched.
- `make lint` / `make test` cannot run on this machine and are not reported. The lane is
  `scripts/windows/verify.ps1`, `build-shell.ps1` (MSBuild Restore then Build as separate
  calls), `dotnet test` on the headless test project, and the shell self-test.

## 9 · Acceptance criteria (the oracle later stages measure against)

1. Two bands — Recently changed and Most used — render separately, with their own headers,
   notes and rows; no view of the board is one ranked list.
2. No row is drawn as trending; no signed delta, rate or percentage is rendered anywhere on the
   board, and the trending-refusal sentence is always present.
3. No row carries an install affordance; opening a row reaches the detail dialog; the only Add
   control is in the dialog; the dialog's Add is disabled with a reason whenever the entry is
   already added, carries no install block, or is missing a required value; install performs the
   real token-authenticated `POST /servers` and never sends `force`.
4. The publisher filter and the search field each reach a filtered view; a filter that empties
   one band within existing results draws that band's own empty sentence.
5. A rate-limited or partially-unreachable registry draws the partial state — classified warning
   copy naming what is missing — and a degraded search that returned nothing draws partial,
   never the no-query empty.
6. Loading, stale, disconnected and failed states all draw, per §5's table.
7. Every row, band, filter and state control is addressable in the UI Automation tree under its
   on-screen name; each row announces its parts as one stop.
8. `dotnet test` green on the headless suite; `build-shell.ps1` green; the shell self-test
   captures the Discover board in both appearances. The live-registry integration is attempted
   against a real router run and recorded with its true verdict — if unreachable from this
   machine, the disconnected state is the honest draw and the integration is recorded NOT-RUN,
   never faked.
