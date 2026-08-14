# M8: Settings, the menu-bar popover, and the quarantine route

**Status:** Ready for Work
**Depends on:** M1 (shell), M3 (Servers board + the held-change sheet), F2 (design system),
F3 (control client), F4 (state tracker) — all merged.
**Design representation:** `design/mocks/html/m8-settings-popover.html`
**Plan:** `planning/plans/plan-M8.md`
**Brief:** `planning/features-to-triage/M8-settings-quarantine.md`
**Authority for anything that renders:** `DESIGN.md`
**Binding practices:** `planning/practices/CODING_PRACTICES.md`,
`planning/practices/NEW_PROJECT_BEST_PRACTICES.md`, `planning/practices/SWIFT_PRACTICES.md`,
`planning/practices/UI_VERIFICATION.md`

---

## Feature description

The brief names three surfaces: a menu-bar popover, a schema-quarantine review, and a Settings
pane.

Triage found that **the quarantine review is half-built** — the router quarantines descriptions
*and* input schemas, and the existing sheet reviews only descriptions — and that the Settings pane
is constrained by the control API far more tightly than the brief assumes. Both findings are
recorded below with the measurement behind them, because both change what this item delivers. The
first was caught by the spec gate after a first draft had certified the quarantine surface as
complete; that draft was wrong, and the correction is the most important thing in this document.

**M8 ships:**

1. **The Settings pane** — four groups: Router (observed, read-only), Menu bar (app-owned,
   writable), Warm set (observed, read-only), Control token (local, writable). Registered in
   `BoardRegistry.installed` so the destination stops rendering a placeholder.
2. **The menu-bar status item and its popover** — a template symbol that takes a single
   `--attn` dot only while something wants a decision; a popover carrying observed counts, an
   attention band, the last six calls, and one action.
3. **The schema half of the quarantine diff** — a surgical addition to M3's `ToolChangeCard`, so a
   tool that rewrites its input schema while leaving its description alone is visibly reviewed
   rather than silently accepted.
4. **The route from the popover into that sheet** — one press from a dot in the menu bar to the
   diff, for the one condition that is a live security decision.
5. **A poll that outlives the window**, without which 2 and 4 are decorative.

**M8 does not ship** a second quarantine review surface, and rebuilds none of the existing one.

---

## The quarantine review is half-built, and M8 builds the other half

`MCPRouterUI/Boards/ServerSheets.swift:134` is `HeldChangeSheet`, and it is good. It is also
**reviewing one of the two things the router quarantines**, which the first draft of this spec
missed and the spec gate caught.

`diffTools` (`src/manifest.ts:73-102`) holds a change when **either** the description **or** the
input schema differs:

```js
const nextShape = { description: tool.description, schema: JSON.stringify(tool.inputSchema ?? {}) };
...
if (prevShape.description !== nextShape.description || prevShape.schema !== nextShape.schema) {
```

Both fields are shipped on the wire — `ToolShape` carries `description` **and** `schema`
(`Control/Models.swift:193-196`). `ToolChangeCard` renders `before?.description` and
`after?.description` and **nothing else** (`ServerSheets.swift:217-222`).

**The consequence is a silent hole in the security surface this product exists for.** A server that
leaves its description untouched and rewrites `inputSchema` to add, say, a `context` parameter
produces a held change whose review sheet shows two identical text fields and no indication that
anything changed at all. The user is asked to accept a diff they cannot see. That is worse than not
holding the change, because it manufactures the appearance of review.

So the scope decision is narrower than "the sheet exists, leave it alone":

| The brief asks for | Status |
|---|---|
| show the before/after **description** diff | **M3 shipped it** — `ToolChangeCard`'s `was`/`now` fields |
| name invisible codepoints in a description | **M3 shipped it** — `ServerSheets.swift:223` |
| require an explicit accept | **M3 shipped it** — `approvePendingChange(server:)` |
| do not offer a dead accept button | **M3 shipped it** — `acceptReason`, `ServerSheets.swift:143` |
| show the before/after **schema** diff | **absent. M8 ships it.** |
| make a held change findable without already looking at Servers | **absent. M8 ships it.** |

**M8 does not rebuild the sheet, restyle it, or duplicate it.** It makes one surgical addition to
`ToolChangeCard` — the schema half of the diff the router already sends — and adds the route that
gets a human in front of it. Two review surfaces for one security decision would drift, and the one
that drifted would be the one somebody happened to open.

### What the schema half must show

`ToolShape.schema` is `JSON.stringify(inputSchema)` — one line of JSON, unformatted, and often long.
Rendering it raw as two adjacent blobs would technically be a diff and practically be unreadable,
which fails the same way the missing field does.

- Both sides are **pretty-printed with sorted keys** before display, so an ordering change in the
  serialisation is not shown as a change, and a real change lands on its own line.
- The card names **what changed at the top level** — parameters added, removed, or altered — from a
  structural comparison of the two decoded objects, so the reader is told "adds `context`" rather
  than being handed two JSON documents to compare by eye.
- **An added parameter is the case that matters** and reads in `--attn`, because a new input a tool
  did not previously ask for is the shape an exfiltration takes.
