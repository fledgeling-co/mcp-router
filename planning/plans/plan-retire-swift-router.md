# Plan — retire the Swift router

- status: draft, for owner review
- decision: owner, 2026-10-19. Retire `app/Sources/RouterCore` and the router verbs of `MCPRouterCLI`. TypeScript is the only router.
- scope: this file only. No code, test or record changes in this item.
- method: read against the sources, with the gates listed in the report. No router was started and no live router was probed, so every "absent" below is a source-level fact.

## Where it stands

The router that runs today is the TypeScript one. Both launchd agents execute `node ~/.local/share/mcp-router/dist/index.js` (`~/Library/LaunchAgents/gg.rhodes.mcp-router.plist` and `gg.rhodes.mcp-router-watch.plist`), so the retirement changes nothing on this machine until something reinstalls.

Something would. `docs/install.sh:39` at `6917ebc4` reads `MCPR_ROUTER="${MCPR_ROUTER:-swift}"`, the default that R4-C1 shipped on 2026-08-20. A reinstall would move both agents onto the Swift binary. Order-of-work item O1 flips that default, and it goes first.

The Mac app, the iOS app and the Windows shell do not link the Swift router. Only `MCPRouterCLI` (11 files) and the `ControlDiff` harness import `RouterCore`, across `app/Sources`, `app/MCPRouter`, `app/MCPRouterIOS` and `app/Tests`. The clients talk to a router over the loopback control API, so deleting the Swift router does not touch their builds.

The cost is in routes. There are eleven Swift-only route families (25 method-and-path pairs) and four Swift-only CLI verbs. `src/control.ts` answers each Swift-only route with a 404, and the divergence rows in `planning/parity/surface.tsv` record the same. Two clients call some of them: the Mac app (Harnesses, Insights and Skills boards, and the extension-update check) and the Windows shell (Harnesses, Insights and Skills models). Against the TypeScript router those calls get a 404, which the Mac client's absent-route handling reads as version skew rather than failure (`app/Sources/MCPRouterKit/Control/LiveControlAPIClient+Absent.swift:7` at `a64e4b9f`, reads `which is version skew rather than`).

## Route inventory

Shared routes are answered by both routers. Swift-only routes are listed with the file that answers them. The method list for the R28, F8 and R27 families comes from their `surface.tsv` rows, which are checked against source by `parity-manifest-check.sh`.

