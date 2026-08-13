# LEDGER — MCP Router feature pipeline

Ids are allocated here and nowhere else. Allocation is a read-modify-write on this file:
**one triage at a time**, and any runner creating a child spec takes the ledger lock
first.

| ID | Title | Brief | Spec | Plan | Status |
|---|---|---|---|---|---|
| F1 | Swift workspace, shared kit, three targets | `F1-swift-workspace.md` | — | — | Untriaged |
| F2 | The design system in SwiftUI | `F2-design-system.md` | — | — | Untriaged |
| F3 | Typed control-API client and models | `F3-control-client.md` | — | — | Untriaged |
| R1 | Swift router: core, config, manifest | `R1-router-core.md` | — | — | Untriaged |
| R2 | Swift router: lazy pool, relay, passthrough | `R2-router-pool-relay.md` | — | — | Untriaged |
| R3 | Swift router: control, auth, usage, registry | `R3-router-control-registry.md` | — | — | Untriaged |
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
