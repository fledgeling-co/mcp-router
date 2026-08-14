# M4: Skills and marketplaces

- **Status:** Ready for Work
- **Depends on:** M1 ✓ (merged), F2 ✓, F3 ✓, F4 ✓, M3 ✓ (merged — its board is the shape this one follows)
- **Design:** `design/mocks/html/m4-skills-board.html` (authoritative), `DESIGN.md` (authority),
  `design/mocks/prototype.html?only=mac&pane=skills` (reference, stale in three places — see D1)
- **Plan:** `planning/plans/plan-M4.md`

---

## Feature description

From `planning/features-to-triage/M4-skills.md`, verbatim in substance:

> The half of the product that is not MCP: skills and plugin marketplaces installed across Claude
> Code, Claude Desktop, Codex/ChatGPT, opencode and Cursor from one place.
>
> - Per-skill: version, marketplace, run count, last run, eval result, and **which clients it is
>   installed into** as a slot row — the same skill can be live in two clients and absent from two
>   others.
> - Auto-update as a visible toggle, never a silent default, with update notifications and a
>   changelog view per version.
> - **Trust decays per version, not at install time.** A new version lands as a shadow copy and
>   promotes automatically only when its capability delta is empty; a version that wants more than
>   the one before it is held for review.
> - Provenance warnings where an upstream owner has changed since install.
> - Marketplace management: add, remove, and see what each one supplies.

Three of those per-skill fields — **run count, last run, eval result** — cannot be delivered, and
this spec says so up front rather than in a footnote. See "What the router cannot observe" below.

---

## The problem this item had to solve first

**The router serves nothing about skills.** `grep -rin skill src/ app/Sources/RouterCore/` returns
zero implementation in either router. M1's merged `Destination.badgeSource` already records the
consequence in a comment: *"the control API serves neither: there is no skills endpoint at all"* —
which is why the Skills row is one of only two sidebar destinations that may never carry a badge.

Two standing constraints then close every easy route:

1. *"The Mac app talks to the router ONLY over the loopback HTTP control API. Do not add a second
   channel."* — so the app may **not** read `~/.claude/skills` itself, however obviously it could.
2. *"No number is displayed that the router does not observe."* — so the board may not be built
   against fixtures and shipped, because `ShellClientFactory` makes a Release build **always**
   `.live`; a fixture-backed board would be a Release build rendering invented data.

Therefore **M4 includes the router-side skills surface**. That is not scope inflation; it is the
only path by which this board can display anything at all. Without it the item ships a screenshot.

### Which router serves it — and the answer that a merged gate forced

The first version of this spec assumed adding two read routes to `src/control.ts` was permitted,
on the reading that the standing constraint forbids *deleting* `src/*.ts` and *touching*
`install.sh` and does neither. **That assumption is false, and the repo enforces the stronger
reading as a test.** `StandingConstraintsTests.theReferenceIsUntouched` (A38, merged) runs

```
git diff --stat main -- src/ install.sh package.json
```

and fails the suite unless it is empty. The TypeScript reference is untouched until R4's parity
gate passes, full stop.

The implementation had already been written and validated against this machine before that gate
ran. It was reverted rather than kept, and the gate was not weakened — `SWIFT_PRACTICES.md` §7 is
explicit that a test is never loosened to make a change pass. What was learned from it is recorded
below and in the appendix, which is the deliverable for whoever does implement it.

So the router-side surface has **no legal home in this item**:

| | Available to M4? | Why |
|---|---|---|
| TypeScript (`src/`) | **No** | A38 forbids it as an executable gate |
| Swift (`RouterCore/`) | **No, in practice** | R2R — the process that actually serves — is in flight and unmerged; R4 records "there is no Swift router process". Routes added here would serve nothing and would collide with the item that owns control serving |

**Consequence, stated plainly rather than hidden.** Against the router a user runs today, this board
renders the version-skew Error state: *"The router sent a response this version doesn't understand
— the router may be newer or older than this app."* That state was designed for exactly this (design
doc §7) and is now load-bearing rather than hypothetical. The populated board is reachable in Debug
through the fixture lane, which is how M1 shipped and how the acceptance gate drives every state.

