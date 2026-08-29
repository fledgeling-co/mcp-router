# spec-R27 — Upstream health check and timeouts

**Item** R27, `router` lane · **Brief** `planning/features-to-triage/upstream-server-health-probe-settings.md`
**Requirement** REQ-029 · **Cases** CASE-0217 … CASE-0222 · **Defect filed** DEF-063

---

## 1. What this is, and the one fact that shapes all of it

A health probe is a claim about the world outside this process. The brief asks for probe
intervals, request timeouts, a degraded state that precedes a tripped one, a manual re-probe, and
automatic recovery.

The fact that shapes the design is that **a probe of a stdio upstream is a child process**. The
router's first guarantee — `README.md`, and REQ-001 — is that at rest there are zero of those:
nothing is spawned until a tool on that server is actually called. An interval probe that cold
started every declared upstream would hold one child per server open forever, so the feature meant
to watch the router's central promise would invert it.

Two rules keep the two compatible, and everything else follows from them:

1. **Background probing is off by default.** `probeIntervalMs` defaults to zero, which arms no
   task at all — not a loop that wakes to find nothing due, which would be indistinguishable in a
   process listing from probing that is switched on.
2. **A scheduled sweep never cold-starts an upstream.** It probes only what is already live and
   declines the rest with a reason. A **manual** probe may cold-start, because a person asked.

The brief said the same thing from the other side: *background health checks run passively during
idle windows rather than issuing disruptive polling storms.*

## 2. Scope, and what is deliberately not here

Delivered: the router half — the policy, the monitor, the probe, and two control routes.

**Not delivered, and registered rather than dropped:**

- **R27-C1 — the Settings controls and the server-detail action.** The brief's acceptance sketch
  names both. The `router` lane's convention is the router half (R28, R29 and R31 all shipped
  routes with no UI), and the surface this needs — a Settings pane writing a policy, an inspector
  button reading a record — is a second item with its own design gates. It also needs a way to
  *write* the policy, and `PATCH /servers/:name` is a reference-diffed route whose allow-list must
  not grow without a parity decision: the config file is the only writer today.
- **R27-C2 — a per-invocation timeout on `tools/call`.** The timeout this item ships bounds the
  probe. A budget on the relayed call is a change to the hot path the parity corpus diffs, and it
  is inert only while it defaults to off — which makes it a decision about defaults, not a line of
  code.

## 3. The model

### 3.1 `HealthPolicy` — three numbers, resolved per server

`probeIntervalMs` (0 disables), `probeTimeoutMs`, `tripAfter`. A global block at the top of
`servers.json` sets the defaults; a server's own `health` block overrides them **key by key**, so
naming one value does not reset its siblings.

**Out-of-range values are refused, not clamped**, and the refusal reaches the wire carrying the key,
the value as written, the floor that rejected it, and a `scope` of `global` or `server` saying
which block to fix. A clamp reports 2 over a file that says 1, and the operator's next reading of
their own file disagrees with the router for a reason neither of them can see.

Three floors, and the third is this item's own version of the vacuity rule:

| key | floor | why |
|---|---|---|
| `probeIntervalMs` | 1000, or exactly 0 | a sub-second interval over twenty-one upstreams is the polling storm the brief asked this not to be. Zero is not "below the floor" — it is how you say "do not probe this one". |
| `probeTimeoutMs` | 1 | an unbounded probe can never report a timeout, so `degraded`-on-timeout would be unreachable. |
| `tripAfter` | 2 | **with a threshold of 1 the first failure trips, `degraded` is unreachable, and the guarantee that an upstream is flagged degraded before it is tripped would hold only because nothing can enter the state it names.** That is a guarantee satisfied by the absence of the thing it constrains. |

### 3.2 `UpstreamHealthState` — four states, and not on `ServerState`

`unprobed · healthy · degraded · tripped`, and `ServerState` (`idle · starting · running · stopping`)
is deliberately not extended. That enum is the control API's wire contract, transcribed from
`describe()` in `src/control.ts` and diffed by R4's parity gate. It is also a category error: those
four say what the router is doing with a process, these four say whether the thing on the other end
answers.

**The state is derived, never stored.** A stored `state` beside a stored `consecutiveFailures`
makes `(healthy, 4)` representable and holds the two in agreement only by every assignment being
written correctly. `ServerStateTracker.hasLoaded` records the same argument for the same reason.

