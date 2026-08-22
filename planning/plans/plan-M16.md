# plan-M16 — the Signal Path replaces the Breaker Column

**Spec:** `planning/specs/spec-M16.md`
**Brief:** `planning/features-to-triage/M16-signal-path.md`
**Design of record:** `design/mcp-router-console.html` — settled 2026-08-22, recorded in `ORCHESTRATOR.md`'s DESIGN OF RECORD block. Do not reopen it.
**Branch:** `ai/m16` · **Worktree:** `.worktrees/M16`
**Tier:** Large — a new signature element, a new headless geometry type with its own documented table and parity suite, a retirement that reaches twelve source files and six test files, and three edits to M23's gate.
**Base:** `main` at `87e16dc`.

Deliver what is planned below, at the scope stated. Make routine judgement calls yourself and
record them in the branch's progress note; check in only where two readings would produce
materially different work. Delegate to a subagent only for a wide multi-file investigation you
cannot finish in a handful of tool calls, and keep the count at or below two.

---

## What this item is

A **retirement and a replacement, in one change.** `DESIGN.md` §1 already says so in the document's
own words — *"The outgoing signature, recorded rather than deleted: the breaker column … `###
Breaker geometry` below still specifies it value by value and the app still draws it, because M21
authors the token layer and moves no surface. M16 retires both together."* — and the table's own
note names the third thing that goes with them: `BreakerGeometryParityTests`.

So this item does four things, and the order matters because the parity suite's oracle is the
document:

1. Adds `SignalPathGeometry` and its `### Signal Path geometry` table, the direct replacement for
   `BreakerGeometry` and `### Breaker geometry` — same shape, same parity contract, same
   headless-invariants argument.
2. Draws the Signal Path on the Servers board: the hub, the flow arrow, the jack field.
3. Retires the breaker — the drawing, the geometry, the state enum, the document's rows, the
   parity suite — and replaces the row's lever with the mock's row plug.
4. Teaches M23's gate the two control kinds the mock draws here and nothing in the build has ever
   answered, then re-pairs the affordances so the ledger describes what is now on screen.

**The harness column is not built, and §"The harness column" states why with the measurement
behind it.** That is the one part of the brief this item does not deliver.

---

## The decisions taken before writing this, and what they beat

### 1 · `SignalPathGeometry`, not nine new `MetricToken` cases

The spec's out-of-family disposition says the brief's `minimum: 132`, its 20pt arrow and its 0.2s
duration *"route through `MetricToken`"*. They route through a token **layer** — the binding
constraint is `scripts/lint/no-raw-design-values.sh`, whose geometry rule forbids
`.frame(width: 132)` anywhere under `Boards/` — and this plan satisfies it through a value type in
the headless target rather than through nine additions to the chrome ladder.

The repository argues this itself, in the file that would have to carry them:
`app/Tests/MCPRouterKitTests/DesignDocParser.swift:327` gives the reason the breaker got a table of
its own — *"mixing nineteen breaker rows into the chrome ladder would bury the four."*
`MetricToken` is the chrome ladder: titlebar, toolbars, sidebar, the control rungs, the selection
fill. A signature element's construction is not chrome, and `DesignTokenParityTests.metricNameSetsMatchExactly`
compares §2's **Chrome geometry** table against every `MetricToken` case in both directions — so
nine signal-path cases would be nine chrome rows, and every one of them would also need naming in
`MockTokenRegister.metricsTheMockDoesNotDeclare`, because the mock's `mac-craft:metrics` comment
publishes exactly one of them (`jack-lane 44px`).

`MetricToken.jackLane` stays where it is and `SignalPathGeometry` reads it. The lane is authored
once, in the one place the mock publishes it, and the register's `jack-lane` row keeps matching.

### 2 · The harness column is parked, on a measurement rather than on a preference

The brief's first part is *"**Harnesses** — the wired clients, each with a state dot: routed over
HTTP, routed through a stdio shim, or not routed."* **The app cannot observe any of those three
states**, and this is not a judgement call:

- `ControlAPIClient` (`app/Sources/MCPRouterKit/Control/ControlAPIClient.swift:109`) declares
  sixteen operations and none of them is harness-shaped. `src/control.ts` routes `/servers`,
  `/usage`, `/registry` and nothing else; the string `harness` does not occur in it.
