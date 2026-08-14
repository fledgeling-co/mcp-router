# M7 — acceptance evidence

`Evals and Cleanup` · branch `ai/m7` · worktree `.worktrees/M7`
Spec `planning/specs/spec-M7.md` (A1–A30) · Plan `planning/plans/plan-M7.md` ·
Design `DESIGN.md` (authoritative) ·
Mock `design/mocks/prototype.html?only=mac&pane=evals` and `?only=mac&pane=cleanup`

Append to this file, never rewrite it. Read it **before** testing anything: if a row exists and
`git diff <that SHA>..HEAD` does not touch the files behind it, that row *is* the evidence, and the
right thing to do is skip the check and say so.

---

## What was verified, and what was deliberately not

**Two surfaces changed in this item**: the Evals pane and the Cleanup pane, both new, plus their
sheets. Everything below drives those two and nothing else, in **one launch**.

**Not re-verified, and why.** Servers, Skills, Activity, Settings and Discover are M3's, M4's, M2's,
M8's and M5's, and this branch does not touch the files behind them. Their evidence is
`planning/evidence/M3-acceptance.md`, `M4-`, `M2-`, `M8-` and `M5-acceptance.md`. Re-running those
against unchanged code has exactly one possible outcome. The shell's own clauses belong to
`scripts/acceptance/mac-shell.sh` and are not repeated here.

**Inbox was not driven at all.** It is the one destination still in `BoardRegistry.scaffolded`, so
driving it would prove only that a placeholder is a placeholder.

**What this branch changes outside its own files** is the board registry, its assertions in two
separate files, and the three acceptance scripts that read the registry. Those are covered by the
unit suite and by re-running the affected scripts, not by the rendered pass.

---

## The run

Every row below comes from **one** invocation of `scripts/acceptance/m7-evals-cleanup.sh` at
`7a4f60a`, plus its repeat to capture the exit code. The app was launched with `open -g`, every
read was an accessibility query by pid, and the script asserts at both ends that MCP Router never
became frontmost.

```
frontmost at start: Proctor
final frontmost:    Proctor
16 passed, 0 failed
exit 0
```

| # | Screen / clause | How it was verified | SHA | Result |
|---|---|---|---|---|
| 1 | Build tree installs `.evals` and `.cleanup` | `board_registry_installs` over `ScaffoldPane.swift` | `7a4f60a` | pass |
| 2 | **Evals** is not the placeholder | `axkit select <pid> Evals`, then the scaffold sentinel `isn't built yet` absent from every string the window speaks | `7a4f60a` | pass |
| 3 | Evals window title (§3.7) | `axkit title <pid>` == `Evals` | `7a4f60a` | pass |
| 4 | Evals renders real rows | 10 row-bearing `AXButton` elements from the `populated` fixture | `7a4f60a` | pass |
| 5 | A17b — no grading vocabulary | 11 grading words (`healthy`, `score`, `grade`, `rating`, `failing`, `good`, `bad`, …) absent from the spoken tree | `7a4f60a` | pass |
| 6 | A17b — the scan is not vacuous | the four observation nouns *are* on screen, asserted with `blocked` rather than `fail` | `7a4f60a` | pass |
| 7 | A4 — no figure the router does not observe | 8 patterns for run counts, durations, byte figures and memory savings absent, matched as figures-with-units rather than bare words | `7a4f60a` | pass |
| 8 | A18 — the disclosure is present | the pane speaks about the router | `7a4f60a` | pass |
| 9 | **Cleanup** is not the placeholder | `axkit select <pid> Cleanup`, sentinel absent | `7a4f60a` | pass |
| 10 | Cleanup window title (§3.7) | `axkit title <pid>` == `Cleanup` | `7a4f60a` | pass |
| 11 | The rejected trash metaphor | 8 spellings (`trash`, `bin`, `recycle`, `rubbish`, `wastebasket`, `garbage`, `delete forever`, `empty the`) absent from the **rendered tree**, not only from source | `7a4f60a` | pass |
| 12 | A8 — the observation window is the router's own | `1d recorded` on screen, read from `UsageSummary.since` | `7a4f60a` | pass |
| 13 | A8 — no invented threshold | the prototype's `last > 3600` and its prose forms reach no surface | `7a4f60a` | pass |
| 14 | A16 — no skill removal the router cannot perform | no enabled `AXButton` matching a skill removal anywhere in the pane | `7a4f60a` | pass |
| 15 | Offline state | relaunched under `offline`: the pane reports the router, and **states no count it did not observe** — the considered zero this item fixed | `7a4f60a` | pass |
| 16 | Partial state | relaunched under `partial`: renders under an unreadable client | `7a4f60a` | pass |
| 17 | Never took the screen | `axkit front` at start and end, plus after every launch and every assertion block | `7a4f60a` | pass |

### The pass is not vacuous, and that was measured rather than assumed

