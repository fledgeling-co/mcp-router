# Implementation plan — M2: Activity, the live call log

**Spec:** `planning/specs/spec-M2.md` · **Design representation:**
`design/mocks/html/m2-activity.html` · **Design authority:** `DESIGN.md`
**Tier:** Standard — one new module directory, one shared-file wiring change, one honest fix to the
shared test double, and a behavioural acceptance script.
**Branch / worktree:** `ai/m2` in `.worktrees/M2`.
**Status:** delivered. The record of what actually happened is at the foot of this file — three of
the plan's decisions did not survive contact and the reasons are worth more than the plan was.

---

## What already exists, and is therefore not built again

Read before writing anything; every one of these is merged and load-bearing.

| Need | Already merged | File |
|---|---|---|
| the wire shapes | `CallRecord`, `UsageResponse` | `MCPRouterKit/Control/Models.swift` |
| the backfill call | `ControlAPIClient.usage(limit:server:cwd:)` | `.../ControlAPIClient.swift` |
| the live feed | `ControlEventStream`, `StreamEvent`, `StreamPhase`, `ReconnectPolicy` | `.../ControlEventStream.swift` |
| the failure vocabulary | `ControlAPIError` with `headline` / `advice` / `actionLabel` | `.../ControlAPIClient.swift` |
| the state containers | `SurfaceState`, `StateMessage`, `MessageState`, `SkeletonRows` | `MCPRouterUI/StateContainer.swift` |
| relative time and project label | `shortAgo`, `projectLabel`, `String.asControlAPIDate` | `MCPRouterKit/Formatting/RelativeTime.swift` |
| tokens | `ColorToken`, `TypeToken`, `MetricToken`, `.typeRole(_:monospaced:)` | `MCPRouterKit/Design/*`, `MCPRouterUI/*+SwiftUI.swift` |
| icons | `Icon`, `IconView` | `MCPRouterUI/Icon.swift` |
| button styles | `ProminentButtonStyle`, `StandardButtonStyle`, `ControlScale` | `MCPRouterUI/Controls.swift` |
| the double | `FixtureControlAPIClient` with 13 scenarios and `streamEvents()` | `.../FixtureControlAPIClient.swift` |
| the background-safe AX harness | `session`/`trusted`/`front`/`dump`/`select`/`key`/`focus`/`accent`/`rowrect` | `scripts/acceptance/axkit.swift` |
| the raw-value gate | `scripts/lint/no-raw-design-values.sh` | — |

**`Icon` has no frost case.** `Icon.allCases` maps to SF Symbols; the cold mark needs one added
(`snowflake`, which is a real SF Symbol). That is a one-case addition to a shared enum in
`MCPRouterUI`, additive, and `ShellIconTests` already asserts every case resolves — see step 2.

---

## Phase A — the model, with no view attached

Everything in this phase is testable without a window, which is the point: the filter algebra, the
de-duplication, the ring cap and the state derivation are where the defects live.

### A1 · `MCPRouterUI/Activity/ActivityRecords.swift`

A value type holding the loaded window and answering the questions the board asks.

- `struct ActivityRecords` — an ordered `[CallRecord]`, newest first, plus `since: String`.
- `capacity` = 500, read from one named constant with the reason recorded (`src/usage.ts`'s
  `RING_SIZE`). `prepending(_:)` drops from the tail past capacity — **B19**.
- De-duplication on `CallRecord.id` (`ts|server|tool|pid`), which the model already provides —
  **B20**. A `Set<String>` of ids alongside the array so this is not O(n) per arrival.
- `sessions() -> [SessionOption]` and `directories() -> [DirectoryOption]`, each derived **only**
  from the loaded records with a per-option count — **B13**. An option with no matching record
  cannot be produced, because the options *are* the grouping.
- `SessionKey` is `enum { attributed(pid: Int), unattributed }`; `DirectoryKey` is
  `enum { path(String), unattributed }` — **B15/D3**. Modelled as enums rather than
  `Int?`/`String?` so no call site can accidentally treat "unknown" as a filter that matches
  everything.

### A2 · `MCPRouterUI/Activity/ActivityFilter.swift`

- `struct ActivityFilter { var session: SessionKey?; var directory: DirectoryKey? }`, `nil`
  meaning "all".
- `matches(_ record: CallRecord) -> Bool`, and `isActive`.
- `filter(_:)` over `ActivityRecords` returning the visible slice **plus** the total, so the
  `N of M` line and the "filtered to nothing" state both read one value — **B16/B17**.

