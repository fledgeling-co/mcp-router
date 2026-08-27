# R2: Swift router — lazy pool, relay, HTTP passthrough

**ID:** R2
**Status:** Ready for Implementation Plan
**Created:** 2026-08-14
**Last updated:** 2026-08-14
**Depends on:** R1 (merged)

## Feature description

*Verbatim from `planning/features-to-triage/R2-router-pool-relay.md`.*

> # R2 — Swift router: lazy pool, relay, HTTP passthrough
>
> **Depends on:** R1.
>
> Port `src/pool.ts`, `src/router.ts`, `src/watch.ts` — the mechanism the product exists
> for: one shared endpoint, children spawned only when a tool on them is actually called,
> reaped when idle, with a warm set held under a RAM budget.
>
> Carry across the behaviours that were tuned against real traffic rather than designed:
> - The reaper skips warm servers; warm implies running.
> - Schema quarantine — a server whose tool descriptions change after install is held,
>   not silently accepted.
> - HTTP upstreams route through the same lazy-spawn path as stdio children.
> - `watch.ts` migrates new stdio entries out of client configs automatically.
>
> Known trap: reading the HTTP request body for every POST breaks the MCP endpoint,
> because a request stream can be consumed exactly once. Body reading must stay gated on
> control paths only.

---

## What this item is really for

R1 built the router's *data* layer — config, manifest, discovery, JSON. Nothing in it runs a
server or starts a child. R2 is the first item that makes the Swift router a **router**: it
spawns, relays and reaps.

That matters for two reasons beyond the obvious.

**It is the item R4's parity gate is really about.** Config and manifest parity are file
comparisons. Spawn/reap parity is a *timing and lifecycle* comparison — R4 diffs "spawn and reap
timing" and "behaviourally identical spawn/reap decisions over the full corpus". A port that gets
the decisions right but arms its idle timer from the wrong moment passes every unit test and fails
the gate. So the criteria below are written against **when** things happen, not only what happens.

**It is where the Swift SDK stops being a drop-in.** The TypeScript SDK hands you a
`StdioClientTransport` that spawns and kills the child, and a `StreamableHTTPServerTransport` that
plugs into `node:http`. The pinned Swift SDK 0.12.1 does **neither** (D1, D2, both independently
confirmed by the out-of-family review). Both gaps are R2's to fill, and both are recorded as
divergences — an unrecorded difference is precisely what R4 must treat as a regression.

### Scope: what R2 delivers, and the one part it defers

R2 delivers the **relay path, end to end and provable**: a listening router binary that spawns a
real child on first call, relays, reaps, and serves the union — which is exactly wave 3's stated
success criterion, "Swift router relays a real call".

**`watch.ts` is deferred to a child spec (R2-W).** This is a scope decision made on evidence, not
convenience. The out-of-family review established that the watcher's central correctness
requirement is a **cross-process** one: the watcher and the daemon are separate processes, both
write `servers.json`, and R3's control-API PATCH writes it too. An adoption that reads the config,
spends seconds indexing a child, then writes back a stale object will erase a concurrent PATCH, and
no actor or lock inside one process can fix it (finding 24). Choosing that protocol requires R3's
control API to exist to be tested against. Building the watcher before then means either guessing
the protocol or shipping a known data-loss window.

The watcher is also off the relay path: nothing in "relays a real call" needs it, and the
TypeScript watcher keeps running and keeps adopting servers throughout, because TypeScript remains
the installed default until R4.

The watcher's contract is nonetheless specified below (W-clauses), so R4 knows what parity means
and R2-W inherits a finished contract rather than starting from the brief.

### The boundary with R3, which runs in parallel

R2 and R3 both depend on R1 and are in the same wave. `src/router.ts` imports `control.ts`,
`usage.ts` and `auth.ts` — all three are **R3's**. R2 ports the relay and the HTTP surface and
defines **frozen seams** where R3 plugs in. Finding 22 showed that naming a protocol is not enough:
a seam with no methods forces R3 to edit R2's code. Each seam below is therefore specified as an
API, and R2 owns the composition root (finding 23) so R3 contributes factories rather than editing
a `main`.

| Concern | Owner | The frozen seam |
|---|---|---|
| Control API routing, token, PATCH rules | R3 | `ControlHandling`: `claims(path:) -> Bool`, and `respond(request:body:) async -> HTTPResponse?`. R2 buffers the body once and hands the **raw bytes**; R3 does all decoding. |
| Usage records, caller identity | R3 | `CallerIdentifying`: `prefetch(connection:)` at accept time, `identity(for:) async -> CallerIdentity`. `CallObserving`: `record(_: CallEvent)` and `flush() async`. |
| OAuth token storage / browser flow | R3 | `UpstreamAuthorizing`: `authorizer(for:) -> (any Sendable)?` plus a challenge callback. R2 records `pendingAuth`, which is pool state `/status` reports. |
| Registry search | R3 | none |
| `/health`, `/status` | **R2** | Assigned explicitly (finding 22). Both are unauthenticated, non-mutating, and live in `router.ts`. |

