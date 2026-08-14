# M2: Activity — the live call log

**Status:** Ready for Implementation Plan
**Depends on:** M1 (shell) ✓ merged · F2 (design system) ✓ · F3 (control client) ✓ · F4 (tracker
and failure states) ✓
**Design authority:** `DESIGN.md` · **Design representation:**
`design/mocks/html/m2-activity.html`
**Mock input:** `design/mocks/prototype.html?only=mac&pane=activity` (stale in three named ways —
see *Where the prototype is stale*)
**Practices:** `planning/practices/SWIFT_PRACTICES.md` (binding),
`CODING_PRACTICES.md`, `NEW_PROJECT_BEST_PRACTICES.md`
**Spec review:** in-family adversarial gate, 2026-08-14 — `codex: usage limit -> claude
(downgrade)`. 36 findings, 2 blockers; accept 17 / reject 19 on the first draft. Every finding is
resolved below and the ones that changed a decision are cited by number.

---

## Feature description

*(verbatim from `planning/features-to-triage/M2-activity.md`)*

> # M2 — Activity: the live call log
>
> **Depends on:** M1.
>
> The surface that answers "what is my agent actually calling?" — a live-updating log of
> tool calls with session, working directory, server, tool, duration and outcome.
>
> - Filter by session and by directory; this is the per-project ledger the router already
>   keeps in `usage.ts`.
> - Cold-start calls are marked, because a call that had to spawn its server is a
>   different event from one that hit a warm child.
> - Row height is fixed; long tool names truncate with the full value in the inspector.
> - States: empty (no calls yet since the router started — say that, it is not an error),
>   loading, offline.
>
> Deep link: `?only=mac&pane=activity`.

---

## What this item finishes

`.activity` is in `BoardRegistry.installed` and `ScaffoldedDestination(.activity)` returns `nil`.
`ShellIntegrationTests` asserts `installed` and `scaffolded` are exact complements in both
directions, so a board that compiles but is not registered fails the suite — and a board registered
without a view cannot be constructed. Seven destinations remain scaffolded, so
`scripts/acceptance/mac-shell.sh` still requires the Release bundle to carry the scaffold sentinel.

---

## Where the data comes from — the whole of it

