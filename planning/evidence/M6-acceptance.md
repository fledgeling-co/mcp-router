# M6 — acceptance evidence

Append-only, per `planning/practices/UI_VERIFICATION.md`. Read this before testing anything: a row
whose commit is untouched by `git diff <SHA>..HEAD` for that screen's files **is** the evidence.

Item: M6 — Inbox and pairing (Mac). Branch `ai/m6`, worktree `.worktrees/M6`.
Out-of-family gates: `codex: usage limit -> claude (downgrade)` (ORCHESTRATOR contract; the codex
account limit runs to 2026-08-20, past this fleet's horizon). Three adversarial in-family reviewers.

---

## Screens verified

| Screen | How verified | Commit | Result |
|---|---|---|---|
| Inbox pane — populated | `scripts/acceptance/m6-inbox-pairing.sh`, scenario `paired`; `axkit select … Inbox`, `axkit dump … window`, sentinel grep, row count from `AXButton` descriptions carrying the provenance clause | `ai/m6` @ acceptance run 2026-08-15 | **pass** — 2 rows, title `Inbox`, no sentinel, header present |
| Inbox pane — empty | scenario `pairedEmpty`; asserts `Nothing waiting` **and** the sentence that explains the queue | same | **pass** |
| Inbox pane — partial | scenario `partial`; asserts `This entry could not be read` and 2 rows | same | **pass** |
| Inbox pane — unpaired | scenario `none` (what a Release build does); asserts `no phone paired` | same | **pass** |
| Pairing — no endpoint | scenario `none`; asserts no countdown string and no host/port/fingerprint anywhere in the tree | same | **pass** |
| Sidebar badge | scenario `paired`; badge read from the row's spoken label and compared to the rendered row count | same | **pass** — `Inbox, 2 waiting from your phone`, equals 2 rows |
| All 8 destinations | one launch, select each, dump, grep for the sentinel | same | **pass** — the placeholder is gone from the product |
| Inbox pane — loading | scenario `loading`; asserts `Reading what is waiting…` **and** that no subtitle claims a queue or a pairing | same | **pass** |
| Inbox pane — failed | scenario `failed`; asserts the condition that actually occurred and that the router is *not* named | same | **pass** |
| Inbox pane — overflow | scenario `overflow`; asserts the over-wide name renders, on one row | same | **pass** |
| Pairing — live countdown | scenario `expiring`; opens the sheet through the accessibility API and reads the countdown | same | **pass** — `expires in 0:09` |
| Sidebar badge — after a decline | scenario `paired`; declines a row through the accessibility API, re-reads badge and rows | same | **pass** — 1 = 1 |
| Row actions | the row's default accessibility action opens review; its named Decline action disposes | same | **pass** |

`20 passed, 0 failed. MCP Router was never frontmost during this run.`

All eight fixture scenarios are launched. Four of them — `loading`, `failed`, `overflow`, `expiring`
— had never been launched before the Phase D critic pointed out that A17 was being claimed on the
half that had.

**Not re-driven, and cited instead:** Servers (`M3-acceptance.md`), Skills (`M4-`), Activity (`M2-`),
Settings and the menu bar (`M8-`), Discover (`M5-`), Evals and Cleanup (`M7-`). The destination sweep
above selects each of those panes but asserts **only** the absence of the placeholder sentence, which
is M6's own claim and could not be made by any earlier item.

---

## The defect the rendered lane caught, which nothing else did

**The window came up 0 × 0 and the accessibility tree reported no window at all.**

Every unit test passed. `make lint` passed. `make build-mac` reported `BUILD SUCCEEDED`. The app
launched, stayed alive, and its `CGWindowList` entry was present and correctly titled `Cleanup`. Only
its bounds were zero.

Diagnosis, measured rather than reasoned:

| Step | Result |
|---|---|
| `axkit title <pid>` on `ai/m6` | `no window` |
| `CGWindowListCopyWindowInfo` on `ai/m6` | one window, `name=Cleanup layer=0 bounds=0×0 at (0,0)` |
| Cleared the stored frame keys and relaunched | still 0 × 0 — not stale restoration state |
| `ProcessInfo.hostName` timed | 40 ms — not a blocking call |
| **Built and launched `main` (85d8331) in the same worktree** | **`bounds=980×620 at (180,140)`** |

So it was M6's, not the environment's. Cause: `inboxBoard` was a `lazy var` on `@Observable
ShellModel`, and `badge(for:)` reaches it — which the sidebar calls for **all eight destinations on
every render**. Initialising lazy storage *mutates* the observable object, from inside a view's body,
which invalidates the view being evaluated.

Fix: `inboxBoard` is stored and built in `init`; `badge(for:)` moved to `ShellModelBadges.swift`,
where a Swift extension cannot hold stored properties and so the compiler refuses that specific
mistake; `PairingSessionModel` resolves the host name when it issues a code rather than at init.
Re-measured after the fix: `bounds=980×620 at (180,140)`, identical to main.

**Worth keeping:** a build success and a full green suite were both true while the app rendered
nothing. The only instrument that could see it was a launch and a window measurement.

---

## Gates, with exit codes captured directly rather than through a pipeline

| Gate | Command | Exit | Result |
|---|---|---|---|
| lint | `make lint` (worktree root) | **0** | 0 violations / 355 files; all four linters ran — `swiftformat`, `swiftlint --strict`, `no-raw-design-values: clean`, `no-wire-codable: clean` |
| test | `swift test` (from `app/`) | **0** | **1143 tests / 145 suites passed** (up from main's 1073) |
| build-mac | `make build-mac` | **0** | `** BUILD SUCCEEDED **` |
| acceptance | `scripts/acceptance/m6-inbox-pairing.sh` | **0** | 20 passed, 0 failed, never frontmost |
| parity | `scripts/acceptance/parity-gate.sh` | **2** | **blocked, not passed.** Every lane but `pool` ran and found no divergence; `pool` needs `npm install` for the MCP client SDK. Recorded as blocked because the gate itself refuses to call a skipped lane a pass. M6's diff touches no file under `app/Sources/RouterCore`, `app/Sources/MCPRouterCLI` or `src/` — measured, `git diff --name-only main` over those paths is empty — so this item cannot move parity in either direction. |

Full-suite repetition: **6 consecutive green runs** on the final tree (4 measured back to back plus 2
earlier), because one run proves nothing about a suite this size.

---

## Red-green proving (`SWIFT_PRACTICES.md` §7)

Each mutation applied, its guard run **by function name** (a display-name filter matches nothing and
reports `0 tests passed`, which is a green that means nothing), then reverted. Every run reports the
number of tests it actually ran, so a filter that matched nothing is distinguishable from a pass.

| # | Mutation | Guard | Result |
|---|---|---|---|
| M1 | `MacPairing.decide` checks live before spent | `spentBeatsLive` | **RED** (1 test) |
| M2 | `randomCanonicalCharacters` draws from a wider alphabet | `generatedCodesExcludeTheAmbiguousLetters` | **RED** (1) |
| M3 | `encode` writes `"type"` instead of `"t"` | `MacPairingWireTests` | **RED** (3) |
| M4 | the Release branch of `ShellPairingFactory` reads the environment | `releaseIgnoresEveryScenario` | **RED** (1) |
| M5 | `InboxEnvelope` accepts an empty `entry` | `missingFieldsAreNamed` | **RED** (1) |
| M6 | the accept path passes `force: true` | `acceptInstallsExactlyOnce` | **RED** (1) |
| M7 | the badge counts the loaded snapshot rather than the rendered rows | `badgeTracksRenderedRows` | **RED** (1) |
| M8 | `installed` drops `.inbox` | `everyDestinationIsInstalled` | **RED** (1) |

**M2's design is the one worth recording.** `issue` ends in a `preconditionFailure`, which is a
process trap Swift Testing cannot catch — a mutation routed through it would crash the run rather
than fail an assertion, which is a gate that cannot report. So the character draw was extracted and
is asserted directly, and the precondition remains as an invariant nothing depends on reaching.

**M7 had to be made capable of failing.** The badge and the row count are trivially equal on a freshly
loaded board, so the assertion is made *after a decline* — the moment the two can diverge.

---

## Declared, not fixed

**`CleanupPresentationTests.weakWindowBoundary` (M7's merged file) failed once, under load.**

Observed immediately after the mutation harness's eight back-to-back builds; did **not** reproduce in
10 isolated runs or 4 full-suite runs afterwards. It is not in this item's diff —
`git diff main -- app/Sources/MCPRouterKit/Cleanup/ …CleanupPresentationTests.swift …/Formatting/`
is empty.

Mechanism, stated rather than shrugged at: the test builds its fixtures with
`ISO8601DateFormatter` at `.withInternetDateTime` — **whole seconds, no fractional part** — from a
`Date()` that has one, then asserts on exact boundaries (`isWeak == false` at exactly 7.0 days,
`days == 41` at exactly 41). Any sub-second shift in the formatted string moves both assertions
across their edge at once, which is precisely the pair that failed. The fix is to build the fixtures
from a whole-second instant, the same correction M6 applied to its own expiry for the same reason.

**Not fixed here** because it is M7's file and outside this item's diff scope, and this repo has
already recorded that mislabelling a defect as a flake was the dangerous half — so it is written down
with its mechanism rather than re-run until green.


---

## After the Phase D critic

The critic returned **AMEND** with ten findings; every one was accepted, and the dispositions are
tabulated in `planning/specs/spec-M6.md` under *Phase D · completeness critic*. Six were defects in
shipped behaviour, two were gates that could not fail, two were criteria the spec had stated wrongly.

Two further defects surfaced from the fixes' own gates rather than from the review:

**The failed pane blamed the router for something the router had not done.** It rendered "The router
isn't running" for *every* read failure, including one whose error is `.unreadable` — this Mac's own
queue storage. The headline is now derived from the error, and the acceptance script asserts the
router is *not* named under `failed`.

**A queued row announced itself as a button, answered `AXPress` with `.success`, and did nothing.**
`.accessibilityElement(children: .combine)` had folded the row's Review and Decline controls into its
label without restoring them as actions. Measured against the running app: the press succeeded and
the state did not move — a control reporting success while doing nothing, for the one user who cannot
see that nothing happened. Fixed with an explicit default action plus named Review and Decline
actions, and the acceptance script's decline step now runs through that path, so it is a standing
assertion rather than a one-off repair.

### Red-green proving, second pass

The three guards added for the critic's findings, each mutated and reverted:

| # | Mutation | Guard | Result |
|---|---|---|---|
| M9 | `undoLastDisposition` restores an accepted row again | `acceptIsReportedAndNotUndoable` | **RED** (1 test) |
| M10 | the loading state renders the subtitle it did not observe | `statesWithoutASnapshotClaimNothing` | **RED** (1) |
| M11 | a missing registry file returns `[]` instead of throwing | `missingRegistryFileIsNamed` | **RED** (1) |

**M11 is the one worth recording.** Its first form survived: `entries(in:)` was `private`, both
bundled resources exist, and so *no test could reach the missing-file branch at all* — the mutation
changed code nothing executed. The guard only became real once the seam was made internal and called
with a name that is deliberately not there. A branch no test can reach is not covered by the tests
that pass around it, and a mutation that "survives" for that reason is reporting missing coverage,
not a weak assertion.

The eight mutations from the first pass (M1–M8) were proven RED on the pre-critic tree; their guards
are unchanged by this pass and all eight still pass in the 1143-test run.

### A note on what the rendered lane keeps catching

Three of this item's real defects — the 0 × 0 window, the router-blaming failure headline, and the
unactionable row — were invisible to `swift build`, `make lint` and a full green suite. Each needed
the app launched and something read back out of it. That is the whole argument for the lane.
