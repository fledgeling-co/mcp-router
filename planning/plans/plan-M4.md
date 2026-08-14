# plan-M4.md — Skills and marketplaces

- **Spec:** `planning/specs/spec-M4.md`
- **Design:** `design/mocks/html/m4-skills-board.html`, `DESIGN.md`
- **Branch / worktree:** `ai/m4` in `.worktrees/M4`
- **Size tier:** Large. This item carries a router surface as well as a board, for the reason the
  spec states: the router observes nothing about skills, and the app may not open a second channel.

---

## Phase order, and the cut order if room runs out

Phases are ordered so the **item becomes real as early as possible** — P4 is where `.skills` enters
`BoardRegistry.installed` and the user stops seeing a placeholder. Each phase is independently
committable.

| Phase | Deliverable | Cut order |
|---|---|---|
| P1 | Wire contract + TypeScript read endpoints | never — nothing works without it |
| P2 | Kit models + client methods + fixture | never |
| P3 | `SkillPresentation` — the headless decisions | never |
| P4 | The board, and `.skills` registered | **never — this is the item** |
| P5 | Inspector, sheets, menu, keyboard | never — the states are the design |
| P6 | Write operations | cut second: degrade to disabled-with-reason, which is a designed state |
| P7 | Swift `RouterCore` parity implementation | **cut first** — it serves nothing until R2R lands a daemon |
| P8 | Gates, evidence, commit | never |

If P6 or P7 is cut it is **reported as cut**, with the disabled reasons actually rendered, not
silently omitted.

---

## P1 · The wire contract and the TypeScript endpoints

### The contract

`GET /skills` →

```
{ "skills": [ {
    "name": "trawl",
    "description": "…" | null,
    "source": { "kind": "marketplace", "marketplace": "fledgeling-plugins",
                "version": "2.2.0", "installedAt": "…", "lastUpdated": "…",
                "commit": "423563c…" }
             | { "kind": "local" },
    "presence": { "claudeCode": "present", "codex": "present",
                  "cursor": "absent", "opencode": "unreadable" },
    "held": { "version": "2.3.0", "addedCapabilities": ["runs scripts/collect.sh"] } | null,
    "provenance": { "installedOwner": "acme-tools", "currentOwner": "unknown-user" } | null
  } ],
  "clients": [ { "id": "claudeCode", "supportsSkills": true,
                 "root": "…", "status": "read" | "absent" | "unreadable",
                 "reason": "permission denied" | null } ] }
```

`GET /marketplaces` →

```
{ "marketplaces": [ { "name": "fledgeling-plugins",
                      "source": { "kind": "github", "repo": "fledgeling-co/fledgeling-plugins" }
                             | { "kind": "directory", "path": "…" },
                      "autoUpdate": false, "installedSkillCount": 6 } ] }
```

**Three shapes that carry the spec's honesty rules structurally**, rather than by convention:

- `source` is a tagged union, so a local skill **has no version field to fill in**. It is not
  possible to render a version for a local skill by accident; there is nothing there.
- `presence` is a per-client enum with `unreadable` distinct from `absent` (A7). A boolean would
  have collapsed "not installed" and "we could not look", which is the Partial state's whole point.
- `clients` reports every client including the two with `supportsSkills: false`, so the inspector
  can name them rather than the app hardcoding a list the router disagrees with (A13).

There is **no** `runs`, `lastRun` or `eval` field anywhere on the wire. The absence is structural:
a field that does not exist cannot be rendered by a later careless edit (A10).

### Work

1. `src/skills.ts` — new. Reads the four client roots, `known_marketplaces.json`,
   `installed_plugins.json`, and the cache directory. Uses the router's existing JSON reader.
2. `src/control.ts` — add `/skills` and `/marketplaces` to `isControlPath`, and two GET handlers.
   Nothing removed, nothing else edited.
3. Tests against a **temporary fixture filesystem**, not the real home directory.

### The trap to avoid, named

`SWIFT_PRACTICES.md` §2 records this repo's own bug: a flat `servers.json` loaded **zero servers
with no error at all**, because the reader looked for a key that was not there and found an empty
collection. Skills discovery has the identical shape and the identical failure mode — a missing
`plugins` key would report "you have no skills". **Every read either finds its key or fails
loudly**, and a test asserts a malformed file raises rather than returning `[]` (A8).

---

## P2 · Kit models and the client

- `MCPRouterKit/Control/SkillModels.swift` — `Skill`, `SkillSource`, `ClientPresence`,
  `HeldVersion`, `Provenance`, `Marketplace`, `MarketplaceSource`, `SkillClient`,
  `SkillsResponse`, `MarketplacesResponse`.
  - Every closed set on the wire is a **Swift enum that fails decoding on an unknown value** — no
    `String` plus a guessing `default` (`SWIFT_PRACTICES.md` §2).
  - `SkillSource` and `MarketplaceSource` are enums with associated values, mirroring the tagged
    unions, so the "local skills have no version" guarantee survives into Swift.
- `ControlAPIClient` gains `skills()`, `marketplaces()` and — in P6 — the four write operations.
  Added to the protocol, so a client that does not implement them does not compile.
