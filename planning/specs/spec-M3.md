# M3: Servers — the breaker board

- **Status:** Ready for Work
- **Depends on:** M1 (shell, merged) · F2 (design system, merged) · F3 (control client, merged) · F4 (tracker failure states, merged)
- **Brief:** `planning/features-to-triage/M3-servers-board.md`
- **Plan:** `planning/plans/plan-M3.md`
- **Design authority:** `DESIGN.md` (root) · **Practices:** `planning/practices/SWIFT_PRACTICES.md`, `CODING_PRACTICES.md`, `NEW_PROJECT_BEST_PRACTICES.md`, `UI_VERIFICATION.md`
- **Mock:** `design/mocks/prototype.html?only=mac&pane=servers` (read over HTTP, 2026-08-14)

---

## Feature description

The app's signature surface, and the reason it goes first: after M1 the window opens and every
one of its seven panes says "isn't built yet". This is the pane that makes the product legible —
one breaker per declared server, its state, and the lever.

Three surfaces, not one:

1. **The board** — breaker, name, state subtitle, transport, tools, calls, errors, last used, and
   a per-row action that changes with state.
2. **The inspector** — the full configuration (read-only), the per-project scoping list, the tool
   inventory, and the route into the held-description diff.
3. **The actions** — add a server, remove one, reset a tripped one, keep one warm, scope one to a
   project, review a held tool description, and authorise an HTTP upstream.

**M3 is not done when the view compiles.** It is done when `.servers` is in
`BoardRegistry.installed` in `app/Sources/MCPRouterUI/Shell/ScaffoldPane.swift`.

**And the merged test does the opposite of what an earlier draft of this spec claimed**, which is
worth recording because it changes what M3 has to do. `ShellIntegrationTests` asserted
`#expect(BoardRegistry.installed.isEmpty)` — a statement about M1, not about the registry — and
`scaffolded` is *derived* (`Destination.ordered.filter { !hasBoard($0) }`), so the two sets are
complements by construction and no test could ever have caught an omitted registration. The
consequences ran the other way: omitting it kept the suite green, and performing it turned that test
red. M3 replaces the empty assertion with the complement invariant it was standing in for, plus a
direct assertion that `.servers` is installed. The replacement is strictly stronger, so it is not a
weakened test under `SWIFT_PRACTICES.md` §7.

---

## What the router actually observes

Every clause below is written against this list, because `DESIGN.md` §6 forbids displaying a number
the router does not observe, and the prototype displays two it does not. Source: `MCPServer` and
`ServersResponse` in `app/Sources/MCPRouterKit/Control/Models.swift`, transcribed from
`describe()` in `src/control.ts`.

| Field | Type | Used by |
|---|---|---|
| `name` | `String` | row identity, name cell |
| `transport` | `.stdio/.http/.sse` | transport cell, config section |
| `state` | `.idle/.starting/.running/.stopping` | breaker, subtitle |
| `inFlight` | `Int` | subtitle, inspector |
| `callsServed` | `Int` | inspector only, labelled **Calls by this process** — it is the live child's counter and resets each time the reaper closes it |
| `usage.calls`, `usage.errors` | `Int` | the board's calls column and the inspector's **Use** section — the lifetime totals |
| `idleSec` + `ServersResponse.idleMs` | `Int` | the reap countdown |
| `command`, `args`, `cwd`, `url` | optional | inspector configuration, **read-only** |
| `envKeys`, `headerKeys` | `[String]?` | inspector configuration — **keys only, never values** |
| `hash`, `indexedAt`, `indexError` | optional | inspector configuration |
| `tools`, `toolNames` | `Int`, `[String]` | tools cell, inspector inventory |
| `projects` | `[String]` | subtitle, scoping list |
| `warm` | `Bool` | subtitle, Keep-warm toggle |
| `placard` | `Placard?` (`reason`, `substitute`, `until`) | the tripped state |
| `pendingChange` | `PendingChange?` (`seenAt`, `count`) | the held state |
| `auth` | `ServerAuth` (`supported`, `authorized`, `authorizedAt`, `pendingURL`) | the authorise state |
| `usage.lastUsed`, `usage.firstSeen` | optional | last-used cell, inspector |
| `usage.projects` | `[String: Int]` (not optional) | inspector |
| `ServersResponse.pendingAuth` | `PendingAuth?` | "already waiting in your browser" |

**Two things the prototype shows that this list does not contain**, both removed rather than
invented — see *Stated deviations* below:

- a per-row **eval chip** ("passed" / "not evaluated"). There is no eval field on a server anywhere
  in the control API and no `eval` token in `src/control.ts`. Evals belong to M7.
- a **hardcoded 300-second reap countdown**. The horizon is `ServersResponse.idleMs`, which the
  router does report, so the countdown is computed from it.

---

## The board

### Header

| Element | Content | Token |
|---|---|---|
| Title | `Servers` | Title1, `--t1` |
| Subtitle | `{T} tools from {N} servers · {R} running` | Body, `--t2` |
| Trailing action | `Add server…` | `ProminentButtonStyle` — the one accent-filled action in this view (§3.4) |

`T` is the sum of `tools`, `N` the row count, `R` the count of `state == .running`. On a `.stale`
load the subtitle drops `· {R} running` and reads `· last reading, not current`: a running count is a
present-tense claim about a router that is not answering, and M1's A18 already draws that line for
the readout. It does **not** name a time — nothing observes when the poll answered, and a duration
derived from the newest `lastUsed` would be reporting when a tool was called under a label that says
something else.