- The reading exists, and it is exactly the brief's three states:
  `app/Sources/RouterCore/Discovery/HarnessReconciliation.swift:52` declares `HarnessState` with
  `notWired(overlapping:)`, `wiredViaHTTP`, `wiredViaShim(bridge:)` and
  `wiredWithDuplicates(route:count:)`. But it is in `RouterCore`, which **neither app target
  links**, and it gets there by reading harness config files off disk. (`spec-M22.md`:153 spells
  these `.wired(route:)`; the source is what is quoted here.)
- A board may not go and read them. `no-raw-design-values.sh`'s A36 rule forbids `FileManager`,
  `Data(contentsOf:)`, `URL(fileURLWithPath:)`, `Bundle`, `Process(` and every socket type under
  `MCPRouterUI/Boards`, with the comment *"Reading a file is one of the ways past the API."*
- `spec-M22.md`:154 states it outright — *"**There is no `GET /harnesses`**"* — and M22 absorbs
  `R7-C1`, the route itself.

What **is** observed is `CallRecord.client`, the executable name the router resolves per
connection. It answers "which harnesses have called", which is a different fact: it cannot produce
*not routed* at all, because a harness that has never called cannot appear in a usage log. The one
state carrying the finding is the one state that reading cannot reach.

The repository has already settled the identical question one surface over. `SettingsPaneCopy.harnessesGovernance`
renders the Harnesses **settings** pane as governed-elsewhere with the reason spelled out — *"The
app reaches the router over one loopback channel and that channel serves no harness settings at
all, so there is nothing here it could set."* This is that, on the board.

So the rail is **hub → arrow → jacks**, its topology line reads what the router reports, and the
harness column is recorded as owed to M22's route. Beaten alternative: drawing the column from
observed callers, which fills the picture with a weaker reading of a different fact and hands M22 a
surface to rewrite.

### 3 · `0 at rest` is the warm set

The hub's third line is the product's whole thesis as a live readout, and it must be a number the
router reports. It is **the count of servers marked warm**:

- `src/pool.ts:435` — *"A warm server is one the user has committed to paying for. Reaping it would
  …"* — `if (u?.warm) return;` is the reaper's skip.
- `src/pool.ts:452` — `warmUp()` pre-opens every warm upstream at startup.

So the warm set is the set of children that stay up when nothing is calling, which is what "at
rest" names. It is reported per server on the wire (`MCPServer.warm`), it is not a slogan, and it
is falsifiable: mark a server warm and the hub reads `1 at rest`. It is also why the mock can draw
`0 at rest` beside two live jacks without contradicting itself.

**It is `warm && state == .running`, not `warm` alone** — a correction the out-of-family review
made and the router's own code supports. `warmUp()` at `src/pool.ts:452` *"Failures are logged and
swallowed: a warm server that will not start is a …"*, so a warm server whose process never came up
carries `warm == true` and `state == .idle`. Counting it would put a child in the readout that is
not on the machine, which is the one thing this figure exists not to do. The two facts stay
distinguishable on screen: that server's row still reads `warm · never reaped` and its jack still
draws an unlit plug.

**It is withheld, not zeroed, on a reading that is not current** — the same rule
`ServersBoardHeader.running` already applies, and for the same reason.

### 4 · The jack's five states come from one precedence chain, shared with the row

`ServerSubtitle.forServer` and `BreakerState.forServer` are two orderings of one set of facts, and
the second exists because the lever's meaning is narrower than the subtitle's. The jack's plug has
the lever's meaning exactly — *"lights the moment something calls the server and goes dark when the
reaper closes the child"* — so `JackState` inherits `BreakerState`'s ordering, with `wantsYou`
split into `held` and `needsSignIn` because the mock gives those two different words.

The fifth condition `BreakerState.wantsYou` also covers — an index error — is **unreachable as a
distinct state on the wire**: `placardFor()` in `src/manifest.ts:301` returns the user's placard
first and `{ reason: entry.error }` second, so a server with an `indexError` always arrives
carrying a placard, and the `.tripped` arm above catches it. The plan asserts this over the cross
product rather than asserting the comment.

**The word and the plug take different precedences, and that is the fix the review forced.** The
plug's meaning is narrow — a child is up — so `.live` is `state == .running` and nothing outranks
it. The *word* is what a person reads, and `ServerSubtitle` puts `warm` above `running` for a
reason it states three ways: *"a warm server never shows a reap countdown"*, because the reaper
skips it. A single chain would have drawn `3:41 left` on a warm running server while the hub two
inches above read `1 at rest` — a live contradiction on the signature surface, and the sharpest
finding the review returned.