Every field this board renders is a field the router logs. There is no estimated or invented number
anywhere on the surface (`DESIGN.md` §6, and the product's standing constraint). The one **derived**
value is named as such rather than hidden behind a raw field name.

| On screen | Field | How it is rendered |
|---|---|---|
| when | `ts` | **Derived**: an age against the *device* clock, which is not the router's. `shortAgo` floors the interval at zero, so a `ts` in the future (clock skew) reads "now" rather than negative. The absolute value is in the inspector, so the raw fact is never out of reach |
| server | `server` | verbatim |
| tool | `tool` | verbatim, truncated at the tail; full value in the inspector |
| project | `project` / `cwd` | `project`, or the last segment of `cwd`. The full `cwd` is in the inspector |
| session | `pid` | the pid alone in the column; `client · pid N` in the inspector and the accessibility label |
| took | `ms` | verbatim, in ms — the unit the router measures in |
| cold mark | `cold` | a drawn glyph; the words are in the inspector |
| failure mark | `ok`, `err` | `--fail` on the mark, `err` verbatim in the inspector |
| subtitle "since" | `since` | `UsageResponse.since` as a clock time |
| subtitle count | `records.count` | the **loaded window's** size, worded "Showing N calls" so it cannot be read as a total |

**What `since` is, and what no sentence may claim from it (F3, F4).** `UsageResponse.since` is
`stats.since` in `src/usage.ts`. `readStats()` *persists* it: it survives every restart and moves
only when `reset()` zeroes the counter. It is the moment the counting window opened and says nothing
about how long the router has been running, and nothing on the wire does. So the empty state says
"Nothing has called a tool since 09:12" and never "the router has been up since 09:12", and the
disabled-filter reason says "No calls have been recorded yet" and never "since the router started".
`ActivityCopyTests` asserts the absence of both phrasings.

**There is no completeness watermark on the wire (F6).** `UsageResponse` is `{since, records}`. The
newest record's timestamp proves a record arrived; it never proves none was missed. A stream that
dropped at 09:43 still shows 09:41 and cannot see the hole. So the feed states say "The newest call
here is from 09:41" and never "complete up to 09:41".

**The count is a window, not a total (F9).** The window caps at `ActivityRecords.capacity` (500,
matching `RING_SIZE` in `src/usage.ts`), the router's JSONL rotates at 8 MiB keeping one generation,
and `readTail()` warms the ring from the last 512 KiB — so after a restart the ring may hold far
fewer than 500 with `since` unchanged. The subtitle is therefore *unfiltered* and worded "Showing N
calls · since 09:12 · live"; the filtered pair is `N of M` in the filter bar, and the two are kept
distinct so neither silently changes meaning.

**Transport.** `GET /usage` for the backfill and `GET /usage/stream` (SSE) for the live half — both
already implemented by F3's `ControlAPIClient.usage(limit:server:cwd:)` and `ControlEventStream`.
The board opens no socket, no file and no process of its own, and speaks only the loopback control
API. That is the standing boundary constraint, unchanged.

**The board owns the stream, and the shell deliberately does not.** `ShellModel` constructs its
`ServerStateTracker` poll-only with `stream: nil`, and says why in its own doc comment: "the call
stream is what M2's Activity board is for, and attaching it here would put a second subscription
behind a surface that renders nothing from it." This item takes that subscription, scoped to the
board's lifetime, so navigating away closes it.

---

## Decisions taken during triage

**D1 — Filtering is client-side over one loaded window, and the endpoint's own filters are not used
for it.** `GET /usage` accepts `server` and `cwd`, but the SSE stream is unfiltered, so a
server-side `cwd` filter would produce a list whose backfill and live half disagree — new records
for other directories would arrive and have to be dropped anyway. One in-memory window with
predicate filters means the two halves can never diverge, filter changes are instant with no
refetch and no flicker, and there is exactly one definition of "what is showing".

**D2 — A session is `pid` + `client`, filtered client-side because the endpoint has no `pid`
parameter.** `GET /usage` reads `limit`, `server` and `cwd` only. Nothing is lost: D1 already puts
every filter on the client. The match is on `pid` alone — the client name travels for display and
must not narrow it, since the router resolves it per connection and can legitimately send it for one
call and not the next.

**D3 — Records the router could not attribute are grouped under "Unattributed", never dropped and
never guessed.** `pid`, `cwd`, `project` and `client` are all optional on the wire —
`ClientResolver` returns an empty identity on every failure path, deliberately, because "an
unattributed record is worth far more than a dropped one". Both filter keys are **enums** rather
than optionals of a primitive, so no call site can turn *show me the unattributed calls* into *show
me everything*.

**D4 — A successful call carries no indicator colour.** The prototype paints every ok row's dot
`--live`. §2 makes that token mean "a child process is running" and forbids any other use; a call
that has finished is not a running process. Only failures are marked, in `--fail`. Colour is never
the only signal — a failed row carries `err` in the inspector and the word "failed" at the front of
its accessibility label.

**D5 — Cold start is a drawn glyph in `--t2`, not `❄` and not `--accent`.** §4: icons are drawn, one
grid, one stroke weight, `currentColor`. §2 reserves `--accent` for selection, focus and the one
primary action, and on this board an accent-coloured duration would compete with the selected row.
`Icon.frost` maps to the `snowflake` SF Symbol; the inspector spells the meaning out in words.

**D6 — Row height is `MetricToken.tableRows`, which resolves 24pt — the lower bound of §2's
"24–28pt for dense lists" band (F14).** §2 gives a range, and this reads the token that already
resolves inside it rather than adding a row to the document that another item would have to keep in
step. The Servers board earned its own 56pt token because a breaker housing does not fit a
documented size; a text row does.

**D7 — "Reset history…" is not in this item.** It is a destructive, un-undoable act on the router's
ledger, so §9 requires a named-consequence dialog and §3.9 a menu item — and a new menu item means a
new `MenuCommand` case plus a new row in **M1's merged command inventory**, which `MenuCommandTests`
asserts in both directions. It is not in this brief. Filed as child **M2a**.

**D8 — No search field, so `⌘F` is not rebound.** `MenuCommand.find` stays `surfaceAbsent` with its
existing reason. Filed as child **M2b**.

**D9 — The list is chronological, newest first, and not sortable.** That is the order the router's
`recent()` returns (`.slice(-limit).reverse()`) and the only order in which "a new call appears at
the top" is true. A sortable column would silently break the live contract.

**D10 — The board has two independent sources and therefore two failure directions.** A dropped feed
over a good history is §5's partial; a failed reload over a delivering feed is its mirror, and a
board with one failure story answers the second by discarding a live subscription. Both have their
own state (F32).

**D11 — The double is extended rather than the recording rewritten.** `usage.json` is a captured
fixture written by `scripts/capture-control-fixtures.sh`; hand-editing it would make a recording
into an invention. An **authored** `usage-call-log.json` is added instead, and
`FixtureControlAPIClient` serves it for the scenarios that need a log with shape. Two honest gaps in
the double are closed at the same time: `.empty` returned the recording's records, so the empty
state was unreachable, and `.overflow` had no over-long *tool* name.

**D12 — The row shows the session, because the brief says it does (F1).** The first draft demoted
`pid` to the inspector, which meant the board could not answer "which of my two agent windows made
this call" without a click per row. The column shows the pid; the client name and the full form are
in the inspector and in the accessibility label. Six things per row, which is the brief's six.

**D13 — Monospace covers the age, the session, the duration, the error and the timestamp, and
nothing else (F16).** §2: "Monospace is for instrument data only — numerals, counts, durations,
error codes, status subtitles. It is the instrument voice and loses its meaning if it leaks into
prose." A tool name and a project name are **identifiers**, on none of those five lists. The first
draft monospaced them and argued alignment; the columns are fixed-width, so the gutter is aligned
without borrowing the voice. The inspector's prose fields — "Succeeded", the cold/warm sentence — are
prose and take UI text for the same reason.

---

## Recorded deviations from `DESIGN.md`

Stated as deviations rather than argued into compliance.

**§5's empty state asks for "one action"; this board offers none (F18).** The thing that fills this
list is an agent making a tool call, and no control on this surface can do that. The three options
were a button that does nothing, a button that navigates to a surface which is still a placeholder
in this build, or no button. `StateMessage.actionLabel` is optional for exactly this case. The
earlier justification cited §3.4, which is a rule about how a disabled control *behaves* and not a
prohibition on offering an action — that citation was wrong and is withdrawn.

**§3.9 makes the menu bar the complete command surface; "Clear filters" and "Reconnect now" have no
menu item (F19).** Both are view-local controls rather than commands, on the same reading M1 already
applied when it excluded `Space`, `Return` and `Esc` from `MenuCommand` — "a bare key on a focused
row is not a menu command on macOS". The native precedent is exact: Finder's search field has a
clear button and no menu item for it, and Safari's error page has *Try Again* and no menu item for
that. If a later item disagrees, both become commands and M1's inventory gains two rows; that is
child **M2d** rather than a silent decision here.

**The Unauthorised state is unreachable against the real router, and ships anyway (F12).**
`src/control.ts` gates the token on `mutating = POST || DELETE || PATCH` and 401s only when
mutating; this board issues `GET /usage` and `GET /usage/stream` exclusively. On the stream path a
non-2xx is converted before the consumer sees it (`throw URLError(.badServerResponse)`), so even a
hypothetical 401 would surface as `.transport` — the Error state. It is designed and driven from the
fixture because it is what a Release build shows before pairing and because R5's auth work will make
it reachable; it is not claimed as a production path today.

---

## Where the prototype is stale

1. **`--live` on every successful row** — forbidden by §2's exclusivity (D4).
2. **`❄` as the cold mark** — unicode where §4 requires a drawn icon (D5).
3. **No filters at all, and no session column.** The prototype's Activity pane has neither; the
   brief requires both. Incomplete rather than wrong.

The prototype's 32px row is web CSS at web type sizes, not a Mac point value, and is not treated as
a disagreement — §2's `Table rows` is the number that governs (D6).

---

## Acceptance criteria

Every clause carries a typed evidence obligation: **measurement**, **exercised request /
interaction**, or **red-green test**. A clause whose evidence is only "it builds" is not accepted.
Where evidence comes from the running app, the **configuration** is named — Debug is the only one in
which a fixture scenario is reachable, and it is also the only one carrying M1's `KeyClaimProbe`.

### The board exists and is installed

| # | Clause | Evidence |
|---|---|---|
| B1 | `.activity` is in `BoardRegistry.installed`, `ScaffoldedDestination(.activity)` is `nil`, and selecting Activity renders the board rather than the scaffold | red-green test on the registry + AX assertion (Debug) that the running app's Activity pane carries no `ScaffoldCopy.sentinel` and does carry the board's identifier |
| B2 | `installed` and `scaffolded` are **exact complements in both directions**, and this build's installed set is `[.activity]` with 7 scaffolded | red-green test on the set algebra + a separate assertion on the membership, so a board landing is a deliberate edit rather than something set algebra absorbs |
| B3 | The board is reachable by `⌘1` and by the sidebar row, and the window title reads "Activity" (§3.7) | exercised interaction over AX (Debug): select by row, assert the pane identifier and the title |

### The row, and what it is allowed to say

| # | Clause | Evidence |
|---|---|---|
| B4 | Every string a row renders comes from **one `CallRecord`-to-text mapping**, and that mapping's field set equals the *Where the data comes from* table's — asserted against the table as an external oracle rather than by a survey of the view (F23) | red-green test comparing the mapping's key set to the parsed table |
| B5 | Row height is `MetricToken.tableRows` and is **identical** across the populated row, the skeleton row and a row whose server, tool and project all overflow — asserted against the token, not a literal | measurement of the three rendered heights compared to `MetricToken.tableRows.leadingScalar` + red-green test |
| B6 | An over-length tool name truncates at the tail; the full value is in the inspector and in the row's accessibility label. The same holds for the server and project columns (§5 overflow) | measurement at a forced overflow + red-green test on the accessibility label carrying the untruncated string |
| B7 | The cold mark is an `IconView`, not a text glyph: no `Text` on this board renders a single character from the Dingbats, Miscellaneous Symbols or Emoji blocks, and every drawn symbol sits at the icon set's one stroke weight (F21, F22) | red-green test with that named predicate (a whole-file non-ASCII scan is not the check — the board's own copy legitimately contains `·`, `…` and `—`) + a test that the mark's colour token is `t2` and not `accent` |
| B8 | The board's indicator-coloured elements are exactly this closed list, each with its trigger, and any other use fails (F25): **`--fail`** — the row mark when `!ok`, the inspector's Outcome and Error fields when `!ok`, the error state's icon; **`--attn`** — the feed banner's icon, the offline and unauthorised icons; **`--accent`** — the selected row's server name, the focus ring, `Clear filters`, the one prominent action on a replaced-board state. **`--live` appears nowhere** | red-green test enumerating the board's coloured elements against this list, failing on an element not on it and on a listed element rendering the wrong token |
| B9 | Colour is never the only carrier of failure: a failed row's accessibility label begins "failed" and the inspector shows `err` verbatim | red-green test on the label + on the inspector's error field |
| B10 | Monospace covers the age, the session, the duration, the inspector's error, timestamp and numeric fields — and **not** the tool name, the server name, the project name or any sentence (§2, D13) | red-green test over the board's type roles, in both directions |
| B11 | The subtitle is `Showing N calls · since HH:MM · <feed>` — the loaded window's size, `UsageResponse.since`, and the feed's phase. It is unfiltered, and no sentence on the board claims the router's uptime or a completeness watermark | red-green test on the composed string + the copy-honesty suite asserting the absent phrasings |
| B12 | The session column shows the pid and the inspector shows `client · pid N`; a record with no pid shows the em dash on the row and "Unattributed" in the inspector, from one shared constant (D12, D3) | red-green test per case |