### A3 · `MCPRouterUI/Activity/ActivityCopy.swift`

Every string the board renders, as data, so the tests and the design representation can both be
compared against it — the pattern `ServersBoardCopy` and `PairingCopy` already set.

- `empty`, `filteredToNothing`, `partialReconnecting`, `partialDisconnected`, `disabledFilters`,
  and the subtitle composer.
- Offline, unauthorised and error copy is **not** written here: it is read from
  `ControlAPIError.headline` / `.advice` / `.actionLabel` — **B34**, §6's one-wording rule. A test
  asserts these three states construct their `StateMessage` *from* the error rather than from a
  literal.

### A4 · `MCPRouterUI/Activity/ActivityModel.swift`

`@MainActor @Observable final class ActivityModel`.

- Holds `records: ActivityRecords?` (nil is not empty — the M1/F4 distinction, and **B32** turns on
  it), `filter`, `selection: CallRecord.ID?`, `failure: ControlAPIError?`, `phase: StreamPhase?`.
- `load()` — one `client.usage(limit: capacity, server: nil, cwd: nil)`, storing either the records
  or the typed error. Filters are **not** passed to the endpoint — D1, and **B18** counts the
  requests to prove it.
- `subscribe()` — iterates an injected `ActivityEventSource` (below), applying `.record` and
  `.phase`.
- `surfaceState` — the single derivation the view switches over, returning the enum the view
  renders. Written as one exhaustive `switch` so a state cannot be forgotten.
- The clock is injected (`@MainActor () -> Date`), as `ShellModel` and `ReadoutModel` both do, so
  the relative times are testable without sleeping.

### A5 · `MCPRouterUI/Activity/ActivityEventSource.swift`

`ControlEventStream` is a concrete struct, so it cannot be substituted directly.

```
protocol ActivityEventSource: Sendable { func events() -> AsyncStream<StreamEvent> }
struct LiveActivityEventSource: ActivityEventSource   // wraps ControlEventStream
struct ReplayActivityEventSource: ActivityEventSource // replays a [StreamEvent]
```

`ReplayActivityEventSource` is fed by `FixtureControlAPIClient.streamEvents()`, which is already
public and already produces the three phases. This is the seam **B22** and **B23** are proven
through, and it wraps rather than modifies the merged stream type.

---

## Phase B — the fixture gap, closed honestly

`FixtureControlAPIClient` cannot currently produce Activity's empty state (its `.empty` scenario
returns the recording's records) and has no over-long *tool* name for overflow. Both are gaps in the
double's own stated contract. Closed with the smallest change that does not rewrite a capture.

1. **New authored fixture** `MCPRouterKit/Control/Fixtures/usage-call-log.json` — header comment is
   impossible in JSON, so the file is documented at its use site and in the spec (D11) as
   **authored, not captured**. Contents, chosen to make each clause reachable:
   - ≥ 12 records across 3 servers;
   - 2 attributed sessions (`pid` 51310 `claude`, `pid` 48822 `claude`) and ≥ 1 record with no
     `pid` and no `cwd` — **B15**;
   - 3 distinct `cwd` values — **B13/B14**;
   - ≥ 2 `cold: true` and the rest warm — **B7**;
   - ≥ 1 `ok: false` carrying a real `err` string — **B8/B9**;
   - one tool name > 40 characters and one server name > 40 — **B6**.
2. `FixtureControlAPIClient.usage(...)`: return `records: []` when `scenario == .empty`; otherwise
   decode `usageFixtureName(for: scenario)`, which is `usage-call-log` for `.populated`,
   `.overflow`, `.streamLive`, `.streamReconnecting`, `.streamDisconnected` and `usage` for the
   rest. `streamEvents()` uses the same helper so backfill and stream agree.
3. `usage.json` is **not** touched. `ControlFixtureTests` reads that file directly and asserts
   `.first` carries attribution; `FixtureClientTests` asserts `.populated`'s records are non-empty —
   both still hold. No `Scenario` case is added, so `everyScenarioIsCovered` (which asserts
   `count == 13`) and `ShellClientFactoryTests`' two `allCases` loops are untouched.
4. New tests live in **M2's own** test file, not in F3's: `.empty` has no records; `.populated` has
   ≥ 2 distinct pids, ≥ 3 distinct cwds, a failed record, a cold record and an unattributed record;
   `.overflow` has a tool name > 40 chars.

