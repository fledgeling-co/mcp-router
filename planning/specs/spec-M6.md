# M6: Inbox and pairing (Mac)

| | |
|---|---|
| Status | In Progress |
| Item | M6 — the eighth and last Mac board |
| Deps | M5 ✓ (merged `2a81c87`) · M1 ✓ · I1 ✓ (merged `d582d43`) |
| Branch | `ai/m6` · worktree `.worktrees/M6` |
| Mock | `design/mocks/prototype.html?pane=inbox`, `?sheet=pair` |
| Design authority | `DESIGN.md` — §5 states, §6 words, §7 motion, §8 keyboard, §9 forgiveness |
| Out-of-family gate | `codex: usage limit -> claude (downgrade)` — the codex account limit runs to 2026-08-20, past this fleet's horizon (ORCHESTRATOR contract). Every gate here is an adversarially-briefed `claude -p` opus-5 reviewer. |

---

## Feature description

The Mac's Inbox pane, and the Mac half of pairing.

The phone **queues; it never installs** (`DESIGN.md` §9). Pairing grants a remote party the ability
to put executable code on a laptop, so what the phone sends is a *request*, and the Mac is where a
queued item is accepted or rejected. That boundary is a product decision, not an accident, and every
line below is written to keep it: nothing the phone sends is trusted to describe itself, and nothing
arrives installed.

This item ships the last board. When `.inbox` is registered, `BoardRegistry.installed` covers every
`Destination` and the placeholder sentence leaves the product.

---

## Scope: two surfaces and the Mac-side session logic, and no transport

M6 does **not** build a network transport, and the wave-6 exit gate *"Phone → Mac inbox round-trip
works end to end"* is **NOT met by this item.**

The reason is **scope, not impossibility**, and the first draft of this spec got that wrong. I1
shipped `protocol PairingService` precisely so a live implementation could be *added*; a
`LivePairingService` conforming to that merged public API would edit none of I1's files. So "a
second writer on merged phone code" was never the obstacle. The obstacle is that a transport is a
different item — a listener, a client, a TLS identity, a device-record store — and none of that is
"the Inbox pane and the pairing sheet".

Measured, not assumed:

| Fact | Evidence |
|---|---|
| No listener exists in either app target | `NWListener`/`NWConnection`/`NetService` appear only in `RouterCore` and `MCPRouterCLI`; neither app target links `RouterCore` |
| The phone has no network client either | I1 shipped `FixturePairingService` only, by decision |
| The wire *is* fixed | `PairingPayload` (`t: "mcp-router-pair"`, `v: 1`, `code`/`mac`/`exp`/`host`/`port`/`fp`) and `PairingCode` (8-char Crockford Base32) |

The transport is deferred child **D-m6-a**, with its mechanism.

---

## The QR must not encode an endpoint that does not exist

`PairingPayload` requires `host`, `port` and `fingerprint`. With no listener bound, a Mac that
rendered a QR today would encode **a port nothing answers on and the fingerprint of no certificate**.
That is worse than an ordinary fabricated number because it is *actionable*: a phone scans it, stores
it, and reports "Paired." for a Mac it can never reach.

So **the endpoint is an input, never something the sheet invents**, and its absence is a designed
state. `PairingEndpoint` is failable against exactly the constraints `PairingPayload.validated`
enforces, so an endpoint that could not produce a decodable payload cannot be constructed at all —
the check sits one layer earlier than the encoder, where a test reaches it without a QR.

- **`.noEndpoint`** → no code is issued, no payload is encoded, no QR is drawn. The sheet renders
  the *no pairing endpoint* state.
- **`.available(endpoint)`** → the whole session runs: code issued, payload encoded, countdown live,
  one code pairs one device, request accepted or refused by a human.

**In a Release build today the sheet's only reachable state is `.noEndpoint`, and the Inbox is
always empty.** That is the truth about this build, and rendering it is the point.

---

## The Debug lanes, declared by name

The spec gate's fair complaint about the first draft was that eleven of eighteen state-matrix cells
had no named lane. They are named here. Both follow `ShellClientFactory`'s existing rule verbatim —
**a Release build may never render a fixture, and the Release branch takes no input** — so no
environment variable can talk a shipped build into drawing a QR or filling an inbox.

| | |
|---|---|
| Factory | `ShellPairingFactory` — `app/Sources/MCPRouterUI/Shell/ShellPairingFactory.swift` |
| Env variable | `MCPROUTER_PAIRING`, Debug only |
| Release behaviour | `.noEndpoint` and an empty inbox, unconditionally, ignoring the environment |
| Inbox seam | `protocol InboxService` + `FixtureInboxService` — `app/Sources/MCPRouterKit/Inbox/` |

