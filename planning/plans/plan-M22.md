# plan-M22 — the Harnesses and Insights boards, and the route behind them

**Spec:** `planning/specs/spec-M22.md`
**Brief:** `planning/features-to-triage/M22-harnesses-and-insights-boards.md`
**Design of record:** `design/mcp-router-console.html` — settled 2026-08-22. Not `design/mocks/prototype.html`.
**Branch:** `ai/m22` · **Worktree:** `.worktrees/M22`
**Tier:** Large.
**Base:** `main` at `87e16dc`.

Deliver what is planned below, at the scope stated. Routine judgement calls are made here and
recorded; anything that survives goes in the progress note as a parked item with its reason.

---

## 1 · What this item is

Two new boards and the router-side reporting they read. It absorbs `R7-C1`, because
`scripts/lint/no-raw-design-values.sh` A36 forbids anything under `Boards/` from touching
`FileManager`, `Data(contentsOf:)`, `URL(fileURLWithPath:)`, `Bundle`, `Process(` or a socket —
so a Harnesses board cannot read a harness config itself, and the route is not optional.

Three layers, in dependency order:

1. **Router** — `GET /harnesses` and `GET /insights` on the control API, plus the two pieces of
   observation neither had: resident memory crossing the wire, and per-server alive-time.
2. **Kit** — the wire types, the client operations, the fixtures, and the copy that belongs to
   each reading.
3. **UI** — `HarnessesBoard`, `InsightsBoard`, two destinations, two View items, two shortcuts.

---

## 2 · The decisions, and what each beat

### 2.1 The four readings are `HarnessState`'s four, not a fifth

Triage §3.3 read the fourth reading — *routed but still declaring direct upstreams* — as new
modelling. It is not. `RouterCore/Discovery/HarnessReconciliation.swift` already carries
`HarnessState` with exactly four cases and its doc comment names the brief: *"The brief's four
answers, derived from the report rather than stored… the route survives inside the duplicate
case."* `.wiredWithDuplicates(route:count:)` fires when a harness is wired **and** declares
entries the router already fronts, which is the reading the brief's finding sentence is about.

**What this loses, stated rather than discovered:** a harness wired over HTTP that declares eight
servers the router does *not* front reads `.wiredViaHTTP`. Nothing is hidden — the row carries
`entries` beside the reading — but the reading itself does not name it. Beaten alternative: a
fifth case, or widening case three to `wired && entries > 0`, which would relabel every
already-correct HTTP harness that happens to keep one unrelated server.

The Swift enum on the app side is `HarnessReading`, closed, four cases, decoded from a closed
string set so a fifth transport fails decoding rather than defaulting (`SWIFT_PRACTICES.md` §2).
The sentence for each reading lives on the case in `HarnessPresentation`, never at a call site.

### 2.2 The harness version is not shipped, and that is a parked row

The brief asks for *"its config path and version"*. Nothing in this repository observes a harness
version. `HTTPCapability.known(for:)` carries strings like `codex 0.146.0`, but those are the
binary **a probe was taken against in August 2026**, not a reading of this machine — rendering one
as "version" would be a claim about the user's install that nothing measured, which `DESIGN.md` §6
forbids. Getting it honestly means spawning each harness binary with `--version`, which is a
process per harness on every board refresh.

Rows carry name and config path. Version is parked as a child with that reason.

### 2.3 Insights counts what the log holds, over a fixed 24 hours

The mock draws a `Last 7 days` pop-up. The usage log rotates at 8 MiB keeping one generation, so
the window a router can answer for is whatever the log reaches back to — offering 7 days on a
machine whose log holds two would be a control that lies about its own range.

So: a fixed 24-hour window, and the response carries `logHorizon` — the oldest record actually
read — so the board can say what it covered and render the brief's *"too little history"* empty
state from a measurement rather than a guess. The pop-up is parked with the durable store it
needs.

### 2.4 Duty cycle is measured over the router's uptime, in the pool

`UpstreamPoolReaping.reap` already computes `aliveMs = now - handle.startedAtMilliseconds` and
logs it as `closing idle child "x" after N call(s), Ms alive`. The quantity exists; nothing keeps
it. The pool now accumulates it per server and adds the currently-open handle's elapsed time, over
a denominator of the pool's own uptime.