- When only the schema changed, the description fields say so explicitly rather than rendering the
  same sentence twice with no explanation.
- When the schema is unparseable JSON, that is stated, and the raw strings are shown — a schema this
  app cannot decode is itself worth seeing, and falling back to "no change" would be the silent
  failure `SWIFT_PRACTICES.md` §2 forbids.

---

## The menu bar needs a poller that outlives the window

Also caught by the spec gate, and also load-bearing.

`ShellModel.run()` is the poll loop, and it is driven from exactly one place:
`ShellWindow.swift:45`'s `.task { await model.run() }`. `.task` is cancelled when its view goes
away, which its own doc comment describes as correct — *"a sleep that is interrupted means the
window went away, and continuing to poll for it is how a closed window keeps working"*.

That was right when the window was the only surface. **A menu-bar app's normal state is
window-closed**, and M8 adds a surface that is live precisely then. Without a change, the status
item's dot and the popover's counts would be frozen at whatever the last open window saw, or absent
entirely — a glanceable instrument that silently stops being true.

**The fix, and the deviation it records:** `ShellModel` gains an idempotent `startPolling()` that
stores its `Task` on the model and is **not cancelled by any scene**. Both scenes call it; whichever
appears first starts it; the model's lifetime is the app's, so the loop's is too.

`ShellWindow`'s `.task` therefore stops owning the poll. That is a deliberate reversal of M1's
stated rationale, and the reason it is correct now and was not before is exactly the sentence above:
the app has acquired a surface that outlives its window. Recorded here rather than changed quietly.

The cost is honest and small — a 2-second poll for the life of the app. For a menu-bar app whose
entire purpose is live status, that is the feature, not a leak.

---


## What the router actually observes

`DESIGN.md` §6 — *"Numbers the router does not observe are never displayed"* — did most of the
design work on the Settings pane, because the brief names five setting groups and the control API
supports **read** for two and **write** for none. Every row below was measured against the merged
tree.

| Fact | Served? | Where |
|---|---|---|
| `port` | yes | `GET /servers` → `ServersResponse.port` (`src/control.ts:246`) |
| `idleMs` | yes | `ServersResponse.idleMs`, already retained on `TrackerState.idleMs` |
| `since` | yes | `ServersResponse.since` — when the usage counter last opened |
| per-server `warm` | yes | `MCPServer.warm`; writable per-server via `ServerPatch.warm` |
| held change | yes | `MCPServer.pendingChange`, `GET /servers/:n/changes` |
| recent calls | yes | `GET /usage` → `CallRecord` incl. `ok`, `ms`, `cold` |
| **any router setting write** | **no** | `isControlPath` admits only `/servers`, `/usage`, `/registry` (`src/control.ts:206-215`). There is no endpoint that writes `port`, `idleMs`, or anything else about the router itself. |
| **resident memory** | **no** | `residentMb()` exists (`src/pool.ts:319`) and **has zero callers**. It never reaches `describe()` and never reaches the wire. |
| **client install targets** | **no** | `ClientConfigs.discover` lives in `RouterCore`, which `app/Package.swift` links from **neither app**, deliberately. |
| **app update state** | **no** | there is no updater in the app at all. |

Two consequences follow, and both are load-bearing:

**Router settings are read-only in this app, and that is a product decision rather than a
limitation to route around.** The standing constraint is that the Mac app talks to the router only
over the loopback control API; writing `~/.claude/mcp-router/servers.json` from the app would be a
second channel. The pane therefore shows the router's own facts and says, in place, where they are
configured and that the router must be restarted.

**A control for a mechanism that does not exist is not drawn at all.** A dimmed "warm-set RAM
budget" slider tells the user the budget exists and is merely switched off, and tells the next
person to read the code the same thing. Those groups are filed as children below with the
measurement that ruled each out.

---

## Settings — the four groups

The pane is a sidebar destination, not a separate Settings scene. M1 bound `⌘,` to selecting it and
deliberately gave `MenuCommand.settings` no ellipsis for that reason. M8 keeps it: the router's
facts change while you watch, so they belong in the window that is already polling, and a separate
scene would need its own poller for data the shell already holds.

Label-left, control-right, on **one shared axis across the whole pane** — a fixed 150pt label
column, so the Router card's values and the Menu bar checkbox align with each other and not merely
within their own cards. Section headers are sentence case in `--t3` (§3.2). Instrument values are
`SF Mono`; prose is not (§2).

### Router — observed, read-only

| Row | Value | Source |
|---|---|---|
| Endpoint | `http://127.0.0.1:{port}/mcp` | `ServersResponse.port`, composed into the loopback URL the app itself talks to |
| Home | `~/.claude/mcp-router` | `RouterTokenFile.url`'s parent — the same directory the client resolves to find the token, so the path shown is the path used |
| Idle reaper | `{idleMs/1000}s` | `TrackerState.idleMs` |
| Counting since | a formatted date | `ServersResponse.since` |

Helper, verbatim:

> Read from the router, not set here. The app reaches the router over one loopback channel and that
> channel has no endpoint that rewrites the router's own configuration — deliberately, because an
> API that can rewrite a command line can run anything. Change these in
> `~/.claude/mcp-router/servers.json` and restart the router.