### The two filters

| # | Clause | Evidence |
|---|---|---|
| B13 | The session filter and the project filter are **pop-up buttons** — a value shown, an exclusive set — not pull-downs and not segmented controls (§3.6) | red-green test on the control type + AX assertion (Debug) of the running control's role and value |
| B14 | Each filter's options are built from the loaded records only: an option appears if and only if at least one loaded record has that value, and carries that value's call count | red-green test in both directions against a fixture with three directories and two sessions |
| B15 | Filtering by session narrows to records with that `pid`; filtering by directory narrows to records with that `cwd`; the two compose; the session match is on `pid` alone and the client name does not narrow it | red-green test + exercised interaction (Debug): read the row count, apply each filter, apply both, assert the rendered rows each time |
| B16 | Records the router could not attribute appear under **Unattributed** in both filters and are never dropped, and the unattributed key matches only unattributed records | red-green test with a record carrying no `pid` and no `cwd` |
| B17 | While any filter is set the board states what it is hiding — `N of M` — and offers **Clear filters**; neither appears when no filter is set | red-green test at both conditions + exercised interaction |
| B18 | A filter combination matching nothing renders its **own** state, distinct in copy from the empty state, and offers Clear filters | red-green test asserting the two copies differ + AX assertion of the rendered sentence |
| B19 | Filtering re-renders from the already-loaded window: changing a filter issues **no** request to the router | red-green test counting requests through a recording double across a filter change |
| B20 | A filter whose last matching record has rolled out of the window falls back to "all" rather than stranding the board on an option its own menu no longer offers (F35) | red-green test |

