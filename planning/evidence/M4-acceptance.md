# M4 — acceptance evidence

`Skills and marketplaces` · branch `ai/m4` · worktree `.worktrees/M4`
Spec `planning/specs/spec-M4.md` · Plan `planning/plans/plan-M4.md`
Design `design/mocks/html/m4-skills-board.html`

Append to this file, never rewrite it. Read it **before** testing anything: if a row exists and
`git diff <that SHA>..HEAD` does not touch the files behind it, that row *is* the evidence, and the
right thing to do is skip the check and say so.

---

## What was verified, and what was deliberately not

**One screen changed in this item: the Skills pane.** `BoardRegistry.installed` is
`[.servers, .skills]`, so five of the seven destinations still render `ScaffoldPane` and driving
them would prove only that a placeholder is a placeholder. They were **skipped deliberately**.

The **Servers pane was not re-verified**. This branch touches two files behind it —
`ShellWindow.swift` (one branch added to `pane`) and `ShellCommandRouter.swift` (`focusSearch` now
checks the destination) — and both changes are covered by tests that ran green, including M1's own
`ShellCommandRouterTests` which asserts the Servers routing is unchanged. M3's rows at `589ab2e`
remain the evidence for that board.

The menu bar **was** read, because this item changes one of its items from `surfaceAbsent` to live.

## The pass was invisible

**MCPRouter was never frontmost, before, during or after.** No `open -a`, no `open -g -a`, no
`activate`, no `set frontmost to true`. The binary was launched **directly** —

```
MCPROUTER_SCENARIO=populated nohup "<worktree>/app/.derived/.../MCPRouter" &
MINE=$(pgrep -f "worktrees/M4/app/.derived.*MCPRouter" | head -1)
```

— for the reason M3 recorded: `open -g -a` reuses another worktree's already-running app because
they share a bundle identifier, and the first pass would then measure somebody else's build. Every
read went over the accessibility plane by pid via `scripts/acceptance/axkit.swift`, and the one
screenshot was `screencapture -l<CGWindowID>`, which is window-scoped, never `-R`, which photographs
whatever is on top.

`axkit front` was sampled at every step and returned **TextEdit**, then **Ledger**, then **Ghostty**,
then **Google Chrome** — the user switching applications around the run. It never once returned
MCPRouter, which is the invariant that matters.

---

## Screens verified — at `3f52f14` + the two fixes below

Three launches, each terminated before the next: the first found a menu defect, the second confirmed
its fix and found a layout defect, the third confirmed that. Recorded as three rather than presented
as one, because a single clean pass here would not be true.

| Screen | How verified | Result |
|---|---|---|
| Skills pane renders the board, not the placeholder (A1, A2) | `axkit select <pid> Skills`, then `axkit dump <pid> window`; counted the scaffold sentinel | **pass** — `isn't built yet` occurs **0** times; window title followed to `Skills` |
| Header and subtitle | same dump | **pass** — `Skills`, `6 skills · 4 marketplaces · 1 held for review`, `Manage marketplaces…` |
| Filter segments carry counts, and none reads zero | same dump | **pass** — `All 6`, `Held 1`, `Local 2`, `Needs attention 2` as `AXRadioButton`/`AXSegment` |
| Column headers name the right entity | same dump | **pass** — `skill`, `installed into`, **`plugin version`** — not "version", because a plugin can supply thirty skills that share one |
| Rows, and what each one speaks | same dump, row `AXDescription` | **pass** — six rows, listed in full below |
| The footer states the absence once | same dump | **pass** — the full `Run counts and evaluation results are not shown…` sentence is present, and there is no runs, last-run or eval column anywhere in the tree |
| Row geometry is fixed | same dump, row `AXSize` | **pass** — every row `48.0`pt; sidebar `256.0`pt |
| Skills sidebar row carries **no** badge | same dump | **pass** — `Skills` has no count, while `Servers, 1 need attention` and `Cleanup, 3 never used` do. M1's rule that Skills may never carry a badge still holds |
| Menu — `Add marketplace…` went live | `axkit dump <pid> menu`, `AXHelp` field | **pass after fix** — carries **no** reason; `Pair iPhone…` and `Export library…` still carry `This part of the app isn't built yet.` |
| Board reads from its top edge | `axkit dump`, header y-position | **pass after fix** — header at `208.0`, directly under the 192pt toolbar |
| Rendered appearance | `screencapture -l<CGWindowID>` → `design/mocks/m4/skills-board-populated.png` | **pass** — lit vs dim slot pips, amber held arrow, amber provenance warning, `unversioned` visibly in the body face while `1.14.0` is monospace |
| Invisibility invariant | `axkit front` at every step | **pass** — never MCPRouter |
| The five scaffolded destinations | **not tested, deliberately** — each renders `ScaffoldPane`; there is nothing in them to drive | skipped |
| The Servers pane | **not re-tested, deliberately** — M3's rows at `589ab2e` stand; the two files this branch touches behind it are covered by tests that ran green | skipped |