Home is shown with the tilde form when the path is under the user's home directory and in full
otherwise; the raw path is never truncated at the right (see the overflow state).

### Menu bar — app-owned, writable

One checkbox: **Show MCP Router in the menu bar**, persisted in `UserDefaults`. It is not a secret,
so `UserDefaults` is correct here; `SWIFT_PRACTICES.md` §6 bars only secrets from it.

Helper, verbatim:

> The item is a plain symbol and stays one. It takes a dot only while something wants a decision —
> a held tool description, a server that needs authorising, one that failed to index. An icon that
> changes constantly is one the eye learns to skip, and then it skips the change that mattered.

### Warm set — observed, read-only, acts elsewhere

`{n} of {m} servers` kept resident, counted from `MCPServer.warm`, with the warm servers' names as
chips and a **Show in Servers** button that changes the shell's selection.

**No megabyte figure anywhere.** The per-server switch lives on the Servers row, because that is
where the cost is visible; this pane counts the set and does not edit it.

### Control token — local, writable

| Row | Value |
|---|---|
| Token | `Stored in this Mac's keychain` / `Not stored yet` / `Stored, and the router rejected it` / `Not stored — this Mac's keychain refused` |
| Read from | the `RouterTokenFile.url` path |

One button: **Forget the stored token**, which deletes the keychain item so the client re-reads the
router's file on its next request. **The token value is never rendered, never logged, and never
reaches a view** — not even redacted, not even its length.

---

## The status item, and the one rule it obeys

A **template** SF Symbol, so macOS tints it for the bar's appearance and it inverts correctly on a
light menu bar.

It carries a single `--attn` dot **only** while at least one server satisfies
`MCPServer.needsAttention` — which is already the Servers sidebar badge's source, so the bar and the
sidebar cannot disagree about whether something is wrong.

Three rules that are decisions, not defaults:

- **No count in the bar.** The number is in the popover. In the bar the only question is whether to
  look, and a changing digit is a changing icon.
- **The dot is never `--fail`, even for a tripped server.** Both conditions end in a human deciding
  something, and two dot colours in a 16pt glyph are two things to learn for no gain. The
  distinction is drawn in the popover, where there is room for a sentence.
- **`--live` never appears in the bar.** A running child process is the normal state; marking it
  would make the icon change constantly, which is the exact failure the brief names.

Under `accessibilityDifferentiateWithoutColor` the dot gains a hairline ring so it reads as a
shape. The item's accessibility label is `MCP Router` at rest and
`MCP Router, {n} items need a decision` while the dot shows — the information the dot carries
visually is carried in the label too.

---

## The popover

Liquid Glass (§3.3 — floating chrome only; it is the only glass M8 draws). Radius 20 with
concentric children at 14 (§2). Three zones and one action. It answers one question and vanishes:
there is no navigation in it and no setting.

**Header** — `{running} running · {idle} idle · {tools} tools`, all observed. Running is
`state == .running` counted the same way M1's readout counts it, so the popover and the window
cannot disagree. **`idle` means *not running***, so `starting` and `stopping` are counted there
rather than dropped — the two numbers must always sum to the declared total, and reading "idle" as
`state == .idle` would break that during every cold start (A16b). **No skills count**: the prototype
shows one and there is no skills endpoint.

**Attention band** — one row per server wanting a decision, each naming *which* condition, split
from `needsAttention` into its three real causes:

| Cause | Row copy | Glyph and tint |
|---|---|---|
| `pendingChange != nil` | `changed a tool description — held, not served` | `Icon.shield`, `--attn` |
| `auth.supported && !auth.authorized` | `needs authorising before it can answer` | `Icon.shield`, `--attn` |
| `indexError != nil` | `failed to index — will not retry on its own` | `Icon.warn`, `--fail` |

Glyphs are named `Icon` cases, never literal Unicode — `DESIGN.md` §4 is "drawn, never unicode", and
`Icon` maps each to a monochrome SF Symbol at one weight. The cold-start marker on a call row adds
one case to that registry for the same reason.

A server matching more than one reports the held change first: it is the only one of the three that
is a security decision the router is actively holding bytes back for.

**The band is absent, not empty, when nothing wants a decision.** A permanent "all clear" row is
something to read every time that says nothing, and its presence would stop meaning anything.

**Call rows** — the last six from `usage(limit: 6)`, at 26pt: an `ok`-derived dot, relative age,
server, tool, duration, and the cold-start marker where `CallRecord.cold` is true. All mono except
the server name.

**Footer** — **Open MCP Router** (prominent, the one action) and **Quit**. Quit's help tag says
"Quits MCP Router. The router keeps running and your sessions keep working." — the one thing a user
might reasonably fear when quitting an app whose whole subject is a daemon.

---

## The quarantine route

| Step | What happens |
|---|---|
| 1 | The status item takes its dot the moment `needsAttention` becomes true for any server. |
| 2 | The popover's band names the server and the condition. |
| 3 | Pressing a **held-change** row activates the app, selects `.servers`, selects that server, and opens its held-change sheet. |
| 4 | M3's `HeldChangeSheet` renders, with its diff loaded — including the schema half M8 adds to `ToolChangeCard`. Nothing else in that sheet is M8's. |