| Route | Method | Swift | TS |
| --- | --- | --- | --- |
| `/servers` | GET, POST | `if path == "/servers", request.method == "GET"`, `ControlHandler.swift:42` at `a64e4b9f`, `:45` | y |
| `/servers/:name` | GET, PATCH, DELETE | `ControlHandler.swift`, `dispatchServer` | y |
| `/servers/:name/reindex` | POST | `case ("/reindex", "POST")`, `ControlHandler.swift:211` at `a64e4b9f` | y |
| `/servers/:name/changes` | GET | `case ("/changes", "GET")`, `ControlHandler.swift:222` at `a64e4b9f` | y |
| `/servers/:name/approve` | POST | `case ("/approve", "POST")`, `ControlAuthDispatch.swift:40` at `a64e4b9f` | y |
| `/servers/:name/auth` | POST, DELETE | `case ("/auth", "POST")`, `ControlAuthDispatch.swift:43` at `a64e4b9f`, `:46` | y |
| `/servers/:name/document` | GET | `case ("/document", "GET")`, `ControlHandler.swift:219` at `a64e4b9f` | y |
| `/usage`, `/usage/summary`, `/usage/stream` | GET | `case ("/usage", "GET")`, `ControlHandler.swift:390-393` at `a64e4b9f` | y |
| `/usage/reset` | POST | `case ("/usage/reset", "POST")`, `ControlHandler.swift:392` at `a64e4b9f` | y |
| `/registry/search` | GET | `if path == "/registry/search", request.method == "GET"`, `ControlHandler.swift:69` at `a64e4b9f` | y |
| `/health`, `/status` | GET | outside the control block, shared (`surface.tsv` mcp rows) | y (`if (url.pathname === '/health')`, `src/router.ts:402` at `a64e4b9f`, `:405`) |
| `/servers/:name/probe` | POST | `case ("/probe", "POST")`, `ControlHandler.swift:216` at `a64e4b9f` | n |
| `/harnesses` | GET | `case ("/harnesses", "GET")`, `ControlHandler.swift:362` at `a64e4b9f`, `ControlHarnesses.swift` | n |
| `/insights` | GET | `case ("/insights", "GET")`, `ControlHandler.swift:363` at `a64e4b9f`, `ControlInsights.swift` | n |
| `/insights/analyse` | POST | `case ("/insights/analyse", "POST")`, `ControlAnalyst.swift:28` at `a64e4b9f` | n |
| `/insights/analyst` | PATCH | `case ("/insights/analyst", "PATCH")`, `ControlAnalyst.swift:29` at `a64e4b9f` | n |
| `/extensions` | GET | `path.hasPrefix("/extensions/")`, `ControlExtensions.swift:23` at `a64e4b9f` | n |
| `/extensions/:kind` | GET, POST | `ControlExtensions.swift` | n |
| `/extensions/:kind/:name` | GET, DELETE | `ControlExtensions.swift` | n |
| `/extensions/updates` | GET | `guard path == "/extensions/updates"`, `ControlUpdates.swift:30` at `a64e4b9f` | n |
| `/invocations`, `/invocations/export` | GET | `path == "/invocations/export"`, `ControlInvocations.swift:43` at `a64e4b9f`, `:56` | n |
| `/caches` | GET | `case ("/caches", "GET")`, `ControlCaches.swift:34` at `a64e4b9f` | n |
| `/caches/invalidate` | POST | `case ("/caches/invalidate", "POST")`, `ControlCaches.swift:36` at `a64e4b9f` | n |
| `/upstreams/health` | GET | `guard path == "/upstreams/health"`, `ControlHealth.swift:32` at `a64e4b9f` | n |
| `/upstreams/auth-expiry` | GET | `case ("/upstreams/auth-expiry", "GET")`, `ControlAuthExpiry.swift:30` at `a64e4b9f` | n |
| `/upstreams/auth-expiry/notify` | POST | `case ("/upstreams/auth-expiry/notify", "POST")`, `ControlAuthExpiry.swift:32` at `a64e4b9f` | n |
| `/diagnostics` | GET | `case ("/diagnostics", "GET")`, `ControlDiagnostics.swift:34` at `a64e4b9f` | n |
| `/diagnostics/bundle` | POST | `case ("/diagnostics/bundle", "POST")`, `ControlDiagnostics.swift:36` at `a64e4b9f` | n |
| `/profiles`, `/profiles/:name`, `/profiles/:name/projection` | GET; GET, POST, DELETE; GET | `path.hasPrefix("/profiles/")`, `ControlProfiles.swift:17` at `a64e4b9f` | n |
| `/sessions`, `/sessions/notify` | GET; POST | Swift does not answer them | y (`if (p === '/sessions' && req.method === 'GET')`, `control.ts:861` at `a64e4b9f`, `:884`), TS only |

CLI verbs. `serve`, `watch`, `import`, `index`/`refresh`, `status`, `tools`, `usage`, `auth` and `help` exist in both routers, and their `surface.tsv` rows are proven. The Swift-only verbs are below.

| Verb | Swift | TS |
| --- | --- | --- |
| `ingest` | `IngestVerb.swift` (92 lines) | n |
| `desktop-entry` | `DesktopEntryVerb.swift` (167) | n |
| `install-entry` | `InstallEntryVerb.swift` (69) | n |
| `harnesses` | `HarnessesVerb.swift` (109) | n |
| `sessions` | none | y (`mcp-router sessions [--push] [--dry-run]`, `src/index.ts:70` at `a64e4b9f`) |

## Feature inventory