### Search — `⌘F`

The prototype has no search field. `DESIGN.md` §8 binds `⌘F` to *Focus search*, and where the two
disagree the document is the spec. A search field sits beside the segmented filter and matches
against the server name **and** its `toolNames`, both observed. Search composes with the filter
rather than replacing it.

### Filter — segmented, switches the view in place (§3.6)

| Segment | Predicate | Count shown |
|---|---|---|
| All | every declared server | always |
| Running | `state == .running` | when > 0 |
| Idle | `state != .running` | when > 0 |
| Needs you | `needsAttention \|\| placard != nil` | when > 0 |

`MCPServer.needsAttention` is already `pendingChange != nil || (auth.supported && !auth.authorized)
|| indexError != nil`. `placard` is added because a placarded server is inoperative and shows a
tripped breaker; a filter that means "not fine" that skips the red rows is the wrong filter.

### Columns and rows

Column headers in sentence case at `--t3` (§3.2): *(breaker)* · server · transport · tools · calls
· last used · *(action)*.

Row height is **`MetricToken.serversRow` (56pt)** and does not vary with content (§5 Overflow). Row
identity is `server.name`, never an index — this product's list reorders as servers start and stop
(`SWIFT_PRACTICES.md` §4).

| Cell | Content | Token |
|---|---|---|
| Breaker | `Breaker(state:)`, `BreakerGeometry.standard`, 30×48 | per state |
| Name | `name`, one line, tail truncation | Body, `--t1` |
| Subtitle | the branch below | Caption **monospace** — instrument data (§2) |
| transport | `stdio` / `http` / `sse` | Callout mono, `--t2` |
| tools | `tools` | Callout mono, `--t2` |
| calls | `usage.calls`, then `usage.errors` when > 0 | mono; `--t2`, `--t3` at zero; errors `--fail` |
| last used | `shortAgo(usage.lastUsed)` or `Never` | mono; `--t2`, `--t3` when never |
| action | the contextual action below | `StandardButtonStyle(scale: .small)` |

### The subtitle branch — the clause that failed twice in the prototype

The brief names this as the thing to get right: *warm implies running; the reaper skips warm; a warm
server never shows a reap countdown; the subtitle branches on warm before running.*

The prototype branches on `s.warm && s.st==='running'`, which is a conjunction rather than a
precedence — a warm server the router has not yet brought up falls through to `dormant`, which tells
the user a server the reaper will never touch is dormant. The order below is a strict precedence and
`warm` sits above `running`:

| # | Condition | Subtitle | Tint |
|---|---|---|---|
| 1 | `inFlight > 0` | `{n} in flight` | `--t2` |
| 2 | `placard != nil` | `tripped · {placard.reason}` | `--fail` |
| 3 | `pendingChange != nil` | `{count} description held` / `{count} descriptions held` | `--attn` |
| 4 | `auth.supported && !auth.authorized` | `needs authorising` | `--attn` |
| 5 | **`warm`** | `warm · never reaped` | `--t2` |
| 6 | `state == .running` | `reaps in {n}s` | `--t2` |
| 7 | `state == .starting` | `starting` | `--t2` |
| 8 | `state == .stopping` | `stopping` | `--t2` |
| 9 | `!projects.isEmpty` | `scoped to {n} project` / `{n} projects` | `--t2` |
| 10 | otherwise | `dormant` | `--t3` |

Failure and decision outrank lifecycle because they are what the user can act on. Within lifecycle,
warm outranks running, which is the invariant: **there is no input to rows 5 and 6 that produces a
countdown for a warm server.**

`{n}` in row 6 is `max(0, idleMs / 1000 - idleSec)`, from the response's own `idleMs`. Nothing is
assumed about the horizon.

### The breaker state

A pure function on `MCPServer`, in `MCPRouterKit` so it is testable without a host:

| Order | Condition | `BreakerState` |
|---|---|---|
| 1 | `state == .running` | `.running` — lever up, `--live` |
| 2 | `placard != nil` | `.tripped` — lever down, `--fail` |
| 3 | `needsAttention` | `.wantsYou` — lever down, `--attn` |
| 4 | otherwise | `.dormant` — lever down, unlit |

Running is checked first because the lever is a claim about a child process: raising it for a server
that is not running, or lowering it for one that is, is the only way this control can lie. A running
server that also holds a description therefore shows green, and its attention is carried by the
subtitle, the row action and the *Needs you* count — colour is never the only signal (§3 rule 10).
The limitation this leaves is recorded under *Shared-surface changes wanted and skipped*.

### The per-row action

| Condition | Action | Effect |
|---|---|---|
| `placard != nil` | `Reset` | see below |
| `pendingChange != nil` | `Review…` | opens the held-description sheet |
| `auth.supported && !auth.authorized`, and `pendingAuth?.server != name` | `Sign in…` | `beginAuthorization`, opens the returned URL |
| `pendingAuth?.server == name` | `Reopen the page` | re-opens `pendingAuth.url` |
| otherwise | nothing | the cell is empty |

The cell is **empty** where there is nothing to do. It does not carry an eval chip, because there is
nothing behind one.

`Review…` and `Sign in…` are `StandardButtonStyle`, not accent-filled: §3.4 allows exactly one
prominent accent-filled action per view and `Add server…` is it. The prototype paints `Review…` with
the accent class; that is the prototype being stale against its own rule.