So the label is computed **from the state plus `warm`**, never from a second precedence chain:

| State | `warm` | Word |
|---|---|---|
| `.live` | yes | `never reaped` |
| `.live` | no | `3:41 left`, or `awake` where the router sent no horizon |
| `.tripped` | — | `tripped` |
| `.held` | — | `2 held changes` |
| `.needsSignIn` | — | `needs sign-in` |
| `.dormant` | yes | `warm` |
| `.dormant` | no | `dormant` |

One chain, seven arms, and no input reaches a countdown with `warm == true` — which is what
`JackPresentationTests` asserts over the cross product rather than over examples, exactly as
`ServerPresentationTests.warmNeverShowsACountdown` already does for the row.

---

## Files

Verified against the tree at `87e16dc`. Paths marked **new** do not exist yet; every other path was
opened.

### New

| Path | What |
|---|---|
| `app/Sources/MCPRouterKit/Design/SignalPathGeometry.swift` | the signature's construction as values, with its invariants and its motion decision |
| `app/Sources/MCPRouterKit/Servers/JackPresentation.swift` | `JackState`, `JackCondition`, the topology line and the at-rest count |
| `app/Sources/MCPRouterUI/Boards/SignalPath.swift` | the rail — head, hub, arrow, jack field |
| `app/Sources/MCPRouterUI/Boards/Jack.swift` | one jack, one plug, one state dot |
| `app/Tests/MCPRouterKitTests/SignalPathGeometryTests.swift` | the construction invariants and the column arithmetic |
| `app/Tests/MCPRouterKitTests/SignalPathParityTests.swift` | the replacement for `BreakerParityTests` |
| `app/Tests/MCPRouterKitTests/JackPresentationTests.swift` | the precedence chain, over the cross product |

### Deleted

| Path | Why |
|---|---|
| `app/Sources/MCPRouterUI/Breaker.swift` | `Breaker`, `BreakerToggle` — the drawing |
| `app/Sources/MCPRouterKit/Design/BreakerGeometry.swift` | `BreakerGeometry`, `BreakerState` |
| `app/Tests/MCPRouterKitTests/BreakerGeometryTests.swift` | the construction invariants of a construction that is gone |
| `app/Tests/MCPRouterKitTests/BreakerParityTests.swift` | named by `DESIGN.md`:385 as retiring with the table |

### Changed

| Path | Change |
|---|---|
| `DESIGN.md` | §1 the outgoing-signature paragraph; §2 `### Breaker geometry` → `### Signal Path geometry`; §2 the `Servers row` cell's derivation; §7 the two breaker rows and the opening line; §10 a row for the parked harness column |
| `app/Sources/MCPRouterKit/Servers/ServerPresentation.swift` | `BreakerState.forServer` → gone; `ServerRowModel.breaker` → `.jack: JackState` |
| `app/Sources/MCPRouterUI/Boards/ServersBoard.swift` | the band above the controls row; `Space` keeps its meaning |
| `app/Sources/MCPRouterUI/Boards/ServersBoardRow.swift` | the lever → the row plug |
| `app/Sources/MCPRouterUI/Boards/ServersBoardTable.swift` | the header gutter reads the plug's slot |
| `app/Sources/MCPRouterUI/Boards/ServersBoardMetrics.swift` | `indicatorColumn` |
| `app/Sources/MCPRouterUI/Boards/ServerInspector.swift` | the inspector's lever → the row plug |
| `app/Sources/MCPRouterUI/StateContainer.swift` | `SkeletonRows` and `OverflowRow` |
| `app/Sources/MCPRouterUI/Shell/Sidebar.swift` | `ShellMotion.badgeBump` reads the plug transition |
| `app/Sources/MCPRouterUI/Gallery/DesignGallery.swift` · `GallerySections.swift` | the Breaker section → the Signal Path section |
| `app/Sources/MCPRouterUI/Icon.swift` | `flow`, the mock's `#i-arrow-r` |
| `app/Tests/MCPRouterKitTests/DesignDocParser.swift` | `breakerRows` → `signalPathRows` |
| `app/Tests/MCPRouterKitTests/MockTokenRegister.swift` | the exemption note stops citing the breaker housing |
| `app/Tests/MCPRouterKitTests/ServerBoardShapeTests.swift` · `ServerPresentationTests.swift` | the lever assertions become jack assertions |
| `app/Tests/MCPRouterUITests/DesignSystemTests.swift` · `ServersBoardSurfaceTests.swift` · `ShellAppearanceTests.swift` | A29, the icon census, the row-height floor, the badge spring |
| `scripts/acceptance/mock_fidelity.py` | `VOUCHED_CONTROLS` gains `jack`, `indicator`, and `signature` under `card` |
| `planning/fidelity/servers.pairing.tsv` | the band, the jacks and the row plugs |

