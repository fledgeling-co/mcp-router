# plan-R26 — Upstream auth expiry notification

Spec: `planning/specs/spec-R26.md` · Branch `ai/p4` · Requirement REQ-034 · Cases CASE-0314…0320

## Slices

| # | slice | files | done when |
|---|---|---|---|
| 1 | The policy and its refusals | `AuthExpiry/AuthExpiryPolicy.swift`, `Config/ConfigLoader.swift`, `Config/UpstreamConfig.swift` | a value below either floor is refused with key, value, scope and reason; zero is refused on both keys |
| 2 | The derived state | `AuthExpiry/AuthExpiryRecord.swift` | six states, derived from five stored facts; no path from a missing `expires_in` to `valid` |
| 3 | The notice and its copy | `AuthExpiry/AuthExpiryNotice.swift` | three kinds; no command offered when a refresh token is held; the headline can say the expiry is unknown |
| 4 | The monitor and the throttle | `AuthExpiry/AuthExpiryMonitor.swift` | report is pure with respect to actor state; claim advances; escalation and a moved expiry are never withheld; recovery drops the record |
| 5 | The two routes | `Control/ControlAuthExpiry.swift`, `Control/ControlAuthExpiryJSON.swift`, `Control/ControlToken.swift`, `Control/ControlHandler.swift`, `Control/ControlPorts.swift` | 200 on both, 503 with no monitor, 405/401/415 on the wrong verb, token and type, 404 on a prefix collision |
| 6 | The daemon's own wiring | `Service/RouterService.swift`, `Service/RouterServiceDispatch.swift` | the monitor is the service's, held for the life of the process |
| 7 | The socket lane and the arms | `scripts/acceptance/r26-auth-expiry.sh`, `planning/test-campaign/bin/arm-r26-auth-expiry.py` | 30 assertions green; eight arms watched red; sources restored byte-identically |

## Test strategy

Three planes, because each sees something the one below cannot.

- **Unit** — the derivation and the throttle are pure functions of stored facts, and this is the
  only plane that can visit every boundary cheaply. It cannot see the daemon's wiring.
- **Socket lane** — the routes as the process that ships answers them, against credential records
  planted on disk in a scratch `MCP_ROUTER_HOME`. This is the only plane that can see
  `ControlDeps.authExpiry` shipping nil, and the only one that can read the process table.
- **Arms** — the plane that decides whether either of the two above means anything. Every arm plants
  one defect its assertion exists to catch and requires the named tests to go red, with a presence
  control required green over a non-zero test count first.

## Decisions taken, with what they beat

- **Derive rather than probe.** The alternative — asking each upstream whether its token still works
  — would have needed R27's whole apparatus (interval off by default, no cold start from a sweep)
  and would have inverted REQ-001 for a fact already on disk. What it would have bought: detection
  of an early revocation. That is covered instead by the `refused` notice kind, read off the index
  error the manifest already holds.
- **Two routes, not one.** A single GET that both reported and claimed would be smaller. It would
  also make opening a settings pane silence the next alert.
- **Global policy only.** Per-server windows are plausible and are deferred to R26-C2 with the
  writer they need, rather than half-built here.
- **`unknown` is reported and never notified.** The alternative, notifying, produces an alert
  nobody can act on that never stops.

## Deferred

`R26-C1` (the desktop notification, the click-through, the status indicator) and `R26-C2` (a writer
for the policy, and per-server overrides). Both registered at the ledger.
