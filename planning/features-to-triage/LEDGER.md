# LEDGER — MCP Router feature pipeline

Ids are allocated here and nowhere else. Allocation is a read-modify-write on this file:
**one triage at a time**, and any runner creating a child spec takes the ledger lock
first.

| ID | Title | Brief | Spec | Plan | Status |
|---|---|---|---|---|---|
| F1 | Swift workspace, shared kit, three targets | `F1-swift-workspace.md` | `spec-F1.md` | `plan-F1.md` | **Merged** `0924040` |
| F2 | The design system in SwiftUI | `F2-design-system.md` | `spec-F2.md` | `plan-F2.md` | **Merged** `22d1802` |
| F3 | Typed control-API client and models | `F3-control-client.md` | `spec-F3.md` | `plan-F3.md` | **Merged** `13825c9` |
| F4 | ServerStateTracker cannot report failure | `F4-tracker-failure-states.md` | — | — | Untriaged |
| R1 | Swift router: core, config, manifest | `R1-router-core.md` | `spec-R1.md` | `plan-R1.md` | **Merged** `c30eac9` |
| R2 | Swift router: lazy pool, relay, passthrough | `R2-router-pool-relay.md` | — | — | Untriaged |
| R3 | Swift router: control, usage, registry | `R3-router-control-registry.md` | — | — | Untriaged |
| R5 | Swift router: OAuth and the auth routes | `R5-router-auth.md` | — | — | Untriaged |
| R4 | Differential parity harness and cutover | `R4-router-parity-cutover.md` | — | — | Untriaged |
| M1 | Mac window shell, menu bar, keyboard | `M1-mac-shell.md` | — | — | Untriaged |
| M2 | Activity: the live call log | `M2-activity.md` | — | — | Untriaged |
| M3 | Servers: the breaker board | `M3-servers-board.md` | — | — | Untriaged |
| M4 | Skills and marketplaces | `M4-skills.md` | — | — | Untriaged |
| M5 | Discover: the registry | `M5-discover.md` | — | — | Untriaged |
| M6 | Inbox and phone pairing (Mac side) | `M6-inbox-pairing.md` | — | — | Untriaged |
| M7 | Evals and Cleanup | `M7-evals-cleanup.md` | — | — | Untriaged |
| M8 | Settings, menu-bar popover, quarantine | `M8-settings-quarantine.md` | — | — | Untriaged |
| I1 | iPhone: shell and pairing | `I1-ios-shell-pairing.md` | — | — | Untriaged |
| I2 | iPhone: Discover and detail | `I2-ios-discover.md` | — | — | Untriaged |
| I3 | iPhone: Triage, Queue, Library, Settings | `I3-ios-triage.md` | — | — | Untriaged |
| P1 | Make the two auth routes reachable | `P1-auth-routes-reachable.md` | — | — | Untriaged |
| P2 | The `import` verb and the config rewrite | `P2-import-verb.md` | — | — | Untriaged |
| P3 | Oracles for the usage stream and registry search | `P3-stream-and-registry-oracles.md` | — | — | Untriaged |
| P4 | Derive the manifest rows; fix the directory-dependent normaliser | `P4-derive-manifest-rows.md` | — | — | Untriaged |
| M13 | The scroll-edge separator, A34 | `M13-scroll-edge.md` | — | — | Untriaged |
| G1 | Stop the checks blaming the app for being out of date | `G1-gate-hygiene.md` | — | — | Untriaged |
| V1 | Re-run the out-of-family review on the router items (grok) | `V1-outside-review-router.md` | — | — | Untriaged |
| I4 | Let the phone install directly | `I4-phone-direct-install.md` | — | — | Untriaged |
| D1 | Deferred register: router side (12 children) | `D1-deferred-router.md` | — | — | Untriaged |
| D2 | Deferred register: Mac surfaces and design authority (14) | `D2-deferred-mac.md` | — | — | Untriaged |
| D3 | Deferred register: phone copy and the harness limit (4) | `D3-deferred-phone-harness.md` | — | — | Untriaged |
| — | **BLOCKED: the Apple developer identity** | `BLOCKED-apple-identity.md` | — | — | **Needs input — `as-found`, not confirmed** |
| M14 | A shipped menu tells the user the app is not built | `M14-menu-says-not-built.md` | — | — | Untriaged |
| R6 | Children inherit launchd's minimal PATH | `R6-child-process-path.md` | — | — | Untriaged |
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
| P7 | `control-auth-post-http` needs a real OAuth client | `P7-auth-post-oauth-client.md` | — | — | Untriaged |
| P8 | Make `install-launchd-watch`'s `reran` term attributable | `P8-launchd-watch-attributable.md` | — | — | Untriaged |
| X1 | The iOS accessibility-tree harness, and two surfaces still empty | `X1-ios-a11y-harness.md` | — | — | Done (closed by X3's engine fix + the accessibility-frame row oracle; `make test-ios` 36/0) |
| X2 | The iOS on-glass instrument, and the six cases it takes off `n/a` | `X2-ios-on-glass.md` | — | — | In Progress (`ai/x2`) |
| X3 | The iOS unit lane read an empty accessibility tree because the engine was off | `X3-ios-unit-lane-empty-tree.md` | — | — | Done (DEF-029 closed, armed three ways) |

## Allocation notes

- **M9–M12 are unused.** They were never allocated; the M series jumps from M8 to M13. New Mac
  work continues at M24 rather than filling the gap, so an ID never means two things.
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
