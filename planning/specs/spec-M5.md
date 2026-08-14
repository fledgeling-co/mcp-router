# M5: Discover — the registry

| | |
|---|---|
| **Status** | Ready for Work |
| **Brief** | `planning/features-to-triage/M5-discover.md` |
| **Plan** | `planning/plans/plan-M5.md` |
| **Depends on** | M4 (merged), M3 (merged), M1 (merged) |
| **Deep link** | `?only=mac&pane=discover` |

---

## Feature description

Browse the merged official + Smithery catalogue and install a server from it. The board is the
one surface in this app whose data is **not the router's own**: it is what two third-party
indexes said, deduped and ranked by the router, with an `installed` flag added locally.

That single fact drives every decision below. On every other board a number is either observed
or absent. Here a number can be observed *for some rows and not others*, and can mean *two
different things depending on which index supplied the row* — and both of those are worse than
absence, because a partial signal presented as a total one is a false claim that looks like a
feature.

---

## The problem this item had to solve first

The brief asks for three bands: **recently added**, **popular**, and **trending** — the last
defined explicitly as "a signed delta over a stated window — 24h / 7d / 30d, the window being
the user's choice, not a hidden editorial one".

The router observes none of the three as stated. This section is the evidence, because the
rest of the spec is a consequence of it.

### What the control API actually serves

One route: `GET /registry/search?q=&limit=`. There is no second registry endpoint, and
`DESIGN.md`'s standing constraint permits no second channel. It fetches both indexes live,
dedupes, enriches with GitHub stars, ranks, slices, and returns:

| Field | Source | Completeness |
|---|---|---|
| `id`, `name`, `displayName`, `description` | both indexes | every row |
| `source` (`official` \| `smithery` \| `both`) | the router's merge | every row |
| `repository` | official `repository.url`; Smithery `homepage` | most rows |
| `version` | official only | official rows only — **Smithery rows carry none** |
| `updatedAt` | **two different meanings — see below** | most rows |
| `useCount` | Smithery only | **Smithery-sourced rows only** |
| `verified` | Smithery only | Smithery-sourced rows only |
| `iconUrl` | Smithery only | Smithery-sourced rows only |
| `stars`, `forks`, `pushedAt`, `archived` | GitHub enrichment | **≤10 rows per call, then never** |
| `install{type,command,args,url,requires[]}` | either index | absent when neither said |
| `installed` | computed by the router against live upstreams | every row |

Envelope: `sources{official,smithery,merged}` and `warnings[]`.

### `updatedAt` carries two different meanings, keyed on `source`

Read off `RegistryMerge.swift`, and the single most important finding in this triage:

- `officialRow` sets `updatedAt` from `_meta`'s first value's `updatedAt` — a genuine
  **registry-entry update** time (`RegistryMerge.swift:117,136`). It is absent when `_meta` is.
- `smitheryRow` sets `updatedAt` from Smithery's **`createdAt`** (`RegistryMerge.swift:164`) —
  a **first-published** date, not an update at all.
- `merge` overrides only `source`, `useCount`, `verified`, `iconUrl` and `install` onto an
  official row (`RegistryMerge.swift:210-217`). **`updatedAt` is not among them**, so a `both`
  row keeps the *official* meaning.

So the meaning is a pure function of `source`: `official` and `both` mean *entry updated*;
`smithery` means *first published*. A column labelled "updated" is therefore false for every
Smithery-only row, and a column labelled "added" is false for every official and `both` row.
**A single recency ordering over the merged set sorts two different clocks against each other.**

### Therefore

| Brief asked for | Ships as | Why |
|---|---|---|
| **trending** — signed delta over 24h/7d/30d | **Not shipped.** Stated once in the footer with its named successor. | No historical store exists anywhere in the product. See below. |
| **popular** — a level | **"Most used on Smithery"**, scoped to Smithery-sourced rows. | `useCount` is complete over that universe and absent outside it. |
| **recently added** | **"Recently added to Smithery"**, scoped to Smithery-sourced rows. | Smithery's field genuinely is an add date; official's is not. |
| (implicit) the cold-catalogue default | **"Best match"** — the router's own merged rank, untouched. | It is the router's ordering, not one this app invented. |

