# F6 — acceptance evidence

**Item:** F6, the update check · **Branch:** `ai/n2` · **Worktree:** `.worktrees/N2`
**Spec:** `planning/specs/spec-F6.md` · **Plan:** `planning/plans/plan-F6.md`
**Brief:** `planning/features-to-triage/F-marketplace-auto-update-checker.md`

Append-only. Each row names what was verified, the actual command, and the result.

---

## 0 · The one measurement everything else follows from

The brief asks for a checker that "queries marketplace registries for version deltas on installed
tools". Run over the author's real machine, that mechanism reports **no update, 127 times**.

```
python3 planning/evidence/F6/measure-update-surface.py
```

| reading | figure |
|---|---|
| installed plugin records compared against their own marketplace | **127** |
| …reported **update available** | **0** |
| …equal | 105 |
| …offered with **no version declared** | 10 |
| …**no longer offered** by that marketplace | 10 |
| …whose marketplace directory is **not there** | 1 |
| …where the **catalogue is OLDER than the install** | **1** |
| offers across the ten catalogues | 763, of which **557 declare no version** |
| readable skills declaring a `version:` | 12 of 22 |
| installed plugins whose "version" is a **git short SHA** | 3 |
| marketplaces that are **not git checkouts** | 2 of 10 |

The output is shape and counts. No value from any file under `~/.claude` is reproduced here or in
the script's output.

**This is R31's finding in a second place.** There an identity key could not see 15 of 21 upstreams
move; here a version string cannot see 22 of 127 plugins at all, and the one difference it does see
means the opposite of what it looks like. So the delivery is eight verdicts with a direction, not a
boolean — and the `catalogue-behind` state exists because a checker without it would have offered a
**downgrade, described as an update**, with nothing in the reply able to say which it was.

---

## 1 · The requirement table

| # | requirement (the brief's words) | oracle | verdict |
|---|---|---|---|
| A1 | *queries marketplace registries for version deltas on installed tools* | `ExtensionFreshnessTests` F1–F12 · `ExtensionFreshnessScanTests` G1 reaches all eight verdicts through a real store · lane rows 6–13 drive all eight over the socket | **met** |
| A2 | *displays pending updates* | `summary.updatesAvailable` beside `compared`/`uncomparable`; lane asserts 1 update, 4 compared, 7 uncomparable, 11 total, and that editing the fixture catalogue moves them | **met** |
| A3 | *read-only until the user approves* | structural — a `GET` with no sibling verb; lane asserts POST, PUT, PATCH and DELETE are 405 **and** that the store holds the same 11 files after all four | **met** |
| A4 | *local caching to avoid rate limits* | **reinterpreted, and declared.** Nothing here reaches the network, so there is no limit to hit. What replaces it is the per-catalogue age, `staleAfterMs`, and `refreshable` | **met as reinterpreted** |
| A5 | *renders GFM release notes inside `CapabilityDocumentSheet`* | — | **not built · M19** |
| A6 | *indicators on the Skills and Servers boards and the menu bar* | — | **not built · M4, M3, M20** |
| A7 | *the iPhone receives notifications and queues updates* | — | **not built · I3** |

`spec-F6.md` §5 carries the reason for each of the three, and each names the item that owns the
file it would have to edit. A4's reinterpretation is written as one rather than as a deferral: the
brief assumed a remote query, this item makes none, and the assumption's purpose — do not present a
stale answer as a fresh one — is served by carrying the age instead.

---

## 2 · Gates, with their actual exit codes

| gate | command | result |
|---|---|---|
| F6 unit suites | `swift test --filter 'SemanticVersionTests\|MarketplaceCatalogueTests\|ExtensionFreshnessTests\|ExtensionFreshnessScanTests\|ControlUpdateRoutesTests'` | **42 tests in 5 suites passed** |
| F6 socket lane | `bash scripts/acceptance/f6-updates.sh` | **33 ok, 0 failed · exit 0** — transcript `planning/evidence/F6/lane-f6-updates.txt` |
| arming | `python3 planning/evidence/F6/red-green.py` | **10 of 10 mutations RED · exit 0** — record `planning/evidence/F6/red-green.txt` |
| reader accounting | `python3 planning/reader-accounting.py` | exit 0 · 20 readers record, 45 declare, 2 recorded gaps — neither new file is among them |
| sweep controls | `python3 planning/sweep-control-gate.py` | `planning/evidence/F6/red-green.py` dispositioned `waived` with its reason; the two findings left are `carrier-parity-gate.py` (120s under load) and `G11-corpus-determinism.py`, neither of which is this branch's |