Two of the searches carry their own `blocked` guard, so a tree that failed to render would report a
harness failure rather than a clean sweep: the grading-word scan is void unless the four observation
nouns are on screen, and the fabricated-figure scan unless the pane discusses the router.

The script as a whole was checked by making it fail. Its vocabulary gate was pointed at a word that
**is** on screen (`Evals`), and the run ended:

```
EXIT=1
FAIL: the Evals pane speaks a grading word: 'Evals'
```

The mutation was reverted and the full pass re-run green.

---

## Verified by unit test rather than by the rendered pass

These are behavioural claims proven where they can actually be asserted. Full suite at `7a4f60a`:
**1057 tests in 134 suites passed**.

| Clause | Test | Kind |
|---|---|---|
| A5 | `callsSucceed` over `calls ∈ {0,1,7}` × `errors ∈ {0,1,9}` — zero calls is never a confirmation | exhaustive |
| A5b | `updateWantsNoMore(held: nil)`, `originUnchanged(.standalone)`, `authorized(!supported)` are `.notApplicable` | per case |
| A5c | `declaresTools` is `.unknown` for every `tools` value when `indexError != nil` | exhaustive |
| A6 | `reachable` over both unreadable signals independently and a missing `presence` key | exhaustive |
| A8b | `callsServed > 0, usage.calls == 0` ⇒ listed — a reset history is visible | measurement |
| A10b | `historyRowState` over the stored × live stamp cross product | exhaustive |
| A15b | an **unobserved** call count renders no number in the reset consequence, and differs from an observed zero | red→green |
| A15 | a removal with no statable consequence says so and disables Remove | source + string |
| A17 | every `CheckResult` carries a non-empty statement, over all eleven ids | structural |
| — | the observation track substitutes no day count for an unknown window | source guard |
| — | the badge note waits for a reading rather than counting from nothing | source guard |
| — | the reset dialog passes the observed count through, nil and all | source guard |
| — | no trash metaphor in the four Cleanup sources, comments stripped first | source guard |

The four source guards are in `app/Tests/MCPRouterUITests/M7BoardHonestyTests.swift`. They are
source guards because a SwiftUI `body` is not inspectable from a unit test — a real limit, stated in
the file. Rows 11 and 15 of the rendered pass above are what cover the same rules against pixels.

---

## What is NOT proven, and by what

**The segmented filter cannot be driven by this toolkit.** Both panes carry a segmented filter,
which SwiftUI renders as an `AXRadioGroup` of `AXRadioButton`s. `axkit press` matches
`AXRole == "AXButton"` only — deliberately, per its own comment about menu items — so no verb here
can operate a segment.

This is M5's deferred child **M5-d**, raised an item earlier with the explicit prediction that M7's
two boards would hit the same wall. They do. It is a tooling gap, not a defect in this item, and
nothing here fakes a press to cover it.

What *is* proven: the filter's logic is exhaustive in the unit suite (`CheckPresentation.Filter`,
`CleanupBoardModel.rows`, including the rule that a filter with no matches carries no badge rather
than a zero). What is **not** proven by any rendered pass is that pressing the drawn segment reaches
that logic. Closing it needs a `press` verb that accepts a role other than `AXButton`, which is
M5-d's scope.

**`⌘F`, the arrow-key order and `⌘⌫`** are asserted behaviourally in the unit suite against the
board models. They are not driven through the rendered tree here: `axkit key` delivers to a process,
but the menu commands these shortcuts route through reach the window via `@FocusedValue`, which an
inactive app does not have — and activating the app is the one thing this gate may not do.

---

## A pre-existing failure on main, found while re-running the shell gate — NOT M7's

`scripts/acceptance/mac-shell.sh` **exits 1 on this branch and on main**, at its A22 clause:

```
FAIL: File / Add server… carries no discoverable reason (AXHelp was '')
```

It is reported here rather than fixed: the fix is to a merged shared surface (`spec-M1.md`'s
command inventory), which this item may not edit.

**What is wrong.** A22 reads its oracle from the command inventory table in
`planning/specs/spec-M1.md:49`, which lists seven commands as `surfaceAbsent`. That was true in M1's
world, where `BoardRegistry.installed` was empty. `MenuCommand.availability(in:)` derives the real
answer from what is installed, so as boards landed the two drifted apart:

| Inventory row | Says | `availability(in:)` actually returns now | Stale since |
|---|---|---|---|
| File / Add server… | `surfaceAbsent` | `.enabled` — `hasServers` | M3 `589ab2e` |
| Edit / Find | `surfaceAbsent` | `.enabled` — same rule, same commit | M3 `589ab2e` |
| File / Add marketplace… | `surfaceAbsent` | `.enabled` — `.skills` installed | M4 |
| Edit / Reset server | `surfaceAbsent` | `.needsServerSelection` | M3 `589ab2e` |
| Edit / Remove server | `surfaceAbsent` | `.needsServerSelection` | M3 `589ab2e` |
| File / Pair iPhone… | `surfaceAbsent` | `.surfaceAbsent` — still correct | — |
| File / Export library… | `surfaceAbsent` | `.surfaceAbsent` — still correct | — |

