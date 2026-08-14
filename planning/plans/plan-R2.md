# Plan — R2: Swift router, lazy pool, relay, HTTP passthrough

**Spec:** `planning/specs/spec-R2.md`
**Branch:** `ai/r2` · **Worktree:** `.worktrees/R2`
**Tier:** Large
**Created:** 2026-08-14 · **Revised:** 2026-08-14 after the out-of-family plan gate (REJECT, 2
critical · 13 high · 2 medium)

## What the plan gate changed

Three findings reshaped the architecture rather than adding tasks, and they are recorded first
because everything below follows from them.

**1. The relay cannot speak the SDK's typed models (finding 12, confirmed first-hand).**
`CachedTool.sdkTool()` drops every member the SDK does not model — its own doc comment says so and
says "never round-trip a cached tool through this". The committed union corpus requires `title`, a
vendor `x-vendor` object, **and object key order** to survive
(`app/Tests/RouterCoreTests/Vectors/union-tools.json:73-101`). R4 compares every tool-list
response. Therefore: **`tools/list` is served as raw JSON built from R1's `JSONValue`**, which was
proved byte-for-byte against `JSON.stringify`, and not through `Server`'s typed handler. Finding 13
shows the same loss on the way back — `Client.callTool` returns only `content` and `isError`,
discarding `structuredContent` and `_meta` — so upstream calls go through
`Client.send(CallTool.request(...))` and relay the complete result.

This is the difference between a port that looks right and one that passes R4.

**2. A stale successful open leaks a live child (finding 5 — critical).** The first plan's
generation guard made a late-completing start a "silent no-op". But that start owns a running
child; not installing it does not close it, and shutdown cannot force-reap a handle it never saw.
That is an orphan, and on this platform stdin EOF is not reliable liveness, so it persists.
**Every invalidated start is cancelled, and any late success is disconnected and its process
terminated and awaited before the error is returned.**

**3. Generations alone do not close the races (finding 6).** One counter cannot distinguish a
start attempt from a handle from a timer from a lease, so a duplicate `release()` decrements twice
and a retried start shares its predecessor's identity. Four separate monotonic ids replace it:
`startAttemptID`, `handleID`, `reapEpoch`, `leaseID`, with active lease ids tracked for
exactly-once release.

**4. NIO is isolated, not imported into `RouterCore` (findings 1, 2).** The gate's third option is
better than either of mine: exact-pinned NIO in a thin **`RouterHTTPNIO`** target linked only by
the daemon executable, bridged with `NIOAsyncChannel` so no `@preconcurrency import`,
`@unchecked Sendable` or `nonisolated(unsafe)` reaches `RouterCore`. `MCPRouterKit`'s
no-dependency promise and `RouterCore`'s dependency surface both stay as they are.

## Scope this runner delivers, and what it hands on

The gate established that R2 as scoped is four subsystems, and that two of them (the HTTP upstream
client lane, finding 3; the per-request lifecycle owner, finding 11) had **no owner at all** in the
first plan. Delivering all of it to the evidence standard E0 sets — real processes, real sockets,
pinned-SDK sessions — is more than one runner should claim.

**This runner delivers Phases 0-2:** the frozen seams, and the lazy pool proven against real child
processes. That is the mechanism the product exists for, it is the part R4's spawn/reap timing diff
is about, and the seams are what stops R3 — running in parallel right now — inventing a colliding
boundary.

**Phases 3-6 become child spec R2-R** (relay, listener, HTTP upstreams, composition root),
inheriting a finished contract. Reported to the orchestrator; not registered here.

---

## Phase 0 — Frozen seams

**Files:** `app/Sources/RouterCore/Seams/RouterSeams.swift`

R3 is building against these now, so they land first and do not move. Specified as APIs, not names
(finding 22 of the spec gate):

- `ControlHandling` — `claims(path:) -> Bool`, `respond(request:rawBody:) async -> HTTPResponse?`.
  R2 buffers the body once and hands the **raw bytes**; R3 does every decode.
- `CallerIdentifying` — `prefetch(_ connection: ConnectionDescriptor)` called at **accept time**,
  and `identity(for:) async -> CallerIdentity`. `ConnectionDescriptor` is a `Sendable` value (peer
  address, accept timestamp), never a channel handle, so no NIO type crosses the seam (finding 16).
- `CallObserving` — `record(_ event: CallEvent)`, `flush() async`. `CallEvent` carries every field
  the reference records: `ts, server, tool, ok, ms, cold, pid, cwd, project, client, err`.
- `UpstreamAuthorizing` — returns `(any HTTPClientAuthorizer)?`, the pinned SDK's actual protocol,
  not `any Sendable` (finding 4 — a runtime cast would have failed at the first HTTP upstream).

**Gate:** compiles; a no-op default implementation of each proves an unattached seam is inert.

## Phase 1 — Pool state machine

**Files:** `app/Sources/RouterCore/Pool/{PoolIdentifiers,PoolEntry,UpstreamPool,Lease,PoolStatus}.swift`

The actor, with the transport behind `UpstreamTransporting` so the state machine is testable
without spawning.

The four ids and their rules:

| Id | Bumped | Guards |
|---|---|---|
| `startAttemptID` | each start attempt, including a retry after failure | commit-or-discard of a completed start |
| `handleID` | each successful install | eviction, close events, release |
| `reapEpoch` | each timer arm | that a cancelled-but-still-running sleep does not reap |
| `leaseID` | each lease | exactly-once release; a duplicate is ignored |