**Reset resolves to the operation that actually clears the condition**, which depends on where the
placard came from — `placardFor()` in `src/manifest.ts` returns the user's placard first and the
index error second:

- `indexError != nil` → `reindex(name)`. Clearing the placard field would not help; the router
  recomputes it from the index error on the next describe.
- otherwise → `patch(server:, ServerPatch(placard: .clear))`, which encodes an explicit `null` —
  the one thing `ServerPatch`'s hand-written encoder exists for.

### Footer

`{shown} of {total} servers · {tools} tools indexed`, and — when any server is scoped — a second
quiet line saying so.

The earlier wording ended "in every session's tool list", which is false the moment a server is
scoped: `visibleTo(u, opts.cwd)` in `src/manifest.ts` filters scoped servers by the calling session's
directory, so the same router answers a different list in one repo than in another. The count was
observed; the sentence attached to it was not — and this board ships the control that creates the
discrepancy.

### Empty-in-filter

Distinct from Empty, and worded per filter rather than once. The prototype's single string ("Every
server is behaving") is false under the Running filter, where the truth is that nothing is up.

| Filter | Title | Detail | Action |
|---|---|---|---|
| Running | `Nothing is running` | `No server has a child process up right now. The router starts one the moment an agent calls it.` | `Show all servers` |
| Idle | `Everything is running` | `All {n} declared servers have a child process up.` | `Show all servers` |
| Needs you | `Nothing needs you` | `No held descriptions, nothing tripped, and nothing waiting to be authorised.` | `Show all servers` |
| Search, under All | `No server matches “{query}”` | `Nothing is named that, and no tool on any server is either.` | `Clear search` |
| Search, under a filter | `No {filter} server matches “{query}”` | `Another server may match — this is only the {filter} view.` | `Search all servers` |

The third row is the one that matters: search **composes** with the filter, so a query matching an
idle server read under Running matches nothing here while the server plainly exists. Claiming
"nothing is named that" then would be the same false-sentence defect D7 removes from the prototype,
one level further in.

---

## The inspector

Opens on row selection; `Esc` clears the selection (§8). Header: a breaker at the same geometry,
the name, `{transport} · {tools} tools`, and a close control.

**Banners** sit at the top, adjacent to the thing that failed (§5 Error):

- **Tripped** — `Tripped. {reason}. It will not re-arm on its own — that is deliberate, because a
  server that fails and silently retries hides the failure.` Followed by `{substitute} is standing
  in meanwhile.` when `placard.substitute` is set, and `Held until {until}.` when `placard.until`
  is. Action: `Reset`.
- **Held** — `{n} tool description held. The approved text is still what your sessions see.`
  Action: `Review the change`.
- **Needs authorising** — `This server hasn't been authorised yet. Its tools are declared, and calls
  to them are refused until you sign in.` Action: `Sign in…`, or `Reopen the page` with
  `A browser page is already open for this.` when `pendingAuth` names it.

### 1 · Right now

State · In flight · Calls served (`{n}` then `· {e} failed` when errors > 0) · Last used · First
seen. Monospace values.

### 2 · Configuration — read-only, and labelled as such

The brief asks for "full config". It is shown and it is never editable, which is the product
constraint made visible rather than merely enforced:

Transport · Command · Arguments (as the argument array) · Working directory · URL · Environment ·
Headers · Config hash · Indexed at · Index error.

**Environment and Headers render `envKeys` and `headerKeys` only** — `3 variables · API_KEY, HOME,
PATH`. The control API never sends values and this surface never asks for them.

Closing sentence, one quiet secondary line (§6): `MCP Router reads these from the config file the
server is declared in, and never writes them there. Change them where you declared it.`

### 3 · Behaviour — the only writable section

Every control here maps to a `ServerPatch` field, which is the only shape the app may PATCH and
which structurally cannot carry `command`, `args` or `env`.

- **Keep warm** — toggle → `ServerPatch(warm:)`. Helper: `Skip the reaper. Costs resident memory to
  save a cold start.`
- **Only load in named projects** — toggle → `ServerPatch(projects:)`, with the scoping list beneath
  it: one row per path, each removable, plus `Add this project…`. Helper when off: `Every session
  sees its {tools} tools.` An empty array clears the restriction; omitting the field leaves it
  alone, and the toggle sends the array explicitly in both directions.

`ServerPatch.idleMs` is deliberately **not** surfaced. It is writable and it is not readable back —
`MCPServer` carries no per-server idle override — so a control for it would show a value it had
invented. Recorded as a deferred child.

### 4 · Tools

`toolNames` as tags, and `+{n} more` when `tools > toolNames.count`. The count and the names are
both the router's.

### 5 · Danger

`Remove this server…` — destructive, never the default (§3.4).

---

## Sheets and dialogs

### Add server — `⌘N`

Lede, kept from the prototype because it is honest and load-bearing: *You don't normally need this.
Add it to `~/.claude.json` exactly as you always have and the router adopts it within a second —
indexing it first, so a typo'd command stays visible where you typed it.*

A config fragment field, and the note that *it is spawned once to enumerate its tools, then stopped.
Nothing is written to your config until that succeeds.* Actions: `Cancel` (leads) ·
`Index and add` (prominent).