### Live behaviour

| # | Clause | Evidence |
|---|---|---|
| B21 | The board backfills with one `GET /usage` at `limit: ActivityRecords.capacity` — 500, matching `RING_SIZE` — and applies **no** server-side filter. The window is capped at that number, so a live feed drops the **oldest** record rather than growing without limit (F13) | exercised request assertion through a recording double + red-green test driving records past the cap and asserting the newest survives |
| B22 | A record that arrives on the stream and is also in the backfill appears once. De-duplication is on `CallRecord.id`, so the same call reported with a different duration is still one row | red-green test both ways |
| B23 | A record that arrived on the stream **before** the backfill returned survives it: the response merges into the window rather than replacing it | red-green test |
| B24 | The subscription is scoped to the board: leaving Activity cancels it, and returning re-backfills rather than showing a stale list | red-green test on cancellation + exercised interaction switching destination and back |
| B25 | The feed's conditions each render distinctly, and **only the spent ones offer a button** (F30): `reconnecting` says the feed dropped and offers nothing, because the retry is already running; `disconnected` after `.live` says it stopped retrying and offers Reconnect; `disconnected` with no prior `.live` says it never connected, in different words, and offers Reconnect (F31); no source configured is none of these and offers nothing | red-green test per condition, driven by phase ordering rather than by scenario — the difference is the sequence, which no scenario can express |
| B26 | **Reconnect now** reloads the history *and* re-subscribes, and the copy says so (F33). Subscribing alone would leave the calls that arrived while the feed was down permanently missing behind a board that never mentions them | red-green test asserting both halves run |
| B27 | A failed reload over a delivering feed keeps the rows and names the missing half — it does not replace the pane with an error (F32) | red-green test with a client that fails `/usage` only |
| B28 | A stream record this version cannot decode leaves the rendered row count unchanged and the phase still `live` — the board half of what `ControlEventStream` already logs (F27) | red-green test feeding a malformed event |