**The other two causes route differently, deliberately.** A server needing authorisation and one
that failed to index both land on Servers with the row selected and **no sheet** — their next
action is in the inspector, and opening a modal the user did not ask for puts a decision in front of
them they may not want to make yet.

**This is the one press in the app that legitimately activates it.** Everywhere else the popover is
the surface; here the destination is a window, and a sheet behind a menu-bar popover on an
unactivated app is a sheet nobody can reach.

---

## The nine states (§5) — with real copy

| State | Settings | Popover |
|---|---|---|
| **Default** | four groups populated | header, band, six calls, one action |
| **Loading** | four skeleton rows in the Router card at the real 32pt row height, so nothing moves when values land | skeleton header and 26pt call rows; only on the first open of a session |
| **Empty** | per group, never per pane: "Every server is started when something first calls it and closed when the reaper reaches it. Keep one warm from its row in Servers when its cold start is the thing you keep waiting on." | counts stay real; the log says **No calls yet** / "Tool calls appear here as your sessions make them. Nothing is running until something asks." |
| **Partial** | the Router group degrades and the two local groups keep working — Settings is the only surface with something true to say while the router is down | the tracker's `.stale`: servers stay, counts are stamped — **Last refresh failed** / "showing what the router said 40s ago" |
| **Error** | adjacent to the group that failed. Keychain: "The keychain would not hand over the token (item not found, −25300). The app is still using the copy it read from the router's file, so nothing has stopped working; it will read it again next time it starts." | the stale notice appears as **its own row above the band**; the band's rows keep the tints their own causes give them. A refresh that did not complete is not three servers failing, and recolouring them `--fail` would say it was (A19b). |
| **Success** | in place, no toast: the checkbox makes the item appear or disappear; Forget flips the Token row and dims the button in the same frame | n/a |
| **Offline** | `ControlAPIError.routerNotRunning`, **verbatim** | the same two sentences, verbatim |
| **Disabled** | **Forget the stored token** dims in place with "There is no stored token to forget."; the menu-bar checkbox dims when the system has no menu bar item slot, naming that | rows that cannot be acted on are not drawn |
| **Overflow** | long server names truncate inside their chip and the set collapses to `+n`; **a long path truncates from the left**, because the filename identifies it and a right-clipped path shows only the part every path shares | names truncate with an ellipsis and rows never change height |

**No "Start the router" button anywhere.** `ControlAPIError.actionLabel` offers the label and
nothing in the merged tree renders it as an action — M3's banners show headline and advice only. A
button that cannot start anything is worse than the sentence that says what happened.

---

## Keyboard

| Key | Where | Behaviour |
|---|---|---|
| `⌘,` | anywhere | Selects Settings. M1's, unchanged. **M8 adds no shortcut and no menu item.** |
| `Tab` | Settings | Reading order: the checkbox, then **Show in Servers**, then **Forget the stored token**. The Router card holds no controls and is not in the loop. |
| `Space` | Settings | Toggles the focused checkbox. The shell reserves `Space` for a selected row's breaker; Settings has no rows, so there is no contest. |
| `Return` | Settings | **Nothing.** Four groups with unrelated controls have no one thing `Return` could mean, and binding it to the last-focused control is how a keyboard user deletes a token by accident. |
| `↑` `↓` | popover | Moves through band rows. Call rows are not pressable and are skipped. |
| `Return` | popover | Opens the focused band row's destination — the popover's one default action. |
| `Esc` | popover | Dismisses. Provided by `MenuBarExtra(.window)`; listed because it is part of the contract, not because M8 implements it. |

---

## Motion (§7)

| Moment | Feel |
|---|---|
| Popover entry | materialises from the status item — `MenuBarExtra(.window)`'s own. Never a centre fade, never opacity-from-0. |
| Status dot appearing | a small scale bump, transform only. Never a colour flash, never a pulse. |
| Attention count changing | nothing — the dot carries no count, so 3→2 is not a visual event. That is the point of not putting a number there. |
| Checkbox toggling | the system's own; the item's appearance is immediate and unanimated, because macOS does not animate menu-bar items. |
| Reduce Motion | removes the scale bump and the popover transition. The state change always happens. |
| Reduce Transparency | the popover's glass becomes an opaque `--panel` fill. |

---

## Acceptance criteria

Evidence type per clause: **M** measurement from the running app · **X** exercised request against a
stub or fixture client · **T** red-green unit test (the guard is seen to fail before it is trusted).

### The board is installed

- **A1 (T)** `.settings` is in `BoardRegistry.installed` and `ScaffoldedDestination(.settings)` is
  `nil`. The existing complement test passes with it.
- **A2 (M)** Selecting Settings in the running app renders the pane and **not** the sentence
  `isn't built yet`, read from the accessibility tree by pid.

### Router facts are observed, never invented

