# R30: ingest what Claude acquires, so the router stays the only source

**Category:** router · **Brief:** `planning/features-to-triage/R30-ingest-what-claude-acquires.md`
**Depends on:** R28 (the router owns skills, plugins and marketplaces) — merged `784dde9`.
**Related:** R29 (push a reload), R31 (invalidate the caches a change outruns).

R28 gave the router somewhere to hold an extension. Nothing keeps it the *only* place: a plugin
installed Claude's own way lands under `~/.claude/plugins/` and from that moment the two disagree.
This item moves what Claude acquired into the router and withdraws Claude's copy — copy, verify,
then remove, never remove-then-copy — and makes the removal reversible from the router's own disk.

**It is built and it is not run.** The owner's standing answer for work of this shape (the Warden
migration, W2) was *prepare it, don't run it*, and that is the boundary here: every claim below was
measured against a fixture tree this repository creates, the live run is a command the owner types,
and the default invocation prints a plan and touches nothing.

---

## 1 · What was measured, and by what instrument

Read-only, on the author's machine, **2026-08-28**, with `python3` walking `~/.claude`. No value
from any file below is reproduced in this repository; what was taken is shape and counts.

| reading | figure |
|---|---|
| `skills/` directories | 24, of which **22** carry `SKILL.md` |
| `plugins/marketplaces/` directories | 7, of which **7** carry `.claude-plugin/marketplace.json` |
| `plugins/cache/` directories shaped like `<marketplace>/<plugin>/<version>` | **335** |
| …of those, carrying `.claude-plugin/plugin.json` | 251 (76 of them also carry a bare `plugin.json`) |
| …carrying no `plugin.json` anywhere | **84** |
| top-level `plugins/cache/` entries that are not marketplaces | **5**, all `temp_git_*` clones |
| `plugins/installed_plugins.json` records | **127**, every one holding exactly one element |
| …whose `installPath` resolves and carries a descriptor | 124 |
| …whose `installPath` is not on disk | 1 |
| …which resolve but carry no descriptor | 2 |
| `settings.json` top-level members | **22** |
| `enabledPlugins` keys | 120, all of them a subset of the 127 installed |
| plugins installed but not in `enabledPlugins` | 7 |
| `extraKnownMarketplaces` entries | 5 (the two built-in marketplaces have no key) |
| **plugin names present in two marketplaces at once** | **13** |

Three of those rows decide the design, and each one refutes an obvious approach.

### 1.1 · The plugin cache cannot be walked

335 version-shaped directories against 127 installed plugins. The surplus is not noise that a
filter removes: 84 of them carry no descriptor, and the five `temp_git_*` clones walk to the same
depth a real `<marketplace>/<plugin>/<version>` does, so `.git/hooks` is indistinguishable from a
version directory by shape alone.

The marker that looks as though it selects the installed version does not. `.in_use` is present on
**241 of the 335**, and of the **65 plugins that have more than one version, 52 carry `.in_use` on
more than one of them**. Exactly one has it on a single version.

`installed_plugins.json` names the installed version outright — one `installPath` and one `version`
per `<plugin>@<marketplace>` key. So the plugin lane is a **register read**, and a cache directory
no record names is never a candidate rather than being reported as one of 84 failures. The two
directory-walk lanes (skills, marketplaces) are safe because their layouts are flat and their
descriptors are required.

### 1.2 · A flat store keyed on the bare name loses work

13 plugin names exist in two marketplaces at once on this one machine — `code-review`,
`design-craft`, `ship-feature`, `ux-craft` and nine others. R28's store is flat per kind, so a
store keyed on `code-review` holds one of that pair and drops the other.

The identity Claude itself uses is `<plugin>@<marketplace>`: it is the literal key of
`enabledPlugins` and of `installed_plugins.json`. So that is the name the router stores a plugin
under, and `ExtensionNaming.isWellFormedSegment` gained `@` to allow it. It is a path character
like any other, it is a separator in no path this store builds, and `.` and `..` are still refused,
so the containment argument R28 wrote is unchanged.

**The alternative this beat:** treat a collision as a conflict, report it, and leave both in
Claude. That satisfies "reported and left alone" and fails the item — 13 plugins would be
permanently un-ingestible, and "the router is the only source except for these" is the state R30
exists to end.

### 1.3 · `settings.json` is 22 members and two of them are R30's

