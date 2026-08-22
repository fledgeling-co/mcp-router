# LEDGER — MCP Router feature pipeline

Allocation is a read-modify-write on this file: **one triage at a time**, and any runner
creating a child spec takes the ledger lock first.

**This file is not the only allocator, and a scan of its table is not a free-id check.**
It said "ids are allocated here and nowhere else" until 2026-08-21, and that sentence
produced two near-misses from two sessions inside one hour — one session reached for I6
while it was merged at `ef4f615`, another for X7/X8 against a table that records neither
X4 nor X5. `ORCHESTRATOR.md` carries live rows this table has never held (P5, P6, R2-R,
R2-W, R4-C, and the M9-M12 deferred children), and merged branches exist for ids recorded
in neither file (`ai/x4`, `ai/x5`). Before allocating, scan **both files plus
`git branch --merged main --list 'ai/*'`**, and expand any range notation first — see the
allocation notes below for why a range is the one place a reconciliation reports agreement
it never tested.

| ID | Title | Brief | Spec | Plan | Status |
|---|---|---|---|---|---|
| F1 | Swift workspace, shared kit, three targets | `F1-swift-workspace.md` | `spec-F1.md` | `plan-F1.md` | **Merged** `0924040` |
| F2 | The design system in SwiftUI | `F2-design-system.md` | `spec-F2.md` | `plan-F2.md` | **Merged** `22d1802` |
| F3 | Typed control-API client and models | `F3-control-client.md` | `spec-F3.md` | `plan-F3.md` | **Merged** `13825c9` |
| F4 | ServerStateTracker cannot report failure | `F4-tracker-failure-states.md` | — | — | **Merged** `aba30bd` |
| R1 | Swift router: core, config, manifest | `R1-router-core.md` | `spec-R1.md` | `plan-R1.md` | **Merged** `c30eac9` |
| R2 | Swift router: lazy pool, relay, passthrough | `R2-router-pool-relay.md` | — | — | **Merged** `a8091bb` |
| R3 | Swift router: control, usage, registry | `R3-router-control-registry.md` | — | — | **Merged** `e154bae` |
| R5 | Swift router: OAuth and the auth routes | `R5-router-auth.md` | — | — | **Merged** `b7c527c` |
| R4 | Differential parity harness and cutover | `R4-router-parity-cutover.md` | — | — | **Merged (harness only)** `e129779` |
| R4-C1 | The installer points at Swift; the TypeScript tree stays | `R4-C1-installer-points-at-swift.md` | — | — | **Done** (ai/r4c) |
| R4-C2 | Retire `src/*.ts` — held, and what it waits on | `R4-C1-installer-points-at-swift.md` | — | — | Held (owner: not on a green streak) |
| M1 | Mac window shell, menu bar, keyboard | `M1-mac-shell.md` | — | — | **Merged** `10cad44` |
| M2 | Activity: the live call log | `M2-activity.md` | — | — | **Merged** `c39c891` |
| M3 | Servers: the breaker board | `M3-servers-board.md` | — | — | Done (`589ab2e`, `3b11f33`, `af77200` on main) |
| M4 | Skills and marketplaces | `M4-skills.md` | — | — | **Merged** `7a28de8` |
| M5 | Discover: the registry | `M5-discover.md` | — | — | **Merged** `2a81c87` |
| M6 | Inbox and phone pairing (Mac side) | `M6-inbox-pairing.md` | — | — | **Merged** `6b3e940` |
| M7 | Evals and Cleanup | `M7-evals-cleanup.md` | — | — | **Merged** `85d8331` |
| M8 | Settings, menu-bar popover, quarantine | `M8-settings-quarantine.md` | — | — | **Merged** `affaed6` |
| I1 | iPhone: shell and pairing | `I1-ios-shell-pairing.md` | — | — | **Merged** `d582d43` |
| I2 | iPhone: Discover and detail | `I2-ios-discover.md` | — | — | **Merged** `ba139d4` |
| I3 | iPhone: Triage, Queue, Library, Settings | `I3-ios-triage.md` | — | — | **Merged** `b50aa8d` |
| P1 | Make the two auth routes reachable | `P1-auth-routes-reachable.md` | — | — | **Merged** `496f88c` |
| P2 | The `import` verb and the config rewrite | `P2-import-verb.md` | — | — | **Merged** `95d16f9` |
| P3 | Oracles for the usage stream and registry search | `P3-stream-and-registry-oracles.md` | — | — | **Merged** `f466020` |
| P4 | Derive the manifest rows; fix the directory-dependent normaliser | `P4-derive-manifest-rows.md` | — | — | **Merged** `8686fd6` |
| M13 | The scroll-edge separator, A34 | `M13-scroll-edge.md` | — | — | **Merged** `08b9bdf` |
| G1 | Stop the checks blaming the app for being out of date | `G1-gate-hygiene.md` | — | — | **Merged** `8cfb9e3` |
| V1 | Re-run the out-of-family review on the router items (grok) | `V1-outside-review-router.md` | — | — | **Merged** `29af3eb` |
| I4 | Let the phone install directly | `I4-phone-direct-install.md` | — | — | **Retired** — replaced by I5 (`4157bc4`) and I6 (`ef4f615`) |
| D1 | Deferred register: router side (12 children) | `D1-deferred-router.md` | — | — | **Merged** `997f7af` |
| D2 | Deferred register: Mac surfaces and design authority (14) | `D2-deferred-mac.md` | — | — | **Merged** `9e8a754` |
| D3 | Deferred register: phone copy and the harness limit (4) | `D3-deferred-phone-harness.md` | — | — | **Merged** `67ae4f5` |
| — | **BLOCKED: the Apple developer identity** | `BLOCKED-apple-identity.md` | — | — | **Needs input — `as-found`, not confirmed** |
| M14 | A shipped menu tells the user the app is not built | `M14-menu-says-not-built.md` | — | — | **Merged** `7e7ed70` |
| R6 | Children inherit launchd's minimal PATH | `R6-child-process-path.md` | `spec-R6.md` | `plan-R6.md` | **Done** — merged to `main` at `1d958b4` (`ai/r6` `7a4f15a`; rung `effect-witness`; 9 follow-ups `D-r6-d`…`D-r6-k`) — both routers append the user's own `bin` directories to a child's PATH; `r6-child-path.sh` examined=6 failures=0; parity census untouched at 83 rows, cli 17/17, pool 5/5 |
| R8 | An upstream that refuses our credentials must say so | `R8-auth-rejection-visible.md` | — | — | **Done** (ai/r8 → main; owner unfroze `src/`, A38 rewritten to guard the reference's existence; Swift half unblocked by R9; parity 82/83 control 16/16 0 diverged; auth gate examined=8 failures=0) |
| R7 | The router's thesis is unmet for every harness but Claude Code | `R7-harness-reconciliation.md` | `spec-R7.md` | `plan-R7.md` | **Merged** — **Verified — Done** (`effect-witness`, 2026-08-21). B1 closed and cross-checked against `agy mcp list`'s own twenty rows; both real Gemini configs byte-identical on six attributes across the run. All five write-gate walk-throughs now exit 1, re-planted independently. B3 and B4 closed in both directions with a seven-shape sweep finding no remaining silent zero. The stripper was checked by construction and three string-literal shapes still miss — latent, since the whole tree opens exactly one block comment and it is genuine. `make lint`'s three-pass block is a false dependency. Awaiting merge; follow-ups `D-r7-z`…`D-r7-ai` — prior-pass detail: **Ready to verify** — gap-fix 2 complete (`ai/r7` `d285298`). B1 closed against the real machine: the run reads `~/.gemini/config/mcp_config.json` and its 19 entries plus the router match `agy mcp list`'s twenty rows. The panel again caught two defects in the fix — a key rewrite that made stdio entries read as HTTP, and byte-for-byte endpoint comparison turning `/mcp` vs `/mcp/` into B4's silent loss. **The write gate's own comment stripper was blanking every line to EOF** on a Swift string containing a slash-star, so an applier under one reported clean. Selftest 22→27 cases, lane 55→59 checks. Two findings overruled on measurement. grok down as a lane at 16.5 KB, substituted with fable. Follow-up `D-r7-y` |
| R7-C1 | The Harnesses board and the `GET /harnesses` route behind it | — | — | — | Deferred — **absorbed by M22** at its 2026-08-22 triage. The two rows named each other as blockers and neither could be scheduled; A36 forbids the board reading a harness config itself, so the route is not optional and the work is one piece |
| R7-C2 | Apply a reconciliation plan to a harness config, behind a human | — | — | — | Deferred (child of R7; the write R7 refuses) |
| R7-C3 | opencode's transport is unestablished | — | — | — | Deferred (child of R7) |
| R7-C4 | Project-scoped harness entries | — | — | — | Deferred (child of R7) |
| R11 | Skills write endpoint (remove/disable) with preconditions and undo | — | — | — | Registered (ORCHESTRATOR.md deferred register; filed as R7, renumbered 2026-08-21) |
| R12 | Server soft-delete with a restore endpoint | — | — | — | Registered (ORCHESTRATOR.md deferred register; filed as R8, renumbered 2026-08-21) |
| R13 | Router-side behavioural eval runner — servers only | — | — | — | Registered (ORCHESTRATOR.md deferred register; filed as R6, renumbered 2026-08-21) |
| G2 | The ledger table holds two row shapes, and every reader silently drops one | `G2-orchestrator-table-is-heterogeneous.md` | — | — | Ready for AI — deferred from 2026-08-21 while agents were mid-read |
| G3 | `make test` is not deterministically green | `G3-make-test-is-not-deterministic.md` | — | — | **Merged** `4e18cc0` — **Verified — Done** (`metamorphic`, 2026-08-21), awaiting merge. All three shapes flip, confirmed by building the scanner standalone at both the pre-fix and delivered commits; exactly 5 call sites, all bounded, over 508 files. The directional count is wrong about which scanner it measured — nine shapes at 6/3 against the delivered artifact, not twelve at 8/4 — and the population is a convenience sample the verifier doubled in one session, though the conclusion it supports is unaffected. Nine new shapes, none blocking, because the artifact declared its bound honestly. **The title cannot be met by this item**: the one red in five runs was a port collision, not a sleep, so the residue is three mechanisms and wants its own item — prior-pass detail: **Ready to verify — gap-fix 3 complete** (`ai/g3` `94ddd73`, 4 commits on `e8c20e0`). The property is unchanged and every gate held. This pass fixed the layer the rebuild deliberately did not replace — Swift's statement and trailing-closure grammar — where a verifier measured **two misses and one false fire**, each pinned by a one-token control: a statement label made a control-flow body read as the wrapper's trailing closure; a labelled string-literal final argument produced no call site at all, because a literal blanked to whitespace is the shape of an unapplied method reference; and `Task` inside a string interpolation reddened a correct wrap. **The previous pass's directional claim is corrected where it was made** — "fails toward a red on correct source rather than toward a miss" was true of the three unreachable shapes it named and false as a statement about the layer. Measured: 2 misses to 1 false fire in the blocking shapes, and 6 misses to 3 reds across the nine further shapes the lanes found and this pass did not take (`D-g3-ah`). Stated as a count: of the twelve shapes measured against the delivered scanner, eight fail toward a miss and four toward a red, so the layer fails both ways and the direction is not predictable from it. **The completeness claim is bounded rather than closed** (`D-g3-ae`): Family A is 19 controls on a citable production list, Family B is 12 on brace nesting, and **Family C is 38 with an open population** — the count is now given family by family and the mutation matrix stated separately. 69 controls, each red under at least one of twelve mutations. **`D-g3-q`'s derivation withdrawn**: it does not reproduce, and the verifier got both sites red 4 of 4 under heavier load; deferred on scope alone. **Five duplicated register ids removed** (`D-g3-ad`), and `ledger-reconcile.py` — taken from `main` for **check K** — exits 0 at 172 register rows. Gates: `make test` **0** and **0** (7.126 s, 12.513 s at 1587 tests in 199 suites), `make lint` **0** at 0 violations in 500 files, `make parity` **0** at 358/358, `make acceptance-r6` **0** at `examined=6 failures=0`, the assigned mutation red at **exit 2** naming its own condition at `PoolReapingTests.swift:98:29` in 13.189 s. Two further `make test` runs went red in files this item does not touch — `CallbackLifecycleTests.swift:238` and `ControlStreamTests.swift:72`, `D-g3-c`'s class, recorded under `D-g3-s` as its fourth and fifth instances; **`make test` is still not deterministically green on this machine, which is this item's own title**, and what G3 fixed is the pool suite, the residue being `D-g3-c`'s ~60 unclassified sleeps elsewhere. The scan finds exactly 5 call sites, all bounded, over 499 files. Load average 421 and 0.0% idle throughout, so the timings are not representative. Two out-of-family lanes asked to break it found eight more, two of them regressions this pass had introduced; five taken, the rest registered with their direction. New follow-ups `D-g3-aa`…`D-g3-ah`. Prior: The property is unchanged and established: **a regression in this class produces a named red inside the CI bound, not a timeout** — the assigned mutation reds at exit 2 after 11.280 s naming its own condition. This pass fixed the guard, not the property. The scanner was **rebuilt rather than patched**: all seven defects the panel and the verifier found are instances of two approximations of Swift's grammar — comments recognised by a line's first three characters, and block structure read from indentation. A delexer implementing the real comment and literal grammar and a brace-balance walk replace both, and three named residues close with them. Held by **53 controls** asserting both directions, every one seen to fail: **34 single-mechanism mutations, 34 of 34 red, all 53 controls covered**. **Three out-of-family rounds asked to break it rather than review it and found twelve more defects, all fixed here** (`D-g3-y`) — including a raw literal read as a multi-line opener that was silently blanking a real file, and a CRLF desync that kept the readability guard green. `D-g3-l`/`m`/`n`/`o`/`p`/`r`/`v` closed; `D-g3-q` re-measured wider and deferred with a probe-tested reason (`awaitSessionEnded` takes its early return at 3 of 3 call sites, so the remedy is `D-g3-g`); acceptance criterion 3 deleted with its reason, as the orchestrator's error. New: `D-g3-w`, `D-g3-x`, `D-g3-y`, `D-g3-z`. `make test` **0** twice at `1587 tests in 199 suites` (4.941s, 4.130s); `make lint` **0** at `0 violations, 0 serious in 497 files`; `make parity` **0** at 358/358; `make acceptance-r6` **0** at `examined=6 failures=0`; the assigned mutation reds at **exit 2** in 10.589 s naming its own condition at `PoolReapingTests.swift:98:29`. One unrelated red in six runs — `CallbackLifecycleTests.swift:238`, a third measured `D-g3-c` instance, recorded under `D-g3-s`. Idle 0.0-44.6% with two sibling runners live What is still approximated is named — Swift's statement and trailing-closure grammar, regex literals, `#if` branches read as if all compile, and lexical containment standing in for an execution bound. All mutated files restored from `cp` backups and `git diff app/Sources/` empty across the pass |
| G4 | Assertions that do not read the quantity they are named for | `G4-assertions-that-do-not-read-their-own-quantity.md` | — | — | Needs More Work — gap-f **Verified 2026-08-22 (1st); verdict Needs More Work — gap-fix queued (`G4-gapfix.md`), figures only, no gate logic.** Four of five claims hold, each re-derived rather than read. **The load-bearing one stands**: `make all` is red at `parity-selftest` and **red identically at the base** — `git archive 72958de` plus this worktree's `node_modules` and `dist` gives `31 behaved, 5 did not`, exit 1, `diff`ing empty against the HEAD run bar one case killed at exit 143 under load 945 which behaved on re-run. Both gates print their boundary on every run, confirmed by running them. `no-wire-codable.sh` behaves as blamed. Both arms recorded as fixture defects read that way from outside. The verifier armed both gates itself **in a clone**, and both bit. **The block is one number and it is this item's own shape: the census's before column counts the instrument into its own denominator.** With the gate placed outside `planning/` and `scripts/`, the base reads **15 readers / 22 iterations / 34 drop sites**, not 19/27/48 — and copying `reader-accounting.py` into that base tree reproduces the reported column exactly, which proves the mechanism rather than suggesting it. `table_ids` had **one** base drop site, not three. *Nineteen readers in this repository* is `5a9569c`'s subject line and §1's headline. **The after column had already caught it** — `unresolved 67` is the measured 55 plus the 12 the three new files contribute — so the accounting was sound and the baseline was not. Filed as G4's **eleventh instance**, and the only one on its own reachable side. Also settled here: **1686/210 was never `main`'s** — `ai/r17` carries `IndexFailureRecordTests.swift`, one suite of exactly two `@Test`s, and `git diff --name-only HEAD main` holds zero `.swift` files. |
| G5 | Vendor the `test-campaign` version the gates actually run | `G5-vendor-the-campaign-version-the-gates-run.md` | `ai/g5` | — | **Ready to verify** 2026-08-22, **gap-fix 4 applied** — `vendor/test-campaign/` is 0.9.2 pinned to `28ecd67`, byte-identical to both the plugin cache and `git archive` at that commit, with the pin and the four gate commands in `vendor/README.md`. Reproduced from a fresh clone with the submodule uninitialised and `~/.claude/plugins` denied under `sandbox-exec`: `campaign.py check` exit 0 at 69/76 armed 69/69, `strict-check.py` 62 of 76, `capture-lineage.py --gate` 16 of 16, `vacuity-check.py` 1 finding — the same numbers `0.9.4` gives. Progress at `planning/progress/G5.md`, gap-fix 1 at `planning/progress/G5-gapfix.md`, gap-fix 2 at `planning/progress/G5-gapfix-2.md`, gap-fix 3 at `planning/progress/G5-gapfix-3.md`, gap-fix 4 at `planning/progress/G5-gapfix-4.md`. Gap-fix 4 dropped the `installed <version>` label at twelve sites in six documents and committed `planning/installed-claim-sweep.py` to guard the pattern. Filed 2026-08-22 from **M28/DEF-057, answered by the owner**: vendor `test-campaign` only, over bumping the whole submodule or dropping the reproducibility claim. Measured: vendored `0.5.0` against the `0.9.2` every reported gate actually ran, and `plugins/test-campaign` is **8.9 MB** against the submodule's **546 MB**. 0.5.0 carries none of the scripts the campaign depends on, so a fresh clone following the documented `git submodule update --init --recursive` reproduces none of its numbers. **A second cost the docket predates**: populating that submodule in a worktree breaks every runner dispatched into it — three launches lost on 2026-08-22 — so the vendoring claim describes something this fleet actively avoids doing. Acceptance requires the fallback be *disproved* by renaming the cache away, since a path that silently falls back is this item's own defect class. **Does not close X7 or X8**: vendoring makes them editable here for the first time, but an edit that never reaches upstream is a fork rather than a fix. **Corrected 2026-08-22: the trap is wider than the submodule pin.** `0.9.1` also reads **58 of 76** on today's registry — it has no `effect-witness` rung either — so every version through 0.9.1 prints the figure `strict-ratchet.json` records and reads as agreement. It follows that **the vendored 0.9.2 does not reproduce the campaign's recorded strict figure**: it reads 62 where `RUN-2026-08-20.md:589` records 58, that reading having come from a sitting headed 0.9.1. Still the right pin — reproducing 58 would mean pinning an instrument blind to four of the registry's own armed cases, and 0.9.2 is 0.9.1 plus the DEF-048 fix the campaign requested; the recorded figure is what should move, and it is the campaign owner's to raise. The strict 58→62 rise is the **instrument**; the `capture-lineage` 15→16 rise is the **registry**, that script being byte-identical across 0.9.1 and 0.9.2. |
| M15 | Settings becomes its own window | `M15-settings-window.md` | `spec-M15.md` | `plan-M15.md` | **Ready for AI** — planned 2026-08-22 at `planning/plans/plan-M15.md`, Large tier. Settings is a sidebar destination today and no `Settings` scene exists; no URL handling exists in the app at all so the brief's deep links are the mock's own. Seven panes confirmed against the mock. **Removing `.settings` from the destination enum is the risky edit and the plan found eleven readers, not the four triage recorded** — eleven Swift sites, plus two more in `mac-shell.sh` and `m6-inbox-pairing.sh` that a source-only sweep misses. Out-of-family plan review `agy`/`gemini-3.7-flash-high` **REJECT** with nine findings, seven dispositioned into the plan; the `claude-fable-5` second reading never returned, so the gate stands on one family. §11's four narrowings and three §8 parity rows are recorded as still open in the plan's §14 — the planner's session ended mid-disposition. Nine triage assumptions, not eight: `spec-M15.md:23-31` lists nine and both the spec and the plan miscount |
| M16 | The Signal Path replaces the Breaker Column | `M16-signal-path.md` | `spec-M16.md` | — | **To Do** — design of record settled 2026-08-22 as `design/mcp-router-console.html`. Needs More Info — triaged 2026-08-22. One essential question, and it is M21's fork applied to the signature element: does the breaker column stay. `BreakerGeometryParityTests` asserts exact equality against `DESIGN.md`'s nineteen rows, so removing the levers reddens a parity test whose oracle is the contested document. M23's Servers ledger has already enumerated the work and cites this brief by name |
| M17 | Four states on every surface, and chrome that follows | `M17-surface-states.md` | `spec-M17.md` | — | To Do — triaged 2026-08-22. The brief's declared dependency on M1 alone is wrong: forty cells needs M22's two boards and M15's window, so it lands after both. Nine-versus-four states produces the same build either way and is recorded as an assumption. `StateContainer` already models nine and is used only in the debug gallery. Cites `D-m23-g`, `DEF-015`, `DEF-014`, `DEF-034` and `SURF-003` rather than re-deriving them. Nine assumptions, no essential question |
| M18 | Twelve sheets, and the gate each decision gets | `M18-sheets-and-gates.md` | `spec-M18.md` | — | To Do — triaged 2026-08-22. Measured thirteen sheets in the mock, not twelve — `official` was added by M24 — and two of the mock's own sheet links resolve to nothing. The build has seven sheet sites, three still on `isPresented:`, five per-board enums and one dead case. Five of the thirteen have no host surface until M15, M19 and M22 land. Only `pair` has measured evidence and its transport is `DEF-001`, still open. Ten assumptions, no essential question |
| M19 | The in-app GitHub-flavoured Markdown viewer | `M19-gfm-viewer.md` | `spec-M19.md` | — | To Do — triaged 2026-08-22. No Markdown rendering of any kind exists in the app and nothing in the campaign measures this feature at all, so M23's gate is the only thing that will catch drift. The mock's readme sheet gained a product header and a facts strip after the brief was written. One acceptance line waits on M21 for the badge colour — a dependency, not an owner question. Eight assumptions, no essential question |
| M20 | Menu bar, status item, and the notification banner | `M20-menubar-status-notification.md` | `spec-M20.md` | — | To Do — triaged 2026-08-22. The app declares six command groups with no Router or Library menu and `⌘1`-`⌘7` over seven destinations; the mock wants nine, which waits on M22 and M15. The accelerator map disagrees three ways and the mock wins, recorded as an assumption. The status item has never been measured — `SURF-009` carries three `n/a` cases on a structural limit — and M23's harness is the route that reaches it. Eight assumptions, no essential question |
| M21 | The token layer, the split accent, and `DESIGN.md` | `M21-token-layer-and-design-md.md` | `spec-M21.md` | `plan-M21.md` | Merged `e12180 **Verified Done 2026-08-22 and merged at `e121801`.** `ColorToken` 40 cases over four resolved appearance contexts, `MetricToken` 21, `DESIGN.md` §1-2 re-authored to *Patchbay*, register regenerating **byte-identical** to the committed file at **89 rows — 70 matched, 19 pending, 0 uncited** against a plan expecting 64+. **The verification is stronger than the delivery in the two places the runner said it could not reach from its own worktree.** `mac-shell.sh`'s one scroll-edge failure is **not this branch's**: `main`'s build reports the identical `0.872 uniform` against the same 0.90 bar and passes 52/52. What M21 does move there is the separator — `main` **0.0742** to the branch's **0.0921** against a token going 7.5% → 9%, nominal 1.200 and measured 1.241, while `main` at the unchanged token differs from M13's reading by 1.9%, the run-to-run spread. An order of magnitude outside the noise and landing where the token says. And all 40 colour rows were reparsed from `DESIGN.md` alone with all **78** documented ratios recomputed in WCAG arithmetic: **zero disagreements beyond 0.05**. **Arm 7a's no-bit confirmed to four decimals** — `#FF5A5D` is 4.5610:1 on dark `--raised`, `#FF6E70` is 5.1209:1, so lightening raised contrast and the arm was aimed the wrong way; one precision the note missed is that the mutation would have reddened `colorsDocumentToCode` regardless, since `DESIGN.md:169` documents the original, so *no bit* is true of the aimed oracle and not of the suite. The silent-mutation-reuse defect is settled by evidence rather than assurance: 7b's and arm 8's recorded figures reproduce to **sixteen digits**, which cannot happen without the mutation having been applied. Departures all delivered-with-reason, none scope drift — the pin is **ported not replaced** and provably so, since no call site moved. Carried as `D-g4-a`: `planning/fidelity/servers.ledger.md` still reads `25 matched, 64 pending` beside the new register. |
| M22 | The Harnesses and Insights boards | `M22-harnesses-and-insights-boards.md` | `spec-M22.md` | — | To Do — triaged 2026-08-22. **Absorbs `R7-C1`**: neither board exists, no `GET /harnesses` route exists, and A36 forbids the Mac app reading a harness config itself, so the board and the route ship together or neither does. The route owes a parity row against `src/control.ts`. Three of the brief's four readings already exist in `HarnessState`; the fourth is new modelling. `PRD.md` §8.2's savings sketch is superseded by this brief, and the brief's own duty-cycle caption needs re-cutting for the same reason. Eleven assumptions, no essential question |
| M23 | The mock-to-SwiftUI conversion contract | `M23-mock-to-swiftui-contract.md` | — | — | **Merged** `6d54ce2` — **Verified — Done** (`effect-witness`, 2026-08-21), awaiting merge. Eight bounces, closed on live-process measurement throughout. The whole trace was rebuilt from `git archive` and reproduces exactly, and `53` turned out recoverable after all — the count of processes *mentioning* the engine — so the row that called it unrecoverable now under-claims rather than over-claims. Done rather than a ninth cycle because the one false sentence found is a rebuttal on which no figure rests, where the previous block was an acceptance failure. `D-m23-bq` is the one to carry forward: `swift test --filter` reports a zero-match filter as a pass |
| M24 | The storefront's own artwork — banners and app-style icons | — | — | — | **Done** (ai/m24 → main; design-only, 23 files, all under `design/`) |
| M25 | The controls row, not the columns, set the boards' width | `M25-board-columns-do-not-flex.md` | — | — | **Done** (ai/x4 broke the min-width chain, ai/x5 flexed the two controls rows) |
| M26 | The Checks board and the design's eval board are two surfaces | `M26-checks-board-framing.md` | — | — | **Done** (ai/m26 → main; owner kept the reachability board, mock amended, DEF-031 closed) |
| P7 | `control-auth-post-http` needs a real OAuth client | `P7-auth-post-oauth-client.md` | — | — | **Done** (ai/p7 → main; parity reached 82 of 83) |
| P8 | Make `install-launchd-watch`'s `reran` term attributable | `P8-launchd-watch-attributable.md` | — | — | **Done** (ai/p8 → main; the lane was shown able to go red) |
| R9 | The SDK drops an upstream's message on -32603; the router reads it off the wire | `R9-sdk-drops-upstream-message.md` | — | — | **Done** (ai/r9 → main; DEF-047 closed, 7 tests armed 5-of-7 red, parity 82/83 0 diverged) |
| R10 | `index` prints two counts that disagree, and neither is checked | `R10-index-reports-a-write-that-did-not-land.md` | — | — | **Done** — merged to `main` at `8241e0f` (`ai/r10` `f810870`; `effect-witness`; 3 follow-ups) |
| R14 | A client's Authenticate action succeeds, and says which upstreams still need authorising | `R14-client-auth-succeeds-and-reports-upstreams.md` | — | — | **Merged** `2481e05` — **Verified — Done** (`raster-visual`, 2026-08-21), awaiting merge. The whole flow driven independently against both routers: registration 201 and idempotent, `/authorize` 200, `/token` 200, replay refused, and `401` appears nowhere. The report's discriminator proved on the verifier's own fixtures — `auth.authorized` fails in **both** directions and the page ignores it. The bypass class is clean across six confusions on both routers. Merge is held by `parity-gate.sh` redding on an unrelated row R14 cannot have caused (`D-r14-f`, 5 green 4 red over nine runs). Follow-ups `D-r14-a`…`D-r14-g` |
| R15 | The Host check guards `/mcp` and nothing else | `R15-host-check-is-scoped-to-the-mcp-transport.md` | — | — | **Merged** `2481e05` — **Verified — Done** (`effect-witness`, 2026-08-21), awaiting merge with R14. Holds across all eleven routes on both routers; `/mcp`'s 403 stays byte-identical at 97 bytes. The live foreign-Host exposure on `/health`, `/status`, `/servers` and `/usage` is closed |
| R16 | Adoption reads global scope only, so a project-scoped server is invisible to it | `R16-adoption-cannot-see-project-scoped-servers.md` | — | — | To Do — triaged 2026-08-22, scoped to **shape 2**. Both halves confirmed at HEAD: `cmdImport` reads `src.mcpServers` at `src/index.ts:85` and never `projects`, while `projects?: string[]` is modelled at `src/config.ts:21` and `:126`, carried through resolution at `:164`/`:189` and **editable through the control API PATCH** at `src/control.ts:450` — so an owner can hand-scope an upstream today and the router honours it; only learning it from the harness is missing. **One thing the brief did not know, and it shrinks the item: the report criterion 3 asks for is already built** — `skipped` is collected at `src/index.ts:93` and printed as `not adoptable:` at `:153-155` with a per-server reason, and today only ever holds servers `parseServer` refused. So the work is enumeration plus the collision decision, not enumeration plus a new report. **Shape 1 is not deferred by preference**: it decides what scope this product works in, and `D-r7-i` is its mirror image (`HarnessesVerb` prints *Global scope only* while reading a project-scoped file), so building it now would settle that from the side with less evidence. Filed as **R16-C1**. Shape 3 stays refused — it changes the tool namespace the model sees. |
| R16-C1 | Adopt project-scoped upstreams and serve them by caller cwd | `R16-adoption-cannot-see-project-scoped-servers.md` | — | — | Deferred (child of R16) — registered 2026-08-22 at R16's triage. Blocked on the same scope decision as `D-r7-i` and `R7-C4`, which are its mirror image. `CallerIdentity` already carries cwd and `usage` already reports per-project call counts, so it is a decision problem rather than a plumbing one. |
| G5-C1 | Repo-owned gate wrappers for the vendored campaign scripts | `G5-vendor-the-campaign-version-the-gates-run.md` | — | — | Deferred (child of G5) — registered 2026-08-22. Nothing in this repo invokes a `test-campaign` script: every hit across `Makefile`, `scripts/` and `planning/test-campaign/bin/` is a comment naming one, and no file resolves a skill directory. The skill loads its own `scripts/` from the plugin cache, so vendoring a copy does not change what runs. Wrappers `make` could call are new surface rather than a relocation, so G5 carries the code and proves it runs by hand, and this carries the wiring. |
| R17 | A failed index leaves a recorded error for one server and nothing at all for another | `R17-a-failed-index-can-leave-no-trace.md` | — | — | Needs More Work (3rd) — gap-fix **Verified 2026-08-22 (3rd); verdict Needs More Work — gap-fix 3 queued (`R17-gapfix-3.md`), two lines, no code.** Criteria 1, 2 and 4 pass: the withdrawn clause is gone and a wrap-tolerant sweep finds the assertion nowhere; the six-site list has **both inventories re-derived from source rather than carried** (node 5 `saveManifest` with `writeFileSync` only inside it, Swift 3 `ManifestIO.save` and no other writer), verb attributions spot-checked; gates unmoved. **Criterion 3 fails, and the instrument is the finding.** `R17-acceptance.md:472` still reads *the declaration names all four uncovered sites* — the document in its own voice, now false since `surface.tsv` names six — and **the runner's sweep could not see it**: the hard wrap falls between `all four` and `uncovered sites`, so `grep -c` returns **0** where a whitespace-normalising match returns **1**. Fourth consecutive pass to block on this claim class and the first where the instrument rather than the diligence is at fault. Filed as G4's **tenth instance**. `:647` fails arguably too — node-scoped it is true, but its subject is what the declaration says. **`D-r17-d` refuted as stated and strengthened in substance**: serially it never reds (**0 of 40** on the branch, **0 of 40** on main), under four concurrent copies **53 of 104** and **24 of 72** — concurrency-conditional, not flat, and reproduces-on-main settled. Mechanism **proven**: ten fixture names reported in **both directions at once** over an unchanging git-tracked directory, which can only come from the `grep -qxF`-per-item comparison at `parity-manifest-check.sh:431`/`:437`. Now also carried as a fleet-level gate hazard. **The base-behind-main pair confirmed**: `grep -c '"L"'` is 0 here and 1 on main, both conflict blocks are still at `:242-249` and `:643-664`, so check L would go red from this base and the work order's `A-L` was unmeetable — the dispatch's gap, not the runner's, and it does not change the verdict. |
| R18 | A failed index drops the digest, so the next success serves a changed surface unheld | `R18-a-failed-index-drops-the-digest-that-holds-the-diff.md` | — | — | To Do — triaged 2026-08-22, plan alongside `R20` (same manifest row, opposite direction). **Confirmed by reading, and the drop is incidental rather than deliberate**: `buildManifest`'s `catch` at `src/manifest.ts:258-265` constructs a whole new entry while `prev` is in scope, and the held-diff branch four lines above spreads it — so `digest` and `tools` are both dropped, and at `:236` `!prev?.digest` takes the same branch as a matching digest. The evidence is this file's own convention rather than silence in general: every deliberate retention here carries a defending comment, the first-sight branch has a six-line one, and this branch has none. So the brief's first fix is right — **keep the last good digest**, and an absent digest keeps meaning *never seen*, which is what `:236` already assumes. **The fork that remains is the plan stage's first decision**, because `unionTools` at `src/manifest.ts:326` skips on `!entry ‖ entry.tools.length === 0` and **never reads `entry.error`** — the zero-length list is load-bearing and doing the job the error field looks like it should do. Digest-only leaves a seen-then-failed server held against an empty approved set; digest-and-tools with serving gated on `error` is correct for the right reason and reaches `router.ts:168` and `:347`. Criterion 2 is what separates them, so arm it against a never-seen server **and** a seen-then-failed one. |
| R19 | A watch fire saves a manifest snapshot taken before a concurrent write | `R19-a-stale-manifest-snapshot-clobbers-a-concurrent-write.md` | — | — | Ready for AI — triaged 2026-08-22, Standard. **The precondition is settled and the answer is neither option the brief listed.** Referred to the Google lane (`agy`, `gemini-3.7-flash-high`) with the write-site census, the `ConfigMutationLock` source and both options; it returned a third shape: *perform long-running child indexing with no lock held, then acquire the lock strictly around the commit phase — read current disk state, merge the single server row, write to temp, rename. Lock duration drops from seconds to <1ms.* **The policy over all eight sites is `withExclusiveLock { load; merge the rows this path owns; save }`** — the load moves inside the lock because it is the stale read that clobbers, not the write. **This dissolves the objection that made it a fork**: option A held the lock across the seconds-long read-then-index window and would have made a concurrent PATCH fail at the 2000 ms daemon bound; commit-phase-only never reaches it. Two shapes asked about and rejected by name: a `manifest.d/*.json` split (*orphan cleanup bugs on delete/rename, migration churn for a single small config*) and optimistic CAS retry (*unnecessary — `flock(2)` queues sub-millisecond writes with zero retries*). **`VER-R17-2` inverts**: Swift's re-load-per-entry was the right instinct without exclusion, so the fix upgrades it and the two converge by construction — convergence is the expected outcome and a `surface.tsv` declaration is the fallback. `ConfigMutationLock` is already generic over the path; node has no counterpart and that is the larger half. Eight sites, a node lock module, and **one overlapping-writer scenario with no precedent here** — `parity-cli.sh` runs the binaries sequentially and is structurally blind, so it needs a new lane rather than a new row. |
| R21 | `approve` answers 200 while discarding the write that would make it true | `R21-approve-answers-200-over-a-discarded-write.md` | — | — | Ready for AI — filed 2026-08-22 while re-measuring M28's DEF-049, which had two halves fixed and a third predicted. **The prediction is refuted and the plainer defect survives it.** `AuthRoutes.swift:120` is the last of DEF-049's three `try? ManifestIO.save` sites; the route sets `tools`/`digest`/`builtAt`, removes `pending`, discards the write and returns `(200, approved: N)` unchanged — so a refused write leaves the surface held while the caller is told it was approved, and `approved` is counted from the pending entry **before** the write. DEF-049's louder prediction (a stale `builtAt` fires `Describe.swift:218` and `/servers` reports `authorized: true`) **does not follow**: approve is reachable only with `pending` present, and both implementations clear `error` when they stage one — `src/manifest.ts:246` and `ManifestBookkeeping.swift:83` — so the `guard case let .string(text)?` at `Describe.swift:208` fails first and `:218` is never reached. The fix shape is already in this repo at `ServicePorts.swift:388-394`: catch, carry a `cacheFailure` into the response. **Do not move the status code** — `ControlApproveDispatchTests.swift:114-118` pins 200 deliberately. |
| X1 | The iOS accessibility-tree harness, and two surfaces still empty | `X1-ios-a11y-harness.md` | — | — | Done (closed by X3's engine fix + the accessibility-frame row oracle; `make test-ios` 36/0) |
| X2 | The iOS on-glass instrument, and the six cases it takes off `n/a` | `X2-ios-on-glass.md` | — | — | **Done** (ai/x2 → main; lane-owned device, six green runs) |
| X3 | The iOS unit lane read an empty accessibility tree because the engine was off | `X3-ios-unit-lane-empty-tree.md` | — | — | Done (DEF-029 closed, armed three ways) |
| X6 | Cleanup's `Read first…`, the half DEF-011 was held open for | — | — | — | **Done** (ai/x6 → main; CASE-0135/0136/0137, nine mutation arms) |
| M27 | The sidebar foot's loopback readout and the child-process label | `M27-sidebar-foot-readout.md` | — | — | **Done** — merged to `main` at `cbe5cc3` (`ai/m27` `26337b8`; rung `raster-visual`; 6 follow-ups `D-m27-a`…`D-m27-f`, none blocking) — both restored, on glass 8 of 8 boards. The count card announces as ONE element — `Child processes, 1 of 4 declared servers running` — after a reversal: the branch first shipped it as two stops because A35's readout line was anchored whole, and three model families independently found that anchor was written before the label existed. A35 widened to its own stated prefix tolerance. The mock's `--live` foot dot deliberately not, and the same argument convicted the count numeral, which was painting `--live` on `0 of 4`. `mac-shell.sh` exit 0, 1552 tests, evidence in `planning/evidence/M27-acceptance.md` and `planning/evidence/M27/` |
| M28 | Five findings that need a decision rather than a runner | `M28-decision-docket.md` | — | — | Done — all five dispositioned 2026-08- **Closed 2026-08-22.** DEF-057 answered by the owner — vendor `test-campaign` only — and filed as **G5**. Four of five never reached the owner: two had been answered by work that landed after the docket was written, one was the orchestrator's to take, and DEF-033 needs nothing. The two that became work are **R21** and **G5**. |
| X7 | The campaign's published artifacts under-report what it knows | `X7-campaign-artifacts-underreport.md` | — | — | Untriaged (**upstream**: fledgeling-plugins, not this repo) |
| X8 | Two campaign detectors report findings they cannot support | `X8-detectors-misattribute.md` | — | — | Untriaged (**upstream**: fledgeling-plugins, not this repo) |

| I5 | Prove the phone↔Mac pairing round trip, and stop there | — | — | — | **Merged** `4157bc4` (ORCHESTRATOR.md) |
| I6 | Make Mac approval fast, without moving the boundary | — | — | — | **Merged** `ef4f615` (ORCHESTRATOR.md) |
| M9 | Rename the `Evals` destination to `Checks` | — | — | — | Done inside D2 (`9e8a754`) — triaged 2026-08-21 |
| M10 | Amend `DESIGN.md` §6:279–280 | — | — | — | Done inside D2 (`9e8a754`) — triaged 2026-08-21 |
| M11 | Regenerate the M1 command inventory | — | — | — | **Merged (partial)** `2a434b9` — promoted out of the deferred register |
| M12 | Staleness and an as-of time inside a destructive dialog | — | — | — | Ready for AI — triaged 2026-08-21, measured still open |
| P5 | Close the last three closeable parity rows | — | — | — | **Merged** `e752305` (ORCHESTRATOR.md) |
| P6 | State the owner's cutover target in the gate | — | — | — | **Merged** `05296ea` (ORCHESTRATOR.md) |
| R2-R | Router: the process that actually serves | — | — | — | **Merged** `62678aa` (ORCHESTRATOR.md) |
| R2-W | Router: the `~/.claude.json` watcher and its adoption protocol | — | — | — | **Merged** `8e48a80` (ORCHESTRATOR.md) |
| R4-C | The installer cutover | — | — | — | **Superseded** — split into R4-C1 (Done, `ai/r4c` merged) and R4-C2 (Held). Not blocked: each half has its own state and its own row. The owner's target is 82 of 83 |
| X4 | Mac boards: six defects the design of record names | — | — | — | **Merged** `2ff0941` (`ai/x4`) — its work is written up under M25 |
| X5 | Discover and Skills: the controls row set the board's width | — | — | — | **Merged** `dee20da` (`ai/x5`) — its work is written up under M25 |

## Allocation notes

- **Statuses were synced from ORCHESTRATOR.md on 2026-08-21.** Twenty-six rows here read
  `Untriaged` for work that had already merged — R2, R3, R5, M1–M8, I1–I3, P1–P4, D1–D3, F4,
  G1, M13, M14, V1 and R4. A fleet reading this column would have dispatched twenty-six shipped
  items. Membership and status drift separately: `ledger-reconcile.py` catches the first and
  cannot see the second, because both files having a row for an id says nothing about the two
  rows agreeing. When you change a status, change it in both files or the next fleet re-plans
  the work.
- **M3 was triaged on 2026-08-21 and it had shipped.** The earlier note here recorded it as
  unresolved rather than open — its row said `Untriaged` with no branch while M7's dependency
  cell read `M3 ✓ M4 ✓` — and refused to guess which reading was right. The answer is the first
  one: `589ab2e` ("the breaker board — Servers is the first pane that is actually built"),
  `3b11f33` and `af77200` are all ancestors of `main`, six `ServersBoard*.swift` sources are in
  the tree and seven test files name the board. M7's tick was correct and both rows were simply
  never updated. Scheduling it would have rebuilt a shipped board — which is the cost this note
  existed to prevent, and the reason a status a fleet cannot explain gets triaged rather than
  assumed in either direction.

- **`R7` was two different items, and both ledgers reconciled clean the whole time.** This file
  carried `R7 — the router's thesis is unmet for every harness but Claude Code`, with a brief on
  disk named for it. `ORCHESTRATOR.md`'s deferred register carried a different `R7` — the skills
  write endpoint, a child of R3 filed by M7. Two items, one id.

  `ledger-reconcile.py` could not see it, and the reason is worth keeping: checks A and B ask
  whether an id appears in *both* files, and it did. **Membership and identity drift separately,
  the same way membership and status do.** Check `F` was added for this — it compares the two
  description cells for an id present in both files and reports a pair sharing no content word at
  all. That bar is deliberately low: a legitimately reworded row nearly always keeps its subject
  noun, so requiring *zero* overlap is what stops the check firing on a correct use.

  Resolution: the top-level ledger item keeps `R7`, because a brief file carrying the id in its
  filename is the stronger claim. The deferred child became `R11` and now has a row here of its
  own. It is still open — `CleanupSheets.swift:204` draws `DisabledAction(label: "Remove", …)`.

  **Check F then found two more on its first run, and the second one exposed a defect in the
  check itself.** `R8` was the merged auth-rejection item here and *server soft-delete with a
  restore endpoint* in the deferred register; it became `R12`. `R6` was the child-PATH item here
  and *a router-side behavioural eval runner* in the deferred register; it became `R13`.

  `R6` is the one worth keeping. The first version of check F read **one row per file**, and
  `ORCHESTRATOR.md` carries two `R6` rows — the child-PATH item in the wave table, and the eval
  runner in the deferred register. The row that agreed with this file was simply the earlier one,
  so the check reported clean. A collision inside a single file is the same defect as one across
  two, and a predicate that reads one row per file cannot see it. F now compares every row for an
  id against every other, whichever file each came from.

  **Fixing the collisions created a fourth defect, and check `G` was added for it.** Renumbering
  the deferred `R8` to `R12` left the *merged* `R8` — the auth-rejection item on `ai/r8` — with
  no ORCHESTRATOR row at all, because that had been its only one. Check B did not fire: B clears
  on an id being **named** anywhere, which is the right bar for "does the other file know this
  exists" and the wrong one for "can a fleet resume from that file". G asks the narrower
  question, and found `R8` plus `X4` and `X5`, two merged branches this reconciliation had given
  rows here but never there. All three now have rows. Both tables stand at 77.

  The sequence is the point: six checks reported clean over a file with three id collisions and
  three missing rows. Each new check found something on its first run, and one of them found a
  defect the previous fix had just introduced. A reconciliation is not a state you reach; it is a
  claim that only holds for the predicates you have written down.

  **Then eight checks reported clean over five stale duplicate rows**, found by `dev-09` rather
  than by this script. `ORCHESTRATOR.md` carried two rows for `M23`, `M27` and `R10` — each pair
  agreeing on the title and disagreeing on the status, with the stale one reading *earlier* than
  the truth: `Untriaged` beside `Ready to verify` for two branches sitting at 6 and 12 commits.
  A fleet slot filled from the stale row dispatches a triage run on work that is already built.

  None of A, B, F or G could see it. Their diagnosis is worth keeping verbatim: **each check
  tests a different key, and a row is only as bound as the weakest key any check uses.** A and B
  test membership, F identity, G resumability — and none tests currency, so a present, plausible,
  wrong row satisfies every one of them. That is worse than a missing row, because a missing row
  fails membership and a stale duplicate fails nothing.

  Check `H` groups rows by id and compares status cells. It indexes the column by its **header
  name** rather than its position, which is what keeps it honest: this file has one nine-column
  table carrying `Status` and a four-column deferred register carrying none, so a positional
  predicate would have compared `M11`'s register row against whatever sat at that offset. H found
  the three plus `R4-C`, whose two rows read `Blocked — needs 82 of 83` and `Wave 4 — last` — a
  wave label written into a status cell, both stale, both quoting a parity figure since
  superseded. R4-C is now one row: superseded by `R4-C1` (Done, `docs/install.sh` defaults to
  `MCPR_ROUTER=swift`) and `R4-C2` (Held).

  Fixing it also turned up `M13`: a complete nine-column row pasted into the four-column register,
  where its cells read as *Absorbed by: mac* and its outcome as a dependency list.

  **H then had the same defect it was written to catch, one level down.** `dev-09` asked what the
  parser does with a row whose field count does not match its header — and the answer was that it
  skipped it, silently. Measured: **70 rows examined, 23 skipped**, all of them four-cell
  deferred-child rows interleaved in the nine-column table with no header of their own. None of
  the 23 can disagree about a status it has no cell for, so the finding survives — but a check
  that quietly discards what it cannot parse reports clean over a subset, which is the same
  denominator failure as a campaign publishing a pass rate over the surfaces it happened to reach.

  The script now prints `H examined N rows; skipped K` on **every** run, names the skipped ids,
  and returns **2** rather than 0 when `examined == 0`. A gate that never ran is not a gate that
  passed, and the one way to reach a false clean here was for the table shape to change under it.

  A row with *more* cells than its header is placed rather than skipped, and correctly: a stray
  `|` shifts only the cells after it, so every column before the offending pipe keeps its index.
  `D3` is the live case — 11 cells against a nine-column header, `Status` still landing on
  `**Merged** \`67ae4f5\``.

  H is armed three ways: the unmutated file is clean at exit 0; a stale duplicate row injected for
  `M27` makes it name both line numbers at exit 1; and renaming the `Status` header to `State`
  makes it exit 2 saying it measured nothing, rather than reporting a clean file it could not
  read.

- **M9, M10 and M12 were triaged on 2026-08-21 by measuring the tree, not by reading their
  rows.** Two of the three had already shipped. `M10`'s amendment is in `DESIGN.md` §6, which now
  carries the correction *and* the reason — the old illustration "a skill with no evaluation reads
  'not evaluated'" named a state the product cannot be in, because there is no eval runner
  anywhere in it. `M9` is closed in `Destination.swift`: `.evals` reads `Checks`, and the
  `rawValue`, `iconName` and `?pane=evals` slug stay `evals` **on purpose**, documented in source
  — they are identifiers held in frame restoration and in every mock link, and `DESIGN.md` §6
  governs words a user reads rather than keys a machine matches. `M12` is the one still open:
  `CleanupSheets.swift` draws its destructive "Remove <name>?" dialog with a consequence figure
  carrying no staleness marker and no as-of time.

  Three items, two of them already done — the same shape as the M3 note above. A deferred
  register records what was *filed*, and a later item closing it does not write back. So a row in
  this table is a claim about the past; check it against the tree before scheduling from it.

- **Thirteen rows were added on 2026-08-21 that this file had never carried.** Eleven were
  named only in this file's prose or only in ORCHESTRATOR.md; two — X4 and X5 — were merged
  branches recorded in neither. An allocator scans the table, so a mention in prose does not
  stop an id being reissued: that is how I6 came to be allocated for a new brief while it was
  already merged at `ef4f615`. Run `planning/ledger-reconcile.py` after every allocation; it
  refuses in both directions and has six predicates, because each is blind to the others.

- **This file is not the only allocator, despite the header above.** Measured 2026-08-21:
  `ai/i5`, `ai/x4` and `ai/x5` exist as branches, `I5` holds a live worktree, and
  `ORCHESTRATOR.md` carries rows for **I5 (Merged `4157bc4`)** and **I6 (Merged `ef4f615`)** —
  none of which appear in the table above. ORCHESTRATOR.md is the live ledger; this file has
  drifted behind it. Check both, plus `git branch --list 'ai/*'`, before allocating. Two
  sessions independently reached for an id that was already taken on the same evening, which
  is what this note exists to stop.
- **X4 and X5 are taken** (branches exist and both are merged into `main`: `2ff0941`, `dee20da`),
  as are I5 and I6. New instrument work continues at X7 rather than reusing them, so an ID never
  means two things. This line used to reach for M9–M12 as the example of an unfilled gap; that
  comparison was false in both halves and the note below says why.
- **X7 and X8 are editable here since G5, and still closable only upstream.** Both are defects in
  `test-campaign` 0.9.2. Until 2026-08-22 a runner in an mcp-router worktree had nothing to edit —
  the submodule pin carries 0.5.0 and lacks the scripts entirely (DEF-057). `vendor/test-campaign/`
  now holds the real 0.9.2, so the blocker has changed shape rather than lifted: an edit that lands
  only in this repository is a fork of the instrument, and a script that behaves one way here and
  another way everywhere else stops being evidence. Closing them still means a change pushed to
  `fledgeling-plugins`, after which the pin in `vendor/README.md` moves to the new commit. G5
  touched neither.
- **M28 is a decision docket, not work.** A ship-feature runner should skip it. It closes by
  the owner answering four questions, after which each answer becomes an ordinary item.
- **DEF-001 and DEF-041 did not get a brief.** The pairing transport is already specified by
  M6 (Mac side) and I1 (phone side), both Untriaged. The campaign's measurements are appended
  to those two rather than duplicated into a third.

- **M9–M12 are all allocated, and this line used to deny it.** It read "unused … never allocated;
  the M series jumps from M8 to M13", which is false for all four. They are ledger items in
  **ORCHESTRATOR.md's deferred register, lines 241–244**: M9 renames `Evals` to `Checks`, M10
  amends `DESIGN.md` §6:279–280, M12 covers staleness inside a destructive dialog. **M11 was
  promoted out of that register and merged at `2a434b9`** (an ancestor of `main`). M9, M10 and
  M12 carry no branch and have not shipped. New Mac work continues at M24 rather than filling
  the gap, so an ID never means two things.
- **A range in a note hides the id inside it.** "M9–M12 are unused" absorbed a merged id and read
  clean in every membership check over this file, because nothing searches for `M11` inside the
  string `M9–M12`. Expand ranges before reconciling two id tables; a range is the one notation
  where a reconciliation reports agreement it never tested.
- **M23 blocks M15–M22.** It specifies how a mock-to-SwiftUI conversion is proved. Converting a
  board before the measurement layers exist produces a build that looks right and cannot be shown
  to be, which is the failure the brief's sources were written from. New Mac work continues at M24.
- **One skill is vendored; four are machine dependencies.** `vendor/test-campaign/` carries
  `test-campaign` **0.9.2**, pinned to `28ecd6753386ff6d480a98d6646a5b73c62dc299` of
  fledgeling-plugins and byte-identical to it; the four campaign gates run from there and
  `vendor/README.md` carries the pin, the tree checksum and the commands. `mockup-fidelity`,
  `mac-craft`, `design-craft` and `ux-craft` are **not** vendored in any usable sense: they exist
  only inside the `.claude/plugins/fledgeling-plugins` submodule, and no worktree may run
  `git submodule update --init` because populating 546 MB of plugin skills where Claude Code loads
  them kills the runner (ORCHESTRATOR.md, DISPATCH — WORKTREE SUBMODULE). This entry used to claim
  all five were read at a repo-relative path. **What that cost, measured 2026-08-22:** the
  submodule pin carries `test-campaign` 0.5.0, which has no `capture-lineage.py` and no
  `vacuity-check.py` at all, and whose `strict-check.py` prints **58 of 76 (76%)** on this
  registry — the exact figure `strict-ratchet.json` records — because it does not know the
  `effect-witness` rung and silently drops all four such cases. 0.9.2 and 0.9.4 both
  print **62 of 76 (82%)**. A clone following the old instruction would have read agreement off an
  instrument measuring something laxer.
- **M15–M22 were allocated together on 2026-08-19** from the interactive mock at
  `design/mcp-router-console.html`. They are UI specification, not defects: each names something
  the mock draws that no earlier brief covers. `design/mcp-router-console-spec.md` carries the
  audit numbers and the list of what the mock specifies rather than measures.

- **Three ids mean two things each, and R7 found it while allocating.** `ORCHESTRATOR.md`'s
  deferred register (lines ~334–337) carries rows **R6** (router-side eval runner), **R7** (skills
  write endpoint) and **R8** (server soft-delete), while this table carries **R6** (child PATH,
  ready to verify), **R7** (harness reconciliation, this item) and **R8** (auth rejection, Done).
  Six live rows, three ids. The deferred register was populated from a different allocator than
  this table and nothing reconciles the two namespaces, which is the same hole the notes above
  describe for membership — `ledger-reconcile.py` compares ids across files and a collision
  between a *ledger* id and a *deferred-register* id is not a membership disagreement, so it
  reports agreement. R7 did **not** renumber anything: three rows written by other items are not
  a runner's to renumber mid-fleet, and picking a direction silently is how the drift got here.
  R7's own children are `R7-C1`…`R7-C4`, following `R4-C1`/`R4-C2`, which cannot collide either way.
  The decision this needs is which namespace yields — that is M28's shape, not a runner's.
