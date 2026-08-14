# spec-I2 — iPhone: Discover and detail

**Status:** Ready for Work
**Depends on:** I1 (iPhone shell and pairing) ✓ merged, F2 (design system) ✓, F3 (control client) ✓.
I3 owns Triage and Queue and is **not merged**; Assumption C records how the commit's destination is
handled without waiting for it.
**Design authority:** `DESIGN.md` (root). **Design representation:**
`design/mocks/i2-phone-discover.html`.
**Practices:** `planning/practices/SWIFT_PRACTICES.md`, `CODING_PRACTICES.md`,
`NEW_PROJECT_BEST_PRACTICES.md` — all binding.

> **This spec was substantially rewritten after its review gate returned 27 findings, 10 of them
> high, every one verified against source before acceptance.** The first draft amended the brief's
> third band correctly and then chose its replacement without checking whether the replacement could
> be populated. The revision is recorded in §Gate verdict rather than smoothed away, because the
> reasoning that produced the first draft is the reasoning a reader should be able to audit.

---

## Feature description

Verbatim from `planning/features-to-triage/I2-ios-discover.md`:

> # I2 — iPhone: Discover and detail
>
> **Depends on:** I1.
>
> Finding capabilities on the go, which is the companion's reason to exist.
>
> - The same three bands as the Mac (recently added / popular / trending over a chosen
>   window), in an iOS idiom.
> - Detail carries the full capability list in plain language before anything can be
>   queued — the security fact is never behind a tap the user can skip.
> - Sending to the Mac is the only commit available, and its button says so.
>
> Deep link: `?only=phone&tab=discover`, `?pdetail=<name>`.

---

## What the router actually observes

Everything below is derived from this section, so it comes first. Every claim was read out of
`src/registry.ts`, `src/control.ts`, `src/config.ts`, `src/usage.ts` and the recorded fixture
`app/Sources/MCPRouterKit/Control/Fixtures/registry-search.json`.

### The endpoint

`GET /registry/search` takes **`q` and `limit` (capped at 60), and nothing else** — no sort
parameter, no window, no offset (`src/control.ts:478-482`). `searchRegistries` merges the official
MCP registry with Smithery, dedupes on a GitHub repo key, enriches some entries from GitHub, **sorts
by `useCount` → `stars` → `updatedAt`, and then truncates with `results.slice(0, limit)`**
(`src/registry.ts:342-352`).

**The client therefore receives the top N *by popularity*, and cannot ask for anything else.** This
single fact governs the whole band design: any other ordering the app applies is a re-sort of a
popularity-selected page, and may only make claims about *the results shown*, never about the index.

### Per entry

| Field | Source | Kind | Coverage |
|---|---|---|---|
| `useCount` | Smithery | cumulative sessions started, all-time | 2 of 3 in fixture |
| `updatedAt` | official `_meta.updatedAt`, **or** Smithery `createdAt` | **two different quantities under one name** — see below | 3 of 3 |
| `stars`, `forks`, `pushedAt`, `archived` | GitHub, via `enrichWithStars` | cumulative / timestamp / flag | 1 of 3 |
| `install` | either index | `{type, command, args, url, requires}` | 3 of 3 |
| `verified` | Smithery, about itself | flag | 0 of 3 |
| `installed` | the router | **a display-name collision test** — see below | computed |
| `source` | the merge | `official` \| `smithery` \| `both` | 3 of 3 |

**`updatedAt` is two quantities.** Official entries take `meta?.updatedAt` — an *update* stamp, so an
entry published years ago and edited yesterday reads as newest (`src/registry.ts:128`). Smithery
entries take `s.createdAt` — a *creation* stamp (`:165`). No copy may call this "when the index
published the entry", because that is true of neither.

**GitHub enrichment is heavily bounded, and its membership is arbitrary.** `enrichWithStars` is
called on the **unsorted** merged map (`src/registry.ts:337`), spends a **budget of 10** fetches per
search (`:222, :239`), and abandons every remaining entry once GitHub returns 403/429 (`:249`).
`repoKey` requires a parseable `github.com/owner/repo` (`:52-56`), and Smithery entries carry
`repository: s.homepage` — a smithery.ai URL (`:166`) — so **the entire Smithery subset is
permanently excluded**. Consequence: `pushedAt`, `stars`, `forks` and `archived` exist for at most 10
of up to 60 results, chosen by merge order rather than by any property, and vanish entirely under an
unauthenticated rate limit (60 requests/hour).