Line counts are the Swift lines in each file, with the route file alongside. "Clients" means a call in `app/Sources/MCPRouterKit`, `app/Sources/MCPRouterUI`, `app/windows`, the CLI or a script. `app/MCPRouterIOS` was searched too and calls none of these routes.

| Feature | Swift source | Clients | Recommendation |
| --- | --- | --- | --- |
| F7 session analyst | `RouterCore/Analyst` (10 files, 1,373 lines); `ControlAnalyst.swift` (171) | Mac: `LiveControlAPIClient+Absent.swift` (`runAnalyst`, analyst write), `InsightsAnalystPanel.swift`. Windows: `Shell.Model/Insights/InsightsBoardModel.cs` | **PORT**, L, after P5 |
| M22 harnesses | `ControlHarnesses.swift` (72); CLI `HarnessesVerb.swift` (109) | Mac: `ControlAPIClient.swift`, `HarnessesBoard.swift`. Windows: `Shell.Model/Harnesses/HarnessesBoardModel.cs` | **PORT** the route, M (P4). CLI verb: **DROP** unless wanted (decision 1) |
| M22 insights base | `ControlInsights.swift` (214, shared with F7) | Mac: `InsightsBoardModel.swift`, `InsightsBoard.swift`. Windows: `InsightsBoardModel.cs` | **PORT**, M (P5) |
| R28 extension store | `RouterCore/Extensions` (22 files, 2,830 lines, including the R30 files); `ControlExtensions.swift` (149); `ControlExtensionsJSON.swift` (118) | Mac: `LiveControlAPIClient+Absent.swift` (`skills`, `marketplaces`), `SkillModels.swift`, `SkillsBoardModel.swift`, `SkillSheets.swift`. Windows: `Shell.Model/Control/SkillsControlApi.cs` | **PORT**, L, first (P1). The owner needs it for P2 and P3 |
| F6 marketplace update check | `ExtensionFreshness.swift`, `ExtensionFreshnessReport.swift`, `MarketplaceCatalogue.swift` (321 together); `ControlUpdates.swift` (71); `ControlUpdatesJSON.swift` (108) | Mac: `ServerStateTracker.swift`, `ShellModel.swift` | **PORT**, M, after P1. Owner-requested |
| R30 ingest | 13 files in `RouterCore/Extensions`, 1,742 lines (`IngestPlan`, `IngestManifest`, `ExtensionIngest*`, `ClaudeSettingsEdit*`, `ClaudeExtensionScan*`, and related); CLI `IngestVerb.swift` (92), `IngestReport.swift` (190) | None. CLI verb only, and `scripts/acceptance/r30-ingest.sh` | **PORT** only the undo path P2 needs. **DROP** the rest and the CLI verb |
| R31 caches | `RouterCore/Caches` (6 files, 985 lines); `ControlCaches.swift` (97); `ControlCachesJSON.swift` (122) | None. `scripts/acceptance/r31-caches.sh` only | **DROP** the routes (decision 2 covers the content key) |
| R27 health | `RouterCore/Health` (4 files, 588 lines); `ControlHealth.swift` (65); `ControlHealthJSON.swift` (77); probe at `case ("/probe", "POST")`, `ControlHandler.swift:216` at `a64e4b9f` | None for `/upstreams/health` or `/probe` | **DROP** the routes and the monitor. The monitor starts at `await health.start()`, `RouterService.swift:281` at `a64e4b9f` and probes upstreams on a schedule. Its snapshot is read only at `let rows = await health.snapshot()`, `ControlHealth.swift:40` at `a64e4b9f` |
| R26 auth expiry (+notify) | `RouterCore/AuthExpiry` (4 files, 531 lines); `ControlAuthExpiry.swift` (89); `ControlAuthExpiryJSON.swift` (83) | None | **DROP** (decision 1). The monitor ("holds no task and no timer", `RouterService.swift:74` at `a64e4b9f`) and only its route reads it. If kept, the security note applies |
| R22 diagnostics | `RouterCore/Diagnostics` (4 files, 633 lines); `ControlDiagnostics.swift` (52); `ControlDiagnosticsJSON.swift` (277) | None. Client-side diagnostics in `ControlTokenStore.swift` is not a call | **DROP** (decision 1) |
| F8 profiles | `RouterCore/Profiles` (7 files, 945 lines); `ControlProfiles.swift` (171); `ControlProfilesJSON.swift` (104); disk store at `profiles: DiskProfileStore(root: home.profilesPath`, `RouterServiceDispatch.swift:262` at `a64e4b9f` | None. `scripts/acceptance/f8-profiles.sh` only | **DROP** (decision 1). Profile files already on disk stay where they are; the drop removes the readers |
| F5 invocations | `RouterCore/Invocations` (15 files, 1,808 lines); `ControlInvocations.swift` (92) | None. `deferred rather than absent`, `InsightsBoard.swift:22` at `a64e4b9f` describes a deferred board read (D-f5-a), which is a comment, not a call | **DROP** the routes (decision 1). Reopen if D-f5-a is scheduled |
| R32 Claude Desktop entry | `RouterCore/Desktop` (4 files, 610 lines); `DesktopEntryVerb.swift` (167); `DesktopEntryTests.swift` | None. CLI verb only | **DROP** (decision 1) |
| `install-entry` verb | `InstallEntryVerb.swift` (69) | None outside Swift sources and tests | **DROP** |