The endpoint itself is a **deferred child owned by R2R/R4**, with the wire contract, the measured
filesystem facts and a validated algorithm handed over in the appendix.

## What the router actually observes

Every field the board renders traces to a file the router reads. Verified against this machine on
2026-08-14; the shapes below are real, not assumed.

| Field | Source |
|---|---|
| Skill name | the directory name under a client's skills root; `name` in `SKILL.md` frontmatter where present |
| Description | `description` in `SKILL.md` frontmatter |
| Installed into | presence of the skill's directory under **each** client's own skills root |
| Marketplace, and its source | `~/.claude/plugins/known_marketplaces.json` → `source.repo` (github) or `source.path` (directory) |
| Version | `~/.claude/plugins/installed_plugins.json` → `plugins["<skill>@<marketplace>"][].version` |
| Installed at / last updated | the same record's `installedAt`, `lastUpdated` |
| Commit | the same record's `gitCommitSha` |
| Auto-update | `known_marketplaces.json` → `autoUpdate` on the marketplace entry (a real optional field; absent means off) |
| Held version | a version directory under `plugins/cache/<marketplace>/<skill>/` newer than the installed record names |

### The four clients that have a skills mechanism

| Client | Skills root | Slot |
|---|---|---|
| Claude Code | `~/.claude/skills`, plus marketplace plugins under `~/.claude/plugins` | `CC` |
| Codex | `~/.codex/skills` | `CX` |
| Cursor | `~/.cursor/skills` | `CR` |
| opencode | `~/.config/opencode/skills` | `OC` |
| Claude Desktop | **none** — Claude Extensions is a different mechanism | no slot |
| ChatGPT | **none** | no slot |

`MCPClient` already enumerates all six for MCP server discovery. Skills support is a **property of
the client**, modelled as such, so the two without a mechanism render as a capability statement in
the inspector and get no slot in the table. An empty slot would say "not installed here", which
invites an install that has nowhere to go.

## What the router cannot observe, and what happens to it

| Field the brief asks for | Why it cannot ship | Where it goes |
|---|---|---|
| **Run count** | A skill is markdown the *client* loads into an agent's context. It never traverses the router, so the process that would report the count never sees the event. The only trace anywhere is per-client session transcripts, which the router does not read for anything today. | Deferred child, new item |
| **Last run** | As above. `lastUpdated` in the install record is when the *file* changed and is a different number wearing this one's label. | Deferred child, new item |
| **Eval result** | There is no eval runner in this product. | Deferred child, **M7 (Evals)**, which already depends on M4 |

They are **absent from the table**, not rendered as `—` or `0`. An empty cell in a populated table
reads as a per-row claim ("this skill has never run"), which the router cannot distinguish from
"runs constantly, invisibly to me". The absence is stated **once**, in the board's footer, as a
property of the product — which is a claim that is true.

Precedent: M1 refused the Skills sidebar badge the same prototype draws, for the same reason.

---

## What M4 writes, and the one write it does not

Every write here mutates real files in the user's `~/.claude/plugins/` on the machine the router
runs on. That is established product behaviour — the router already rewrites `~/.claude.json` for
server config through `ConfigWriter` — but it sets the bar for what may ship in one item.

| Write | Ships in M4? | Why |
|---|---|---|
| Follow a marketplace | **Yes** | Appends one record to `known_marketplaces.json`. Reversible by removing it; nothing is fetched or executed, so a followed marketplace with nothing installed reads `Supplies nothing`, which is a true observation rather than an error |
| Unfollow a marketplace | **Yes** | Removes that record. Refused, in place and with the count in its reason, while it still supplies installed skills |
| Auto-update on/off | **Yes** | Flips one boolean on the marketplace record. This is the brief's "visible toggle, never a silent default" |
| **Promote a held version** | **No — deferred child** | It is package management (move a cached version directory into place, rewrite `installed_plugins.json`) *plus* a capability-delta engine. AS3 records that no skill manifest format carries a capability list, so the delta has to be **derived by static analysis** of the skill's own files. That is a feature in its own right, and shipping a half-derived delta behind a button labelled `Promote` would put a trust decision on evidence this item cannot stand behind |