### The inspector

| # | Clause | Evidence |
|---|---|---|
| B29 | Selecting a row opens an inspector carrying the untruncated tool name, the full `cwd`, the session in full, `ms`, the cold/warm statement in words, the timestamp, and `err` where the call failed | red-green test per field + AX assertion (Debug) in the running app |
| B30 | The inspector contains no control that mutates anything | red-green test |
| B31 | The selection is by `CallRecord.id`, so it follows the **record** across a live insert rather than the row index; and a selection the filter hides is cleared rather than left describing an unseen row (F36) | red-green test for each |

### Keyboard and motion

| # | Clause | Evidence |
|---|---|---|
| B32 | `↑`/`↓` move the selection within the visible rows and clamp at both ends; with no selection they select the newest; `Esc` clears it; the keyboard does nothing at all on an empty board | red-green test per key at the model, which is where the decision lives |
| B33 | **`Space` is not claimed by this board.** In a Debug build M1's `KeyClaimProbe` holds first responder and reports the last bare key it received; with Activity selected, `Space` reaching the probe is the assertion that the board did not take it (F20) | exercised interaction over AX by pid, with the configuration named. `↑`/`↓`/`Return`/`Esc` are proven at the model by B32 and are **not** claimed as running-app evidence, because the probe holds focus in the only configuration where fixtures are reachable — stated rather than worked around |
| B34 | Keyboard focus is visible, accent-bound and `MetricToken.focusRing` thick on the board's own controls | measurement of the rendered ring |
| B35 | A record arriving animates on **transform only**, never opacity-from-zero, honours `accessibilityReduceMotion` by removing the movement and not the insertion, and there is no toast (§7, §5 success) | red-green test per moment + a test that the reduced-motion path still inserts the row |
| B36 | The board's **own** controls each carry default / hover / focused / pressed / disabled — the two pop-up buttons, Clear filters, Reconnect now, and the one action on a replaced-board state. Framework-drawn states are not claimed (F28) | red-green test per control per state it authors |