Five of the seven rows are wrong. A22 fails on the first one it reaches.

**Two independent probes, because "not mine" is exactly the claim a runner most wants to be true.**

1. *Structural.* Both inputs to the failing assertion — `planning/specs/spec-M1.md` and
   `app/Sources/MCPRouterKit/Shell/MenuCommand.swift` — are byte-identical to `main`
   (`git diff --quiet main HEAD --` reports no change for either). M7's only edit to
   `mac-shell.sh` is the registry reader, hundreds of lines from A22. The assertion's inputs and
   its logic are therefore exactly main's, so main reaches the same verdict.
2. *Historical.* `planning/evidence/M1-acceptance.md:60` records A22 green at `8858864` with
   **"7 `surfaceAbsent` commands"** — the count that was correct when no board was installed. M3
   installed `.servers` in the same commit that gave `Add server…` and `Find` their `hasServers`
   rule, and nothing updated the inventory. The regression is dated to that commit by the code, not
   inferred.

**Suggested fix, for whoever owns it:** the inventory is a static table restating a rule the code
computes, which is why it can rot silently. Either regenerate the `availability` column from
`MenuCommand.availability(in:)` under the build's real `installedDestinations`, or drop the column
and have A22 read the rule directly. Restating it by hand a third time buys another silent
divergence at the next board to land.

**M7 did not run into this and does not depend on it.** `m7-evals-cleanup.sh` covers this item's two
panes and passes 16/16; the shell's own clauses are `mac-shell.sh`'s and were never M7's to assert.

---

## Deferred children discovered

| Suggested id | Title | Deps | Why |
|---|---|---|---|
| **M9** | Rename the `Evals` destination to `Checks` | M1, M7 | The residual objection this item cannot fix from inside. Every *reading* on both panes is an observation with its input shown beside it, and the vocabulary carries no grading verb — but the word "Evals" in the sidebar, the window title, the menu and the deep link still says "test results". `Destination.title` is a merged shared surface. |
| M10 | Amend `DESIGN.md` §6:279–280 | M7 | Its mandated "not evaluated" skill string describes a state that no longer exists. DESIGN.md is authoritative and merged; a runner editing it unilaterally is how a design authority stops being one. |
| **M11** | Regenerate `spec-M1.md`'s command-availability inventory from the code | M1, M3, M4 | Five of its seven `surfaceAbsent` rows are wrong and `mac-shell.sh` A22 has been red since M3. See the section above. The inventory restates by hand a rule `MenuCommand.availability(in:)` computes, which is why it rots silently. |
| R6 | Router-side behavioural eval runner — **servers only** | R3, R4 | The router can start a server and call a tool; it cannot execute a skill. A runner that promised both would be promising something the product does not do. |
| R7 | Skills write endpoint (remove/disable) with preconditions and undo | R3 | Cleanup lists absent skills and can offer no action on them, because the control API is read-only for skills. A16 asserts that gap rather than hiding it. |
| R8 | Server soft-delete with a restore endpoint | R3 | Removal is irreversible today, which is why it needs a named-consequence dialog. |
| **M5-d** (already open) | An `axkit` verb that can press a non-`AXButton` role | — | Raised by M5, predicted to hit M7's two boards, and it did. Until it exists no rendered pass can drive a segmented filter. |

## Shared-surface changes wanted and deliberately skipped

- `Destination.title` `.evals` → "Checks". **Reported, not made** — M9.
- `DESIGN.md` §6:279–280's mandated "not evaluated" string. **Reported, not made** — M10.
- `planning/specs/spec-M1.md`'s command inventory. **Reported, not made** — M11.
- A `BadgeSource` case for Cleanup's actual predicate. Not added: it would be a count the router does
  not serve as such, so the pane states the relationship in words instead.

## Shared-surface changes that WERE made, and why they were not optional

`scripts/acceptance/m2-activity.sh` and `m5-discover.sh` both read `BoardRegistry.installed` with a
`head -1` grep. Installing a seventh board wraps that declaration past `--maxwidth 110`, and a
wrapped declaration makes those reads match nothing — so both scripts would have reported
`BLOCKED: the tree being tested does not install .activity` for boards that shipped and merged.

This was not a change M7 wanted; it is a repair of readers M7's own change breaks. Leaving them
would have shipped a regression in two merged gates. The three readers are now one
(`scripts/acceptance/board-registry.sh`), and both scripts were re-run on this branch to prove it:

```
m2-activity.sh   exit 0 — every assertion passed, and the app was never brought to the front
m5-discover.sh   exit 0 — 32 passed, 0 failed — MCP Router never came to the front
```