`MCPROUTER_PAIRING` scenarios, one per otherwise-unreachable matrix cell:

| Scenario | Drives |
|---|---|
| `none` (default) | `.noEndpoint`, empty inbox — what Release does |
| `paired` | An endpoint, a live code, a populated inbox |
| `pairedEmpty` | An endpoint and a live code, nothing queued |
| `loading` | The inbox's Loading state |
| `expiring` | A code within seconds of expiry, for the countdown and the expired branch |
| `partial` | One queued item whose registry entry cannot be read |
| `failed` | The inbox read failed |
| `overflow` | A queued item with a name long enough to truncate |

Every matrix cell below is marked with the scenario that reaches it. A cell with no scenario is a
cell with no evidence, and there are none.

---

## What the phone is allowed to say about an item

The gate's sharpest finding was that a fixture inbox would invent a content model — the thing I1
refused to do — and that a future phone item (I3) would have to match a schema M6 made up.

**The phone sends a coordinate, never a description.** The Mac reads the registry entry itself and
derives the capability statement with M5's existing `RegistryCapability.statement(for:)`. The phone
never gets to say what a thing does — so a compromised or spoofed sender cannot present `rm -rf` as
"read-only", and the fields I3 must produce are five facts it already holds, none of them a
judgement.

### The envelope, specified

Decoded in two passes with a named failure per shape, exactly as `PairingPayload` is, and never
`try?`-and-default (`SWIFT_PRACTICES.md` §2).

| Key | Type | Meaning |
|---|---|---|
| `t` | String | Discriminator — `"mcp-router-queue"`. Anything else is not ours. |
| `v` | Int | `InboxEnvelope.supportedVersions = [1]`, a closed set |
| `id` | String | The item's stable identity, minted by the phone. Row identity comes from this. |
| `entry` | String | The registry entry id. **This is the coordinate the Mac resolves.** |
| `name` | String | The name the phone displayed. Rendered **only** when the entry cannot be read, so a Partial row still says which thing it is; otherwise the Mac shows what it read. |
| `queued` | String | ISO-8601 instant, parsed with `ISO8601Instant.parse` — the same tolerant parser I1 needed for the fractional-second form. |
| `device` | String | Which paired device sent it. |

| Failure | When |
|---|---|
| `notAQueueItem` | Unparseable, or `t` is not the discriminator |
| `unsupportedVersion(found:)` | Ours, a version this build does not speak |
| `malformedPayload(detail:)` | Ours and our version, body missing/mistyped/empty — the field named |

**Registered as a risk rather than waved away:** the consumer is defining the wire and the producer
is not, which reverses I1's direction. The precedent for doing it anyway is I1 itself, which fixed
`PairingPayload` — the thing the *Mac* produces — from the phone side, because the consumer needed
something exact. **D-m6-b** records that I3 may amend it, and that it does so by adding to
`supportedVersions` rather than widening v1: the closed set is what makes an unknown version a named
failure instead of a silent empty read.

---

## `.versionMismatch` is not a Mac surface

`PairingOutcome.versionMismatch` is the **phone's** reading of a Mac speaking a version it does not
know. The Mac never submits an attempt, so there is no Mac screen for it, and building one would be
dead code dressed as state coverage.

The Mac's mirror *is* reachable and is modelled as `PairingRefusal.unsupportedVersion(found:)` — a
rejection the Mac decides, not an outcome it suffers. `PairingPayload.supportedVersions` stays the
single closed set both sides read.

---

## The Inbox pane

### Header

Title `Inbox`. Subtitle is one line, sentence case, and **every part comes from state** — the
prototype hardcodes `paired with Luke's iPhone`, and a build with no pairing must not claim one.

| Condition | Subtitle |
|---|---|
| Nothing paired | `Nothing waiting · no phone paired` |
| Paired, empty | `Nothing waiting · paired with <name>` |
| Paired, populated | `<n> waiting from <name>` |

Trailing: one quiet `Pairing…` button. The ellipsis is load-bearing (§3.4) — it opens a further view.

### Rows

One row per queued item, 56pt, **identity from the envelope's `id`** (`SWIFT_PRACTICES.md` §4 — this
list reorders as items arrive and are dispositioned).