**Held versions are still observed and still surfaced.** Detecting one is a directory comparison, not
an analysis: a version in `plugins/cache/<marketplace>/<skill>/` newer than the install record names.
So the board shows the amber `2.2.0 → 2.3.0`, the Held filter counts it, and `Review 2.3.0…` opens a
sheet that states the two versions, the source, and what is known — with `Promote` **disabled in
place, carrying its reason** (§3.4: disabled dims in place and never disappears). The board tells the
truth about a held version and declines to act on evidence it does not have, which is the same
instinct as §9's "the phone queues; it never installs".

---

## The board

### Header

`Skills` · subtitle `{n} skills from {m} marketplaces · {h} held for review`. Every number is a
count of rows the router returned. The held clause is omitted entirely when `h` is zero rather than
reading "0 held". While loading, the subtitle is **empty** — a count that is not yet known is not a
count.

Trailing: `Manage marketplaces…` (the ellipsis means it opens a further view, §3.4).

### Filter — segmented, switches the view in place (§3.6)

`All` · `Held` · `Local` · `Needs attention`, each with its count, and a count is omitted when zero.

- **Held** — a newer version is in the cache than the install record names.
- **Local** — no install record: a directory someone placed in a client's skills folder by hand.
- **Needs attention** — provenance changed, or held. This is the only filter that combines two
  conditions, and it exists because both mean "a human should look at this".

Selecting a filter that matches nothing shows an empty-in-filter message naming the filter, with a
`Show all skills` action — never the first-run empty state, which would claim the user has no skills.

### Columns and rows