Deliver: single-flight where one cohort of waiters shares one attempt (P2, P2a); **invalidated
starts are cancelled, and a late success is closed and its process terminated** (finding 5);
`lease`/`release` as one actor-isolated commit with all OS work outside the critical section
(P4a, finding 6); epoch-guarded reap verifying timer identity, handle id, zero in-flight and a
genuinely passed deadline (P4, P6, P6a); warm skip (P5); per-server and `<= 0` idle (P6);
identity-checked eviction (P8, P8a); shutdown that refuses acquisitions, awaits starts,
cancels timers, force-reaps, and is idempotent (P9); `pendingAuth` (P14).

**The counter transition table (finding 14)** — pinned here because two reasonable implementations
would otherwise differ observably and R4 would call it a regression:

| Event | `callsServed` | `lastUsedAt` | reap deadline |
|---|---|---|---|
| cold cohort of *N* waiters | **+1 total**, at start completion | set | armed at completion |
| warm-up open | +1 | set | never armed (P5) |
| hot acquire | +1 each | set | re-armed |
| reopen after eviction | **resets to 0** | set | armed |

`idleSec` uses JavaScript's `Math.round` semantics (half away from zero on ties), and `status()`
preserves **configuration order**, not dictionary order.

**Gate:** `swift test --filter Pool`. Each race clause has a test that fails without its guard: a
start completing after eviction (and asserting the stale child was closed), a cancelled timer
firing after re-arm, a delayed close after reopen, a duplicate release. These are **development
tests against a fake transport** and, per finding 7, they do **not** discharge E0 — Phase 2 does.

## Phase 2 — Real child processes, and the E0 evidence pass

**Files:** `app/Sources/RouterCore/Pool/{ChildProcess,ObservingStdioTransport,StdioUpstreamTransport}.swift`

The layer the SDK does not provide (D1), plus the two hazards the gate found in it:

- **There is no close callback (finding 8).** `Transport` exposes none; `StdioTransport` merely
  finishes its private stream at EOF and `Client` privately owns the receive loop, so a naive
  wrapper re-requesting a finished stream hot-loops. `ObservingStdioTransport` forwards **one**
  receive stream, reports EOF or send failure **once**, and combines it with process termination to
  drive identity-checked eviction plus `Client.disconnect()`.
- **Pipe ownership (finding 9).** The SDK sets both parent descriptors `O_NONBLOCK` and neither
  closes them nor joins its read task on disconnect. Every `Pipe` is retained, the two descriptors
  handed to the SDK are `dup`ed, exactly one closer exists, nothing else reads stdout, and teardown
  is ordered: disconnect and cancel, close parent descriptors, terminate, then await the process.
- argv, `cwd`, merged environment with per-server override, and **PATH lookup using the merged
  child environment**, shell-free (finding 10)
- stderr drained continuously on its own task (P12)
- termination escalates **TERM → KILL** with an asynchronous waiter, because `Client.connect`'s
  continuation is not resumed by cancellation alone (finding 10)
- startup timeout, per-server override, cancelled on success; on timeout: `Client.disconnect()`,
  close descriptors, kill and await, join the connection task (P13)
- `residentMb()` omitting upstreams with no local process, asserting the key set (P10)

**Gate — this is the E0 pass, and it is clause-indexed (finding 7).** Every P-clause is re-proved
against a **real spawned child**: a fixture executable that reports its argv, cwd and environment,
floods stderr past the pipe buffer, can hang on demand, and can ignore SIGTERM. Zombie and
descriptor assertions read the real process table. A PATH-only executable proves lookup. The
completion note's evidence table cites these executions, never the Phase 1 fakes.

---

## Handed to child spec R2-R

Specified, unimplemented here, with the gate's findings already folded in so the next runner starts
from a corrected contract:

- **Relay** — raw-JSON `tools/list` from `JSONValue` (finding 12); `Client.send(CallTool.request)`
  preserving `structuredContent` and `_meta` (13); server identity pinned to `mcp-router`/`0.1.0`
  with `tools: .init()` and non-strict configuration (15).
- **Listener** — `RouterHTTPNIO` target, `NIOAsyncChannel` bridge, no `@preconcurrency` in
  `RouterCore` (1, 2); buffer once, cap 32 MiB, route before decode (T1-T4); the seven framing
  adversaries (H8); accept-time `prefetch` from channel acceptance (16).
- **HTTP upstream clients** — the lane that had no owner: headers, `oauth: false`, pending-auth
  lifecycle, pooled initialization, teardown, legacy-SSE rejection (3; P14, P15, H4).
- **Per-request lifecycle owner** — `Server.stop()` neither awaits its receive task nor cancels
  pending request tasks, so an aborted request can leave a relay task holding a pool lease (11).
- **Composition root** — `RouterD` executable, seams wired, `/health` and `/status` (C1, C2).

## Risks

| Risk | Mitigation |
|---|---|
| `StdioTransport` setting fds non-blocking fights `Process` pipes | Phase 2 gates on a real child before anything builds on it; descriptors are `dup`ed so ownership is unambiguous. |
| The four-id discipline is more machinery than the races need | Each id has a test that fails without it. An id whose test cannot be made to fail is removed rather than kept for symmetry. |
| Phase 2's fixture executable becomes a build-time dependency of the suite | It is a plain executable target in the same package, built by `swift build`, with no external tooling. |