On a refusal carrying a hint — the router replies `{error, hint: "retry with ?force=1 to add it
anyway"}` — the hint is shown and a second action appears: `Add it anyway`, calling
`add(_:force: true)`. `ControlAPIError.server(status:message:hint:)` already carries the hint; a
client that dropped it would leave the user told what failed and not what to do.

### Held tool description — from `Review…`

Driven by `heldChanges(for:)` → `HeldChanges { server, pending, seenAt, changes: [ToolChange] }`.

Title `{server} rewrote {n} tool description`. Lede: `The approved text is still what your sessions
see. Nothing changed for them.` Then per `ToolChange`: its `kind` (added / removed / changed), its
`name`, and `before` against `after` for both the description and the schema.

**`ToolChange.invisible` is rendered explicitly, never silently:** `This description carries {n}
invisible characters that render as nothing and that a model still reads: {codepoints}.` That field
is the quarantine surface's whole reason to exist.

Actions: `Remove {server}` (destructive) · `Keep serving the old text` (leads) · `Accept the new
text` (prominent, `approvePendingChange`).

`Keep serving the old text` closes the sheet and calls nothing, because that is exactly what it
does — the router is already serving the approved text and the change stays held. The copy says so
rather than implying a write took place.

### Remove a server — a named-consequence dialog

**This is a stated deviation from `DESIGN.md` §8 and §9, and the measurement behind it is why.**

§8 gives `⌘⌫` as *"Remove the selected server (undoable, never confirmed)"* and §9 makes removal
undoable and uncounted. Measured against the router this app talks to: `DELETE /servers/:name`
(`src/control.ts` ~line 312) calls `editConfigFile` and **deletes the entry from the user's config
file**, then clears its stored credentials. The app can read `envKeys` and `headerKeys` — the key
names — and never the values. So an undo built on `add(NewServer)` would restore a server with its
secrets missing: a row that looks recovered and does not work. That is worse than a dialog.

§9's own escape clause covers it: *"Friction scales to blast radius only for genuinely destructive
acts, and then as a named-consequence dialog that is never the default button."* Deleting an entry
from a user's config file, including values this app cannot read back, is that act.

- Title: `Remove {name}?`
- Detail: `This deletes its entry from the config file it is declared in. Its {n} tools leave every
  session's tool list.`
- The named consequence, when `envKeys` or `headerKeys` is non-empty: `{k} environment variables are
  set on this server and MCP Router can see their names but not their values, so it cannot put this
  back. Copy the entry first if you might want it.`
- When both are empty: `Nothing secret is stored on this entry, so re-declaring it restores it
  exactly.`
- Checkbox, on by default: `Keep its call history` → `remove(name, keepHistory: true)`. Off calls
  the router's own default, which forgets the usage rows. An independent setting, so a checkbox
  (§3.6).
- Actions: `Cancel` (leads, **default**) · `Remove` (destructive, never default).

Nothing is tallied and no trash metaphor is used (§9).

---

## Keyboard, and the menu bar behind it

`DESIGN.md` §3.9 makes the menu bar the complete command surface, so every one of these is a menu
item as well as a key. M1 shipped the items with `availability == .surfaceAbsent` and left a comment
saying the board flips them; this is that flip.

| Key | Command | Availability once M3 ships |
|---|---|---|
| `⌘N` | Add server… | `.enabled` |
| `⌘F` | Find (focus search) | `.enabled` |
| `⌘R` | Reset server | `.enabled` with a tripped server selected, else `.needsServerSelection` |
| `⌘⌫` | Remove server | `.enabled` with a server selected, else `.needsServerSelection` |
| `Return` | opens the inspector for the focused row; in a sheet, its prominent action | — |
| `Esc` | dismisses the sheet, then clears the selection | — |
| `Space` | toggles **Keep warm** on the selected row | — |

**`Space` is a stated deviation and the reason is that the alternative is not implementable.** §8
says *"toggles the selected row's breaker"*, and F2's `BreakerToggle` carries the hint *"Toggles the
server between dormant and running"*. There is no start endpoint and no stop endpoint on the control
API — the whole of it is listed on `ControlAPIClient`, and the router's design is that a server is
spawned lazily when a tool is called and reaped when idle. The only user-controllable lever over
whether a child process stays up is `warm`, and `PATCH { warm: true }` does start one
(`src/control.ts` ~line 385 calls `deps.pool.warmUp()`). So `Space` toggles warm: a real lever, and
the one the breaker is actually attached to. The board renders the plain `Breaker` indicator rather
than `BreakerToggle` for the same reason.

The flip is **additive**, so M1's contract is untouched: `MenuCommand.availability` keeps its present
meaning as the answer with no board installed and nothing selected — which is what the table in
`spec-M1.md` records and `MenuCommandTests` parses — and a new `availability(in:)` taking a small
`CommandContext { installedDestinations, selectedServer }` answers for the live app.

Focus order runs sidebar → search → table → inspector (§8), extending M1's declared prefix.

---

## The nine states (§5) — with real copy

