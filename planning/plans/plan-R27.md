# plan-R27 — Upstream health check and timeouts

Spec: `planning/specs/spec-R27.md`. Branch `ai/l6`, worktree `.worktrees/L6`.
Delivered 2026-08-29. **Stopped at ready-to-verify; nothing merged.**

## Order of work, and why this order

1. **Read the effect boundary before designing anything.** `references/effect-boundary.md`, and
   this repository's own instance of it: REQ-016 declared an `outbound-socket` effect with no
   provider in 492 production files and was moved to `vacuous` rather than left reading as
   satisfied. The first design question was therefore *which production symbol performs the
   effect*, not *what should the API look like* — and the answer decided the whole shape, because
   the symbol is `Process()` in the stdio transport and REQ-001 says at rest there are none of
   those.
2. **The policy and the record**, pure and testable without a process.
3. **The probe**, over the real pool, with a bounded request.
4. **The monitor**, holding the two probe paths apart.
5. **The routes**, wired into the daemon in the same change — R28's and R31's rows both record
   what happens when they are not.
6. **The witness**, last, because it is the only thing that can say the rest is not vacuous.

## What was built

| | |
|---|---|
| `RouterCore/Health/HealthPolicy.swift` | three numbers, per-server resolution, refusals with a scope |
| `RouterCore/Health/UpstreamHealthRecord.swift` | the four states, derived; the four outcomes; due-ness |
| `RouterCore/Health/UpstreamProbing.swift` | the port, and `PoolUpstreamProbe` — the production effect |
| `RouterCore/Health/UpstreamHealthMonitor.swift` | the two probe paths, the sweep, the loop |
| `RouterCore/Control/ControlHealth.swift` + `…JSON.swift` | `GET /upstreams/health`, `POST /servers/:name/probe` |
| config | a `health` block, global and per server, in `ConfigLoader` and `ServerParser` |
| daemon | the monitor built once in `RouterService`, started after `listen`, stopped in `stop` |

Three edits to existing code that are not additions, each with its reason in the source:

- **`FirstOutcome` became generic.** It carried `Handshake` directly; the probe needs the same race
  to bound `tools/list`. Copying it would leave two implementations of one concurrency primitive
  free to drift, and the drift would be in the half nobody reads until it hangs.
- **`changesResponse` moved to `ControlAuthDispatch.swift`.** `dispatchServer` is capped at
  cyclomatic complexity 10, that body carried three of its branch points, and the `/probe` arm took
  the total to 11. `/changes` and `/approve` are one quarantine surface read from two sides, so the
  move is a seam rather than arithmetic. `ControlHandler.swift` went 398 → 379 lines.
- **`RouterConfig` gained two defaulted fields** rather than required ones, so the twenty-six
  construction sites that predate health checking build a router with probing off — which is what
  they described before this existed.

## Gates, with the exit codes actually seen

| gate | exit | what it says |
|---|---|---|
| `swift test --filter` over the four new suites | 0 | 40 tests in 4 suites |
| `scripts/acceptance/r27-health.sh` | 0 | 22 ok, 0 failed, over the daemon's own socket |
| `planning/test-campaign/bin/witness-health-probe.sh` | 0 | witnessed, count 1, sabotage held |
| `planning/test-campaign/bin/arm-r27-health.sh` | 0 | 7 of 7 held — five arms red, one green baseline, one byte-identical restore |
| `campaign.py check` | 0 | 142 cases, 129 pass, armed 129/129, effect-witness 9 |

## Two things that went wrong, kept because they are the useful part

**The arming pass filtered on `@Suite` display names.** swift-testing matched nothing, all four
arms reported *"0 tests passed"*, and the pass would have recorded four arms that compared nothing
while wearing a green — this repository's own standing rule arriving inside the script written to
enforce it. `--filter` takes a type name. Every run in `arm-r27-health.sh` now reports how many
tests it ran and the script exits 1 if any arm matched none.

**The acceptance lane's first flaky probe took longer than curl would wait**, which read as a hung
route and is not. It is DEF-063: a stdio child that starts and then exits is not noticed, so
acquisition waits out the whole `startupTimeoutMs` — 3.15s against a 3000ms budget, where a command
that does not exist fails in 0.01s. Filed, not fixed: the race lives in the reference-diffed
startup path, and changing how this router reports a failure the reference reports differently is a
parity decision.

## Registered, not dropped

- **R27-C1** — Settings controls and the server-detail re-probe action. Needs a writer for the
  policy; `PATCH /servers/:name` is reference-diffed and its allow-list must not grow without a
  parity decision.
- **R27-C2** — a per-invocation timeout on `tools/call`. A change to the hot path the parity corpus
  diffs, inert only while it defaults to off, so it is a decision about defaults.
- **DEF-063** — the startup-budget finding above.

## Not done, and why

No UI, so no `design-review`, no `be-my-witness` and no glass lane: this item renders nothing. No
parity lane drives the two routes against `src/control.ts`, because it answers 404 and 405 on them
and calling that agreement would be two routers being equally silent — the `div-r27-*` rows are
`proven-by-suite` and say so.
