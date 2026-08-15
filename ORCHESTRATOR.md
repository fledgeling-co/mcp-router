# ORCHESTRATOR.md — MCP Router

**This file is the memory, not the transcript.** A fresh session resumes the whole fleet
from here plus `DESIGN.md` and `planning/features-to-triage/LEDGER.md`. Update it after
every state change, before acting on that change.

---

## Contract

| | |
|---|---|
| Repo | `~/Dev/mcp-router` · public · `fledgeling-co/mcp-router` |
| Integration branch | `main` (pushed; the marketing site deploys from `main` `/docs`) |
| Pipeline root | **`planning/`**, not `docs/` — `docs/` is the live GitHub Pages source for mcp-router.fledgeling.app and Jekyll would publish every spec to the public site |
| Specs · plans · briefs | `planning/specs/spec-<ID>.md` · `planning/plans/plan-<ID>.md` · `planning/features-to-triage/` |
| Practices | `planning/practices/` — inherited from bella-team-files. **They are TypeScript/Next.js and carry no Swift guidance.** F1 owes `SWIFT_PRACTICES.md`; until it lands, Swift runners have no house style to conform to |
| Design authority | `DESIGN.md` at the root. Reference implementation `design/mocks/prototype.html` (interactive, deep-linkable) |
| Worktrees | `.worktrees/<ID>` on `ai/<id>` |
| External model CLIs | **On** (no opt-out marker in this repo) but **the codex lane is UNAVAILABLE — do not probe it.** See below |
| Concurrency | ≤8 slots; the DAG peaks at 5 |
| Merges | **Serialized by the orchestrator.** Runners stop at ready-to-merge |

### Two standing decisions, taken with the user at preflight

1. **Swift ships alongside TypeScript; TS stays the installed default until R4's parity
   gate passes.** The router the user's sessions depend on must not be under a rewrite
   with no fallback. Only R4 flips the installer and deletes `src/*.ts`.
2. **macOS is direct-distribution, unsandboxed** (Developer ID + notarized DMG). An app
   that spawns arbitrary MCP subprocesses and rewrites `~/.claude.json` cannot run under
   App Sandbox, so MAS was never available to it. iOS is the opposite: App Store,
   sandboxed. The entitlements differ per target and are written in F1, not retrofitted.

### Standing constraints every runner inherits

- The Mac app talks to the router **only** over the loopback control API. That boundary
  is what lets R1–R4 swap the router underneath without the app changing.
- `command`, `args` and `env` are never writable through the control API's PATCH.
- The phone **queues**; it never installs. Deliberately narrower than "remote install".
- No number is displayed that the router does not observe. There is no fabricated memory
  saving anywhere in this product.
- The Swift MCP SDK is pre-1.0 and warns that minor bumps may break — pin exact.

### Only test a screen you changed, and only that screen — user instruction, 2026-08-14

Standing, and it outranks any sweep-everything habit in the pipeline skills. Changed a row,
a menu item, one pane? Test that one thing. Changed nothing under a screen since it was last
proven? Do not test it at all — cite the existing evidence. Never relaunch the app or boot a
simulator per screen: one launch, one pass, quit.

The measurement behind it: **M1 and I1 have each been through four runs**, and every relaunch
restarted UI verification from zero because nothing on disk recorded what had already been
proven. The Mac lane drives the user's *real* screen through `osascript`, so they sat watching
the same windows and menus driven over and over. That is their time, not just tokens.

The fix that makes it stick across a relaunch: each UI item keeps
`planning/evidence/<ID>-acceptance.md` — one row per screen: screen · how it was verified
(the actual command or AX path) · the commit SHA · result. Append, never rewrite, commit it,
and **read it before testing anything**. A row whose SHA-to-HEAD diff does not touch the files
behind that screen IS the evidence.

This narrows repetition, never rigour: a screen never yet tested still gets tested properly,
once, and behavioural claims still need behavioural proof. Skips get reported as skips.

### The codex lane is down until 2026-08-20 — read before any out-of-family gate

Verified by the orchestrator on 2026-08-14: every `codex exec` call, down to a one-word
probe at low effort, returns *"You've hit your usage limit … try again at Aug 20th, 2026
1:29 PM"*. That is **account-level**, not per-call, and Aug 20 is past this fleet's
horizon. Do not spend a probe rediscovering it.

Run the three out-of-family gates in-family instead: a **fresh `claude -p` opus-5 reviewer
per gate**, briefed adversarially — told to refute, and told that finding nothing is a
failed review rather than a pass — and record `codex: usage limit -> claude (downgrade)`
in the spec, plan or completion note, so the weakness travels with the evidence instead of
disappearing. This is a logged in-family downgrade, which the skill permits; it is not a
skipped gate.

**The trap that makes this dangerous: `codex exec` exits 0 on a usage limit.** A gate keyed
on `$?` records a pass for a review that never ran. The only honest tells are the ERROR
line in the log and a missing-or-empty `-o` file — assert the `-o` file is non-empty before
believing any codex result, on this fleet or a later one.

### A runner that messages the orchestrator ends its turn

Observed twice on 2026-08-14 (R5, and the stopped R3 duplicate): a runner that calls
SendMessage stops, and `TaskStop` then reports *"no active task"* for it. It stays stopped
until the orchestrator replies, which resumes it from its transcript. So a message is not
an aside — it costs the runner its turn.

Two consequences. Runners: say what you need in one message and expect to be resumed;
don't message mid-phase for something you could decide yourself. Orchestrator: **reply
promptly, because a runner awaiting a reply is indistinguishable from a dead one** — the
liveness watcher will report it quiet in fifteen minutes either way.

---

## Wave plan

Waves are the dependency DAG's topological levels. Slots refill on completion rather
than barriering on whole waves, so the real overlap is greater than the table implies.

| Wave | Items | Peak slots | Gate to leave |
|---|---|---|---|
| 1 | F1 | 1 | ✅ **CLEARED** — both targets build, CI green on a clean runner, `SWIFT_PRACTICES.md` landed |
| 2 | F2 · F3 · R1 | 3 | ✅ **CLEARED** — all three merged; merged-tree `make all` exit 0, 237 tests, lint clean |
| 3 | M1 · R2 · R3 · I1 (+ **F4**, injected) | 3 | **R2 ✓ R3 ✓ R5 ✓ F4 ✓ merged.** Remaining: M1 (no UI shipped), I1 (partial). Concurrency cut 5 → 3: I1's iOS build was `Killed: 9` by memory pressure from five parallel Swift/Xcode builds, which is part of what kept killing agents |
| 4 | M2 · M3 · M4 · I2 · R4 | 5 | **R4 is the parity gate and may not pass on a subset** |
| 5 | M5 · M7 · M8 · I3 | 4 | — |
| 6 | M6 | 1 | Phone → Mac inbox round-trip works end to end |

```
F1
├── F2 ─┬── M1 ──┬── M2
│       │        ├── M3 ──┬── M7
│  F3 ──┘        │        └── M8
│       │        └── M4 ──┬── M5 ── M6
│       │                 └── M7
│       └── I1 ── I2 ── I3
└── R1 ─┬── R2 ─┐
        └── R3 ─┴── R4
```

---

## Ledger

Status: `Untriaged → Spec → Plan → In Progress → Ready to merge → Merged` · `Blocked` ·
`Parked`.