| State | When | What renders |
|---|---|---|
| **Default** | `.loaded(servers)`, non-empty | the board |
| **Empty** | `.loaded([])` | `ServersBoardCopy.empty` — *No servers declared yet* / *MCP Router reads the servers your agents already have configured. Point it at a config, or declare one by hand.* / `Add server…` |
| **Loading** | `.loading` | `SkeletonRows` at `MetricToken.serversRow`, so nothing jumps when data lands |
| **Partial** | `.stale(servers, error)` | the rows stay, under a banner (below), and the header's running count goes absent |
| **Error** | `.failed(error)`, error is not `routerNotRunning` | full pane from `error.headline` / `error.advice` / `error.actionLabel` |
| **Success** | after any write | in place, from the server the router returned — see below. No toast (§5) |
| **Offline** | `.routerNotRunning`, in **either** load state | *The router isn't running* / *Nothing is listening on the control port…* / `Start the router`, shown dimmed — see below |
| **Disabled** | see below | dims in place with a reason (§3.4) |
| **Overflow** | long values | truncation, full value in the inspector, row height unchanged |

**The Partial banner** — real copy: `{headline}. These servers are the last reading the router
gave, kept rather than cleared. Nothing about them is current. {advice}`

**No timestamp and no duration appear, and their absence is a correction.** An earlier draft read
`as of {time}` and `last read {ago}`; nothing observes when a poll answered — `LoadState` carries
servers and an error, and no `apply` entry point records a time — and deriving one from the newest
`lastUsed` would be reporting *when a tool was called* under a label that says something else. The
stale header therefore reads `· last reading, not current`. "As of {time}" was also an overstatement
in its own right: `ServerStateTracker` records that stale servers are the last poll **as corrected by
any call records seen since**, so they are not a frozen instant. F4's `.stale` case exists precisely so this state can be rendered
without either throwing away good data or hiding a live failure.

**Offline is not only `.failed`.** `.failed` means *nothing has ever loaded*, which is true only
of an app launched against a dead router. A router that was running and stops produces
`.stale(servers, .routerNotRunning)` — the ordinary case — so the Partial banner takes its whole
wording *and* its action from the error, and `routerNotRunning` still says "The router isn't running"
there. `SWIFT_PRACTICES.md` §3 requires that state to be rendered as itself on every surface and
never as a generic banner; this is how a surface that still has rows honours it.

**The `Start the router` action is shown disabled, with its reason.** Nothing in this repository
starts a daemon — that is R2R's item — so a live button would do nothing. §3.4's disabled treatment
(dims in place, discoverable reason, never hidden) is the honest rendering: *MCP Router can't start
the daemon itself yet. Start it the way you normally do and this fills in on its own.* Naming a
launch command this app does not own would be inventing a fact about the user's machine.

**Offline and Error copy comes from `ControlAPIError`**, not from new strings. `ControlCopyTests`
already asserts those two against `design/mocks/html/f3-connection-states.html`, and §6 asks for one
wording per state. See *Shared-surface changes wanted* for the one place F2's gallery copy differs.

**Disabled, and its reason:**

| Control | Disabled when | Reason shown |
|---|---|---|
| `Reset` | the selected server is not tripped | `Only a tripped server can be reset.` |
| `⌘R` | nothing selected | `Select a server first.` |
| `⌘⌫` | nothing selected | `Select a server first.` |
| Behaviour toggles | a PATCH is in flight | `Applying…` |
| Behaviour toggles | load is `.stale` or `.failed` | `The router isn't answering, so this can't be changed right now.` |

Every control additionally carries default / hover / focus-visible / active / disabled; focus rings
are the accent at `MetricToken.focusRing` (§8), applied through F2's `focusRing(_:)`.

**Motion** (§7): the breaker's two springs are already `BreakerGeometry.spring(raised:reduceMotion:)`
— rise 0.18/0.62, fall 0.60/1.0 — and the board applies the answer rather than choosing one. Reduce
Motion removes the animation and never the state change. Nothing animates opacity from 0 on entry.

---

## Acceptance criteria

Evidence type is named per clause: **M** measurement from the running app · **X** exercised request
against a stub or fixture client · **T** red-green unit test (the guard is seen to fail before it is
trusted).

### The board is installed

- **A1 (T)** `.servers` is in `BoardRegistry.installed`, and `ScaffoldedDestination(.servers)` is
  `nil`. The merged complement test passes with it.
- **A2 (M)** Selecting Servers in the running app renders the board and **not** the sentence
  `isn't built yet`, read from the accessibility tree by pid.

### The state rules

- **A3 (T)** The subtitle branch is a pure function and is exhaustive over its ten rows, one case
  each, asserted on a constructed `MCPServer`.
- **A4 (T)** **No input produces a reap countdown for a warm server.** Asserted over the cross
  product of `warm` × every `ServerState` × `inFlight ∈ {0,1}` × placard × pending change: **no**
  case containing `reaps in` has `warm == true`. Separately, a warm server with nothing else to
  report reads `warm · never reaped` in every lifecycle state — stated as its own clause because
  row 1 (`{n} in flight`) legitimately outranks warm, so "every warm case reads warm" would
  contradict the precedence table this spec also defines.
- **A5 (T)** A warm server with `state == .idle` reads `warm · never reaped`, not `dormant` — the
  precedence the prototype gets wrong.
- **A6 (T)** The countdown equals `max(0, idleMs/1000 - idleSec)` and is taken from the response,
  including a case where `idleMs` is not 300000. No literal 300 appears in the board's sources.
- **A7 (T)** The breaker mapping is exhaustive and running-first: a running server with a
  `pendingChange` maps to `.running`; a placarded non-running server to `.tripped`; a server needing
  auth to `.wantsYou`; anything else to `.dormant`.

### What is displayed is what is observed