Beaten alternative: a durable lifetime log covering a rolling 24 hours to match the calls window.
That is a second JSONL in the router home, and the parity lanes diff that directory; a new file
there is a risk this item does not need to take for a chart whose caption already states its
window. Parked as a child.

Explicitly refused: deriving alive-time from the call log by assuming a child lives `idleMs` past
its last call. That is modelling, and the brief's rule is that no number here is modelled.

### 2.5 The duty-cycle caption states the mechanism, never a figure

The brief's caption — *"before the router, every one of these sat at 100%"* — is a number about a
world the router never ran, which `DESIGN.md` §6 and `ORCHESTRATOR.md` both forbid, two paragraphs
before the brief says no number here is modelled. Triage recorded this as an accepted amendment.

The shipped caption: *"The share of wall-clock time each child was alive, since the router
started. A server a harness starts for itself has no reaper, so it stays alive for the whole
session."* Mechanism, no percentage.

### 2.6 Calls by harness: attribution has a provenance, like `HTTPCapability`

`UsageRecord.client` is the peer process's executable name, resolved by `LibProcPeerResolver`
through `proc_name`. Turning that into a harness name is a *naming* claim, and this repository
already has the pattern for one: `HTTPCapability` puts the provenance in the case.

Measured on this machine on 2026-08-22 with `file $(command -v …)`:

| Harness | Executable | Reading |
|---|---|---|
| Claude Code | `claude` | Mach-O arm64 — the process name is the harness's own |
| Codex CLI · ChatGPT CLI | `codex` | Mach-O arm64, and **two** harness entries share it |
| Gemini CLI | `agy` | Mach-O arm64 |
| grok | `grok` | Mach-O arm64 |
| Cursor | `node` | a bash wrapper that `exec`s a bundled `node` |
| opencode | `node` | a `#!/…/node` script |
| Claude Desktop | — | not probed |

So `ClientProcessName` has three cases — `measured(name:probe:on:)`, `ambiguous(name:reason:)`,
`unknown` — and a row whose name is ambiguous or unknown reports **no count at all** rather than a
zero, because a zero is a measurement and an absence is not (spec §2). A harness that is
`.measured` and never appeared reports `0`, which is the brief's finding: *a harness at zero is
one still using its own servers.*

A shim's calls arrive under the bridge process. `grok` reaching the router through `mcp-remote`
appears as `node`, so its row reads *not attributable* with that reason rather than a false zero.

Every observed client name that matches no harness is summed into one `other` row, so the bars
reconcile against the headline total instead of quietly losing calls.

### 2.7 Both routes are declared divergences, not control rows

`scripts/acceptance/parity-manifest-check.sh` derives the `control` group from `src/control.ts` in
**both** directions, so a `control` row for a route the reference does not answer is a red. These
are Swift-only surface: the reference answers `404 {"error":"not found; MCP endpoint is /mcp"}`
and this router answers 200. That is exactly what the `divergence` group is for, it is observable
on the wire at both binaries, and `scripts/acceptance/parity-divergence.sh` is the lane that
drives it.

Two rows, `div-m22-harnesses` and `div-m22-insights`, `# rows:` moves 92 → 94, and
`PARITY_CUTOVER_TARGET` in `parity-gate.sh` moves with it in the same commit — the check prints
the disagreement rather than re-deriving a target.

### 2.8 Two destinations, and the digits follow the sidebar

`Destination.allCases` is declaration order and `MenuCommand.allCases` derives the View items from
it, so the enum order must stay group-contiguous or
`ShellDestinationTests.groupsPartitionTheOrder` fails. `.harnesses` is inserted after `.skills`
(Running) and `.insights` after `.cleanup` (Library).

Digits are renumbered so ⌘n matches the nth row: `harnesses` takes 4 and Discover/Inbox/Checks/
Cleanup shift to 5–8, `insights` takes 9. Leaving the old digits would print a View menu reading
⌘1 ⌘2 ⌘3 ⌘8 ⌘4 ⌘5 ⌘6 ⌘7 ⌘9. `planning/specs/spec-M1.md`'s inventory table is the oracle
`MenuCommandTests` parses, so it moves in the same change, and so does A11's group membership.

