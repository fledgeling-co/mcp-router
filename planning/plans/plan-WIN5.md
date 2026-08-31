# plan-WIN5 — the Windows Activity board

**Spec:** `planning/specs/spec-WIN5.md`
**Brief:** `planning/features-to-triage/WIN5-windows-activity-board.md`
**Mock:** `design/mcp-router-console.html` §ACTIVITY — WHAT · **Windows floor:** `DESIGN.md` §11–13 — HOW
**Branch:** `ai/win5` · **Worktree:** `.worktrees/WIN5`
**Tier:** Standard.
**Base:** `main` at `22d7abf6`.

Deliver what is planned below, at the scope stated. Anything that survives a routine judgement
call goes in the progress note as a parked item with its reason. **Stop before verify and
merge** — the conductor owns both.

---

## 1 · Slices, in dependency order

### S1 · The wire types and the formatting, headless-first

`MCPRouter.Shell.Live` — plain `net8.0`, no WinUI reference, so every claim about the wire is
testable without a display (the same reasoning that split `MCPRouter.Shell.Model` out in WIN3).

- `CallRecord` — the wire type, verbatim against `src/usage.ts`: `ts, server, tool, ok, ms,
  cold, pid?, cwd?, project?, client?, err?`. Id is `ts|server|tool|pid` — the Mac's
  de-duplication key, because the stream and the backfill overlap by construction.
- `CallResult` — the classification of §3.2: `Ok`, `Timeout`, `Failed`, `Held`, decided from
  `ok` and `err`, never from `ms`.
- `ActivityFormatting` — duration words (`612 ms`, `1.94 s`, `30.0 s`, `—`), time-of-day
  (`HH:mm:ss` local from the ISO `ts`), the paste-string `server__tool`, harness display names
  (`claude` → `Claude Code`; unknown renders as itself; no client → `Unattributed`).

### S2 · The SSE client — the real boundary

`UsageStreamClient` over `HttpClient` against `http://127.0.0.1:8879`:

- line-based SSE: `:` prefix is a comment (the `: connected` greeting and the 25 s `: ping`
  both land here and are skipped, never decoded); `data:` carries one JSON record; one record
  that fails to decode is skipped and counted, not thrown — a single malformed record must not
  masquerade as the router going away.
- `ReconnectPolicy`: initial 500 ms, ceiling 30 s, 6 attempts, 5 s minimum-healthy duration
  (the Mac's measured values, kept so a greeting-and-instant-drop loop cannot reset the
  failure count). Emits `StreamEvent` — `Record(CallRecord)` and `Phase(Live/Reconnecting/
  Disconnected)` — as `IAsyncEnumerable<StreamEvent>`.
- `UsageSnapshot` — `GET /usage?limit=500` decode: `since` + records, newest first.

**Gate:** headless xunit against a **real loopback SSE server** (`HttpListener`) — greeting,
comments, records, malformed-record skip, phase events, reconnect delays, disconnect. Plus
golden bytes captured from a real router on this machine (S6), asserted verbatim.

### S3 · The model — window, pause, filters, tallies