---

## Slices

Each slice is a commit. They are ordered so the tree builds and the suite is green at every one of
them — which is the whole reason the retirement is split across three.

### A · `SignalPathGeometry` and its table  *(no surface moves)*

`app/Sources/MCPRouterKit/Design/SignalPathGeometry.swift`, modelled on `BreakerGeometry` — a
`Sendable, Equatable` value with `standard`, derived properties, invariants as `Bool` properties a
headless test can read, and `documentedValues: [String: Double]` built from the stored properties
rather than retyped.

| Element | Value | Mock |
|---|---|---|
| Signal Path padding | 12pt | `.signalpath{padding:12px 14px 14px}` |
| Jack minimum width | 132pt | `.sp-jacks{…minmax(132px,1fr)}` |
| Jack inset | 10pt | `.jack{padding:0 10px}` |
| Jack gap | 9pt | `.jack{gap:9px}` |
| Jack plug diameter | 16pt | `.jack .plug{width:16px;height:16px}` |
| Jack plug ring | 3pt | `.jack .plug{box-shadow:0 0 0 3px}` |
| Row plug diameter | 8pt | `.dot{width:8px;height:8px}` |
| Hub width | 76pt | `.sp-hub{width:76px}` |
| Flow arrow width | 20pt | `.sp-rail > .flow-arrow{flex:0 0 20px}` |
| Plug transition | 0.2s | `.jack .plug{transition:… 200ms …}` |

`laneHeight` is **not** a row: it reads `MetricToken.jackLane`, which the mock publishes and the
register already matches.

Invariants, each one a failure the mock's own CSS would have produced if written by eye:

- `plugFitsTheLane` — `plugDiameter + ringWidth * 2 <= laneHeight`. A plug whose ring overflows its
  lane clips against the row above, which is the breaker's failure 3 in a new shape.
- `theLabelHasRoom` — `jackMinimum - inset * 2 - plugDiameter - gap` is at least half the jack.
  The brief's second measured constraint is that the sub-label must fit; this is the value form of
  it.
- `theRingIsThinnerThanThePlug` — a ring at or above the plug's own radius reads as a second plug.

Two pure functions, both testable without a host, both replacing a claim the breaker could only
make in a comment:

- `columns(inJackFieldWidth:) -> Int` — the CSS `auto-fill` arithmetic,
  `max(1, floor((w + gutter) / (jackMinimum + gutter)))`. This is what makes *"two jacks fit beside
  an open inspector"* an assertion rather than a hope, and it is what the acceptance criterion
  measures.
- `plugTransition(reduceMotion:) -> Double?` — `nil` under Reduce Motion, `0.2` otherwise. Same
  contract as `BreakerGeometry.spring(raised:reduceMotion:)`: the motion goes, never the state
  change.

`DESIGN.md` §2 gains `### Signal Path geometry (specified)` **beside** the breaker's table, which
stays byte-identical in this slice for the reason its own note gives — a table removed before the
element it specifies turns the parity test's oracle into a parse error.

`app/Tests/MCPRouterKitTests/DesignDocParser.swift` gains `signalPathRows(in:)` alongside
`breakerRows(in:)`, and `SignalPathParityTests` asserts the two-way name-set equality and the
values. **Both parity suites are green in this slice**, against two tables and two types.

### B · The presentation layer  *(additive — nothing is removed)*

`app/Sources/MCPRouterKit/Servers/JackPresentation.swift`:

```
public enum JackState: String, CaseIterable, Sendable {
    case live, tripped, held, needsSignIn, dormant
}
```

with `plug: ColorToken?` (`nil` → `--jack-off`, drawn by the view), `border: ColorToken?`,
`word: String` — and `JackCondition.forServer(_:idleMs:)` returning `(state, label)` where the
label is the short form the jack draws: `3:41 left`, `tripped`, `2 held changes`, `needs sign-in`,
`dormant`.

The countdown is `mm:ss` from `ServerSubtitle.reapSeconds(_:idleMs:)` — the **same** function the
row's subtitle already uses, so the two cannot disagree about how long is left. Where `idleMs` is
absent the label is `awake`, because there is no horizon to count against; the row already refuses
to invent one and this refuses the same way.