| ID | Title | Category | Deps | Mock (deep link) | Lane | Status | Branch | Outcome |
|---|---|---|---|---|---|---|---|---|
| F1 | Swift workspace, kit, three targets | foundation | — | — | Opus | **Merged** `0924040` | — | `make all` exit 0 on the merged tree · 31 tests · both targets build · **A12 (CI) MET** — run 31747021039 `build-and-test: success` on a clean GitHub runner, 2026-08-14 |
| F2 | Design system in SwiftUI | foundation | F1 ✓ | `?only=mac` + `DESIGN.md` §§2–7 | Opus | **Merged** `22d1802` | — | merged-tree `make all` exit 0 · 75 tests · both appearances authored · tokens tested *against* `DESIGN.md`, so doc and code cannot drift · two recorded deviations (tertiary 50% not 25%; `--onAccent` 3.23:1, kit wins) |
| F3 | Control-API client and models | foundation | F1 ✓ | — (surface: `src/control.ts`) | Opus | **Merged** `13825c9` | — | merged-tree `make all` exit 0 · 147 tests · 23 recorded fixtures + `ControlProbe` · **merge found a real defect**: unanchored `.gitignore` `servers.json` had silently swallowed a source fixture, green on the branch and red only when merged |
| R1 | Router: core, config, manifest | router | F1 ✓ | — | Opus | **Merged** `c30eac9` | — | merged-tree `make all` exit 0 · 237 tests · 224 parity vectors · mutation gate exit 0 · SDK pinned exact `0.12.1`, confined to `RouterCore` which neither app links |
| F4 | ServerStateTracker cannot report failure | foundation | F3 ✓ | — | Opus | **Merged** `aba30bd` | — | 306 tests on the merged tree · LoadKind .failed/.stale + StreamCondition .notConfigured · M55 survived the first mutation run (no test saw the notification lost when `register` is deferred into a Task) and `ServerStateTrackerPublicationTests.swift` is the test written to kill it · unblocks M2, M3 |
| R2 | Router: pool, relay, passthrough | router | R1 ✓ | — | Opus | **Merged** `a8091bb` | — | 279 tests · 224 parity · 13 mutation guards load-bearing · 10 behavioural tests against a REAL spawned child (pipes, signals, PATH, SDK handshake) · gate run on the rebased tree |
| R3 | Router: control, usage, registry | router | R1 ✓ R2 ✓ | — | Opus | **Merged** `e154bae` | — | 386 tests · 352 parity (parity-regen matches the reference exactly) · differential harness vs the RUNNING TypeScript router: 32/32 rows, 3 of which kill the reference where Swift answers 400 · 35/35 mutations red · 8 live port defects · **Phase D critic never ran** (codex account limit) — degraded, not passed |
| R5 | Router: OAuth and the auth routes | router | R3 ✓ | — | Opus | **Merged** `b7c527c` | — | 456 tests · 358 parity (352 core + 6 auth, asserted by name) · 10 mutations red-green · the real NWListener exposed 5 defects the double could not, incl. a CheckedContinuation double-resume in `AuthFlow.cleanup` that traps and kills the daemon · Phase D in-family (downgrade logged) 11 findings/8 fixed · one guard correct-by-construction but untested, recorded in the evidence file |
| **R2-R** | **Router: the process that actually serves** | router | R2 ✓ R3 ✓ R5 ✓ | — | Opus — never downgrade | **Merged** `62678aa` | — | The daemon exists: composition root, `LoopbackHTTPServer`, `MCPEndpoint`, `MCPRouterCLI`, lifecycle. **Parity gate 50/81 → 69 of 82, 0 DIVERGED** — the five structurally-blocked lanes (`mcp`, `cli`, `install`, `state`, `log`) are now measurable rather than blocked. Merged-tree gates re-run by the orchestrator, not taken on report: lint **0 violations / 243 files**, **750 tests / 106 suites**, **358 parity vectors**; merged tree byte-identical to the gated tree (`163597f7`). Lint went green by splitting on real seams (`RouterService` → root/dispatch/collaborators, `MCPEndpoint` split, `StdioUpstreamTransport.open` → spawn + handshake) — **no limit raised**. Real violation count was **31, not 29**: swiftformat's wrapping pushed three more files past the 400-line cap. One narrow config change for a genuine swiftformat↔swiftlint `opening_brace` deadlock, verified by hand. The gate still exits 1 by design; the cutover stays with R4 and the user |
| R4 | Parity harness and cutover | router | R2 ✓ R3 ✓ R5 ✓ | — | Opus — never downgrade | **Merged (harness only)** `e129779` | — | **Cutover NOT performed and NOT recommended.** `parity-gate.sh` exits 1 at **50/81** — `mcp` 0/5, `cli` 0/10, `install` 0/5, `state` 0/1, `log` 0/1, all blocked structurally because **there is no Swift router process**. All 3 gates REJECT, all 3 independently confirmed the no-daemon finding, all 3 rejected the coverage number (was overstated five ways; denominator rose 71→81). Gate proven by hiding `dist/`, by a lane exiting 0 recording nothing, and by a fabricated test name |
| **R2-W** | **Router: the `~/.claude.json` watcher and its adoption protocol** | router | R2 ✓ R3 ✓ | — | Opus — never downgrade | **Merged** `8e48a80` | — | The second launchd agent and the cross-process adoption protocol. Delivered with a **sidecar flock**, not a lock on the config itself, and the watcher shares that lock without sharing `ConfigEdit`'s writer. **It fixes the reference's own bug rather than porting it** — `D-i`/`R2 D7`, where a lost restart means an adopted server can never reach the running router; `restartPending` now persists before the rename, declared as a parity vector so R4 reads it as intent. Merged-tree gates: lint **0 / 403 files**, **1267 tests / 159 suites**, `parity-cli` 15 verbs agreed, `parity-divergence` 3 as declared 0 stale, `parity-install` four real launchd agents. **Parity 68 → 71 of 82 proven, 13 → 10 blocked**, measured by the orchestrator from the repo root both times — the runner read 69 → 72 from its own worktree and the **delta is identical**; the absolute differs by one row because of **D-o**. Gate still exits 1 by design. 8 mutations, 6 red, and **two that did not bite are recorded as such rather than swapped for ones that did**. The **plan gate returned REJECT** (2 critical, 3 high) and the design changed before any code existed |
| **R4-C** | **The installer cutover** | router | R2-R ✓ R4 ✓ · R2-W · D-j · D-k | — | Opus — never downgrade | **Blocked — needs 83/83 and a user decision** | — | **Registered by the orchestrator 2026-08-14.** Flip `install.sh` to the Swift binary and retire `src/*.ts`. The commit is already specified in `spec-R4.md`. Two gates on it, and the second is not technical: the parity gate must reach **83 of 83** (it is at 69), and **the user decides**, because this changes the router their own live Claude Code sessions depend on |
| M1 | Mac shell, menu bar, keyboard | mac | F2 ✓ F3 ✓ F4 ✓ | `?only=mac` | Opus | **Merged** `10cad44` | — | 671 tests / 97 suites, lint clean over 205 files. **The FRAME, not the app** — `BoardRegistry.installed` is empty, so all seven destinations render the same placeholder; the boards are M2–M8. Real: three-zone window, sidebar + F2 focus ring, six menus with disabled reasons, keyboard routing, frame restoration, readout via F4's tracker, scroll-edge. Placeholder cannot outlive the boards — failable type, complement test, Release gate reading the list from source. Stopped before its critic: it was running over seven identical placeholders |
| M2 | Activity | mac | M1 ✓ M3 ✓ | `?only=mac&pane=activity` | Opus | **Merged** `c39c891` | — | 822 → merged-tree green. The lint block was real and was cleared by splitting on seams, never by raising a limit. The one test failure at merge time was a wall-clock load flake (`ActivityRecoveryTests.swift:198`), later fixed properly by `ShellTestSupport.waitUntil` |
| M3 | Servers: the breaker board | mac | M1 | `?only=mac&pane=servers` | Opus | Untriaged | — | — |
| M4 | Skills and marketplaces | mac | M1 ✓ M3 ✓ | `?only=mac&pane=skills` | Opus | **Merged** `7a28de8` | — | Relaunched after a 503 capacity death, not resumed — lifeline had the original agent parked and would have put a second writer in the worktree. **The merge found a merge-only defect**: M4 added `skills()`/`marketplaces()` to `ControlAPIClient` and M2 had written three test doubles against the older protocol, so both branches were green alone and the merged tree would not compile |
| M5 | Discover | mac | M4 ✓ | `?only=mac&pane=discover` | Opus | **Merged** `2a81c87` | — | The registry board plus the honesty it has to carry — every row declares its source. Found and fixed **D-p**, a data race in `StubHTTP` that had been mislabelled a flake; the label was the dangerous half, because flaky invites re-running until green. Four deferred children M5-a/b/c/d, one of which (**M5-d**, `axkit press` matches `AXRole == AXButton` only) is a harness limit later confirmed independently by M7 |
| M6 | Inbox and pairing (Mac) | mac | M5 ✓ | `?only=mac&pane=inbox`, `?sheet=pair` | Opus | **Merged** `6b3e940` | — | **The eighth and last board. `installed == Set(Destination.allCases)`, `scaffolded` is derived rather than listed, so it is empty by construction and the `isn't built yet` pane is unreachable.** Merged-tree gates re-run by the orchestrator: lint **0 / 356 files**, **1143 tests / 145 suites**, `BUILD SUCCEEDED`, acceptance **20 passed 0 failed** with the app never frontmost. Parity **not** run green (exit 2, `pool` needs `npm install`) — accepted only because M6's diff over `RouterCore`, `MCPRouterCLI` and `src/` is **empty**, verified rather than taken on report. **Eight tripwires, none deleted** — the brief named seven, M6 found an eighth; three moved off `ScaffoldedDestination(x) == nil`, which goes vacuous once nothing is scaffolded, onto `!BoardRegistry.scaffolded.contains(x)`. Critic AMEND, 10/10 accepted: the load-bearing one is **an `Undo` that undid neither half of what it named** — it restored an accepted row while the server stayed installed. **Two defects the critic missed**, both invisible to build, lint and a green suite: the failed pane blamed the router for this Mac's own storage failure, and a queued row announced itself as a button, answered `AXPress` with `.success`, and did nothing. One mutation **survived** its first form because the seam was private — missing coverage, not a weak assertion |
| M7 | Evals and Cleanup | mac | M3 ✓ M4 ✓ | `?pane=evals`, `?pane=cleanup` | Opus | **Merged** `85d8331` | — | Two boards in one item, taking `installed` to **seven of eight**. Merged-tree gates re-run by the orchestrator: lint **0 / 336 files**, **1073 tests / 137 suites**, **358 parity**, `BUILD SUCCEEDED`, acceptance **16 passed 0 failed** with Proctor frontmost throughout. Eight mutations red-green. Phase D critic REJECTed (11 raised · 3 fixed · 2 → M12 · 1 hedge removed · 5 rejected with citation). Unified three acceptance registry readers into `scripts/acceptance/board-registry.sh`, fixing a latent `head -1` that would have blocked on a second board. **Declared, not fixed: `mac-shell.sh` exits 1 at A22 on this branch AND on main** → **M11** |
| M8 | Settings, popover, quarantine | mac | M3 ✓ | `?pane=settings`, `?popover=1`, `?sheet=held` | Opus | **Merged** `affaed6` | — | Settings pane, the menu-bar status item and popover, and the quarantine sheet. `command`/`args`/`env` stay unwritable through the control API PATCH — now enforced as a Swift test rather than as a convention |
| **M11** | **Regenerate the M1 command inventory** | mac | M1 ✓ M3 ✓ M4 ✓ | — | Opus | **Merged (partial)** `2a434b9` | — | **The brief's premise was half wrong and the wrong half was a live product defect.** The orchestrator asserted the app *correctly* had `Add server…` enabled — an inference from reading `availability(in:)`, never a measurement. M11 measured the built app: `Add server…`, `Add marketplace…` and `Find` rendered **`enabled=0` with an EMPTY `AXHelp`** — dimmed **and** silent, permanently unusable with no explanation, **since M3**. `CommandItem` computed `.disabled()` from the `.none` shorthand while `ShellMenuReasons` wrote the help tag from the live context. **The inventory was deliberately NOT regenerated**: its column means the `.none` answer, a green test pins it, and rewriting it would have reddened a correct table — the derivation went into the **gate**, which now compiles `MenuCommand.swift` and asks `availability(in:)` with the real registry, so it cannot rot when a board ships. **A22 green**; lint 0/383, 1234 tests, both mac builds. `MenuCommand.swift` byte-identical to main — the rule was right. **Still exits 1 at A34** → **M13** |
| I1 | iPhone shell and pairing | ios | F2 ✓ F3 ✓ | `?only=phone&pairing=1` | Opus | **Merged** `d582d43` | — | 566 tests / 86 suites · 12 iOS tests on ONE reused simulator · 6 red-green mutations · fixed two `try?` sites swallowing Keychain failures (a refused save rendered "Paired." while nothing was written) · Phase D critic 8/6 caught `PhoneStorageFailureTests.swift` **untracked** — the fix would have shipped with no tests while `make test` still rose · unblocks I2 |
| I2 | iPhone Discover and detail | ios | I1 ✓ | `?only=phone&tab=discover` | Opus | **Merged** `ba139d4` | — | Resumed, not restarted: two runs died on 503 capacity and 4,911 lines survived as orchestrator rescues on a branch **37 commits stale**, whose raw diff read as deleting M5/M7/M8's merged work. Rebased twice, both clean. Merged-tree gates: lint **0 / 382 files**, **1230 tests / 152 suites**, **test-ios 23 tests `TEST SUCCEEDED`** on one reused simulator, **358 parity**, `BUILD SUCCEEDED`, acceptance 11 assertions over Discover and detail only. **No merge-only defect** although M6 rewrote the shared test support and five tripwires in the same window. Critic **REJECT**, 16 findings, 14 fixed in code and 2 in docs; all three HIGHs real, incl. copy rendering **"…changed in the last Any time days"** with a reset action that did nothing, and `isBandEmptyWithinResults` proven in the Kit suite while **nothing called it**. The critic also found **a guard blind to its own defect class**: `stripped()` removed string literals before the source scan ran, and the one logic-bearing file was exempted by name with no reason |
| I3 | iPhone Triage, Queue, Library | ios | I1 ✓ I2 ✓ | `?only=phone&tab=triage` | Opus | **Merged** `b50aa8d` | — | **The phone is complete.** Merged-tree gates: lint **0 / 433 files**, **1350 tests / 166 suites**, **test-ios 28 `TEST SUCCEEDED`**, 358 parity, `BUILD SUCCEEDED`, acceptance 5 assertions over its three surfaces only. **The inherited state was the story**: the branch arrived with ~3,800 lines of Phase A/B/C code and **1233 tests against main's 1234 — a net loss of one**; the plan's eight mutations each named the assertion that should kill them and most had never been written, so the first real work was building the proof layer. **8 defects found — 3 by the critic, 4 by the new tests, 1 live in shipped code**: `CapabilitySummary` took attention severity from `CapabilityPlate`, firing the attention colour on **every Smithery entry**, a majority of the corpus and exactly the noise A6 exists to prevent. Critic **AMEND** 18 findings (15 fixed, 2 rejected with citation, 1 registered) — three user-visible falsehoods incl. **the Queue's Undo not undoing, M6's exact defect one item later**, and **six of its own gates that could not fail**. Interaction is a **checklist**, with the commit bar absent rather than disabled; the three rejected patterns all share "the act happens where the affordance was not visible", so **A1 is asserted negatively and structurally** — verified independently at merge: no `DragGesture`/`swipeActions`/`onDrag`/`gesture(` anywhere under `Phone/` |
| **P1** | **Make the two auth routes reachable** | router | R3 ✓ R5 ✓ | — | Opus | **Merged** `496f88c` | — | `D-j` + `D-r2r-c`. **control-differential 49+2-known-defect → 53 of 53** against the running reference. Parity **72/82 → 73/83**, so **the DENOMINATOR MOVED and R4-C's target is now 83/83**. Merged-tree gates: lint **0 / 438**, **1379 tests / 169 suites**. Caught **the fleet's third merge-only break** — V1 tightened `ControlDeps.fileSystem` mid-flight, both branches green alone, merged tree would not compile. Declined to flip `install-launchd-watch`: unstable on **both** binaries over six runs (agreed 1 in 6, losing side alternating) → `D-p1-e`, and **deliberately not called "flaky"**, which was the `D-p` mistake. Two mutation defects found in the mutations themselves: one **could not** have reddened and was re-aimed rather than swapped, and one reported **11/11 green against a stale binary** |
| **M13** | **The scroll-edge separator, A34** | mac | M1 ✓ M6 ✓ M11 ✓ | — | Opus | **Merged** `08b9bdf` | — | **The item inverted itself: the separator is correct and the CHECK was wrong, and NO APP SOURCE CHANGED.** `#2F2F2F` is `--line` (#FFF @7.5%) over `--ground` #1E1E1E — 0.075·255 + 0.925·30 = 46.875 = 0x2F — so the check was reporting the separator's own colour and calling it content. Per-pixel alpha recovers **0.0756 scrolled, 0.0000 at rest**, verified by the orchestrator after a clean rebuild (32 oks). **The orchestrator's own predicted mechanism was false** and the runner said so: `boardsThatScrollThemselves = [.activity]`, so Servers needed no move. Both mutations red. Two grok passes killed its first design and found two false-reds it had shipped (a white-only solver reads nothing on the light ground; a hard-coded 2× scale) |
| **V1** | **Re-run the out-of-family review on the router items** | review | R3 ✓ R2-W ✓ | — | Opus | **Merged** `29af3eb` | — | Owner's note overrode the lane: **grok-4.6 at high, no downgrade**, model verified per run from the JSON envelope (`modelUsage: grok-4.6-build`). **21 findings, all dispositioned, NONE rejected** — and that ratio is the finding, because R3's Phase D critic never ran at all, so no independent reader had ever read its shipped code. **9 fixed red-green**, incl. three trapping `Int` conversions on file-sourced numbers (measured `signal 5, Fatal error: Double value cannot be converted to Int`), `control.token`/`servers.json` written at the umask default where the reference uses `0600`, and the watcher resolving **two different homes** so a scratch `$HOME` still hit the developer's real directory. **Lane trap found and worth the item: grok exits 0 when session init fails** — the first dispatch of both reviews returned exit 0 carrying only an error payload, so a gate keyed on `$?` would have recorded two reviews that never ran. Merged-tree gates: lint **0 / 434 files**, **1362 tests / 167 suites**, `BUILD SUCCEEDED` |
| **P2** | **The `import` verb writes to the developer's own home** | router | R2-R ✓ R2-W ✓ | — | Opus | **Merged** `95d16f9` | — | Three rows blocked → proven (`div-r1-d3`, `install-import-servers`, `install-claude-json`), all blocked by one defect: `NSHomeDirectory()` ignores `$HOME`, so measuring them would have rewritten the developer's real `~/.claude.json`. **A live security defect found and fixed on the way**: `servers.json` was written at the umask default where the reference passes `{mode: 0o600}` — the file holding every server's API keys. Its M4/M5/M6 mutation triple exists because `fileExists ? .fixed(0o644) : .fixed(0o600)` passes the first two while widening a 0600 config on every import. The `install-claude-json` lane **extracts the node -e body from docs/install.sh at run time** rather than retyping it, because a retyped oracle drifts silently. Parity 74 → 77 of 83. **One deliberate deviation from the brief, flagged not buried, and accepted**: it did NOT lock `~/.claude.json`, because that lock would exclude nothing (Claude Code will never take it, the watcher's rewrite is unlocked by `D-v1f`, nothing in the app writes it) while leaving a permanent lockfile in the user's home |
| P3 | Oracles for the usage stream and registry search | router | R3 ✓ | — | Opus | Wave 2 | — | `D-l` + `D-m`. Both are oracle problems, not implementation gaps. **An accepted-as-uncomparable row is a legitimate outcome; a quietly passing one is not** |
| **P4** | **Derive the manifest rows, and the directory-dependent normaliser** | harness | R4 ✓ | — | Opus | **Merged** `8686fd6` | — | **D-o is dead, and the fix is not the one the brief proposed.** Widening the character class was **rejected with a reason**: the path rules run first, so `[^"]+` would have rewritten a whole-cwd regression through to `<project>` and hidden it. Instead `project` is no longer matched by shape at all — it is checked against its own contract (equals `basename(cwd)` of its own object, non-empty), which is the reference's actual rule at `usage.ts:305`. **Verified by the orchestrator in the direction that matters**: every parity group reads byte-identical between the hyphenated repo root and a non-hyphenated worktree, including `fixture` at 23 of 24, the group D-o corrupted. That rewrite exposed a **second, blind defect no test had reported**: the `projectNames` rule split an array of OBJECTS on their internal commas and substituted `<project>` for the `calls` count, so a per-project count of 1 and of 900 normalised identically — it never failed because it mangled both sides the same way. **D-n closed for all 83 rows, up from 39**: four row deletions each exited 0 while reporting 82. Parity 73 → 74, denominator unmoved. **The pin is kept, and that was the orchestrator's call** — one line in a diff is the right price for closing a class where the number improves by losing work |
| G1 | Stop the checks blaming the app for being out of date | harness | M11 ✓ I3 ✓ | — | Opus | Wave 2 | — | Measured 2026-08-15: **seven of eight checks red on a clean main, six green after a rebuild with no source change.** Sequenced after P1/P4 because all three touch `scripts/acceptance/` |
| D2 | Deferred register: Mac surfaces and design authority | mac | M13 | — | Opus | Wave 2 | — | 14 children. Three are **shared-surface changes individual runners declined to make alone** (`M9`, `M10`, `D-f`), which is why they are batched here rather than forced on a runner |
| D1 | Deferred register: router side | router | P1 P2 P3 P4 | — | Opus | Wave 3 | — | 12 children. `D-g` and `D-r2r-b` both move parity rows, so they follow the parity items rather than racing them on the same files |
| I4 | Let the phone install directly | ios | I3 ✓ D-m6-a | — | Opus | Wave 3 | — | Owner's own choice, **against the shipped queue-only default and with the threat-model consequence shown and accepted**. Absorbs `D-m6-a`: the pairing round trip has never been proven end to end, and direct install cannot be built on an unproven transport |
| D3 | Deferred register: phone copy and the harness limit | ios | I3 ✓ | — | Opus | Wave 3 | — | 4 children. Two are **spec-level** (`D-i3-g`, `D-i3-h`) and want the owner's word on the copy before the code changes |
| **R4-C** | **The installer cutover** | router | P1 P2 P3 P4 · **83/83** | — | Opus — never downgrade | **Wave 4 — last** | — | The owner chose `finish-first`, so the switch is licensed **only once parity reads 83 of 83**. Currently 71 from the repo root. Flips `install.sh` to the Swift binary and retires `src/*.ts` |
| — | **BLOCKED: the Apple developer identity** | — | — | — | — | **Needs input** | — | `apple-identity` came back `as-found`: pre-selected by the page, never confirmed, and flagged `blocksAutomation`. **Not scheduled.** Its note points at a 1Password vault, and the bundle id it supplies is domain-shaped rather than reverse-DNS and conflicts with the assumed one. Holds signing, the phone leaving the simulator, and `D-e` |

