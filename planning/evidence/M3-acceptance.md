# M3 — acceptance evidence

`Servers: the breaker board` · branch `ai/m3` · worktree `.worktrees/M3`
Spec `planning/specs/spec-M3.md` (A1–A33) · Plan `planning/plans/plan-M3.md`

Append to this file, never rewrite it. Read it **before** testing anything: if a row exists and
`git diff <that SHA>..HEAD` does not touch the files behind it, that row *is* the evidence, and the
right thing to do is skip the check and say so.

---

## What was verified, and what was deliberately not

**One screen changed in this item: the Servers pane.** The other six destinations are still
`ScaffoldPane`, and driving them would prove only that a placeholder is a placeholder. They were
**skipped deliberately**, and the skip is safe to state because `BoardRegistry.installed` is the
single source for which destinations have a surface — it contains `.servers` and nothing else.

The menu bar was read because M3 changes four of its items from `surfaceAbsent` to live. Nothing
else in the shell was re-verified: M1's rows at `8858864` cover the window, the sidebar, restoration,
the bare keys and the scroll edge, and this branch does not touch the files behind them except
`ShellWindow.swift` (one branch added to `pane`) and `ShellModel.swift` (two additive members).

## The pass was invisible, and two things about that are worth recording

**Ghostty was frontmost before, during and after every read.** The app was never activated: no
`open -a`, no `activate`, no `set frontmost to true`, and every read went over the accessibility
plane by pid using `scripts/acceptance/axkit.swift`, which M1 built for exactly this.

**`open -g -a` attached to another runner's app, and that is a trap worth naming.** The fleet was
running M2 concurrently from `.worktrees/M2`, whose build carries the same bundle identifier. macOS
LaunchServices saw MCPRouter already running and *reused it* rather than launching this worktree's
binary — so the first pass read M2's window, found the scaffold sentinel, and would have reported
this board as unbuilt. The fix is to launch the executable directly:

```
MCPROUTER_SCENARIO=populated nohup "<worktree>/app/.derived/.../MCPRouter" &
MINE=$(pgrep -f "worktrees/M3/app/.derived.*MCPRouter" | head -1)
```

and to drive and terminate **that pid only**. M2's instance was left running and was confirmed alive
afterwards. Any later runner verifying a Mac surface while the fleet is live must do the same, or it
will measure somebody else's build.

**`AXEnabled` is unusable on a background app's menu.** Every item in all six menus reports
`AXEnabled 0` while the app is inactive, including ones that are plainly enabled. The signal that
*does* work is the help tag, which is what §3.4 requires a disabled command to carry — so
"enabled" is measured as *the absence of a reason*, and it distinguishes correctly (see A28).

---

## Screens verified — at `589ab2e`

One launch, one pass, terminated at the end.

| Screen | How verified | Commit | Result |
|---|---|---|---|
| Servers pane — renders the board, not the placeholder (A1, A2) | `axkit select <pid> Servers` then `axkit dump <pid> window`; counted the scaffold sentinel `isn't built yet` in the tree | `589ab2e` | **pass** — 0 occurrences; window title followed to `Servers` |
| Servers pane — header, filter, search (A9, D6) | same dump | `589ab2e` | **pass** — `Servers`, `2 tools from 4 servers · 1 running`, `Add server…`, segments `All 4 / Running 1 / Idle 3 / Needs you 1`, a search field and its magnifying-glass icon |
| Servers pane — rows and their spoken state (A3, A7, A32) | same dump, row `AXValue` and `AXDescription` | `589ab2e` | **pass** — four rows; breaker values `Dormant`, `Running`, `Wants your decision`; descriptions `fixture-tools, reaps in 300s, stdio, 2, 1 calls, 17h` and `fixture-oauth, needs authorising, http, 0, 0 calls, Never` |
| Servers pane — row geometry (A33) | same dump, row `AXSize` height | `589ab2e` | **pass** — every row `56.0`pt, matching `MetricToken.serversRow`; sidebar column `256.0`pt |
| Servers pane — footer (M1 gate finding) | same dump | `589ab2e` | **pass** — `4 of 4 servers · 2 tools indexed`; the false "in every session's tool list" claim is gone |
| Menu bar — the four board commands went live (A26, A28) | `axkit dump <pid> menu`, field 7 (`AXHelp`) | `589ab2e` | **pass** — `Add server…` and `Find` carry **no** reason (they carried "This part of the app isn't built yet." in M1); `Reset server` and `Remove server` carry `Select a server first.` with nothing selected; `Add marketplace…`, `Pair iPhone…`, `Export library…` still carry the surface-absent reason |
| Invisibility invariant | `axkit front` before launch, after launch, after each read, after terminate | `589ab2e` | **pass** — `Ghostty` every time |
| The other six destinations | **not tested, deliberately** — `BoardRegistry.installed == [.servers]`, so each renders `ScaffoldPane` and there is nothing in them to drive | `589ab2e` | skipped |