Whole-tree `make lint` and `make test` are recorded in §5.

---

## 3 · Every assertion was watched to fail

Rule: an assertion that cannot fail is not evidence. **On the real machine `update-available` fires
zero times**, so there is no reading of a real tree that exercises the state this feature exists to
produce, and the fixtures are the only place it can be driven. The driver mutates the
**implementation** — never a test — runs the suite, and records which named tests went red. It
refuses to start unless the unmutated tree is green, and `PARTIAL`, `SURVIVED` and
`NOT APPLICABLE` all exit non-zero.

| # | mutation | expected red | went red |
|---|---|---|---|
| M1 | an unorderable pair compares `.orderedAscending` | S3, F4 | **both** |
| M2 | the direction is inverted in `ExtensionFreshness` | F1, F3, G1 | **all three** |
| M3 | `hasUpdate` becomes true for `catalogueBehind` | F3, F12 | **both** |
| M4 | the equality check runs before the version guards | F9 | **yes** |
| M5 | `routeExtensions` stops declining `/updates` | U4 | **yes** |
| M6 | a negative age is reported as a number | G10, U7 | **both** |
| M7 | `isComparison` is true for every verdict | F12, G2 | **both** |
| M8 | an empty-string version is kept as a version | C1 | **yes** |
| M9 | a skill's `version:` frontmatter is never read | G1 | **yes** |
| M10 | the age problem is folded into the read problem | G10, U7 | **both** |

**What it does not prove, stated rather than implied:** that these are the ten mutations that
matter. Each named test can fail for the reason its name gives; nothing here says the suite would
catch a defect nobody thought of.

---

## 4 · Three defects the tests found in this item's own code

Recorded because each was found by an assertion going red, not by re-reading.

1. **A non-GET on `/extensions/updates` answered `404 no extension kind named "updates"`.** The
   route declined the method, and `routeExtensions` then matched the path as a `:kind`. A reply
   denying that a served path exists. Fixed by teaching `routeExtensions` to decline `/updates`
   explicitly; M5 is the arm that holds it.
2. **The first fixtures were built through `add`, which cannot express the real shape.** `add`
   refuses a descriptor whose `name` differs from the entry name — and the real store cannot
   satisfy that, because R30 stores a plugin under `<plugin>@<marketplace>` while the `plugin.json`
   Claude wrote says `<plugin>`, which is exactly why R30 uses `adopt`. Both benches and the lane
   now write their entries with `mkdir` and `printf`.
3. **An unmeasurable catalogue age suppressed every comparison against it.** The first fix for a
   negative age folded it into the catalogue's read problem, which turned eight working verdicts
   into `no-catalogue`. How old a file is and whether it parses are independent questions, and
   `CatalogueReading` now carries them as two members. M10 is the arm.

The lane found three more before it went green: an assertion that an untokened read is refused
(the control token guards the mutating half, so a GET is served — the lane now asserts the design
instead of a guess about it), a fixture whose catalogue did not offer the entry the row was named
for, and a row count that forgot a marketplace is an entry as well as a catalogue.

---

## 5 · Case ids allocated

The registry's maximum at HEAD is **`CASE-0261`**, read from
`planning/test-campaign/cases.in.json` (98 rows). `cases.json` holds 142 rows to `CASE-0222` and is
the **derived** register — `record-arms.py` writes it and refuses an id `cases.json` does not
already hold — so the authored input is the file that carries the maximum. The brief's figure of
`CASE-0216` was stale in both.

**Taken: `CASE-0262` … `CASE-0266`**, in `cases.in.json`, each citing the lane transcript and the
red-green record.

| id | req | what it holds |
|---|---|---|
| CASE-0262 | REQ-007 | `update-available` is one verdict of eight, and the machine cannot produce it |
| CASE-0263 | REQ-007 | a catalogue older than the install is never reported as an update |
| CASE-0264 | REQ-007 | `0 updates` is distinguishable from having read nothing |
| CASE-0265 | REQ-007 | an age that cannot be taken is `null`, never `0` and never negative |
| CASE-0266 | REQ-012 | four mutating verbs are 405 and the store is unchanged |

**Carried:** the derived `cases.json` does not hold these five. Its generator arms a case that is
already in it, and seeding it by hand would put the derived register ahead of its input — the same
disagreement `K5` declined to create and recorded instead of papering over.
