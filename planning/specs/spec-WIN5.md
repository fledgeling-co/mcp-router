# spec-WIN5 — the Windows Activity board

| | |
|---|---|
| ID | WIN5 |
| Status | **Developer Review** — built and gated on `ai/win5` in `.worktrees/WIN5` (progress note, §9); a runner cannot verify its own build, so this stops before verify and merge |
| Category | windows · new surface · the densest reading surface in the product |
| Depends on | WIN3 ✓ (the shell this is drawn inside) · WIN2 ✓ (DESIGN.md §11–13) · WIN17 ✓ (the Windows-shaped wire, measured) · WIN18 ✓ (the lane) |
| Brief | `planning/features-to-triage/WIN5-windows-activity-board.md` |
| Mock | `design/mcp-router-console.html` §ACTIVITY (`:2211`–`:2373`) — WHAT |
| Windows floor | `DESIGN.md` §11 · §12 · §13 — HOW |
| Triage | 2026-08-31, fleet runner (cross-family review not-run: `codex`/`agy`/`grok` absent on this machine, recorded as not-run, never as a pass) |

---

## 1 · What this item is

The live reading surface: every tool call every harness made, as it happens, answering *which
agent did that*. Five columns — Time, Harness, Tool, Duration, Result — a `Pause` control, an
`Export…` action, the four result filters, and a per-harness tally, all consuming `GET
/usage/stream` on the loopback control API. It is the first Windows surface with a router client
behind it, and it is the real test of whether the Windows palette survives the product's densest
board.

Two properties outrank the layout: it is **live** (a stream, never a poll), and it is **honest**
— every figure it draws is one the router actually sent (`DESIGN.md` §6).

## 2 · The wire, read rather than assumed

Measured from `src/usage.ts` and `src/control.ts` on this branch:

- `GET /usage/stream` is **SSE** (`text/event-stream`), opens with a `: connected` comment,
  emits `data: {…}` per call, and keeps the connection alive with a `: ping` comment every 25 s.
  A line beginning with `:` is a comment, never an event — decoding it would look like a broken
  router.