**`installed` is a name-collision heuristic, not an identity match.**
`installed: installed.has(r.displayName)` against the locally declared server keys
(`src/control.ts:486-489`), where `displayName` is `s.name.split('/').pop()` for official
(`registry.ts:123`) and `s.displayName || s.qualifiedName` for Smithery (`:161`) — human labels. A
local server called `github` marks every entry whose last path segment is `github`; the fixture's
Smithery entry is `"GitHub"` and would miss a local `github` on case alone.

**Every Smithery-hosted install declares a required credential unconditionally**
(`src/registry.ts:172-179`), so "needs a credential" carries no signal within that subset.

### Time series

**There is no time series for registry entries.** The only persisted registry-derived state is
`github-cache.json` under `ROUTER_HOME` (`~/.claude/mcp-router`, `src/config.ts:79`), whose record is
`{stars, forks, pushedAt, archived, at}` — current values with one freshness stamp, overwritten on
refresh. No prior value is kept, so no rate, delta or per-window change is computable for any entry.

**The router does keep one real time series, and it is the wrong one for this surface.**
`usage.jsonl` is append-only with `{ts, server, tool, ok, ms}` per call (`src/usage.ts:8-11, :207`).
It was evaluated for this feature and **rejected**: it measures how much *your own Mac* uses servers
you already have, which is a fact about your machine, not about a registry entry's popularity — the
wrong question for a surface whose job is finding things you do not have. Recorded because "no time
series exists" would have been false, and a spec that overstates its grounds is as unreliable as one
that understates them.

### No skills index

No `/skills` route on either router, no `src/skills.ts`, and M4's `SkillFixtures` records that its
endpoint does not exist yet and that a Release build never reaches its fixtures. Both merged indexes
index **servers**. Discover searches servers.

---

## The band design, and why it is two bands

The brief asks for three: "recently added / popular / trending over a chosen window". Measured
against the section above:

| Brief's band | Verdict |
|---|---|
| popular | **Ships.** `useCount` is published, and is the endpoint's own primary sort. |
| recently added | **Ships, re-labelled and re-scoped.** `updatedAt` is on every entry, but it is an update stamp for one index and a creation stamp for the other, and the page it orders was selected by popularity. It becomes **Recently changed**, scoped to the results shown. |
| trending over a chosen window | **Cannot ship.** Requires two observations over time; none exist. |

The obvious replacement for the third — ranking on `pushedAt` as "actively worked on" — was
considered and **rejected**, and the reason is worth stating because it is subtle: the field is
present for at most 10 entries per search, never for Smithery-hosted ones, and **which** 10 is
decided by merge order rather than by any property of the entries. A band is a ranking claim about a
population; ranking on a field whose membership is an artifact of a fetch budget makes a claim the
data cannot support, which is the same defect as the fabricated percentage in a less obvious costume.

**So Discover ships two bands, and the repository activity moves to Detail as a per-entry fact**,
where "Last commit 28 Nov 2025" states something true about one entry and its absence is explained
rather than silently changing a ranking. Recorded as Assumption F, and raised for the user in
§Questions.

---

## Acceptance criteria

### The bands

**A1 — no rate, delta or percentage is displayed anywhere in this feature.**
No band is called "Trending". A test asserts that no rendered string in any Discover or Detail
surface matches a `%`-suffixed figure, and that no view model computes a difference between two
values of the same field. This discharges the open item `DESIGN.md` §10 assigns to whatever ships
Discover, and it is the criterion the whole spec exists to protect.

**A2 — two bands: Most used, then Recently changed.**
Most used is `useCount` desc; Recently changed is `updatedAt` desc. An entry lacking a band's field
is **absent from that band**, never ranked at zero — a missing `useCount` means Smithery does not
index it, which is not the same as nobody using it.

**A3 — every band label is scoped to the results shown, and says what it measures.**
One quiet secondary sentence per band (`DESIGN.md` §6 helper text). No note may assert an index-wide
fact, because the page was selected by popularity before the app saw it (see §What the router
actually observes). `bandRecentlyChangedNote` states the two-stamp difference explicitly.