### One read raced, and the retry is recorded rather than hidden

The **first** menu dump showed no reason on `Reset server` / `Remove server`, which would have been a
failure. It was a race, not a defect: `ShellMenuReasons` documents that SwiftUI builds a
`CommandGroup`'s items **bare** and the walker re-applies every 100 ms, so a dump taken in that
window reads an un-annotated item. A second dump two seconds later showed both reasons. Recorded
because the same race will bite the next runner, and because a single green read here would not have
been trustworthy either.

---

## Clauses proved by test rather than by driving the app

These are behavioural claims about logic, not about rendering, and a unit test is the stronger
evidence for them — a rendered check could only ever sample a few of the inputs.

| Clause | Where | Note |
|---|---|---|
| A3, A4, A5, A6, A7 | `ServerPresentationTests` | A4 and A7 are **cross products**, not examples |
| A8, A18, A24 and the filters, search, header, row model | `ServerBoardShapeTests` | |
| A11–A18, A29 | `ServersBoardWriteTests` | asserted on the **encoded request body**, not the Swift value |
| Success, the write gate, failure reporting | `ServersBoardOutcomeTests` | |
| A1 | `ShellIntegrationTests.serversBoardIsInstalled` | plus the complement invariant |
| A26, A27 | `ShellCommandRouterTests` | A27 proves M1's contract is untouched |
| A30, A32 | `ShellAppearanceTests`, extended to scan the board files | |
| A13 | `ServersBoardWriteTests` | narrowed to PATCH — see the spec's gate record for why the wider claim was false |

### Red–green: the guards were seen to fail before they were trusted

`SWIFT_PRACTICES.md` §7 — a test that has never failed is not known to work. Three mutants were
introduced into `ServerPresentation.swift`, each run, each restored:

| Mutant | What it reinstates | Caught by |
|---|---|---|
| M1 | `if server.warm, server.state == .running` — the prototype's conjunction | A4's reads-as-warm clause and A5, with `warm · never reaped` becoming `dormant` / `starting` / `stopping` |
| M2 | the `warm` branch deleted entirely | A4's cross product, with `reaps in 300s` appearing for a warm server |
| M3 | attention checked before running in the breaker mapping | A7, `breaker.isRaised → false` where `state == .running` |

Note that **M1 was not caught by the no-countdown assertion alone** — the conjunction bug produces
`dormant`, not a countdown. Both halves of A4 are needed, which is why they are separate tests.

---

## Gates at `589ab2e`

```
make test   → Test run with 714 tests in 101 suites passed
              executed 714 tests          (baseline before this item: 671)
make lint   → clean (SwiftFormat + SwiftLint, 215 files)
make build-mac → ** BUILD SUCCEEDED **
```

## What is not proved here

- **The breaker's 30×48 housing is not readable from the accessibility tree.** `Breaker` sets
  `.accessibilityElement(children: .ignore)`, so the tree reports the row, not the housing. The
  geometry is covered by `BreakerParityTests` against `DESIGN.md` instead, and A33's measured half is
  the row height and the sidebar.
- **The sheets, the inspector and the empty states were not driven in the running app.** They need a
  selection or a click to reach, and a click needs the window in front. Their content is asserted
  against models and copy functions in the suites above; a human pass is the honest next step, and it
  is left for one rather than taken by stealing the screen.
- **`Space`, `⌘N`, `⌘F`, `⌘R`, `⌘⌫` were not exercised through the running app.** M1 measured that a
  menu command reaches its window through `@FocusedValue` and an **inactive app has no focused
  scene**, so `AXPress` on a menu item returns `.success` and does nothing. The mapping is therefore
  proved in `ShellCommandRouterTests`, which is where M1 moved that decision for exactly this reason.
