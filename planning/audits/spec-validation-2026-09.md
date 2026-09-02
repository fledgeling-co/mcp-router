# Specification Validation & Data Provenance Audit — 2026-09

**Audit Target:** `mcp-router` codebase (`app/Sources/`, `app/windows/`, `src/`) vs. `planning/specs/spec-*.md`, `planning/plans/plan-*.md`, and `planning/features-to-triage/*.md`.  
**Auditor Role:** Specification Validation Specialist (`/spec-validation:spec-validation`)  
**Epistemic Standard:** "Renders + schema-valid + tests-pass ≠ REAL". Every claimed-done data field must be traced to the producer function that computes or derives it.

---

## 1. Systemic Pattern

The repository exhibits clear architectural separation between real live producers and debug/test fixtures:
1. **Mac Shell Seam (`ShellClientFactory.swift:57`):**
   - **Release Mode (`#if !DEBUG`):** Unconditionally returns `LiveControlAPIClient` pointing to `http://127.0.0.1:8879` (`shippingEndpoint`). Real HTTP calls derive server states, tools, and configurations.
   - **Debug Mode (`#if DEBUG`):** Driven by `MCPROUTER_SCENARIO`. Allows live loopback targeting via `MCPROUTER_SCENARIO=live` and `MCP_ROUTER_URL`, or deliberate fixture replay (`.populated`, `.empty`, etc.) for acceptance lane photography.
2. **Windows Native WinUI 3 Client (`app/windows/`):**
   - Implements live producers across net8.0 models and client services (`UsageStreamClient.cs` reading SSE streams from `/events`, `LiveControlClient.cs` reading `/servers`). 625 unit and model tests pass on net8.0.
3. **Pairing Seam (`ShellPairingFactory.swift:42`):**
   - **Release Mode:** Returns `NoTransportInboxService()`, honestly acknowledging that local network pairing transport is not built.
   - **Debug Mode:** Supports `FixtureInboxService` for mock storyboard capture. This is the primary unbuilt capability (`DEF-001` / `I5` / `REQ-016`).

---

## 2. Issue Register & Provenance Gaps

| ID | Surface / Subsystem | Issue & Provenance Gap | Tier | Status | Producer / Seam Location |
|---|---|---|---|---|---|
| **GAP-01** | Phone ⇄ Mac/Win Pairing (`I5`) | Network transport protocol unimplemented; falls back to `NoTransportInboxService` in Release and `FixturePairingService` in Debug (`DEF-001`, `REQ-016`) | Tier 1 (High) | OPEN | `app/Sources/MCPRouterUI/Shell/ShellPairingFactory.swift:51` |
| **GAP-02** | Menu Bar Badge (`M34`) | NSMenuItem badge channel has no accessibility plane representation in background app (`BLOCK-0001`, `REQ-028`) | Tier 2 (Med) | OPEN | `planning/test-campaign/cases.json:CASE-0197` |
| **GAP-03** | GET /servers Disclosure (`DEF-070`) | Full stdio upstream argv exposed without redaction over control API | Tier 2 (Med) | OPEN | `app/Sources/RouterCore/Control/RouterEndpoints.swift:84` |
| **GAP-04** | Plugins Submodule (`DEF-057`) | Vendored `fledgeling-plugins` submodule pinned at older test-campaign 0.5.0 | Tier 3 (Low) | OPEN | `.gitmodules:1`, `.claude/plugins/fledgeling-plugins` |

---

## 3. Subsystem Classification Ledger

| Subsystem / Feature | Spec Reference | Status | Classification | Producer Function & File:Line |
|---|---|---|---|---|
| **Router Daemon & Supervision** | `spec-R1.md`–`spec-R7.md` | Shipped | **REAL** | `RouterService.start()`, `ProcessSupervisor.spawn()` in `app/Sources/RouterCore/` |
| **Control HTTP API & Routing** | `spec-R2.md`, `spec-R2R.md` | Shipped | **REAL** | `ControlHTTPHandler.handle()` in `app/Sources/RouterCore/Control/ControlHTTPHandler.swift:45` |
| **Server State Tracking** | `spec-M2.md`, `spec-M3.md` | Shipped | **REAL** | `ServerStateTracker.update()` in `app/Sources/MCPRouterKit/Control/ServerStateTracker.swift:88` |
| **Skills & Profiles Management** | `spec-F1.md`–`spec-F8.md` | Shipped | **REAL** | `DiskSkillRoots.inventory()` in `app/Sources/RouterCore/Profiles/SkillRootInventory.swift:24` |
| **Live SSE Usage Stream** | `spec-M2.md`, `spec-WIN23.md` | Shipped | **REAL** | `ControlEventStream.listen()` in `app/Sources/MCPRouterKit/Control/ControlEventStream.swift:52` & `UsageStreamClient.cs:34` |
| **Windows WinUI 3 Shell** | `spec-WIN3.md`–`spec-WIN23.md` | Shipped | **REAL** | `MCPRouter.Shell.Model` & `UsageStreamClient` in `app/windows/MCPRouter.Shell.Model/` (625 tests pass) |
| **Local Device Pairing Transport** | `spec-I1.md`, `spec-I5.md` | Unbuilt | **MOCK / REFUSAL** | `ShellPairingFactory.choice()` returning `NoTransportInboxService()` in `ShellPairingFactory.swift:51` |

---

## 4. Backlog Intake Status

All identified gaps and defects have dedicated, triage-ready feature briefs registered in `planning/features-to-triage/`:
- `GAP-01` (`DEF-001` / `I5` / `REQ-016`): [planning/features-to-triage/local-network-device-pairing-handshake.md](planning/features-to-triage/local-network-device-pairing-handshake.md) & [phone-pairing-qr-render-and-countdown.md](planning/features-to-triage/phone-pairing-qr-render-and-countdown.md)
- `GAP-02` (`BLOCK-0001` / `M34`): [planning/features-to-triage/M34-the-menu-badge-is-unmeasurable-by-any-lane.md](planning/features-to-triage/M34-the-menu-badge-is-unmeasurable-by-any-lane.md)
- `GAP-03` (`DEF-070`): [planning/features-to-triage/server-profile-export-redaction.md](planning/features-to-triage/server-profile-export-redaction.md)

`planning/brief-target-gate.py` passes with exit code 0 across all 219 briefs in the backlog.