**A4 — the window filters one band, and the control says which.**
Options: **Any time (default) / 90 days / 30 days / 7 days**, filtering **Recently changed** only.
Most used does not respond: `useCount` is a cumulative all-time total and slicing it by a window
would assert a per-window figure that was never measured. Any time is the default so the first render
is populated; the band ranks on `updatedAt`, and the recorded fixture's newest `updatedAt` is
2025-11-19, which is outside every offered window, so a default that renders an empty band would be
a designed-in empty state. (The fixture also carries a `pushedAt` of 2025-11-28, on a different
entry and on a field this band does not rank on — an earlier draft of this criterion cited that
stamp, which made the argument true by accident rather than by the field it turns on.)

**A5 — each band has its own empty state, distinct from the list's.**
One band empty while the other is populated is the common case, not an edge case, and it is not the
whole-list Empty state. Real copy in the state matrix.

**A6 — the popularity figure is labelled as what Smithery publishes.**
"2,984 sessions on Smithery" — never "installs" and never "downloads". Monospace, since it is
instrument data (`DESIGN.md` §2), and it carries its unit.

**A7 — every numeric string rendered maps to a named `RegistryEntry` field.**
Stated positively so it is checkable — an unbounded "no fabricated figures" is not. The permitted
set is exactly `useCount`, `stars`, `forks`, and dates from `updatedAt` / `pushedAt`. No eval count,
no licence, no category, no download count: nothing on the wire carries them.

**A8 — truncation is disclosed.**
`sources.merged` is `results.length` *before* the slice, so it legitimately exceeds the rows shown
(fixture: merged 5, results 3). No count is rendered from it. When `results.count == limit` the list
says it is showing the first N matches, because a silently truncated list invites the user to
conclude the index holds nothing more.

### Search

**A9 — search is the only filter, because `q` is the only filter the endpoint takes.**
Placeholder "Search the server registries" — plural, because two indexes are searched and either can
fail alone. It never promises skills (there is no skills index).

**A10 — an empty query shows the bands; a non-empty query shows one flat ranked list.**
Bands order the whole page and stop meaning anything once the user has narrowed it. The window
control **dims in place** with its reason beside it, and is never hidden — `DESIGN.md` §3.4 requires
a disabled control to dim in place with a discoverable reason.

### Detail, and the capability plate

**A11 — Detail performs no fetch of its own, and the spec says so rather than describing one.**
Every input Detail renders — `install`, `requires`, `archived`, `pushedAt`, `stars`, `source` —
already arrives inside the search row. No new endpoint is added. Detail's Loading, Partial and Error
are therefore **inherited from the search that produced the row** and are surfaced on the list; the
state matrix records which of the nine are structurally unreachable on this surface and why, rather
than writing plausible copy for a fetch that never happens.

**A12 — the capability plate is drawn, above the commit, never behind a disclosure control.**
The brief's rule: the security fact is never behind a tap the user can skip. Its lines are **derived
from the `install` descriptor**, never authored per entry, and it ends with the literal invocation in
monospace — the evidence the plain-language lines interpret.

**A13 — the plate's lines accumulate; colour precedence is stated.**
The derivations are not mutually exclusive: a `stdio` entry may also require a secret and be
archived. **All matching lines render**, in the table's order, and the plate takes `--attn` if any
attn-row matches. Five derivations:

| Input | Line | Colour |
|---|---|---|
| `install.type == stdio` | runs a program on your Mac, with your own access | `--attn` |
| remote transport (`http`/`sse`) | nothing runs on your Mac; requests go to {host} | fact |
| `install.requires` any `isSecret` | needs a credential, entered on your Mac | `--attn` |
| `archived == true` | the repository is archived; nobody is maintaining it | fact chip |
| `install` absent | neither index says how this runs | fact, commit disabled |

The remote line **names the host**, because for a remote MCP server the decision that matters is that
tool arguments leave the machine — and treating remote as the quiet case inverts the real risk on a
surface whose job is queueing things the user has not examined. It is a fact line rather than
`--attn`: the user is queueing for review, not granting access, and an amber block that fires on
everything stops meaning anything.

**A14 — the credential line states when it carries no signal.**
Every Smithery-hosted install declares a required `Authorization` unconditionally, so within that
subset the line distinguishes nothing. Its copy says the key is Smithery's, not the server's.

**A15 — the fact chips are enumerated, and `verified` is attributed or absent.**
The chips are exactly: `source` (which index), `archived`, and `stars` where present. **`verified` is
not rendered** — it is Smithery's claim about itself, the router does not verify anything, and a bare
"Verified" chip displays an assurance nobody established.

