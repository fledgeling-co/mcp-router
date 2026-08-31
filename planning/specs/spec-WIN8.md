# spec-WIN8 — the Windows Checks board

| | |
|---|---|
| ID | WIN8 |
| Status | **Developer Review** — built on `ai/win8`, gated, not verified. A runner cannot verify its own build |
| Category | windows · new surface · the Maintenance group's board, drawn inside WIN3's shell |
| Depends on | WIN3 ✓ (the shell it is drawn inside) · WIN2 ✓ (DESIGN.md §11–13) · WIN18 ✓ (`scripts/windows/verify.ps1`) · WIN20 ✓ (the automation-plane contract its controls are named for) |
| Blocks | nothing directly; the first Windows read path to the control API is this item's client |
| Brief | `planning/features-to-triage/WIN8-windows-checks-board.md` |
| Source of layout, IA and vocabulary | `design/mcp-router-console.html` (design of record, settled 2026-08-22), `#b-checks` |
| Source of the check vocabulary | `app/Sources/MCPRouterKit/Checks/CheckCopy.swift` — the design of record for the check sentences per DESIGN.md §6's table |
| Source of the visual language | `DESIGN.md` §11 · §12 · §13 |
| Triage | 2026-08-31 |

---

## 1 · What this item is

The Checks board, replacing the placeholder at the shell's Checks destination. It carries the
product's strongest honesty guarantee, stated on the surface itself: **a result belongs to the
version it ran against, and is thrown away when that version moves — a green tick carried forward
is worse than no tick.** Concretely:

- every result this board shows is a **stored run stamped with the capability version it ran
  against**, and the stamp is visible on the row;
- when a capability's version moves, its stored result is **dropped**: the row reads `Stale`, the
  old tally is never re-shown against the new version, and an invalidation notice above the table
  names what was dropped and why;
- `Run all` and `Run the stale suite` are distinct actions, and the second acts only on stale rows;
- a failing check opens — by selecting its row — to the exchange that failed: the observed input
  and the reason, not only a count;
- no surface anywhere shows a model-graded score, and the board states that refusal permanently.

It is also the **first Windows surface with a real read path to the router's control API**: a
loopback HTTP client that reads `GET /servers`, attempts `GET /skills` and calls
`POST /servers/:name/reindex` with the control token when the user runs a server's checks. Where
this machine cannot exercise a live router, the path is real anyway and the gap is recorded as
not-run (§7).

## 2 · The one idea, and how it differs from the Mac

The Mac's board (M7) computes every verdict **live**, from the response the board just fetched,
and uses its history store only for the inspector's history section. Under that model a row can
never read stale: a fresh reading is always at hand, so there is no moment where yesterday's tick
stands against today's code.

This board does not inherit that rendering model, and the difference is the point of the item.
The brief and the design of record both demand the stale row: `Run the stale suite` is one of the
board's two head actions and can only ever act on rows whose stored result no longer matches the
live version — under a compute-live model there would be no such rows, and the action the mock
draws in the head could never do anything. So:

> **The row's `Result` is the stored run's, and it is valid only while its stamp equals the
> capability's live version.** Load reconciles the store against the live versions and never
> derives a verdict from a response alone. `Run` fetches a fresh reading, derives, and records a
> run stamped with the live version.

The cost is stated rather than argued away: a row on this board can be out of date *by design*,
and the board's whole job is to say so (`Stale`, the notice, `Not checked`) instead of quietly
re-deriving a current-looking answer. A re-computed tick that looks identical to a measured one is
exactly the "carried forward" the guarantee forbids.

The derivation itself is client-side, exactly as on the Mac: every check is a pure function of a
field the control API already serves. The brief's assumption — "checks are executed by the router
rather than by the Windows client, so the client shows and triggers rather than runs" — is
settled as **half right**: the *observations* are the router's (it serves every input), the
*derivation* is the client's (as on the Mac), and *triggering* a server re-check is
`POST /servers/:name/reindex`, which genuinely re-performs the handshake.

## 3 · The decisions

### 3.1 The word is Checks, and the refusal is permanent

