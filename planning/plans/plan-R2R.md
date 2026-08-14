# plan-R2R — Router: the process that actually serves

**Spec:** `planning/specs/spec-R2R.md` (revision 2) · **Branch:** `ai/r2r` · **Tier:** Large
**Acceptance:** `scripts/acceptance/parity-gate.sh`

Out-of-family gate: codex is account-limited until 2026-08-20 and **exits 0 on that limit**, so both
the spec review and this plan's review ran in-family — a fresh adversarial `claude -p` opus-5
reviewer per gate, briefed to refute and told that finding nothing is a failed review. Recorded so
the weakness travels with the evidence: `codex: usage limit -> claude (downgrade)`.

The spec was **rejected twice** before it was built from. Revision 1: 3 blockers, 5 majors, 3
minors. Revision 2: 3 blockers, 7 majors, 3 minors. Both reviews are answered in the spec's §10 and
in §7 below; two of the blockers changed the shape of the item, and one of them (the `D-j` fix)
would have turned the gate red on a *fixed* defect.

---

## 1 · Shape

Five things, in dependency order. Each unblocks the next, and each has parity rows that go green the
moment it lands — which is what made it safe to build in this order rather than all at once.

| # | Phase | Lands | Rows it unblocks |
|---|---|---|---|
| A | The listener | `HTTPWire`, `LoopbackHTTPServer` | none on its own |
| B | The composition root | `RouterService`, `ServicePorts`, `ServiceLogEvent` | `mcp-health`, `mcp-status` |
| C | The relay | `MCPEndpoint`, `UpstreamCalling`, the `UpstreamSession` calling requirements | `mcp-endpoint`, `mcp-tools-list`, `mcp-tools-call`, `pool-p4`, `pool-reap-traffic`, `div-r2r-d8` |
| D | The CLI | `MCPRouterCLI` target, 9 verbs | 8 `cli` rows |
| E | Lifecycle and lanes | signals, `install.sh`, five lane scripts, the self-test | `install-launchd-serve`, `state-ondisk-compat`, `log-bytes` |

## 2 · Phase A — the listener

`app/Sources/RouterCore/HTTP/HTTPWire.swift`, `.../LoopbackHTTPServer.swift`.

`HTTPWire` is pure — parsing and serialising with no socket in the file — because every framing rule
in it is a decision that can be wrong, and a rule reachable only by binding a port is a rule that
gets tested once and then trusted. `HTTPWireTests` covers it without a port.

R5's `LoopbackCallbackListener` is read first and three decisions carried over: the loopback pin
through `requiredLocalEndpoint` (never `NWListener(using:on:)`, which binds every interface), a bind
failure that **throws** in the reference's `listen EADDRINUSE: address already in use 127.0.0.1:N`
wording, and a head deadline. It is not reused — it binds once per instance, reads only a request
line, answers one request per connection and has no streaming.

Each connection gets its own `Task`. A design routing every request through one actor would
serialise the router behind its slowest tool call.

**Decisions that were not obvious:**

- A bare `LFLF` head terminator is accepted as well as `CRLFCRLF`. Real clients send it, and a
  server waiting for a CR that is not coming is indistinguishable from a hung router.
- `Transfer-Encoding` on a **request** is refused rather than implemented. No client of this router
  sends one, and a server accepting both framings without agreeing on precedence is the classic
  request-smuggling shape.
- `Connection: close` is honoured. Found by the CLI's own `status` verb reporting "no router
  answering" against a live router: the client read until the peer hung up, and a keep-alive server
  does not hang up.

## 3 · Phase B — the composition root

`RouterService` assembles config, manifest store, pool, control handler, usage store, auth and
registry, and dispatches in `src/router.ts`'s order: identity prefetch at accept time → `/health` →
`/status` → control paths → `/mcp` → 404.

Two seam gaps were found by building the process rather than by reading, and both are real: R2's
`UpstreamPool` is an actor while R3's `UpstreamPoolPort` is synchronous, and R5's `FileAuthStore`
reads are `async` while `AuthStore`'s are not. Neither seam was wrong — nothing had ever had to hold
both at once, because nothing had ever composed them. Resolved with a **snapshot per request**
(`PoolSnapshotPort`, `SnapshotAuthStore`), so the control handler stays what R3 built it to be: a
total function of its dependencies.