| Zone | Content |
|---|---|
| Tile | The registry entry's artwork, or its drawn monogram plate (§4). Never a gradient rectangle. |
| Name | The entry name, `--t1`; beneath it `queued <relative> · <device>` in `--t3` |
| Capability | The **headline** of `RegistryCapability.statement(for:)` |
| Eval | M7's evaluation vocabulary, unchanged, or "not evaluated" |
| Actions | `Review…` (opens the sheet) and `Decline` |

**The prototype paints "wants shell + network" in `--fail`.** That is an indicator colour used
decoratively, which §2 forbids outright — `--fail` means "failed or tripped", and a capability
description is neither. `DESIGN.md` §10 already records the prototype doing this on phone Discover;
this is the same defect on this pane, and it is not reproduced. The capability reads as text in the
label tiers, exactly as M5's declaration sheet renders it.

### The review sheet

M6's own file, which **calls** M5's `RegistryCapability` rather than editing M5's sheet. Two
additions over the declaration surface:

1. A provenance line — *"Sent from your iPhone. It has been sitting in the inbox and has not run."*
   The tense is the guarantee the queue exists to make.
2. `Decline` alongside the commit action. Cancel leads; the destructive action is never the
   default (§3.4).

Accepting calls `ControlAPIClient.add(_ server: NewServer, force: false)` — **once**, with `force`
never `true`, for exactly M5's reason: `force: true` adopts an existing declaration, which would let
a row that arrived from a phone replace the command line of a server the user already trusts.

### Empty state

Illustration, one sentence, one action (§5) — and the sentence is the product's own argument:

> **Nothing waiting**
> Things you send from your phone land here. The phone can queue and nothing else — a lost or
> unlocked phone still cannot install code on this Mac.

### Undo (§9)

Both dispositions are reversible, through the `.undo` menu command that already exists on `⌘Z`.
Single-slot: the board holds the last disposition and nothing older, because a deeper stack would
promise a history this surface does not keep. Declining returns the item to the queue; accepting
removes the server that was added. Each is *reported* in place — a quiet secondary line under the
list — never a toast (§5 Success: macOS does not toast a click).

---

## The sidebar badge — an amendment to M1, and the argument the gate corrected

`Destination.inbox.badgeSource` is `nil` today. After this item **the app itself holds the queue**,
so `BadgeSource` gains a case naming that queue, and the doc comments on `BadgeSource` and on
`badgeSource` — which currently say every case names a field the router serves on `MCPServer`, and
that `ShellDestinationTests` fails if that stops being true for Inbox — are corrected rather than
left to read falsely.

Both mocks draw this badge, and `mac-surfaces.html` names its motion — *"Inbox arrival: the sidebar
badge scales 1 → 1.25 → 1 once"* — which is `DESIGN.md` §7's badge row. An inbox that fills with
nothing to notice it is a real gap: it is the one surface a user has no reason to visit
speculatively.

**The gate was right that the first draft's argument was wrong, and it is withdrawn.** That draft
cited `.cleanup` as a precedent for a fixture-derived count. It is not one: `.cleanup` counts
`MCPServer.neverUsed`, a field the router genuinely serves, and the fixture merely stands in for the
router. An app-held queue has no router field behind it, which is exactly the distinction the doc
comment draws.

The argument that does hold is narrower. §6 forbids a number **nobody observed** — its example is a
memory saving computed against a world the router never runs, a figure with no measurement anywhere
behind it. An inbox count is not that: its observation is the queue itself, which the app holds and
is rendering on the same screen. The rule the objection is really protecting is that the count and
the list must not be able to disagree, and that is honoured **structurally** — `badge(for: .inbox)`
reads the inbox model's own items, so there is one source and no second derivation to drift. A18
asserts it.

`Destination.inbox.badgeCount(from: [MCPServer])` stays `nil`, and its existing assertion keeps its
teeth — it now says something stronger, that an inbox badge is *not* derived from server data.

---

## The pairing sheet

`Pair iPhone…` already exists as `MenuCommand.pairPhone` and routes to `.none`; M6 wires it.

### With an endpoint

- Title `Pair iPhone`, lede naming the phone-side path, matched to **what I1 shipped** rather than
  to what the mock drew.
- The QR, encoding exactly `PairingPayload`'s bytes.
- The code beneath it, monospace, `XXXX-XXXX` — `PairingCode.formatted`, not a second formatter.
- The warning in `--attn`, because it *is* asking for a human decision: *"Treat this code like a
  password. Anyone who scans it can put items in your inbox until it expires."*
