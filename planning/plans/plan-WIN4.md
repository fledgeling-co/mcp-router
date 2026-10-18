# plan-WIN4 — the Windows Servers board and the Signal Path

**Spec:** `planning/specs/spec-WIN4.md`
**Brief:** `planning/features-to-triage/WIN4-windows-servers-board-and-signal-path.md`
**Design of record:** `design/mcp-router-console.html` §`b-servers` (layout, vocabulary, states)
· `DESIGN.md` §1, §2 (`### Signal Path geometry`), §5, §6, §11–13 (the Windows floor and the
Windows arms this item owes)
**Branch:** `ai/win4` · **Worktree:** `.worktrees/WIN4`
**Tier:** Large.
**Base:** the WIN3 shell, merged — `ShowDestination` mounts `BoardPlaceholder` for every
destination today (`app/windows/MCPRouter.Shell/Shell/ShellWindow.xaml.cs:318`).

Deliver what is planned below, at the scope stated. Anything that survives a routine judgement
call goes in the progress note as a parked item with its reason.

---

## 1 · Slices, in dependency order

### S1 · The design authority first

DESIGN.md §12 gains `### Signal Path geometry (Windows)` — the macOS table restated in effective
pixels per §13's tile-size convention, the plug transition replaced by §13's 167ms direct
entrance, the jack's 4px radius, and the two authored off-socket tokens with provenance. §13's
"What the Windows floor still owes" marks the plug's second channel settled, pointing at the new
block.

**Why first:** the board's geometry must be read out of the authority, not out of the code that
is about to be written — the same order WIN2's item ran in, and the reason `no-raw-design-values`
exists on the Mac.

### S2 · The wire, as records

`MCPRouter.Shell.Model/Servers/ServersWire.cs` — `System.Text.Json` records transcribed from
`app/Sources/MCPRouterKit/Control/Models.swift`:

- `ServersEnvelope` (`port`, `idleMs`, `since`, `pendingAuth?`, `servers[]`) and `ServerRow`
  (`name, transport, state, inFlight, callsServed, idleSec`, transport-conditional members,
  `hash, tools, toolNames, indexedAt?, indexError?, projects, warm, disabled, placard?,
  pendingChange?, auth, usage`).
- Strictness where the router is strict: `disabled`, `warm`, `auth`, `usage` are **required** —
  a response missing them fails the decode rather than defaulting, per the Swift model's own
  comment on `disabled`.
- `HarnessesEnvelope` (`port, scope, readAt, harnesses[]`) and `HarnessRow` per
  `HarnessReportJSON.swift`, `unreadable` nullable.

### S3 · The client, as a real boundary

`MCPRouter.Shell.Model/Servers/ControlApiClient.cs`:

- Real `HttpClient` over `http://127.0.0.1:8879` (overridable); 3-second timeout; GET ungated,
  exactly the router's own gate.
- `GetServersAsync`, `GetHarnessesAsync`, `GetChangesAsync(name)`, `AddServerAsync(body, force)`.
- Writes read the bearer token at call time from `<router home>/control.token`
  (`MCP_ROUTER_HOME` env override, else `%USERPROFILE%\.claude\mcp-router`), send
  `Authorization: Bearer …` and `Content-Type: application/json`. **The token is never logged,
  never echoed, never embedded in an exception message.**
- Errors as `ControlApiException` carrying the Mac's taxonomy and §6 wording verbatim:
  `RouterNotRunning` (connection refused / socket absent), `Unauthorized` (401),
  `MalformedResponse`, `Server(status, message, hint)`, `Transport(detail)`. Headline / advice
  / action strings ported from `ControlAPIClient.swift` — one wording per state across devices.
- The base address and the token path are constructor seams; tests inject an `HttpMessageHandler`
  — a seam, not a product stub.

### S4 · The presentation, as pure functions

`MCPRouter.Shell.Model/Servers/JackPresentation.cs` — the port of `JackPresentation.swift`:

- `JackState { Live, Tripped, Held, NeedsSignIn, Dormant }`, `ForServer(row)` with §3.2's
  precedence chain (disabled → running → placard → pendingChange → auth → dormant).
- `JackCondition.ForServer(row, idleMs?)` — the word/contracted pair, `never reaped` on warm
  live, `awake` with no horizon, `m:ss left` otherwise, floor 0.
