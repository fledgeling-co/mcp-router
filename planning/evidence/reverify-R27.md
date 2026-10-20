# Reverify R27: upstream health check and timeout configuration

**Verdict: RETIRED.**

- **Scope.** DEF-361, retrospective verdict for `L6` (merge `1bfad22d`). Requirement REQ-029, cases CASE-0217 to CASE-0222, DEF-063.
- **Requirements, derived from documents alone.** Brief `planning/features-to-triage/upstream-server-health-probe-settings.md` (acceptance lines 18–21); spec `planning/specs/spec-R27.md` (§1 rules 1–2, §3.1–§3.4, §4, §5); plan `planning/plans/plan-R27.md`; LEDGER and ORCHESTRATOR rows R27. The code was not opened until this table was drafted.
- **Tree checked.** main at `fe3b09b9`. Relevant Swift paths are unchanged since `63d7e208`.
- **Why RETIRED.** `plan-retire-swift-router.md` (Feature inventory, row "R27 health") says **DROP** the routes and the monitor, decision 1. The plan notes the monitor runs on a schedule inside the Swift router (`await health.start()`), which the TypeScript router does not have. Same caveat as F5: decision 1 is still listed for the owner to confirm.

## Requirements

| # | Requirement | Source | Verdict | Evidence |
|---|---|---|---|---|
| B1 | Settings controls for probe interval and timeout | brief line 18; spec §2 R27-C1 | RETIRED | Not built. `git grep -l 'probeIntervalMs\|tripAfter\|upstreams/health'` over `app/Sources/MCPRouterKit`, `app/Sources/MCPRouterUI`, `app/MCPRouter`, `app/MCPRouterIOS` and `app/windows` on `fe3b09b9` returns nothing. |
| B2 | Upstreams past the timeout are flagged degraded before they are tripped | brief line 19 | RETIRED | `return consecutiveFailures >= policy.tripAfter ? .tripped : .degraded`, `app/Sources/RouterCore/Health/UpstreamHealthRecord.swift:95` at `fe3b09b9`. The degraded-before-tripped guarantee is the `tripAfter` floor: `public static let minimumTripAfter = 2`, `app/Sources/RouterCore/Health/HealthPolicy.swift:81` at `fe3b09b9`. |
| B3 | Manual re-probe from the server detail view | brief line 20 | RETIRED | Route: `case ("/probe", "POST"):`, `app/Sources/RouterCore/Control/ControlHandler.swift:216` at `fe3b09b9`. No client calls it (client grep, B1). The inspector button is R27-C1 and was never built. |
| B4 | Healthy upstreams recover automatically | brief line 21 | RETIRED | `Recovery is the single`, `app/Sources/RouterCore/Health/UpstreamHealthRecord.swift:100` at `fe3b09b9`. One success clears `consecutiveFailures`; failing takes `tripAfter` readings. |
| B5 | Overrides are global with per-server overrides, not one hard-coded value | brief line 24 | RETIRED | `floor: minimumIntervalMs,`, `app/Sources/RouterCore/Health/HealthPolicy.swift:125` at `fe3b09b9`. Each key resolves separately, so naming one does not reset the others. |
| B6 | Background checks run passively during idle windows, not as polling storms | brief line 25 | RETIRED | `probeIntervalMs: 0, probeTimeoutMs: 5000, tripAfter: 3`, `app/Sources/RouterCore/Health/HealthPolicy.swift:68` at `fe3b09b9`: no background probing by default. |
| S1.1 | Background probing is off by default, and arms no task | spec §1 rule 1 | RETIRED | `defaults to zero, which arms no background probing at all`, `app/Sources/RouterCore/Health/HealthPolicy.swift:41` at `fe3b09b9`. |
| S1.2 | A scheduled sweep never cold-starts an upstream | spec §1 rule 2 | RETIRED | `does not cold start one`, `app/Sources/RouterCore/Health/UpstreamHealthMonitor.swift:100` at `fe3b09b9`. `is a person asking, so it is allowed to cold`, `app/Sources/RouterCore/Health/UpstreamHealthMonitor.swift:7` at `fe3b09b9` (the manual probe may cold-start). |
| S3.1a | Out-of-range values are refused with key, value, floor and scope, not clamped | spec §3.1 | RETIRED | `public let scope: String`, `app/Sources/RouterCore/Health/HealthPolicy.swift:15` at `fe3b09b9`. |
| S3.1b | Floors: interval 1000 or exactly 0, timeout at least 1, `tripAfter` at least 2 | spec §3.1 | RETIRED | `public static let minimumIntervalMs = 1000`, `app/Sources/RouterCore/Health/HealthPolicy.swift:73` at `fe3b09b9`. `public static let minimumTripAfter = 2`, line 81. |
| S3.2 | The health state is derived, never stored | spec §3.2 | RETIRED | `The state is derived, never stored.`, `app/Sources/RouterCore/Health/UpstreamHealthRecord.swift:63` at `fe3b09b9`. |
| S3.3 | `declined` is a fourth outcome, not a failure | spec §3.3 | RETIRED | `case declined(reason: String)`, `app/Sources/RouterCore/Health/UpstreamHealthRecord.swift:20` at `fe3b09b9`. |
| S3.4a | The probe sends `tools/list`, not a ping | spec §3.4 | RETIRED | `rather than a dedicated ping`, `app/Sources/RouterCore/Health/UpstreamProbing.swift:22` at `fe3b09b9`. |
| S3.4b | The timeout bounds the request, not the acquisition | spec §3.4 | RETIRED | `listBounded(lease.session, timeoutMilliseconds: timeoutMilliseconds)`, `app/Sources/RouterCore/Health/UpstreamProbing.swift:52` at `fe3b09b9`. |
| S4a | `GET /upstreams/health` lists every upstream, including never-probed ones | spec §4 | RETIRED | `guard path == "/upstreams/health" else { return nil }`, `app/Sources/RouterCore/Control/ControlHealth.swift:32` at `fe3b09b9`. Never-probed reads `unprobed`: `guard probesRun > 0 else { return .unprobed }`, `app/Sources/RouterCore/Health/UpstreamHealthRecord.swift:93` at `fe3b09b9`. |
| S4b | Both routes answer 503 naming the missing capability when no monitor exists | spec §4 | RETIRED | `this router has no health monitor`, `app/Sources/RouterCore/Control/ControlHealth.swift:38` at `fe3b09b9`. |
| S4c | The monitor is held for the life of the process | spec §4 | RETIRED | `let health: UpstreamHealthMonitor`, `app/Sources/RouterCore/Service/RouterService.swift:69` at `fe3b09b9`. Started once: `await health.start()`, line 281. |
| S4d | Not `/health`, and not `/servers/health` | spec §4 | RETIRED | `/health` is the shared liveness route in `src/router.ts` (`if (url.pathname === '/health')`), and `/upstreams/health` is absent from the TypeScript router (see Tests). |

