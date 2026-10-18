# spec-WIN4 — the Windows Servers board and the Signal Path

| | |
|---|---|
| ID | WIN4 |
| Status | **Developer Review** — built on `ai/win4`, gated, not verified. A runner cannot verify its own build |
| Category | windows · new surface · the board the product exists for |
| Depends on | WIN3 ✓ (the shell this board is drawn inside) · WIN2 ✓ (DESIGN.md §11–13) · WIN18 ✓ (`scripts/windows/verify.ps1`) |
| Blocks | WIN5–WIN11, WIN13–WIN16 (the boards that inherit this item's control client) · the shell's sidebar foot readout (§7) |
| Brief | `planning/features-to-triage/WIN4-windows-servers-board-and-signal-path.md` |
| Source of layout, IA and vocabulary | `design/mcp-router-console.html` §`b-servers` (design of record, settled 2026-08-22) |
| Source of the visual language | `DESIGN.md` §11 · §12 · §13, plus §1 (the Signal Path is the signature element) and §2 (`### Signal Path geometry`) |
| Triage | 2026-08-31, by the item's own runner — the fleet's spec+plan-on-branch variant of the triage stage |
| Cross-family review | **not-run.** `codex`, `agy` and `grok` are absent on this machine (ORCHESTRATOR.md, Windows fleet). Recorded as not-run, never as a pass |

---

## 1 · What this item is

The Servers board, drawn inside WIN3's shell as the `servers` destination's own view: the board
head with its two actions, the **Signal Path** (drawn — it is not a stock control on any
platform), the held-changes band, and the table of declared servers. Under it, the first Windows
control-API client in the repository: a real loopback HTTP client that reads `GET /servers` and
`GET /harnesses`, performs `POST /servers`, and nothing else.

The board is live: it polls, it counts down, a jack lights when the router reports a child and
goes dark when the reaper closes it. Every state DESIGN.md §5 asks of a data surface is drawn
with real copy, including the two the sketch names — empty (nothing declared) and disconnected
(router unreachable).

## 2 · The question this item exists to answer

DESIGN.md §1 names the Signal Path the signature element and "the only loud thing in the app",
and §13 closes with the debt that makes it Windows-specific: **the plug's hue collides with the
user's accent on Windows** — or would, if the plug took the accent. The Mac's plug is `--live`,
the platform's own "a child process is running" hue; §12 already maps that meaning on Windows to
`SystemFillColorSuccess`. So the collision is settled by refusing the accent, not by adding a
token: **the lit plug takes `SystemFillColorSuccess`, which the platform already owns for exactly
this meaning, and the state's word — which every jack carries — is the second channel §13 asks
for.** That matters measurably: §12 measures `SystemFillColorSuccess` against
`SystemFillColorCritical` at **1.00:1 dark / 1.04:1 light**, so on Windows the word is not
decoration; it is the only channel some users have.

The second question is the sketch's own: *what does the signature element's geometry mean when
the design authority publishes it in points and Windows draws in effective pixels?* Restating it
is this item's named deliverable — §3.1 — not something to eyeball from the macOS numbers.

## 3 · The decisions

### 3.1 The Signal Path's geometry, restated for Windows

DESIGN.md §2's `### Signal Path geometry` is written in macOS points. §13 already established
the conversion convention when it carried §4's tile sizes across: **read as effective pixels,
one for one** — a point on the macOS ladder and an epx on the Windows ramp are the same
lay-out unit, and nothing else in the row moves. This item adds `### Signal Path geometry
(Windows)` to DESIGN.md §12 carrying that restatement row by row, with one deliberate
replacement and two authored complements:

- **Plug transition does not cross as 0.2s.** §13's motion table maps "a plug lighting or going
  dark" to **direct entrance, 167ms, `cubic-bezier(0, 0, 0, 1)`** on the fill and the ring, and
  the header rule gives the platform table precedence over §2's hand-set duration.
- **The jack is a 4px-radius element** (`ControlCornerRadius`), by §13's tile-radius rule: it is
  an in-page element and Windows publishes 4px for those, so §2's concentric derivation does not
  apply.
- **The off-socket tokens are authored here, with provenance.** Windows publishes no jack token.
  The socket takes `TextFillColorDisabled` as a *non-text mark* and the resting ring
  `ControlStrokeColorDefault`. Both are published values doing a stated job: an unlit socket is
  absence (the Mac's `--jack-off` is 1.45:1 light for the same reason), and the word beside the
  jack carries the state, per §12's own finding.

The lit / tripped / held hues are not choices and are not restated as ones:
`SystemFillColorSuccess` / `SystemFillColorCritical` / `SystemFillColorCaution` per §12's
indicator-hue table, `held` and `needs sign-in` sharing caution and told apart by their words,
exactly as the Mac's `JackState.indicator` does. The ring around a lit plug takes the same hue's
own published `…Background` token — `SystemFillColorSuccessBackground` and siblings — which is a
halo of the state hue rather than a second invention.

**Cross-family review of this call was not available.** Recorded as not-run in the header; the
precedent is WIN3 §3.1's identical recording.

### 3.2 The five states are the Mac's five states, from one precedence chain

The brief assumes the design of record's five states are the complete set; the Mac's
`JackState` (app/Sources/MCPRouterKit/Servers/JackPresentation.swift) is the working answer and
this item ports it rather than reinventing it — same five cases, same words (`awake`, `tripped`,
`held`, `needs sign-in`, `dormant`), same precedence, because §6's one-name-per-state rule runs
across devices:

1. `disabled` → dormant ("disabled by you" — outranks *running*, because a disabled server with a
   live child is served to nobody and the reaper is on its way)
2. `state == "running"` → **live** (the plug's one invariant: it lights only for a child that is
   up, and never stays dark for one)
3. `placard` → tripped (an index error always arrives carrying a placard, so there is no sixth
   case)
4. `pendingChange` → held (`"<n> held changes"`)
5. `auth.supported && !auth.authorized` → needs sign-in
6. otherwise → dormant (`"warm"` when `warm` is set)

The word's precedence is the plug's plus one arm: a `warm` running server reads **"never
reaped"** rather than a countdown, because the reaper skips it — a jack counting down on a warm
server while the hub counts it at rest would contradict itself on one surface. An unknown reap
horizon (`idleMs` absent) reads plain `awake`; a server past its horizon floors at `0:00`. The
countdown is `max(0, idleMs/1000 − idleSec)` — both figures the router sent — formatted
`m:ss left` (`221:00`, not a rolled hour; a horizon is minutes).

### 3.3 The table draws what the router serves, and relabels one column

The design of record's columns are Server / Transport / Tools / State / Calls 24h / Resident /
Last call. Measured against the wire (`Describe.row`):

- **"Calls 24h" is drawn as "Calls".** The router counts calls since its summary window opened —
  the envelope's `since` — and publishes no 24-hour figure. A column headed 24h over a window
  that is not 24h is a fabricated denominator, which §6 forbids twice over.
- **"Resident" is not drawn at all.** The router serves no resident-bytes figure, and the
  prototype's MB column is the exact class of invented number §6's refusals table exists for.
  The State cell correspondingly draws `Awake · 3:41 left`, never `Awake · pid 91204` — the wire
  carries no pid either.
- `Last call` renders `usage.lastUsed` as a relative time (`2 min ago`), `never` at zero calls.
- `Transport` renders `stdio`, `http`, `sse`; `stdio · OAuth` when `auth.supported` is true on a
  non-stdio row, as the mock does for pocketsmith.
- A `disabled` row draws dimmed, `Disabled by you`, per §3 rule 4's disabled surface.

### 3.4 `Reap idle` is drawn, wired, and disabled — with the measured reason

The sketch says "`Reap idle` acts". **Measured, the router serves no verb that reaps idle
children on demand**: the control path family (`ControlPaths.isControlPath`) contains no reap
route; `PATCH /servers/:name` writes exactly `projects, warm, idleMs, placard, disabled`, and
`UpstreamPoolReaping` treats `idleMs <= 0` as *disable reaping for this server* — so there is no
field whose write forces a reap either. The Mac reached the same wall and ships *Reap Idle
Children* as a `.featureUnbuilt` menu command (MenuCommand.swift line 220; DESIGN.md §8 refuses its
chord on the first limb).

So on Windows the button exists in the head, is wired to a real client method that performs the
real calls, and is **disabled with a discoverable reason** (§5 Disabled: dims in place with a
discoverable reason — the accessibility `HelpText`, WIN3's pattern, plus the head's own reason
line): the reaper runs on the router's own schedule and no route asks it to run early. **"Reap
idle acts" is recorded NOT-RUN on the wire**, with this measurement as the reason, and the
enabled path exists so the day the router serves a reap verb the button goes live without a
surface change. Emulating the act with a `disabled` PATCH round-trip was considered and refused:
two config writes to fake one operation is the fake-green class rule 5 exists for.

### 3.5 `Add server…` opens a further view, and the further view commits for real

The trailing ellipsis is load-bearing (§3 rule 4): the button opens a **ContentDialog** —
Windows' own further view — and commits nothing itself. The dialog's commit is a real
`POST /servers` with the bearer token from the router's `control.token` and JSON content type:
name, command, args (one per line, argv-style split), and — for a URL server — the URL field.
The dialog draws the router's real refusals against the form: 400 `name is required`, 409
duplicate name, 422 with the router's own `hint` — and the hint is what turns **"Add it anyway"**
on, exactly the Mac's rule: never inferred from a status code, only from a hint the router sent.
A successful add closes the dialog and the next poll (not an optimistic row) brings the server
in.

### 3.6 The Signal Path counts what the routes count

The topology line `<n> harnesses → 1 endpoint → <m> upstreams` is computed, not drawn: *n* is
the harness row count from `GET /harnesses` (M22's route, merged — the column macOS §10 defers
is drawable here because Windows has the route), the endpoint is the one router, and *m* is the
declared server count from `GET /servers`. The hub draws `:<port>` from **the port the router
answered on** — never the constant 8879 (§2's LoopbackAddress rule) — and `<n> at rest` where
*n* counts servers whose child is up and idle (`state == "running"`, `inFlight == 0`).
The harness column's dot reads the row's own `state` field: `wired-http` / `wired-shim` lit,
`wired-with-duplicates` caution, `not-wired` off, an `unreadable` harness critical — each with
the harness's display name, never hue alone.

### 3.7 Live means polled

The router publishes no server-state feed this client consumes; like the Mac's tracker, **a
timed poll is the authority for every field**. The board polls `GET /servers` every 5 seconds
(the Mac's cadence) and `GET /harnesses` alongside it; a 1-second local tick re-renders
countdowns from the last answered poll, which is interpolation between two router facts, never a
derived one. A jack lights within one poll of a real call and darkens within one poll of a reap.
The Mac's sub-second lighting comes from `/usage/stream`, which is **not built here** and is
recorded in §7. Neither source is ever extrapolated: a failing poll after a successful one is
**stale**, not empty — the reading stays on screen with a stale notice, and present-tense claims
(countdowns) freeze rather than keep ticking against a router that stopped answering.

## 4 · The state matrix

§5: each spec carries its own matrix, with real copy. The board's states, and the copy each
draws:

| State | When | What draws |
|---|---|---|
| Loading | No poll has answered yet | Skeleton matching the real Signal Path lane and table-row heights — nothing moves when data lands. "Connecting to the router…" as one quiet line |
| Empty | A poll answered; zero servers declared | "No servers adopted yet" + the design of record's explanation, + **Add one by hand…** (real — opens §3.5's dialog). The mock's *Adopt from Claude Code…* is carried, not drawn: adoption has no control route (§7) |
| Loaded | Last poll answered, servers declared | The board: head, Signal Path, held band when held rows exist, table, callout |
| Stale | An earlier poll answered; the latest failed | The last good reading stays, under a caution line: "The last refresh didn't complete — showing the reading from HH:mm:ss." Countdowns freeze |
| Disconnected | No poll has ever answered | Critical mark + **"The router isn't running"** (the Mac's `ControlAPIError.routerNotRunning` headline, §6's one wording) + "Nothing is listening on 127.0.0.1:<port>, so there is nothing to show yet." + **Try again** (real) + **Start the router**, disabled with the Mac's honest reason, ported: "MCP Router can't start the daemon itself yet. Start it the way you normally do and this fills in on its own." (WIN23 owns starting one) |
| Partial | `/servers` answered; `/harnesses` failed (or 503 no inventory source) | The table draws; the harness column carries its own failure inline — "Harnesses unavailable: <reason>" — per §5's *say what arrived and what did not* |
| Row error | A write refused | Inside the add dialog, against the form (§3.5). No toasts (§5: Windows does not toast a click either) |

Every state is addressable in the UI Automation tree with names matching the on-screen
vocabulary (WIN20's plane): the lane announces as `Signal path`, the jack grid as `Upstream
servers`, each jack as `<name>, <word>` (e.g. `obscura, awake, 3:41 left`), the topology line as
one element reading its full sentence, the table as `All servers`, each row as `<name>, <state
sentence>`.

## 5 · What is built

- `MCPRouter.Shell.Model/Servers/` — the plain-net8.0 half, so every claim is headless-testable:
  wire records transcribed from the Swift client's `Models.swift` (strict where the router is
  strict: `disabled`, `warm`, `auth`, `usage` decode non-optionally — a router that omits
  `disabled` is refused, not defaulted, per the Swift model's own comment); `ControlApiClient`
  (real `HttpClient`, loopback, bearer token read at write time from `<router home>/control.token`,
  `MCP_ROUTER_HOME` honoured); the error taxonomy with the Mac's verbatim §6 wording;
  `JackPresentation` (§3.2, ported pure functions); the board model (rows, counts, topology,
  load states).
- `MCPRouter.Shell/Views/ServersBoard.xaml(.cs)` — the board itself, mounted by `ShellWindow`
  for the `servers` destination; the other nine destinations keep their placeholders. The Signal
  Path is drawn from panels and shapes (no stock control claims it), Consolas for every numeral,
  Segoe Fluent / drawn path icons only.
- `MCPRouter.Shell.Tests/` — headless gates: wire decode against the Swift repo's recorded
  router fixtures; `JackState` precedence over the cross product; countdown formatting; topology
  counting; request-shape tests for the client (auth header, content type, force semantics)
  through an injected handler; §6 wording parity against this spec; sentence case.
- DESIGN.md §12 gains `### Signal Path geometry (Windows)` (§3.1) and §13's debt list marks the
  plug's second channel settled.

## 6 · What this item does not do

- **No inspector pane, no row selection, no Keep warm, no remove / wake / trip.** The mock's
  third region is a surface of its own; this item draws the two the brief names (the table and
  the Signal Path) and the head. `Space` stays a declared shell behaviour (WIN3's gate holds);
  wiring it to a selected row's Keep warm belongs with selection and the inspector.
- **No `/usage/stream`.** Poll-only live (§3.7).
- **No harness adoption.** The empty state's adopt action is carried: the control API serves no
  adoption route (the CLI verb is not a control route), and WIN14 owns the harnesses reading.
- **No router lifecycle.** Start/stop belongs to WIN23 (blocked). The disconnected state's start
  action is drawn disabled with the honest reason, per the Mac's own precedent.
- **The shell's sidebar foot readout stays carried.** spec-WIN3 §3.5 named its carrier "the item
  that lands the Windows control client"; this item lands the board's client, not the shell's
  readout, and does not reach into the shell's chrome to take it. It is still owed, and the
  plumbing this item lands (envelope port, running count) is most of its data.

## 7 · Named gaps, each with what it would take to close

1. **`Reap idle` does not act on the wire** — §3.4. Closes when the router serves a reap verb;
   the client method and the button's enabled path exist for that day.
2. **Sub-second jack lighting** — needs `/usage/stream` (SSE) consumed between polls. Real
   route; a client-side event stream is its own slice.
3. **The inspector, selection, Keep warm, remove/wake/trip** — §6. One slice, mock region three,
   `GET /servers/:name/changes` already decoded for the held band.
4. **Nothing has been photographed against a running router.** The self-test exercises the board
   in-process and, with no router able to run on this machine (WIN23 blocked), captures the
   disconnected state — a real state, and the only one a capture here can honestly hold. The
   connected board is witnessed by the headless gates and the build, not by a capture.
5. **Increased contrast / High Contrast** is unmeasured, as §11 records for the whole Windows
   floor.

---

## Progress — built on `ai/win4`, stopped before verify (2026-08-31)

Everything in §5 was built. The build, the headless gates and the in-process self-test are green;
the live-router evidence is stronger than §7 gap 4 anticipated — **a reference (TypeScript) router
was already running on this machine at 127.0.0.1:8879**, so the board's connected states are
measured against a live router, and the signature claim is photographed end to end.

### Gates actually run (exit codes are the evidence)

| Gate | Command | Result |
|---|---|---|
| Model + gates | `dotnet test app/windows/MCPRouter.Shell.Tests/…csproj` | **exit 0 — 226/0** (incl. WIN3's pre-existing suite, unmodified) |
| WinUI build | MSBuild.exe `-t:Restore` then `-t:Build` (separate calls) | **exit 0 / exit 0**, `MCPRouter.Shell.exe` verified on disk |
| Self-test | `scripts/windows/run-shell-selftest.ps1` | **exit 0 ×3** — 10 destinations, 12 captures, no failures |
| Live-call probe | `planning/evidence/WIN4/light-a-jack.ps1` | **exit 0** — real `tools/call fixture__echo` over `/mcp` at 21:42:43; `state=idle → running` observed |
| Reaper watch | 1s poll of `GET /servers` | **child reaped at 21:47:47** (the 300s horizon); `running → idle` observed |
| Cross-family review | — | **not-run** — `codex`/`agy`/`grok` absent on this machine. Never a pass |

### The brief's clauses, each with what witnesses it

| Clause | Status | Witness |
|---|---|---|
| Live states; changes without manual refresh | **measured** | 5s poll; state flipped `idle→running→idle` across polls with no user action (probe output, reap watch) |
| Five states draw distinctly, not hue alone | **measured** (live: awake, dormant; fixture-driven: tripped/held/needs-sign-in at the unit boundary + recorded fixtures) | `JackStateTests` cross product; every jack and row carries its word; hue pairs at 1.00:1 never stand alone |
| Jack lights on a real call, darkens on reap | **measured, photographed** | `captures/jack-lit-real-call.png` (green plug, "3:50 left", hub "1 at rest", row "Awake · 3:50 left") · `captures/jack-darkened-after-reap.png` |
| Countdowns tick and are legible; at-rest reads at rest | **measured** | 3:50 = exact `max(0, 300 − idleSec)` from the router's own figures; 1s tick re-renders words only |
| `Reap idle` acts | **NOT-RUN on the wire** — §3.4's measurement stands: no reap verb exists on any platform; button drawn, wired, disabled with the discoverable reason | `ControlPaths.isControlPath` family + `PATCH`'s five fields + `UpstreamPoolReaping` (idleMs ≤ 0 *disables* reaping) + the Mac's own `.featureUnbuilt` ruling. The reason itself is witnessed on every channel §3.4 names — accessibility `HelpText` and a tooltip on the button, and the head's own reason line — all carrying `ServersCopy.ReapIdleReason`, gated by `ReapReasonTests` (source-text) and the sentence-case suite |
| `Add server…` opens a further view; ellipsis load-bearing | **built, verified at the boundary** | Real ContentDialog → `POST /servers` with bearer token; 400/409/422 shapes and the hint→"Add it anyway" rule gated in `ControlApiClientTests`. **Not exercised against the live router on purpose** — a successful POST is an irreversible write to the user's real `servers.json` |
| Empty + disconnected states draw | **disconnected: not photographed on this machine** — the reference router stayed up; the state machine is gated (`Render()` truth table + §6 wording parity tests). Empty likewise unit-gated | `ControlApiClientTests`, `ServersCopyTests`; the shell walks the board every self-test run |
| Signal Path geometry restated in the design authority | **done** | DESIGN.md §12 `### Signal Path geometry (Windows)`; §13's plug-debt entry marked settled |

### Parked (each with its reason)

- **Harness column against a router that serves the route.** The running router is the
  TypeScript reference, which answers `GET /harnesses` 404 (the route is the Swift daemon's
  M22 divergence). The partial state drew for real, twice — "Harnesses unavailable: not found;
  MCP endpoint is /mcp" is the router's own body — but the wired-harness lane drawing awaits a
  router that serves it.
- **The lane's first-render packing** was wrong twice against the live board (cells narrower
  than the jack's minimum, neighbour-clipped) and is now packed from `JackGrid.ActualWidth`
  with a `SizeChanged` re-pack; both captures above are post-fix.
- **§12's plug transition was never recorded here** — the build shipped a comment deferring it
  to "the platform's own state transitions", which animates nothing on a `Fill` swap, and the
  first verification called the silence. Resolved 2026-08-31, not parked: implemented for real
  (see the gap-fix section below).

### Evidence on disk

`planning/evidence/WIN4/light-a-jack.ps1` (the probe) and `captures/` — connected-dormant,
jack-lit-real-call, jack-darkened-after-reap, forced-light (the element-scoped theme-brush
resolution proven against the self-test's forced Light). Captures are `RenderTargetBitmap`s of
the XAML tree; they do not hold Mica or the system caption buttons.

### Gap fix — closing the first verification's findings (2026-08-31)

The first fresh-context verification returned NEEDS-WORK with three findings. Each, and what it
got:

1. **The Reap idle reason was never discoverable** — `ServersCopy.ReapIdleReason` existed and
   passed its sentence-case test, but nothing attached it. Fixed on both channels §3.4 names,
   the way the disconnected state's `StartButton` already carries its own: the accessibility
   `HelpText` (WIN3's pattern) and a tooltip on `ReapButton`, and the head's own reason line
   beside the dimmed action. One wording carries all three, so the sentence-case gate covers
   them together. Gated by the new `ReapReasonTests` (source-text) — the wiring, not the
   wording, was what had been missing.
2. **§12's 167 ms `cubic-bezier(0, 0, 0, 1)` plug transition was not implemented** — the old
   comment deferred to state transitions the platform does not animate on a `Fill` swap, and
   `RenderJacks` rebuilds the jack field every poll, so no element-lived transition could fire.
   Implemented for real on the fill and the ring: each plug's previous tones are kept per
   server, so a state change carries the crossing across a rebuild onto the fresh element, and
   a plug's first tones are set directly — a first colour is not a change. The curve itself is
   exact, not an approximation: this WinUI projection ships no `BezierEase`, so the crossing is
   drawn as a spline key frame, and a `KeySpline` takes the same two control points
   cubic-bezier does — (0,0)–(0,1) is §13's direct-entrance ease. The crossing holds under
   `UISettings.AnimationsEnabled`, §13's own reduced-motion mapping. Which token each state
   takes moved to `JackPresentation.PlugTokens` in Shell.Model (finding 3's enabler).
3. **The plug-accent refusal had no Windows gate** — a one-line regression in the view would
   have shipped green. The state→brush decision now lives in Shell.Model as a pure function
   returning brush *tokens*, and the view consumes it; `PlugTokenTests` gate the token mapping
   (live → `SystemFillColorSuccess`, every state swept for never-accent), and a source-text
   gate asserts `ServersBoard.xaml.cs` never assigns an Accent brush to any fill or stroke.
   The add action's accent-filled button is style-level and untouched; §13's debt is about
   fills and strokes.

Gates after the fix, exit codes the evidence: `dotnet test` **exit 0 — 236/0** (226 unmodified
plus the ten new gates); MSBuild `-t:Restore` then `-t:Build`, separate calls, **exit 0 / exit
0**, `MCPRouter.Shell.exe` fresh on disk; `run-shell-selftest.ps1` **exit 0** — 10 destinations,
2 appearances, 12 captures, no failures. Cross-family review remains **not-run** — `codex`,
`agy` and `grok` are absent on this machine.