A seam with no implementation attached must behave correctly alone: an absent control handler means
control paths 404, never a trap.

---

## Acceptance criteria

The oracle for every later stage. Each clause names the evidence that settles it — a measurement,
an exercised request, or a red-green test. Clause **E0** below is what stops the rest being
stub-satisfiable (finding 25).

- **E0** — Every clause's evidence is produced against **real OS resources**: a real spawned child
  process for the pool clauses, a real socket and a real pinned-SDK MCP session for the HTTP
  clauses, and the built executable for the composition clauses. No clause may be discharged by a
  hand-written double standing in for the thing under test. The completion note records, per
  clause, which of the three evidence types was used.

### The named trap — restated, because the brief's mechanism is Node-only

The brief's stated cause — "a request stream can be consumed exactly once" — is a property of
Node's `IncomingMessage`. It **does not hold in Swift**: `HTTPRequest.body` is a `Data` value that
can be read any number of times, so an eager read for every POST does not reproduce the bug. The
review confirmed this against the pinned SDK, and the earlier draft of this spec was wrong to claim
the trap survived the port with a different mechanism.

What survives is the *invariant the trap was protecting*, and the Swift hazards that break it:

- **T1** — The bytes the client POSTed to `/mcp` reach the MCP transport **byte-identical**.
  Evidence: a request whose body contains multi-byte UTF-8 and a JSON string that would not survive
  a re-encode round-trip is answered correctly.
- **T2** — Red-green against the **real** Swift hazard: a listener that decodes, re-encodes, or
  otherwise round-trips the body before dispatch must fail T1. Mutating the buffered bytes is the
  red case; passing the original bytes is green.
- **T3** — The body is buffered **once** and routed on the path **before** any semantic decoding.
  A control-path decode failure must not consume, reject or alter an MCP request.
- **T4** — The buffer is capped at **32 MiB**, matching the reference; a larger body is refused
  rather than accumulated.

### Pool — the lazy lifecycle

- **P1** — No child is spawned for a stdio upstream until a tool on it is called. Listing tools does
  not spawn; starting the router does not spawn (except warm; P7).
- **P1a** — The child is launched with the configured command, the argument array, the configured
  `cwd`, the router's inherited environment, and the per-server `env` **overriding** it. Evidence: a
  real child that reports its own argv, cwd and environment back.
- **P2** — Single-flight: *N* concurrent acquires of a cold upstream produce exactly **one** spawn
  and all *N* receive the same handle.
- **P2a** — Single-flight is **generation-guarded**. The in-flight start is stored as a task with a
  generation token; on completion or failure the entry is re-read and committed only if the
  generation still matches. Evidence: a start that completes *after* the entry has been evicted or
  shut down must not install its handle.
- **P3** — A child idle past its window is reaped and the **process is actually terminated**,
  awaited, with every parent-side pipe descriptor closed and no zombie left. Asserted on the
  process and the descriptors, never on the transport (D1).
- **P4** — The reaper never fires while a call is outstanding, and the idle window re-arms from
  **call completion**, not acquisition. A call running longer than `idleMs` completes successfully.
- **P4a** — Acquisition and in-flight accounting are **one atomic actor-isolated lease**: the lease
  cancels the reap timer and increments the in-flight count before returning. Release carries a
  generation-bound token, so a late release cannot decrement a replacement handle's count.
- **P5** — A `warm` server is never reaped, at any idle age.
- **P6** — `idleMs <= 0` disables reaping for that server; a per-server `idleMs` overrides the
  default.
- **P6a** — Reap timers are **epoch-guarded**: cancellation in Swift is cooperative, so a cancelled
  sleeping task may still run. Before reaping, the callback verifies it is still the installed
  timer, the generation matches, in-flight is zero, and the deadline has genuinely passed.
  Evidence: an old cancelled timer firing after a re-arm must not reap.
- **P7** — `warmUp()` opens every warm upstream **concurrently**; one that fails is logged and
  swallowed, and the router still comes up.
- **P8** — An upstream that closes on its own is evicted so the next call reopens it.
- **P8a** — Eviction-on-close is **identity-checked**: a close event from generation A must not
  evict generation B's handle, and an intentional reap disables the callback before closing.
  Evidence: a delayed close delivered after a reopen.