`ActivityModel`, single-threaded (the UI thread; the client's events are marshalled to it):

- window of 500 matching the router's ring; `Prepend(record)` dedups by id, drops past the
  cap, returns whether anything changed;
- **pause**: `Paused` stops view invalidation, never ingestion; `RecordsWhilePaused` counts
  what was actually held; resume applies the window as it now stands;
- result filters: `All / Errors / Slow (over 2 s) / Held` as predicates over the window
  (§3.4); harness toggles compose with them; tallies count per harness under the result
  filter alone;
- `Phase` carries the stream state the subtitle and banners draw.

**Gate:** xunit — dedup, cap, pause-no-drop under a burst, each filter's predicate, tally
agreement with rows, filter-to-nothing detection.

### S4 · The copy

`ActivityCopy` — every sentence of spec §4 as named data, with the words the Mac authored
carried verbatim and the ones this build re-authors marked in comments. Sentence case
throughout (§11 rule 2 — no menu-bar carve-out on Windows).

**Gate:** xunit — every string is sentence-case; no sentence contains a figure no wire field
supports (the §6 honesty sweep); the held and offline wordings are the spec's.

### S5 · The surface

`MCPRouter.Shell/Views/ActivityBoard.xaml(.cs)`, wired into `ShellWindow.ShowDestination` by
one additive branch (`activity` → the board, everything else → placeholder — the seam WIN3
left, and the same seam every board lands on):

- CommandBar head: `Pause`/`Resume` (one control, label and automation name flip with state),
  `Export…`;
- `SelectorBar` with the four filter words; a wrap panel of harness toggle buttons beneath it,
  each labelled `Name · count`;
- a virtualized `ListView` of rows — Time, Harness, Tool, Duration, Result — fixed row height,
  Consolas on the three instrument columns, `TextFillColorSecondary` on Time, truncation with
  tooltip + full automation name;
- result cell: the word beside an 8 px mark in `SystemFillColorSuccess` / `…Critical` /
  `…Caution`, never hue alone (§12);
- the states of spec §4 as one exhaustive switch: loading skeleton at the true row geometry,
  empty with the mock's action (real navigation to Harnesses), offline, partial banner,
  disconnected banner + Reconnect, filtered-to-nothing, populated;
- every control carries `AutomationProperties.Name` matching its on-screen word and an
  `AutomationProperties.AutomationId` unique on the board (WIN20's plane);
- `Export…` opens a `ContentDialog` (JSON lines / CSV radio pair), then the real
  `FileSavePicker` initialised with the window handle; `Export` leftmost accent,
  `Cancel` rightmost (§11 rule 4);
- stream lifetime scoped to the board's presence: navigating away cancels the feed; returning
  reconnects and re-reads (the Mac's session-scoped `.task`, restated).

### S6 · The live probe — real router, real record, real client

On this machine, where node v26 exists:

1. build the router (`tsc -p tsconfig.json` via `node_modules/.bin`);
2. start it with a scratch `MCP_ROUTER_HOME` and the fixture stdio server
   (`scripts/fixtures/mcp-fixture-server.mjs`) declared;
3. call a tool through it (`scripts/fixtures/call-through-router.mjs`) so a real
   `UsageRecord` exists;
4. capture the SSE bytes `GET /usage/stream` actually writes — these become the golden sample
   S2 asserts against;
5. run the S2 test suite with a live-router flag set so the same client code consumes the
   **running router's** stream and backfill end to end.

**Gate:** captured bytes on disk + a green test run that names the live router in its output.
If any step fails, record exactly what and why — never as a pass.

### S7 · Build and self-test

`scripts/windows/build-shell.ps1` — Restore then Build, two invocations, artefact on disk.
The shell's own `--selftest` walks the activity destination with no router running, which
exercises the offline state's draw.

**Gate:** exit 0 and `MCPRouter.Shell.exe` present; self-test JSON recorded if the
interactive-task lane is available to this session — recorded not-run otherwise.

---

## 2 · Test strategy

**What can be proved on this machine:** the build; every wire and model claim (S2, S3, S4 —
headless, real sockets); the board draws (self-test capture lane); the live loop from router
call to parsed record (S6).

**What cannot:** how the board *looks* against the palette (Session 0; spec §8), and the
`verify.ps1` lane (conductor-owned; never run here).

**What is never done:** no test is edited to pass, no stub sits where the real client belongs,
and no gate that cannot run here is reported as anything but not-run.

---

## 3 · Order of work

S1 → S2 → S3 → S4 (gates red first where a test can be written first) → S5 → S6 → S7 → the
progress note on the spec.

S2's golden sample comes from S6's router, so S6's capture steps run as soon as the client's
wire types exist, and the probe re-runs end-to-end after S5.