- **A8 (T)** No eval chip is rendered on any row, in any state. Asserted as the absence of the
  strings `passed` and `not evaluated` from the board's rendered row model.
- **A9 (T)** The header's tools, servers and running figures are each derived from the response, and
  the running figure is **absent** on `.stale` — asserted against a tracker driven to `.stale`.
- **A10 (T)** The inspector's Environment and Headers sections render key names and the count, and
  no code path passes a value: `envKeys`/`headerKeys` are the only fields read, checked against the
  rendered model rather than the type.

### The actions

- **A11 (X)** `Reset` on a server with `indexError != nil` issues `POST /servers/:name/reindex`;
  `Reset` on a placarded server without an index error issues `PATCH` with a body whose `placard`
  key is an explicit JSON `null`. Both asserted on the recorded request.
- **A12 (X)** `Keep warm` issues a PATCH whose encoded body is exactly `{"warm":…}`, and the scoping
  toggle one whose body is exactly `{"projects":[…]}` — through `encodedBody()`, so a forbidden or
  unpermitted key throws rather than shipping.
- **A13 (T)** **No PATCH this surface can issue carries `command`, `args` or `env`**, asserted
  against the *encoded JSON* rather than the Swift type. Scoped to PATCH deliberately: `Add server…`
  is on this surface and sends `NewServer`, which carries all three **by design** — `Models.swift`
  records it as "the only type in the client that carries `command`, `args` and `env`… Adding a
  server is an explicit act with its own surface." The guarantee `SWIFT_PRACTICES.md` §2 actually
  makes is that *editing* a server can never become *installing* one, because the patch type has no
  such field. Both halves are asserted, so the true claim is checked and the false one cannot come
  back as a comforting green test.
- **A14 (X)** A refused `add` carrying a hint surfaces the hint and offers `Add it anyway`, which
  re-issues with `force: true`.
- **A15 (X)** `Remove` issues `DELETE` with `keepHistory=1` when the checkbox is on and without it
  when off.
- **A16 (T)** The remove dialog's named consequence branches on `envKeys`/`headerKeys` being
  non-empty, and `Cancel` is the default action while `Remove` is not.
- **A17 (X)** `Accept the new text` issues `POST /servers/:name/approve` and decodes
  `ApprovalResult`; `Keep serving the old text` issues **no request at all**.
- **A18 (X)** `Sign in…` issues `POST /servers/:name/auth` and opens the returned
  `authorizationUrl`; when `pendingAuth` names the server the action is `Reopen the page` and no new
  authorisation is begun.

### The nine states

- **A19 (T)** Each of the nine `SurfaceState` cases has a rendering on this board, exhaustively
  switched so a tenth case fails to compile.
- **A20 (T)** Loading renders skeleton rows at exactly `MetricToken.serversRow`, equal to the
  populated row height — the board does not jump when data lands.
- **A21 (T)** `.stale` keeps its rows and shows the Partial banner; `.failed` shows the full-pane
  error and no rows; `.failed(.routerNotRunning)` shows the Offline pane with `Start the router`.
- **A22 (T)** Offline and Error copy is `ControlAPIError`'s, character for character — asserted by
  identity against the error's own `headline`/`advice`/`actionLabel`, so a second wording cannot be
  introduced.
- **A23 (T)** A 68-character server name truncates and the row's height is unchanged from a short
  name's; the full name reaches the accessibility label and the inspector.
- **A24 (T)** Each empty-in-filter case has its own copy, and none of the four says a thing that is
  false for its filter (asserted per filter against its predicate).
- **A25 (T)** Every disabled control exposes its reason through its accessibility hint; none
  disappears when disabled.

### The keyboard and the menu bar

- **A26 (T)** `availability(in:)` returns `.enabled` for `⌘N` and `⌘F` once `.servers` is installed;
  `.needsServerSelection` for `⌘R`/`⌘⌫` with nothing selected; `.enabled` for `⌘⌫` with a selection;
  and `.enabled` for `⌘R` only when the selected server is tripped.
- **A27 (T)** The parameterless `MenuCommand.availability` is unchanged, so `spec-M1.md`'s inventory
  table and `MenuCommandTests` still pass without edit.
- **A28 (M)** With the app backgrounded and driven by pid, the File menu's `Add server…` reports
  `AXEnabled` true and no help tag, where M1 measured it disabled with
  `This part of the app isn't built yet.`
- **A29 (T)** `Space` on the selected row toggles `warm` and issues the corresponding PATCH; the
  board renders `Breaker`, not `BreakerToggle`.

### Tokens and the native floor

- **A30 (T)** No colour, size, radius or line height literal appears in the board's sources — every
  value reads a `ColorToken`, `TypeToken`, `MetricToken` or `BreakerGeometry`.
- **A31 (T)** Exactly one `ProminentButtonStyle` is constructed in the board's populated view
  (§3.4), and it is `Add server…`.
- **A32 (T)** No indicator colour is used decoratively: `--live`, `--attn` and `--fail` appear only
  on the breaker, the subtitle tints in rows 2–4, and the error counter.
- **A33 (M)** The board's row height, breaker housing and sidebar column measure 56 / 30×48 / 256pt
  in the running app's accessibility tree.

---

## Triage — 2026-08-14

### Grounding — what already exists and is reused rather than rebuilt