### The commit

**A16 — sending to the Mac is the only commit, and the button says so.**
No install action, no "add to Mac", nothing that could be read as installing. Verb-first
(`DESIGN.md` §6); no ellipsis, because it commits now rather than opening a further view
(`DESIGN.md` §3.4). One prominent accent action per view and this is it.

**A17 — the commit is disabled when no Mac is paired, or when the entry has no `install` descriptor.**
Both, and only these two. With no Mac there is nowhere to write; with no descriptor there is nothing
to queue. It dims **in place** with its reason above it (`DESIGN.md` §3.4), never hidden.

**A18 — the commit stays live when the Mac is unreachable, and its label changes to match the act.**
"Send to Mac" when reachable; **"Save for your Mac" when not**. This diverges from I1's
`SendCommitBar`, deliberately: that is Queue's *send these now* batch control and is right to disable
on `.notReachable`. This writes one item to a local queue, which succeeds with the Mac asleep. The
label changes because a button reading "Send" above a note reading "saved" contradicts itself, and
because a disabled "Send 1 to Mac" on one screen beside a live "Send to Mac" on another, same Mac,
same second, reads as a bug.

**A19 — the predicate is its own, and `canSend` is narrowed in the same change.**
`ConnectionState.canSend` is `self == .reachable` and is documented as "whether a surface that sends
may commit right now" — a general claim `SendCommitBar` binds `.disabled()` to. A18 needs
`canQueue { self != .neverPaired }`, added alongside, and `canSend`'s comment narrowed to "may send
**now**". One property must not answer two questions, or the obvious implementation of A18 silently
ships I1's behaviour while looking correct.

**A20 — the narrowing is one shared constant on every commit surface.**
`PairingCopy.neverInstalls` verbatim, on all **seven** commit states. `DiscoverCopy` gets its own
`narrowingKeys` set, asserted against, so the placement claim has something to check that is not the
thing under test.

**A21 — no copy promises an automatic send, because nothing sends automatically.**
No item owns flush-on-reachable: I3 renders the queue and I1's `SendCommitBar` is a manual batch
control. Copy says where the item is and how it goes — "Send it from Queue when {mac} is back" —
never "it'll go on its own".

**A22 — the queue write is specified and tested.**
I2 defines only the **write port** and the item type; I3 owns the reader and the storage format.
`protocol CapabilityQueueWriter: Sendable { func enqueue(_ item: QueuedCapability) async throws }`,
with `QueuedCapability { id, displayName, source, install, queuedAt }` — the fields Triage needs to
show what is being reviewed. Criteria: an enqueued item survives an app relaunch; enqueueing the same
entry twice is idempotent and does not produce two rows; a refused write renders as a failure and
never as success (I1's `PairingStorageFailureTests` precedent, where a `try?` made a refused Keychain
write render as paired).

**A23 — `installed` is rendered as the name match it is.**
"A server called {name} is already declared on {mac}" — not "this server is already installed". The
router compares display names, and the copy may not assert an identity the comparison cannot
establish. Recorded as a router defect worth fixing, and raised in §Questions.

### States, copy and motion

**A24 — both surfaces ship all nine `DESIGN.md` §5 states with real copy**, or record which are
structurally unreachable and why (A11). Real copy for every unhappy path, in the matrices below.

**A25 — Partial distinguishes the three warning classes.**
`warnings` has three producers: `official registry unreachable: …`, `Smithery unreachable: …`
(`src/registry.ts:301-308`), and two GitHub rate-limit strings (`:251-255`). Each gets its own copy.
Because `searchRegistries` catches per index, the 502 path is nearly unreachable and **warnings are
the realistic degraded surface** — the GitHub rate limit being the likeliest of the three. The wire
carries free text, so classification is by prefix match, **stated as fragile in the code**, and a
warning matching no class renders verbatim under a generic heading rather than being dropped.