- `LiveControlAPIClient` — two GETs, same error mapping as every other call.
- `FixtureControlAPIClient` — new scenarios so the acceptance lane can reach each state:
  `skillsPopulated`, `skillsEmpty`, `skillsPartial` (one client unreadable), `skillsHeld`,
  `skillsProvenance`, `skillsOverflow`. Debug only; Release is always `.live`.

**A18 check:** none of the new write bodies carries `command`, `args` or `env`. Asserted against
the **encoded JSON**, not the Swift type — reflection would miss a `CodingKeys` mapping.

---

## P3 · `SkillPresentation` — where every decision lives

`MCPRouterKit/Skills/SkillPresentation.swift`, no UI framework, testable without a host. It owns:

| Decision | Rule |
|---|---|
| Header subtitle | counts of returned records; held clause omitted at zero; **empty string while loading** |
| Filter membership | `all` / `held` / `local` / `needsAttention` (held ∪ provenance-changed) |
| Filter counts | omitted at zero rather than rendered `0` |
| Version display | `2.2.0`, or `2.2.0 → 2.3.0` held, or `unversioned` — and **which face each uses**, because `unversioned` is body font and the others are monospace (A11) |
| Slot state | on / off / unread, per client, from `presence` |
| Which clients get a slot | those with `supportsSkills` — from the wire, not hardcoded |
| Inspector's client sentence | the in / not-in / no-mechanism three-part phrasing |
| Every disabled reason | the six in the design doc §9 |
| Empty-in-filter copy | names the filter, offers `Show all skills` |

Following M3's split, and for its stated reason: its two prototype failures were wrong answers from
a branch, not styling defects, and a branch only a running app can exercise is one that ships wrong.

---

## P4 · The board — the item

- `MCPRouterUI/Boards/SkillsBoardModel.swift` — `@Observable`, `@MainActor`. Its own `LoadState`
  (`loading` / `loaded` / `stale(rows, error)` / `failed(error)`), because F4's `ServerStateTracker`
  is servers-specific and skills have no tracker.
- `SkillsBoard.swift` — the switch over `LoadState`, reusing M3's `SkeletonRows`, `MessageState`,
  `ConnectionFailurePane`, `StaleReadingBanner`, `Banner`, `DisabledAction` **unmodified**. That
  reuse is what keeps one wording per state across the app.
- `SkillsBoardRow.swift` — tile, name, source line, slots, version, trailing action.
- `SkillsBoardMetrics.swift` — column widths derived from `MetricToken.tableRows` in M3's style;
  nothing chosen by eye (A24).
- `SkillsBoardStates.swift` — the exhaustive `SurfaceState` → treatment mapping, so a tenth state
  fails to compile (A19).
- **`ScaffoldPane.swift` — `.skills` added to `BoardRegistry.installed`.** One line. Everything
  above is inert without it.

### Expected merge conflict, flagged for the orchestrator

M2 is in flight adding `.activity` to the same one-line set. Both edits are additive to
`BoardRegistry.installed`; the resolution is the union `[.servers, .activity, .skills]`. The
complement test in `ShellIntegrationTests` will catch a botched resolution in either direction.

---

## P5 · Inspector, sheets, menu, keyboard

- `SkillInspector.swift` — the eight sections in spec order.
- `SkillSheets.swift` — held-version review (the two variants: wants-more, and empty-delta already
  promoted), marketplaces list, add marketplace.
- Menu items into M1's existing menus with its disabled-reason mechanism; `⌘F`, `Return`, `Esc`,
  arrows wired. `Space` deliberately unbound here.

---

## P6 · Writes

`POST /skills/{name}/promote`, `POST /marketplaces`, `DELETE /marketplaces/{name}`,
`PATCH /marketplaces/{name}` (`autoUpdate` only).

Each mutates `~/.claude/plugins/*.json`, so each writes through the same discipline the router
already uses for server config: read, modify in memory, write atomically, never a partial file.
The PATCH body accepts **exactly one key**; anything else is a 400 rather than a silent ignore.

Every write returns the **updated record**, and the UI applies that returned record rather than
guessing what its own write did (A15).

---

## P7 · Swift `RouterCore` parity

`RouterCore/Skills/` mirroring P1 against the same fixture filesystem, plus vectors asserting the
two implementations emit byte-identical JSON for identical input (A9). Cut first if room runs out —
it serves nothing until R2R lands a daemon — and reported as cut rather than quietly skipped.

---

## P8 · Gates and evidence

`make all` green, reported not asserted. `planning/evidence/M4-acceptance.md`, one row per screen:
screen · how it was verified (the actual command or AX path) · commit SHA · result.

**UI verification is invisible and covers the Skills pane only.** `open -g -a`, never `activate`,
never `set frontmatter true`; `proctor` process-directed kinds; `proctor_capture` for a window-scoped
shot of a window that is not in front. No other pane is exercised — M3's servers rows and M1's shell
have their own evidence files and nothing here touches the files behind them.

### Red-green proving

Every test whose job is to catch drift is deliberately broken, watched to go red, and restored —
recorded in the evidence file. Specifically: the no-runs-column guard, the local-skill-has-no-version
guard, the unreadable-vs-absent distinction, and the malformed-JSON-fails-loudly guard. A test that
has never failed is not known to work.