`env`, `permissions`, `hooks`, `model`, `statusLine` and sixteen others carry configuration for
every project on this machine. `ClaudeSettingsEdit` never builds a new document: it parses the
existing one into `JSONMember`s, deletes named keys out of `enabledPlugins` and
`extraKnownMarketplaces`, and writes the same array back, so every other member keeps its value
*and its position*.

---

## 2 · The order, and what each step buys

1. **scan** — read-only. Produces a candidate for every entry it can identify and an
   `IngestBlocked` for every path it looked at and would not touch. The two lists are a partition
   of what was examined, so nothing falls into a third pile.
2. **copy** — `DiskExtensionStore.adopt`, which stages into `<store>/.staging` and renames into
   place, so a failure leaves no half-entry under a name a caller asked for. `add` could not be
   reused: its `ExtensionFile.text` is a `String`, and a plugin tree holds bytes that are not UTF-8.
3. **verify** — three checks, all of which must hold:
   - the source's stamp is **re-measured** and must equal the one the scan took;
   - the router's copy must have the **same digest** as the source;
   - the store's own reader must return the entry with `problem == nil`.
4. **remove** — Claude's directory is **moved** into `<store>/.removed/claude/<kind>/<name>/<ms>`.
   Nothing is deleted, here or anywhere in this item.
5. **settings** — the keys of the entries that actually left are withdrawn, once, after every
   removal, and the top-level member count is asserted equal before and after.
6. **manifest** — `<store>/.ingest/<runId>.json`, written **before** the settings edit as well as
   after it, so a crash between the two still leaves a document naming every quarantined directory.

A failure at any step leaves Claude's copy untouched and takes the router's copy back out. The two
states a run can end in are *both copies, plan not applied* and *one copy, in the router*. There is
no state in which neither exists.

### 2.1 · "Never against a directory a person is editing"

Two mechanisms, because one is only a filter. A candidate whose newest `mtime` is inside the settle
window (`--settle-seconds`, default 60) is refused before anything is copied; and the source is
re-stamped **after** the copy, so a tree edited *during* it is caught as well. Nothing on a
POSIX filesystem can prove an editor does not hold the file open, and the spec says so rather than
implying the window is a guarantee.

---

## 3 · The command

```
mcp-router ingest --claude-home <path>            # print the plan; touch nothing
mcp-router ingest --live                          # the same, against ~/.claude
mcp-router ingest --live --apply                  # carry it out
mcp-router ingest --live --apply --link-back      # leave a link at Claude's path instead
mcp-router ingest --undo <manifest path>          # put a run back
```

**There is no default tree.** Either `--claude-home` names one or `--live` says the real one out
loud, and an invocation with neither exits 1 explaining why: a default would be the real one.

`--apply` is likewise not the default, because the plan is what a person needs *before* the move.

### 3.1 · `--link-back`, and what it is not proven to do

With `--link-back` the entry's original path becomes a symlink to the router's copy and the
`settings.json` key is **kept**, because Claude can still resolve it. One set of bytes, in the
router, reachable from Claude's path.

**Whether Claude follows that link for a skill or a plugin is unmeasured.** Establishing it means
running against the live tree, which this item's boundary forbids, so the mode ships off by default
and this sentence is the honest status rather than a claim. With it off — the default — the router
holds the only copy and Claude's registration is withdrawn, which is a state the suite measures end
to end.

---

## 4 · The boundary, stated as a boundary

- Nothing in this item reads or writes the real `~/.claude` during development, testing or lint.
  `scripts/acceptance/r30-ingest.sh` records the real `settings.json`'s size and mtime before its
  run and compares them after, so a lane that ever reached the wrong file reddens rather than
  passing quietly.
- **Serving an ingested extension back to a harness is not R30.** The router holds the bytes and
  can restore them; propagating them to a live session is R29's, and invalidating what a change
  outruns is R31's. R30's acceptance is that the router's copy is the only one, is complete, and is
  restorable without re-downloading.

---

## 5 · Deferred

- `GET /extensions/ingest` — the plan over the control API, for the Mac app's Extensions board.
  The engine is a pure function of a `ClaudeTree` and a store, so the route is a wrapper; it is out
  of scope here because R30's deliverable is the owner-invoked command.
- A watcher that ingests continuously. The brief's own assumption, kept: a watcher that moves files
  under a running session is a larger risk than a command run at a known moment.