- **A3 (T)** Every Router row **that the router serves** — Endpoint, Idle reaper, Counting since —
  is derived from `ServersResponse`/`TrackerState` and from nothing else, asserted by constructing a
  response with non-default `port`, `idleMs` and `since` and requiring all three to appear. **Home
  is deliberately not in that set**: it is `RouterTokenFile.url`'s parent, a local path the router
  does not serve, and it is asserted separately against a constructed `RouterFacts`.
- **A4 (T)** `TrackerState` retains `port` and `since` across a poll failure, exactly as it already
  retains `idleMs` — a failure to refresh is not evidence that the router's configuration changed.
- **A5 (T)** **No megabyte, kilobyte or byte figure appears anywhere in M8's rendered strings.** A
  source-level assertion over the pane's and popover's copy, because the failure mode is a plausible
  number added later by someone who did not read §6.
- **A6 (T)** The Endpoint string is composed from the observed port; a response with `port: 9999`
  renders `9999` and never `8879`.

### The token is never disclosed

- **A7 (T)** The token value never reaches a view model: exercising the pane against a store holding
  a known token produces no rendered string containing it, at any length, in any state.
- **A8 (T)** `Forget the stored token` calls `ControlTokenStore.delete()` and nothing else — no
  request is sent to the router.
- **A9 (T)** With no stored token the button is disabled and its reason is
  `There is no stored token to forget.`
- **A10 (X)** After a forget, the next client request re-reads the router's file. Exercised against
  an in-memory store plus a temporary token file.

### The status item

- **A11 (T)** The dot is present **iff** at least one server has `needsAttention`. Asserted over the
  cross product of the three causes plus none-of-them.
- **A12 (T)** The dot's colour is `--attn` in every case, including when the only attention cause is
  `indexError`. **A `--fail` dot in the bar is a failing assertion.**
- **A13 (T)** No count appears in the status item's rendered content, at any attention count
  including 0, 1 and 12.
- **A14 (T)** The accessibility label is `MCP Router` with no attention and
  `MCP Router, 3 items need a decision` with three.
- **A15 (T)** The checkbox governs the item: false hides it, true shows it, and the value survives a
  relaunch through `UserDefaults`.

### The popover

- **A16 (T)** The header's three counts derive from the same servers list the shell's readout uses;
  given one list, popover and readout report the same running count.
- **A16b (T)** **The two counts always sum to the declared total.** `ServerState` has four cases,
  and `idle` in the header means *not running* — `starting` and `stopping` are counted as idle
  rather than dropped. Asserted over a list containing all four states: `running + idle == total`.
  Reading "idle" as `state == .idle` is the obvious implementation and would make the header stop
  summing during every cold start, which is exactly when someone is looking at it.
- **A17 (T)** No skills count is rendered, in any state.
- **A18 (T)** The band is **absent, not empty**, when nothing needs a decision. Falsifiable because
  the popover's content is a value: `PopoverContent.band` is `[AttentionRow]?` and is `nil` — never
  `[]` — when no server wants a decision. A view-level test could not tell a hidden band from a band
  of zero rows; a nil-versus-empty assertion can.
- **A19 (T)** Each band row's sentence matches its cause, over all three causes; a server with both
  a held change and a failed index reports the held change, once.
- **A19b (T)** **A failed refresh does not recolour the band.** The stale notice is its own row
  above the band and the band's own rows keep the tints their causes give them. A refresh that did
  not complete is not three servers failing, and painting them `--fail` would say it was.
- **A20 (T)** Call rows render the cold marker **iff** `CallRecord.cold`, and the error dot **iff**
  `!ok`.
- **A21 (T)** At most six call rows are requested and rendered.
- **A22 (X)** Offline renders `ControlAPIError.routerNotRunning`'s headline and advice **verbatim**,
  and renders no start action — see the recorded deviation from §5 below.
- **A23 (T)** The stale state keeps the servers and stamps the counts with their age.

### The quarantine — the schema half, and the route

- **A24 (T)** Pressing a held-change band row produces **all three** of: `selection == .servers`,
  the board's selection set to that server, **and the held diff actually loaded**. Opening the sheet
  takes two operations — setting `sheet` and calling `loadHeldChanges` — and an implementation that
  sets the sheet alone renders "Reading the held descriptions…" forever with a dimmed accept button.
  Asserting on the sheet case alone would pass that implementation, so the clause asserts the loaded
  diff as well.
- **A25 (T)** Pressing an auth or index-error row selects `.servers` and that server and opens
  **no sheet**.
- **A26 (M)** M8's diff touches `ServerSheets.swift` **only inside `ToolChangeCard`**, and adds no
  second review surface. Measured as a reviewed diff in the completion note — deliberately typed
  **M** and not **T**, because a claim about which lines changed is a claim about a diff, and a unit
  test cannot see one. M3's own sheet tests continuing to pass unmodified is separate evidence, and
  it proves behaviour preserved rather than lines unchanged.
- **A27a (T)** A change in which **only the schema differs** renders as a change: the card names the
  schema difference and states that the description is unchanged. Asserted on a `ToolChange` whose
  `before.description == after.description` and whose schemas differ — which, before this item, drew
  two identical fields and nothing else.