### The nine states, and the board's shape

| # | Clause | Evidence |
|---|---|---|
| B37 | All nine `DESIGN.md` §5 states plus `unauthorized` render, each asserting a **specific observable**. Two are not reachable through a distinct scenario and that is stated rather than papered over (F26): **Disabled** is the filter controls' condition under `.empty`, which is the same scenario as Empty because the same fact causes both; and `.loading` suspends until cancelled, so the loading state is rendered by constructing the model and not awaiting `load()` rather than by awaiting a scenario that never returns | one test per state, each naming its observable and its route |
| B38 | The empty state says nothing has called a tool since the counting window opened, is **not** an error — no error tint, no error icon — and offers no action | red-green test on the copy, the tint and the absence of a control + AX assertion (Debug) in the running app |
| B39 | The loading state is a skeleton at the real row geometry with the column header and the dimmed filters drawn, never a spinner over a blank pane (§5) | measurement comparing skeleton height to populated row height + red-green test on the absence of a progress indicator |
| B40 | The offline and unauthorised copy is `ControlAPIError`'s **verbatim** — one wording per state (§6) — and is constructed *from* the error rather than from a literal | red-green test asserting the `StateMessage` is built from `headline`/`advice`/`actionLabel` + AX assertion (Debug) that the running app carries them |
| B41 | The board renders **outside** the shell's content `ScrollView` and reports its list's scroll geometry through the same callback, so no scroll view nests inside another and the scroll-edge separator behaves identically over a board and over the placeholder (F34) | red-green test on the wiring + the shell's own A34 evidence, re-pointed at a still-scaffolded destination |
| B42 | Both appearances render: the board's token set is asserted against a **declared allowlist** in both appearances — which tokens the board uses, rather than re-testing that `ColorToken` resolves (F29) | red-green test over the allowlist |
| B43 | No file added by this item writes a raw colour, size, radius or font size, and the geometry rule now scans the board's directory as well as the shell's | `scripts/lint/no-raw-design-values.sh`, extended |

---

## The state matrix — real copy, unhappy paths included

Every sentence is the shipped string, asserted against `ActivityCopy`.

| State | Trigger | Copy shipped | Offers |
|---|---|---|---|
| **Default** | records loaded, feed live | `Showing 28 calls · since 09:12 · live` | — |
| **Empty** | window empty, router answered | **No calls yet** / "Nothing has called a tool since 09:12. Servers stay asleep until an agent asks for one — this list fills itself the moment that happens." | nothing (recorded §5 deviation) |
| **Loading** | backfill in flight | skeleton rows at 24pt, column header drawn, filters dimmed | — |
| **Partial — retrying** | feed `reconnecting` | **The live feed dropped. New calls won't appear until it reconnects.** / "The newest call here is from 09:41." | nothing — the retry is already running |
| **Partial — gave up** | feed `disconnected` after `live` | **The live feed stopped retrying.** / "The newest call here is from 09:41. Reconnecting reloads the history as well, so anything that arrived while the feed was down comes back with it." | Reconnect now |
| **Partial — never connected** | feed `disconnected`, never `live` | **The live feed hasn't connected.** / "The history below loaded, but nothing is streaming, so new calls won't appear on their own." | Reconnect now |
| **History unavailable** | `/usage` failed, feed live | **Showing live calls only — the history didn't load.** / the error's own advice | Reconnect now |
| **Error** | `.server` / `.malformedResponse` / `.transport`, nothing loaded | `headline` + `advice` verbatim from the error | the error's own `actionLabel`, nil for these three |
| **Success** | a record arrives | the row slides in at the top on transform only; the count increments; nothing else moves; **no toast** | — |
| **Offline** | `.routerNotRunning` | **The router isn't running** / "Nothing is listening on the control port, so there is nothing to show yet. Starting it takes a moment and your servers stay exactly as you left them." | Start the router |
| **Unauthorised** | `.unauthorized` | **This app isn't authorised to talk to the router** / "The control token was rotated or removed. Re-pair to continue — your servers and their history are untouched." | Re-pair… |
| **Disabled** | no records, so nothing to filter | both filters dim in place; one shared sentence beneath: "Filters need calls to filter. No calls have been recorded yet." | — |
| **Overflow** | server, tool or project wider than its column | truncates at the tail, row stays 24pt, full value in the inspector and in the accessibility label | — |
| **Filtered to nothing** | filters match no loaded record | **No calls match these filters** / "That combination has nothing in it. Clearing the filters shows all 28 again." | Clear filters |