The shared core is not inventoried further: Config, Manifest, Pool, Registry, Discovery, Service, Usage, Watch, Log, IO, JSON, HTTP, Auth, AuthServer and Seams. TypeScript has counterparts in `src/`, and the pool, install, state, log and authserver rows of `surface.tsv` prove them. They leave with the Swift router in G2 and need no port.

## Security note for ports

`GET /upstreams/auth-expiry` answers without the control token. `ControlHandler.swift` returns before its token and content-type gate for every non-mutating request, and it says so: "GET is deliberately ungated, matching the reference". Any port of this route must check the token first, as `x-mcpr-token` or `Authorization: Bearer` (`ControlToken.isAuthorized`, and `function tokenOk(req: IncomingMessage, expected: string)`, `src/control.ts:74` at `a64e4b9f`). If R26 is dropped, nothing is exposed and the note is moot.

The same holds for every Swift-only GET: `/extensions`, `/insights`, `/invocations`, `/diagnostics`, `/profiles`, `/caches` and `/upstreams/health`. Some return session or log content: `/insights` analyses transcripts, and `/diagnostics` carries a log tail (`DiagnosticsBundle.logTail(path: deps.config.logPath`, `ControlDiagnosticsJSON.swift:18` at `a64e4b9f`). Each new port should gate its GETs too. Before it does, confirm that each client sends the token on GET, because a gate a client cannot satisfy changes that client's wire.

The TypeScript router already answers its GETs without the token. `const mutating = req.method === 'POST' || req.method === 'DELETE' || req.method === 'PATCH'`, `src/control.ts:465` at `a64e4b9f` applies the token and content-type checks only to POST, DELETE and PATCH, so `/usage`, `/servers`, `/servers/:name/document` and `/registry/search` are open today. This plan does not change them (decision 3).

## De-gating parity

Parity stops gating releases. Each entry below says what the gate does now and what it should do.

