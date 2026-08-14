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

---

## Second pass — at the gap-fix, after three honesty defects were closed

The first pass (above) was recorded at `589ab2e`. This pass exists because
`git diff 589ab2e..HEAD` **does** touch the files behind the Servers-pane rows —
`ServersBoard.swift`, `ServersBoardModel.swift`, `ServerPresentation.swift` — so those rows no
longer carry themselves and the skip rule does not apply. Nothing else was re-driven.

### What changed, and why each was a lie rather than a bug

| # | Defect | What the user saw | Fix |
|---|---|---|---|
| 1 | `rows(from:)` read `state.idleMs ?? 300_000` | a row counting down to a horizon **the router never sent** — 300_000 is precisely `design/mocks/prototype.html`'s hardcoded literal, the one figure `DESIGN.md` §6 names | `idleMs` is `Int?` end to end; an unknown horizon renders `running` with no countdown |
| 2 | `ServersBoardHeader(isCurrent: Bool)` collapsed "nothing has answered yet" into "not current" | `0 tools from 0 servers · last reading, not current` **on every cold start** — fabricated zeros *and* an asserted prior reading that never happened | `Reading` is a three-case enum (`.current` / `.stale` / `.none`); `.none` renders `Reading the router…` and claims nothing |
| 3 | `header(isCurrent:)` in the view took a flag it then ignored | nothing yet — two places deciding one thing, which is how they come to disagree | the view's `header` takes no flag; `board.header(from:)` derives currency from the load state alone |

Defect 1's comment argued the fallback was "unreachable in practice". It was reachable: the tracker
retains `idleMs` only from a poll that answered, and `.stale` keeps servers while `idleMs` may be
absent. "Unreachable in practice" is not a guarantee, and the number it fell back to was the
prototype's.

### Screens verified — one launch per scenario, both terminated

The scenario is an environment variable read at launch, so the two states need two processes. Both
were launched **directly from this worktree's binary** — never `open -g -a`, which the first pass
recorded attaching to another runner's app with the same bundle id — and driven by pid only.

| Screen | How verified | Commit | Result |
|---|---|---|---|
| Servers pane, `loading` — the cold-start header (defect 2) | `MCPROUTER_SCENARIO=loading` direct launch; `axkit select <pid> Servers`; `axkit dump <pid> window` | this commit | **pass** — header reads `Reading the router…`; **no digits anywhere in the subtitle**, and no `last reading` claim. Skeleton present as `Loading servers`; sidebar readout `Loading the router's status` |
| Servers pane, `populated` — regression on the figures that are real | same, `MCPROUTER_SCENARIO=populated` | this commit | **pass** — `2 tools from 4 servers · 1 running`; segments `All 4 / Running 1 / Idle 3 / Needs you 1`; search field present; first row `fixture-stdio` at height `56.0`pt (`MetricToken.serversRow`); sidebar `1 of 4 declared servers running` |
| Scaffold absent | not re-driven — `ScaffoldedDestination` is **failable** and cannot be constructed for a destination in `BoardRegistry.installed`, so board and placeholder are mutually exclusive by construction, and the board's own content rendering above is the same evidence | this commit | pass, by construction |
| The other six destinations | **not tested, deliberately** — `BoardRegistry.installed == [.servers]`; each renders `ScaffoldPane` and there is nothing in them to drive | this commit | skipped |
| Menu bar | **not re-tested** — `ShellMenuReasons.swift` and `ShellCommandRouter.swift` are untouched since `589ab2e`, so that pass's row still carries itself | `589ab2e` | cited, not repeated |

**Invisibility held.** `axkit front` reported `Ghostty` before and after **both** launches, and each
pid was killed at the end of its read. No `open -a`, no `activate`, no `set frontmost to true`, no
`screencapture -R`. Confirmed afterwards that no MCPRouter process of this worktree survived.

### Red–green: both new guards were seen to fail first

`SWIFT_PRACTICES.md` §7. Two mutants, each reinstating the exact defect, each run, each restored.

| Mutant | Reinstates | Caught by | Observed failure |
|---|---|---|---|
| A | `idleMs: state.idleMs ?? 300_000` | `unknownReapHorizonDropsTheCountdown` | 3 issues — `(subtitle → "reaps in 300s") == "running"` |
| B | `case .loading, .failed: .stale` | `headerClaimsNothingBeforeAnyPollAnswers` | 6 issues — subtitle came back as the literal `0 tools from 0 servers · last reading, not current` |

Mutant B is worth noting: it reproduced the shipped defect **string for string**, which is the
strongest evidence available that the guard is pointed at the real thing rather than at its own
wording. The assertion is on **digits**, not on the new sentence — a wording assertion would pass
if a later edit appended a fabricated count to `Reading the router…`, and the fabricated count is
the defect.

## Gates at this commit