**A26 — a Smithery-only entry is Default, not Partial.**
`source: "smithery"` is a merge outcome known at search time, not a failure, and it is the majority
case. Its missing repository data is stated as a fact ("Smithery doesn't publish repository activity
for this entry"), because GitHub was never asked — the homepage is not a parseable repo URL. Partial
is reserved for the case where GitHub *was* asked and refused.

**A27 — Offline means the router is not running.**
`ControlAPIError.routerNotRunning` renders as its own state (`SWIFT_PRACTICES.md` §3), never a
generic network error. The phone reaches the registry *through* the paired Mac's router. `DESIGN.md`
§5 asks Offline to "offer to start it"; the phone cannot start a process on the Mac, so it gives the
instruction instead — **recorded as a deviation with its reason**, not passed off as satisfied.

**A28 — every rendered string comes from `DiscoverCopy`**, keyed surface × state, exhaustive over an
enum so a tenth state fails to compile rather than shipping blank. Asserted three ways as I1's copy
is: pinned literal, rendered-tree assertion, and parity against the design mock. Where copy carries a
substitution, **the template is pinned and its substitutions enumerated**; `{reason}` is a closed
enum of renderings, never a passthrough of the router's free-text error body.

**A29 — 44pt minimum target, safe area, Dynamic Type xSmall–AX3.**
Every control meets 44pt on the hosted view tree. Nothing is occluded by the status bar or home
indicator. **The row's 44pt is a minimum, not a fixed height**: it grows with Dynamic Type, and the
loading skeleton uses the same modifier so it matches the row it replaces at every size. `DESIGN.md`
§5's "rows never change height" is an Overflow rule about long values, and is satisfied by truncating
the name — not by pinning a height that clips at accessibility sizes.

**A30 — motion is transform and opacity only, honours Reduce Motion, and never fades from 0 on entry.**

**A31 — no raw geometry under the Discover views.** Every value reads `PhoneMetric` or a token;
the new files join `PhoneSourceGuardTests`'s scanned set.

**A32 — the Discover tab is reachable and real in the running app.**
`PhoneShell.Tab.discover` no longer resolves to `AwaitingTab`, and the iOS acceptance pass drives the
real surface. A view that compiles behind a tab still rendering the awaiting state does not satisfy
this criterion.

---

## Copy matrix — `DiscoverCopy` (A28)

| Key | Copy |
|---|---|
| `searchPlaceholder` | Search the server registries |
| `bandMostUsed` | Most used |
| `bandMostUsedNote` | Sessions started on Smithery, all-time, of the results shown. The only popularity figure either index publishes — the official registry publishes none, so entries it alone carries are absent from this band rather than ranked at zero. |
| `bandRecentlyChanged` | Recently changed |
| `bandRecentlyChangedNote` | The most recently changed of the results shown. The official registry reports when an entry was last edited; Smithery reports when it was created. They are different stamps under one field, so this orders them without claiming they mean the same thing. |
| `windowLabel` | Chosen window |
| `windowAppliesTo` | The window filters recently changed. Most used is an all-time total and has no window. |
| `windowDisabledInSearch` | Search results aren't windowed. |
| `useCountUnit` | {count} sessions on Smithery |
| `truncated` | Showing the first {count} matches. Narrow the search to see others. |

## State matrix — Discover, the list (A24)

| State | Copy |
|---|---|
| Default | Two bands, populated, Any time. |
| Empty (no query) | Illustration (`Icon.discover`, `PhoneMetric.emptyGlyph`, as I1's `AwaitingTab` draws it). **Nothing came back from either index.** Both registries answered and neither listed anything. — *action: Try again* |
| Empty (query) | Illustration. **No server matches "{query}".** Search covers the official MCP registry and Smithery. Try a shorter word, or clear the search to browse the bands. — *action: Clear search* |
| Empty (one band, A5) | **Nothing in these results changed in the last {window} days.** Widen the window to see more. — *action: Any time* |
| Loading | Skeleton rows using the row's own height modifier, so the board does not jump when data lands. Never a spinner over a blank pane. |
| Partial — official down | **Showing Smithery only.** The official registry didn't answer, so anything it alone lists is missing. — *action: Try again* |
| Partial — Smithery down | **Showing the official registry only.** Smithery didn't answer, so anything it alone lists is missing — including the session counts Most used ranks on. — *action: Try again* |
| Partial — GitHub limited | **Repository details are incomplete.** GitHub limits how often it can be asked, so stars and archive status are missing for some entries. Everything else is complete. |
| Partial — unrecognised warning | **The search reported a problem.** {warning, verbatim} |
| Error | **The registry search failed.** {reason}. Nothing was queued and nothing changed on your Mac. — *action: Try again* |
| Success | Not applicable — the list has no commit. Recorded rather than invented. |
| Offline | **The router isn't running on {mac}.** Discover reads the registries through it, so nothing can be searched until it starts. Open MCP Router on your Mac. |
| Disabled | The window control dims in place while a search is active: *Search results aren't windowed.* |
| Overflow | A long display name truncates on one line; the full value is on Detail. The row grows with Dynamic Type but never with the name (A29). |

## State matrix — Detail (A24)

Detail performs no fetch (A11), so three of the nine are structurally unreachable here. They are
named as such rather than given plausible copy.

| State | Copy |
|---|---|
| Default | Artwork, name, description, fact chips, the capability plate, the commit. |
| Empty | **Unreachable** — Detail is only opened from a row that exists. Recorded, not invented. |
| Loading | **Unreachable** — every field Detail renders arrived with the row. Nothing is skeletoned, because nothing is being fetched. |
| Partial — no repository data | **Smithery doesn't publish repository activity for this entry.** There's no last-commit date or archive status to show. *(A26: a fact, not a failure.)* |
| Partial — GitHub limited | **Repository details are missing for this entry.** GitHub limits how often it can be asked, so the last-commit date and archive status couldn't be fetched this time. |
| Error | **Inherited from the search** (A11). A row cannot exist without a successful search, so Detail has no error of its own. |
| Success | The commit becomes its queued form in place. No toast. |
| Offline | **The router isn't running on {mac}.** You can still save this here — send it from Queue when the router is back. |
| Disabled | **Neither index says how this server runs.** Without an install descriptor there's nothing for your Mac to review. — commit dimmed in place, reason above it |
| Overflow | A long name wraps to two lines in the title and truncates in the collapsed navigation bar; the invocation line scrolls horizontally rather than wrapping mid-token. |

## Commit copy — seven states (A16–A21)

| State | Button | Note |
|---|---|---|
| Reachable | Send to Mac | Reachable — items you send arrive now. |
| Not reachable | **Save for your Mac** | Can't reach {mac} right now. This is saved here; send it from Queue when it's back. |
| Never paired | Send to Mac *(disabled)* | No Mac paired yet, so there's nowhere to send this. — *action: Pair Mac* |
| No install descriptor | Send to Mac *(disabled)* | Neither index says how this server runs, so there's nothing for your Mac to review. |
| Queued, reachable | Queued for your Mac | Waiting for review on {mac}. |
| Queued, not reachable | Saved on this phone | Send it from Queue when {mac} is back. |
| Already declared | Already on your Mac | A server called {name} is already declared on {mac}. |

All seven carry `PairingCopy.neverInstalls` (A20).

---

## Triage — 2026-08-15

### Codebase grounding

- **Data source exists and is recorded.** `ControlAPIClient.searchRegistry(query:limit:)` is F3's,
  merged, with a recorded fixture. No new endpoint is needed and none is added.
- **The shell is I1's and is merged.** `PhoneShell.Tab.discover` currently resolves to `AwaitingTab`;
  this item replaces that branch (A32).
- **`PhoneMetric` is the only file under `Phone/` permitted to write geometry**, enforced by
  `PhoneSourceGuardTests`.
- **`PairingCopy` is the established copy-manifest pattern.** `DiscoverCopy` is a **sibling** enum in
  Kit, not an extension of it — growing a merged shared surface from inside a feature is how two
  features come to disagree about what it contains.
- **`ConnectionState` gains `canQueue` and a narrowed doc comment on `canSend`** (A19). This is the
  one merged type this feature modifies, and the change is additive plus a comment.

### Assumptions — recorded, and each one falsifiable

**A — the brief's "trending" band asks for a *band*, not a percentage.** Falsifiable by the user
saying the percentage was the point; if so the feature cannot ship it and the router needs a snapshot
store first, which is a router item. Taken because "no number displayed that the router does not
observe" is a standing constraint, and a brief does not override one.

**B — a window over an observed timestamp preserves what the brief wanted from "a chosen window".**
Filtering is computable; a rate is not.

**C — I2 owns the queue *write port*; I3 owns the reader and the storage format.** The brief makes
the commit I2's deliverable, so a commit that commits nothing would be a placeholder. Checked: no
queue type exists anywhere in the tree, so there is nothing to collide with. **Reported as a seam I3
must adopt.**

**D — the commit stays live when unreachable, with a different label (A18).** Falsifiable by the user
preferring visual consistency with `SendCommitBar` over correctness of the act.

**E — Discover searches servers only.** Not a preference: there is no skills index.

**F — two bands, not three, and repository activity moves to Detail as a per-entry fact.**
The strongest assumption here and the one most worth challenging. Falsifiable by the user accepting a
band whose membership is capped at 10 and excludes every Smithery-hosted entry. Raised in §Questions.

### Specification Sentinel — product / UX / compliance

- **Product.** The reason to exist survives: finding capabilities on the go, ranked by what is
  actually published, with the security fact before the commit. What is lost is a fabricated
  percentage and a band that would have ranked on a fetch budget.
- **UX.** Two asymmetries are stated on the controls rather than left to be discovered: the window
  drives one band (A4), and search suspends it (A10). The tidier alternatives are false.
- **Compliance.** The phone queues and never installs (A16, A20); no unobserved number is displayed
  (A1, A6, A7, A8, A23); `command`/`args`/`env` are never writable — this feature performs **no PATCH
  at all**, and its only write is a local queue entry.
- **Accessibility.** 44pt targets, safe area, Dynamic Type to AX3, Reduce Motion, colour never the
  only signal (A29, A30). Every amber plate line carries its reason in words.

### Gate verdict — in-family adversarial review

`codex: usage limit → claude (downgrade).` The out-of-family lane is account-limited until
20 Aug 2026 and **exits 0 on that limit**, so it was neither probed nor keyed on. The gate ran
in-family: a fresh `claude -p` opus-5 reviewer briefed to refute, told that finding nothing would be
a failed review. **This is the weaker arrangement — Claude auditing Claude — recorded here so the
weakness travels with the evidence.**

**Returned 27 findings: 10 high, 11 medium, 6 low. Accepted 26, rejected 1.** Every high was verified
against source before acceptance. The four that changed the design:

- **H1** — "no time series anywhere in this product" was **false**: `usage.jsonl` is append-only with
  per-event timestamps, and `ROUTER_HOME` is `~/.claude/mcp-router`, not `~/.mcp-router`. Claim
  narrowed to registry entries; `usage.jsonl` now recorded as evaluated-and-rejected.
- **H4** — the endpoint sorts by popularity and *then* truncates, so every band re-ranks a
  popularity-selected page. All band copy is now scoped to "the results shown".
- **H2** — `pushedAt` exists for ≤10 entries per search, never for Smithery-hosted ones, chosen by
  merge order. The third band was cut entirely (Assumption F) rather than shipped with three
  sentences of caveat.
- **H5** — `updatedAt` is an update stamp for one index and a creation stamp for the other. The band
  is "Recently changed" and its note states the difference.

**The one rejection.** M6 asked for an illustration in Detail's Empty state to satisfy `DESIGN.md`
§5. Rejected: Detail Empty is structurally unreachable (A11) — Detail opens only from an existing
row — and drawing an illustration for a state that cannot occur is scaffolding, not design. The
finding's other half, Discover's missing illustrations, was **accepted** and both Empty rows now
specify the glyph.

---

## Out of scope

- **The Mac's Discover board (M5).** M5 faces the same question and should read
  §What the router actually observes rather than re-deriving it — particularly H4, which constrains
  any banded presentation on either device.
- **Presenting the queue (I3).** I2 writes; I3 reads.
- **Flush-on-reachable.** No item owns it; the copy therefore promises nothing automatic (A21).
  Reported as a child.
- **Evaluations (M7)** — nothing on the wire carries them.
- **A registry snapshot store**, which would make a real trend computable. Reported as a child.
- **A `sort` parameter on `/registry/search`**, which would make index-wide band claims honest.
  Reported as a child.
- **Fixing the `installed` name-collision match** on the router. Reported as a child; A23 makes the
  copy honest in the meantime.
- **Shared design tokens.** `--attnWash`/`--attnLine` are still absent from `ColorToken` (I1 reported
  this); this feature reads `PhoneMetric.tintedBorderOpacity` as I1 does.

## Questions for the user

1. **Two bands instead of three (Assumption F).** The third would rank on a field present for at most
   10 of up to 60 results, absent for every Smithery-hosted entry, with membership decided by fetch
   order. Shipped as a Detail fact instead. Accept, or ship the band with its caveats?
2. **The `installed` flag is a display-name match**, so it can both false-positive and miss on case.
   A23 makes the copy honest; fixing the router is a separate item. Worth scheduling?