**Run `make test` immediately after this phase**, before any view exists. If a merged test does
object, it is far cheaper to learn here than after the board is written.

---

## Phase C — the view

### C1 · `MCPRouterUI/Activity/ActivityRow.swift`

- Six columns at the widths the design representation measures, laid out with fixed leading widths
  and one flexible tool column.
- `.frame(height: MetricToken.tableRows.leadingScalar)` — **B5**. The same expression appears in
  the skeleton row and is compared by test, not by eye.
- `.lineLimit(1).truncationMode(.tail)` on server, tool and project — **B6**.
- `.accessibilityLabel` composed from the **untruncated** values, prefixed with "failed" when
  `!ok` — **B6/B9**.
- The failure dot renders only when `!record.ok`; there is no success dot — **B8/D4**.
- The cold mark is `IconView(.frost, size: TypeToken.caption.size)` in `ColorToken.t2` — **B7/D5**.

### C2 · `MCPRouterUI/Activity/ActivityFilterBar.swift`

Two `Menu`s presented as pop-up buttons (value shown, double chevron) — **B12**. Options from
`ActivityRecords.sessions()` / `.directories()` with counts. `Clear filters` and the `N of M` count
appear only while `filter.isActive` — **B16**. Both controls disable, in place, with one shared
helper sentence when there are no records — **B31 disabled**.

### C3 · `MCPRouterUI/Activity/ActivityInspector.swift`

A definition list of the nine inspector fields — **B24** — reading only, no control — **B25**.

### C4 · `MCPRouterUI/Activity/ActivityBoard.swift`

- Header (title, subtitle), filter bar, column header, then one exhaustive `switch` over the
  model's surface state.
- `LazyVStack` inside a `ScrollView` with `ForEach(id: \.id)` — stable identity, which
  `SWIFT_PRACTICES.md` §4 requires for a list that reorders.
- `.task { await model.load(); await model.subscribe() }` — scoped to the board, so leaving Activity
  cancels the subscription (**B21**). No work in `body` (§4).
- `.onKeyPress` for `↑`/`↓`/`Return`/`Esc`; `Space` is deliberately unbound — **B27**.
- Insertion animation on transform only, gated on `accessibilityReduceMotion` — **B29**.

### C5 · the two shell wirings

- `ScaffoldPane.swift`: `installed = [.activity]`. Its doc comment already says "M2–M8 each add
  exactly one entry here alongside the view that justifies it."
- `ShellWindow.swift`: `ContentZone.pane`'s `else` branch renders `ActivityBoard` for `.activity`,
  keeping `EmptyView()` for the destinations M3–M8 will fill. The comment on that branch is updated
  to say which are still to come.
- `Icon.swift`: one case, `frost` → `snowflake`.

---

## Phase D — gates and evidence

1. `make lint` · `make build-mac` · `make test` · `scripts/lint/no-raw-design-values.sh` — **B36**.
2. **Red-green proving pass.** Every test whose job is to catch drift is deliberately broken, seen
   red, and restored — recorded per test in the completion note, as `SWIFT_PRACTICES.md` §7
   requires. The list: B5 (row height), B7 (drawn glyph), B8 (indicator exclusivity), B13 (filter
   options in both directions), B18 (no refetch), B20 (de-duplication), B32 (empty copy), B34 (copy
   read from the error).
3. **`scripts/acceptance/m2-activity.sh`** — the behavioural half, built on `axkit.swift`, and
   **invisible**: `open -g -a`, AX reads by pid, `CGEvent.postToPid` for keys, frontmost recorded at
   start and asserted unchanged at the end. It drives **only** the Activity pane; the other six are
   placeholders and are not touched. Scenarios exercised through `MCPROUTER_SCENARIO`:
   `populated` (B1, B3, B6, B14, B16, B24, B27), `empty` (B32), `loading` (B33), `offline` and
   `unauthorized` (B34), `streamReconnecting` and `streamDisconnected` (B22).
4. `planning/evidence/M2-acceptance.md` — one row per screen: screen · how it was verified (the
   actual command or AX path) · the commit SHA · result. Appended, never rewritten.

---

## Risks, and what each is answered with