### Why trending cannot ship, precisely

Not because a derived number is forbidden — a delta between two responses this app received
*would* be observed, and `DESIGN.md` §6 bans fabrication rather than derivation. It cannot ship
because of what the number would mean:

- `useCount` is cumulative and Smithery-only, so a diff is a real rate **only for Smithery rows**.
- Each row's baseline `t₀` is whenever it first appeared in a search result *on this Mac*, so
  per-row windows are ragged and non-comparable.
- Star coverage churns between calls (≤10 fetches, hard stop on the first 403/429), so a star
  diff fires on **enrichment coverage**, not on stars.
- The search route is non-deterministic between calls, so consecutive samples are not guaranteed
  to contain the same rows to diff at all.
- A fresh install cannot honour a 30-day window for thirty days.

The honest label for such a number would be "sessions gained on Smithery while your laptop
happened to be open, over a window that differs per row". That is telemetry about the user's own
use of this app, presented as a fact about the ecosystem. It is not shipped.

**Its successor is named rather than left as an apology.** The router is the component that runs
persistently; a snapshot table there makes 24h/7d deltas over `useCount` legitimate within weeks
of it landing. That is recorded as a deferred child (M5-a) and the footer names it, so the
absence reads as scaffolding with a successor rather than as a permanent tombstone.

### Why there is no "most starred" ordering

Stars are *displayed* where present — a star count is a fact the router read from GitHub. They
are never an **ordering**, because enrichment is capped at 10 fetches per call and stops entirely
on the first rate-limit response. An ordering over a field that ≤10 of 60 rows carry, where
*which* 10 changes between calls, is a control that reshuffles its own list for reasons the user
cannot see. That is a broken control, not a caveated one.

### Why there are no rank numbers

The orchestrator's standing note records the search route as non-deterministic — two calls a
second apart differ. A `#1 / #2 / #3` column asserts a stable position. Nothing here is stable
enough to number, so nothing is numbered.

---

## What the prototype draws that is not shipped

`design/mocks/prototype.html` `PANES.discover` is stale in more ways than `DESIGN.md` §10
records. §10 flags only the indicator-colour misuse; the full list:

| Prototype draws | Status | Disposition |
|---|---|---|
| `installs` count (`2,104`) | **Fabricated** — no index publishes an install count | Dropped. `useCount` is *sessions started*, shown as that. |
| trend delta `+218%` / `−8%` | **Fabricated**, and painted in `--live`/`--fail` | Dropped. §2 reserves those hues; §10 assigns this fix to Discover. |
| `eval` column (`not evaluated` / `✓ 8/8`) | **Fabricated** — no eval runner exists in this product | Dropped, exactly as M4 dropped it from Skills. |
| author (`r.by`) | Not observed — no author field on any row | Dropped. |
| licence (`r.lic`, `no licence` in `--fail`) | Not observed | Dropped. |
| categories (`Design` / `Research` / `Testing`) | Not observed — neither index publishes categories | Dropped. |
| `Recently added — 3 this week` | "this week" is not computable; the field is not an add date for most rows | Replaced by the scoped ordering above. |
| window control `24h / 7d / 30d` | Nothing to window | Dropped with trending. |
| rank column `#` | Asserts a stable order | Dropped. |
| Servers / Skills kind toggle | Skills are not in this registry — `/registry/search` serves MCP servers only | Dropped; see Deferred children. |
| the footer's star-coverage sentence | **Correct and kept** — it is the one honest thing on the pane | Kept, computed from `warnings` rather than hardcoded. |

---

## The board

### Header

Title `Discover`. Subtitle states the two indexes and what came back, computed — never a
constant:

> `Official registry · Smithery · 47 servers`