| Need | Existing | Where |
|---|---|---|
| Server data + failure states | `ServerStateTracker` (`.loading/.loaded/.failed/.stale`, `StreamCondition`) | F4, merged |
| Every operation | `ControlAPIClient` — all **14** protocol requirements | F3, merged |
| The write shape | `ServerPatch` + `encodedBody()` | F3, merged |
| Error copy | `ControlAPIError.headline/advice/actionLabel` | F3, merged |
| The breaker | `Breaker`, `BreakerGeometry`, `BreakerState` | F2, merged |
| Nine-state copy and containers | `ServersBoardCopy`, `SkeletonRows`, `MessageState`, `OverflowRow` | F2, merged |
| Buttons, selection, focus ring | `ProminentButtonStyle`, `StandardButtonStyle`, `selectionFill`, `focusRing` | F2, merged |
| Relative time | `shortAgo`, `asControlAPIDate`, `projectLabel` | F3/F4, merged |
| The pane slot | `ContentZone.pane`'s else-branch, `BoardRegistry` | M1, merged |
| Menu items and routing | `MenuCommand`, `ShellCommandRouter`, `ShellMenuReasons` | M1, merged |

**Nothing new is needed in the control client.** Every operation this board performs already exists
on `ControlAPIClient`, which is what F3's completeness argument was for.

### Where the code goes, and why

- `app/Sources/MCPRouterKit/Servers/ServerPresentation.swift` — the subtitle branch, the breaker
  mapping, the countdown, the filter predicates, the row model. **In the UI-free target** so all of
  A3–A9 are testable without a host, which is the same split `BreakerGeometry` uses and for the same
  recorded reason.
- `app/Sources/MCPRouterUI/Boards/ServersBoard.swift` — the pane: header, search, filter, table,
  footer, and the nine-state switch.
- `app/Sources/MCPRouterUI/Boards/ServerInspector.swift` — the inspector.
- `app/Sources/MCPRouterUI/Boards/ServerSheets.swift` — add, held-diff, remove.
- `app/Sources/MCPRouterUI/Boards/ServersBoardModel.swift` — `@MainActor @Observable`; owns
  selection, search, filter, in-flight writes, and the one path to the client.
- Edits: `ScaffoldPane.swift` (`installed = [.servers]`), `ShellWindow.swift` (the else-branch),
  `MenuCommand.swift` (additive `availability(in:)`), `ShellCommandRouter.swift` (the four
  operations).

### Stated deviations from DESIGN.md and the prototype

| # | Deviation | Why |
|---|---|---|
| D1 | No per-row eval chip, against the prototype | The control API observes no eval for a server; §6 forbids displaying it. M7 owns evals. |
| D2 | Reap countdown from `idleMs`, not a literal 300s | §6 — the router reports the horizon. |
| D3 | Remove is a named-consequence dialog, against §8/§9 | `DELETE` edits the user's config file, and the app can never read env/header **values** back — see the expanded note below. |
| D4 | `Space` toggles Keep warm, against §8's "toggles the breaker" | There is no start or stop operation on the control API — see the expanded note below. |
| D5 | `Review…`/`Sign in…` are not accent-filled, against the prototype | §3.4 — one prominent accent-filled action per view, and it is `Add server…`. |
| D6 | A search field exists, against the prototype | §8 binds `⌘F` to focus search; the document beats the prototype. |
| D7 | Per-filter empty copy, against the prototype's single string | "Every server is behaving" is false under the Running filter. |
| D8 | `ServerPatch.idleMs` is not surfaced | Writable but not readable back, so the control would display a value it invented. |
| D9 | `Return` activates the selected row (opens the inspector), against §8's "commits the view's one default action" | A list's Return conventionally opens the selection (Finder does), and the board's one *committing* action is `Add server…`, which Return should not fire from a row. §8's rule is honoured inside every sheet, where Return is that sheet's prominent action. |
| D10 | Focus order is sidebar → search → table → inspector, against §8's "sidebar → table → inspector" | The search field exists because §8 also binds `⌘F`, and it sits above the table. §8's sequence predates it; the order is otherwise unchanged. Recorded because an earlier draft cited §8 as authority for a sequence §8 does not contain. |
| D11 | Only `approvePendingChange` is irreversible, and no `⌘Z` is offered for any write | §9 asks for reversible actions to be made reversible and reported. Keep-warm and the scoping list **are** reversible in place — the control is its own undo, which is what a toggle is — and the placard clear is undone by re-placarding. Accepting a held description is the one write with no inverse on the control API, which is exactly why it is behind a review sheet rather than a row action. No Edit ▸ Undo item is added, because there is nothing it would undo that its own control does not. |

### Assumptions recorded — autonomous run, no human to ask

1. **"Needs you" includes placarded servers**, not only `needsAttention`. A filter meaning "not
   fine" that omits the red rows is the wrong filter. Reversible in one predicate.
2. **The inspector is a trailing panel inside the content zone**, not a third `NavigationSplitView`
   column. M1 pinned the split view to two columns and a third would change the shell's chrome,
   which is out of scope here.
3. **Search matches name and tool names.** Both observed; tool names are what a user actually hunts
   for.
4. **`Keep its call history` defaults to on.** Losing the history is a second irreversible loss and
   the API explicitly offers to avoid it.
5. **The board polls through `ShellModel.tracker`** rather than opening a second reader. Two poll
   loops against one router is the duplication the tracker exists to remove.

### Open questions — raised, not guessed