- **A27b (T)** A parameter **added** by the new schema is named and tinted `--attn`; one removed or
  altered is named without it. A new input a tool did not previously ask for is the shape an
  exfiltration takes, and it is the case the reader must not have to find by eye.
- **A27c (T)** Key order alone is **not** a change: two schemas differing only in serialisation
  order produce no reported difference, because both sides are decoded and compared structurally.
- **A27d (T)** An unparseable schema says so and shows the raw strings. It never falls back to
  "no change" — a decode path whose failure mode is silence is what `SWIFT_PRACTICES.md` §2 forbids.

### The poller

- **A27e (T)** `startPolling()` is idempotent: called twice it starts one loop, asserted by the
  number of polls a scripted client receives.
- **A27f (T)** The loop survives the window's scene going away — it is retained on the model, not on
  a `.task`, so a cancelled scene task leaves it running. Asserted by cancelling a scene-shaped task
  and observing the tracker still advancing.

### The pane's states

- **A27 (T)** Each of the nine states renders its specified copy, driven by constructed inputs
  rather than by a live router.
- **A28 (T)** The offline pane still renders the Menu bar and Control token groups — the partial
  rule — and does not render a router value it does not have.
- **A29 (T)** The loading skeleton's row height equals the populated row height, so the card does
  not resize when values land.
- **A30 (M)** In the running app, Settings renders its four group headers and the Router card's four
  labels, read over the accessibility plane by pid, with the app never activated.

### The floor

- **A31 (T)** No raw geometry literal appears in any view M8 adds. Every value comes from
  `ColorToken` / `TypeToken` / `MetricToken`, or from **one** board-local metrics type
  (`SettingsMetrics`, `PopoverMetrics`) following the precedent `ServersBoardMetrics` set for M3 —
  which exists because `MetricToken` tokenises only the *leading* scalar of each documented cell, so
  a concentric child radius of 14, a 26pt popover row, a 32pt settings row and a 150pt label column
  have no token to read. Those four are named constants **in one place each, derived from a token
  where one exists**, and the clause asserts that the views themselves contain no bare number.
- **A32 (T)** No indicator colour is used decoratively. **All four** — `--accent`, `--live`,
  `--attn`, `--fail` — appear in M8's views only in the meanings §2 assigns them. `--attn` is named
  explicitly because it is this item's busiest colour and so the one most likely to be reached for
  as decoration.
- **A33 (M)** `make all` is green — typecheck, lint, format, and the full test suite with a non-zero
  test count.

---

## Recorded deviations from `DESIGN.md`

`DESIGN.md` is named at the top of this spec as the authority for anything that renders. Three
places depart from it. Each is argued rather than asserted, and recorded here rather than left for a
reader to discover — the spec gate found all three as unrecorded overrides, which is the right
verdict on a silent departure however good its reasoning.

**§5 Offline: "say so *and offer to start it*". M8 says so and offers nothing.**
`ControlAPIError.actionLabel` ships the string "Start the router" (`ControlAPIClient.swift:81`) and
**nothing in the merged tree renders it as an action** — M3's banners show headline and advice only.
There is no launch path in either app: `RouterCore` is linked by neither, and spawning
`node dist/index.js` from the app would be the second channel the standing constraints forbid.
A button that cannot start anything teaches the user that the app's buttons do not work, which costs
more than the missing affordance. The deviation is bounded and reversible: when a start path exists
— R-lane, the launchd agent R2R made opt-in — this is one button in two surfaces, and the copy is
already written. Consistent with M3, so the two surfaces do not disagree.

**§5 Empty: "an illustration, one sentence, one action — never a bare 'No items'".**
Settings has no whole-pane empty state: it has four groups, of which at most one is ever empty at a
time, and an illustration for a pane that is three-quarters populated would be furniture. The rule's
intent — never a bare "No items" — is met per group: the empty Warm set gets a sentence saying what
happens instead and an action (**Show in Servers**) that leads to where the state is changed. The
popover's empty log gets a title and a sentence and no action, because there is no action: calls
appear when a session makes one, and a button that cannot cause that would be decoration.

**§5 Overflow: "long names truncate with the full value in the inspector".**
Settings has no inspector — it is a single-column pane, and adding one for two truncated strings
would be a large surface for a small problem. The full value is instead reachable in place: a
truncated warm-set chip and a truncated token path both carry the complete string in their help tag
and in their accessibility value, so it is available to pointer and to VoiceOver alike. The rule's
intent is that truncation never destroys information; that holds. The letter of it names a surface
this pane does not have.

**Not a deviation, but argued because the gate asked: §3.9 and the pane's two buttons.**
"The menu bar is the complete command surface" governs *commands* — the operations the app performs
on the user's behalf, which is what a menu item can name and a keyboard shortcut can reach.
**Show in Servers** is navigation within the window, which macOS does not put in menus (no app lists
"go to the third row of the sidebar"), and the destination it navigates to already has its own
`⌘2`. **Forget the stored token** is a maintenance action on a credential this Mac holds; it has no
menu item for the same reason M3's **Accept the new text** has none — it acts on the thing currently
in front of you and is meaningless without it. The precedent is M3's, and it is deliberate there
too. What §3.9 would forbid is a command reachable *only* by a shortcut, or a pane action with no
visible affordance; neither applies.