- The countdown — an **observed** expiry, since this Mac issued it.
- `Can't scan? Type a code` — the path for a phone that cannot use its camera.

### Without an endpoint

Names what is missing and what provides it, adjacent, non-blaming, not emoting (§5, §6). No code, no
QR, no countdown — there is nothing observed to count down.

### One code, one device

`MacPairing.decide` enforces it, and checks **spent before live**: a code that was used and then
re-submitted must say `alreadyUsed` rather than `notRecognised` once the next code has replaced it
on screen, because the two send the user to different places.

---

## The nine states (§5), with real copy and their lanes

`Offline` carried two different conditions in one row in the first draft. The gate was right; it is
two rows.

| State | Inbox | Scenario | Pairing sheet | Scenario |
|---|---|---|---|---|
| Default | Queued items, newest first | `paired` | Code, QR, live countdown | `paired` |
| Empty | "Nothing waiting" + the queue's argument | `pairedEmpty` | — | — |
| Loading | Skeleton rows at the real 56pt geometry, never a spinner | `loading` | "Preparing a code…" | `loading` |
| Partial | Items whose registry entry could not be read still list, saying so, and **cannot be accepted** | `partial` | — | — |
| Error | The named decode failure next to the item; the item is held, never dropped | `failed` | The named issue failure | `failed` |
| Success | In place — the row leaves the list, no toast | `paired` | "Paired with `<name>`." in place | `paired` |
| Offline — router not running | "The router is not running, so nothing can be installed." Items still list; accept dims with that reason | `failed` | — | — |
| Offline — no pairing endpoint | — | — | **The state a Release build reaches**: pairing needs the endpoint the transport item brings | `none` |
| Disabled | Accept dims in place with a discoverable reason (offline, or unreadable entry) | `partial`, `failed` | Commit dims until eight characters are entered | `paired` |
| Overflow | Long names truncate with the full value in the sheet; **rows never change height** | `overflow` | A long Mac name truncates; the code never wraps | `overflow` |

---

## Keyboard (§8)

| Key | Behaviour |
|---|---|
| `⌘5` | Select Inbox — already bound by `Destination.selectionDigit`, unchanged |
| `⌘Z` | Undo the last disposition — the existing `.undo` command |
| `Return` | Commits the view's one default action: opens `Review…` for the selection |
| `Esc` | Dismisses the sheet, then clears selection |

**`⌘⌫` is deliberately not bound here, and the first draft was wrong to bind it.** §8 gives `⌘⌫` to
"Remove the selected server". Binding the same chord to Decline on another board teaches two habits
for one chord — the precise reason `Destination.selectionDigit` gives Settings no digit, since §8
already binds it to `⌘,`. Decline stays a row action and a menu item. The gate caught this.

The menu bar is the complete command surface (§3.9): every command above is reachable from it.

---

## The placeholder retires, and `ScaffoldPane.swift` survives

The gate's first finding was the most consequential, and the first draft was flatly wrong: it said
the Release gate *required* deleting the file, when deleting the file **blocks** that gate.

Both readers point at this one path. `scripts/acceptance/mac-shell.sh:884-886` greps
`sentinel = "…"` out of `ScaffoldPane.swift` and calls `blocked` when it is absent;
`board-registry.sh` reads `installed` from the same path, and `:919-924` blocks on a count of zero.
Four other acceptance scripts read it too. So:

1. **`ScaffoldPane.swift` keeps its path and its name**, and keeps `BoardRegistry`. A file named for
   a view it no longer contains is a wart, and it is the cheaper of the two available warts —
   renaming it means editing five other items' acceptance scripts in this item's diff, which
   `CODING_PRACTICES.md` §5 forbids and this runner's brief forbids by name. **D-m6-c** registers the
   rename for whoever can move the scripts in the same change.
2. **`ScaffoldedDestination`, `ScaffoldCopy` and `ScaffoldPane` are deleted.** With every destination
   installed, `mac-shell.sh:954` fails a Release bundle that still contains the sentence, and a
   compiled `ScaffoldCopy.sentinel` is that sentence.
3. **The sentinel survives as a comment**, in the exact `sentinel = "…"` shape the gate's reader
   matches. A comment is not compiled, so the gate can still read the string it must grep the bundle
   for, and the bundle no longer contains it — which is what lets the `:952` else-branch be reached
   at all instead of blocking at `:886`. No other item's script is edited.

### Every test this touches, enumerated

