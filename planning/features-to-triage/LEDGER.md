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
| M3 | Servers: the breaker board | `M3-servers-board.md` | — | — | Untriaged |
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
| R6 | Children inherit launchd's minimal PATH | `R6-child-process-path.md` | — | — | Untriaged |
| R8 | An upstream that refuses our credentials must say so | `R8-auth-rejection-visible.md` | — | — | **Done** (ai/r8 → main; owner unfroze `src/`, A38 rewritten to guard the reference's existence; Swift half unblocked by R9; parity 82/83 control 16/16 0 diverged; auth gate examined=8 failures=0) |
| R7 | The router's thesis is unmet for every harness but Claude Code | `R7-harness-reconciliation.md` | — | — | Untriaged |
| M15 | Settings becomes its own window | `M15-settings-window.md` | — | — | Untriaged |
| M16 | The Signal Path replaces the Breaker Column | `M16-signal-path.md` | — | — | Untriaged |
| M17 | Four states on every surface, and chrome that follows | `M17-surface-states.md` | — | — | Untriaged |
| M18 | Twelve sheets, and the gate each decision gets | `M18-sheets-and-gates.md` | — | — | Untriaged |
| M19 | The in-app GitHub-flavoured Markdown viewer | `M19-gfm-viewer.md` | — | — | Untriaged |
| M20 | Menu bar, status item, and the notification banner | `M20-menubar-status-notification.md` | — | — | Untriaged |
| M21 | The token layer, the split accent, and `DESIGN.md` | `M21-token-layer-and-design-md.md` | — | — | Untriaged |
| M22 | The Harnesses and Insights boards | `M22-harnesses-and-insights-boards.md` | — | — | Untriaged |
| M23 | The mock-to-SwiftUI conversion contract | `M23-mock-to-swiftui-contract.md` | — | — | Untriaged |
| M24 | The storefront's own artwork — banners and app-style icons | — | — | — | **Done** (ai/m24 → main; design-only, 23 files, all under `design/`) |
| M25 | The controls row, not the columns, set the boards' width | `M25-board-columns-do-not-flex.md` | — | — | **Done** (ai/x4 broke the min-width chain, ai/x5 flexed the two controls rows) |
| M26 | The Checks board and the design's eval board are two surfaces | `M26-checks-board-framing.md` | — | — | **Done** (ai/m26 → main; owner kept the reachability board, mock amended, DEF-031 closed) |
| P7 | `control-auth-post-http` needs a real OAuth client | `P7-auth-post-oauth-client.md` | — | — | **Done** (ai/p7 → main; parity reached 82 of 83) |
| P8 | Make `install-launchd-watch`'s `reran` term attributable | `P8-launchd-watch-attributable.md` | — | — | **Done** (ai/p8 → main; the lane was shown able to go red) |
| R9 | The SDK drops an upstream's message on -32603; the router reads it off the wire | `R9-sdk-drops-upstream-message.md` | — | — | **Done** (ai/r9 → main; DEF-047 closed, 7 tests armed 5-of-7 red, parity 82/83 0 diverged) |
| R10 | `index` prints two counts that disagree, and neither is checked | `R10-index-reports-a-write-that-did-not-land.md` | — | — | Ready for AI |
| X1 | The iOS accessibility-tree harness, and two surfaces still empty | `X1-ios-a11y-harness.md` | — | — | Done (closed by X3's engine fix + the accessibility-frame row oracle; `make test-ios` 36/0) |
| X2 | The iOS on-glass instrument, and the six cases it takes off `n/a` | `X2-ios-on-glass.md` | — | — | **Done** (ai/x2 → main; lane-owned device, six green runs) |
| X3 | The iOS unit lane read an empty accessibility tree because the engine was off | `X3-ios-unit-lane-empty-tree.md` | — | — | Done (DEF-029 closed, armed three ways) |
| X6 | Cleanup's `Read first…`, the half DEF-011 was held open for | — | — | — | **Done** (ai/x6 → main; CASE-0135/0136/0137, nine mutation arms) |
| M27 | The sidebar foot's loopback readout and the child-process label | `M27-sidebar-foot-readout.md` | — | — | **Ready to verify** (`ai/m27` @ `c84ddc8`; both restored, on glass 8 of 8 boards. The mock's `--live` dot deliberately not — and the same argument convicted the count numeral, which was painting `--live` on `0 of 4`. `mac-shell.sh` exit 0, evidence in `planning/evidence/M27-acceptance.md` and `planning/evidence/M27/`) |
| M28 | Five findings that need a decision rather than a runner | `M28-decision-docket.md` | — | — | Needs input (owner) |
| X7 | The campaign's published artifacts under-report what it knows | `X7-campaign-artifacts-underreport.md` | — | — | Untriaged (**upstream**: fledgeling-plugins, not this repo) |
| X8 | Two campaign detectors report findings they cannot support | `X8-detectors-misattribute.md` | — | — | Untriaged (**upstream**: fledgeling-plugins, not this repo) |

| I5 | Prove the phone↔Mac pairing round trip, and stop there | — | — | — | **Merged** `4157bc4` (ORCHESTRATOR.md) |
| I6 | Make Mac approval fast, without moving the boundary | — | — | — | **Merged** `ef4f615` (ORCHESTRATOR.md) |
| M9 | Rename the `Evals` destination to `Checks` | — | — | — | Registered, no branch (ORCHESTRATOR.md deferred register) |
| M10 | Amend `DESIGN.md` §6:279–280 | — | — | — | Registered, no branch (ORCHESTRATOR.md deferred register) |
| M11 | Regenerate the M1 command inventory | — | — | — | **Merged (partial)** `2a434b9` — promoted out of the deferred register |
| M12 | Staleness and an as-of time inside a destructive dialog | — | — | — | Registered, no branch (ORCHESTRATOR.md deferred register) |
| P5 | Close the last three closeable parity rows | — | — | — | **Merged** `e752305` (ORCHESTRATOR.md) |
| P6 | State the owner's cutover target in the gate | — | — | — | **Merged** `05296ea` (ORCHESTRATOR.md) |
| R2-R | Router: the process that actually serves | — | — | — | **Merged** `62678aa` (ORCHESTRATOR.md) |
| R2-W | Router: the `~/.claude.json` watcher and its adoption protocol | — | — | — | **Merged** `8e48a80` (ORCHESTRATOR.md) |
| R4-C | The installer cutover | — | — | — | Blocked — the owner's target is 82 of 83; R4-C1 shipped, R4-C2 held |
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
- **M3 is unresolved rather than open.** Its own row in both files says `Untriaged` with no
  branch, while M7's dependency cell reads `M3 ✓ M4 ✓` and M4–M8 have all merged. Either the
  board shipped inside another item and neither row was updated, or the tick is wrong. Triage
  it before scheduling it; do not assume either reading.

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
- **X7 and X8 cannot be closed from this repository.** Both are defects in `test-campaign`
  0.9.2, which lives in the machine's plugin cache. The vendored submodule carries 0.5.0 and
  does not contain the scripts at all (DEF-057), so a runner in an mcp-router worktree has
  nothing to edit. They are listed here because the campaign found them and the evidence
  should not be lost; closing them means a change pushed to `fledgeling-plugins` and a
  submodule bump.
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
- **The skills the pipeline depends on are vendored.** `.claude/plugins/fledgeling-plugins` is a git
  submodule tracking `main`, so a runner reads `mockup-fidelity`, `mac-craft`, `design-craft` and
  `ux-craft` at a repo-relative path rather than depending on the machine. After a fresh clone:
  `git submodule update --init --recursive`.
- **M15–M22 were allocated together on 2026-08-19** from the interactive mock at
  `design/mcp-router-console.html`. They are UI specification, not defects: each names something
  the mock draws that no earlier brief covers. `design/mcp-router-console-spec.md` carries the
  audit numbers and the list of what the mock specifies rather than measures.
