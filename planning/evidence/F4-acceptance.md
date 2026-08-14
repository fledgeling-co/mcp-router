# F4 — acceptance evidence

`ServerStateTracker cannot report failure` · branch `ai/f4` · worktree `.worktrees/F4`
Spec `planning/specs/spec-F4.md` · Plan `planning/plans/plan-F4.md`

Append to this file, never rewrite it. Read it **before** testing anything: if a row exists and
`git diff <that SHA>..HEAD` does not touch the files behind it, that row *is* the evidence.

---

## Screens verified

**None, and this is a deliberate skip rather than a gap.** F4 ships no UI. It changes one type in
`MCPRouterKit` — `TrackerState` — and that type has **zero consumers outside its own tests**,
re-verified after the change:

```
$ grep -rl --include='*.swift' 'TrackerState\|ServerStateTracker' app/Sources app/Tests
app/Sources/MCPRouterKit/Control/ServerStateTracker.swift
app/Tests/MCPRouterKitTests/TrackerStateMatrixTests.swift
app/Tests/MCPRouterKitTests/ServerStateTrackerFailureTests.swift
app/Tests/MCPRouterKitTests/ServerStateTrackerTests.swift
app/Tests/MCPRouterKitTests/ServerStateTrackerPublicationTests.swift
```

No Mac window, menu, pane or iOS screen was launched, driven or relaunched, because none of them
render anything this branch touches. M1 does not consume the tracker at all — it polls the control
client directly as a local workaround — so its surfaces are unaffected. **M2 (Activity) and M3
(Servers board) are the first surfaces to read this type; screen evidence is owed by them, not
here.**

What F4 *can* prove without a surface is that each of `DESIGN.md` §5's nine states is derivable
from a `TrackerState`, and that is asserted rather than asserted-about: `TrackerStateMatrixTests`
parses §5 out of `DESIGN.md`, parses the derivation table out of
`design/mocks/html/f4-tracker-states.html`, and checks the specimens against it in both directions.

---

## Gates

| Gate | Command | Result | At SHA |
|---|---|---|---|
| Full gate | `make all` (tools → lint → build → test → parity) | **pass**, exit 0 | 53706e6 + working tree |
| Tests | `swift test --no-parallel` | **306 tests in 45 suites passed** | ” |
| Parity | fixture vector corpus | **224 vector cases compared (floor 224)** | ” |
| Lint | `swiftformat --lint` + `swiftlint` | **0 violations in 98 files** | ” |
| Mutation | `python3 scripts/red-green.py --only M5x`, foreground, one at a time | **9 of 10 killed**; M55 a recorded survivor | ” |

Lint was **not** green when this branch was resumed: `ServerStateTrackerTests.swift` was 608 lines
against a 400-line limit and had been since the file was written, so no previous run had ever run
`make all` to completion. The suite is now three files — the merge tests plus two extensions —
which is why the file list changed without the test names changing.

---

## Acceptance criteria → exercised tests

Every row is a test that runs, not a build gate. `‹real loop›` means the assertion is made across
the real `pollLoop()`, which is the only way to observe the original `try?` defect — a test that
calls `apply(pollFailure:)` by hand passes against it.

| # | Criterion | Test | Kind |
|---|---|---|---|
| A1 | `.failed(.routerNotRunning)` with no prior success | `‹real loop› a router that is not running is reported, not retried in silence` | exercised, red-green M50 |
| A2 | `.unauthorized` stays distinct | `‹real loop› an unauthorized token stays unauthorized, and is not flattened into “an error”` | exercised |
| A3 | `.stale` keeps its servers | `‹real loop› a failure after a success is stale, and keeps the servers it already had` | exercised, red-green M51 + M52 |
| A4 | `.loaded` in the router's order | `a successful poll is loaded, in the router's order` | exercised |
| A5 | `.loading` ≠ `.loaded([])` | `a tracker that has not polled is loading, not loaded-and-empty` | exercised |
| A6 | no stream → `.notConfigured` | `a tracker built without a stream is not-configured, never a dropped stream` | exercised, red-green M53 |
| A7 | a stream reports a phase, and an event moves it | `a tracker built with a stream reports its phase…` + `‹real stream› an event delivered by the stream reaches the merge` | exercised, red-green M59 |
| A8 | `apply(phase:)` fabricates nothing | `a phase cannot be fabricated for a tracker that has no stream` | exercised, red-green M54 |
| A9 | recovery observable through `updates()` | `‹real loop› a subscriber sees the failure and its recovery, in order` | exercised — asserts the whole sequence, not the final value |
| A10 | every typed error arrives intact, hint included | `‹real loop› a server error keeps its status, message and hint through the poll` + `‹real loop› every typed ControlAPIError case survives the poll as itself` | exercised, all 5 cases, exhaustive `caseName(of:)` switch |
| A11 | subscribers are told about failures | `‹real loop› subscribers are notified of a poll failure, not only of a success` | exercised, red-green M58 + M56 |
| A12 | the nine §5 states are derivable, totally | `every state DESIGN.md §5 requires has a TrackerState mapped to it…` + `each specimen is the TrackerState the F4 sheet says produces that state` | exercised — both documents parsed, specimens bridged to the sheet |
| A13 | the sheet's copy is `ControlAPIError`'s copy | `the F4 sheet's full-pane copy is the copy ControlAPIError returns` | exercised, verbatim |
| A14 | red-green for every guard, `try?` named | ledger in `spec-F4.md`; M50 is the named one | measurement, 9/10 killed |
| A15 | F3's fixtures untouched | `F3's recorded fixtures are untouched by this branch` | exercised — runs `git diff main...HEAD` and fails if git itself could not run |

Standing constraints re-asserted by the existing `StandingConstraintsTests`, unchanged by this
branch: nothing under `src/`, `install.sh` or `package.json` is modified; the MCP SDK stays pinned
to an exact version.

---

## Log

| Date | SHA | What was verified | Result |
|---|---|---|---|
| 2026-08-14 | 53706e6 → working tree | `make all`, 306 tests, parity 224, lint clean; mutants M50–M59 foreground | pass; M55 recorded survivor |
| 2026-08-14 | ” | No screen tested — F4 ships no UI and `TrackerState` has no consumer outside its own tests | deliberate skip |