```
make test      → Test run with 724 tests in 102 suites passed
                 executed 724 tests   (714 at 589ab2e; +10)
make lint      → clean (SwiftFormat + SwiftLint, 222 files)
make build-mac → ** BUILD SUCCEEDED **
```

`ServersBoardHeader` moved to its own file during this pass: closing defect 2 took
`ServerPresentation.swift` past SwiftLint's 400-line ceiling, and the split is along a real seam —
what remains in that file describes one *row*, the new file describes the *board*. Shaving the
explanations would have bought the same six lines by deleting reasoning.

---

## Third defect, found by sweeping for the class rather than waiting for a report

After fixing two figures the router never sent, the board was swept for **every** value reaching a
user-visible string without having been observed — each `??`, each fallback, each formatter. That
found a third, of the same class and in the same product-critical direction.

`ServerInspectorSections.swift` rendered the Signed-in detail as
`server.auth.authorizedAt.map { "Authorised \(relative($0))." } ?? "Credentials are stored…"`.
`relative()` answers **`Never`** for a string that will not parse as a date. That is the right word
at its three other call sites — `Indexed`, `First seen` and `Last used` all pass an *optional* and
all mean `Never` literally — but here the value is already non-nil, so `Never` could only ever mean
"the router sent a timestamp I could not read". The rendered result was:

> **Signed in**
> Authorised Never.

under a heading asserting the opposite, for a server whose `auth.authorized` is observed `true`.

The fix is `ServerInspector.signedInDetail(_:)`: an unparseable timestamp falls back to the same
sentence an absent one does. The server *is* authorised — that is observed, and it is the branch
this sits inside — and only the *when* is unknown. Identical discipline to the reap horizon: drop
the figure, keep the fact, invent nothing. `static` and taking the raw string, so it is testable
without a view host.

| Mutant | Reinstates | Caught by | Observed failure |
|---|---|---|---|
| C | the original `map`/`relative` call site | `unreadableAuthorisationTimestampDropsTheTime` | 8 issues — `(detail → "Authorised Never.") == "Credentials are stored for this server."`, on all four unreadable inputs, with `nil` still correct |

**Not driven in the running app**, and deliberately so: the inspector needs a selection, a selection
needs a click, and a click needs the window in front. It is proved by the red–green pair above at
the boundary the defect lived on. A human pass over the inspector remains the honest next step and
is left for one rather than taken by stealing the screen.

The same sweep cleared the other fallbacks: `shell.trackerState ?? .loading` (absence of a tracker
state *is* "nothing has loaded"), `envKeys?.count ?? 0` (arithmetic over absent keys, not an
observation), `servers ?? []`, and `lastUsed.map { shortAgo($0) } ?? "Never"` (an optional, where
`Never` is literally true). `ServerPatch` was re-checked against the standing constraint:
`command`, `args` and `env` are absent by construction and guarded by `forbiddenWireKeys` plus
assertions on the **encoded body**.

## Gates at this commit

```
make test      → Test run with 725 tests in 102 suites passed
make lint      → Found 0 violations, 0 serious in 223 files
                 no-raw-design-values: clean · no-wire-codable: clean
make build-mac → ** BUILD SUCCEEDED **
```

---

## The completeness critic rejected the board, and it was right

`codex: usage limit -> claude (downgrade)`. The out-of-family lane is account-limited until
2026-08-20, so Phase D ran as a fresh adversarial `claude -p` opus-5 reviewer, briefed to refute and
told that finding nothing would be a failed review. **It took two attempts** — the first invocation
returned `Execution error` with an empty output file, which is a lane failure and not a pass; the
retry produced a real audit. Recorded because a gate keyed on exit code would have scored the empty
one green.

**VERDICT: reject · ACCEPTED 16 · REJECTED 6.** Three of its six findings were high severity and all
six were confirmed against the source before anything was changed. Nothing was taken on trust.

| # | Finding | Verdict | Action |
|---|---|---|---|
| 1 | The **filter bar** renders `Running N` as current on a stale load, ~30pt below a header deliberately withholding that figure. `counts(from:)` had no currency gate and no test at all | confirmed | fixed |
| 2 | The **empty-in-filter copy** makes present-tense claims from a stale reading — *"right now"*, *"Everything is running"*, and an observed count attached to a present-tense verb | confirmed | fixed |
| 3 | The row's **Reset** and the inspector's **Sign in…** are gated on `isWriting` alone, so both stay live on a stale load beside a Behaviour toggle dimming with `cannotWriteReason` | confirmed | fixed |
| 4 | **A19 is asserted by a test that cannot fail** — nine strings checked only for distinctness, so a treatment naming a place the state is *not* rendered passes | confirmed, and it had already happened | mapping corrected; test limit recorded below |
| 5 | The **removal dialog** reasserts *"leave every session's tool list"*, the exact claim the footer was corrected to drop, for a server that may be scoped | confirmed | fixed |
| 6 | Two sheet controls **dim with no reason given** (§3.4); two more carry theirs as an accessibility hint only, invisible to a sighted user | confirmed | fixed |