## Shipped clients

No client calls `/upstreams/health` or `/servers/:name/probe` (see B1 and B3). No DEF is filed from this item.

## Tests and lanes

- `swift test` (see the F5 report): `warning: No matching test cases were run`, `EXIT=0`. `UpstreamHealthPolicyTests`, `UpstreamHealthMonitorTests`, `UpstreamHealthProbeTests` and `ControlHealthRoutesTests` are not in any declared target. Not run.
- `scripts/acceptance/r27-health.sh`: exit 2. `environment: no MCPRouterCLI at /Volumes/LLMs/Dev/mcp-router-wt/reverify-3/app/.build/debug/MCPRouterCLI (run: make build-cli-debug)`.
- `planning/test-campaign/bin/witness-health-probe.sh` (CASE-0217, `effect-witness`) and `planning/test-campaign/bin/arm-r27-health.sh` are present. Neither was run. The witness drives the Swift daemon over its socket.
- `planning/test-campaign/cases.json` lists CASE-0217, CASE-0218 and CASE-0222 with `status: pass`. Nothing on this tree backs those results.

## Open

1. Owner confirmation of plan decision 1, as in F5.
2. DEF-063. The spec records it as filed and not fixed, in the reference-diffed startup path. `planning/test-campaign/inventory.json` now reads `fixed · in-test`. This audit did not check where the fix lives. Owner to confirm the closure.
3. R27-C1 (settings and the detail action) and R27-C2 (per-call timeout on `tools/call`) were never built and are not scheduled.