- `ReapSeconds(row, idleMs) == max(0, idleMs/1000 − row.IdleSec)`.
- `ServersBoardModel.cs` — rows in router order (never sorted), the at-rest count
  (`running && inFlight == 0`), the topology line's three counts, load states
  `Loading / Loaded / Stale / Failed`, and the harness-dot mapping of §3.6.

### S5 · The gates, red before the view exists

`MCPRouter.Shell.Tests/` — xunit, headless, reading the recorded router fixtures the Swift repo
already carries (`app/Sources/MCPRouterKit/Control/Fixtures/`) as the decode oracle:

| Fixture | What it holds |
|---|---|
| `servers.json`, `server-stdio.json`, `server-http.json`, `server-tools.json` | the envelope and the row shapes, including `cwd`-absent vs null |
| `server-placarded.json`, `server-pending-change.json`, `servers-pending-auth.json` | placard / pendingChange / pendingAuth decode |
| `changes-pending.json`, `patch-response.json`, `added.json`, `add-refused.json`, `unauthorized.json` | the write-path shapes and the `{error, hint}` refusal |

New fixtures: `JackStateTests` over the cross product of the precedence inputs; countdown
formatting (`3:41`, `221:00`, floor, no-horizon, warm); topology counts; the at-rest count;
request-shape tests (URL, method, auth header present on POST and absent on GET, JSON content
type, `?force=1` only when forced, token never in the exception text); §6 wording parity against
spec-WIN4 §4's table; sentence case over every new user-visible string.

### S6 · The board

`MCPRouter.Shell/Views/ServersBoard.xaml(.cs)`:

- **Head** — title, the design of record's sentence, `Reap idle` (disabled, reason per §3.4),
  `Add server…` (the view's one accent-filled action, §11 rule 4).
- **Signal Path** — drawn: harness column (real rows, dot per §3.6, `readAt` staleness
  respected), drawn flow arrows (`PathIcon`, not a gambled codepoint), the hub (`Router`,
  `:<answered port>`, `<n> at rest`, Consolas), the jack field as an adaptive wrap grid —
  132px minimum jack, 44px lane, 16px plug + 3px ring, 4px radius, plug transition 167ms
  `cubic-bezier(0,0,0,1)` on fill and ring. Jack invocation selects the matching table row and
  brings it into view (the mock shares selection between jack and row; there is no inspector to
  open — recorded gap 3).
- **Held band** — drawn when any row carries `pendingChange`, real counts and server name,
  `Review changes…` opening a real dialog over `GET /servers/:name/changes` (kind + tool name +
  invisible-codepoint note per change).
- **Table** — `All servers`, columns Server / Transport / Tools / State / Calls / Last call per
  §3.3; fixed row height (56px, the 8px grid's multiple; the loading skeleton matches it
  exactly); `TextTrimming.CharacterEllipsis` everywhere; disabled rows dimmed with the reason in
  the state cell.
- **States** — §4's matrix, all seven, real copy.
- **Automation** — every name from §4's plane list; the lane announces as `Signal path`, the
  grid as `Upstream servers`, jacks as `<name>, <word>`.
- **Timers** — 5s poll (`DispatcherTimer`, async guard against overlap), 1s countdown tick,
  both stopped when the board unloads.

### S7 · The mount, and the shell's own gates

`ShellWindow.ShowDestination` mounts `ServersBoard` for `servers`, placeholder for the other
nine. WIN3's gates must all still pass unchanged — including `DesignKeyboardParityTests` (no new
chord is bound) and the self-test contract (title, band, capture ≥200px for every destination).
The self-test's servers capture will show the disconnected board, which is the true state of a
machine where no router can run.

---

## 2 · Test strategy

**What can be proved on this machine:** the build (two MSBuild invocations, artifact judged on
disk), every headless gate in S5, and the self-test's JSON/PNGs over the disconnected board.

**What cannot:** the connected board in motion — no router binary runs on Windows (WIN23
blocked), so a jack lighting on a real call and darkening on a reap is witnessed at the unit
boundary (state transitions driven by real recorded payloads, and by poll responses the injected
handler scripts) and **not** by a live capture. Recorded as such, never implied by a green unit.

**What is never done:** no test is edited to pass, no ratchet raised, no gate that cannot run
reported as anything but not-run. `make lint` / `make test` do not exist here and are never
reported green.

---

## 3 · Order of work

S1 → S2 → S3 → S4 → S5 (red first, against nothing) → S6 → S7 → build + dotnet test +
self-test → the progress note on the spec.