The mock's four-group sidebar (Store · Routing · Maintenance · Attention) is **not** adopted.
The spec's owner-facing preview says two rows appear and the count goes from seven to nine; a
regroup is a different change. `Destination.swift`'s comment anticipating it is answered in the
progress note rather than acted on.

### 2.9 The mock's `Skill and server use, by version` table is out

It keys runs on the version of a skill or server that was live when the call ran. Nothing records
that: `UsageRecord` carries `server`, `tool`, `ok`, `ms`, `cold` and the caller, and no version
anywhere. It is not in the brief's four visualisations. Parked with that reason.

---

## 3 · Wire shapes

### `GET /harnesses`

Encoded through `JSONValue`/`JSStringify`, never `Codable` — `scripts/lint/no-wire-codable.sh`
scans `RouterCore/Control`. The member set is `HarnessesVerb.json`'s, extracted to
`RouterCore/Discovery/HarnessReportJSON.swift` so the CLI verb and the route cannot drift, plus
four additive members the board needs (`displayName`, `bridge`, `capability`, and the envelope's
`readAt`). `scripts/acceptance/r7-harness-reconciliation.sh` reads named fields, so additive
members do not move it.

```
{ "port": n, "scope": "global", "readAt": iso,
  "harnesses": [ { "harness", "displayName", "path", "exists", "unreadable",
                   "state", "route", "bridge", "entries", "duplicateCount",
                   "duplicates": [{harnessName, routerName, basis}],
                   "unparsed": [string], "httpCapability", "capability" } ] }
```

`unreadable` is read before `state`, for the reason `HarnessesVerb` already documents: an
unreadable config reaches the encoder as an empty report, so `state` says `not-wired` and the
counts say 0 — the same bytes a clean unwired harness produces.

### `GET /insights`

```
{ "generatedAt": iso, "windowHours": 24, "windowStart": iso, "logHorizon": iso|null,
  "children": { "alive": n, "declared": n },
  "resident": { "megabytes": n, "children": n } | null,
  "calls": { "total": n, "failed": n },
  "callsByHarness": [ { "harness", "displayName", "calls": n|null, "reason": string|null } ],
  "callsPerHour": [ { "hourStart": iso, "calls": n } ]        // 24 buckets, oldest first
  "dutyCycle": { "uptimeSeconds": n, "servers": [ { "server", "aliveSeconds": n } ] },
  "analyst": null }
```

`analyst` is `null` and stays that way: `PRD.md` §6 specifies a session analyst and nothing in
`app/Sources` implements one (triage §3.6). The board draws its empty state, which is what the
brief asks for — *its own configuration and its last run* — rather than absorbing §6.

`resident` is `null` when no child has a process, matching `residentMb()`, which omits an upstream
with no process rather than reporting a zero nobody measured.

---

## 4 · File map

### Router

| File | What |
|---|---|
| `RouterCore/Discovery/HarnessReportJSON.swift` | new — the shared encoder; `HarnessesVerb.json` becomes a caller |
| `RouterCore/Discovery/ClientProcessName.swift` | new — §2.6's table with its provenance |
| `RouterCore/Control/ControlHarnesses.swift` | new — the route. **Its own file**: `no-harness-config-writes.sh` rule 2 fails any file that names `HarnessReport` and also writes, and `ControlHandler.swift` writes `servers.json` |
| `RouterCore/Control/ControlInsights.swift` | new — the route |
| `RouterCore/Control/ControlPorts.swift` | `InsightsSource` port + two optional `ControlDeps` fields |
| `RouterCore/Control/ControlToken.swift` | `isControlPath` admits `/harnesses` and `/insights`, exact-match only |
| `RouterCore/Control/ControlHandler.swift` | two dispatch lines |
| `RouterCore/Usage/UsageInsights.swift` | new — windowed scan of the call log: per-hour buckets, per-client totals, failures, horizon |
| `RouterCore/Pool/UpstreamPool.swift`, `UpstreamPoolReaping.swift` | accumulate per-server alive-time; `dutyCycle()` |
| `RouterCore/Service/ServicePorts.swift` | `PoolInsightsPort` |
| `RouterCore/Service/RouterServiceDispatch.swift` | supply the two deps |

