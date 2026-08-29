# F8: cross-harness skill profiles — the sync already happened, and it rotted

**Category:** router · **Brief:** `planning/features-to-triage/F-cross-harness-skill-sync.md`
**Depends on:** R28 (the router holds skills, plugins and marketplaces) — merged `784dde9`.
**Settles against:** R29 (what can be pushed to a live session), R7 §7 (this router does not
write a harness's MCP configuration).

The brief proposes a central marketplace that propagates outward: define a bundle, push it to
every harness, one click aligns them all. **On the machine the brief was written on, the
propagation already exists, it was done with symlinks, and 27 of the 87 links are dangling.**
Nothing told anybody. So the product is not a pusher. It is the reading that says which harness
holds what, and a projection that says what a profile would require — rendered, never applied.

Which half of R29's split each piece sits on is stated in §3, and the answer for **every** piece
that touches another harness is *neither*: a durable write with no live effect, or a refusal.

---

## 1 · What was measured

Read-only, on the author's machine, **2026-08-29**, with `python3` listing each candidate root and
calling `os.path.islink` and `os.path.exists` on every entry. No file was opened; no value from
any harness's tree is reproduced here. What was taken is shape and counts.

### 1.1 · Five harnesses carry a skills root, and one root serves two of them

| `MCPClient` case | root | entries | symlinks | dangling |
|---|---|---|---|---|
| `claudeCode` | `~/.claude/skills` | 23 | 21 | **1** |
| `claudeDesktop` | `~/Library/Application Support/Claude/skills` | — | — | **absent** |
| `codexCLI` | `~/.codex/skills` | 1 | 1 | 0 |
| `chatGPTCLI` | `~/.codex/skills` — *the same directory* | 1 | 1 | 0 |
| `cursor` | `~/.cursor/skills` | **87** | **87** | **27** |
| `cursor` (second root) | `~/.cursor/skills-cursor` | 22 | 0 | 0 |
| `geminiCLI` | `~/.gemini/skills` | 1 | 1 | 0 |
| `grokCLI` | `~/.grok/skills` | — | — | **absent** |
| `opencode` | `~/.config/opencode/skills` | 1 | 1 | 0 |

Four readings out of that table decide the design, and three of them refute the brief.

- **Cursor is 31% rot.** 27 of its 87 links resolve to nothing. Every one of the 86 non-trivial
  links points into `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/skills/<name>`, and
  a version directory is what an upgrade replaces. So the links break as a *consequence of
  keeping Claude up to date*, silently, and the harness that loses the skill is not the one the
  upgrade happened in. **This is the drift the brief asks to detect, present before F8 writes a
  line.**
- **The two sets are all but disjoint.** `claudeCode ∩ cursor` is **1** name. `claudeCode \
  cursor` is 22 and `cursor \ claudeCode` is 86; the union across every root is **130**. There is
  no "the skills on this machine" to synchronise *to* — there are several unequal sets that share
  a word.
- **A harness's skill root is not one directory per harness.** Cursor has two with different
  shapes (87 symlinks into Claude's cache; 22 real directories), and Codex and ChatGPT share one.
  A model of one root per `MCPClient` case is wrong in both directions at once.
- **Claude Code's own root mostly points somewhere neither harness owns** — 20 of its 23 links
  resolve under `~/.agents/skills`, a third tree. Treating `~/.claude/skills` as the origin would
  make the origin a set of pointers.

### 1.2 · The router holds nothing to select over, on this machine

`~/.claude/mcp-router/extensions` does not exist. R28's store is real and it is **Swift-only**,
supplied at `extensions: DiskExtensionStore(root: home.extensionsPath, clock: clock)`,
`app/Sources/RouterCore/Service/RouterServiceDispatch.swift:228` at `08a24ed`, while the installed
default is still the TypeScript router (ORCHESTRATOR.md standing decision 1). An empty store is
the ordinary state here and is reported as **empty**, never as unreadable.

### 1.3 · The tell half is in the other binary

R29's measured 87 ms path is `await stream.send({ jsonrpc: '2.0', method:
'notifications/tools/list_changed' });`, `src/livereload.ts:152` at `08a24ed` — **TypeScript**.
`git grep list_changed app/Sources` returns nothing. So the one mechanism that can make a live
session re-read anything without a person does not exist in the binary that holds the profiles.

And the socket half only asks, whichever binary sends it. A pushed slash command reaches the
receiver as text — `in the body is a string the` receiving model reads, `src/sessions.ts:17` at
`08a24ed`. Skills and plugins have no protocol equivalent at all.

---

## 2 · What this builds

A **profile** is a named selection over the router's own store, plus the names of the router
upstreams it wants served. It is a record on the router's own disk and it changes nothing else.

A **projection** takes one profile and the machine's harness skill roots and answers, per harness,
what that harness would have to hold — as steps that are read, not applied.

- `ProfileRecord` + `DiskProfileStore` at `<router home>/profiles/<name>.json`. Written the way
  R28's store writes: every refusal decided before a byte lands, the write staged and renamed,
  a removal moved to `.removed/<name>/<millis>` rather than deleted.
- `SkillRootInventory` — one harness skill root, read-only: every entry classified `directory`,
  `link`, or `dangling`, with the count of each. `dangling` is the finding §1.1 measured.
- `ProfileProjection` — profile × store listing × inventories → `ProfileStep`s, each carrying its
  reach (§3) and each naming what it would change. `render()` produces the diff a person reads,
  in `ReconciliationPlan`'s deliberately-not-a-patch shape.
- Control routes `GET /profiles`, `GET /profiles/:name`, `POST /profiles/:name`,
  `DELETE /profiles/:name`, `GET /profiles/:name/projection`.

  **`POST` and not `PUT`, and the method was chosen by a failing test.**
  `ControlAPIRequest.isMutating` — the property the token and content-type gate reads — is
  `POST || DELETE || PATCH`, ported from `src/control.ts`, and **PUT is not in it**. No route
  served PUT before this family, so nothing was ever exposed; this would have been the first, and
  an untokened `PUT /profiles/x` measured **200** while the rest of the suite was green. Widening
  `isMutating` would have changed a ported gate `scripts/acceptance/parity-manifest-check.sh`
  derives from the reference in both directions, to buy a verb. `A8` holds the invariant instead.

**Nothing applies a projection.** There is no writer for a harness skill root anywhere in
`app/Sources`, exactly as there is none for a harness MCP config —
`no conformer anywhere in`, `app/Sources/RouterCore/Discovery/ReconciliationPlan.swift:6` at
`08a24ed` is the precedent, and F8 extends the same discipline one kind further rather than
making an exception for it.

---

## 3 · Which half of R29's split each piece sits on

R29 named two: the router **tells** (`notifications/tools/list_changed`, no model, no person) and
the router **asks** (a socket message the receiver enqueues as text). F8 needs a third word,
because most of what it touches reaches neither — bytes that land on disk and no live session is
made to re-read them.

| piece | half | why |
|---|---|---|
| the profile record on `<router home>/profiles` | **the router's own** | its own disk, its own file; no other process is involved |
| `SkillRootInventory` over a harness root | **read-only** | a reading, and the deliverable |
| a step that would add or repair a skill link in a harness root | **durable, no live effect** | the bytes would persist; §1.3 — skills have no protocol reload and the socket only asks |
| a step that changes the router's served server set | **tell — in the other binary** | `src/livereload.ts:152` at `08a24ed` is TypeScript; this router has no counterpart, so F8 reports the mechanism and does not claim it |
| a step that would need a harness MCP config write | **refused** | R7 §7 and `scripts/lint/no-harness-config-writes.sh`; `the write is R7-C2's, behind a human`, `planning/specs/spec-R7.md:391` at `08a24ed` |
| telling a live session a profile moved | **ask only, default off** | R29 §2.2; it reports `delivered`, never `reloaded` |