M9 renamed the surface from Evals to Checks on the Mac; the mock's sidebar, the mock's board
heading and `DestinationCatalog` all read Checks. No Windows string says Evals.

Two sentences are the design of record by DESIGN.md §6's own table and are drawn **verbatim**:

- the subtitle, permanently, in every state including loading and disconnected:
  *"The checks MCP Router runs itself, stamped to the version each was run against. No
  model-graded evaluation exists in this product."*
- the footer, under the detail:
  *"A check is something MCP Router performed and can show you the input to. It is not a graded
  test of whether a capability does its job well. Skills are never executed by the router, so
  nothing here reports how one behaved when an agent used it."*

The verdict vocabulary is the observation set, not the grading set: `confirmed` · `not met` ·
`not observed` · `not applicable` (`CheckCopy.tallyNoun`, design of record). The mock's row
renders "2 failed" and "9 of 11"; this board renders "not met" and the tally segments, because
§6's table is explicit that the grading nouns are the one thing a faithful port must not copy.
`Stale`, `Could not run` and `Not checked` are state words and cross unchanged.

### 3.2 Six checks, not eleven — the skills half waits on an endpoint

The Mac's board checks servers (six) and skills (five). The five skill checks read one input and
only one: `GET /skills`. **The router this product installs is the TypeScript one, and it serves
no `/skills` route** (`isControlPath` recognises `/servers`, `/usage`, `/sessions` and
`/registry/` only — `src/control.ts:423` at `22d7abf6`) — the Mac's own client records that this
endpoint exists only on the Swift router and answers 404 everywhere else
(`app/Sources/MCPRouterKit/Control/ControlAPIClient.swift:241` at `22d7abf6`). A Windows port of
the five checks would be code whose only input can never arrive: a closed set of questions with
no way to gather a single answer.

So this board ships the **six server checks** — every one a pure function of `GET /servers`'s
fields, every one ported with its Mac semantics intact — and implements the skills read path for
real: the client calls `GET /skills`, and the 404 maps to a named absence the board draws as its
partial state (§5) rather than to a silent omission. When a router serves skills, the five checks
port with their Mac copy and nothing here needs redesign. That is the brief's own rule applied
where it bites: *where a datum cannot be served on Windows yet, implement the real read path and
record what is not-run and why.*

### 3.3 Dropped means demoted, not destroyed

"Thrown away" in the guarantee cannot mean erased from the store, for a reason the mock itself
demonstrates: its detail section is headed *trawl · 1.4.2 · the last complete run* — the dropped
run's own per-check reading, still inspectable under a heading that names the version it ran
against. What is dropped is the run's **standing as a result**: it never renders in the `Result`
cell again, and nothing gathered against 1.4.2 is ever presented as a reading of 1.5.0. Concretely:

- the `Result` cell of a stale row reads `Stale`; the `Checks` column says
  *6 checks · last result was for 1.4.2*; `Ran` reads `—`;
- the invalidation notice names the capability, both versions and the why:
  *trawl moved from 1.4.2 to 1.5.0 since it was last checked, so its result was dropped rather
  than shown against the new code*;