`ManifestIndexer` implements `UpstreamIndexerPort` for real — the seam R3 declared and nobody filled.

## 4 · Phase C — the relay

Two measurements shaped it, and neither was inferable from the source:

1. The reference answers `POST /mcp` with **SSE**, not JSON. The SDK's `StatelessHTTPServerTransport`
   returns `application/json`, so using it would diverge on the framing of every response.
2. The envelope order is `result, jsonrpc, id` on success and `jsonrpc, id, error` on failure — two
   *different* orders, measured separately rather than assumed symmetric.

So `/mcp` is served over R1's `JSONValue` / `JSStringify`, which puts member order, number rendering
and escaping under this router's control. That is what makes a **byte** diff possible rather than a
key-sorted one, and key-sorting is exactly what would hide the divergence most likely to occur.

The framing refusals are hand-written rather than taken from the SDK's validators, also measured:
`OriginValidator` answers `421 Misdirected Request: Host header not allowed` where the reference
answers `403 Invalid Host header: <host>`. The Accept and Content-Type strings do agree with the
SDK's, both implementing the same spec sentence.

### 4.1 The tap

`UpstreamSession` gained `listTools()` and `callTool(name:arguments:)`, both returning `JSONValue`.
There was no way to *call* a leased upstream at all — R2 built the lifecycle and deferred the calls.

Returning `JSONValue` is not a preference. The SDK decodes every result into `MCP.Value`, whose
object case is `[String: Value]` — an **unordered dictionary** — so a `tools/call` result comes back
with its member order destroyed. Byte parity would have been lost one layer below the wire.

`TappingTransport` is the answer: a `Transport` decorator that forwards everything and keeps a copy
of each response's raw bytes, claimed afterwards by a request id we choose ourselves. The SDK keeps
framing, the handshake, correlation and timeouts; only the bytes are kept aside, then parsed by R1's
parser. `ResponseTap` is bounded at 64 entries, evicted oldest-first, because a long-lived upstream
answering thousands of calls would otherwise grow it forever.

## 5 · Phase D — the CLI

`Sources/MCPRouterCLI`. Nine verbs. `watch` is not built — `R2-W`'s.

**stdout, stderr and the exit code are three separate contracts.** `cmdStatus` catches a failed
fetch and writes to stdout with exit 1; `cmdUsage` throws the same sentence, which `run().catch`
writes to **stderr** behind `mcp-router: `. A harness capturing `2>&1` would call those identical,
so `Out.print` / `Out.error` keep them apart and the lane compares them separately.

Three reference behaviours are reproduced rather than improved, and each is marked in the code:

| Reference behaviour | Why it is reproduced |
|---|---|
| `status` prints `undefined calls` for a running child | `cmdStatus` reads `c.calls`; `/status` emits `callsServed`. Measured: `running   stdio  probe   undefined calls, idle 2s`. Reproduced through the same mechanism — an absent member interpolated the way a template literal does — so if either router ever emits `calls`, both change together |
| `tools` has no empty state | `DESIGN.md` §5 wants one sentence and one action; adding it is a divergence on an owned row. Raised as `D-r2r-a` |
| `serve` on a taken port prints the bare `listen EADDRINUSE…` with no advice | any tail would be an undeclared divergence on `cli-serve` |

## 6 · Phase E — lifecycle, installer, lanes

Signals go through `DispatchSourceSignal`, not `signal(2)`: a C handler may only call
async-signal-safe functions and shutting a pool down is none of them. The default disposition is
ignored first, or the process dies before the source fires.

`docs/install.sh` gains `MCPR_ROUTER_BINARY` — opt-in, non-default, and it switches **only the
`serve` agent**. The `watch` agent stays on node, because there is no Swift watcher and a variable
that moved both would leave the second running a verb the binary does not implement, which the user
would discover when a new server silently stopped being adopted. Verified in both modes without
running the installer, which would rewrite the user's own `~/.claude.json`.

### 6.1 The five lanes

`parity-mcp.sh`, `parity-cli.sh`, `parity-install.sh`, `parity-state.sh`, `parity-log.sh`, plus their
names added to `parity-gate.sh`'s `LANES` default — **the only line of the gate this item changes**,
and one R4 anticipated: `parity-gate.sh:201` already prints coverage for those five groups.

Each lane carries what the second review demanded and revision 1 lacked:

1. **An explicit owned set.** `record()` refuses any `(group, id)` pair not in a list declared at the
   top of the lane. The gate binds no script to a group, so authorship is closed from the lane's
   side or not at all.
2. **Its own caveat**, printed into its log — which `parity-gate.sh:101` echoes unconditionally, so
   the disclosure reaches the report without editing the gate's own caveat block.
3. **A port it refuses to share**, and never 8975/8976.
4. **A demonstrated red**, through `parity-lane-selftest.sh` — §6.2.

### 6.2 The self-test

`scripts/acceptance/parity-lane-selftest.sh` seeds a defect per lane and requires the lane to go red.
It is a script rather than a paragraph in an evidence file because a paragraph is re-run by nothing.
The defect is injected through a shim on `$SWIFT_BIN`, never through a hook in the router — a
test-only branch inside the product is a branch that can ship.

It has already earned its place twice, both times by finding a hole in **itself**:

- the first version read the seed from an environment variable, and the install lane reported a
  clean pass against a router that exits immediately — a launchd agent inherits nothing from the
  shell that wrote its plist, so the defect never arrived. Modes are now written into per-mode shim
  files.
- the `stdout` mode piped `serve` through `sed`, which made the real binary a *child* of the shim;
  killing the shim orphaned a listening router, and the next run reported the cli lane as "could not
  run". `serve` now `exec`s.

## 7 · What the reviews changed

| Finding | Change made |
|---|---|
| R1·1, R2·1 — fixing `D-j` forces an edit to `control-differential.sh` | `AuthRoutes` stays undispatched. `cli-auth` is not claimed. Verified at `control-differential.sh:465-479`: the stale branch records `fail`, so the gate is red whether the row is left blocked or flipped |
| R1·2, R2·3 — the lanes are unreviewed gate surface | §6.1 and §6.2 |
| R1·3, R2 (fully answered) — the install lane was one-sided | two real agents, one per binary, four observations each |
| R1·4, R2·4/R2·8 — canonicalised comparison hides envelope order | byte diffs throughout; framing compared as status line + application headers + **de-framed** SSE events, because chunk boundaries are chosen by Node's write scheduler rather than by its code |
| R1·5, R2·5 — the divergence was over-declared | narrowed to the parser text; status and code now match |
| R1·6, R2·9 — the arithmetic | baseline re-measured at 50 of 81 on 2026-08-14 with a compiling tree; the corrected count is in §8 |
| R1·7, R2·1 — no guarantee for the control token on a socket | G10/G11 in the spec, and §8's open item — this is the one finding not fully closed |
| R1·8, R2·10 — invented CLI copy | §5, all measured |
| R2·2 — `cli-refresh`'s oracle was same-side | it now compares against the **reference's** `refresh` |
| R2·6 — "first four log lines" | three, enumerated |
| R2·7 — `mcp-status` needed more normalisation | `port` and `idleSec` only, each named as a coordinate or a clock, with the call sequence driven identically so the counters are comparable |

## 8 · The number, and what is still open

Baseline **50 of 81** (measured 2026-08-14, compiling tree). This item proves its 18 owned rows and
adds one divergence row, for **69 of 82**. Blocked afterwards: 13 — `D-j` 2, `D-k` 3, `D-l` 1,
`D-m` 2, `R2-R` 1 (`cli-auth`), `R2-W` 3, `R4-C` 1.

**Open, and named rather than buried:** the control API is now reachable over a socket for the first
time, and `control-differential.sh` compares the Swift side through `ControlDiff` — an in-process
oracle, not a listener. So the 11 proven `control` rows describe a handler, not a served endpoint,
and G10's token check has no lane. Closing it means either editing a lane this item may not touch or
adding rows to a group nothing audits. It is reported as a deferred child rather than decided here.

## 9 · Deferred children

| id | Title | Depends on |
|---|---|---|
| `D-r2r-a` | `mcp-router tools` has no empty state | the cutover (R4-C) |
| `D-r2r-b` | The control API has never been compared **over a socket** — `control-differential.sh` drives `ControlDiff` in-process | R4, whose lane it is |
| `D-r2r-c` | `cli-auth` and `control-{approve,auth}-post` need `AuthRoutes` dispatched **and** `control-differential.sh`'s known-defect assertions retired in the same change | D-j |