`ProfileReach` carries three cases and all three occur on the real machine, so none of them is a
branch nothing reaches: a skill step is `durable`, a server step is `tellElsewhere`, and a harness
MCP config step is `refused`.

**The brief's fourth acceptance line — "single-click sync to align all harnesses" — is refused,
and for two independent reasons.** The router does not write another program's configuration
(R7 §7), and even where it wrote the bytes, nothing would make a running session read them
(§1.3). Either reason alone is sufficient; recording both means closing one does not silently
open the door.

---

## 4 · Acceptance

| ID | Criterion | Proved by |
|---|---|---|
| A1 | A profile can be created, read, listed and removed, and a removal is recoverable | `ProfileStoreTests`; `scripts/acceptance/f8-profiles.sh` over the daemon socket |
| A2 | A malformed name or a path that escapes the store is refused before any byte is written | `ProfileStoreTests`; the lane asserts `.staging` is empty after each refusal |
| A3 | A harness skill root is classified entry by entry, and a dangling link is reported as dangling rather than as absent | `SkillRootInventoryTests` over fixture roots this item creates |
| A4 | A harness with no skill root reads `absent`, which is not the same as a root with no entries | `SkillRootInventoryTests`; both states in the same test |
| A5 | Every projected step carries its reach, and a step that would write a harness MCP config is `refused` with R7's reason | `ProfileProjectionTests` |
| A6 | Nothing in `app/Sources` writes a harness skill root | `scripts/lint/no-harness-skill-writes.sh`, with its own selftest of planted appliers |
| A7 | The daemon — not just the handler — answers the `/profiles` family | `scripts/acceptance/f8-profiles.sh`, enrolled in `acceptance-lanes.sh` |
| A8 | No method outside the token gate's set is served by this family | `ControlProfileRoutesTests` C6, parameterised over PUT, HEAD, OPTIONS and TRACE, with a tokened-POST control; and the lane's 405 on the wire |

## 5 · Deferred children

| ID | Title | Why not here |
|---|---|---|
| **F8-C1** | Apply a projection into a harness skill root, behind a human | §3. It needs an undo, a confirmation surface and the standing *prepare it, don't run it* answer R30 took; it is what the brief puts out of scope once §1.3 is read |
| **F8-C2** | The profile manager surface in the Mac app | A board is converted under M23 against `design/mcp-router-console.html`, not written by eye; no mock exists for it |
| **F8-C3** | `mcp-router profiles` CLI verb | The routes are the surface F8 proves; a verb needs acceptance coverage of its own (`HarnessesVerb` is the precedent) and buys no capability |
| **F8-C4** | Project-scoped skill roots | Read at global scope only, the same blind spot R7-C4 records |

## 6 · Assumptions

- **Assuming a profile selects over the router's store rather than over the union of the
  harnesses.** The losing option — a profile as "whatever Cursor has" — is better at describing
  this machine today, where the router holds nothing and Cursor holds 87. It is worse at every
  moment after, because it makes the largest accidental set the specification.
- **Assuming a second Cursor root is modelled rather than merged.** `~/.cursor/skills` and
  `~/.cursor/skills-cursor` have different shapes; merging them would report 109 entries and 27
  dangling links against a denominator that describes neither directory.
- **Assuming `codexCLI` and `chatGPTCLI` share one root**, which is what `ClientConfigs` already
  does for their config file. A reading reported twice is one reading, and the projection says so
  rather than counting it twice.