**Mock note:** every item's mock is a deep link into the single interactive
`design/mocks/prototype.html`, not a separate file. `design/mocks/mac-surfaces.html` and
`ios-surfaces.html` are superseded static contact sheets — do not build from them; they
are pending deletion.

---

## Deferred children — registered, not yet scheduled

Reported by wave-1/2 runners. Each names the item that should absorb it; none blocks a wave.

| # | Child | Absorbed by | Why it was deferred |
|---|---|---|---|
| D-a | Record the HTTP status alongside each recorded fixture | R4 | The fixture set proves the *body* decodes; the status is a second assertion the parity harness will want and the client currently infers |
| D-b | Surface the call-log stream's skipped-record count | M2 | The stream already skips an unreadable record "not silently"; nothing yet displays the count, so a lossy stream looks clean |
| D-c | Expose `usage(limit:server:cwd:)` in Activity's filters | M2 | The client takes all three filters; the Activity mock only offers server |
| D-d | Make the router's caller attribution deterministic rather than `lsof`-raced | R3 | F3's fixture capture raced the async lookup and recorded an unattributable call. Worked around with a capture-time guard; the router-side fix belongs to whoever owns the control API |
| D-e | Signed/notarized macOS packaging | new item, after M8 | Blocked on **Needs input #1**, not on code |
| D-f | Machine-readable token block in `DESIGN.md` | M1 | F2's parity gate parses prose tables today; a fenced block would make it robust to editing |
| D-g | Parity vectors for divergences D1/D3/D4 | R4 | R1 recorded three deliberate divergences from the TypeScript router with **no parity vector**. R4 must not read their absence as agreement |
| D-h | Rename `callsServed` to what it measures, across router, control API, client and surfaces | R4-C | R2 D6 — it is an *acquisition* counter, not a served-call count. Wire-visible, so F3 and the Mac surfaces move together with it |
| D-i | Fix the lost router restart in the TypeScript watcher | — | R2 D7 — a latent bug in the **reference**: an adopted server can never reach the running router. Declared so the Swift watcher does not reproduce it |
| D-j | Wire `AuthRoutes.approve` and `AuthRoutes.authStart` into `ControlHandler`'s dispatch | R3 | Both implemented, both unreachable over the wire, both answering 405 where the reference answers 409/400. **Blocks 2 parity rows.** Fixing it also retires `control-differential.sh`'s stale known-defect assertions in the same change (`D-r2r-c`), or the gate goes red on a *fixed* defect |
| D-k | Swift implementations of the remaining CLI verbs | R2-R ✓ / R4-C | `serve watch import index refresh status tools auth usage help`. R2-R shipped the CLI and proved 8 of 10; `import` and the `~/.claude.json` rewrite remain. **Blocks 3 parity rows** |
| D-l | An SSE differential for `GET /usage/stream` | R4 | The body is an open stream, so there is no byte oracle. Framing agreement is not body parity. **Blocks 1 parity row** |
| D-m | A recorded oracle for `registry/search` | — | The reference calls live registries; two runs a second apart differ. Either record a fixture-server registry or accept the route as permanently uncomparable. **Blocks 2 parity rows** |
| D-n | Derive the `cli` and `mcp` manifest rows from source | R4 | `src/index.ts`'s ten `case` arms and `src/router.ts`'s endpoints are mechanically extractable. Until they are, **42 of 82 rows are hand-maintained and deleting one raises the coverage figure** — the gate's own worst failure mode |
| D-r2r-a | `mcp-router tools` has no empty state | R4-C | `DESIGN.md` §5 wants one sentence and one action; the reference has no empty branch, so adding it is a *divergence* on an owned row until the cutover happens |
| D-r2r-b | The control API has never been compared **over a socket** | R4 | `control-differential.sh` drives `ControlDiff`, an in-process oracle. R2-R made `ControlHandler` reachable over a socket for the first time and **that surface has no lane** — 11 `control` rows are proven against an oracle that is not the wire |
| D-r2r-c | Retire the stale known-defect assertions when D-j lands | D-j | Same change or the gate reports a failure *because* the defect was fixed |
| **D-p** | ~~`RegistryEnrichmentTests` is flaky~~ — **CLOSED `1cb3fd7`, and the label was wrong** | — | **It was a data race, not a flake.** `StubHTTP` is `@unchecked Sendable` with a plain `var requested: [String]` appended from `get()`, and `Registry.search` queries the official and smithery registries **concurrently** — two tasks appending to one array unsynchronised, under an annotation promising exactly the safety the class lacked. A lost append presents as *"that URL was never requested"*. Fixed with an `NSLock` (scoped `withLock`; `lock()`/`unlock()` are unavailable from `get()`'s async context). **Filing it as "flaky" was the mistake worth remembering**: flaky invites re-running until green, which would have hidden a real race forever. 8 consecutive full-suite runs, 8 green |
| **D-o** | **The fixture lane's project normaliser drops any project name containing a hyphen** | R4 | `parity-fixture.sh:121` normalises with `"project":"[A-Za-z0-9]+"` — **no `-`, no `_`**. Project attribution is the directory a call came from, so the gate's verdict depends on the *name of the directory it is run from*. Proven: `F3` and `R2R` normalise, `mcp-router` and `my_project` do not. From `.worktrees/R2R` the gate reports **69 of 82, 0 DIVERGED**; from the repo root, on the identical tree, **68 of 82, 1 DIVERGED** (`fixture usage`, `recorded="<project>" live="mcp-router"`). Every runner works in a worktree named alphanumerically, so no runner can hit it — which is why it survived R4's three adversarial reviews and R2-R's re-measure. **The cutover decision will be taken from the repo root**, where the false DIVERGED is what a reader sees. Fix is the character class; the orchestrator did not apply it because it moves the coverage number *up* and that diff should be reviewed by someone who does not benefit from it |
| **M9** | **Rename the `Evals` destination to `Checks`** | M1, M7 | M7's residual objection, which it could not fix from inside. Every *reading* on both panes is an observation with its input beside it and the vocabulary carries no grading verb — but the word `Evals` in the sidebar, window title, menu and deep link still says "test results". `Destination.title` is a merged shared surface, and a runner editing one unilaterally is how a shared surface stops being shared. M7 filed it rather than took it |
| M10 | Amend `DESIGN.md` §6:279–280 | M7 | Its mandated "not evaluated" skill string describes a state that no longer exists. `DESIGN.md` is authoritative and merged; F2's parity gate tests tokens *against* it, so it and the code cannot drift — which is exactly why a runner does not amend it alone |
| ~~M11~~ | ~~Regenerate `spec-M1.md`'s command inventory~~ | — | **Promoted to a ledger item and merged `2a434b9`.** Its A22 half is closed; what it uncovered is now **M13** (the A34 scroll edge) and **D-m11-a** (the freshness check that blocks after a rebase) |
| M12 | Staleness and an as-of time inside a destructive dialog | M7 | M7's Phase D findings 4 and 8, both VALID. A `.stale` reading is shown in the present tense with no marker, and calls accruing between load and POST are discarded uncounted — so the figure is a lower bound presented as a count |
| **M5-a** | Router-side registry snapshot store, and the trending band it makes possible | R3 (control), M5 | The only honest route to a velocity figure: the router is the process that runs continuously. Until it exists the Discover footer names the absence rather than inventing a number |
| M5-b | Registry search for skills and marketplaces | M4, M5 | The prototype's Servers/Skills toggle has no endpoint behind it. Needs a router route before any UI |
| M5-c | GitHub token in settings, to lift star coverage | M8, M5 | `GITHUB_TOKEN` raises the unauthenticated 60/hour limit; the footer currently just explains the shortfall |
| **M5-d** | **An `axkit` verb that can press a non-`AXButton` role** | — | A harness limit, not a product gap. `axkit press` matches `AXRole == "AXButton"` only, so no rendered pass can drive a segmented filter. Raised by M5, predicted to hit M7's two boards, and it did — M7 confirmed it and declared it rather than faking a press |
| R6 | Router-side behavioural eval runner — **servers only** | R3, R4 | The router can start a server and call a tool; it cannot execute a skill. A runner promising both would promise something the product does not do |
| R7 | Skills write endpoint (remove/disable) with preconditions and undo | R3 | Cleanup lists absent skills and can offer no action on them, because the control API is read-only for skills. M7's A16 asserts that gap rather than hiding it |
| R8 | Server soft-delete with a restore endpoint | R3 | Removal is irreversible today, which is why it needs a named-consequence dialog |
| **M13** | **The scroll-edge separator, A34** | mac | M1 ✓ M6 ✓ M11 ✓ | — | Opus | **Merged** `08b9bdf` | — | **The item inverted itself: the separator is correct and the CHECK was wrong, and NO APP SOURCE CHANGED.** `#2F2F2F` is `--line` (#FFF @7.5%) over `--ground` #1E1E1E — 0.075·255 + 0.925·30 = 46.875 = 0x2F — so the check was reporting the separator's own colour and calling it content. Per-pixel alpha recovers **0.0756 scrolled, 0.0000 at rest**, verified by the orchestrator after a clean rebuild (32 oks). **The orchestrator's own predicted mechanism was false** and the runner said so: `boardsThatScrollThemselves = [.activity]`, so Servers needed no move. Both mutations red. Two grok passes killed its first design and found two false-reds it had shipped (a white-only solver reads nothing on the light ground; a hard-coded 2× scale) |
| D-m11-a | The A22 freshness check blocks after a rebase and cannot be cleared | M13 | M11 added an oracle/binary skew check comparing SOURCE MTIMES against the built app — correct in intent and it caught a real skew. But **a rebase rewrites source mtimes without changing content**, so `xcodebuild` rightly does not relink, the binary keeps its old mtime, and the check blocks forever: the orchestrator hit this immediately, and `make build-mac` exiting 0 does not clear it. Clearing it needs the derived Debug product deleted and a full rebuild. Compare content (a hash of the menu sources baked into the build, or the binary's own build id) rather than mtime — **rebase-then-gate is the orchestrator's standard cycle, so an mtime check blocks every merge** |
| D-m11-b | Menu commands render enabled but no-op with the window closed | M1 | M11's critic finding H2, accepted as a finding and deliberately not fixed. With the app running and no window, `@FocusedValue` is nil so the command does nothing. Reverting to `.none` there would falsely claim the surface was never built; the residue is pre-existing for the 16 always-enabled commands and belongs to `ShellCommandRouter` |
| D-w1 | Nothing renders `watch.log` | M2 or M6 | A repeatedly-failing server is **invisible**: the watcher records it and no surface reads it. The adoption protocol is the one part of the product with no window onto it |
| D-w2 | `ImportVerb.swift:22` uses `NSHomeDirectory()` where the reference honours `$HOME` | R4-C | Out of scope for R2-W and currently unreached, because `cli-import` passes `--from`. It diverges the moment anything calls it without one |
| D-w3 | `manifest.json`'s other writers are still unlocked | R3 | R2-W closed the **seconds-wide** window between the watcher and the daemon. The **microsecond** one between R3's and R5's writers remains, and it is the harder half |
| D-i3-g | The Triage commit button says **"Send"** where nothing sends | I3 | The phone queues; the Mac decides. A11 specifies that string **verbatim** and it passed the spec gate, so I3 declined to rewrite it unilaterally. A **spec-level** fix |
| D-i3-h | Decided buckets are the intersection with the current results page | I3 | So the Dismissed empty state claims a durability it does not deliver — dismissals appear to vanish when the page changes. Also spec-level |
| D-i3-a | No phone surface scales with Dynamic Type | — | `TypeToken.font` is a fixed `Font.system(size:weight:)` **shared with every Mac surface**, and `DESIGN.md` §2 fixes the eight sizes deliberately, so this is a shared design decision rather than a bug in any one item. I1's Dynamic Type test **overrides a UIKit trait that measurably never reaches the SwiftUI view** — I3 deliberately did not copy that pattern |
| **D-m6-a** | **Pairing transport: the wave-6 round-trip gate is explicitly NOT met** | I4 | M6 reported this rather than claiming it. The Mac side of pairing exists and the round trip has never been proven end to end against the phone. Folded into **I4**, since direct install cannot be built on an unproven transport |
| D-m6-b | Envelope versioning for the pairing protocol | I4 | No version field, so a phone and a Mac on different builds cannot detect the mismatch; they just misread each other |
| D-m6-c | Rename `ScaffoldPane.swift` | — | The file no longer holds a scaffold; it holds the registry. Five other items’ acceptance scripts read it by name, which is why M6 declined to rename it alone |
| D-m6-d | The popover has no inbox band | M6 | The menu-bar popover is the app’s most visible surface and the one place a queued item should appear without opening the window |
| D-m6-e | An accent-substrate token | M6 | M6 hand-rolled a `0.16` selection alpha where every other row uses the shared `selectionFill`; the fix is a token, not a constant |
| D-m6-f | `CleanupPresentationTests.weakWindowBoundary` | M7 | M7’s merged file, outside M6’s diff. Mechanism recorded, not re-run until green |
| D-m6-g | The readout repaints the whole window once a second | M6 | A cadence problem rather than a correctness one, and the acceptance script works around it by re-walking a fresh element |
| **D-v1a** | **The control API's writes never reach the live process** | R3 | `controlResponse` discards the `deps` it passed `inout`, so a write lands nowhere the running router can see: **`POST /servers` answers 201 and `GET /servers` still lists the old set.** Found by the grok review; **it was in no register**, which is the whole argument for the out-of-family lane |
| D-v1b | The usage debounce is declared and never scheduled | R3 | The timer exists in the type and nothing ever arms it, so every record writes through |
| D-v1c | B52's missing warning | R3 | The clause specifies a warning the code never emits |
| D-v1d | Attribution does not complete inside accept (B68) | R3 | The same class of race F3 hit from the other side; the caller lookup can still finish after the response |
| D-v1e | A `JSToNumber` radix edge | R1 | Diverges from the reference on a narrow input class |
| D-v1f | The watcher's staging rewrite is unlocked | R2-W | **Deliberately left**: it matches the reference's own window, so closing it is a NEW declared divergence and R4's call rather than a fix |
| **D-v1g** | **B23 and B44 are wrong as written** | R4 | Two real divergences are missing from R4's D-table. A divergence absent from the table reads as agreement, which is the parity harness's own worst failure mode |
| **M14** | **A shipped menu tells the user the app is not built** | mac | M1 ✓ M6 ✓ M13 ✓ | — | Opus | **Merged** `7e7ed70` | — | **The diagnosis inverted on measurement, the second item running to do so.** The gate's own text blamed a surviving scaffold; on a clean Release build `ScaffoldCopy` and `ScaffoldedDestination` are **zero** in the bundle, so M6's deletion worked. The single hit **is** `surfaceAbsent`'s live help tag, which has shared that substring with the deleted pane's copy deliberately since M1, and a bytes grep cannot ask about reachability at all. A new `.featureUnbuilt` refusal separates a missing **destination** from an unbuilt **feature**; one substring grep became four derived checks. Merged-tree gates: lint **0 / 438**, **1379 tests**, both Mac builds. **`mac-shell.sh` measured exit 0 / 39 assertions by the runner; the orchestrator's re-run hit `axkit setframe` (line 974, provably outside M14's diff) under load 42.9/64.9/137.9 from two live runners — full green OWED on an idle machine.** Five mutations red-green, **each rebuilt first** (without a rebuild every one reports BLOCKED, not red), incl. one that only bites when the reintroduced symbol is also **referenced**, since unreferenced is dead-stripped. Three grok reviews, all AMEND, all three changed the work; the plan gate found **two mutations that could not have reddened** and both were **re-aimed rather than swapped**. `spec-M1.md` is committed **on the branch** by declared exception: `MenuCommandTests` parses that table as a test oracle, verified at merge |
| D-p1-a | OAuth client behind `AuthTransport` | new item | P1's owner note: must be a NEW item, not R2 (merged) or R4-C |
| D-p1-c | `awaitCompletion` reports a settled flow as absent | R3 | Turns a **successful** auth into a warn with no re-index |
| D-p1-d | `cli-auth` needs a serve-backed row and an OWNED entry | R4 | Comparing it today compares two connection failures agreeing with each other |
| **D-p1-e** | **`install-launchd-watch` is unstable on BOTH binaries** | R4 | Six runs, losing side alternating, agreed 1 in 6, while the control lane read 53/53 every time. **Not filed as flaky** — that label invites re-running until green over a real race |
| D-p1-f | 405 vs 501 | owner | Two grok reviews disagreed; the owner's call |
| D-p1-g | `currentFlow` unset in the daemon | R3 | — |
| D-m13-a | Boards render vertically centred, not top-aligned | D2 | `.frame(minHeight: sidebar*3)` with the default `.center` puts the Servers board **~208pt down the pane**. One word to change and seven boards to re-verify |
| D-m13-b | `SettingsBoard` nests a ScrollView inside the shell's | D2 | `SettingsBoard.swift:70`, absent from `boardsThatScrollThemselves`, which contradicts M2's B41 |
| D-m14-a | Per-command `.featureUnbuilt` copy | M1 | Needs an associated value, which breaks `==` at six sites, or moving reason resolution onto `MenuCommand` |
| D-m14-b | `⌘E` is still bound to a permanently dimmed command | M1 | Pre-existing and inert; it becomes live the day export ships |
| D-m14-c | `Export library…` keeps an ellipsis promising a view that does not exist | M1 | M1 chose the title and `ellipsisRule` pins it, so changing it is M1's call |
| **OWED → G1** | **`mac-shell.sh` cannot launch the app reliably, and blames the window** | G1 | **Discharged as a verification and re-registered as a defect.** Re-run on a quiet machine (load 18–27, none of it this fleet's) and it failed at the FIRST check, `the shell window never appeared` — a different failure from the orchestrator's load-137 run (`axkit setframe`) and from M14's exit 0 / 39 assertions. **Every component proven working in isolation**: `open -g -a` starts the app and the window appears, `swiftc axkit` builds, `axkit dump <pid> window` returns **81 rows, exit 0** against the live window. **Mechanism**: `launch_app` does `pkill; sleep 1; open -g -a` and **never checks `open`'s exit code**, nor waits for the killed process to actually die; when LaunchServices refuses the relaunch (the `-600` M14 saw) no process starts, all 40 poll iterations find no PID, and the harness reports the window absent. A fixed-delay race, same class as `D-p1-e`. **Deliberately not fixed by the orchestrator** — it should not fix a gate it is also reporting — and **not re-run until G1 lands**, because re-running until green is the `D-p` mistake |
| **D-p1-e** → G1 | **`install-launchd-watch` now reports DIVERGED on main** | G1 | Promoted from deferred to blocking. It is `proven` in the manifest, and a proven row whose lane disagrees reports **DIVERGED** — worse than blocked. Main now reads 76 or 77 of 83 depending on the run, and both orchestrator runs had the **reference** as the losing side. P1's recommendation stands: mark it blocked until the lane waits on a launchd observable rather than a fixed delay |
| D-p4-e | `parity-manifest-check.sh` counts one problem as two | G1 | Its counter counts `note` calls and each finding emits a message plus an explanation. Cosmetic, but it inflates a number in a gate whose whole purpose is that numbers are not inflated |
| D-p2-a | Neither Swift writer locks `~/.claude.json` | new item | P2 declined deliberately; see its row |
| D-p2-b | `install.sh` still calls node for the claude.json rewrite | R4-C | `install-claude-json` being green is explicitly **not** evidence that the caller flipped |
| D-p2-c | The import backup's mode | new item | The reference shares the bug |
| D-p2-d | The atomic writer on non-regular files | new item | A consequence of R1-D3 |
| D-p4-a | pool D6 contention | new item | 8/8 isolated reads correct; **not** filed as flaky |
| D-p4-b | A fresh worktree cannot run the parity gate unbuilt | G1 | — |
| D-p4-c | Derive the install rows from source too | new item | — |
| D-p4-d | `spec-R4.md`'s prose D-table lists only D1–D7 | R4-C | `D-v1g` is **stale as written**: `surface.tsv` already carries `div-r3-d1…d5` covering B23/B44, so the defect is in R4's prose and no row is missing |
---

## Needs input — not blocking any wave

| # | Question | Blocks |
|---|---|---|
| 1 | Apple Developer team ID and signing identity for Developer ID + notarization, and the App Store Connect app record for iOS | F1 can build and test unsigned; **release** artifacts for both platforms are blocked until these exist |
| 2 | Bundle identifiers — `app.fledgeling.mcprouter` / `.ios` assumed unless told otherwise | F1, changeable later but noisier after the App Store record exists |
| 3 | The phone currently queues but cannot install, narrowing the original "or the user can remote install them" | I3 ships the narrower behaviour; widening it is a later item, not a change to this fleet |

---

## Changelog

- 2026-08-15 — **Owner answers received and dispositioned** (`mcp-router-status-answers.json`, 6 of 6
  answered, 5 confirmed, 1 as-found, 2 flagged blocksAutomation). Eleven new pipeline items written to
  `planning/features-to-triage/` and the ledger. The pipeline root is **`planning/`, not `docs/`**;
  `docs/` is the published GitHub Pages site and this repo is public.

  | Question | Answer | Origin | Disposition |
  |---|---|---|---|
  | `cutover` | finish-first | own choice | **P1-P4** finish parity to 83/83, then **R4-C** flips. The switch is licensed, but only once the number is complete |
  | `red-checks` | all-three | took the recommendation | **M13** + **G1** |
  | `deferred-plan` | schedule-all | **chose differently** — I recommended picking off the handful that were real gaps | **D1/D2/D3**, all 46 children batched by surface |
  | `review-rerun` | rerun-the-router | took the recommendation, **note qualifies it** | **V1**, on grok-4.6 rather than codex, per the note. Lane probe-verified before scheduling |
  | `phone-install` | allow-install | own choice, against the shipped default | **I4**. Widens the pairing threat model; the page stated that plainly and it was accepted |
  | `apple-identity` | give-me-the-id | **`as-found` — never confirmed**, blocksAutomation | **NOT scheduled.** `BLOCKED-apple-identity.md`. Its note points at a 1Password vault, and the bundle id it gives (`mcp-relay.fledgeling.app`) is domain-shaped rather than reverse-DNS and conflicts with the assumed `app.fledgeling.mcprouter`. Guessing would bake the guess into the signing identity and the App Store record |

  **Also registered: M6's seven deferred children (`D-m6-a` … `D-m6-g`), which M6 reported and nobody
  had written into the table.** That is the same unregistered-child gap that cost R2-R a whole item.
  The register is 46 rows, not 40.

- 2026-08-15 — **Wave M6 + I2 launched** `wf_6527714f-b4a`, two runners. Two, not four: a dAIolog
  runner is live on this machine and the four-wide waves died twice on `503 no-eligible-account`.
  Before launching, `ai/i2` was **rebased off a 37-commit-stale base** — its raw diff against `main`
  read as deleting `spec-M5/M7/M8`, `plan-M8` and four acceptance scripts, which is what a stale
  branch looks like and not what it contained. Clean rebase, 0 conflicts, then measured: the tree
  **does not build** (4 compile errors, 5 lint violations), so its runner inherits a precise failing
  set rather than a claim. Both briefs carry the owner's standing instruction on acceptance —
  **test only the surface you changed, and read `BoardRegistry.installed` before running anything,
  because a pass over a placeholder proves nothing and costs the owner tokens.**

- 2026-08-15 — **M7 merged `85d8331` — seven of eight panes.** The `<<<<<<<` SourceKit reported at
  `ShellTestSupport.swift:161` was a **stale index artefact, not a conflict**: no markers in either
  tree, and line 161 is a comment. Settled by reading both trees rather than by trusting either the
  diagnostic or M7's "tree clean". M7 was 0 behind `main`, so its tree *was* the merged tree; gates
  re-run on it by the orchestrator: lint **0 / 336 files**, **1073 tests / 137 suites**, **358
  parity**, `BUILD SUCCEEDED`. Post-merge re-verified on `main`: 1073 tests, HEAD moved.
  **M11 is a live red gate on `main`** (`mac-shell.sh` exits 1 at A22) and is deliberately NOT being
  fixed now — M6 changes the installed set to 8/8, which would invalidate any inventory regenerated
  today. It is M6's to close, or the orchestrator's immediately after M6 merges.

- 2026-08-15 — **Ledger corrected: five rows (M2, M4, M5, M7, M8) still read `Untriaged`,
  `Blocked on lint` or `Relaunched` after all five had merged.** Each merge SHA re-verified as an
  ancestor of `main` before the row was rewritten. A ledger that disagrees with `git` is worse than
  no ledger, because the fleet plans from it.

- 2026-08-15 — **M5 merged `2a81c87` (five of eight panes) and M8 `affaed6` (four), both under
  one-runner concurrency after four-wide died twice.** M5's merged-tree gates: lint 0 over 313
  files, **1021 tests / 131 suites run three times, three green**, 358 parity, `build-mac` ok, plus
  **32 behavioural assertions** across four fixture scenarios with the app never frontmost.

  **The two M5 findings worth carrying forward are both gates that lie.** A row *claimed*
  `.isButton` and published **no `AXPress`** — accepted-and-inert, so a check keyed on a return code
  passes it because the action genuinely is accepted and simply does nothing. And `declaration` sent
  `command`/`args`/`url` **raw** while the sheet displayed them **sanitised**: display ≠ execution,
  on the one surface whose entire purpose is knowing what will run. Also `missingRequirements` was
  dead code (Add with blank fields sent a credential-less declaration), and the fabricated-field
  grep read four Kit paths and **none of the five files that draw the screen**.

  **A sixth board-registry tripwire exists that git does not mark as a conflict**:
  `ShellIntegrationTests` pins the scaffolded count in a second place outside the conflicted region,
  so M5's rebase was clean and the suite was red anyway. Carried into M7's brief.

- 2026-08-15 — **Two defects were making every runner's gate unreliable; both fixed on main
  (`1cb3fd7`), and one of them I had filed under the wrong diagnosis.**

  **`D-p` was never a flake — it is a data race.** `StubHTTP` is `@unchecked Sendable` with a plain
  `var requested: [String]` appended from `get()`, while `Registry.search` queries the official and
  smithery registries **concurrently**: two tasks appending to one array unsynchronised, under an
  annotation promising exactly the safety the class lacked. A lost append reads as *"that URL was
  never requested"*. **Calling it flaky was the dangerous part** — flaky invites re-running until
  green, which would have preserved a real race indefinitely. Fixed with `NSLock`, scoped
  `withLock` because `lock()`/`unlock()` are unavailable from `get()`'s async context.

  Separately, M8's `pollingIsIdempotent` and its sibling slept a fixed 120ms then asserted a poll
  had run — 5/5 in isolation, **~4 failures in 5 under full-suite load** as M5 measured. Replaced
  with `ShellTestSupport.waitUntil`, which is also *faster* when healthy. `ShellTests`'
  `loadingIsTheAbsenceOfAnAnswer` looks identical and was **left alone deliberately**: it asserts a
  state *stays* put, so there is no condition to wait for and a fixed delay is the right instrument.

  Proof is repetition, not a pass: **8 consecutive full-suite runs, 8 green.** One run proves
  nothing about a race, and the first attempt at this fix did not compile at all — SourceKit's
  async-context warning was real rather than its usual cross-file noise.


- 2026-08-15 — **Capacity returned, the orchestrator took the recovery back from lifeline, and all
  four items relaunched with briefs that describe reality (`wf_997da1e0-2d0`).** A one-word probe
  (`claude -p` → `OK`) confirmed the outage had cleared before anything was spent on a wave.

  **Why take it back rather than let lifeline retry: lifeline replays the ORIGINAL prompt.** M5's,
  M7's and M8's all said `resume: fresh`, and by then M5 had 9 uncommitted files, M7 a design commit,
  and M8 six commits. A lifeline retry would have handed each runner a brief contradicting its own
  worktree. Both old runs were paused first so the two could not race.

  **The WIP rescue declined an hour ago was taken now, and the difference is control of the clock.**
  With lifeline paused and zero live processes verified immediately beforehand, committing is safe;
  while lifeline could fire at any second it was not. Four rescue commits, each labelled as the
  orchestrator's and explicitly **not claimed to compile or pass**: M5 `cf0acdc` (9 files), M7
  `a8169a9`, M8 `c799153`, I2 `e5f7fb5`.

  State the briefs were written from, rather than assumed: **M8** is closest — 6 commits, spec, plan
  and evidence — but its `installed` reads `[.servers, .settings]` because it branched before M4 and
  M2, so **its rebase will conflict on exactly the pair M2 hit an hour ago** and the brief says
  resolve as a union. **M5** is deep in Phase 4 with `.discover` already registered and five new
  files, but *one commit on its branch and that one is mine*, which is why the brief warns it looks
  emptier than it is. **M7** and **I2** both have a spec and no plan — Phase 3. Only M8 and M5 will
  trip the board-registry assertions; both briefs name that as the designed edit and flag the
  `ScaffoldedDestination(.x) != nil` trap that has to be repointed rather than renumbered.

- 2026-08-15 — **Both waves died at once on capacity, not code, and the correct response was to do
  nothing.** All five agents across `wf_67a6b2b6-231` and `wf_4dda644a-0ae` failed within minutes of
  each other on `503 no-eligible-account / over_reserve` (*"9 of 11 accounts at or over their usage
  reserve"*) and `429`. Five simultaneous failures with five different items and one identical cause
  is an outage; nothing here is a defect to diagnose.

  **lifeline already owns the recovery**: M5 and M8 `retrying` on `RATE_LIMIT`, I2 and M7
  `paused-usage-limit` with retry times that have since passed, all at attempt 1 of 30. A
  `resumeFromRunId` would recover nothing anyway — both journals have **results=0**, so replay
  misses on the first call and the miss flag is sticky — and a manual relaunch would cold-start work
  lifeline is holding.

  **Real work survived on all four, and it is deliberately left untouched.** M8 is furthest
  (5 commits), M7 and I2 have their Phase-1 commits, and **M5 has 0 commits and 9 uncommitted files**
  including `ShellModel`, `ShellWindow` and `ScaffoldPane`. The temptation is a WIP rescue commit,
  and it was declined: uncommitted files in a worktree are lost only to a hard reset or a worktree
  removal, neither of which happens on its own, whereas committing into a worktree whose runner
  lifeline may resume *at any second* is the two-writer hazard that has already bitten this fleet
  four times. **The exposure is hypothetical; the collision would be real.**

  I2's resume from the previous wave did work before the outage: it adopted the inherited 79KB mock
  and committed it as `I2 Phase 1`, which is the judgement its brief asked for rather than the
  assumption it warned against.

- 2026-08-14 — **M2 merged `c39c891`. Three of eight panes are real: `[.servers, .skills, .activity]`.**
  Merged-tree gates: lint **0 violations over 279 files**, **891 tests / 120 suites**, 358 parity
  vectors, `build-mac` succeeded, and **0 code files** differ between the merged tree and the tree
  those numbers were taken on.

  **This merge is the argument for gating the merged tree rather than the branch, and it is no longer
  hypothetical.** M2 and M4 each compiled and passed alone; together they **did not compile at all**.
  M4 added `skills()` and `marketplaces()` to `ControlAPIClient` after M2's three Activity test
  doubles were written, so all three stopped conforming. Three board-registry assertions then failed
  — correctly, since they pin the exact set and count precisely so that a board landing is a
  deliberate edit. One could not simply be renumbered: `ScaffoldedDestination(.skills) != nil`, named
  *"a scaffolded destination still builds one"*, lost its subject the moment M4 installed Skills, and
  fixing the counts around it would have left a test that no longer tested what it said.

  **A false alarm worth recording, because the trap is general.** M2's uncommitted delta removed
  seven `@Test` cases and added none — including the `BoardRegistry` complement guard — which is
  indistinguishable from a suite going green by deleting its assertions. It was not: those seven had
  already been *copied* into `ActivityBoardContractTests.swift` in an earlier commit, and removing
  the duplicates completes the move. So **822 is the honest count and 829 was double-counting**. The
  rule: *a working-tree diff cannot show a move whose other half is already committed*, and it
  renders identically to a deletion. Settle it by grepping both files at HEAD, never by reading the
  delta.

- 2026-08-14 — **Wave: M5 and M7 launched (`wf_4dda644a-0ae`), both unblocked by M4's merge, plus
  I2 resumed.** I2 was **dead, not slow** — 63 minutes since its last write, zero commits, and its
  only remaining process was a `python -m http.server` orphaned to PID 1 on port 8931. Its
  predecessor died in Phase 1 leaving one untracked 79KB mock nobody has judged; the brief says so
  rather than implying it is sound. Reaped that orphan; **left M8's two alone because M8 is live**
  and may still be serving a mock. Concurrency 4 with M8.

- 2026-08-14 — **M4 merged `7a28de8`: `BoardRegistry.installed` is `[.servers, .skills]` — two of
  eight panes are real.** M4 never needed resuming. It hit a 503, the harness retried it under a new
  agentId, and the retried agent did the bulk of the work and then stopped **without reporting** —
  the returned-early shape, not the died shape. What it needed was a merge.

  Gates re-run here on the rebased branch and again on the merged tree, deliberately, because
  **this branch stacks commits from two different runners** (a fork of the orchestrator ran an M4
  runner whose brief wrongly said its predecessor had died): lint 0 violations, **819 tests / 113
  suites**, 358 parity vectors, `build-mac` succeeded. Merged tree differs from the branch by
  `ORCHESTRATOR.md` alone — **0 code files** — and was re-gated rather than assumed.

  **The runner's best decision was refusing to fake a rendered pass.** With no accessibility grant
  it did not assert a string and call it proof: it moved inspector item 7's *decision* out of the
  view into `SkillPresentation.autoUpdateItem(for:in:)`, leaving the view a `switch` with no logic,
  and red-green proved both new guards. It also caught its own gate lying — the first `make lint`
  omitted `-C` and linted the **main checkout's 243 files** instead of the worktree's 257 — and
  re-ran it. Declared, not claimed: Empty, Loading, Partial, Offline and Error remain undriven, and
  **inspector item 7 has never been seen rendered by anyone**. That check is now the orchestrator's
  to close, since the interactive session holds the AX grant a runner under a recovered session
  does not.

- 2026-08-14 — **A runner under a lifeline-spawned orchestrator cannot do rendered UI verification,
  and the reason is TCC, not the code.** M4's second pass reported `axkit trusted` → `no` from two
  independently built binaries and correctly refused to fake a rendered pass. Verified from the
  interactive session immediately afterwards: `/tmp/m3-ax/axkit`, `/tmp/m4-pass/axkit` **and a
  freshly built binary all report `trusted` → `yes`**, with `front` → `Ghostty`.

  Both observations are true. The macOS accessibility grant belongs to the **responsible process**,
  and a runner beneath a headless `claude --resume … -p` process that lifeline spawned has a
  different responsible process from one beneath the interactive terminal session. M3 took real AX
  rows earlier because it ran under the terminal; M4 could not because it ran under a recovered
  headless orchestrator. Nothing was misconfigured and **no system permission needs granting.**

  Consequences, in order of usefulness: a rendered pass must run under the interactive session, so
  **the orchestrator can close a runner's blocked rendered check itself** rather than re-dispatching
  it; a runner that reports `axkit trusted: no` has hit this, and should say so and move on rather
  than treat it as its own defect; and `axkit front` keeps answering either way because it reads
  `NSWorkspace` rather than the AX API, so **`front` working is not evidence the grant is present**.

- 2026-08-14 — **Two orchestrators ran this fleet at once, and neither knew until an Edit failed.**
  lifeline (PID 41580) recovered this session by spawning **two** headless
  `--resume <same-session-id> -p "Resume workflow run wf_…"` processes at the same instant — 28866
  and 28892. Both replayed the same transcript, so both believed they were the sole orchestrator,
  and **both committed to `main`** (`0341b42`, `efddb0c`, `a33a7de` from one; `cd3be8d`, `cfb4eda`,
  `eb356df` from the other) and both launched fleet waves.

  **Neither detected it by looking.** One found out when its `Edit` failed with *"File has not been
  read yet"* on a file it had never touched; the other found out from commits in `git log` it had no
  record of making. Resolved by `ListAgents` → `SendMessage`, and 28866 stood down cleanly rather
  than being killed — it handed over its in-flight state, which is the only reason the next two
  facts are known.

  **Attribution between the two is not recoverable and was not worth recovering.** Both sessions
  claim the same commits, because a resumed transcript makes the other's pre-fork work
  indistinguishable from your own. The commits are on `main`, they are correct, and that is the
  part that matters. **Do not spend a turn litigating who wrote what after a fork.**

  What it actually cost: **`ai/m4` carries commits from two different runners.** The sibling's wave
  `wf_60e34389-efe` had an M4 runner that committed `ceeac1e` at 23:08:50; this session's
  `wf_2ff47aa9-981` runner committed `05f5e49` and is still live on top of it. The sibling's runner
  was working from a brief that said its predecessor had died, which was false. **M4's branch must
  be gated on the merged tree with that in mind** — two agents' understanding is stacked in it.

  The guard that held: `.worktrees/M2`'s abandoned split was **measured rather than assumed**. The
  handover recommended deleting three untracked files as half-finished; running them showed 829
  tests in 113 suites, exit 0, and violations down from 5 to 3. They were committed (`138b62c`)
  instead of discarded. *"It looks half-finished"* is a hypothesis, and the test suite is the
  instrument.

- 2026-08-14 — **`planning/watch-fleet.sh` had never run, once, all session (`a33a7de`).** It used
  `declare -A`, which needs bash 4; macOS `/bin/bash` is 3.2 and fails immediately. Every "watcher
  armed" claim this session was false, and the runner deaths it existed to catch were all found by
  hand instead. Now verified the only way that means anything: run it under `/bin/bash` explicitly
  and confirm it is **still alive** when a deadline kills it (exit 142), rather than confirming it
  started. A watcher that exits instantly and a watcher that is quietly watching look identical
  from the outside — which is exactly the failure it was written to detect in other things.

- 2026-08-14 — **`make lint` was hiding half its own output, and it cost two items a turn each
  (`cfb4eda`).** make stops a recipe at the first failing line, so a swiftformat failure meant
  **swiftlint never ran**. R2-R reported its lint clean while 31 violations sat behind a formatting
  failure; M2 reported ready-to-merge with 5 more. The shape is nastier than a silent pass: the
  target *does* exit non-zero, so nothing looks green — it just names one tool's problems and omits
  another's, so a runner fixes what it was shown, re-runs, and meets a fresh set it had no way to
  predict. Now all four linters run and the target fails if any did. Red-green proven both ways:
  green on `main` unchanged at exit 0 with all four running; red with a deliberate swiftformat
  violation gives exit 2 *and* swiftlint still runs, where that count was 0 before.

- 2026-08-14 — **lifeline is the second-writer mechanism, identified (PID 41580).** The daemon at
  `~/Dev/claude-lifeline` recovers a lost agent by **re-dispatching the whole run script**, not the
  one agent, and it labels every item in this fleet `TICKET-123` because it cannot parse item names
  out of the runner prompt. That is the process R2-R caught writing into `.worktrees/R2R` (PID
  24251), and at 22:5x it had **five** `--resume … -p "Resume workflow run wf_"` processes in
  flight, two of them replaying this session's own id.

  A resume instruction for `wf_67a6b2b6-231` arrived and was **declined**: M8's runner is live
  inside that run, so re-dispatching would have put a second `fleet-runner.js` into `.worktrees/M8`
  mid-plan-gate. The rule that follows is `workflow-resume`'s own and it is now load-bearing here —
  **a run with any live agent is never resumed**, whatever asks for it.

  It also had M4's original agent parked at `paused-usage-limit` 1/30, queued to retry into a
  worktree where a freshly-launched M4 was about to work. `lifeline_pause` on that agent is the one
  case pause genuinely covers (it gates retries of failed agents), so that collision was headed off
  rather than discovered afterwards.

- 2026-08-14 — **Capacity, not code, is the binding constraint tonight.** `503 no-eligible-account`
  — *"8 of 10 accounts at or over their usage reserve"* — killed M4 here and is visible in the
  anvil, proctor-mcp and dAIolog fleets simultaneously. Load average **62.7 on 16 cores**. That
  matters for verdicts, not just throughput: M2's one test failure at merge time was
  `completes(within: .seconds(2))`, a wall-clock deadline, missing under an 18.4s suite run that
  normally takes 3.0s. It passes 3/3 in isolation at 0.08s. **A wall-clock deadline in a test is a
  load sensor**, and under a fleet it reports the machine rather than the code.

- 2026-08-14 — **M4 died on capacity, not code; M2 hit a merge-only lint defect; both relaunched.
  M8 and I2 survived the session boundary and were left alone.**

  **M4** was reported lost to a `503 no-eligible-account` from the inference gateway. The disk said
  otherwise: `ai/m4` carries **7 commits**, `.skills` is registered in `BoardRegistry.installed`,
  and `planning/evidence/M4-acceptance.md` is written. It was killed *mid-edit*, leaving an
  uncommitted 5-file delta that is good work and currently broken — it fails to compile
  (`'SkillPresentationStateTests' has no member 'testPluginSkill'`) and pushes a test file to 453
  lines against the 400 cap. Worth keeping because it fixes two real defects: a filter badge
  counting the **unsearched** set, so `Held 1` sat above a list saying nothing was held; and the
  `All` filter with a non-matching search falling through to no message at all, drawing column
  headers over blank space. Relaunched to finish it rather than restart.

  **M2** returned ready-to-merge and its own numbers held on the rebased tree — **822 tests / 111
  suites**, parity 358 — but rebasing onto the R2-R main turned lint red. This is a **merge-only
  defect**: R2-R brought a stricter formatting and lint config, so M2's earlier files fail rules
  that did not exist when they were written. Red on neither branch alone. `make format` fixed three
  files, and — the same trap R2-R documented — that unmasked **5 structural swiftlint violations**
  that had been invisible behind `swiftformat --lint`'s short-circuit. Relaunched as a lint
  close-out with its acceptance evidence explicitly ring-fenced from re-running.

  **Two orchestrator errors worth keeping.** First, I ran `make format` and `make lint` inside M2's
  worktree while my own backgrounded `make build-mac` was still running there, and got
  `** BUILD FAILED **` — `build.db … database is locked. Possibly there are two concurrent builds
  running in the same filesystem location.` A self-inflicted race that reads exactly like "M2 does
  not build". **The orchestrator gates a worktree or a runner owns it, never both at once.**
  Second, `git rebase main` printed *"Current branch ai/m2 is up to date"* while its own reflog
  showed five `rebase (pick)` entries and a `rebase (finish)`. Another case of the word after the
  command not being the verification — ancestry and the reflog are.

  **M8 and I2 are alive** and were not touched. A 45-second no-write probe on their worktrees
  returned nothing, which is a false death signal: both were sitting in adversarial `claude -p`
  spec and plan gates, which think for minutes and write nothing. Liveness was settled by walking
  the gate processes' parents to a live session (PID 92491), not by file mtime.

- 2026-08-14 — **`wf_03c742d3-20a` reported `completed` having lost M4 to a 503, and a workflow
  resume was the wrong instrument.** The run returned 2 of 3: R2-R (merged), M2 (ready-to-merge),
  and **M4 dead** on `API Error: 503 … no-eligible-account, over_reserve` — a death with zero
  retries that the run still reports as completed.

  **The resume was rejected on liveness, not on cache economics.** By `journal started=3 results=2`
  the arithmetic favours a resume: two cached hits, one re-run. But the cache miss flag is sticky,
  and a miss on M2 spawns a *second* M2 runner into its worktree. M2 is demonstrably still working:
  its report names `ai/m2 @ 5d15aff`, **`5d15aff` is not an ancestor of `ai/m2`** (it rebased), the
  branch now contains `cd3be8d` — a ledger commit made minutes ago — and `make test` and
  `make build-mac` are live in `.worktrees/M2`. lifeline reports that agent `done`; the process
  tree and the reflog disagree, and on this repo the process tree has been right every time.
  **A fifth two-writer incident is not worth two cached replays.**

  M4 is **not dead, and the recovery was called off before it started.** Within minutes of the
  paragraph above being written, `ugrep` was running in `.worktrees/M4`, dozens of `swift-frontend`
  processes were seconds old, and the task list moved M4 Phase 4 to completed and Phase 5 to
  in-progress. **The harness retried M4 under a new agentId** — a documented behaviour — so the
  original agent's transcript is frozen at 22:49 forever and lifeline still reports that agent
  `paused-manual` with `lastClass: USAGE_LIMIT`. Both are true statements about a *corpse*, and
  neither is a statement about the item.

  **Agent-keyed state cannot answer "is this item alive".** That is the third time this session
  the two disagreed, and the item-keyed answer was right all three times. `planning/watch-fleet.sh`
  already encodes the fix — liveness per ITEM across transcript, worktree and process cwd — and it
  was consulted last rather than first, which is how a live runner came within one tool call of
  getting a second writer. The order is: process tree and worktree first, journal and lifeline
  second, and never the other way round.

  Net effect: **nothing was resumed and nothing was relaunched.** M2, M4, M8 and I2 are all live
  and untouched, which is the correct outcome of this scan.

- 2026-08-14 — **The parity gate's verdict depends on the name of the directory it is run from
  (`D-o`).** Re-running the gate on merged `main` from the repo root returned **68 of 82 with 1
  DIVERGED**, where R2-R had reported **69 of 82, 0 DIVERGED** on a byte-identical tree. Neither
  number was wrong about the code and neither runner was careless: `parity-fixture.sh:121`
  normalises attributed projects with `"project":"[A-Za-z0-9]+"`, a class that **omits `-` and
  `_`**. A call's project is the directory it came from, so `R2R` normalises and `mcp-router`
  does not, and the `fixture usage` row reports `recorded="<project>" live="mcp-router"`.

  **The reason it survived every review is the interesting part.** Runners work in worktrees named
  `R2R`, `M2`, `I1` — alphanumeric, all of them — so no runner could reach the bug, and R4's three
  adversarial gates and R2-R's independent re-measure all ran from inside one. It is reachable only
  from the repo root, which is exactly where the cutover decision gets taken. A false DIVERGED
  there is worse than a missing row, because the lesson a reader takes from it is to discount
  DIVERGED.

  Registered as `D-o` and **not fixed here**: the diff is one character class and it moves coverage
  *up*, which is the one direction the orchestrator should not move a number it is also reporting.
  It goes to R4 with the mechanism and the proof attached.

- 2026-08-14 — **Twelve unregistered work items found and registered — the R2-R failure repeating,
  seven-fold.** R2-R's evidence groups its 13 blocked parity rows "by the item that would unblock
  them" and names `D-j`, `D-k`, `D-l`, `D-m`, `D-r2r-a/b/c`, `R2-W` and `R4-C`. **Not one of them
  appeared in this ledger or in `LEDGER.md`** — the deferred table stopped at `D-g`, and `D-h`
  through `D-n` lived only inside `spec-R2.md`'s and `plan-R2R.md`'s own tables. `spec-R4.md:68`
  had already written the general form of this down — *"`R2-R` is registered nowhere … the single
  largest missing piece of the Swift router is named only in a deferred table"* — and the same
  thing was true of eleven more items at the moment it said so.

  Two are real work items, now in the ledger rather than in prose: **`R2-W`**, the `~/.claude.json`
  watcher and its adoption protocol — `install.sh` installs a `watch` launchd agent that still runs
  `node dist/index.js` even when `MCPR_ROUTER_BINARY` is set, because there is no Swift watcher to
  point it at — and **`R4-C`**, the cutover itself, blocked on 83/83 *and* on a user decision.

  The one that should worry a future reader most is **`D-n`**: a row missing from `surface.tsv`
  shrinks the denominator, so **deleting a row raises the coverage figure**. That hole is *partly*
  guarded already and the ledger should not overstate it — `scripts/acceptance/parity-manifest-check.sh`
  runs at `parity-gate.sh:49` and derives the **control** and **fixture** rows from source, so a
  deletion there fails the gate. The **43 rows in `cli`, `mcp`, `install`, `divergence`, `pool`,
  `state` and `log` have no such derivation**, and `D-n` covers the two most mechanical of those
  (`src/index.ts`'s ten `case` arms and `src/router.ts`'s endpoints). **`D-r2r-b`** is the same
  shape one level down — 11 `control` rows are proven against `ControlDiff`, an in-process oracle,
  not against the socket R2-R just made reachable.


  The lesson is mechanical, not moral: a deferred child named in a spec is invisible to the fleet.
  Registration is the orchestrator's job and nobody else's, and the check is cheap — grep every
  item id a runner's report mentions against this file before accepting the report.

- 2026-08-14 — **R2-R merged `62678aa`: the router is now a process, and R4's gate went 50/81 → 69
  of 82 with 0 DIVERGED.** The five lanes R4 could not measure at all — `mcp`, `cli`, `install`,
  `state`, `log` — are measurable because the thing they measure now exists. Merged-tree gates were
  re-run here rather than taken on the runner's word: lint **0 violations over 243 files**, **750
  tests / 106 suites**, **358 parity vectors**, and the merged tree is byte-identical to the gated
  tree (`163597f7`), so the numbers describe what landed.

  Three things worth keeping. **The lint fix was structural, never a raised limit** — `RouterService`
  split into composition root / dispatch / collaborators, `MCPEndpoint` split, and
  `StdioUpstreamTransport.open` into spawn + handshake; the honest violation count turned out to be
  **31, not 29**, because swiftformat's own wrapping pushed three more files past the 400-line cap
  after the first pass. **One config change, and it settles a real tool deadlock**: swiftformat's
  `wrapMultilineStatementBraces` and swiftlint's `opening_brace` demand opposite brace positions,
  verified by moving a brace by hand and watching swiftformat put it back — narrowed to
  `opening_brace: ignore_multiline_statement_conditions`. And the runner **hashed the source before
  and after its gate run** and reported the hash, which is what let the merge trust a number
  produced hours earlier.

  **A fourth two-writer incident, and the first one that cost nothing.** A resume of the older run
  `wf_48b3dafa-109` re-dispatched `fleet-runner.js` into `.worktrees/R2R` while R2-R was working,
  creating `AuthVerb.swift` and `StdioUpstreamSession.swift` under it. By merge time that process
  was dead, the worktree was clean, and both files were committed inside R2-R's own history — so the
  gated tree already contained the intruder's work and the gate passed over it. That is luck, not a
  control. **The control is the merged-tree gate**, which is why it is run every time even when the
  branch is already at main's head and the rebase is a no-op.

- 2026-08-14 — **Wave: M8 and I2 launched (`wf_67a6b2b6-231`), and the wave is two items because the
  DAG says two.** M5 and M7 wait on M4, M6 waits on M5, I3 waits on I2 — all still in flight or
  unstarted. Concurrency is 4 with M2 and M4 live. Reclaimed M3's worktree and branch (merged at
  `bf08ecb`, clean, holding only two orphan processes from its finished runner).

- 2026-08-14 — **R4 refused the cutover, and the refusal is the most valuable thing the fleet has
  produced.** Its parity gate exits 1 at **50 of 81 rows**, and the blocked lanes are structural,
  not a matter of effort: `mcp` 0/5, `cli` 0/10, `install` 0/5, `state` and `log` 0/1 each.
  **There is no Swift router process to cut over to.** `RouterCore` is a library; the only
  `NWListener` in it is R5's single-shot OAuth callback; `docs/install.sh` writes launchd agents
  running `node dist/index.js serve`. Verified here independently before acting on it, because it
  invalidates a standing plan.
  The cause: R2 shipped Phases 0–2 and deferred the relay, listener, HTTP clients and composition
  root to **"R2-R" — a name that appeared in R2's plan, in no ledger, and was owned by nobody.**
  Now registered as a first-class item on the critical path, with R4's gate as its acceptance test
  and an explicit instruction not to edit the gate to make it pass.
  All three of R4's reviews rejected its **coverage number**, correctly: it had been 50 of 74 and
  was overstated five ways — a lane recording `blocked` read as proven, group-blind reconciliation,
  `proven-by-suite` counting because a test merely existed, a pool lane naming Swift tests it never
  ran, and a route extractor that saw 15 where there were 16. The denominator rose 71 → 81 once six
  missing rows were added, so **their absence had been inflating the reported coverage.**
- 2026-08-14 — **I1 merged.** 566 tests in 86 suites, 12 iOS tests on one reused simulator. The
  substantive fix was two `try?` sites discarding a Keychain failure: a refused save rendered the
  "Paired." success surface while nothing was written, so the pairing vanished at the next launch
  with nothing having said so. Its in-family Phase D critic caught that
  `PhoneStorageFailureTests.swift` was **untracked** — the fix would have committed with no tests
  while `make test` still reported a rising count.
  Two orchestrator errors worth recording. `git merge -q -F -` with a heredoc silently failed
  (`could not read file '-'`) and a `;` let the "merged" echo print anyway; the tell was the gate
  reporting 456 tests where I1's own count was 566. **A merge is verified by the test count moving
  and HEAD changing, not by the word that follows it.** Separately, backticks inside a `git commit
  -m "…"` were eaten by zsh and dropped a word from R5's pushed merge message — commit messages go
  through a heredoc file, never `-m` with backticks.

- 2026-08-14 — **Four items merged after the fleet was killed and restarted: R2, F4, R3, R5.**
  `main` went `b093122 → a8091bb → aba30bd → e154bae → b7c527c`, each merge gated on the
  **merged** tree rather than the branch. Final state: 456 tests in 68 suites, 358 parity cases,
  lint clean.
  The lost runs were **not resumed**, deliberately. The scanner showed all three as `no-snapshot`
  with results far under started (1-of-3, 0-of-2, 0-of-3), and replay stops at the first miss and
  re-asserts stale results — so a resume would have paid nearly full price *and* carried forward
  claims that were never true. Each item was relaunched instead with a brief handing it what its
  predecessor had actually established, so F4 inherited "M50–M54 killed, M55 survived" rather than
  re-running the gate, and R3 was told to close out rather than rebuild.
  What building for real found, which no double could: R5's `NWListener` exposed a
  **`CheckedContinuation` double-resume in `AuthFlow.cleanup`** — it cleared `current` after two
  awaits, so a callback landing during teardown settled the flow and cleanup then resumed the same
  continuation again, trapping and killing the daemon. Unreachable against the fake, whose `stop()`
  never suspends. R3's differential harness ran the Swift handler against the **running** TypeScript
  router: 32/32 rows, three of which kill the reference (`TypeError`, `URIError`) where Swift
  answers 400.
  Conflict resolved at the R5 rebase exactly as predicted: R3's `coreFiles + controlFiles` structure
  won, R5's auth entry became the first element of `coreFiles`, both assertions kept, and the floor
  ratcheted 352 → 358 — left at 352 the auth corpus could have been deleted without failing.
  **Concurrency cut to 3.** I1's own report named the cause: its iOS build was `Killed: 9` by
  "memory pressure from the concurrent fleet". Five parallel Swift/Xcode builds were thrashing the
  machine, agents died, lifeline retried them, and the retries thrashed it again.
- 2026-08-14 — **The fleet was killed at the user's instruction, and the orchestrator could not do
  it.** Workflow agents are async tasks inside the `claude` process, not child processes. `TaskStop`
  resolves only ids held in the current context and a compaction had wiped them; `lifeline pause`
  gates retries of *failed* agents and does nothing to a healthy one; killing OS processes stopped
  builds that were immediately respawned. The session's own process was the only lever, and it
  exited before the kill landed. **The process tree was the first thing to check and was checked
  last** — three wrong "it's stopped" claims were made before it was.

- 2026-08-14 — **F4 died a second time, and left a mutant in the source.** It ran the
  mutation gate as a background task and polled its output file for a sentinel; the task
  was killed at 14:56:09 without writing one, and the poll never returned because the child
  died with the parent. Mutant **M56** was left applied in `ServerStateTracker.swift`
  (`guard snapshot != lastPublished` rewritten to `if false { return }`) — applied to disk,
  killed before it could run or revert. Since F4 must merge before wave 4, that is
  deliberately-broken code one merge away from `main`. Reverted, the real work committed as
  `ca32ee4`, and F4 relaunched in `wf_196b1c68-865` with the cause named in its brief.
  Inherited by the relaunch rather than re-run: M50–M54 KILLED, **M55 SURVIVED** (a real
  coverage gap — no test observes the notification lost when `register` is deferred into a
  `Task`), M56/M57 never ran. Also flagged: `ai/f4` predates the hooks commit, so its diff
  proposes deleting `planning/hooks/*` and reverting `watch-fleet.sh` — rebase before merge.
- 2026-08-14 — **R5 reported a second writer in its worktree; there wasn't one.** It found
  `Auth/` files it did not recognise, a package resolve it did not remember starting, and a
  subagent citing `FileModeWriting.swift` by path. It stopped rather than raced and committed
  only its own files by explicit pathspec (`0fad8c0`) — exactly right given what it believed.
  Checked before answering, because if it had been right the correct action was to stop:
  across every agent transcript in the session, `.worktrees/R5` has **21 Edit/Write calls,
  all from R5 itself**, four of them the very files it disowned. The resolve was its own
  `swift build`; the subagent was the one plan-gate agent it spawned. Cause is almost
  certainly compaction — 323 entries — which its brief already covers with a re-read rule.
  Told to resume; it owns `ai/r5`.
  Its finding was still worth having: **`DELETE /servers/:name/auth` is already shipped on
  `ai/r3`**, so R5 drops it rather than building a second implementation that can silently
  disagree.
- 2026-08-14 — **Watcher, revision 6: a journalled result no longer retires an item.** R5
  exposed the hole — an orchestrator message resumes a stopped runner, that turn journals a
  result, and the runner then works for another half hour with nothing watching it. Liveness
  alone now decides whether to fire; the result only changes what the event means (`STOPPED`,
  owes a report, versus `QUIET`, probably died). Added a third liveness test ahead of both:
  **a live process whose cwd is inside the worktree**, one `lsof` per pass for all items.
  I1 forced that one — its `xcodebuild` writes DerivedData *outside* the worktree, so 18
  minutes of real compiling read as 18 minutes of nothing to a file-mtime check.
  The proving needed a negative control, because the first red run fired **zero** and that
  looked like a pass: R3, M1 and R5 had all started builds between probes, so the new gate
  suppressed everything and a broken gate would have looked identical. `FLEET_REPO` is now
  overridable purely so it can be pointed somewhere no process can match — under that
  control all 8 items fire, R5 included, and the real repo stays silent.

- 2026-08-14 — **Two R3 runners were editing `ai/r3` at once for ~18 minutes, and I put
  the second one there.** When auth was split out into R5 I relaunched R3 with a corrected
  brief ("auth split out") in a new workflow run — and never stopped the original, which
  was still running the pre-split brief in the run that also carries R5. So one branch had
  two writers, and R5's scope had two owners. Found by accident: the liveness watcher's
  denominator listed R3 in two live runs. Both prompts were read before acting, and the
  ledger's own row (*"Partial — relaunched, auth split out"*) named which one was intended.
  The stale runner was not stoppable by `TaskStop` — workflow-inner agents are not tasks —
  so it was stopped by message, told explicitly not to commit, revert or clean, and to hand
  back findings instead. It had already committed `2a1121e` with `git add -A` four minutes
  earlier, sweeping up the surviving runner's in-flight P6 work.
  **Kept, not reset.** `reset --soft` would leave every file byte-identical, so it buys only
  a more accurate commit message — and it would hand a *live* runner an unexpectedly dirty
  index mid-turn. That is the same live-worktree hazard this fleet already got away with
  once, and attribution is not worth spending it on. The content is entirely in-scope R3
  work on R3's own branch; no `Auth/` sources or OAuth routes reached it, so R5 is
  uncontested. Verified rather than assumed: `git ls-tree` for Auth sources, and
  `ControlHandler` carries only `DELETE /auth` and the 401 path, which are control-surface
  and R3's by right.
  Its stop report was worth more than its code: three further live port defects (all now
  fixed on the branch), B70's cache implemented from the reference's real semantics, the
  parity corpus at 352, a **spec** defect where B69's "never a partial identity" cannot
  coexist with B71's equality-with-the-reference, and a correction retiring a plan-gate
  finding as latent rather than live. All of it forwarded to R5, whose brief carried the
  now-stale 224 floor and the unresolved B69 contradiction.
  Two mechanisms changed. Runners are told a message costs them their turn; the orchestrator
  is told to reply promptly, since a runner awaiting a reply looks exactly like a dead one.
- 2026-08-14 — **The codex lane is down fleet-wide until Aug 20**, reported by the R5
  runner and reproduced here with a one-word probe: an account-level usage limit, past this
  fleet's horizon. The three out-of-family gates now run in-family as adversarially-briefed
  `claude -p` opus-5 reviewers, logged as `codex: usage limit -> claude (downgrade)` in each
  artifact. Recorded in the contract above so in-flight runners see it on their next
  pre-call re-grep — that file is the only kill-switch that reaches a running runner — and
  in `planning/fleet-runner.js` so future launches inherit it.
  The dangerous half: **`codex exec` exits 0 on a usage limit.** Any gate keyed on `$?` would
  have recorded a pass for a review that never ran. Only the log's ERROR line and an empty
  `-o` file distinguish them.
- 2026-08-14 — **The liveness watcher was measuring the wrong thing and reported two false
  deaths.** It keyed on one agent's transcript mtime, so it called M1 quiet at 16m while M1
  was mid-build, and F4 quiet at 24m while F4's gate output was seconds old. Two distinct
  causes, one fix: a transcript is appended when an agent *speaks*, and an agent thirty
  minutes into a `swift build` writes thousands of files and not a byte to it; separately,
  the harness retries under a new agentId, leaving the original's transcript frozen forever
  with no journalled result. Liveness is now judged **per item**, from the newest of every
  agent's transcript *and* the item's worktree (walking the tree, plus `.build/build.db`
  directly, since that one file is touched throughout a compile). Item keying folds a retry
  and its corpse into one row for free.
  Proved both directions before trusting it: silent at real thresholds while M1 and F4 were
  working, and **9 of 9 unfinished items firing** at `FLEET_QUIET=0`. The first red run used
  `FLEET_QUIET=1` and printed only 7 — a transcript written that same second reads as 0s of
  silence, which is not `-lt 1`. A denominator two short is exactly what a coverage hole
  looks like, and it took a second run at 0 to show it was the threshold, not the code.

- 2026-08-14 — **I1 returned early and the fleet read it as delivered.** The runner
  finished Phase 1, wrote a genuinely good design report — 12 sections, 30 phone frames,
  both appearances — and ended its turn. A returned turn is a *success* to the harness, so
  `agent()` journaled a result, nothing retried it, and the item looked complete while no
  spec, no plan and no code existed. Its only artifact sat **untracked** in the worktree,
  one `git clean` from gone.

  This is a different failure from a death and hides better: a dead agent leaves an error,
  this one leaves a good report. The tell was liveness, not output — its transcript stopped
  at 12:43 while the other three were still writing. Worth noting the two adjacent states
  it was distinguished from in the same sweep: R2 looked equally idle on disk but was alive
  inside a 10-minute codex plan gate, and an earlier check reported all four worktrees
  untouched, which was a **broken predicate** (`find -newermt` with a relative time returns
  nothing on BSD find) rather than four idle runners. Uniform zeros are a bug until proven
  otherwise.

  Actions: Phase 1 committed by the orchestrator as `af0234f`; I1 relaunched from Phase 2
  in the same worktree on the same branch, with the failure named in its resume brief; and
  `planning/fleet-runner.js` now carries "finish the whole item in one turn — a phase report
  is not a deliverable", with the instruction that a report naming its own incompleteness is
  recoverable while one that looks finished is not.

- 2026-08-14 — **A runner pushed to `main`, and the instruction against it is now a hook.**
  A wave-3 runner committed `04eac69` ("Ignore .worktrees/") in the shared main checkout and
  pushed it to origin. The change is **correct and kept** — an untracked `.worktrees/` is a
  real hazard, one `git add -A` from the root would commit another branch's whole working
  tree — but it moved the integration branch under a merge sequence that assumes one writer.
  Mid-merge it could have corrupted the tree.

  Every runner prompt already said stop before merge, so the instruction is not the control.
  `.git/hooks/pre-push` now refuses any push without `MCPR_ORCHESTRATOR=1`, proved in both
  directions (refused without, allowed with). Worktrees share the hooks directory, so it
  covers wave 3's in-flight runners too — which matters, because a fleet cannot message its
  own workflow-inner agents. `planning/fleet-runner.js` carries the explicit rule for waves
  4–6. The hook is scaffolding for this run; remove it when the fleet finishes.

- 2026-08-14 — **CI red on the merged main, and the test was wrong rather than the code.**
  `31763577290` failed one assertion: the stream-liveness check timed from *before* the
  connection opened, charging URLSession construction and the TCP handshake to stream
  latency, so a contended runner read 0.52s against a 0.36s bound while streaming
  correctly. Replaced the wall-clock budget with the ordering property the docstring
  already stated — the stub records when it sent its last line, and the first record must
  arrive before that instant. No threshold left to tune. Green on `8e9c689`
  (`31764012564`). The first red-green proof was itself void: `swift test --filter` on the
  *display* name matched nothing and reported `0 tests in 0 suites passed`, which is a gate
  that never ran wearing a pass. Re-proved against the function name.

- 2026-08-14 — **Wave 3 launched: M1, R2, R3, I1.** Four slots. All four wire-verified
  `claude-opus-5` on the first launch.

  That first launch **died whole in 27 seconds** — two runners on `Connection refused`,
  two on `Connection lost mid-response`. Recorded because the signature is easy to
  misread as wave 2's capacity outage and the remedy is opposite: `ps -o etime` showed the
  local gateway had been up **2m07s**, so the launch landed mid-restart. Not capacity, not
  code. Nothing was lost — no worktree, no branch, `started=4 results=0` — so recovery was
  a fresh launch, not `resumeFromRunId`, which would have replayed nothing while
  re-asserting an empty cache. Before relaunching, the lane was proved end to end with a
  real one-token request rather than trusted from `/healthz`: a health flag says the
  process is up, not that a request can obtain an account.

- 2026-08-14 — **Wave 2 cleared: F2, F3 and R1 all merged**, serially, each gated on the
  merged tree rather than on its own branch. `22d1802` → `13825c9` → `c30eac9`; final
  merged tree `make all` exit 0, **237 tests**, `no-raw-design-values: clean`. All three
  worktrees removed and branches deleted, each proved merged by `git branch --merged`
  first. Seven deferred children registered above.

  **The merge found a defect no branch gate could have.** F3 was green on `ai/f3` and red
  the moment it merged: five tests failing on one missing fixture. `.gitignore` carried a
  bare `servers.json` for the router's runtime config, and an unanchored gitignore pattern
  matches at *every* depth — so it silently swallowed
  `app/Sources/MCPRouterKit/Control/Fixtures/servers.json`. The file stayed on disk in the
  author's worktree, which is exactly why its own gate passed. Both runtime-state patterns
  are now anchored (`/servers.json`, `/manifest.json`) and the fixture is committed. This
  is the merge-only defect class again: the break existed on no branch.

  Both merges conflicted in `app/Package.swift` and both were purely additive — F2's
  `MCPRouterUI`/`MCPRouterUITests`, F3's `ControlProbe`, R1's `RouterCore` product,
  `RouterCoreTests` and the exact-pinned MCP SDK. Kept all of them; the SDK stays confined
  to `RouterCore`, which neither app target links, so the kit's no-external-dependencies
  promise still holds for everything the apps compile.

- 2026-08-14 — **A12 met and wave 1's exit gate cleared.** `main` pushed
  (`e5a61ce..e15b31d`, 10 commits) and Swift CI executed for the first time: run
  31747021039, `build-and-test: success`. This is the first verification of F1 that did
  not happen on the authoring machine — every prior green was a warm local toolchain.
  The `pages-build-deployment` run also succeeded and `docs/` was untouched in the diff,
  so mcp-router.fledgeling.app is unaffected.
- 2026-08-14 — **Wave 2 relaunched into the contended pool** at the user's instruction,
  riding lifeline's retries rather than waiting for the `~/Dev/hopper` fleet to finish.
  All three wire-verified `claude-opus-5`; two took 503s within the first minutes and
  backed off, as expected. Each carries a RESUME brief naming its existing worktree and
  branch, forbidding a fresh worktree, and pointing at its pause checkpoint.

- 2026-08-14 — **Wave 2 died on capacity, not code.** All three runners took
  `503 no-eligible-account` — "9 of 11 accounts at or over their usage reserve". The
  gateway pool is shared, and `lifeline` shows **another live fleet in `~/Dev/hopper`**
  with agents in flight. Relaunching into that starves again, so wave 2 is **paused, not
  failed**, and nothing has been discarded.

  The journal reads `started=6 results=0`, so a `resumeFromRunId` would replay **nothing**
  — the recovery is a re-run in the existing worktrees on the existing branches, never a
  fresh start, because all three died LATE:

  | Item | Branch | Gate now | Died at |
  |---|---|---|---|
  | F2 | `ai/f2` (4) | `make test` exit 0, 65 tests, clean | mid Phase-D critic, after two codex lane failures |
  | F3 | `ai/f3` (2) | `make test` exit 0, **93 tests** | entering the red-green proving pass |
  | R1 | `ai/r1` (6) | **RED — does not compile** | mid-write of `VectorRegistry.swift` |

  Orchestrator actions taken while the pool is contended:
  1. **Rescued 52 orphaned files.** F3 died with 28 uncommitted and *nothing* on its
     branch; R1 with 24 and a broken build. Both are now WIP commits, R1's deliberately
     red and labelled as such — losing the files is worse than a red commit on a branch
     that is never merged in that state.
  2. **Wrote pause checkpoints into all three specs**, since no runner survived to write
     its own: exact stopping point, what is on disk, the diagnosed-but-unfixed defect, and
     the next three steps. A resume reads those instead of re-deriving state.
  3. Confirmed each branch's gate independently rather than trusting a report.

  **Resume is blocked on capacity, which is the user's call, not a code fix.**

- 2026-08-14 — **Wave 2 launched: F2, F3, R1.** Three slots.
- 2026-08-14 — **F1 merged as `0924040`.** Verified independently rather than on the
  runner's report: protected files diffed clean (`DESIGN.md`, the ledger, this file,
  `install.sh`, `package.json`, `src/`), `make all` re-run to exit 0 on the **merged**
  tree, and the token-parity gate proved able to fail — changing `DESIGN.md`'s ground
  colour by one digit fails the suite. A gate that cannot fail is not evidence.
  Four things the run surfaced, recorded rather than smoothed over:
  1. **Two runner attempts died and were retried by the harness** before the third
     returned; the journal holds three `started` entries and one `result`. The surviving
     runner correctly read the on-disk work as a resume rather than restarting.
  2. **A runner wrote to this file, which its prompt forbids.** Its content was accurate
     and has been absorbed here, but the edit was reverted and re-authored by the
     orchestrator. Ownership is reasserted at every merge rather than trusted to the
     instruction — that is the control that actually holds.
  3. **A12 (CI) has never executed.** The workflow is delivered and calls the same
     Makefile targets, but nothing is pushed, so wave 1's "CI green" exit gate is
     **not met**. Recorded as unmet, not waived.
  4. **~1,800 lines of the earlier hand-rolled scaffold were deleted** (`ServersView`,
     `DiscoverView`, `ServerDetailView`, `MenuBarView`, `ActivityView`, `CleanupView`,
     `SettingsView`, `RootView`). Consistent with the brief, and recoverable from
     `97d4a55` — M1–M8 may want it as reference.
  Also: `make acceptance` needs an Accessibility grant and fails *safe* (exit 2) without
  one, so on hosted CI it will report blocked rather than green.

- 2026-08-14 — A task notification reported wave 2 stopped with "no completion record"
  and instructed a relaunch with `resumeFromRunId`. **Declined — the premise was false.**
  The scanner reports the run `LIVE · session-alive`, one agent still writing, and F2/F3
  worktrees held by live processes with an active `swift test`. Relaunching would have
  dropped a second set of agents into worktrees already being written to. It would also
  have bought nothing: `started=6 results=0`, so the replay cache is empty and a resume
  cold-starts regardless. The notification's `TICKET-123` is lifeline's placeholder id,
  not one of ours. Six starts against three items = the harness retrying; the recurring
  cause on every agent is a **session/usage limit**, which is throttling this wave rather
  than killing it. Left alone; a tracked waiter is armed for the settle. Journal resolves
  under session `bdb1ad3b`, so nothing is orphaned — but note compaction can mint a new
  session id and silently orphan a journal mid-run, which would break any later resume.
- 2026-08-13 — Fleet size confirmed with the user: **all 18 items**. Runner lane verified
  on the wire (`claude-opus-5`), not merely configured. Wave 1 launched: F1 alone, since
  every other item depends on it. Deviation from the skill's serial pre-triage, stated:
  ids are pre-allocated in the ledger and runners are forbidden from writing LEDGER.md at
  all, which removes the shared-write hazard rather than locking around it.
- 2026-08-13 — Preflight: pipeline rooted at `planning/` (docs/ is the published Pages
  source); practices copied from bella-team-files with the Swift gap recorded; router
  work committed as `2e70229`; `DESIGN.md` authored from the verified prototype tokens;
  18 briefs written; ledger and wave plan built. No fleet slot has started.