### Finding 1 is the one that matters, and it is the fourth of its kind

The board was contradicting itself inside one screen. The header withholds `1 running` on a stale
reading and says why; the segmented control twenty points below printed `Running 1` from the same
data with no gate. The fix puts **both** on one function — `ServersBoardModel.reading(for:)` — so the
two cannot disagree again, and splits the counts the way the header already splits its figures:
`All` and `Needs you` survive (declared configuration, and conditions the router reported), `Running`
and `Idle` are withheld (claims about a live process). A withheld count is **absent**, not zero, so
the segment reads `Running` rather than `Running 0` — a zero would be the defect wearing the fix's
clothes.

### Finding 4 was already true, and the rendered pass proved it

The A19 treatment for `partial` read *"LoadState.stale — StaleReadingBanner; PartialIndexNote when
unindexed"*. Driving the `partial` scenario shows a **loaded** board: the header reads
`2 tools from 4 servers · 1 running`, which only a `.current` reading may say, with the
PartialIndexNote present and no stale banner. So the string named a rendering site that scenario does
not use — precisely the failure the critic said the test could not catch, sitting in the code
already. The mapping is corrected. **The test is still weaker than its subject**, and that is recorded
rather than papered over: it proves the nine treatments are present and distinct, not that each names
a real site. Suggested as a deferred child.

### Red–green: three more mutants, each reinstating the exact defect

| Mutant | Reinstates | Caught by | Observed failure |
|---|---|---|---|
| D | `counts(from:)` without its currency gate | `filterBarAndHeaderAgreeAboutWhatMayBeClaimed` | `(counts[.running] → 1) == nil` on stale, and `→ 0` on loading — both the stale figure and the fabricated zero |
| E | `emptyMessage` ignoring `reading` | `emptyFilterCopyClaimsNothingWhenTheReadingIsStale` | `"No server has a child process up right now"` returned for a stale reading |
| F | the removal dialog's scoped branch removed | `removalDialogDoesNotOverstateAScopedServer` | `"Its 3 tools leave every session's tool list."` for a scoped server |

Mutants A–F all reproduce their defect **string for string**. An earlier attempt at E and F was a
silent no-op — the patch text did not match, so the tests passed unchanged and would have been
recorded as a red–green pass that never went red. Both were redone with an asserted target. Worth
naming: a mutation that fails to apply looks exactly like a guard that works.

## I took the screen once, and it is recorded rather than omitted

`axkit front` read **`MCP Router`** after the second launch of this pass. The app was terminated
immediately and the window was up for a few seconds, but the invisibility invariant was broken and
the rule outranks every other testing instruction here.

**Cause:** launching the built binary directly — the technique the first pass adopted precisely
*because* `open -g -a` attached to another worktree's app — can still let macOS activate a newly
launched GUI process. It is not deterministic: the first pass in this file read `Ghostty` before and
after both launches, and this pass read `Ghostty` after the first launch and `MCP Router` after the
second. A launch that was invisible four times is not an invisible launch.

**Consequence:** no further launches were made. The remaining unverified item is the stale path,
which **cannot** be reached by a scenario in any case — `LoadState.stale` requires a poll to succeed
and a later one to fail, and `MCPROUTER_SCENARIO` sets a single fixture at launch with no `stale`
case. It is covered by mutants D and E at the boundary. Anyone adding a rendered check for the stale
board needs a scenario that changes its answer over time, which does not exist yet; that is a
deferred child, not something to be got at by launching repeatedly and hoping.

| Screen | How verified | Result |
|---|---|---|
| Servers pane, `populated` — regression after four fixes | direct launch, `axkit dump <pid> window` | **pass** — `2 tools from 4 servers · 1 running`; segments `All 4 / Running 1 / Idle 3 / Needs you 1` unchanged, which is correct: a current reading may claim all four |
| Servers pane, `partial` — the index-failure note | same | **pass** — `warn, 2 servers could not be indexed, so their tools are missing from this count. Those rows say why.`; `Needs you 3`; sidebar `2 not indexed`. Also established that `partial` is a **loaded** board, correcting A19 |
| Servers pane, stale — the filter-bar fix in situ | **not driven** — `.stale` is unreachable from a launch-time fixture | covered by mutants D and E |
| Invisibility | `axkit front` each side of each launch | **FAILED once** — `MCP Router` after the second launch. Disclosed above |

## Gates at this commit

```
make test          → Test run with 729 tests in 103 suites passed   (725 before, 714 at 589ab2e)
make lint          → Found 0 violations, 0 serious in 224 files
make build-mac     → ** BUILD SUCCEEDED **
make build-mac-release → ** BUILD SUCCEEDED **
```

`ServersBoardHonestyTests.swift` was split out when the surface test file crossed 400 lines. The seam
is real: those are not assertions about what the board shows but about **what it is allowed to
claim**, which is the rule this whole item turned out to be about.