While loading, the subtitle is **empty**. A count that is not yet known is not a count, and
"Loading…" where a number belongs is a worse answer than nothing (M4's rule, adopted).

Trailing: no prominent action. Discover's one primary action lives in the detail sheet, which is
the whole point of detail-then-install — a prominent `Add` in the board header would be a
one-click path from a ranking to executing code.

### Search — a query to two third-party indexes, not a local filter

Placeholder: `Search the registries`. This is materially different from M4's `Filter skills`,
and the copy says so because the behaviour differs:

- It is **debounced at 400 ms** and re-fetches. A fetch per keystroke would issue two
  third-party HTTP requests per character.
- `Return` in the field commits the query immediately without waiting for the debounce.
- An in-flight re-query keeps the **current rows on screen** and marks them as being replaced,
  rather than blanking to a skeleton. Blanking on every keystroke is the same defect as throwing
  away a stale reading.

### Ordering — segmented, switches the view in place (§3.6)

Three segments, each naming the universe it is honest over:

| Segment | Universe | Orders on | Shown per row |
|---|---|---|---|
| `Best match` | every row | the router's own merged rank, untouched | — |
| `Most used on Smithery` | Smithery-sourced rows (`smithery` or `both`) | `useCount` desc | `2,984 sessions` |
| `Recently added to Smithery` | Smithery-sourced rows | `updatedAt` (= Smithery `createdAt`) desc | `added 9 Oct 2025` |

Selecting a scoped segment states what it set aside, immediately under the control, as one quiet
secondary sentence — never silently:

> `14 rows from the official registry are not shown here: it publishes no usage figure.`

A segment whose universe is empty is **disabled in place with its reason** (§3.4 — disabled dims
and never disappears), rather than being hidden:

> `Smithery returned nothing for this search, so there is nothing to order by usage.`

### Rows

Row height is fixed and matches the loading skeleton exactly. Long values truncate; the full
value is in the detail sheet (§5 Overflow). Columns:

| Column | Content | Notes |
|---|---|---|
| tile | 30pt (radius 7) — the row tile size in §4 | Smithery `iconUrl` where present; **a drawn monogram plate otherwise**, never a gradient rectangle (§4) |
| name | `displayName`, body | `name` beneath in `--t3` when it differs |
| source | the provenance mark — see below | |
| figure | the one number this row actually carries, with its unit | `2,984 sessions` · `9 stars` · nothing at all |
| date | labelled by its meaning for **this row's source** | `added 9 Oct 2025` (smithery) · `updated 14 Sep 2025` (official/both) |
| state | `installed`, or a chevron | `installed` is `--t3` text, not a badge — it is a fact, not a status |

**The figure column shows the row's own number and its unit, never a bare integer.** `2,984`
and `9` on adjacent rows under one heading would read as one scale; `2,984 sessions` and
`9 stars` cannot. A row with neither figure shows nothing — not a zero, which would be a claim
that the number was measured and found to be none.

**`archived` is surfaced where GitHub reported it**, because it is observed and it is the single
most useful warning available before install:

> `repository archived`

in `--attn` (this genuinely wants a human decision), with the word carrying the meaning so
colour is never the only signal (§2).

### The provenance mark — Discover's subject-mined element

`DESIGN.md` §10 records that the breaker is the app's only subject-mined element and that a board
of stock tables has "one signature and eight defaults". Discover's central fact is *which index
said this*, and a merged catalogue where that is a grey text pill is a merged catalogue pretending
to be one list.

The mark is a **two-cell plate**: a left cell for the official registry and a right cell for
Smithery, each filled when that index supplied the row and drawn as an empty recess when it did
not — the same recess logic as the breaker slot, which is the app's established vocabulary for
"a place where a thing would be". A `both` row shows both cells filled, and is the only row shape
that does. `verified` (Smithery's flag, observed) adds a check to the Smithery cell.

This is a **board-local element built from existing tokens**. It introduces no new shared token,
no new colour, and no change to any shared component — see *Shared-surface changes wanted and
deliberately skipped*.

### Footer — where the incompleteness is stated

The brief's rule: "Where a count is incomplete, say so in the footer rather than presenting a
partial ranking as total." Four sentences, each appearing **only when its condition holds**, each
computed:

1. **Sliced** — `sources.merged > results.count`:
   > `Showing 30 of 47 that matched. The rest are not ranked lower — they are past the limit this search asked for.`
2. **An index did not answer** — from `warnings`:
   > `The official registry did not answer (HTTP 503), so everything here came from Smithery alone and nothing official is missing on purpose.`
3. **Star coverage** — from `warnings`:
   > `GitHub allows 60 requests an hour without a token, so star counts cover some rows and not others. Rows without one are not less popular; they are unmeasured.`
4. **Trending, stated once** — always:
   > `No trend or velocity figure is shown. Measuring one needs a history of these indexes over time, which the router does not keep yet.`

Sentence 4 is the resolution of the second opinion's fair objection that a permanent absence
plaque teaches users the board is half-built: it is one quiet `--t3` caption line in a footer
that already carries three other honesty notes, not a band, not a panel, and it names the
successor rather than apologising.

---

## The detail sheet — the whole point of detail-then-install

Opening a row **never installs**. The sheet is reached by click, by `Return` on a selected row,
or by `⌘↓`. Its structure, top to bottom:

1. **Identity** — 64pt tile (radius 14, §4), `displayName`, `name`, the provenance mark expanded
   to words (`In the official registry and on Smithery`), `verified` where Smithery said so,
   `version` where the official registry said so.
2. **Description** — the index's own text, in full, never truncated here.
3. **What this will do** — the capability statement. See below.
4. **What it asks you for** — `install.requires[]`, one row each, `isSecret` marked.
5. **Repository** — a link, and `archived` stated if GitHub said so.
6. **The action bar** — cancel leads, one prominent accent-filled action trailing (§3.4).

### The capability statement — a reading, and labelled as one

The brief requires "every entry states its capabilities in plain language before install — what
it reads, what it contacts, whether it runs shell". **No index publishes a capability manifest.**
The only honest source is the install block itself, which is a fact the index published, so the
statement is a *reading of the install block* and says so — the same discipline M4 applied to its
`capabilityDerivation` sentence.

For `install.type == .stdio`:

> **Runs a program on this Mac.**
> `npx -y @modelcontextprotocol/server-github`
> It runs with your user account, which means it can read and write the same files you can and
> open the same network connections. Nothing declares what it will actually do, and that cannot
> be checked before it runs.

For `install.type == .http`:

> **Connects to `server.smithery.ai`.**
> Nothing runs on this Mac. What that host does with what you send it is not declared here.

When `install` is **absent entirely** (a real case — it is optional on the wire):

> **Neither index says how to run this.**
> There is nothing to add. The entry exists in the catalogue but carries no command and no URL.

The command line is shown **verbatim, in the instrument face** (§2 — monospace is for instrument
data, and a command line is the most literal instrument datum in the product). The claim that it
"runs shell" is answered by showing the actual argv rather than by a boolean, because the argv is
what is true.

### What it asks you for

Each `RegistryRequirement` renders name, description, and whether it is secret. A secret is
marked as one and its field is a secure entry. The values the user types are sent to the router
as part of `add(NewServer)` — in `env` for stdio, in `headers` for HTTP — and this is stated
plainly rather than implied:

> `Sent to the router, which stores it in your router config. It is not put in the keychain.`

That sentence is deliberately unflattering and deliberately accurate; it must be re-verified
against the router's storage during work and corrected if the router's behaviour differs.

### The action, and its label

`DESIGN.md` §3.4: `…` means "opens a further view", its absence means "commits now". The label is
therefore a decision, not a constant:

| Condition | Label | Behaviour |
|---|---|---|
| `install.requires` is empty or absent | `Add GitHub` | commits immediately |
| `install.requires` is non-empty | `Add GitHub…` | reveals the requirement fields; commits on the second press |
| `installed == true` | `Added` (disabled, dimmed in place) | reason beside it: `Already declared as "github".` |
| `install == nil` | `Add GitHub` (disabled) | reason: `Neither index says how to run this.` |

The action is the view's **one** prominent accent-filled control (§3.4), trailing, with `Cancel`
leading.

### Success is an in-place state change

macOS does not toast a click (§5). On success the sheet's action becomes `Added` and disabled,
the row behind it gains `installed`, and the sheet stays open so the user can read what they just
did. Failure renders adjacent to the action, non-blaming, stating the fix:

> `The router refused: a server called "github" is already declared. Rename it or remove the existing one first.`

---

## The nine states (§5) — with real copy

| State | Copy and behaviour |
|---|---|
| **Default** | The populated list, ordering control, search, footer notes as they apply. |
| **Empty — first open** | Both indexes answered and the merged set is empty. **Title:** `Neither index returned anything` · **Detail:** `The official registry and Smithery both answered, and neither lists a server right now. That is unusual — it is more often a sign the indexes are having a bad day than that the catalogue is empty.` · **Action:** `Search again` |
| **Empty — a query matched nothing** | **Title:** `Nothing matches “postgres tunnel”` · **Detail:** `Neither index has a server whose name or description contains that. The indexes match on whole words, so a shorter query often finds more.` · **Action:** `Clear search` |
| **Empty — a scoped ordering** | **Title:** `Smithery returned nothing for this search` · **Detail:** `Usage figures come from Smithery, and none of these rows came from it. The other 14 are still here under best match.` · **Action:** `Show best match` |
| **Loading** | Skeleton rows at the exact populated row height, never a spinner over a blank pane. This board's loading is genuinely slow — two live third-party calls with a 12 s timeout — so the skeleton is what the user looks at, not a flash. |
| **Partial** | The four footer sentences above, each computed and each appearing only when true. A partial result renders its rows *and* its shortfall; it never renders as either a clean success or a failure. |
| **Error** | Both indexes failed, or the router answered 502. **Title:** `The registries could not be reached` · **Detail:** `The router answered, but neither the official registry nor Smithery did. Your servers are unaffected — this board is the only thing that needs them.` · **Action:** `Try again` |
| **Success** | In-place: the action becomes `Added` and disabled, the row gains `installed`. No toast, no dismissal, no animation beyond the state change. |
| **Offline** | `routerNotRunning` renders the shell's shared offline pane — the router is loopback, so this means the daemon is not running on this Mac, and the pane offers to start it. Never conflated with the Error state above, which means the *router* answered and the *indexes* did not. |
| **Disabled** | Every disabled control dims in place with its reason adjacent: the `Add` button when installed or uninstallable, a scoped ordering segment whose universe is empty. Nothing disappears. |
| **Overflow** | Long `displayName` and `description` truncate at the row with the full value in the sheet. **Rows never change height** — the skeleton and the populated row are the same fixed height, so the board does not jump when data lands. |

Every control additionally carries default / hover / focus-visible / active / disabled.

---

## Keyboard and the menu bar (§8)

| Key | Behaviour on Discover |
|---|---|
| `⌘F` | Focus the search field (via the shell's existing focus-request counter) |
| `Return` | Opens the detail sheet for the selected row. **Never installs** — that would be exactly the one-click path from a ranking to executing code the brief forbids. Inside the sheet, `Return` commits the sheet's default action. |
| `Esc` | Dismisses the sheet; if no sheet, clears the selection. Never both at once. |
| `↑` / `↓` | Move the selection through the *visible* rows |
| `Space` | **Not handled.** It toggles a breaker on Servers and has no meaning here, so it is left unswallowed rather than repurposed. |
| `⌘N` | Unchanged — the shell's global `Add server…`, which is M3's manual path and not this board's |

Focus order runs sidebar → search → ordering → table → sheet. Focus rings are visible,
accent-bound, 2pt.

---

## Acceptance criteria

### A1 — The board is installed, not scaffolded

- `.discover` is a member of `BoardRegistry.installed`.
- `ShellIntegrationTests`'s three tripwires (exact-complement both ways, the exact installed set,
  the scaffolded count) are updated in the same change and pass.
- Selecting Discover renders `DiscoverBoard` and **not** `ScaffoldPane`; `ScaffoldedDestination(.discover)` is `nil`.

### A2 — Nothing is displayed that the router does not observe

- No install count, trend delta, eval verdict, author, licence, category, rank number or window
  control appears anywhere in the Discover sources. Asserted by a test that greps the shipped
  source for the prototype's fabricated field names, so a future edit re-adding one fails.
- Every figure rendered carries its unit and its universe.
- A row with no figure renders nothing in that column — never `0`.

### A3 — `updatedAt`'s two meanings are honoured

- A Kit function maps `source` to the date's meaning: `official` and `both` → *entry updated*;
  `smithery` → *first published*.
- Red-green: flipping the mapping makes the test fail.
- No ordering sorts the two meanings against each other; the recency ordering is scoped to
  Smithery-sourced rows.

### A4 — Scoped orderings state their universe

- `Most used on Smithery` and `Recently added to Smithery` include only rows whose `source` is
  `smithery` or `both`.
- Each states the count it excluded, computed from the response.
- Each renders disabled with its reason when its universe is empty.
- `Best match` preserves the router's order **exactly** — asserted by comparing against the
  response's own sequence, so a client-side re-sort cannot creep in.

### A5 — Detail-then-install

- No control in the board list installs anything. Asserted behaviourally: exercising every row
  affordance produces no `add` call on a recording client.
- `Return` on a selected row opens the sheet and issues no write.
- The sheet's action label carries `…` iff `install.requires` is non-empty.
- The action is disabled with a stated reason when `installed` or when `install` is absent.

### A6 — The capability statement is a reading of the install block

- stdio renders the verbatim argv in the instrument face and the "runs with your user account"
  sentence.
- http renders the host and the "nothing runs on this Mac" sentence.
- A missing `install` renders the "neither index says how to run this" state and a disabled action.
- The statement is never presented as author-declared.

### A7 — Partiality is stated, never smoothed

- Each of the four footer sentences appears iff its condition holds, and each is computed from
  the response (`sources`, `results.count`, `warnings`) rather than hardcoded.
- A sliced response states the slice.
- A response with an index warning states which index and renders the rows it did get.

### A8 — The nine states

- Each of the states above is reachable in a test through the fixture client, and each renders
  its own copy.
- Offline (`routerNotRunning`) is distinguishable from Error (indexes unreachable) — different
  panes, different words.
- The loading skeleton's row height equals the populated row height.

### A9 — Tokens and the native floor

- No hardcoded colour, size, radius or line height; everything reads `ColorToken` / `TypeToken` /
  `MetricToken`.
- No indicator colour used decoratively. `--attn` appears only on `archived`, which genuinely
  wants a human decision.
- Sentence case throughout; no tracked uppercase.
- One prominent accent-filled action per view, trailing, in the sheet and nowhere else.
- Both appearances render; the light palette is not an inversion.

### A10 — Search behaviour

- Typing does not issue a request per keystroke — debounced, asserted by counting requests on a
  recording client across a burst of input.
- An in-flight re-query keeps the previous rows visible rather than blanking.
- A failed re-query keeps the last good rows and labels them, rather than discarding them.

---

## Triage — 2026-08-14

### Grounding — what exists and is reused rather than rebuilt

| Need | Exists | Where |
|---|---|---|
| Registry wire shapes | **Yes, complete** | `MCPRouterKit/Control/RegistryModels.swift` |
| `searchRegistry(query:limit:)` | **Yes** | `ControlAPIClient` |
| A captured real fixture | **Yes** | `MCPRouterKit/Control/Fixtures/registry-search.json` |
| `add(NewServer, force:)` for install | **Yes** | `ControlAPIClient` |
| Load-state shape (loading/loaded/stale/failed) | **Yes** — M4's, adopted wholesale | `SkillsBoardModel` |
| Offline pane, failure pane, stale banner, message state | **Yes** | M3/M4 shared board views |
| Search field | **Yes** | `SkillsBoard.swift`'s `SearchField` |
| Board registration | **Yes** | `BoardRegistry.installed` |
| Relative/absolute date formatting | **Yes** | `MCPRouterKit/Formatting/RelativeTime.swift` |

Nothing new is needed on the router side. This is a pure app item over an endpoint that already
ships.

### Where the code goes

Following M4's split exactly — every decision in Kit, testable without a host; the view is a
`switch` that draws answers and decides nothing.

| File | Contents |
|---|---|
| `MCPRouterKit/Registry/RegistryPresentation.swift` | Ordering, universes, exclusion counts, the date-meaning mapping, figure formatting, footer sentences, empty messages |
| `MCPRouterKit/Registry/RegistryCapability.swift` | The capability reading of the install block, and the action-label decision |
| `MCPRouterUI/Boards/DiscoverBoard.swift` | The view |
| `MCPRouterUI/Boards/DiscoverBoardModel.swift` | Load state, debounce, selection, sheet, install |
| `MCPRouterUI/Boards/DiscoverBoardRow.swift` | The row and the provenance mark |
| `MCPRouterUI/Boards/DiscoverDetailSheet.swift` | The detail sheet |
| `MCPRouterUI/Boards/DiscoverBoardMetrics.swift` | Board geometry, from tokens |

### Stated deviations from the brief

1. **Trending is not shipped**, and the window control is not shipped with it. Reason and
   successor above. This is the one place this spec refuses its brief, and it is refused rather
   than faked because the alternative is a fabricated number on a security-sensitive surface.
2. **"Recently added" is scoped to Smithery** rather than offered over the merged set, because
   `updatedAt` is not an add date for official or `both` rows.
3. **"Popular" is scoped to Smithery** rather than offered over the merged set, because a merged
   popularity ordering is structurally biased by source and reshuffles on enrichment coverage.
4. **The three bands are one list with an ordering control**, not three stacked sections. Three
   stacked bands over one ≤60-row response would show the same rows three times.

### Assumptions recorded — autonomous run, no human to ask

1. **The debounce is 400 ms.** Nothing specifies it; it is short enough to feel responsive and
   long enough that a typed word is one request rather than eight.
2. **Requirement values are sent to the router, not stored in the keychain.** Stated as such in
   the sheet. To be re-verified against the router's storage during work; if the router does
   something else, the sentence changes rather than being dropped.
3. **Skills are out of scope for this board.** `/registry/search` serves MCP servers; the
   prototype's Servers/Skills toggle has no endpoint behind it for skills. M4 owns skills and
   marketplaces.
4. **`⌘↓` opens the detail sheet** in addition to `Return`, matching the Finder idiom for
   "open the selection".

### Open questions — raised, not guessed

1. Should the router grow a registry snapshot table so trending becomes measurable? Recorded as
   deferred child M5-a; not decided here.
2. Should `Best match` explain the router's ranking rule in the footer? Currently it does not —
   adding it would make four honesty sentences into five.

### Deferred children discovered

| Suggested id | Title | Depends on | Why |
|---|---|---|---|
| **M5-a** | Router-side registry snapshot store, and the trending band it makes possible | R3 (control), M5 | The only honest route to a velocity figure. The router runs persistently; the app does not. |
| **M5-b** | Registry search for skills and marketplaces | M4, M5 | The prototype's Servers/Skills toggle has no endpoint. Needs a router route before any UI. |
| **M5-c** | GitHub token in settings, to lift star coverage | M8, M5 | `GITHUB_TOKEN` raises the 60/hour limit; the footer currently just explains the shortfall. |

### Shared-surface changes wanted and deliberately skipped

1. **A shared `Badge` component.** Three boards now draw their own small labelled marks. Not
   built here — it would touch M3's and M4's rendered surfaces, which are merged and evidenced.
2. **`--attn` on `--raised` contrast.** `DESIGN.md` §10 records two dark-palette shortfalls on
   `--raised`; `archived` in `--attn` sits near that class of problem. Not altered in passing, per
   §10's own instruction.
3. **A shared honesty-footer component.** M4 has `observationFooter`, M5 has four computed
   sentences. A shared component is the right end state and is not this item's to build.

---

## The spec gate — in-family, and what it found

`codex: usage limit → claude (downgrade)`. The out-of-family lane (`gpt-5.6-sol`) is
account-limited past this fleet's horizon, verified by the orchestrator on 2026-08-14, so the
spec review ran as a fresh adversarial `claude -p` opus-5 reviewer instead. The weakness travels
with the evidence: every reviewer in this item's pipeline is Claude auditing Claude.

*(Filled in below by the gate run.)*