### Kit

`Control/HarnessModels.swift`, `Control/InsightsModels.swift`, `Harnesses/HarnessPresentation.swift`,
`Insights/InsightsPresentation.swift`, `Control/HarnessFixtures.swift`,
`Control/InsightsFixtures.swift`, plus `ControlAPIClient` / `LiveControlAPIClient` /
`FixtureControlAPIClient` and `Shell/Destination.swift`.

Fixtures are **authored Swift**, like `SkillFixtures`, never JSON under `Control/Fixtures` — a file
there is one `parity-fixture.sh` replays against the reference, which cannot produce it.

A 404 maps to `malformedResponse`, not `server(status:)`, by the same argument `skillsRead`
already carries: the TypeScript router is the installed default and has no such route, so 404 is
version skew rather than "the router couldn't complete that".

### UI

`Boards/HarnessesBoard.swift`, `HarnessesBoardModel.swift`, `HarnessesBoardRow.swift`,
`Boards/InsightsBoard.swift`, `InsightsBoardModel.swift`, `InsightsBoardCharts.swift`,
`Boards/M22BoardMetrics.swift`, `Icon.swift`, `Shell/ScaffoldPane.swift`, `Shell/ShellWindow.swift`,
`Shell/ShellModel.swift`.

Every dimension comes off `MetricToken` — `no-raw-design-values.sh` forbids a geometry literal
under `Boards/`. Bar fills are `ColorToken.liveInk` and `.attentionInk`, the text-safe twins, never
`.live`/`.attention`: the kit greens and ambers measure 2.22:1 and 2.31:1 on the light ground and
Charts will happily paint the brighter one.

A zero-valued row is drawn by the row view, not by `Charts`, so an empty series cannot be dropped.

---

## 5 · Tests

| Suite | What it holds |
|---|---|
| `RouterCoreTests/ControlHarnessesTests` | the envelope; `unreadable` ahead of `state`; the four readings; `/harnesses/` reaching 405 rather than 404 |
| `RouterCoreTests/ControlInsightsTests` | zero-history answers the empty horizon; `resident` null with no children; the 24 buckets are 24 and oldest-first |
| `RouterCoreTests/UsageInsightsTests` | bucketing at the hour boundary; a torn last line skipped; failures counted from `ok` |
| `RouterCoreTests/DutyCycleTests` | alive-time accumulates across a reap and includes the open handle |
| `RouterCoreTests/ClientProcessNameTests` | every `MCPClient` has an arm; two harnesses sharing `codex` are both ambiguous |
| `MCPRouterKitTests/HarnessModelTests` | a fifth reading fails decoding; the sentence comes off the case |
| `MCPRouterKitTests/InsightsModelTests` | a null count decodes as absent, not as 0 |
| `MCPRouterUITests/M22BoardTests` | the zero row renders its label and its zero; a not-attributable row renders neither; bar fills name the ink tokens |
| `MCPRouterKitTests/ShellDestinationTests` | updated membership and digits |

Every drift guard added here is broken once and seen red before it is trusted (`SWIFT_PRACTICES.md`
§7); the progress note records which.

---

## 6 · Gates this change owes

- `make lint` — swiftformat, swiftlint strict, the three lints, the two Python gates.
- `scripts/lint/no-harness-config-writes.sh` — the new files sit inside its seam by name; nothing
  in them writes.
- `scripts/acceptance/parity-manifest-check.sh` — two rows, the pin, and the cutover target.
- `swift test` for the three targets.
- M23: `planning/fidelity/harnesses.*` and `insights.*`, and two `MeasureDump.Surface` cases.

---

## 7 · Parked, each with its reason

| Item | Why |
|---|---|
| Harness version on the row | nothing observes it; §2.2 |
| The `Last 7 days` window pop-up | needs a durable store the log rotation does not give; §2.3 |
| Duty cycle over a rolling 24 h | needs a second JSONL in a directory the parity lanes diff; §2.4 |
| `Skill and server use, by version` | no version is recorded anywhere; §2.9 |
| The mock's four-group sidebar | the spec says two rows appear, not a regroup; §2.8 |
| The analyst's own configuration | `PRD.md` §6 is unimplemented; the board draws its empty state |