---


**D1 — the sheet is M3's; the schema half of its diff is M8's.** Evidenced above. M8 adds the
missing field and the reachability, and rebuilds nothing. This is the item's largest scope decision,
and the first draft of this spec got it wrong in the other direction — it certified the quarantine
surface as complete because the description diff was complete. The correction came from the spec
gate.

**D2 — Router settings are read-only.** There is no control-API write path and creating one would
be R-lane work; writing `servers.json` from the app would be a second channel, which the standing
constraints forbid outright.

**D3 — Absent, not disabled, for mechanisms that do not exist.** Disabled-in-place is for a control
whose mechanism exists and is momentarily unavailable. A dimmed control for a mechanism that was
never built asserts that it exists. RAM budget, auto-update and install targets are therefore filed
as children rather than drawn dim.

**D4 — A checkbox, not a new menu command.** The prototype puts "Show Menu Bar Popover" in the View
menu. A menu item that opens a popover anchored to a status item is a command whose target may not
exist, and §3.9 would then want the popover itself to be a command. The checkbox breaks that loop,
matches where a Mac user looks (System Settings does the same for Wi-Fi and Bluetooth), and adds
nothing to `MenuCommand` while other runners are editing it.

**D5 — Settings stays a sidebar destination.** M1 named M8 as the item that might move it to its own
scene. It does not: a separate scene needs its own poller for data the shell already has.

**D6 — "Reset call history" is not in this item.** The prototype puts it in Settings' Danger group
and it would fit. M2's spec already filed it as child **M2a** together with a new File-menu command
(`spec-M2.md:365`). Shipping the button without the command breaks §3.9; shipping both means editing
`MenuCommand.swift` while M4 is in it. Left to M2a and reported.

**D7 — The bar's dot is one colour.** Argued both ways. Two colours would let a glance distinguish
"broken" from "wants a decision", but a 16pt glyph carrying a two-colour code is a code nobody
learns, and both conditions resolve the same way — a human decides. The popover has room for a
sentence and uses it.

---

## Out of scope, and filed as children