| Gate | Where | What it does now | Recommendation | Reason |
| --- | --- | --- | --- | --- |
| `parity`, `parity-selftest` in `all` | `Makefile:287` | Blocks a release on the Swift VectorRegistry corpus and on the harness selftests | **REMOVE** from `all` (G1). Keep the targets until G2 and G3 | Parity no longer gates releases |
| `make parity` | `Makefile:615-633` | Runs `VectorRegistryTests`; requires the `PARITY-VECTORS-EXECUTED` marker and a count at or above `executedFloor` | **REMOVE** with RouterCore (G2) | It compares Swift with vectors generated from TypeScript. Once Swift is gone there is nothing to compare |
| `make parity-regen` | `Makefile:638`, not in `all` | Regenerates vectors from the TypeScript reference and diffs the committed ones | **KEEP**, outside `all` | Still a useful TypeScript golden check. It needs a built `dist/` |
| `parity-lane-selftest`, `parity-watch-mutations` | `Makefile:743`, `:766` | Self-tests for the dual-router harness | **REMOVE** with the harness (G3) | They test a comparison that no longer has two sides |
| `parity-gate.sh` | (`PARITY_CUTOVER_TARGET=82`, `scripts/acceptance/parity-gate.sh:381` at `a64e4b9f`, decided 2026-08-16) | Compares both routers over `surface.tsv`. Exits 1 while any row is blocked | **Informational** now (G1). **REMOVE** with the harness (G3) | The cutover target is superseded. Exit 1 on a blocked row would keep it red |
| `parity-manifest-check.sh`, `SURFACE_ROW_FLOOR` | `scripts/acceptance/`; `surface.tsv` header | Fails when `surface.tsv` and source disagree. Ratchets the row count | **KEEP** until G3. Lowering the floor is an owner-approved change in the same commit (decision 4) | The file's own header says a removed blocked row must lower the floor. Lowering it to make a gate pass is the thing this plan refuses |
| `carrier-parity-gate.py` | `Makefile:1100`, in `lint`; waivers at `planning/carrier-parity-gate.py`, `planning/sweep-controls.json:52` at `a64e4b9f` and `:766` | Requires a disposition for each one-sided landing since the pin | **KEEP** as the port backlog. Non-blocking in `lint` until P1 to P6 land. **REMOVE** in G4 | Blocking would keep `make lint` red for the whole port period. Its output is the list of Swift-only landings still waiting for a port or a drop. Its docstring still frames TypeScript as a reference to be retired, so its text needs updating with its behaviour |
| `green-streak.sh` (R33) | `Makefile:1145`; `planning/parity/green-streak.md` | Measures a whole-gate streak. Exits 2 with nothing recorded | **REMOVE** the cutover meaning. Delete the target with the harness (G3) | The streak was a precondition for deleting `src/*.ts`, and that deletion is cancelled |
| `install-default` in `all` | `Makefile:704`; `scripts/acceptance/install-router-default.sh` | Asserts the installer default is Swift | **INVERT** in O1, in the same change that flips `MCPR_ROUTER="${MCPR_ROUTER:-swift}"`, `docs/install.sh:39` at `6917ebc4` | The lane still protects a release-relevant fact; only the expected value changes. Flipping the default alone would fail it |
| `mutation-selftest`; `app/Scripts/pool-mutation-gate-selftest.sh` in `lint` | Tests the Swift pool (`UpstreamPool.swift` and siblings) | Not a parity gate. It tests Swift code | **KEEP** until G2, then **REMOVE** | It goes with RouterCore |
| `surface-reconcile` in `all` | `planning/test-campaign/bin/surface-reconcile.py` | Reconciles the campaign's product destinations | **KEEP** | Not a parity gate. The script contains no reference to `parity`. Its `surface` is the campaign's, not `surface.tsv` |
| Goal M30 | "serve real capability documents from both routers", `planning/goals/goal-ship-remaining-work.md:29` at `a64e4b9f`, with parity vectors. To Do, owner authorised | **RE-SCOPE** to TypeScript, or close (O2) | A second router to serve from no longer exists |
| Windows parity fleet | `planning/goals/ledger-windows-parity-fleet.jsonl`, `w2-dispatch.js`, `w4-dispatch.js` | "Parity" means the Windows shell against the Mac app | **NOT AFFECTED** | A different meaning of the same word |

## Records

Nothing below is edited in this item. Each entry gives the current state and the wording O2 should write.