- **P9** — `shutdown()` is fully specified: it refuses new acquisitions, awaits every in-flight
  start, cancels every timer, then **force-reaps even entries with calls outstanding**, closing
  client, transport and process. Calling it twice is a no-op.
- **P10** — `residentMb()` reports measured RSS per live stdio child and **omits** upstreams with
  no local process — matching the reference exactly, which returns only names that had a pid.
  Evidence asserts the dictionary's **keys** as well as its values. No number the router does not
  observe (DESIGN.md §6).
- **P11** — `status()` reports `callsServed` and `inFlight` as separate quantities with states
  `running` / `starting` / `idle`. **`callsServed` is an acquisition counter, not a served-call
  counter** — see D6; the spec states its true semantics so no later runner "fixes" it into
  something R4 reads as a regression.
- **P12** — A stdio child's stderr is drained continuously, proven by a child that writes **beyond
  the pipe buffer's capacity** and must not wedge.
- **P13** — A startup exceeding the timeout fails the acquire and leaves **no** half-open child,
  socket or descriptor. The per-server `startupTimeoutMs` overrides the default, and the timeout is
  cancelled on success rather than left to fire.
- **P14** — An unauthorized HTTP upstream records a `pendingAuth` entry (server, url, timestamp)
  that `/status` reports; `clearPending` removes it; a successful open clears it.
- **P15** — HTTP upstream configuration is honoured, not merely pooled: configured `headers` are
  sent, `oauth: false` suppresses authorization entirely, and a `transport: "sse"` upstream **fails
  loudly** with D3's capability-gap message rather than being quietly treated as streamable HTTP.

### Relay — what is served and what is refused

- **R-1** — `tools/list` serves the union read **through** the manifest store, not a startup
  snapshot, so an index run while the router is up reaches the next client that lists.
- **R-2** — The union is scoped by the caller's working directory.
- **R-3** — **Schema quarantine**: only the approved surface is served; a server whose tool surface
  changed after install is held pending and its changed tools are not served.
- **R-4** — A name that is not `<server>__<tool>` returns a tool error naming the expected format,
  without touching the pool. Missing `arguments` are passed as `{}`, matching the reference.
- **R-5** — A scoped-out server is **refused when called**, not merely hidden.
- **R-6** — A placarded server answers with the INOPERATIVE text — reason, substitute, and the
  instruction not to retry — **without spawning anything**.
- **R-7** — `cold` is determined **before** the call is issued, and is observable on the emitted
  `CallEvent` so the clause can be checked rather than asserted.
- **R-8** — A failing upstream returns an `isError` result naming server, tool and reason. One
  broken server never takes the others down and never crashes the router.
- **R-9** — A tool reporting its own failure (`isError` in the result) is recorded as a failure.
- **R-10** — `CallObserving` runs **after** the result is on its way and swallows every error;
  attribution never delays or breaks a call. `CallerIdentifying.prefetch` is invoked at **accept
  time**, not at call end, because the lookup can only answer while the peer is alive.

### HTTP passthrough

- **H1** — `/health` returns `{ok, upstreams}`; `/status` returns `{ok, port, idleMs, children,
  pendingAuth, tools}` with each child carrying `name`, `transport`, `state`, `callsServed`,
  `inFlight`, `idleSec`. The exact field set is the criterion.
- **H2** — The MCP endpoint refuses a request whose `Host` is not in the allowlist. The allowlist
  is the four reference forms: `<host>:<port>`, `127.0.0.1:<port>`, `localhost:<port>`,
  `[::1]:<port>`.
- **H3** — Stateless: a transport and server per request, sharing no MCP session state; both are
  **torn down when the response closes**, including on a client abort, leaving no retained waiter
  or task.
- **H4** — HTTP upstreams route through the same lazy path as stdio children — one acquire, one
  handshake shared by every session, reaped on the same rule.
- **H5** — An unknown path 404s naming the MCP endpoint; an unsupported method returns 405 with
  `Allow: POST`.
- **H6** — Control paths are delegated to the seam before `/mcp` is considered. Both cases are
  evidence: with a handler attached the seam answers, and with **no** handler attached control
  paths 404 and the router keeps serving.
- **H7** — The listener binds loopback by default.
- **H8** — The hand-written listener is proven on **real sockets** against the framing cases Node
  supplied for free (D2): headers and body arriving fragmented across packets, `Content-Length`
  bodies, chunked transfer-encoding, two requests on one persistent connection, a client abort
  mid-request, malformed framing, and the 32 MiB cap.

### Composition root

- **C1** — R2 owns a named executable target and a single composition-root file. R3 contributes
  factories conforming to the frozen seams and does not edit it.