1. **Should a running server with a held description show amber?** It cannot today: `BreakerState`
   is one enum whose `isRaised` is `self == .running`. Shipped as green-with-an-amber-subtitle.
2. **Is `Start the router` implementable from the app?** `ControlAPIError.routerNotRunning`
   advertises the action and nothing in this repo starts a daemon. R2R owns the daemon. Shipped
   showing the action and reporting honestly if it cannot act.

### Deferred children discovered

| Suggested id | Title | Depends on |
|---|---|---|
| R-idle | Report the effective per-server `idleMs` on `GET /servers` | R3 |
| R-lifecycle | A start/stop operation, so the breaker can be a switch rather than an indicator | R2 |
| M7-evals | Server evals — the data the prototype's chip implies | M7 |
| M3-a11y | A full VoiceOver pass over the board's table semantics | M3 |

### Shared-surface changes wanted and deliberately skipped

1. **`BreakerState` cannot express "running and wants a decision."** It is one enum in
   `MCPRouterKit/Design/BreakerGeometry.swift`, used by F2's gallery. Wanted: a lever position and a
   lamp colour as two values. **Not made** — it is a merged base element.
2. **`BreakerToggle`'s accessibility hint claims something the API cannot do** — "Toggles the server
   between dormant and running". There is no such operation. **Not changed**; the board simply does
   not use that control.
3. **Two wordings for one state.** `ServersBoardCopy.offline.title` is *"The router is not running"*
   and `ControlAPIError.routerNotRunning.headline` is *"The router isn't running"*. §6 asks for one
   name per state. The board uses `ControlAPIError`'s. **Not changed** — `ServersBoardCopy` is F2's
   gallery surface.


---

## The two deviations that were argued against, and what survived

An adversarial review put the opposite case on D3 and D4. Both stand, with their reasoning
strengthened and their real costs written down rather than glossed.

### D3 · why removal is not undoable, even though the app could in principle read the file

The counter-argument: `DELETE` edits `~/.claude.json`, this app is **deliberately unsandboxed** and
already "rewrites `~/.claude.json`" per `SWIFT_PRACTICES.md` §6 — so it could capture the entry
before deleting it and undo would work.

It is refused on a constraint that outranks the convenience: **the Mac app talks to the router only
over the loopback HTTP control API, and a second channel is not permitted.** That boundary is what
lets the router be swapped from TypeScript to Swift underneath without the app changing, and reading
the config file directly to support an undo is precisely a second channel. `ShellIntegrationTests`
enforces it as a source-level grep over every shell and board file, so the alternative is not merely
unwise here, it is structurally unavailable.

What that leaves is a genuinely destructive act the app cannot reverse, which is §9's own escape
clause: a named-consequence dialog, never the default button. The cost is stated in the dialog
itself, and it branches — a server with no stored secrets says re-declaring restores it exactly.

### D4 · why `Space` is bound to warm, and what that costs

Four objections, each conceded on the facts:

1. **The breaker does not show `warm`.** Correct: the lever follows `state`, so pressing `Space` on
   a running, non-warm server does not move it. What *does* change immediately is the subtitle, which
   reads `warm` at row 5 — so the key changes something visible, just not the lever.
2. **The operation is asymmetric.** Correct: `warm: true` starts a process; `warm: false` stops
   nothing, it clears a policy and lets the reaper take the server when it next goes idle. Recorded
   in the code rather than glossed.
3. **It teaches a mechanism §8 does not describe.** Conceded, and it is the real cost. The
   alternative — leaving `Space` unbound until a start/stop operation exists (`R-lifecycle`) —
   teaches nothing false but also leaves §8's only row-level key doing nothing.
4. **The keybinding bypassed the gating its own control has.** This one was a defect and is fixed:
   `Space` now shares `canWrite(to:)` and the in-flight check with the Keep-warm toggle, so the key
   cannot write where the control would be dimmed.

It stands because `warm` is the only lever the control API offers over whether a process stays up,
and a key bound to the nearest real mechanism is better than a key bound to nothing. When
`R-lifecycle` lands, `Space` should move to it and this deviation should be retired.

---

## The spec gate — in-family, and what it found

`codex` is account-limited until 2026-08-20 and **exits 0 on that limit**, so its result cannot be
keyed on an exit code. Recorded honestly: **codex: usage limit → claude (downgrade)**. The gate ran
as a fresh `claude -p` Opus 5 reviewer briefed to refute, with an inability to find defects defined
as a failed review.

**Verdict: REJECT — 5 blockers, 10 majors, 10 minors.** Every blocker and every major was either
fixed or answered above. The five blockers are worth naming because each was a real error:

| # | Finding | Resolution |
|---|---|---|
| B1 | The merged test pins `installed` to **empty**, so registering `.servers` turns it red — the opposite of what this spec claimed | Test replaced with the complement invariant plus a direct installed assertion |
| B2 | A4 contradicted the spec's own precedence table (`inFlight` outranks `warm`) | A4 split into the invariant and the reads-as-warm clause |
| B3 | A13 was unsatisfiable — `Add server…` legitimately sends `command`/`args`/`env` | A13 narrowed to PATCH, with the add case asserted as its deliberate opposite |
| B4 | The Partial banner displayed a time nothing observes, and overstated the rows as a snapshot | Timestamp removed entirely; copy corrected |
| B5 | A router that dies **after working** is `.stale`, so offline rendered as a generic banner | Offline copy and action now render in both load states |