- **REQ-020** (`planning/test-campaign/requirements.in.json`, class `deferred`). Current text: "install.sh flips to the Swift binary and retires src/*.ts once parity is 82 of 83 and the owner decides." The owner has decided, and the decision is the reverse. Proposed text: "Superseded 2026-10-19. The owner retired the Swift router. install.sh defaults to node and src/*.ts stays. See planning/plans/plan-retire-swift-router.md." Set the class from the requirements vocabulary, since `deferred` no longer describes it.
- **R4-C1** (`2026-08-20, which is`, `planning/specs/spec-R4.md:257-283` at `a64e4b9f`). Shipped 2026-08-20 and kept as history. Add one line: "Superseded 2026-10-19: the default is restored to node in O1." Do not rewrite the shipped entry.
- **R4-C2** (same spec, "Held"). Proposed: "Cancelled 2026-10-19. The Swift router is retired instead, so `src/*.ts`, `package.json`, `package-lock.json`, `tsconfig.json` and `dist/` are not deleted." Its hold condition, a DEF-033 reproduction or a stated bound, is moot.
- **R33** (`planning/features-to-triage/R33-four-features-shipped-to-the-router-that-does-not-run.md`, and the docstring of `carrier-parity-gate.py`). Proposed: "Dispositioned 2026-10-19 in plan-retire-swift-router.md. The one-sided landings are the port list: R28 and the R30 undo path port (P1, P2), R31 and R32 are dropped, and R29 stays TypeScript-only. The gate stays non-blocking until P1 to P6 land." The docstring's sentence that REQ-020 "reserves that retirement to the owner" becomes "The owner retired the Swift router on 2026-10-19."
- **`planning/parity/cutover-readiness.md`** and **`README.md`**: a superseded header above the existing body, which stays as history.

## Order of work

Sizes. **S**: one route, or one gate or config change, under about 300 new TypeScript lines. **M**: one route family, up to about 1,000 Swift lines to port. **L**: more than 1,000 Swift lines, or an on-disk format that TypeScript must read or write.

Every port item follows the same proof. The TypeScript route tests are written first and watched failing before the change. `npx tsc -p tsconfig.json --noEmit` and `npm test` pass. One live check runs against a running TypeScript router. Each item merges on its own.

1. **O1. Flip the installer default to node (S).** Change `MCPR_ROUTER="${MCPR_ROUTER:-swift}"`, `docs/install.sh:39` at `6917ebc4` to `node`. Invert the default assertions in `scripts/acceptance/install-router-default.sh`. Update the README install copy where it names the Swift default. Depends on nothing. Lands first, because a reinstall would otherwise move both launchd agents to Swift. Proof: the inverted lane fails against the current installer, then passes after the flip.
2. **O2. Record the decision (S).** Apply the records above and re-scope goal M30. Depends on owner approval of this plan.
3. **G1. Take parity off the release gates (S).** Remove `parity` and `parity-selftest` from `all`. Make `parity-gate.sh` informational. Make the carrier gate non-blocking in `lint`. Depends on O1.
4. **P1. TypeScript extension store, the R28 collections (L).** Serve `GET /extensions`, `GET` and `POST /extensions/:kind`, and `GET` and `DELETE /extensions/:kind/:name`. A colliding add answers 409, and an unknown item answers 404 in the same words. The new GETs require the token. Serves the Mac Skills board and the Windows `SkillsControlApi`. First step: find the Swift store's on-disk path and format under `RouterCore/Extensions`, and check whether any such file exists on this machine before choosing a format. Depends on nothing.
5. **P2. Promote-with-undo for held skill updates (M).** The owner has asked for it. Port the undo path (`ExtensionIngestUndo.swift`, and the parts of `IngestPlan` it uses) onto P1's store. Depends on P1.
6. **P3. Marketplace update check, `GET /extensions/updates` (M).** The owner has asked for it. Port `ExtensionFreshness`, `ExtensionFreshnessReport`, `MarketplaceCatalogue` and `ControlUpdates`. Serves the Mac `ServerStateTracker` and `ShellModel`. Depends on P1.
7. **P4. `GET /harnesses` (M).** Port `ControlHarnesses.swift`. First step: confirm which harness data TypeScript already reads. Serves the Mac Harnesses board and the Windows `HarnessesBoardModel`. Depends on nothing.
8. **P5. `GET /insights`, base envelope (M).** Port the base of `ControlInsights.swift`, with the analyst member null until P6. Serves the Mac and Windows Insights boards. Depends on P4, since they share a board.
9. **P6. F7 analyst: `POST /insights/analyse`, `PATCH /insights/analyst` (L).** Port `RouterCore/Analyst` (1,373 lines) and `ControlAnalyst.swift` (171). The analyst reads Claude's session stores, so its first step is to confirm which of those stores the TypeScript side can already read. Depends on P5.
10. **D1. The owner confirms the drop list (no code).** Decision 1. Depends on the owner.
11. **G2. Delete the Swift router (M).** Remove `RouterCore`, the `MCPRouterCLI` router verbs and target, `ControlDiff`, `RouterCoreTests`, their `Package.swift` entries, `make parity`, and the pool mutation selftest. Depends on P1 to P6 merged or dropped, D1 and G1. Proof: `cd app && swift build --build-system native` and `make test` pass, and the Mac and iOS builds still compile, since neither imports `RouterCore`.
12. **G3. Delete the parity harness and its census (S).** Remove `scripts/acceptance/parity-*.sh`, `planning/parity/surface.tsv`, the cutover target and the green-streak target. In the same commit, and only with owner approval, lower `SURFACE_ROW_FLOOR` (decision 4). Depends on G2.
13. **G4. Retire the carrier gate (S).** Remove `carrier-parity-gate.py` from `lint`, delete its two waivers and `planning/parity/carriers.tsv`. Depends on P1 to P6 and G2.