| File · test | Disposition |
|---|---|
| `ShellIntegrationTests.installedAndScaffoldedAreComplements` | **Re-pointed.** Disjointness against an empty set is vacuous. Becomes `installed == Set(Destination.allCases)` — which still fails if a `Destination` is added and not registered. |
| `ShellIntegrationTests.installedIsTheShippedSet` | **Amended.** Set becomes all eight; the `scaffolded.count == 1` line becomes `installed.count == Destination.allCases.count`. Still a deliberate edit. |
| `ShellIntegrationTests.scaffoldRefusesAnInstalledDestination` | **Replaced.** Its subject type is gone. Becomes a source-level test that the placeholder sentence appears in no compiled string in `MCPRouterUI`. |
| `ShellIntegrationTests.scaffoldCopyIsHonest` | **Replaced.** `try #require(scaffolded.first)` has no subject. Becomes the assertion that no scaffold type exists and none can be reintroduced without failing. |
| `ShellIntegrationTests.serversBoardIsInstalled` · `activityBoardIsInstalled` | **Amended** — the `ScaffoldedDestination` lines go; `hasBoard` and the complement remain. |
| `ActivityBoardContractTests.registryIsTheShippedSet` | **Amended.** The set and count update; `ScaffoldedDestination(.inbox) != nil` is deleted, as its own comment instructs. |
| `SettingsAndMenuBarTests.settingsIsInstalled` · `DiscoverBoardTests.discoverIsInstalled` | **Amended** — same two lines each. |
| `ServersBoardSurfaceTests` (`installedDestinations == BoardRegistry.installed`) | **Unchanged.** Still true, still real. |
| `ShellTestSupport.shellFiles` / `shellFileListIsComplete` | **Amended** — `ScaffoldPane.swift` stays (the file survives); M6's new Shell files are enrolled. |
| `ShellDestinationTests.badgeSourcesAreOnlyWhatTheRouterObserves` | **Amended** — Inbox's source is no longer `nil`; the test asserts the new invariant and keeps the `badgeCount(from:)` assertion. |

---

## Acceptance criteria

Rewritten after the gate: the first draft's criteria were largely satisfiable by an empty tree or by
I1's merged code alone. Each below names an M6 type or asserts a positive.

### The board is installed, and the placeholder is gone

- **A1** `BoardRegistry.installed.contains(.inbox)`; selecting Inbox renders `InboxBoard`.
- **A2** `BoardRegistry.installed == Set(Destination.allCases)`.
- **A3** `ScaffoldedDestination`, `ScaffoldCopy` and `ScaffoldPane` do not exist in `MCPRouterUI`;
  no compiled string in the module contains the sentence; `ScaffoldPane.swift` still parses for both
  script readers.
- **A4** The running app's accessibility tree contains no node whose value carries the sentence,
  **and** Inbox's pane exposes `InboxBoard`'s own header — so the check cannot pass on a blank pane.

### Nothing is displayed that was not observed

- **A5** *Positive.* Given `.available(endpoint)`, `MacPairing.issue` returns a code and
  `MacPairing.encode` produces bytes carrying that exact code. Given `.noEndpoint`, the sheet's state
  is the no-endpoint one and neither function is called.
- **A6** `ShellPairingFactory.choice(isDebugBuild: false, environment:)` returns `.noEndpoint` for
  **every** value of `MCPROUTER_PAIRING`, including each named scenario.
- **A7** No `host`, `port` or `fingerprint` appears in any rendered string or log line, asserted by
  scanning M6's own view sources for the accessors.

### The wire is I1's, not a second one

- **A8** *Positive.* A code from `MacPairing.issue` round-trips through `PairingCode.init?(_:)` and
  contains none of `I`, `L`, `O`, `U` — over many generated codes, not one.
- **A9** *Positive.* `PairingPayload.decode(MacPairing.encode(payload))` equals the input payload,
  field for field. **Labelled wire-format conformance**: it proves codec agreement, not delivery.
  Calling it the round-trip would be a fake gate.
- **A10** `MacPairing.decide` returns `.unsupportedVersion(found:)` for a version outside
  `PairingPayload.supportedVersions`, `.alreadyUsed` for a spent code **even when a newer code is
  live**, `.expired` for a live code past its window, and `.notRecognised` otherwise.

### The phone describes nothing

- **A11** *Positive.* The capability text rendered for a queued item is byte-equal to
  `RegistryCapability.statement(for:)` on the entry the Mac resolved. An envelope carrying extra
  fields contributes no rendered text.
- **A12** A `partial` item renders its Partial copy and its accept control is disabled with a reason.