| Suggested id | Title | Depends on | Why it is not here |
|---|---|---|---|
| **M8a** | Warm-set memory budget — serve `residentMb()` on the wire, add an eviction-by-budget mechanism, then a control | R-lane + M8 | `residentMb()` has zero callers and never reaches the wire; there is no budget mechanism to control |
| **M8b** | App auto-update — an updater, then its policy control | M8 | no updater exists in the app at all |
| **M8c** | Per-client install targets — a control-API endpoint (or an explicit second-channel decision), then the pane group | R-lane + M5 + M8 | `ClientConfigs` lives in `RouterCore`, linked by neither app deliberately; write-back is called out in its own doc comment as a later item |
| **M2a** | Reset call history — the dialog plus its File-menu command | M2, M1 | already filed by M2; would fit this pane's Danger group |
| **M8d** | Capability-update promotion policy (the prototype's three "Updates" toggles) | M4, M7 | no skills or marketplace model and no endpoint behind any of them |

Paired-device management is **M6's** by its own brief and is not filed here.

---

## Shared-surface changes this item makes, and why each is unavoidable

| File | Change | Why |
|---|---|---|
| `MCPRouterUI/Shell/ScaffoldPane.swift` | `BoardRegistry.installed` gains `.settings` | Anticipated by its own doc comment: "M2–M8 each add exactly one entry here". Without it the pane exists and the user still sees a placeholder. |
| `MCPRouterKit/Control/ServerStateTracker.swift` | `TrackerState` gains `port` and `since`, retained across failure | Additive, and it follows the precedent `idleMs` already set in the same type for exactly this reason. The alternative — a second poller in Settings for data the tracker already fetches — is worse. |
| `MCPRouterUI/Shell/ShellModel.swift` | `startPolling()`, idempotent and retained on the model | The menu bar is live while the window is closed, and the poll was owned by the window's `.task`. Argued in full above. |
| `MCPRouterUI/Shell/ShellWindow.swift` | one branch in `pane` for `.settings`; its `.task` calls `startPolling()` instead of owning `run()` | The same one-branch addition M3 made for `.servers`, plus the poll-ownership change. |
| `MCPRouterUI/Boards/ServerSheets.swift` | `ToolChangeCard` gains the schema half of the diff | The router quarantines schemas and this card reviewed only descriptions. **Confined to that one view**; nothing else in the file is touched, and A26 measures that. |
| `MCPRouterUI/Icon.swift` | one case for the cold-start marker | `DESIGN.md` §4: drawn, never unicode. A literal ❄ in a status-adjacent surface is the web tell §3 exists to remove, and `Icon` is the registry every other glyph in the app is addressed through. |
| `MCPRouter/MCPRouterApp.swift` | a `MenuBarExtra` scene | Assembly only; the popover's content and every decision in it live in `MCPRouterUI` where tests reach them, consistent with that file's stated rule. |

**No shared design token, base control, or `MenuCommand` entry is touched.** The two entries above
that are not one-line registrations — the tracker's retained facts and the poll's ownership — are
each argued in their own section rather than listed and hoped for.

---

## Assumptions

- **The app is "MCP Router", not "Conduit".** The prototype still says Conduit throughout;
  `CFBundleName` and the brief agree with this spec, and DESIGN.md's precedence rule makes the
  prototype stale where it disagrees. M1 recorded the same assumption.
- **`Counting since` replaces the prototype's `Started — 3d 4h ago · pid 41208`.** The router serves
  no start time and no pid on any endpoint; that row is two invented numbers. `since` is real.
- **The keychain error copy carries an OSStatus.** It is the one detail a support conversation
  needs, and it is not a secret.
- **`cold` is shown.** `CallRecord.cold` is on the wire, so the cold-start marker is an observation
  rather than a decoration — and it is the one column that explains why a call was slow.

---

## The spec gate — in-family, and what it found

**`codex: usage limit → claude (downgrade)`.** The out-of-family reviewer was unavailable for this
fleet: every `codex exec` call, down to a one-word probe, returns
`You've hit your usage limit … try again at Aug 20th, 2026 1:29 PM`. That is account-level and past
this fleet's horizon, so the gate ran as a fresh `claude -p` opus-5 reviewer briefed adversarially —
told to refute, and that an inability to find defects is a failed review rather than a pass. The
weakness travels with the evidence: every reviewer in this item's pipeline is Claude auditing
Claude, and on this occasion it still found the thing that mattered.

**Round 1 verdict: REJECT — ACCEPT 7, REJECT 15.** It was right about the two that mattered, and I
verified both against the source before acting rather than taking them on the reviewer's word:

- **Finding 1 (disqualifying, upheld).** The router quarantines **descriptions and input schemas**
  (`src/manifest.ts:80-93`); `ToolChangeCard` rendered only descriptions. A schema-only rewrite drew
  two identical fields and no indication of change. The first draft of this spec certified that
  surface as complete. It was a gap disguised as a scope decision, which is exactly what the
  reviewer was pointed at. The spec now ships the schema half (A27a–A27d).
- **Finding 2 (disqualifying, upheld).** `ShellModel.run()` is driven only by `ShellWindow`'s
  `.task` (`ShellWindow.swift:45`), so a menu-bar app with its window closed has no poller. The spec
  now specifies an app-lifetime poll (A27e, A27f) and records the reversal of M1's rationale.

The other thirteen, and what each produced:

| # | Finding | Disposition |
|---|---|---|
| 3 | A31 unsatisfiable — 14, 26, 32, 150 have no `MetricToken` | **Upheld.** A31 rewritten around a board-local metrics type, following `ServersBoardMetrics`' precedent. |
| 4 | Offline omits §5's "offer to start it" with no deviation filed | **Upheld.** Now a recorded deviation, argued. |
| 5 | A24 cannot detect a sheet opened without its diff loaded | **Upheld.** A24 now asserts the loaded diff too — the failure it names lands the one press this item exists for on a dead sheet. |
| 6 | A3 falsified by its own table — Home is not from the response | **Upheld.** A3 narrowed to the served rows; Home asserted separately. |
| 7 | A18 not falsifiable at evidence type (T) | **Upheld.** The band is now a nil-versus-empty value, which a unit test can tell apart. |
| 8 | `starting`/`stopping` unallocated between the header's two buckets | **Upheld.** A16b added; idle means *not running*, and the counts must sum. |
| 9 | Error state recolours the band `--fail`, breaking §2 exclusivity | **Upheld.** A19b added; the stale notice is its own row and the band keeps its causes' tints. |
| 10 | The brief's three deep links neither shipped nor filed | **Partly upheld** — see below. |
| 11 | Empty and Overflow deviate from §5 unrecorded | **Upheld.** Both now recorded and argued. |
| 12 | A32 omits `--attn`, this item's busiest colour | **Upheld.** All four indicator colours now named. |
| 13 | A26 typed (T) but rests on a completion note | **Upheld.** Retyped **M**. |
| 14 | §3.9 asserted rather than argued for the pane's two buttons | **Upheld.** Argued in the deviations section. |
| 15 | Glyphs specified as literal Unicode against §4 | **Upheld.** Named as `Icon` cases; the cold marker adds one case to the registry. |

**On finding 10, the deep links.** `?only=mac&pane=settings`, `?popover=1` and `?sheet=held` are
query parameters of `design/mocks/prototype.html`, not of the app — the Mac app has no URL scheme
and this item does not add one. They were used: all three were rendered during the design stage and
two of them carry real prototype content, which is how the popover's and the held sheet's copy was
grounded. The third, `pane=settings`, renders a settings pane whose four groups are **Router,
Updates, Paired devices, Danger** — three of which this item does not ship, for the reasons in §10
of the design representation. Recording that explicitly rather than leaving the omission silent is
the right response to this finding; filing a child for "add a URL scheme to the app" is not, because
nothing asked for one.

Round 2 was re-run against this amended spec; its verdict and tally are in
`planning/evidence/M8-acceptance.md`.