### The six rows, as the accessibility tree speaks them

```
design-craft, diolog-plugins, 1.14.0, In Claude Code, Cursor and opencode
trawl, fledgeling-plugins, 2.2.0 → 2.3.0, In Claude Code, Codex and Cursor
changelog-writer, community, 0.4.1, In Claude Code, Owner changed — was github:acme-tools/skills
intent-layer, local — not from a marketplace, unversioned, In Claude Code, Codex, Cursor and opencode
ai-gateway, vercel · claude-plugins-official, 0.45.1, In Claude Code
graphify, local — not from a marketplace, unversioned, In Claude Code
```

Four of the design's load-bearing decisions are legible in those six lines: a held version reads as
an arrow between two versions; a moved owner replaces the marketplace line rather than sitting beside
it; a hand-placed skill says `unversioned` and never a number; and `ai-gateway` names its **plugin**
because `vercel` supplies thirty skills that all share `0.45.1`.

---

## Two defects the pass found, and what was done

**1 · `Add marketplace…` still said the app was not built.** The first menu dump showed the item
carrying `This part of the app isn't built yet.` after the Skills board had shipped — the shell
disagreeing with its own window. `MenuCommand.availability` hardcoded `.surfaceAbsent` for it.
Fixed the way M3 fixed the Servers commands: it is now `.enabled` when `.skills` is installed, and
routes to `.showMarketplaces`, which selects Skills and opens the marketplaces sheet.
`SkillsMenuTests` covers both directions and reads `BoardRegistry.installed` itself, so it fails if
the board is ever un-installed while the menu keeps claiming it works.

Found only by driving the app. No test would have caught it, because no test asserted the item's
reason after a board shipped.

**2 · The board was vertically centred, with ~170pt of dead space above the header.** Measured, not
eyeballed: the header sat at y=362.5 inside a scroll area starting at y=192. The shell's content zone
gives its pane a `minHeight` so there is always something to scroll, and a `VStack` handed more height
than it needs centres itself in it. Pinned with `alignment: .topLeading`; the header now sits at
y=208.

**A third finding was left alone deliberately.** `ShellCommandRouter.focusSearch` selected `.servers`
unconditionally, so `⌘F` on the Skills board would have navigated away from the pane being filtered.
That is fixed here rather than reported, because it is a defect *this item created* by being the
second board — before Skills existed the behaviour was correct.

---

## Red-green: four guards deliberately broken and watched to fail

`SWIFT_PRACTICES.md` §7 — a test that has never failed is not known to work. Each mutation was
applied, the named test run, the failure counted, and the source restored.

| Mutation | Guard | Issues raised |
|---|---|---|
| `version()` returns `1.0.0` in the instrument face for a standalone skill | `standaloneHasNoVersion` | **2** |
| `slot()` maps `.unreadable` to `.off` | `unreadableIsNotAbsent` | **1** |
| A stored `runs: Int` added to `Skill`, so it reaches the wire | `noUnobservableFieldsExist` | **1** |
| `SkillsResponse` decodes a missing `skills` key as `[]` — the flat-`servers.json` trap | `missingSkillsKeyFails` | **1** |

All four went red; the suite is green with the source restored.

---

## Gates