**The contraction rule is implemented, not paraphrased.** The brief's second measured constraint is
*"Where the width is tight, drop the redundant word — the plug colour already says 'awake' — rather
than clipping the countdown"*, and the first draft of this plan carried the short labels and called
that the rule. It is not: `3:41 left` and `2 held changes` are already short, and neither shrinks
when a track narrows.

So `JackCondition` carries **two** strings:

- `word` — the condition in full: `3:41 left`, `2 held changes`, `needs sign-in`, `never reaped`.
- `contracted` — the same fact with the word the plug already carries removed: `3:41`, `2 held`.
  Equal to `word` for the four states that have nothing redundant to drop.

The **view** picks, with `ViewThatFits(in: .horizontal)` over the two — so the choice is made
against the real laid-out width rather than against a character budget estimated from a glyph
width. The number is in both forms, so nothing that was carrying information can be the thing that
goes.

`contracted` is what a narrow track draws; `word` is always what the accessibility label carries,
so the state in full reaches a screen reader at every width. That is AC3, and it is why the
contraction cannot quietly cost a state its word.

`ServersBoardHeader` gains two derived figures, both withheld on a reading that is not current:

- `atRest: Int?` — `list.filter(\.warm).count`.
- `topology: String` — `"1 endpoint → N upstreams"`. `N` is the declared count, which is
  configuration and survives a stale reading; the endpoint count is 1 because there is one router.

`ServerRowModel` gains `jack: JackState` and `condition: JackCondition` **beside** `breaker`,
which is untouched. Nothing is renamed and nothing is deleted, so every existing reader — the row
view, four test files — still compiles and the suite is green on this commit.

**This is a correction the out-of-family review forced, and it was a real defect.** The first
draft renamed `breaker` here and fixed its readers in slice C, which leaves
`ServersBoardRow.swift:46` calling `Breaker(state: row.breaker)` against a model with no such
member — `MCPRouterUI` would not have compiled on that commit. A slice boundary that does not
build is a bisect that cannot run.

### C · The band, and the row plug

`SignalPath.swift` — an `HStack` of hub, `Icon.flow`, jack field, under a head row carrying the
title, the topology line and the four-word legend. `Jack.swift` — one jack as a `Button`, and
`StatePlug`, the 8pt dot the legend and the rows draw.

The jack field is `LazyVGrid(columns: [GridItem(.adaptive(minimum: SignalPathGeometry.standard.jackMinimum), spacing: gutter)])`,
which is the brief's instruction and the direct translation of `repeat(auto-fill, minmax(132px, 1fr))`.

Selection is `board.selection` — the property the table and the inspector already read. One
binding, three readers, and no new state: a jack sets it and reads `isSelected` from it, which is
what makes *"selecting a jack selects that server in the table below and in the inspector, and the
reverse holds"* true by construction rather than by synchronisation.

The row's `Breaker(state:)` becomes `StatePlug(state:)`, the inspector's does too, and
`ServersBoardMetrics.indicatorColumn` replaces `BreakerGeometry.standard.housingWidth` in
`ServersBoardTable.columnHeaders` — one value, both sites, so the header cannot fall out of
alignment with the cells. **The table's columns move left by the difference**, which is the visible
consequence of retiring a 30pt lever and is expected rather than incidental.

`SkeletonRows`, `OverflowRow` and the gallery section move in **this** commit rather than in D, for
the reason above: they are the remaining `Breaker` call sites, and D deletes the type. So does
`ServersBoardSurfaceTests.theBoardDrawsTheIndicatorNotAToggle` — A29's positive half asserts the
board draws an indicator and its negative half that it never draws a toggle, and both halves point
at `Breaker` today. Retargeted at `StatePlug` in the same commit that moves the view, because a
test left pointing at the old symbol for one commit is a red suite at a slice boundary.

Every new node carries `.measured(…)`, because a node the harness does not report is a node the
gate reads as absent.

### D · The retirement

`Breaker.swift`, `BreakerGeometry.swift`, `BreakerGeometryTests.swift` and `BreakerParityTests.swift`
are deleted. `DESIGN.md`'s `### Breaker geometry` goes with them, along with §1's outgoing-signature
paragraph and §7's two breaker rows. `DesignDocParser.breakerRows` goes.

Three consumers are re-homed rather than deleted, and each is a decision:

1. **`ShellMotion.badgeBump`** read `BreakerGeometry.standard.riseResponse/riseDamping`, with the
   stated reason that *"a badge ticking up and a breaker snapping up are the same event."* Under
   the new signature that event is a plug lighting, so it reads
   `SignalPathGeometry.standard.plugTransition(reduceMotion:)` — the reasoning is preserved
   verbatim and the value stays parity-checked. `badgeBumpHold` follows it.
2. **`SkeletonRows`** stood a rounded rectangle at the housing's dimensions. It stands a circle at
   the row plug's instead, still inside a row at `MetricToken.serversRow`, which is the property
   the skeleton exists for.
3. **`OverflowRow`** and the gallery's `BreakerSection` become the plug and a `SignalPathSection`
   drawing the five jack states plus a live plug whose transition can be watched — the same
   argument `DESIGN.md` §10 made for the breaker section, which was that the motion had never been
   observed running.

§7's opening line — *"Springs, not durations."* — is amended rather than left standing over a table
with no springs in it. The console mock authors this element's motion as a duration and a curve,
and it is the design of record.

`DESIGN.md` §2's `Servers row` cell reads `56pt (4 + 48 breaker housing + 4)`. The derivation
retires with the housing; the value does not move, because the table's own conversion is not this
item's and a row height changed here would move the skeleton, the column headers and the
inspector's neighbour in a diff nobody asked for. The cell restates what now sets it and §10
records that the mock draws 36pt.

### E · The gate

`scripts/acceptance/mock_fidelity.py`'s `VOUCHED_CONTROLS` gains **two** entries —
`"jack": {("jack", "hstack")}` and `("signature", "vstack")` under `card`. The file's own comment
anticipates this (*"Extending the list is a deliberate, reviewable act"*) and names this item as
the one that activates the claimant defect it guards against.

**`indicator` is deliberately not vouched, and the review is why.** Vouching it would put
`indicator` into `MOCK_KINDS_FOR_ROLE`, which turns `declared` from 0 to the mock's census of
indicator affordances for that state — and at that point every build node of that role which
answers no affordance stops being `covered-by-pair` and becomes `extra`, a finding
(`mock_fidelity.py`:935-956). The build's row plugs sit inside paired rows and are exactly that
population. Worse, a vouched indicator pairing cannot be measured anyway: the harness records no
text for a dot, so `readable()` fails on both sides and the row lands `unclassified` — *"Agreement
between two absences is not a measurement"*, which is the gate's own phrase for it.

So the mock's indicator affordances stay `absent` with a citation that says what is true after this
item: the build now draws the mark, and the gate has no instrument that can pair a textless node.
That is `D-m23-h`'s subject — the mock kinds `VOUCHED_CONTROLS` does not name — and it is recorded
against that deferred item rather than closed by a vouch that would make the gate louder and less
accurate.

`planning/fidelity/servers.pairing.tsv` gains rows for the band, the four jacks the fixture
declares, and the four row plugs.

**Two honest outcomes to expect, stated here so neither reads as a regression:**

- The seven mock jacks with no counterpart stay `absent`. The mock draws eleven upstreams and the
  fixture declares four — the same population difference the eight table rows already carry, four
  paired and four `-`.
- The paired jacks read **`divergent`, not `present`**, because `present` requires the two labels to
  be equal and the mock's are its own server names. Every existing paired row on this surface reads
  the same way for the same reason.
- The mock's row plugs stay `absent` and keep a citation rather than being paired. The ledger row
  is not a claim that the build draws nothing there — the citation column is where the owner of a
  difference is recorded — and the alternative measures nothing while reading louder.

---

## Test strategy