- **C2** — Evidence for C1 is the **built binary**: launch it, POST a real MCP `tools/list` and
  `tools/call` to `/mcp`, observe the child spawn on the call and not before, and observe the reap.

### Watch — specified now, delivered by child spec R2-W

Recorded so R4 knows what parity means and R2-W inherits a contract.

- **W1** — Fast path: an unchanged `mcpServers` hash means a read, a hash and an exit — nothing
  spawned, nothing written. Hashing canonicalises object-key order.
- **W2** — A `~/.claude.json` that does not parse **on the initial read** abandons the run and
  writes nothing. This is deliberately narrower than "any parse failure": see D7.
- **W3** — A server is indexed **before** adoption. A failure is retried only after a five-minute,
  **hash-sensitive** backoff — an edited definition retries immediately. Manifest entries that are
  current are not re-indexed, failed entries are removed rather than cached as indexed, and the
  temporary indexing pool is always shut down.
- **W4** — Every write **to `~/.claude.json` or `servers.json`** is preceded by a backup and
  performed temp-plus-rename; `~/.claude.json`'s file mode is preserved; backups are pruned to ten.
  (Watcher state is exempt — it is derived and recoverable.)
- **W5** — `~/.claude.json` is re-read immediately before the delete, and an entry that changed
  while it was being indexed is left in place.
- **W6** — Reserved names and the router's own self-reference are never adopted.
- **W7** — The state hash is taken **after** our own write, so the fire our write triggers takes the
  fast path.
- **W8** — Anything still pending withholds the state hash so the next fire retries. A missing input
  or missing router config likewise exits without sealing the hash. Corrupt watcher state recovers
  as empty state.
- **W9** — Adoption covers **every parseable transport**, not only stdio: the reference's
  `candidateOf` applies no stdio filter. The brief's wording ("new stdio entries") describes the
  common case, not the contract.
- **W10** — Adoption must not erase a concurrent control-API PATCH of `servers.json`. One
  cross-process mutation protocol is chosen — file lock plus re-read-and-merge, a content-hash CAS,
  or routing adoption through the daemon — and an unrelated concurrent PATCH must survive adoption.
  **This is R2-W's central design question and the reason it is a child spec.**

### Structure and the standing constraints

- **S1** — Extends the `RouterCore` target. No second MCP SDK dependency; the exact `0.12.1` pin is
  unchanged. Evidence is the built executable (C2), not the presence of a target.
- **S2** — The HTTP listener is **swift-nio, pinned exact**, and lives only in `RouterCore` — the
  target neither app links. See D8 for why this is the right dependency to add and why it does not
  reopen the pre-1.0 hazard the standing constraint is about. `MCPRouterKit` keeps its
  no-external-dependency promise untouched.
- **S3** — Swift 6 language mode, strict concurrency, no `@unchecked Sendable`.
- **S4** — Neither app target links `RouterCore`; the Mac app's only channel stays the loopback
  control API.
- **S5** — `install.sh` and `src/*.ts` untouched. TypeScript stays the installed default.

---

## Declared divergences from the TypeScript reference

R4 must not read any of these as a regression — nor read their absence elsewhere as agreement.