| Gate | Result |
|---|---|
| `swift test` | **774 tests in 107 suites passed**, run four times |
| `make lint` | clean — swiftformat, swiftlint `--strict`, `no-raw-design-values`, `no-wire-codable` |
| `make build-mac` | `** BUILD SUCCEEDED **` |
| `StandingConstraintsTests` A38 | **pass** — `git diff main -- src/ install.sh package.json` is empty |
| `ShellIntegrationTests` complement | **pass** — `installed` and `scaffolded` are exact complements with `.skills` added |
| `ShellIntegrationTests` board-file list | **pass** — the six new board files are registered, so they sit inside the one-channel and indicator-colour gates |

### One flake observed and not hidden

A single full run failed `RegistryEnrichmentTests."an absolute path discards the base's own path"`.
It passed on three consecutive re-runs of that suite alone and on three consecutive full runs
afterwards. It is in `RouterCoreTests`, uses a shared HTTP stub, and this branch touches nothing it
covers — so it reads as pre-existing order/parallelism sensitivity rather than a regression. Recorded
because a flake that goes unrecorded is a flake the next runner rediscovers from scratch.

---

## Clauses proved by test rather than by driving the app

Behavioural claims about logic, where a unit test is the stronger evidence — a rendered check could
only ever sample a few of the inputs.