O1 and O2 can run at once, and so can P1 and P4. P2 and P3 wait for P1. P6 waits for P5. Each port's TypeScript acceptance evidence replaces the `surface.tsv` divergence row it closes, so that row's proof moves to TypeScript rather than disappearing.

Not established here: the on-disk format of the Swift extension store (P1), which harness data TypeScript reads (P4), which of Claude's session stores TypeScript reads (P6), and whether any Swift-written state exists on this machine. Each is the first step of the item that needs it.

## Open decisions for the owner

1. **The drop list.** Drop the routes for R22, R26, R27 (with its monitor), R31, F5, F8 and R32, and the `install-entry` verb. Drop the `ingest` and `harnesses` CLI verbs unless P2 or P4 needs them. Lean: drop all of it. No client, script or record outside its own acceptance lane calls these. What is yours to weigh: R26's `notify` and F5's deferred Insights board (D-f5-a) may be capabilities you want. I found no record that you asked for either.
2. **R31's content identity.** `RouterCore/Caches/ContentIdentity.swift` puts a content component into the tool-index key, and the TypeScript key lacks it (`The cache is keyed on each server's command/args/env identity`, `src/manifest.ts:120` at `a64e4b9f` keys on command, args and env). Lean: drop the routes and keep the TypeScript key. The cost is that an upstream whose file changed under an unchanged command keeps its cached tools until a reindex. That is a risk call, and it is yours.
3. **Token on existing TypeScript GETs.** `/usage`, `/servers`, `/servers/:name/document` and `/registry/search` answer without the token. Lean: gate the GETs of the new ports now and leave these for a separate item, because gating them changes the wire for existing clients. Your call.
4. **The ratchets.** `SURFACE_ROW_FLOOR` and `PARITY_CUTOVER_TARGET=82`. Lean: keep both until G3, then lower the floor in the same commit that removes the rows it counts. Lowering it while the rows still exist would make a gate pass by shrinking its denominator. The commit needs your approval.
5. **The carrier gate non-blocking.** Lean: non-blocking in `lint` until P1 to P6 land. It weakens a gate, so it is yours to approve.

## Not affected

- The Mac app, the iOS app and the Windows shell do not import `RouterCore` and keep the loopback control API.
- `/sessions` and `/sessions/notify`, and R29's session notification, are TypeScript only. The Windows inbox depends on the first two.
- The shared core (Config, Manifest, Pool, Registry, Discovery, Service, Usage, Watch, Log, IO, JSON, HTTP, Auth, AuthServer, Seams). TypeScript already has counterparts, and their rows are proven.
- The Windows parity fleet, whose "parity" means the Windows shell against the Mac app.