- the stale run stays in the store (bounded, capacity 20, the Mac's bound) and renders only in the
  detail's history list, where every row carries its own version — evidence labelled as evidence.

The store is the app's own record of observations the router served, stamped with a version and a
time, over the loopback API and adding no second channel — the same argument the Mac's
`CheckHistoryStore` header makes. It lives beside the shell's data
(`%APPDATA%\MCPRouter\check-history.json`), keeps the Mac's JSON shape, and records nothing for a
subject with no stamp, which is the structural half of "no result without a version".

### 3.4 No durations

The mock's per-check rows carry stopwatch figures (`340 ms`). The Mac's check model has no
duration field, because the six checks are derivations the client performs over data it already
holds, not executions it times. A millisecond figure beside a pure derivation dresses it as suite
execution — the exact vocabulary the board's honesty defence is built to refuse — so the
instrument voice here is spent on counts, stamps and timestamps only. Dropped with the reason;
not an omission.

### 3.5 Emphasis: `Run all` takes the accent, not `Run the stale suite`

The mock marks `Run the stale suite` as the primary action. On Windows only the default button
takes the accent fill (§11 rule 4), and in the board's ordinary state — nothing stale — that
button is disabled. A view's one accent fill, spent on the control that is usually dim, is worse
than the small emphasis divergence from the mock, so **`Run all` is the accent and the default**
(`Return` commits it, per §13), and `Run the stale suite` sits beside it as a standard button that
is enabled exactly when a stale row exists and carries the reason in its accessibility help text
when not.

### 3.6 The empty state is the built product's sentence

The mock's empty state (*"Nothing here ships a check suite"*) describes a suite-file model — a
suite is a file in the capability's own repository — that no built product here implements. The
Mac's built board drew a different empty state, and DESIGN.md §6's table already ruled this shape
of disagreement: where the mock and the build's sentence disagree about a model the product does
not have, the refusal wins. This board draws the Mac's sentence, worded for what this board
checks:

> **Nothing to check yet** — MCP Router checks the servers it can see. Declare a server and its
> checks appear here.

No action button: the action that would fill this state is *declare a server*, and that command
is unbuilt (WIN4). A button that navigated elsewhere would be an offer in place of the feature —
the same refusal `BoardPlaceholder` records.

### 3.7 Disconnected says so, and offers no start button

`ControlAPIError`'s vocabulary ports verbatim (§6: one name per state, taken from one source):
headline *"The router isn't running"*, then the Mac's advice sentence. The Mac pairs it with a
`Start the router` action; the router's Windows lifecycle is unsettled (every such command in the
shell's Router menu is unbuilt, owned by WIN23), so this board offers **Retry** — re-poll now —
and the advice sentence stays true of starting the router by whatever means WIN23 lands.

### 3.8 The doctor question

`CommandCatalog.library.runDoctor` is marked `Unbuilt("WIN8", "Doctor reports onto the Checks
board;")`. This item does not build doctor — the brief does not name it, and nothing in the
control API serves it. The command stays on the menu, disabled. Its owning-item string is left
as the catalogue recorded it: relabelling another item's scheduling decision is the conductor's
reconciliation, not a board's drive-by, and the gap is recorded here (§7) rather than hidden.

`library.runChecks` — *Run all checks* — flips to **Available** and is wired: navigate to Checks,
then run all.

### 3.9 Cross-family review was not available

`codex`, `agy` and `grok` are absent on this machine and the `claude` CLI lane is disabled here.
The triage and plan reviews this pipeline normally routes out-of-family are recorded **not-run**,
never as a pass.

## 4 · What is built

### 4.1 Layout

```
app/windows/
  MCPRouter.Checks.Model/            plain net8.0 — no WinUI, so every claim here is headless-testable
    ControlApiError.cs               the five failure shapes + headline/advice copy, ported from
                                     ControlAPIClient.swift
    ControlClient.cs                 the read/write path: GET /servers, GET /skills,
                                     POST /servers/:name/reindex; bearer token read from the
                                     router's control.token for the write only; never logged
    ServerRecord.cs                  the wire shape describe() serves — the fields the checks read
    Checks/
      CheckVerdict.cs  CheckId.cs  CheckResult.cs  SubjectKey.cs  Stamp.cs  StoredRun.cs
      CheckCopy.cs                   every sentence the board says, one place
      ServerChecks.cs                the six checks + the input each was computed from
      CheckHistoryStore.cs           the bounded, stamped store; load error kept, never fatal
      ChecksBoardModel.cs            the state machine: load, reconcile, run, run-all, run-stale
      RelativeTime.cs                the Ran column's "4 h ago" voice
  MCPRouter.Shell/
    Views/ChecksBoard.xaml(.cs)      the surface (§4.3)
    ShellWindow.xaml.cs              + the checks branch in ShowDestination and Invoke
  MCPRouter.Shell.Model/
    CommandCatalog.cs                library.runChecks → Available
  MCPRouter.Shell.Tests/             the gates (§4.4), + project reference to Checks.Model
```

### 4.2 The client

Loopback only, default port 8879; the first successful `/servers` answer carries `port` and it is
adopted for subsequent calls, so the address is the port the router actually answered on (the
Mac's `LoopbackAddress` rule). Reads need no token — the control API authenticates only
mutations, and its server descriptions carry env *key names* and never values, so nothing
secret crosses this boundary. The single write, reindex, sends `Authorization: Bearer` from the
router's own `control.token`; the token is read into the request header and nothing else — never
logged, never persisted, never echoed (fleet rule 4). Failures map to `ControlApiError`:
connection refused → `RouterNotRunning`; 401 → `Unauthorized`; unparseable body →
`MalformedResponse`; other statuses → `ServerError` carrying the router's message and hint.

### 4.3 The surface

A `UserControl` in the shell's board host, on the content layer, nothing off the Windows ramp:

- **Head** — the board title (Subtitle 20/28), the permanent subtitle (Body 14/20, secondary),
  and the two actions. `Run all` takes the accent and is the default; `Run the stale suite` is
  standard, enabled only while a stale row exists, with its disabled reason discoverable through
  the automation tree.
- **Invalidation notices** — one InfoBar (caution, not closable) per dropped result above the
  table, each naming the capability, the move and the why, each with its own
  *Re-run \<name\>* action. Words beside every colour, always (§12's finding).
- **The table** — columns Capability · Version · Result · Checks · Ran, then the per-row action.
  Version, stamps and timestamps in Consolas (§12's instrument voice); a result is a word or a
  tally, never a bare dot. Row states: `Not checked`, current `n of 6` (with tally segments in
  the Checks column when anything is not confirmed), `Stale`, `Could not run` with the reason.
  Rows select; the per-row `Run` re-checks that one capability.
- **The detail** — for the selected capability: the heading *\<name\> · \<stamp\> · the last
  complete run*; the six per-check rows (statement, verdict word, and for every not-met check the
  **exchange**: the observed input the check was computed from plus the reason — the thing the
  brief refuses to collapse into a count); and the bounded history list, every row labelled with
  the version it was gathered against.
- **The footer** — `evalsFooter`, verbatim.
- **States** — §5's matrix, all nine rows, real copy.

Every interactive control carries `AutomationProperties.AutomationId` and a `Name` that matches
the word on screen — the WIN20 contract: `Checks.RunAll`, `Checks.RunStale`,
`Checks.Invalidation.<subject>`, `Checks.Row.<subject>`, `Checks.Check.<checkId>`,
`Checks.Empty`, `Checks.Disconnected`, and the rest; names are the on-screen vocabulary so the
plane can measure the surface against itself.

### 4.4 The gates

xunit, headless, in `MCPRouter.Shell.Tests` — the only gates this machine can settle:

| Fixture | What it holds |
|---|---|
| `CheckEngineTests` | the six checks against fixture servers, including the Mac's load-bearing cases: zero calls is `not observed`, never confirmed; a failed index suspends `declares tools` to `not observed`; stdio auth is `not applicable`; every verdict travels with its statement |
| `CheckCopyTests` | the tally nouns are the observation set; the subtitle carries the denial unconditionally; the only occurrence of "graded" in any user-facing string is the denial itself; no score, percent or grading verb anywhere |
| `CheckHistoryStoreTests` | capacity bound at 20; no stamp → nothing stored; corrupt file → empty + the load error kept; roundtrip |
| `VersionBoundTests` | **the item**: a run at stamp A renders current; the live stamp moving to B turns the row `Stale`, drops the tally from the row, and raises a notice naming both versions; `Run the stale suite` calls only stale rows; a run at B records and renders; the A run survives in history, labelled |
| `ControlClientTests` | a real loopback `HttpListener` fixture serving `describe()`-shaped JSON: decode; `/skills` 404 → the named absence; refused connection → `RouterNotRunning`; reindex sends the bearer header and maps 401 → `Unauthorized` (the fixture's token lives only in the request assertion) |
| `ChecksBoardModelTests` | with a fake client: load → rows; first-read failure → the disconnected state with the ported headline verbatim; failure after a reading → the reading kept + the error (§5's stale-reading row); the skills-absent partial note |
| `BoardCopySentenceCaseTests` | every new user-facing string sentence case (§11 rule 2) and verb-first where it is a button |

## 5 · The state matrix

DESIGN.md §5's nine rows are the design; real copy, no placeholders:

| State | This board draws |
|---|---|
| Default | the table over the stored, stamped results; notices above for any dropped |
| Empty | *Nothing to check yet* + *MCP Router checks the servers it can see. Declare a server and its checks appear here.* — no action button (§3.6) |
| Loading | skeleton rows at the real row height, first paint to first poll; the subtitle stays visible (§6: permanent while loading) |
| Partial | an informational note: *Skills could not be read — the router answered 404 for /skills, so no skill is checked here. The server checks are unaffected.* The server table draws underneath |
| Error | read failed after a reading: the reading stays, an error band names what happened with the ported headline + advice, `Retry` beside it |
| Success | in place: the row's Result and Ran update to the fresh run; the notice for it clears; no toast |
| Offline | the disconnected state: *The router isn't running* + the advice sentence + `Retry` (§3.7) |
| Disabled | `Run the stale suite` at zero stale rows dims in place with its reason in the automation help text; the per-row `Run` of a subject mid-run dims the row's own button |
| Overflow | long capability names and reasons truncate at the cell with the full value in the detail; rows never change height (§5's overflow row) |

## 6 · What this item does not do

- No skill checks (§3.2), no marketplace/doctor surface (§3.8), no start-the-router (§3.7).
- No across-versions percentage bars: the mock's bars summarize suite-file runs across releases;
  this board's history list carries the same information as version-labelled rows, bounded at 20.
- No Signal Path, no servers editing, no router lifecycle — WIN4's and WIN23's.
- No UI Automation lane run: WIN20's harness drives the probe surface it was built on; enrolling
  this board's tree in that lane is the orchestrator's verification step, run from the interactive
  station this session does not have.

## 7 · Named gaps, each with what it would take to close

1. **No live router was on this machine.** Measured 2026-08-31: nothing listens on 8879, and
   `%USERPROFILE%\.claude\mcp-router\` holds neither `servers.json` nor `control.token`. The read
   and write paths are proven against a real loopback `HttpListener` fixture serving the wire
   shapes (`ControlClientTests`), which is a real HTTP exercise and **not** a run against the
   installed router — the latter is **not-run** here and closes with a machine that runs the
   router.
2. **The reindex write is unproven against a real router** for the same reason, including the
   token round-trip. The fixture proves the header is sent and 401 maps to `Unauthorized`; a live
   proof is owed.
3. **The skills half is unserved** until the router grows `/skills` (§3.2). The read path and the
   partial state are the implemented answer.
4. **The board has not been measured through the automation plane.** Its controls are named for
   that lane (§4.3), but the lane needs the interactive window station; the runner's session does
   not have it. The orchestrator's verify step can run `run-probe-lane.ps1` against this surface.
5. **Nothing here has been photographed on the interactive desktop** — the shell's standing gap
   (spec-WIN3 §7 gap 1). The self-test captures the composed XAML tree, disconnected state, and
   are honest about it.
6. **High Contrast is unmeasured**, as §11 already records for the whole Windows floor. The
   meaning-never-rests-on-colour rule is carried: every state word sits beside its mark.

---

## 8 · Progress — built on `ai/win8`, 2026-08-31

**Status: built and gated; NOT verified, NOT merged.** The conductor verifies from fresh context
and serializes the merge.

### 8.1 What ran, with its real exit codes

| Command | Exit | Notes |
|---|---|---|
| `MSBuild.exe MCPRouter.Shell.csproj -t:Restore` / `-t:Build` | 0 / 0 | two invocations, per the WIN18/WIN20 rule; artifacts on disk (`MCPRouter.Shell.exe`, `MCPRouter.Checks.Model.dll`, `MCPRouter.Shell.pri` under `bin/Debug/.../win-x64/`) |
| `MSBuild.exe -t:Restore` / `-t:Build` on Checks.Model, Shell.Model, Shell.Tests, AutomationProbe | 0 / 0 each | all five `.csproj` in the tree build |
| `dotnet test MCPRouter.Shell.Tests.csproj` | 0 | **242 passed, 0 failed** — 199 pre-existing + 43 new |
| 24 python gates of the lane (exact lane arguments, `PYTHONIOENCODING=utf-8`) | see left | 21 green; 3 at their lane-reserved no-verdict codes, none failed: `registry-drop-gate` exit 2, `foreign-path-gate --quiet` exit 2, `raster-claim-gate` exit 4. `sweep-control-gate` needed ~4 minutes and exits 0 — its earlier timeout was the probe, not the gate |

### 8.2 The acceptance sketch, clause by clause

| # | Clause | Verdict | Evidence |
|---|---|---|---|
| 1 | every result stamped with the version it ran against, visible on the row | **met in code** | `Stamp` is failable — no version, no stored result; the row's Version cell draws the live stamp, the detail heading names the run's stamp. `CheckHistoryStoreTests`, `VersionBoundTests` |
| 2 | version moves → previous result dropped, row reads stale, never re-shown | **met in code** | `VersionBoundTests.WhenTheVersionMovesTheResultIsDroppedAndTheRowReadsStale`, `…TheDroppedRunSurvivesInHistoryLabelledWithItsVersion`, `…AStaleRowShowsNoLiveInputsBesideItsSupersededEvidence` |
| 3 | the invalidation notice names what was dropped and why, offers re-run | **met in code** | `CheckCopy.Invalidated` (name, both stamps, the refusal sentence); one InfoBar per drop, each with `Re-run <name>`. `TheInvalidationNoticeNamesWhatWasDroppedAndWhy` |
| 4 | `Run all` and `Run the stale suite` distinct; the second acts only on stale rows | **met in code** | `TheStaleSuiteActsOnlyOnStaleRows` (two rows, one moves, exactly one reindex call), `RunAllActsOnEveryRow` |
| 5 | a failing check opens to the exchange that failed, not to a count | **met in code** | the detail renders each check's statement, verdict word, reason and the observed input. `SelectingARowExposesTheExchangesThatFailed`, `EveryCheckNamesTheInputItWasComputedFrom` |
| 6 | no surface shows a model-graded score | **met in code** | `TheOnlyGradedWordAnywhereIsTheDenialItself`, `NoStringShowsAScoreOrAPercentage`, `TheVerdictVocabularyIsTheObservationSet` |
| 7 | empty, running, disconnected states draw | **built; drawing unmeasured here** | all three are built surfaces with real copy (§5); the disconnected state is what this machine's board actually loads into. Their captures belong to the self-test lane, which this session cannot run (7.5) |

### 8.3 What could not run here, and why

1. **The live router conversation** — nothing listens on 8879 and no `servers.json`/`control.token`
   exists on this machine (measured 2026-08-31). The read/write path is proven against a real
   loopback `HttpListener` fixture (`ControlClientTests`, 8 cases over real sockets). **not-run
   against the installed router.**
2. **The self-test and any window capture** — attempted from this session with the built exe:
   the process exited before writing `shell-startup.log` and the self-test directory stayed
   empty, matching spec-WIN3 §7's measured Session-0 death. The interactive-task lane
   (`run-shell-selftest.ps1`) is the channel; **not-run here.**
3. **The UI Automation lane** — needs the interactive window station; **not-run.**
4. **Out-of-family review (codex/agy/grok, and the claude lane)** — absent/disabled on this
   machine; recorded **not-run** per §3.9, never as a pass.
5. **The reindex write against a real router** — fixture-proven only (bearer header sent, 401
   mapped); **not-run** live.

### 8.4 Departures and parked items

- §3.4's dropped durations, §3.5's accent placement, §3.6's empty state, §3.2's six checks — all
  decisions, recorded in place.
- `library.runDoctor` stays disabled with its `WIN8` owning-item string unchanged (§3.8); the
  conductor should re-target or schedule it — this item did not build doctor.
- `Button.IsDefault` does not exist in WinUI 3: the board binds no Return default. `Run all`
  remains reachable by pointer, access key and `Library → Run all checks`; §13's Return row is
  unimplemented on this board and noted here rather than silently dropped.
- Row selection uses a `ListBox` (its items publish the selection patterns WIN20 measured); the
  invalidation notice is an `InfoBar` per dropped result, the Fluent control for exactly this
  shape.