- Each record: `ts` (ISO), `server`, `tool`, `ok` (bool), `ms` (int), `cold` (bool),
  `pid?`, `cwd?`, `project?`, `client?` (the harness's executable name), `err?`.
  On Windows `cwd`/`project` are absent (WIN17's measured limit), so no Windows surface may
  group by project.
- **GET routes carry no token** — `handleControl` gates only mutating methods. The client
  therefore reads GET-only and never reads `control.token` at all. The board holds no secret
  and cannot leak one.
- The router records a call only after it completes, and its in-memory ring holds **500**
  (`RING_SIZE`). `GET /usage?limit=500` returns that tail newest-first. The board matches the
  ring exactly: the backfill is the whole of what the router has, and the live half tops up to
  the same bound rather than growing without limit (the Mac's `ActivityRecords.capacity`
  reasoning, one platform over).
- Records are de-duplicated by id `ts|server|tool|pid` — the stream and the backfill overlap by
  construction, and a log that shows one call twice is a log nobody can count from.

## 3 · The decisions

### 3.1 The harness column — discovered, never hardcoded

The brief's assumption holds: which harnesses exist is a property of the machine. The tally is
built from the `client` values actually present in the loaded window, ordered by count then
name, with one row per distinct client. A record the router could not attribute joins **one**
group named `Unattributed` — `ActivityNaming.unattributed`'s word, the Mac board's constant, so
both platforms say it one way (§6). A client name that is empty or absent is the same group.

Display names: known executable names map to their product names (`claude` → `Claude Code`,
`codex` → `Codex`, `cursor` → `Cursor`, `gemini` → `Gemini CLI`, `grok` → `Grok`); an unknown
name renders as itself. The *list* is discovered; the dictionary only names what is already
discovered.

### 3.2 The result column — four words the wire can defend

The mock draws `ok`, `timeout`, `held`. The wire carries `ok: bool` and `err: string`. The
mapping, each step named:

| Word | When | Mark |
|---|---|---|
| `ok` | `ok == true` | success dot |
| `timeout` | `!ok` and `err` matches a timeout (`timed out`, `timeout`) | critical dot |
| `failed` | `!ok`, any other error | critical dot |
| `held` | nothing on this wire can produce it | caution dot |

`failed` is not in the mock's vocabulary and is kept anyway: the router reports non-timeout
failures, and hiding them inside `timeout` would write a wrong word on real rows. Every
colour-carrying cell carries its word beside it (§6) — on Windows this is not decoration, it is
the only channel some users have, because `SystemFillColorSuccess` against
`SystemFillColorCritical` measures 1.00:1 dark and 1.04:1 light (§12).

**`held` is the recorded deviation.** The design of record draws a held call; the router holds
*tool-surface changes*, never calls, and no field on this wire names a held call. So the `Held`
filter and the `held` result word exist, are defined, and match nothing today; selecting the
filter over a loaded window draws the filtered-to-nothing state whose copy says what is true
("the router holds no calls for review"). This is the M2 precedent — the build's own honest
sentence is the design of record where the drawing names a state the wire cannot produce — and
the deviation is recorded here rather than papered over with a fabricated mapping.

### 3.3 Pause — the view freezes; the window does not drop

While paused, arriving records are still ingested into the 500-record window (that is what
"must not drop" means here), but rows, tallies and counts are not recomputed on screen. On
resume the view refreshes to the window as it now stands, so every call that arrived while
paused is present, in order, exactly once. The board draws what was held back: "`N` calls
arrived while paused." — a count of records actually held, cleared on resume, never an
estimate. The control reads `Pause` while live and `Resume` while paused, and its automation
name carries the word on screen (WIN20's plane).

### 3.4 Filtering is client-side over one window

`GET /usage/stream` accepts no filter, so a server-side filter would give a board whose
backfill and live half disagree (spec-M2 §D1's finding, restated). One predicate over one
in-memory window: the four result filters and the harness toggles compose, filter changes cost
no request, and there is exactly one definition of what is on screen. The tallies count the
records passing the current *result* filter per harness; the rows show records passing the
result filter *and* the harness toggles — so a tally and the rows it heads can be read against
each other without arithmetic.

### 3.5 Export… opens a further view, then writes a real file

The ellipsis convention binds the first half. The second half is real: the dialog offers JSON
lines or CSV over the **visible slice** (what is on screen is what is exported — the window is
capped, so this is a fact the reader can verify against the rows), then writes through the
platform's `FileSavePicker`. §11 rule 4's dialog order: `Export` leftmost and accent-filled,
`Cancel` rightmost. The picker is initialised with the window's handle, which an unpackaged
WinUI 3 app must do explicitly or the picker throws.

### 3.6 The offline action is Reconnect, and the "Start the router" button is not copied

§6's one-name-per-state rule carries the *wording* across: the board's offline state reads
**"The router isn't running"** with the Mac's `routerNotRunning` detail sentence. The Mac's
action — "Start the router" — is a capability this build does not have: starting the router is
router lifecycle, owned by a later item, and a button that names an action nothing performs is
the disabled-placeholder failure `StateMessage.withoutAction` exists to prevent. The board
offers **`Reconnect`** instead, which is real: the user who has started the router themselves
gets on the board with one click, and retrying a refused loopback connection is instant.

### 3.7 Commands live on the board's CommandBar

§11 rule 7 names the CommandBar as the home of a view's commands. `Pause` and `Export…` sit on
a CommandBar at the head of the board; the four result filters are a `SelectorBar` (the WinUI
control for exactly this: an exclusive, one-of-n view switch); the harness tallies are toggle
buttons, because each is an independent inclusion — §11 rule 6 maps that to checkbox semantics.

No new chords are granted. DESIGN.md §13's table carries `Ctrl+4` (to the board, already bound
by WIN3) and no row for pause or export, and WIN3 §3.3's rule holds: a build does not grant a
chord the design authority does not carry. The buttons are pointer- and keyboard-tab-reachable.

### 3.8 What is drawn with the instrument voice

§2/§12 reserve monospace (Consolas on Windows) for anything a user could paste into a terminal
plus numerals, counts, durations and status. So: **Tool** (`server__tool` — the namespaced name
the harness actually calls, measured from `scripts/e2e.mjs`'s "every tool is namespaced
`<server>__<tool>`"), **Time**, and **Duration** are Consolas. Harness names are words, not
paste-strings, and are Segoe UI. Tool names truncate with the full value in the tooltip and in
the row's automation name (§5's overflow row, answered without an inspector).

### 3.9 Durations render in the design of record's units

The mock writes `612 ms`, `1.94 s`, `30.0 s`. The board writes the same: below one second in
whole milliseconds; one to ten seconds with two decimals; ten seconds and above with one. The
router's unit is the millisecond (`UsageRecord.ms`), so this is presentation, never
re-measurement. A slow call (> 2 s, the Slow filter's own threshold) is distinguishable at a
glance by its duration text sitting beside a result word — and by the filter that isolates it —
rather than by an extra colour, which §2's indicator-exclusivity rule does not have to spend.

## 4 · The state matrix (§5 — the states ARE the design)

Every state below is drawn by the board, with its real copy. Where the Mac authored the
sentence first, the words carry across unchanged (§6), and the file records which.

| State | Draws | Copy |
|---|---|---|
| Populated | the five columns, tallies, subtitle | subtitle `Showing N calls · <feed>`, or `N of M` while a filter is on |
| Empty | glyph, one sentence, one action | mock's: **Nothing has called a tool yet** / *Start a session in any wired harness and its calls appear here within a second. The log fills itself; there is nothing to set up.* Action **See which harnesses are wired** → the Harnesses board (a navigation the shell can really perform) |
| Loading | skeleton rows at the true row geometry + status line | *Attaching to the event stream…* — never a spinner over a blank pane |
| Partial (feed dropped, retrying) | banner over the history, no button | *The live feed dropped. New calls won't appear until it reconnects.* / *The newest call here is from `ts`.* — Mac wording, carried |
| Disconnected (ladder walked) | banner over the history + action | *The live feed stopped retrying.* / *… Reconnecting reloads the history as well, so anything that arrived while the feed was down comes back with it.* Action **Reconnect now** |
| Offline (nothing on the loopback port) | full-pane state | *The router isn't running* / *Nothing is listening on the control port, so there is nothing to show yet. Starting it takes a moment and your servers stay exactly as you left them.* Action **Reconnect** — see §3.6 |
| Filtered to nothing | empty-matches state + action | *No calls match these filters* / *That combination has nothing in it. Clearing the filters shows all N again.* Action **Clear filters** |
| Held filter, satisfied by nothing | the same state, held's own copy | *No held calls* / *The router holds tool-surface changes for review, not calls, so nothing matches this filter yet.* (§3.2's deviation, drawn) |
| Overflow | truncation + tooltip + full automation name | rows never change height |
| Disabled | n/a — no control on this board is conditionally disabled | — |

Controls carry default / hover / focus-visible / pressed states from the platform controls
themselves; no control restyles them.

## 5 · What is built

```
app/windows/
  MCPRouter.Shell.Live/               plain net8.0 — the router client, no WinUI, so every
    CallRecord.cs                     claim about the wire is testable headless
    UsageSnapshot.cs                  GET /usage decode
    UsageStreamClient.cs              the SSE client: comment skip, record decode,
                                      ReconnectPolicy (0.5 s → 30 s, 6 attempts, 5 s healthy),
                                      IAsyncEnumerable<StreamEvent>
    ActivityModel.cs                  the window: capacity 500, dedup, pause buffer,
                                      result filters, harness tallies, phase
    ActivityCopy.cs                   every sentence §4 draws, as data
    ActivityFormatting.cs             duration words, time-of-day, harness display names,
                                      result classification
  MCPRouter.Shell.Live.Tests/         xunit, headless, real loopback sockets
  MCPRouter.Shell/
    Views/ActivityBoard.xaml(.cs)     the surface; wired into ShellWindow's ShowDestination
                                      by one additive branch, the seam WIN3 left
```

## 6 · What this item does not do

- No inspector pane. The mock draws one; the brief does not name it, and the mock's inspector
  carries fields this wire does not send (arguments, result payload, spawn/queue/upstream
  splits) — drawing them would fabricate exactly what §6 forbids. A Windows inspector that
  draws only wire-carried facts is a follow-up, not a silent cut.
- No router lifecycle (§3.6), no settings, no notification surface.
- No project column or project filter: the Windows wire carries no `cwd` (WIN17's measured
  limit), so there is nothing to draw and the board does not pretend otherwise.
- No retention callout. The mock's "kept for 90 days" is a number this wire does not carry; the
  board's foot says what is true (§4's populated foot: *Calls are recorded locally and never
  leave this PC. The list shows the router's recent-call window — older calls rotate out as new
  ones arrive.*) rather than shipping the mock's stale figure.

## 7 · Gates and what each can prove here

| Gate | Proves |
|---|---|
| `MCPRouter.Shell.Live.Tests` (headless xunit) | the SSE client against a **real loopback SSE server**: greeting/comment/record parsing, decode-and-skip of one malformed record, reconnect ladder and its delays, disconnect detection; the model's dedup, cap, pause-no-drop, filters, tallies, classification, formatting; the copy's sentence-case and §6 honesty. Golden SSE bytes captured from a **real router on this machine** are asserted verbatim |
| `scripts/windows/build-shell.ps1` | the shell with the board inside it builds; Restore and Build as two MSBuild invocations, artefact on disk |
| self-test (`--selftest`) | the board draws inside the shell for the activity destination, disconnected state included (no router in that session) |
| live probe (this session) | a real router, a real tool call through it, and the board's own client code consuming the record off `GET /usage/stream` |
| `scripts/windows/verify.ps1` | **not run by this item** — the conductor's fresh-context verify owns it |

## 8 · Named gaps, each with what it would take to close

1. **The board has not been photographed.** The session that builds it is in Session 0; the
   self-test's in-process capture is the evidence channel, and it holds the XAML tree, not Mica
   (spec-WIN3 §7 gap 1, unchanged). §12's "nothing has been rendered" note closes for this
   surface only when someone reads the captures against the palette.
2. **Live in-app behaviour with a running router** is proven by the probe lane and the headless
   tests, not by watching the window on the interactive desktop. The chain — real router bytes,
   real socket tests, real client code — is recorded in §7; the missing step is a human at the
   window, and nothing here claims otherwise.
3. **`held` is drawn and satisfiable by nothing** (§3.2). Closes if the router ever holds calls;
   the copy is already honest about the wait.

---

## 9 · Progress note — 2026-08-31, the session that finished the item

The item was built across two sessions of the same runner: the first wrote the wire library,
the tests, the board and this spec, and died before anything compiled or committed; the second
surveyed that work on disk, finished it, and gated it. This note records what actually ran.

### The gates, with their real results

| Gate | Result |
|---|---|
| `MCPRouter.Shell.Live.Tests` (`dotnet test`) | **100 passed, 1 skipped, exit 0** — the skip is §S6's live probe, skipped by name because no router was running (`no live router named by WIN5_LIVE_ROUTER - skipped, not passed`) |
| the same suite with `WIN5_LIVE_ROUTER=http://127.0.0.1:8979` | **101 passed, 0 skipped, exit 0** — against a real router started for the probe on a scratch port and scratch `MCP_ROUTER_HOME`, since killed |
| the live probe itself | the board's own `UsageStreamClient` consumed the running router end to end: the probe walked the initialize dance over plain JSON-RPC, made one real **failing** call (`nosuchserver__nope`), and asserted the record arrived **live** on `GET /usage/stream` (phase `Live`, then the decoded `CallRecord` with `err` populated) and in the `GET /usage?limit=500` backfill through the same client |
| `scripts/windows/build-shell.ps1` | **exit 0**, `MCPRouter.Shell.exe` present on disk; Restore and Build as two MSBuild invocations |
| the self-test lane (`run-shell-selftest.ps1`) | **exit 0**: 10 destinations walked, 2 appearances forced, 12 captures, no failures. `destination-activity.png` (2560×1528) holds the board drawn inside the shell with **no router running** — the offline state's draw, as §7 promised. The capture and `selftest.json` are in `planning/evidence/WIN5/` |
| the golden bytes | three captures of real router SSE on this machine, 2026-08-31 (`usage-stream-capture-1/2/3.txt`); the first two are the golden samples §7's suite row asserts verbatim; the third is the finishing session's re-run, with a successful attributed call (`client:"node"`, `pid`, `cold:true`) and the probe's failing call |

### What the finishing session changed, and why it had to

The first session's work had never been compiled. Building it measured five API mismatches,
each fixed against the platform rather than around:

1. `MCPRouter.Shell.csproj` carried no reference to `MCPRouter.Shell.Live` — the board's
   `using` resolved against nothing. Reference added.
2. `ShowDestination` still routed every destination to `BoardPlaceholder` — the seam WIN3
   left was unwired. One additive branch: `activity` draws the board, everything else keeps
   the placeholder.
3. `AccessKeyService` does not exist in WinUI 3; the same API is the string `UIElement.AccessKey`
   property the XAML attributes already use. Four call sites moved to it.
4. `PickerLocationId.Documents` is `DocumentsLibrary`; `SelectorBar` carries `SelectedItem` and
   `SelectorBarItem.IsSelected`, not `SelectedIndex`; `Grid.SetColumn` wants the
   `FrameworkElement` local rather than a `UIElement` collection lookup; `ActivityWrapPanel`
   used `Size`/`Rect` without `using Windows.Foundation`.

No test was edited; the suite was green on its first complete run (the CS1998 warning on one
existing test is the prior session's and is harmless).

### Not-run, and who owns it

- **`scripts/windows/verify.ps1`** — the conductor's fresh-context verify owns it; never run
  by this item, per the runner contract.
- **Cross-family review** (`codex`/`agy`/`grok`) — unavailable on this machine (ORCHESTRATOR,
  Windows fleet, measured); recorded as not-run, never as a pass.
- **§8 gap 1 and gap 2 stand unchanged** — the self-test capture holds the XAML tree, not Mica,
  and nothing here is a human at the window reading it against the palette.

**No deferred work.** The plan's seven slices are all on the branch; nothing was parked.