### 3.3 `ProbeOutcome` — and the fourth case that makes a sweep safe

`ok(latencyMs, tools)` · `timedOut(afterMs)` · `failed(reason)` · **`declined(reason)`**.

`declined` is not a flavour of `failed`. A sweep skips an upstream that is not live, is disabled,
or already has a probe in flight; recording that as a failure would trip every idle server on the
second sweep — a health check reporting the router's own design as an outage.

Recovery is deliberately asymmetric: failing takes `tripAfter` readings, recovering takes one.
Reporting a working server as tripped sends somebody to debug a server that is fine.

### 3.4 The probe itself

`PoolUpstreamProbe` leases the upstream from `UpstreamPool` and sends `tools/list` down it, then
releases the lease. `tools/list` rather than a dedicated ping, because MCP has no ping every server
answers and a health check using a method half the fleet does not implement reports a protocol gap
as an outage — while `tools/list` is the one request every upstream here must answer, since the
router's own cache is built from it. The tool count is reported and never judged: a server that
legitimately advertises none is healthy.

`probeTimeoutMs` bounds the **request**, not the acquisition. A cold upstream is bounded by the
`startupTimeoutMs` it already has, and a second budget over the same spawn would be two numbers
racing to describe one failure — the caller would be told the probe timed out where the truth is
that the child never started. **DEF-063** is what that costs today and is filed rather than fixed
here: a child that starts and then exits is not noticed, so acquisition waits out the whole startup
budget (measured at 3.15s against a 3000ms budget, where a command that does not exist fails in
0.01s). The fix lives in the reference-diffed startup path and is a parity decision.

## 4. The wire

Two routes, both Swift-only, both declared in `planning/parity/surface.tsv` as `div-r27-inventory`
and `div-r27-probe`.

- **`GET /upstreams/health`** — every declared upstream in configuration order, with state, probe
  history, the policy in force and any refusals. A never-probed server is present and `unprobed`
  rather than omitted: an absent row and a server the router does not know about are different
  problems with different fixes.
- **`POST /servers/:name/probe`** — probe one now, answer with the record it produced.

**Not `/health`**: that is the router's own liveness, answered ahead of the control block and
shared with the reference; extending its body would move a surface R4 diffs. **Not
`/servers/health`** either: that parses as a server *named* `health`, so the two readings would be
decided by whether somebody had a server with that name.

With no monitor both routes answer **503 naming the missing capability**, the way `/harnesses`,
`/extensions` and `/caches` do. An empty report would be indistinguishable from a router that had
probed nothing — which is `D-p1-a`'s shape: a dependency nil in the one process that ships,
invisible to every unit test.

The monitor is held by `RouterService` for the life of the process, because **health is history**.
A monitor rebuilt per request would report every server `unprobed` forever and `tripAfter` could
never be reached — a failure invisible to any test that makes one request.

## 5. Evidence

| | |
|---|---|
| `UpstreamHealthPolicyTests` | 13 tests — resolution, refusals, the state machine at every threshold from 2 to 5 |
| `UpstreamHealthMonitorTests` | 11 tests — what is probed, what is declined, what is armed |
| `UpstreamHealthProbeTests` | 6 tests — the production probe against a real `UpstreamPool` |
| `ControlHealthRoutesTests` | 10 tests — both routes through `ControlHandler.handle` |
| `scripts/acceptance/r27-health.sh` | 22 assertions over the daemon's own socket, against real python children; enrolled in `acceptance-lanes.sh` |
| `planning/test-campaign/bin/witness-health-probe.sh` | the effect witness — CASE-0217, `effect-witness`, count 1, with a sabotage arm |
| `planning/test-campaign/bin/arm-r27-health.sh` | five arms, each watched red, sources restored byte-identically |

**The witness is the load-bearing one.** The unit suite's transport is a double, so nothing in it
spawns: a probe that reported `healthy` without ever reaching an upstream would pass every
assertion in it. The witness drives the production route over the daemon's socket and reads the
spawn out of the child's own `getppid()`, written to a path the product never reads back — then
denies the effect with a second upstream whose command does not exist and requires all four
recorders to flip. That fourth part is what separates a witness from an attempt that happened near
a test. The lane is the **portable floor** and says so: no bpf, no eslogger, no root, so the kernel
bar is not available and is not claimed.
