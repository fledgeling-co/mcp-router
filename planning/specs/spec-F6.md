# F6: the update check, and the catalogue it cannot see past

**Category:** feature · **Brief:** `planning/features-to-triage/F-marketplace-auto-update-checker.md`
**Depends on:** R28 (the router owns skills, plugins and marketplaces) — merged `784dde9`;
R30 (ingest what Claude acquires) — merged, `<plugin>@<marketplace>` is the plugin's name.
**Related:** R31 (invalidate the caches a change outruns) — merged `567b5a1`, and the item whose
finding this one repeats in a second place. M19 (the capability-document renderer), M4 (the Skills
board), M20 (the menu), I3 (the phone's queue) — the four surfaces this item does **not** build,
each with its reason in §5.

The brief asks for a checker that "queries marketplace registries for version deltas on installed
tools". §1 is a read-only measurement of what that query can actually answer on the machine this
product runs on. **It answers "an update is available" zero times out of 127, and answers it
backwards once.** So a version delta is not the mechanism; it is one of eight outcomes, and the
other seven are the item.

---

## 1 · What was measured, and by what instrument

Read-only, on the author's machine, **2026-08-29**, by
`planning/evidence/F6/measure-update-surface.py` walking `~/.claude`. It prints shape and counts
only; no value from any file under that tree is reproduced here or in the script's output.

```
python3 planning/evidence/F6/measure-update-surface.py
```

| reading | figure |
|---|---|
| `skills/` directories | 23, of which **22** carry `SKILL.md` |
| …whose frontmatter carries `version:` | **12** — so **10 of the 22 declare no version at all** |
| `plugins/installed_plugins.json` records | **127**, every one carrying a `version` |
| …whose version parses as semver | 124 |
| …whose version is a **git short SHA** | **3** (`playwright`, `frontend-design`, `skill-creator`, all `@claude-plugins-official`) |
| `plugins/marketplaces/` directories | **10**, all 10 carrying a readable `.claude-plugin/marketplace.json` |
| …that are git checkouts | 8 |
| …that are **not** git checkouts | **2** (`claude-plugins-official` and its `.bak`) |
| plugins offered across those catalogues | **763** |
| …declaring a `version` | 206 |
| …**declaring none** | **557** |

And the comparison the brief asks for, run over all 127 installed records against the catalogue of
the marketplace each one names:

| outcome | count |
|---|---|
| **an update is available** | **0** |
| the versions are equal | 105 |
| the catalogue offers the plugin and **declares no version** | 10 |
| the catalogue **no longer offers** the plugin at all | 10 |
| the plugin's **marketplace directory is not there** | 1 |
| **the catalogue is OLDER than what is installed** | **1** (`security-guidance@claude-code-plugins`, held 2.0.0, offered 1.0.0) |

Four of those rows decide the design.

### 1.1 · The mechanism the brief names fires zero times

`installed != offered` is the obvious implementation and on this machine it produces exactly one
row — and that row is pointed the wrong way. Held 2.0.0, offered 1.0.0: the local copy of the
catalogue is a month behind the install, and a checker that reads a difference as an update would
offer the user a **downgrade**, described as an update, with no way to tell from the reply which
it was.

This is R31's finding in a second place. There the identity key could not see 15 of 21 upstreams
move; here the version string cannot see 22 of 127 plugins at all, and the one difference it does
see means the opposite of what it looks like. So the verdict type below has a **direction**, and
`catalogueBehind` is reported as a fact about the catalogue rather than as an update. There is no
route by which it can become one: `hasUpdate` is a computed property with exactly one true case.

### 1.2 · 557 of 763 offers declare no version, so "no update" is usually "no answer"

A catalogue that does not say what it offers cannot be compared with anything. Reporting those as
*up to date* is the failure this item exists to avoid, and it is invisible in a boolean: a report
of "0 updates" over 127 plugins is produced identically by a healthy machine and by a checker that
read nothing. So `noVersionDeclared` and `notOffered` are **their own verdicts**, present in the
reply, counted in the summary, and never folded into `current`.

`DESIGN.md` §6 is the standing rule and this is its shape here: a count of zero that means *I
compared and found none* and a count of zero that means *I could not compare* are different
answers, and only one of them is a measurement.

### 1.3 · A version is not always orderable

Three installed plugins carry `ed404106fcd8` where a version goes. Two git short SHAs have no
order, so `differs` is knowable and `behind` is not. `unorderable` carries both strings and says
so, rather than falling back to a string comparison that would order them by hexadecimal accident.

**The alternative this beat:** normalise a non-semver version to `0.0.0` so everything compares.
That makes all three plugins permanently *behind* every catalogue entry, which is a fabricated
update on a machine that has none — the failure in §1.1 with a different cause.

### 1.4 · The evidence has an age, and the report has to carry it

The catalogue is a file on disk. Nothing in this item refreshes it: 2 of the 10 marketplaces are
not git checkouts at all, so even a refresh has a class it cannot serve, and reaching the network
is the act the brief's own assumption puts behind user approval.

So every verdict travels with the catalogue it was taken against — the path, the newest
modification time in the tree, and whether it is refreshable — and the report marks a catalogue
`stale` when that time is older than the caller's `staleAfterMs`. **A `current` verdict against a
stale catalogue is still `current`, and it is printed beside an age.** The router does not get to
say "up to date" without saying what it read and when that last moved.

---

## 2 · What is built

Five types in `RouterCore`, one route, and two additions to R28's reader.

| file | what it is |
|---|---|
| `Extensions/MarketplaceCatalogue.swift` | a marketplace descriptor parsed into the offers it makes: name, version, and how many it declared no version for |
| `Extensions/ExtensionFreshness.swift` | the verdict type, and the comparison of one installed entry against one catalogue |
| `Extensions/ExtensionFreshnessReport.swift` | every entry of every kind, the per-catalogue readings behind them, and the summary counts |
| `Extensions/SemanticVersion.swift` | ordering two version strings, or declining to |
| `Control/ControlUpdates.swift` + `ControlUpdatesJSON.swift` | `GET /extensions/updates` |

And in R28's existing files:

* `ExtensionDescriptor.Reading` gains `version: String?` — the `version:` frontmatter line for a
  skill, the `version` member for a plugin and a marketplace. One field, read by the rule that
  already reads `name` and `description`.
* `ExtensionRecord` gains `version: String?`, so `GET /extensions/:kind` answers it too.
* `ExtensionStoring` gains **one** method, `descriptorText(_:name:)`, returning the entry's
  descriptor bytes as text or `nil`.

**The alternative `descriptorText` beat:** put an `offers` array on `ExtensionRecord`. That was
rejected on a measured cost — the largest catalogue on this machine declares **291** plugins and
the ten together declare 763, so every `GET /extensions/marketplaces` would carry three orders of
magnitude more body to serve a question that route is not asked. The narrow method reads one
named descriptor and cannot address any other path, so it adds no traversal surface: the name goes
through `ExtensionNaming.isWellFormedName` exactly as `read` does.

### 2.1 · The verdict vocabulary

```swift
public enum FreshnessVerdict: Sendable, Hashable {
    case updateAvailable(installed: String, available: String)
    case current(String)
    case catalogueBehind(installed: String, available: String)
    case unorderable(installed: String, available: String)
    case installedDeclaresNoVersion
    case catalogueDeclaresNoVersion(installed: String?)
    case notOffered
    case noCatalogue(String)
}
```

`hasUpdate` is `true` for `updateAvailable` and for nothing else. `isComparison` is `true` for the
first four and `false` for the last four, which is what makes the summary able to report *four of
127 could not be compared* rather than *four are up to date*.

### 2.2 · `GET /extensions/updates`

A `GET`, and there is no sibling verb. The brief's assumption — *update checks are read-only until
the user approves the update* — is held by there being nothing to call, not by a flag anyone can
pass. Installing is R30's and R29's territory and is not reachable from this route.

Query parameters: `kind` (one of the three; absent means all three), `staleAfterMs` (default
`86_400_000`, one day — the interval the brief's own example names), and `name` to ask about one
entry. It **diverges from `src/control.ts`**, which answers the path 404, declared in
`planning/parity/surface.tsv` as `div-f6-updates` in the same way the `div-r28-*` and `div-r31-*`
rows are.

The body carries, per entry: `kind`, `name`, the installed `version`, the `available` version, the
verdict `state` as a slug, a sentence, and the `catalogue` block — `name`, `path`,
`newestModifiedMs`, `ageMs`, `stale`, `refreshable`. Plus a `summary` holding
`total`, `updatesAvailable`, `compared`, `uncomparable`, and `staleCatalogues`.

### 2.3 · Who owns the clock

**The router holds no timer.** The check reaches no network and spawns no child; it reads ten JSON
files and 127 descriptors, so the cost that would justify a background schedule is not there. What
the caller needs is not a cadence inside the daemon but an answer that says how old its evidence
is, which is `staleAfterMs` and the per-catalogue `ageMs`.

**The alternative this beat:** a `launchd` timer in the daemon writing a cached report. It costs a
third background writer (R2-W added the second) and a cache that can disagree with the disk, to
save a walk that takes no measurable time. The cadence lives with whoever polls — the Mac app's
timer, or an existing agent — and both readings produce identical router code, which is why this
was decided here rather than asked.

---

## 3 · What each verdict is proved by

Rule 11 of this fleet: an assertion that cannot fail is not evidence. **On the real machine,
`updateAvailable` fires zero times** (§1), so every arm below is driven against a fixture store the
suite builds, and each was watched to fail before it was trusted. The red-green record is
`planning/evidence/F6/red-green.txt`.

| verdict | how the fixture reaches it |
|---|---|
| `updateAvailable` | plugin `1.0.0`, catalogue offers `2.0.0` |
| `current` | plugin `1.0.0`, catalogue offers `1.0.0` |
| `catalogueBehind` | plugin `2.0.0`, catalogue offers `1.0.0` — the state measured on this machine |
| `unorderable` | plugin `ed404106fcd8`, catalogue offers `aa11bb22cc33` |
| `installedDeclaresNoVersion` | a skill whose frontmatter carries `name` and no `version` — 10 of 22 on this machine |
| `catalogueDeclaresNoVersion` | catalogue offers the plugin with no `version` member — 557 of 763 |
| `notOffered` | catalogue readable, plugin absent from its `plugins` array |
| `noCatalogue` | the plugin names a marketplace the store does not hold |

---

## 4 · The requirement table

| # | requirement (the brief's words) | oracle |
|---|---|---|
| A1 | *queries marketplace registries for version deltas on installed tools* | `ExtensionFreshnessTests` — all eight verdicts, each watched red; `GET /extensions/updates` over the daemon's socket in `scripts/acceptance/f6-updates.sh` |
| A2 | *displays pending updates* | the `updateAvailable` rows and `summary.updatesAvailable`; the lane asserts the count moves when the fixture catalogue is edited |
| A3 | *read-only until the user approves* | structural — the route answers `GET` and the family has no other verb; the lane asserts `POST`, `PUT` and `DELETE` on the path are 405, and that the store's byte count is unchanged across the whole run |
| A4 | *local caching to avoid rate limits* | **reinterpreted and declared.** Nothing here reaches the network, so there is no limit to hit. What replaces it is the per-catalogue age and `staleAfterMs` — §1.4 |
| A5 | *renders GFM release notes inside `CapabilityDocumentSheet`* | **not built** — §5 |
| A6 | *surfaces indicators on the Skills and Servers boards and the menu bar* | **not built** — §5 |
| A7 | *iPhone receives notifications and queues updates* | **not built** — §5 |

---

## 5 · What is not built, and why

Three of the brief's seven acceptance lines are surfaces, and each already has an owner in this
backlog. Building them here would put a second author in a file another item is specified against.

| line | owner | why not here |
|---|---|---|
| GFM changelog rendering in the document sheet | **M19** | M19 is the renderer, and it carries the two constraints that shape it — a README is untrusted input from a marketplace, and `AttributedString(markdown:)` covers inline runs but not tables or fenced code blocks. A second renderer would be the thing M19 exists to prevent |
| update indicators on the Skills and Servers boards, and the menu bar | **M4**, **M3**, **M20** | those boards are merged and specified; an indicator is a change to their state matrices, which is a `design` stage this item has not run |
| the phone queues an update for Mac review | **I3** | the phone **queues, never installs** is a standing constraint of this repository, and I3 owns the queue |

They are not dropped: each is a row this item's report makes possible, and the report is the
surface all three read. **A4 is a genuine reinterpretation rather than a deferral** and is written
as one — the brief assumed a remote query, this item does not make one, and the assumption's
purpose (do not present a stale answer as a fresh one) is served by carrying the age instead.

## 6 · Assumptions

1. The store's marketplace entries are the catalogue. A marketplace Claude knows about but the
   router does not hold is `noCatalogue`, which is the honest answer and also the one that makes
   R30's ingestion visibly worth running.
2. A skill has no catalogue on this machine and therefore no comparison — it reports its declared
   version, or `installedDeclaresNoVersion`, and `noCatalogue` with that reason. It is listed
   rather than omitted, for the reason `notOffered` is.
3. `version` in a skill's frontmatter is the flat `key: value` shape R28 measured over 23 skills.
   A nested version is ignored rather than refused, matching how R28 treats an unknown key.