| Risk | Answer |
|---|---|
| A merged test objects to the fixture-client change | Phase B runs `make test` before any view exists, so this surfaces at its cheapest |
| The board's stream and the shell's poll both hit the router | They are different endpoints and the shell is explicitly poll-only; nothing is duplicated |
| 500 rows in a `LazyVStack` janks | Lazy stack, fixed row height, stable ids, and the filter is a pure function over an in-memory array with no request behind it |
| `Space` is silently claimed by a focusable row | B27 asserts it is not, using M1's proven `CGEvent.postToPid` route |
| The acceptance run takes the screen | The gate asserts the frontmost app is unchanged and fails itself if it ever does |
| M3 lands concurrently and conflicts in `installed` / `Icon` / the fixture client | All three are single-line additive edits; the orchestrator serializes merges |


---

## What the plan got wrong, recorded rather than quietly corrected

**1. The authored fixture went in the wrong directory, and two merged gates said so.**
Phase B put `usage-call-log.json` in `app/Sources/MCPRouterKit/Control/Fixtures`. That directory is
not a bag of JSON: `scripts/acceptance/parity-fixture.sh` replays **every** `*.json` in it against
the running TypeScript reference, and `parity-manifest-check.sh` requires each to carry a row in
`planning/parity/surface.tsv`. A hand-written body there is a body R4's harness will replay and the
reference will never reproduce. F4's fixture-immutability guard caught it. The file now lives in
`Control/Authored`, copied as its own bundle resource and searched after `Fixtures`, and
`ControlFixtureTests.expected` is untouched after all — so the plan's claim that a merged test had
to be edited for it was wrong in the direction that matters.

**2. Phase A put the data layer in `MCPRouterUI`; it belongs in `MCPRouterKit`.**
`ActivityRecords`, `ActivityFilter` and `ActivityEventSource` are Foundation-only value types with no
UI dependency, and `SWIFT_PRACTICES.md` §8 keeps the kit free of UI frameworks so the router's own
tests can import it. They are in the kit. `ActivityCopy` stayed in `MCPRouterUI` because
`StateMessage` lives there, which is the same reason `ServersBoardCopy` does.

**3. The board could not simply fill `ContentZone`'s `else` branch.**
That branch sits inside the shell's `ScrollView`, and a board with its own scrolling list would put
one scroll view inside another. The board renders outside it and reports its list's scroll geometry
through the same callback, so the scroll-edge separator behaves identically over a board and over a
placeholder. The knock-on: M1's A34 assertion drove **Activity** specifically, relying on it being a
deliberately over-tall placeholder, and is re-pointed at Servers with the reason recorded in the
script.

**4. The plan's Phase D listed a red-green pass and assumed the gates existed.** One did not: B5's
row height had no test at all, and swapping its token left the suite green. Found by running the
proving pass rather than by reading the code. `ActivityColumn.rowHeight` is now the single value the
row and the skeleton draw at, asserted as the only height in the file.

**5. B27's keyboard evidence could not be taken in the running app**, and the plan did not see it.
M1's `KeyClaimProbe` claims first responder and swallows Space, Return and Esc, and Debug is the only
configuration in which a fixture is reachable. Arrow keys, Return and Esc are proven at the model;
`Space` is proven in the app, because the probe receiving it *is* the assertion that the board did
not claim it. Written down in `planning/evidence/M2-acceptance.md` rather than worked around.

## What landed

| Area | Files |
|---|---|
| data layer | `MCPRouterKit/Activity/{ActivityRecords,ActivityFilter,ActivityEventSource}.swift` |
| board | `MCPRouterUI/Activity/{ActivityModel,ActivityCopy,ActivityChrome,ActivityRow,ActivityFilterBar,ActivityInspector,ActivityBoard}.swift` |
| shell wiring | `ScaffoldPane.swift`, `ShellWindow.swift`, `ShellModel.swift`, `ShellClientFactory.swift`, `Icon.swift` |
| double | `Control/Authored/usage-call-log.json`, `FixtureControlAPIClient.swift` |
| tests | `MCPRouterKitTests/ActivityRecordsTests.swift`, `MCPRouterUITests/{ActivityModelTests,ActivityCopyHonestyTests,ActivityBoardRulesTests,ActivityTestClients}.swift` |
| gates | `scripts/acceptance/m2-activity.sh`, `scripts/lint/no-raw-design-values.sh` (geometry rule extended), `scripts/acceptance/mac-shell.sh` (A34 re-pointed) |
| merged tests updated | `ShellIntegrationTests.swift` (state → invariant), `DesignSystemTests.swift` (icon count + reason) |
