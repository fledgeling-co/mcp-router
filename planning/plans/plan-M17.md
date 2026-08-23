# plan-M17 — Four states on every surface, and chrome that follows them

- ID: M17
- Status: Ready for AI
- Category: mac · mock conversion
- Depends on: M1 ✓, M15 ✓, M22 ✓, M23 ✓
- Spec: `planning/specs/spec-M17.md`
- Brief: `planning/features-to-triage/M17-surface-states.md`
- Design of Record: `design/mcp-router-console.html`

---

## 1. Goal and Overview

Ensure all ten primary surfaces across MCP Router (9 boards: Servers, Activity, Skills, Discover, Inbox, Checks, Cleanup, Harnesses, Insights + Settings window) explicitly support all four core UI states: **Ideal**, **Empty**, **Loading**, and **Error** (40 total cells). Each state must carry distinct, per-surface copy, and window chrome (toolbar subtitle, sidebar tallies, and health indicators) must reflect the active surface's state.

---

## 2. Surfaces and the 40-State Matrix

| Surface | Ideal | Empty | Loading | Error |
|---|---|---|---|---|
| **Servers** | Live server cards with jacks | No servers adopted yet | Reading declared servers | Cannot reach the router |
| **Activity** | Live call stream & stats | Nothing has called a tool yet | Loading event stream | The event stream dropped |
| **Harnesses** | Configured harness rows | No AI harnesses found | Probing harness configs | Harness config would not parse |
| **Skills** | Marketplace & installed skills | No skills installed | Updating marketplace indices | Doctor found broken links |
| **Discover** | Browse registry & capabilities | No results for search query | Searching registry indices | Index lookup failed |
| **Inbox** | Queued pairing/arrivals | Nothing is waiting on you | Checking queue | Upstream failed to install |
| **Insights** | Usage analytics & charts | Not enough history yet | Computing usage statistics | Usage store query failed |
| **Checks** | Suite runner & diagnostics | Nothing here ships a check suite | Running check suites | Check suite failed |
| **Cleanup** | Provenance & stale servers | Everything installed has been used | Scanning stale upstreams | Usage store scan failed |
| **Settings** | Configuration panes | Settings unavailable while stopped | Loading configuration | Router returned unrecognised response |

---

## 3. Implementation Plan

### Step 1: Copy Models & Enums
- Standardize or extend `*Copy.swift` files for all 10 surfaces:
  - `ServersBoardCopy`, `ActivityCopy`, `HarnessBoardCopy`, `SkillCopy`, `DiscoverCopy`, `InboxCopy`, `InsightsCopy`, `CheckCopy`, `CleanupCopy`, `SettingsPaneCopy`.
- Guarantee each string is distinct, > 12 characters, and free of placeholder tokens.

### Step 2: View State Binding
- Ensure each board view uses `StateContainer` or its respective model's load/empty/error state to render:
  - Loading skeleton matching content row heights.
  - Empty state with informative guidance and action button where applicable.
  - Error state displaying specific error message, exit codes, or diagnostic logs.

### Step 3: Chrome Adaptations
- Sidebar badge and tallies: hide/dim when a board is empty, unconfigured, or offline rather than showing stale counts.
- Toolbar title & subtitle: reflect active state (e.g. "Connecting...", "Offline", or item count).

### Step 4: Verification & Test Suite
- Add comprehensive `FortyStateMatrixTests` in `app/Tests/MCPRouterUITests/` verifying:
  - 40 distinct cells across the 10 surfaces.
  - No empty or placeholder strings.
  - Proper state transitions in board models.
- Run `make lint`, `make test`, and `ledger-reconcile.py`.