### The boundary holds

- **A13** *Positive.* Accepting one item calls `add(_:force:)` exactly once with `force == false`,
  counted on a recording double; declining, decoding, loading and rendering call it zero times.
- **A14** Declining returns the item to the queue and accepting is reversible, both through the
  single-slot undo, asserted on the model.

### The sidebar badge

- **A18** `model.badge(for: .inbox)` equals the number of rows `InboxBoard` renders, in every
  scenario including `partial` and `overflow`, and is `nil` when nothing is paired.
  `Destination.inbox.badgeCount(from:)` stays `nil` for any `[MCPServer]`.

### Colour, words and the native floor

- **A15** No M6 view uses `--fail`, `--live` or `--attn` for anything other than its own meaning;
  the prototype's `--fail` capability text is not reproduced. Asserted by scanning M6's sources.
- **A16** Sentence case throughout; one prominent accent action, trailing; Cancel leads.

### The states

- **A17** Every cell in the matrix is reached **in the running app** under its named scenario, and
  its real copy is read back from the accessibility tree.

---

## What this item does not do

| # | Deferred child | Mechanism |
|---|---|---|
| D-m6-a | The pairing transport | A listener on the Mac and a `LivePairingService` on the phone, plus a TLS identity whose fingerprint is what `PairingPayload.fp` finally carries. Additive to I1's merged protocol. **Until it lands the wave-6 round-trip gate is unmet and the sheet's only Release state is the no-endpoint one.** |
| D-m6-b | I3 may amend the inbox envelope | M6 writes the wire because the consumer needed something exact, reversing I1's direction. A new field bumps `supportedVersions` rather than widening v1 — the closed set is what makes an unknown version a named failure instead of a silent empty read. |
| D-m6-c | Rename `ScaffoldPane.swift` | It now contains `BoardRegistry` and no pane. The rename must move `mac-shell.sh`, `m2-activity.sh`, `m5-discover.sh`, `m7-evals-cleanup.sh` and `m8-settings-menubar.sh` in the same change, which is five other items' files and out of scope here. |
| D-m6-d | The menu-bar popover has no inbox band | The prototype draws one (*"N queued from iPhone"*); M8's shipped popover has no inbox reference at all. M8's surface, registered so it is not mistaken for something M6 dropped. |

---

## Spec gate

`codex: usage limit -> claude (downgrade)`. Two adversarial in-family reviews ran: one on the scope
decision before drafting, one on the full spec. Verdicts **AMEND** and **AMEND**.

| # | Finding | Disposition |
|---|---|---|
| 1 | Deleting `ScaffoldPane.swift` **blocks** the Release gate rather than satisfying it; A3 was unachievable as written | **Accepted.** File and name survive, placeholder types deleted, sentinel becomes a comment. The reviewer's own fix (move the type, edit five scripts) was rejected — it is a drive-by change to other items' files. |
| 2 | Eleven of eighteen matrix cells had no lane; the fixture inbox was never declared | **Accepted.** `ShellPairingFactory`, `MCPROUTER_PAIRING`, eight named scenarios, every cell mapped. |
| 3 | `Offline` carried two conditions in one row | **Accepted.** Split into two rows with separate copy. |
| 4 | The badge argument was unsound — `.cleanup` counts a router-served field | **Accepted for the argument, rejected for the conclusion.** The `.cleanup` analogy is withdrawn; the narrower argument (§6 forbids an *unobserved* number, and the queue is the observation) stands, and A18 now gates it. |
| 5 | A4–A15 would pass on an empty tree or on I1's merged code alone | **Accepted.** Every criterion rewritten as a positive naming an M6 type. |
| 6 | `⌘⌫` collides with §8's "Remove the selected server" | **Accepted.** The binding is dropped rather than rebound. |
| 7 | The inbox envelope was prose, never specified, yet D-m6-b makes it I3's contract | **Accepted.** Field table, discriminator, closed version set, one named failure per shape. |
| 8 | "A test fails if the type ever regains a case" is incoherent — `ScaffoldedDestination` is a struct | **Accepted.** Reworded to the assertion actually made. |
| 9 | Scope: badge, `BoardRegistry`, review sheet, eval column and menu commands all touched | **Partly accepted.** The badge, `BoardRegistry` and `pairPhone` are genuine edits to M1's surfaces and are registered as such. The review sheet and the eval column are **reuse, not edits** — M6 adds its own file that calls `RegistryCapability`; M5's and M7's files are not modified. |