**Seams, all existing.** `MCPRouterKitTests` for everything headless — the geometry, the parity, the
precedence chain, the header figures. `MCPRouterUITests` for the source-level board assertions
(`ServersBoardSurfaceTests`' A-clause style) and the design-system census.
`scripts/acceptance/mock-fidelity-gate.sh servers` for the five measurement layers. No new harness.

**Unit and contract coverage:**

| What | Where | The assertion |
|---|---|---|
| the construction holds | `SignalPathGeometryTests` | the three invariants, each with the failure it rules out named |
| the columns pack | `SignalPathGeometryTests` | `columns(inJackFieldWidth:)` at the board's own width ≥ 2, and ≥ 2 at the width left beside an open inspector |
| Reduce Motion | `SignalPathGeometryTests` | `plugTransition(reduceMotion: true) == nil`, and the state change is the caller's |
| the document and the code agree | `SignalPathParityTests` | two-way name-set equality plus every value, replacing `BreakerGeometryParityTests` one for one |
| the plug never lies | `JackPresentationTests` | over the cross product of state × placard × pendingChange × auth × warm: `state == .live` **iff** `server.state == .running` |
| an index error is not a sixth state | `JackPresentationTests` | a server carrying one arrives placarded, so it reads `.tripped` |
| the two spellings agree | `JackPresentationTests` | the jack's countdown and the row's subtitle read the same `reapSeconds` |
| at rest is observed | `ServerBoardShapeTests` | `atRest` is the warm count, and is `nil` on a stale reading |
| the ladder is closed | `DesignSystemTests` | the icon census is base + two named additions |
| the board draws the indicator | `ServersBoardSurfaceTests` | A29's positive and negative halves, retargeted at `StatePlug` |

**Acceptance criteria, each falsifiable at `87e16dc`:**

| # | Criterion | What shows it false at the base commit |
|---|---|---|
| AC1 | A structure dump of `servers.ideal` at 1280×820 contains a `signal-path` node with a `jacks` child carrying one node per declared server | `grep signal-path planning/fidelity/servers.dump.json` → nothing; no `SignalPath` type exists in `app/Sources` |
| AC2 | The jacks lay out in **two or more columns** at that width | there is no jack field; and `columns(inJackFieldWidth:)` does not exist to be called |
| AC3 | Every jack node carries its state **word** in its accessibility label, so colour is not the only signal | no jack; `Breaker`'s `accessibilityValue` is the only such label on the board |
| AC4 | Selecting a jack selects the row and the inspector, and the reverse holds | no jack; `board.selection` has two readers |
| AC5 | The hub reads the router's own port and the warm count, and withholds the count on a reading that is not current | nothing draws a hub; `atRest` does not exist |
| AC6 | No `Breaker`, `BreakerToggle`, `BreakerGeometry` or `BreakerState` symbol remains in `app/Sources` or `app/Tests` | `grep -rn 'Breaker' app/Sources app/Tests` → 30 hits across 18 files |
| AC7 | `DESIGN.md` documents the Signal Path's construction value by value and no longer documents the breaker's | §2 carries `### Breaker geometry` with 19 rows and no signal-path table |
| AC8 | The Swift suite discovers **more than 1725** tests and `make test` is green; `make lint` is at 0 violations and `no-raw-design-values.sh` is clean | `swift test list` at the base discovers exactly 1725 — measured on this tree at slice A (1736 lines, 11 of them this item's two new files), which is also the figure `ORCHESTRATOR.md` records at `29d5111`. A run that discovers 1725 or fewer has added no test |
| AC9 | `mock-fidelity-gate.sh servers` records the signal-path card and the jacks as paired rather than absent, with the breadth finding count **down** from 116 | the ledger's 116 findings include 26 rows cited to this brief, all `absent` |

**Visual and state coverage.** The board's four measured states are the state matrix here:
`ideal` draws the band populated; `empty` and `error` must not draw it at all (a rail with no jacks
is dead chrome, and an `error` load has no servers to draw); `loading` draws the skeleton and no
band, because a band of jacks at a reading that has never answered would be four fabricated
dormant plugs. Each is asserted in `ServersBoardSurfaceTests` and measured by the gate, which
renders all four.

**A test that has never failed is not known to work** (`SWIFT_PRACTICES.md` §7). Four mutation arms
are run against the working tree, restored with `git checkout --`, and recorded in the progress
note with the failure verbatim: `jackMinimum` 132 → 133, a `### Signal Path geometry` row deleted,
a `JackState` case added with no view arm, and `state == .running` inverted in `JackCondition`.

---

## Out of scope, and where each lands

| Not here | Owner |
|---|---|
| the harness column and its three-state reading | M22 — it absorbs `R7-C1` and the `GET /harnesses` route |
| the table's seven mock columns, `State`, `Resident`, `Calls 24h` | M23's ledger; `Resident` is cited to `DESIGN.md` §6 as unobserved |
| the row height moving to the mock's 36pt | recorded in §10; the table's conversion |
| the four states' copy | M17, per `servers.pairing.tsv`'s own header |
| the held-changes banner and its sheet | M18 |
| `Reap idle` | M7 |

**Scope-narrowing check.** Every line above was compared against the brief and against the five
triage assumptions. One overlap, and it is declared rather than quiet: assumption 5 —
*"`[Operations]` The wording for how each AI tool reaches the router comes from the reading the
router already produces"* — is about the harness column, which this plan parks. The assumption is
not contradicted; it is unreachable, because there is no reading to take the wording from. It is
surfaced in the spec as its own line. The other four assumptions are all delivered: the band packs
to the width (AC2), the redundant word is dropped rather than the countdown clipped
(`JackCondition`), every state has a word as well as a colour (AC3), and one selection is shared by
three surfaces (AC4).

---

## Sequencing risk, and the one thing that would go red

The parity suite's oracle is the document, and the document is being edited. Slice A adds the new
table while the old one is untouched, so both suites are green; slice D removes the old table and
its suite in the **same commit**. There is no commit in which `### Breaker geometry` is gone and
`BreakerGeometryParityTests` still reads it — that ordering is the mechanical half of the block
triage recorded, and it is closed by construction rather than by care.

The second is `ServerRowModel.breaker`, which four test files read. Slice B renames the property and
fixes its readers in the same commit; slice D deletes the enum. A commit that did both would be
unreviewable, and one that did them in the other order would not build.

---

## Gate record

**Mechanical path check** — every backtick-quoted path in this plan was resolved against the tree
at `87e16dc`. Seven resolve to nothing and all seven are in the *New* table above; the rest exist.
The bare basenames used in prose (`Breaker.swift`, `GallerySections.swift`, `ShellAppearanceTests.swift`,
`spec-M22.md`, …) each resolve to exactly one tracked file.

**Out-of-family review** — `agy` / `gemini-3.7-flash-high`, read-only, briefed adversarially over
eight questions at once and told that finding nothing is a failed review. `codex` / `gpt-5.6-sol`
is recorded down until 2026-08-27 and `grok-4.6`'s balance was re-confirmed exhausted on
2026-08-22, so the Google lane is the gate and is **not** a downgrade. Verdict: **AMEND** — four
ACCEPT, four REJECT.

| # | Finding | Disposition |
|---|---|---|
| 1 | Parking the harness column is sound; M22 owns the route | **Accepted, and the citation corrected.** The lane opened `HarnessReconciliation.swift` and found the case names are `notWired(overlapping:)` / `wiredViaHTTP` / `wiredViaShim(bridge:)` / `wiredWithDuplicates(route:count:)` — the brief's three states exactly, and `spec-M22.md`:153's spelling is stale. The plan now quotes the source |
| 2 | `SignalPathGeometry` over nine `MetricToken` cases is a continuation, not a descope | **Accepted.** No change |
| 3 | `warm` alone counts a warm server that failed to start, whose process is not up | **Accepted — the figure changed.** `atRest` is `warm && state == .running`. `warmUp()` logs and swallows a start failure, so `warm` alone puts a child in the readout that is not on the machine |
| 4 | A **warm running** server would draw a reap countdown while the hub reads `1 at rest` | **Accepted — the sharpest finding, and a real defect.** The plug's precedence and the word's are now separate: `.live` is still `state == .running`, and the word is computed from the state plus `warm`, so no input reaches a countdown with `warm == true`. `ServerSubtitle` has enforced this for the row since M3 and the first draft would have broken it on the signature |
| 5 | Slice B renamed `ServerRowModel.breaker` while `ServersBoardRow.swift:46` still read it — that commit does not compile | **Accepted.** B is additive: `jack` lands beside `breaker`. Every `Breaker` call site moves in C, including `SkeletonRows`, `OverflowRow`, the gallery and A29's two halves; D deletes the type |
| 6a | The contraction rule was paraphrased, not implemented | **Accepted.** `JackCondition` carries `word` and `contracted`, and the view chooses with `ViewThatFits` against the real width. The accessibility label always takes `word` |
| 6b | AC8 is not falsifiable at the base — lint and tests are already green there | **Accepted.** AC8 now names a number: more than the **1725** tests `swift test list` discovers at the base, measured rather than quoted |
| 7 | Vouching `indicator` destroys the `covered-by-pair` exemption and produces `extra` findings for the build's own row plugs | **Accepted.** Only `jack` and `("signature","vstack")` are vouched. The mock's indicator affordances stay `absent` with a citation, recorded against `D-m23-h` |
| 8 | The biggest unmentioned risk is the hub/jack contradiction on a warm server | **Accepted — the same defect as 4**, and closed by the same change |

Nothing was rejected. The two findings that changed shipped behaviour are 3 and 4, and both are
cases where the router observes something the first draft would have drawn over.