| Clause | Where |
|---|---|
| Version display, source line, slot state, filters, search, counts, empty-in-filter, partial note, held-sheet copy, marketplace lines | `SkillPresentationTests`, `SkillPresentationStateTests` (two suites only because one struct may not exceed the linter's body-length limit) |
| Closed enums fail on unknown values; tagged unions; missing-key decoding; no `runs`/`lastRun`/`eval` on the wire, asserted against the **encoded JSON** | `SkillModelsTests` |
| `Add marketplace…` availability in both directions, and against the real `BoardRegistry` | `SkillsMenuTests` |
| `.skills` is installed and the complement holds | `ShellIntegrationTests` |
| Every command outside the acting set still maps to no operation | `ShellCommandRouterTests` |

### Not verified in the running app, and said so

The **Empty, Loading, Partial, Offline and Error** states were not driven. `FixtureControlAPIClient`
answers them (`empty`, `loading`, `partial`, `offline`, `error` scenarios all reach `skills()`), so
the lane exists and a later runner can drive them with `MCPROUTER_SCENARIO`. They were skipped here
because the rule is one launch per pass and the populated state is the one this item changed most;
their copy is asserted as literals by test. A runner picking this up should drive them rather than
assume this row covers them.

---

# Second pass — the resume, after the 503

Appended, not rewritten. The rows above still stand: they were taken at `3f52f14`+fixes, which
survived the rebase as `33463a2`, and this pass re-verifies only what changed since.

## What changed since the rows above, and therefore what was in scope

`git diff 33463a2..HEAD --name-only` names ten files. Four are UI:

| File | What changed | Rendered effect |
|---|---|---|
| `SkillsBoard.swift` | empty-state message now keyed on filter **and** search; segment labels search-aware | yes |
| `SkillSheets.swift` | marketplace `Remove` became a visible `DisabledAction` instead of a `.help()` tooltip; missing-subject copy reworded | yes |
| `SkillInspector.swift` | **new** — inspector item 7, the auto-update section | yes |
| `SkillsBoardModel.swift` | `Task.isCancelled` guards | no — a cancelled load leaves no banner |

Everything else is `SkillPresentation` / `SkillCopy` copy and the tests over them.

**Still one screen: the Skills pane.** `BoardRegistry.installed` is `[.servers, .skills]`, so five of
seven destinations remain `ScaffoldPane` and were **not** driven — there is nothing in them to drive.
The **Servers pane was not re-verified**: `git diff 33463a2..HEAD` touches no file behind it, so M3's
rows at `589ab2e` remain its evidence. The menu bar was **not** re-read: `SkillsMenuTests` is
unchanged and still green, and no menu code was touched this pass.

## The rendered pass is BLOCKED, and was not faked

The accessibility plane is unavailable to this session. Two probes, per the two-probe rule:

| Probe | Command | Result |
|---|---|---|
| 1 — a freshly built toolkit | `swiftc -O -o /tmp/m4-pass/axkit scripts/acceptance/axkit.swift` then `axkit trusted` | `no` |
| 2 — the toolkit the earlier passes actually used | `/tmp/m3-ax/axkit trusted` (built 20:18, the binary behind the rows above) | `no` |

`axkit front` still answers (`Ledger`) because that reads `NSWorkspace`, not the AX API — so the
process runs, and it is specifically the **AX trust grant** that is absent. The grant belongs to the
responsible process; it was present when the rows above were taken and is not present for processes
this session spawns. Granting it means editing TCC, which is a change to the user's system
permissions and is not mine to make unilaterally. `proctor` is not exposed as a tool in this session,
so the documented fallback was unavailable too.

**A launch was attempted and cleanly abandoned.** The app was started from the worktree binary
directly (never `open -a`, never `activate`), `axkit select` and `axkit dump` both returned
`axkit: not trusted for accessibility`, and the process was terminated. `axkit front` was sampled at
four points across the attempt — before launch, after select, after the key event, after teardown —
and returned **`Ledger`** every time. The user's screen was never taken.

## What was done instead of faking it

The one genuinely new rendered element is inspector item 7. Rather than assert a string and call it
proof, its **decision** was extracted out of the view into `SkillPresentation.autoUpdateItem(for:in:)`,
which returns a three-case enum, and the view became a `switch` with no logic in it. That is the seam
`SkillPresentation.swift` already declares — decisions in Kit, sentences in Copy, drawing in UI — and
it converts an untestable view branch into a tested one.

| Clause | Evidence | Result |
|---|---|---|
| Item 7 present for a marketplace skill, with the setting read off the record | `autoUpdateItemPicksTheRightOutcome` | pass |
| A missing record resolves to `.unread`, **never** to `.setting(isOn: false)` | same | pass |
| A hand-placed skill omits the section rather than showing an unread one | same | pass |
| A local directory's reason is permanent ("nothing to fetch"), not the board-wide "not yet" | `autoUpdateItemDistinguishesLocalFromUnbuilt` | pass |
| The unread sentence is not mistakable for either real state | `autoUpdateWithoutARecordSaysSo` | pass |
| Empty-state label and action are one judgement (`clearsSearch`) | `actionMatchesItsLabel` | pass |
| Segment counts follow the search | `countsFollowTheSearch` | pass |
| A search matching nothing is explained under every filter, `All` included | `searchEmptinessIsAlwaysExplained` | pass |
| The held body promises no action the sheet cannot perform | `heldBodyDoesNotPromisePromotion` | pass |

### Red-green: both new guards broken and watched to fail

| Mutation | Guard | Issues raised |
|---|---|---|
| `autoUpdateItem` returns `.setting(line: "Auto-update off", isOn: false)` where it should return `.unread` — the exact collapse the enum exists to prevent | `autoUpdateItemPicksTheRightOutcome` | **1** |
| `autoUpdateReason` gives a local directory the generic "not yet" sentence | `autoUpdateItemDistinguishesLocalFromUnbuilt`, `suppliesNothing` | **3** |

Both went red; the suite is green with the source restored.

## Gates, this pass

| Gate | Result |
|---|---|
| `make -C .worktrees/M4 test` | **819 tests in 113 suites passed** |
| `make -C .worktrees/M4 lint` | **0 violations, 0 serious in 257 files**; `no-raw-design-values: clean`; `no-wire-codable: clean` |
| `make -C .worktrees/M4 build-mac` | `** BUILD SUCCEEDED **` |

Note on the lint gate: the first run was issued without `-C` and linted the **main checkout** (243
files) rather than this worktree. Re-run against the worktree it reports 257 files. The 257-file run
is the one that counts, and the main checkout was confirmed unmodified afterwards.

## Still not verified in a running app, and said so plainly

The **Empty, Loading, Partial, Offline and Error** states remain undriven — same as the first pass,
and now for a second reason on top of the first. `FixtureControlAPIClient` answers all five via
`MCPROUTER_SCENARIO`, so the lane exists. **Inspector item 7 has never been seen rendered**, by
anyone: its logic is tested in all three branches and its layout is not. A runner that inherits a
working AX grant should drive the Skills pane with a row selected and confirm the section draws,
and should not treat the table above as covering that.