---

## Out of scope, and filed as children

| Child | Title | Suggested deps |
|---|---|---|
| **M2a** | Reset usage history — named-consequence dialog (§9), a new `MenuCommand` in File, and the matching row in M1's command inventory | M2, M1 |
| **M2b** | Free-text search across the call log, binding `⌘F` to it and flipping `MenuCommand.find` off `surfaceAbsent` | M2 |
| **M2c** | Per-server drill-down from Activity into the Servers board once M3 has landed | M2, M3 |
| **M2d** | If the §3.9 reading above is rejected, promote **Clear filters** and **Reconnect now** to menu commands with their inventory rows | M2, M1 |

**Deep links are not in scope (F2).** `?only=mac&pane=activity` is a routing affordance of the
prototype's single HTML page. The Mac app has no URL scheme and this item does not add one; a
`mcprouter://` scheme that selects a destination is worth its own item and is not smuggled in here.

## Shared-surface changes this item makes, and why each is unavoidable

| File | Change | Why |
|---|---|---|
| `ScaffoldPane.swift` | `.activity` added to `BoardRegistry.installed` | the item is defined as this |
| `ShellWindow.swift` | the board renders outside the content `ScrollView` and reports its own scroll geometry | the branch's own comment says "the branch M2–M8 fill in"; the scroll change is F34 |
| `ShellModel.swift` | a lazy `activity` model with an injectable event source | `@State` cannot be initialised from another view's value, and building it in `body` would make a new subscription per evaluation |
| `ShellClientFactory.swift` | `makeEventSource()`, choosing live-or-replay by the same rule as the client | a Debug fixture run must not open a socket to a port with nothing behind it |
| `Icon.swift` | one case, `frost` → `snowflake` | §4 forbids the prototype's `❄` |
| `FixtureControlAPIClient.swift` | `.empty` returns no records; an authored call-log fixture serves the log-shaped scenarios | the double could not produce Activity's empty or overflow state (D11) |
| `ControlFixtureTests.swift` | `usage-call-log` claimed in `expected` (F10) | `everyFixtureIsClaimed` asserts on-disk equals claimed; an unclaimed recording is a failure by design, so the file **must** be claimed. Strengthening, not weakening |
| `ShellIntegrationTests.swift` | "installs no board" becomes "installed and scaffolded are exact complements" | the old assertion pinned a *state* rather than the invariant, and would have failed M2 for doing what it was for |
| `DesignSystemTests.swift` | 21 → 21 + 1, stated as base-plus-reason | a bare 22 would let a symbol appear without a reason |
| `scripts/lint/no-raw-design-values.sh` | the geometry rule scans `MCPRouterUI/Activity` too | a board draws far more geometry than the shell; outside the list it is the largest unguarded surface |
| `scripts/acceptance/mac-shell.sh` | A34's scroll-edge assertion re-pointed from Activity to a still-scaffolded destination | it relied on Activity being a deliberately over-tall placeholder, which M2 replaces. The clause is about the shell's scroll edge and any scaffolded pane proves it |

**The first draft claimed "no merged test file is edited". That was false (F10)** and is corrected
above: four merged files are touched, each additively and each because the old assertion described a
world in which no board had shipped.

No design token is added or changed. No `FixtureControlAPIClient.Scenario` case is added, so
`FixtureClientTests.everyScenarioIsCovered` and `ShellClientFactoryTests`' two `allCases` loops are
untouched.

---

## Assumptions

1. A session is identified by `pid` for the run of one router. A pid reused after a session exits
   would merge two sessions in the filter; the router has no session id to do better with, and
   inventing one would be a fabricated identity.
2. `limit: 500` is the whole of the router's ring at the moment of asking. After a restart
   `readTail()` warms the ring from the last 512 KiB of the log, so it may hold far fewer while
   `since` is unchanged — which is why the subtitle says *showing* rather than a total (F15).
3. The device clock and the router's clock are the same machine's, since the router is loopback. The
   age column would still be well-behaved under skew, because `shortAgo` floors at zero.