| Column | Content |
|---|---|
| tile | 30pt, radius 7 (§4). Real marketplace art where the marketplace ships it; a drawn monogram plate otherwise. **Never a gradient rectangle** (§4). |
| skill | name (500 weight), and beneath it the marketplace — or the provenance warning in `--attn` when the owner has changed, or `local — not from a marketplace` |
| installed into | four slots, `CC CX CR OC`; on / off / **unread** (dashed, when that client's directory could not be read) |
| version | monospace. `2.2.0` normally; `2.2.0 → 2.3.0` in `--attn` when a version is held; `unversioned` in the **body font** for a local skill |
| trailing | `Review {version}…` when held; otherwise nothing |

Row height is fixed and identical in every state including the skeleton. One line per field, tail
truncation, full value in the inspector (§5 Overflow).

**`unversioned` is set in the body font, not monospace**, because §2 reserves monospace for
instrument data and this is a statement about the skill rather than a reading off it. A local skill
has no version anywhere on disk — `SKILL.md` frontmatter carries `name` and `description` only — so
printing `1.0.0` would be invented.

### Footer

> Run counts and evaluation results are not shown. A skill is loaded into an agent's context by the
> client and never reaches the router, so the router does not see it run; evaluations arrive with
> Evals.

Rendered once, at `--t3`, on the populated board only.

---

## The inspector

Trailing panel inside the content zone, at `ServersBoardMetrics.inspectorWidth`, matching M3 — the
shell's split view is two columns and a third would change M1's chrome.

1. **Identity** — 46pt tile, name, marketplace.
2. **Description** — from frontmatter; omitted with no placeholder when the file has none.
3. **Installed into** — names the clients it is in, then the supported clients it is not in, then
   *"Claude Desktop and ChatGPT have no skills mechanism"*. All six accounted for, so the missing
   slots are explained rather than merely absent.
4. **Version** — installed version, and the held version in `--attn` when there is one.
5. **Source** — `github: owner/repo` or `directory: <path>`.
6. **Installed** — date and short commit, monospace.
7. **Auto-update** — states the marketplace's setting, with the toggle.
8. **Actions** — `Review {version}…` (prominent, when held), `Reveal in Finder`.

---

## Sheets

### Review a held version — the trust-decay surface

Title states the finding: **`{skill} {new} is being held`**. Body: *"It was fetched and is being kept
aside rather than installed. Nothing has changed for any client — every session is still running
{old}."*

The sheet states what is **observed**: the installed version and its commit, the held version and
where it was found, the marketplace and its source, and when each arrived. It does not render a
capability delta, because M4 derives none.

In place of one it carries the reason, at `--t3`, as a quiet secondary sentence:

> What this version wants that {old} didn't isn't shown yet. Nothing publishes a skill's
> capabilities, so the comparison has to be read out of the files themselves — and until it is,
> promoting from here would be a trust decision with nothing behind it.

Actions, leading to trailing: `Reveal held version in Finder` · **`Promote to {new}`**, prominent and
**disabled in place** with that same reason (§3.4). `Keep {old}` is **not** offered: keeping is what
is already happening, so a button for it would imply an action where there is none.

### Marketplaces

One row per followed marketplace: name, source, `{n} skills installed` or `Supplies nothing`,
auto-update state, `Remove`.

`Remove` is **disabled with a count in its reason** when the marketplace supplies installed skills:
*"{n} installed skills come from this marketplace. Remove them first."* The count is observed.

`Supplies nothing` is a real observation about a followed marketplace with nothing installed from
it, and is not an error.

### Add a marketplace

One field: `owner/repo, or a folder on this Mac`. Helper text, one quiet secondary sentence (§6):

> Following a marketplace lets it put executable instructions in front of your agents. Skills from a
> new marketplace are held for review the first time, whatever your auto-update setting.

---

## Keyboard and the menu bar

| Key | Behaviour |
|---|---|
| `⌘3` | Select Skills — already bound by M1's `Destination.selectionDigit`; no new binding |
| `⌘F` | Focus the filter field |
| `Return` | Review the selected skill's held version, when it has one — the view's one default action |
| `Esc` | Dismisses the sheet, then clears the selection |
| `↑` `↓` | Move the selection |
| `Space` | **Nothing.** §8 gives it the selected row's breaker; a skill has no breaker, and rebinding it here would teach two habits for one key |
| `⌘N` | Unchanged — "Add server…" belongs to the shell |

Menu items, added to existing menus rather than a new one (§3.9): `Manage marketplaces…`,
`Add a marketplace…`, `Review held version` — the last disabled with a reason when the selection has
none, via M1's existing disabled-reason mechanism.

---

## The nine states (§5) — with real copy

| State | Copy / treatment |
|---|---|
| **Default** | the table |
| **Empty** | *"No skills installed yet"* / *"A skill is a markdown file that teaches an agent how you want a job done. Follow a marketplace and the skills it supplies appear here, across every client that supports them."* / `Add a marketplace…` |
| **Loading** | skeleton rows at the populated row's exact height; blank subtitle; never a spinner |
| **Partial** | *"Cursor's skills folder could not be read, so nothing installed only into Cursor is listed and the slot column understates for every row. Everything below is from the other three clients. `~/.cursor/skills` — permission denied."* Unread slots render dashed, not off. |
| **Error** | from `ControlAPIError`'s own three strings. The likeliest instance is version skew: *"The router sent a response this version doesn't understand"* / *"The router may be newer or older than this app (no skills endpoint)."* — no action, because there is none |
| **Success** | in place, from the record the router returns. The amber arrow goes, the Review button goes, the Held count drops |
| **Offline** | `routerNotRunning`'s own two strings, unchanged from F3, plus `Start the router` **dimmed** with its reason |
| **Disabled** | six controls, each with the reason it shows — tabulated in the design doc §9 |
| **Overflow** | one line, tail truncation, fixed row height, full value in the inspector |

Stale (rows kept under a live error) reuses M3's `StaleReadingBanner` — one wording per state across
the app, not a second set written here.

---

## Acceptance criteria

### The board is installed

- **A1** `.skills` is in `BoardRegistry.installed`, and `ShellIntegrationTests`' existing
  complement assertion passes with it there.
- **A2** Selecting Skills renders `SkillsBoard`, never `ScaffoldPane`. Constructing
  `ScaffoldedDestination(.skills)` returns `nil`.
- **A3** The Release scaffold gate still passes: the sentinel is present iff `scaffolded` is
  non-empty, which it still is.

### The wire contract

M4 owns the contract and the client; the server is R2R/R4's (see above). These are what this item
can actually be held to.

- **A4** `ControlAPIClient` carries `skills()` and `marketplaces()`, so the app has no reason to
  reach for a second channel. A shape that is modelled but not callable is what forces one.
- **A5** Every closed set on the wire is a Swift enum that **fails decoding on an unknown value** —
  no `String` plus a guessing `default`.
- **A6** `SkillSource` is a tagged union whose `.standalone` case has **no version field**, so a
  hand-placed skill cannot be given a version by a careless default. Asserted by decoding.
- **A7** `SkillPresence` has three cases, and `unreadable` is distinct from `absent` on the wire and
  in the board. A boolean would collapse "not installed there" with "we could not look".
- **A8** A `SkillsResponse` whose `skills` key is missing **fails decoding** rather than yielding an
  empty list — the flat-`servers.json` trap `SWIFT_PRACTICES.md` §2 records. Proven red-green.
- **A9** A 404 from `/skills` maps to `malformedResponse`, not `server(status:)`, because a router
  predating this item answers 404 and "The router couldn't complete that" is the wrong sentence for
  "this router does not have the feature".

### What is displayed is what is observed

- **A10** No type in the wire model has a `runs`, `lastRun` or `eval` field, asserted against the
  **encoded JSON** rather than by reflection — reflection sees stored properties and would miss a
  computed property or a `CodingKeys` mapping that still puts a key on the wire. (The first draft
  of this criterion asked for a grep for the string "run", which the spec gate correctly called
  untestable: it collides with "Running" and would pass without the feature working.)
- **A11** A local skill renders `unversioned`, never a version number, and `unversioned` is not in
  the monospace face.
- **A12** Every number in the header subtitle is a count of records the router returned, asserted
  by driving `SkillPresentation.subtitle` with known inputs. A zero held-count is omitted entirely
  rather than rendered "0 held".
- **A13** The two clients with no skills mechanism have no slot, and are named in the inspector as
  having none.
- **A14** Auto-update state is read from the marketplace record; a marketplace with no `autoUpdate`
  key reads as off, never as unknown-rendered-as-on.

### The actions

- **A15** Following a marketplace, unfollowing one, and toggling its auto-update each write through
  the control API, and the row updates from the **returned** record, not from a local guess.
- **A15b** `Promote` is present, prominent and **disabled**, and carries the stated reason. A test
  asserts it is disabled in every state including a fully-loaded writable board — so the day the
  delta engine lands, the test fails and forces the reason to be removed deliberately rather than
  leaving a permanently dead control.
- **A15c** No promote path exists behind the disabled control: no client operation, no route, no
  handler. The control cannot be enabled by a UI edit alone.
- **A16** Every write control is disabled, in place, with its stated reason when the board is stale
  or the router refused.
- **A17** `Remove` on a marketplace supplying installed skills is disabled with the count in its
  reason.
- **A18** The control API's `command`, `args` and `env` guarantee is untouched: nothing added here
  puts any of those three keys on a PATCH body, asserted against the **encoded JSON**.

### The nine states

- **A19** `SkillsBoardStates.treatment` switches over all nine `SurfaceState` cases with no
  `default`, so a tenth case stops the module compiling. This is a compile-time guarantee rather
  than a test, and is described as one.
- **A20** Each unhappy state's copy is the real copy in this spec, asserted as a literal.
- **A21** Offline renders `routerNotRunning`'s two strings unchanged from `ControlAPIError` — no
  second wording.

### The keyboard and the menu bar

- **A22** `⌘F` focuses the filter; `Return` opens the held-version review when the selection has
  one; `Esc` dismisses then clears; `Space` does nothing on this board.
- **A23** Every new command is reachable from the menu bar, and each is disabled with a reason
  rather than hidden when it does not apply.

### Tokens and the native floor

- **A24** No hardcoded colour, size, radius or line height; everything reads `ColorToken`,
  `TypeToken`, `MetricToken`.
- **A25** No indicator colour used decoratively. `--attn` marks held and provenance because both
  mean "wants a human decision"; `--fail` marks nothing on this board that is not failed.
- **A26** Sentence case throughout; the one prominent accent action per view rule holds in every
  sheet; disabled dims in place.
- **A27** Both appearances render; the light column is the authored light palette, not an inversion.

---

## Triage — 2026-08-14

### Grounding — what exists and is reused rather than rebuilt

| Reused | From |
|---|---|
| `ControlAPIError` and its three strings, `ConnectionFailurePane`, `StaleReadingBanner`, `Banner`, `MessageState`, `DisabledAction`, `SkeletonRows` | F3, M3 — reused unmodified, which is what keeps one wording per state |
| `ServersBoardMetrics` | M3 — the derived grid; this board adds its own column widths in the same derived style |
| `MCPClient`, `ClientConfigs` path discovery | R1 — the six clients and where their config lives |
| `Destination.skills`, `selectionDigit` 3, the icon | M1 — already present, no change |
| `BoardRegistry`, `ScaffoldedDestination` | M1 — one line added to `installed` |
| `JSONValue`, `JSONParser`, `ECMAKeyOrder` | R1 — the router's own JSON, so parity is byte-exact |

### Where the code goes

| Path | Why |
|---|---|
| `src/skills.ts` | TypeScript discovery + serialization; the router that actually serves today |
| `src/control.ts` | two routes added; nothing removed |
| `app/Sources/RouterCore/Skills/` | Swift discovery, for parity and for R2R's daemon |
| `app/Sources/MCPRouterKit/Control/SkillModels.swift` | wire DTOs, closed enums |
| `app/Sources/MCPRouterKit/Skills/SkillPresentation.swift` | every *decision* — filters, slot state, version display, copy — headless and testable without a host |
| `app/Sources/MCPRouterUI/Boards/Skills*.swift` | the drawing only |

The split follows M3's, and for M3's stated reason: its two prototype failures were wrong answers
from a branch rather than styling defects, and a branch only a running app can exercise is a branch
that ships wrong.

### Stated deviations from the prototype

- **D1 · The runs, last-run and eval columns are removed.** DESIGN.md outranks the prototype by the
  prototype's own precedence rule, and §6 forbids all three. Recorded above with named future owners.
- **D2 · The slot set is `CC CX CR OC`, not the prototype's `CC CX CDX OC`.** `CDX` was Claude
  Desktop, which has no skills mechanism. Cursor, which has 87 skills on the test machine, was
  missing from the mock entirely.
- **D3 · Auto-update is per marketplace, not per skill.** The real field is on the marketplace
  record. A per-skill toggle would need a store the router does not have, and inventing one to match
  a mock is the wrong direction. The brief's requirement — visible, never a silent default — is met
  at the granularity the data actually has.

### Assumptions recorded — autonomous run, no human to ask

- **AS1 — MADE, THEN PROVEN WRONG BY A MERGED GATE.** The assumption was that adding two read
  routes to `src/control.ts` is permitted because the constraint forbids only deleting `src/*.ts`
  and touching `install.sh`. `StandingConstraintsTests` (A38) enforces the stronger reading and
  failed. The TypeScript work was written, validated against the real filesystem, and then
  reverted; the gate was not weakened. This is the assumption a reviewer should look at first,
  because it was load-bearing and it was wrong.
- **AS2** Write operations mutate `~/.claude/plugins/known_marketplaces.json`, which the router
  already does for server config via `ConfigWriter`. They are implemented behind the same file-write
  discipline and injected `FileSystem` seam, so no test touches a real home directory, and they are
  the one part a reviewer should look at hardest.
- **AS3** "Capability delta" has no source. No skill manifest format publishes one, so it would have
  to be derived by static analysis of the skill's own files — invoked scripts and named network
  hosts. That derivation is a feature, not a field, and M4 therefore **defers promotion** rather than
  shipping a button whose evidence it cannot stand behind. See "What M4 writes".

### Open questions — raised, not guessed

- **Q1** Should the phone see skills at all? §9 says the phone queues and never installs; a
  read-only skills list is consistent with that, but it is I-series scope and is not assumed here.
- **Q2** Run counts would need the router to read per-client session transcripts. That is a real
  feature with a real privacy cost and it is a product decision, not a column.

### Deferred children discovered

| Child | Absorbed by | Why |
|---|---|---|
| **Capability delta + promote a held version** | **new item** | The trust-decay mechanism's acting half. Needs a static-analysis engine that derives what a version wants from its own files, plus package management to move a cached version into place. M4 observes and surfaces held versions; this item acts on them |
| Skill run count and last run | new item | Needs session-transcript observation the router does not do for anything |
| Per-skill eval result | M7 (Evals) | No eval runner exists; M7 owns it and already depends on M4 |
| Installing a skill from the board | M5 (Discover) | Discover is where something is chosen; this board manages what is there |
| Parity vectors for `/skills` and `/marketplaces` in R4's harness | R4 | The endpoints ship with vectors; wiring them into the differential gate is R4's surface |
| Per-skill auto-update | new item | The real field is per marketplace |

### Shared-surface changes wanted and deliberately skipped

- **S1** `ServersBoardMetrics` is servers-named but generic. It wants renaming to `BoardMetrics`.
  Not done — it is M3's shared surface and renaming it touches a merged board. Reported instead.
- **S2** `MessageState` / `Banner` / `DisabledAction` want lifting out of `ServersBoardBanners.swift`
  into a shared file. Same reason: reported, not done. This board imports them where they are.

---

## The spec gate — in-family, and what it found

**codex: usage limit → claude (downgrade).** The out-of-family lane was unavailable for this fleet
(account-level limit to 20 Aug 2026, verified by the orchestrator), so the gate ran as a fresh
`claude -p` Opus reviewer briefed adversarially: refute, and treat an inability to find defects as a
failed review. The weakness travels with the evidence — every reviewer in this pipeline was Claude
auditing Claude.

**Verdict: REJECT, 0 of 6 areas accepted.** Every factual claim it made was checked against the real
filesystem before acting, and every one held.

| # | Finding | Verified how | Outcome |
|---|---|---|---|
| 1 | A plugin is not a skill; `installed_plugins.json` is keyed `<plugin>@<marketplace>` and `vercel` alone holds 30 skills | `python3` over the real file: **96 plugin records**; `ls .../vercel/*/skills` → **30** | **Accepted.** Wire renamed to `pluginVersion`, `siblingSkillCount` added, column headed "plugin version", row names its plugin |
| 2 | Client slots measure symlinks, not installs | `ls -la ~/.cursor/skills` → **87 symlinks** into the plugin cache; `~/.claude`, `~/.codex`, `~/.config/opencode` all link into a shared `~/.agents/skills` | **Accepted.** Identity is the resolved real path. Before the fix one skill reachable from four clients was four rows; after it, **81 skills** correctly dedupe |
| 3 | The Error copy cannot be produced by the path it names — non-2xx maps to `.server`, not `.malformedResponse` | Read `LiveControlAPIClient.swift:197–201` | **Accepted.** 404 on these two reads maps explicitly to `malformedResponse` (A9) |
| 4 | Held-version detection scans a path that is 99% scratch | `ls ~/.claude/plugins/cache \| wc -l` → 692, of which **685** are `temp_git_*` | **Accepted.** Enumerated from each record's own `installPath`, never by walking `cache/` |
| 5 | `ControlAPIClient` was never extended, and it is the only channel | Read the protocol's own doc comment | **Accepted.** `skills()` and `marketplaces()` added; both test doubles implement them explicitly rather than via a default that would return empty |
| 6 | The Swift `RouterCore` half is dead code and is the seam | R4's record that no Swift router process exists | **Accepted, and then overtaken** — A38 closed the TypeScript route too, so the whole server side is deferred |
| 7 | The writes are the weakest part | — | **Accepted.** AS2 withdrawn; the board ships read-only |
| 8 | Untestable or vacuous criteria (A10, A12, A19, A9) | — | **Accepted.** All four rewritten |
| 9 | Missing surfaces: changelog, add-marketplace failures, filter-field contradiction | — | Partly accepted; changelog and add-marketplace failures leave with the writes, and the filter is a segmented control with a separate search field |
| 10 | §6 miscited — it forbids unobserved *numbers*, and an eval result is not one | — | Accepted; the removal stands on the no-runner argument alone |

A second reviewer (`claude-fable-5`) was consulted separately on the scoping question before any
code was written, and endorsed removing the three unobservable columns rather than rendering them
empty: *"Rendering '—' asserts knowledge of absence you don't have; that's fabrication with extra
steps."* It also supplied the rule that an undiscoverable client must read as **unsupported**, a
capability statement, rather than **empty**, a data claim — which is why Claude Desktop and ChatGPT
have no slot at all.

---

## Appendix — the discovery algorithm, validated, for R2R/R4

This was implemented and run against a real machine on 2026-08-14 before A38 forced its removal. The
numbers below are measured, not estimated. Whoever implements the endpoint should not have to
rediscover any of it.

**Inputs**

| Path | Carries |
|---|---|
| `~/.claude/plugins/installed_plugins.json` | `plugins["<plugin>@<marketplace>"][]` → `version`, `installedAt`, `lastUpdated`, `gitCommitSha`, `installPath` |
| `~/.claude/plugins/known_marketplaces.json` | per marketplace: `source.source` (`github`/`directory`), `source.repo` or `source.path`, `lastUpdated`, optional `autoUpdate` |
| `~/.claude/skills`, `~/.codex/skills`, `~/.cursor/skills`, `~/.config/opencode/skills` | per-client skill roots, **overwhelmingly symlinks** |
| `<installPath>/skills/` | the skills a plugin supplies — how Claude Code reaches them |

**Algorithm**

1. For each of the four clients with a skills root: list entries, `realpath` each one, keep those
   resolving to a directory. Record `absent` (no root) and `unreadable` (root exists, listing threw)
   as **distinct** outcomes.
2. Key every skill by its **resolved real path**. Two clients resolving to the same path are one
   skill with two slots.
3. Fold in each installed plugin's own `<installPath>/skills/*` as reachable by **Claude Code** —
   without this step a marketplace supplying 47 skills reports 0, because Claude Code loads a
   plugin's skills from the plugin rather than from `~/.claude/skills`.
4. Attribute a skill to a plugin by `installPath` **prefix match** against the resolved path. Never
   walk `cache/`.
5. A held version is a *different version directory beside the installed one*, found in
   `dirname(installPath)`. Compare capability sets read from each `SKILL.md`; an empty added-set may
   promote, a non-empty one is held.
6. Provenance needs a baseline the client files do not have — they record a commit but never an
   owner. The router must keep its **own** first-seen record (`skills-provenance.json` in the router
   home, written atomically), and the copy must then say "when this Mac first saw this marketplace",
   which is what is actually known.

**Measured on this machine, after the corrections**

| Figure | Value |
|---|---|
| Skills discovered | **161** |
| Reachable from more than one client | **81** |
| Claude Code / Cursor / Codex / opencode | 155 / 87 / 1 / 1 |
| From a plugin / standalone | 144 / 17 |
| With a held version | 68 |
| Marketplaces | 7, from 96 installed plugin records |

**Traps, each of which produced a wrong answer before it was fixed**

- Keying on the directory name instead of the resolved path — one skill became four.
- Walking `cache/` — 685 of 692 entries are `temp_git_*` clone scratch and become invented plugins.
- Reading `~/.claude/skills` alone for Claude Code — reports 0 skills for a marketplace supplying 47.
- Returning `[]` when `installed_plugins.json` lacks its `plugins` key — renders as "every skill you
  have is standalone and unversioned", confidently and silently.