| # | Divergence | Why | R4 impact |
|---|---|---|---|
| **D1** | `StdioTransport` takes two file descriptors and **spawns nothing**. R2 owns the child: spawn, env, cwd, stderr drain, pid, descriptor closure and **explicit termination on reap**. | `StdioTransport.swift:50-83`; `disconnect()` merely flips state (lines 182-187). TS's `StdioClientTransport` spawns and kills the child itself. | Reap is asserted on the process and its descriptors. Closing a Swift transport does not kill the child, and stdin EOF is not reliable liveness for an MCP server. |
| **D2** | The SDK ships **no HTTP listener**. `StatelessHTTPServerTransport` is `handleRequest(HTTPRequest) -> HTTPResponse`; its own example server brings NIO. R2 supplies the listener from a platform framework (S2). | Adding swift-nio puts another package in the graph for a socket accept loop. | Framing, chunking and connection lifetime are R2's code, so H8 proves them rather than inheriting Node's guarantees. |
| **D3** | `transport: "sse"` **cannot be served**. TS uses `SSEClientTransport`, the legacy 2024-11-05 HTTP+SSE transport. The Swift SDK has only `HTTPClientTransport` — Streamable HTTP with optional SSE *streaming*, a different protocol. | Confirmed: `HTTPClientTransport.swift:15-30`, POST at 246, session-aware GET at 590. | A known **capability gap**, not a difference to explain away. P15 requires failing loudly with the stated message. |
| **D4** | OAuth is a seam. R2 records `pendingAuth`; R3 owns storage and the flow. | `auth.ts` is R3's. | Until R3 lands, an upstream needing authorization reports pending rather than authorizing. |
| **D5** | **The body-consumption trap does not exist in Swift.** The brief's mechanism is Node-specific. | `HTTPRequest.body` is reusable `Data`; the SDK reads it directly (`StatelessHTTPServerTransport.swift:178-215`). | The invariant is preserved by T1-T4 instead. R4 should not expect a Swift analogue of the Node failure, because there is none. |
| **D6** | `callsServed` counts **acquisitions**, not served calls. Warm-up counts one; *N* concurrent cold callers sharing a start count one between them; a reopen resets it to zero. | `pool.ts:264-270` — `calls += 1` is inside `touch()`, called on acquisition. | Swift reproduces this **exactly**, because R4 diffs the value. Correcting it is a wire-visible change affecting F3's client and every surface that renders it — recorded as deferred child D-h rather than fixed here. |
| **D7** | **The reference loses a router restart** when `~/.claude.json` becomes unparseable *between* the initial read and the pre-delete re-read: the manifest and `servers.json` may already be written, and the early return skips `restartRouter()`. On the next fire the config already matches, so `configChanged` is false and the restart is never issued — the running router never learns about the adopted server. | `watch.ts:285-300` skips the restart at line 336's function; confirmed by reading. | A **latent bug in the reference**, not a Swift decision. R2-W must not reproduce it; the divergence is declared here so R4 treats the difference as intended. Logged as deferred child D-i for the TypeScript side. |
| **D8** | **swift-nio is added to `RouterCore`, pinned exact**, to supply the listener D2 says the SDK lacks. | The alternative is hand-writing HTTP/1.1 framing — request line, headers, `Content-Length`, chunked bodies, keep-alive, aborts — on top of `NWListener`. That is the surface H8 exists to test, and getting it subtly wrong breaks *real* MCP clients in ways a unit suite does not catch. The reference used `node:http`, a battle-tested server; NIO is the like-for-like choice, and a hand-rolled parser is not. The pre-1.0 hazard the standing constraint names is specific to the MCP SDK: swift-nio is 2.x, Apple-maintained and API-stable for years, it is **already in the resolved graph** (2.101.3, pulled by the SDK's own package), and the SDK's own reference server uses it. `RouterCore` is linked by neither app, which is the same containment argument `Package.swift` already makes for putting the SDK there. | The listener is a shared, tested implementation rather than R2-authored protocol code, which *reduces* the surface R4 must attribute. Known wrinkle: NIO needs `@preconcurrency import` under Swift 6 (the SDK's own example does this) — permitted, and distinct from `@unchecked Sendable`, which stays forbidden by S3. |

---

## Design representation — 2026-08-14

**R2 renders nothing.** It is the router's runtime: no view, no surface, no interaction, no
overlay. Inventing screens for it would be fabrication. Scaled honestly, the design stage covers
what R2 genuinely owns — the **values later surfaces need to tell DESIGN.md §5's states apart**,
and the **words** (§6) it emits.

Not a formality here either. R2 produces the numbers the product's central surface renders, and §6
is explicit that a number the router does not observe is never displayed. P10 and P11 are that rule
as acceptance criteria — and the review sharpened P11 into something better than the draft claimed:
`callsServed` is *not* a served-call count, so a surface that labels it "calls served" would be
displaying a number the router does not observe. That is now D6 and deferred child D-h, rather than
a label nobody checked.

### Which `DESIGN.md` §5 states this item feeds

| State | What R2 supplies | Surfaced by |
|---|---|---|
| Default | `status()` per server: `running` with `callsServed`, `inFlight`, `idleSec`; measured `residentMb` | M3, M2 |
| Loading | `starting` as a state **distinct** from running and idle, so a spawning server gets a skeleton rather than reading as live | M3 |
| Partial | a deliberately short tool union: the approved surface, with a quarantined server's changed tools withheld and named | M3, M8 |
| Error | per-call failure carrying server, tool and reason; a startup timeout distinguished from a crash; an unservable legacy-SSE upstream (D3) | M2, M3 |
| Offline | — not this item; "the router is not running" is the control client's | F3 |
| Success | in-place: a cold call moves `idle → starting → running`, no toast | M3 |
| Disabled | placarded and scoped-out servers, each with the reason | M3 |
| Empty · Overflow | — not this item; no surface | — |

### The copy, written now rather than left to a later runner

**This table is normative** (finding 16): the model-facing strings are asserted by the relay tests,
and the log lines are snapshot-asserted. Strings carried **verbatim** from the reference are marked;
rewording one would make R4 report a difference that is only a rewording.

| Condition | Copy | |
|---|---|---|
| Tool not namespaced | `Tool "<name>" is not namespaced <server>__<tool>.` | verbatim |
| Server out of scope | `Upstream "<server>" is not available in this project (<cwd>).` | verbatim |
| Placarded tool | `Tool "<tool>" is INOPERATIVE: <reason>. Use <substitute> instead. Do not retry this tool; it will keep returning this.` | verbatim |
| Upstream call failed | `Upstream "<server>" failed to handle "<tool>": <reason>` | verbatim |
| Startup timed out | `upstream "<name>" did not initialize within <ms>ms` | verbatim |
| Not authorized | `upstream "<name>" is not authorized. Run \`mcp-router auth <name>\` to sign in.` | verbatim |
| Unknown upstream | `unknown upstream server "<name>"` | verbatim |
| Shutting down | `router is shutting down` | verbatim |
| Unknown path | `not found; MCP endpoint is /mcp` | verbatim |
| Legacy SSE upstream (D3) | `Upstream "<name>" uses the legacy SSE transport, which the Swift router cannot speak. Keep this server on the TypeScript router until it is migrated to streamable HTTP.` | new — R2 owns it |
| Reap, stdio | `closing idle child "<name>" after <n> call(s), <s>s alive` | verbatim |
| Reap, HTTP | `closing idle connection "<name>" after <n> call(s), <s>s alive` | verbatim |
| Self-closed upstream | `upstream "<name>" closed on its own; evicting so the next call reopens it` | verbatim |
| Warm start failed | `warm upstream "<name>" did not start: <reason>` | verbatim |

---

## Triage — 2026-08-14

**Ready for Implementation Plan.**

### Out-of-family spec review — codex `gpt-5.6-sol`, effort `max`, read-only

Wire verified: `model: gpt-5.6-sol`, `reasoning effort: max`, exit 0. Report at
`/tmp/gate-R2-spec.md` (gone). **Verdict: REJECT** on the draft — 1 critical, 17 high, 6 medium, 1 low.
Every finding is dispositioned below; the spec above is the rewrite.

**Accepted and fixed (22):** 1 (the critical — T1-T4 and D5 replace a trap that does not exist in
Swift), 2 (H8), 3 (P1a, P12), 4 (P3, P13 — the three SDK claims were independently confirmed
correct; the fd/zombie extension is the fix), 5 (P15), 6 (P7, P13), 7 (P9), 8 (P11, D6), 9 (P10),
10 (R-4, H1, H2), 11 (H3, H5), 13 (W3), 14 (W2, D7), 15 (W4, W8), 16 (copy table made normative),
17 (P2a), 18 (P4a), 19 (P6a), 20 (P8a), 21 (`CallerIdentifying`, R-10), 22 (seams specified as
APIs; `/health` and `/status` assigned to R2), 23 (C1, C2), 25 (E0).

**Accepted, and it changed the scope (2):** 12 and 24. Finding 12 established that the watcher
adopts every parseable transport, not just stdio (W9). Finding 24 established that its correctness
requirement is cross-process and unresolvable without R3's control API (W10). Together they make
the watcher a child spec rather than a slice of this one — see *Scope* above.

**Rejected: none.** Two were confirmed first-hand before acceptance rather than taken on trust:
`calls += 1` inside `touch()` (`pool.ts:264-270`) and the skipped `restartRouter()`
(`watch.ts:285-300`).

### Assumptions carried forward

1. **The HTTP listener is swift-nio, pinned exact, inside `RouterCore`** (S2, D8). The draft assumed
   Network.framework to avoid any new package; that trades a dependency for hand-written HTTP/1.1
   framing, which is the wrong trade when real MCP clients and R4's parity gate both sit downstream
   of it. This is the one assumption most worth challenging at the plan gate, and it is put to it
   explicitly.
2. **`/health` and `/status` belong to R2.** They are unauthenticated and non-mutating, they live
   in `router.ts`, and F3's client already consumes them. R3 owns only the token-guarded paths.
3. **`callsServed` keeps the reference's semantics and its wire name.** Parity outranks the naming
   defect while R4's gate is the thing that decides the migration.

### Deferred children discovered

Reported to the orchestrator, not registered here.

| Suggested id | Title | Deps | Why |
|---|---|---|---|
| **R2-W** | Swift router: the `~/.claude.json` watcher and its cross-process adoption protocol | R2, R3 | W10 needs R3's PATCH to exist to be tested against; building it earlier means guessing the protocol or shipping a data-loss window |
| **D-h** | Rename `callsServed` to what it measures, across router, control API, client and surfaces | R4 | D6 — it is an acquisition counter. Wire-visible, so it needs R4's gate to have passed and F3 + the Mac surfaces to move together |
| **D-i** | Fix the lost router restart in the TypeScript watcher | — | D7 — a latent bug in the reference: an adopted server can never reach the running router |

## Progress — 2026-08-14

**Status: delivered, not merged.** Branch `ai/r2`, worktree `.worktrees/R2`. Scope is Phases 0–2 of
`plan-R2.md` — the frozen seams and the lazy pool, with real-process evidence. The relay, the HTTP
listener, HTTP upstream clients and the composition root remain with child spec **R2-R**; the
config watcher remains with **R2-W**.

### Gate evidence

| Gate | Result |
|---|---|
| `make test` | `Test run with 279 tests in 44 suites passed` / `executed 279 tests` |
| `make lint` | `Found 0 violations, 0 serious in 95 files` · `no-raw-design-values: clean` |
| `make parity` | `parity: 224 vector cases compared (floor 224)` |
| `app/Scripts/pool-mutation-gate.sh` | **Superseded twice; this row is the third verdict and the first one that is both runnable and complete.** (1) As first written the gate was unrunnable — it `cd`'d into a deleted worktree and exited 90 on every invocation (G9), so the original row recorded a verdict nobody could have obtained. (2) Re-run on the repaired gate 2026-08-25: exit 1, `MUTATION GATE: FAILED`, **11 OK / 1 HOLE / 1 SKIP** — the HOLE was P8b *evict before suspending*, whose test `endedSessionIsEvictedBeforeAnySuspension` waited on the eviction and so outlasted the very window the guard closes, passing against both orderings; the SKIP was E0 SIGKILL escalation, whose mutation stopped applying when `waitForExit` moved from `StdioUpstreamTransport.swift` to `StdioUpstreamSession.swift` and the gate's file list did not follow. (3) G13 strengthened the test to act inside the window (it now takes a lease while the close is being logged and requires a fresh session), added the session file to the gate's mutate-and-restore set, and replaced the summary's single `fail` bit and its literal "thirteen" with five typed outcomes over a denominator counted from the gate itself. Re-run 2026-08-27 on that gate: **exit 0, `MUTATION GATE: PASSED — 13 of 13 guards proved load-bearing, none withdrawn`, 0 HOLE / 0 STALE / 0 inconclusive / 0 withdrawn**. The verdict logic has its own control, `app/Scripts/pool-mutation-gate-selftest.sh` (14 cases, no build): it runs the real gate against a `swift` shim and requires a hole, a stale mutation and an empty run each to go red and to be labelled apart from a guard that was proved. Re-check this row whenever the gate's verdict changes. |

### E0 — which clauses have real-resource evidence

E0 says a clause may not be discharged by a double standing in for the thing under test. Ten tests
in `RealProcessTests.swift` run against a real spawned child, real pipes, real signals and a real
handshake over the pinned SDK. The table separates those from the clauses whose evidence is still
only the state machine, because "tested" and "tested against the thing" are different claims.

| Clause | Evidence | Type |
|---|---|---|
| P1 | `poolSpawnsAndReapsARealChild` — nothing spawned before the first lease | real process |
| P1a | `childIsLaunchedAsConfigured` — child reports its own argv, cwd and env back | real process |
| P2 | `concurrentLeasesSpawnOneRealChild` — five callers, one interpreter | real process |
| P2a | `timedOutStartLeavesNoOrphan`, `lateStartIsClosed` | real process + red-green |
| P3 | `poolSpawnsAndReapsARealChild` — the pid is gone after the idle window | real process |
| P4 | `callOutstandingIsNeverReaped`, `reaperCannotBeatTheWaitingLease` | red-green + mutation |
| P4a | `releaseIsExactlyOnce` | red-green + mutation |
| P5, P6, P7 | warm and idle-window behaviour | state machine only |
| P8 | `realChildThatExitsIsEvicted` — a real child exits, the pool notices and reopens | real process |
| P8a, P8b | `staleCloseCannotEvict`, `selfEndedSessionIsClosed`, `endedSessionIsEvictedBeforeAnySuspension` | red-green + mutation |
| P9 | `shutdownReapsEveryChild`, `stubbornChildIsKilled`, `shutdownIsABarrier` | real process + mutation |
| P10 | `residentMemoryIsMeasuredNotInvented` — RSS read by `ps` from a live pid | measurement |
| P11 | `callsServedCountsAcquisitions` and the transition table | state machine only |
| P12 | `chattyChildDoesNotWedge` — 300 KB of stderr before the first reply | real process |
| P13 | `timedOutStartLeavesNoOrphan` | real process |
| P14, P15 | pending-auth recording; the SSE capability gap fails loudly | state machine only |
| S1, S3, S4, S5 | `StandingConstraintsTests`, `make lint`, the exact `0.12.1` pin | measurement |
| T1–T4, R-1…R-10, H1–H8, C1–C2 | **not delivered** — R2-R | — |
| W1–W10 | **not delivered** — R2-W | — |
| S2 | **not delivered** — the listener is R2-R's, and the swift-nio pin lands with it | — |

Seam sufficiency is covered separately by `SeamTests.swift`: a query string survives, a stream
delivers as produced, a dropped reader reaches the producer, an authorizer is accepted by the SDK's
own transport, and each inert default behaves correctly unattached.

### What the real-process evidence found that the doubles could not

Wiring the pinned SDK to an actual child immediately produced a deadlock, and the shape of it is
worth recording. `handshake` raced `Client.connect` against a timer inside a `withTaskGroup`, and a
task group does not return until **every** child task finishes. A server that never answers leaves
`connect` awaiting a reply that will not come; cancellation is cooperative and does not reach it; so
the group waits forever — the exact hang the startup timeout exists to prevent. `waitForExit` had
the same shape, which meant the SIGKILL escalation could never fire for the stubborn child it was
written for. Both now publish the winner to a box and abandon the loser.

A second finding: every member of a cold cohort is labelled `cold`, not just the caller that paid
for the start. That is parity, not an oversight — the reference reads `!pool.isLive(name)` before
the call at `router.ts:136`, so in Node all *N* concurrent callers also see a dead upstream. Making
it read more sensibly would have made it diff worse under R4.

### Phase D completeness critic — disposition

Out-of-family, `gpt-5.6-sol` at `max`, read-only, log at `/tmp/gate-R2-phased.md` (gone). Verdict **REJECT**,
19 findings. Every one is dispositioned below; none is left silent.

| # | Disposition |
|---|---|
| 1 | **Fixed.** Phase 2 delivered: `StdioUpstreamTransport` plus ten real-process tests. The table above now records an evidence type per clause. |
| 2 | **Fixed.** `sessionEnded` evicts and persists synchronously before any `await`; proved by `endedSessionIsEvictedBeforeAnySuspension` with a blocking log sink. |
| 3 | **Fixed.** A self-ended session is now closed, not merely forgotten; `selfEndedSessionIsClosed` asserts `shutdownCount == 1`. |
| 4 | **Fixed.** A waiter reservation is taken before suspending, so no timer is armed while a caller waits for the start it paid for. |
| 5 | **Fixed.** `shutdown()` is a shared flight; a second caller awaits the first rather than returning into a half-torn-down pool. |
| 6 | **Rejected, with reason.** The reference does not hot-reload its upstream list — `watch.ts:361-371` says so and restarts the daemon via `launchctl kickstart`. A `reload` API would invent behaviour R4 diffs against. R3 does not need one. |
| 7 | **Fixed.** `ControlRequest` carries `rawQuery` beside a query-free `path`. |
| 8 | **Fixed.** `ControlBody.stream` models `/usage/stream`; disconnection arrives through the stream's own `onTermination`. |
| 9 | **Fixed.** The seam names `(any HTTPClientAuthorizer)?` — what `HTTPClientTransport` actually accepts — so a wrong authorizer fails at compile time rather than at the first HTTP upstream. |
| 10 | **Deferred to R2-R, deliberately.** `UpstreamSession` cannot yet relay a call. Designing that API without the relay in hand would be guessing, and the constraint is recorded for R2-R: `tools/list` must be served as raw JSON (`CachedTool.sdkTool()` drops `title` and `x-vendor`, which the union corpus requires) and calls must go through `Client.send(CallTool.request(...))`, since `callTool` drops `structuredContent` and `_meta`. |
| 11 | **Fixed.** The mutation gate parses the executed count and requires it to be non-zero, distinguishes `HANG` from `HOLE`, and fails on a mutation that no longer applies. It now covers thirteen guards. |
| 12 | **Open — a product decision, not mine.** `spawning` logs the command line and `childStderr` logs child output, either of which can contain a token. The reference does exactly the same, so redacting diverges from a surface R4 diffs byte for byte. Raised in the runner's report. |
| 13–19 | Belong to the deferred relay/listener scope; carried into `R2-R`'s brief rather than closed here. |

### Deferred children

- **R2-R — Swift router: relay, HTTP listener, HTTP upstreams, composition.** Depends on R2 and R3.
  Carries T1–T4, R-1…R-10, H1–H8, C1–C2, S2, and Phase D findings 10 and 13–19.
- **R2-W — Swift config watcher.** Depends on R2-R. Carries W1–W10, whose central requirement is a
  cross-process mutation protocol that cannot be tested without R3's control API.
