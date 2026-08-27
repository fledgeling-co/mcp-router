---
status: completed
shipped-by: aba30bd
---

# F4 — ServerStateTracker cannot report failure

**Category:** foundation · **Depends on:** F3 (merged) · **Blocks:** M2, M3

## The defect

`app/Sources/MCPRouterKit/Control/ServerStateTracker.swift`, on `main`. Found by the M1 runner
during its plan gate and verified in source by the orchestrator before scheduling.

Two faults, both of which make a failure state unrenderable:

1. **Every typed error is discarded.** `pollLoop()` is

   ```swift
   if let response = try? await client.servers() { apply(poll: response) }
   ```

   `try?` throws away the whole of `ControlAPIError` — `routerNotRunning`, `unauthorized`, a 5xx,
   a decode failure. The loop simply retries. F3 went to real trouble to make those errors typed
   and distinguishable (there is a test asserting `unauthorized` is a different value from
   `routerNotRunning`), and this is the one place that consumes them, throwing all of it away.

2. **`phase` is pinned to `.disconnected` when there is no stream.** `run()` starts
   `consumeStream()` only `if stream != nil`, and `apply(phase:)` is called from nowhere else. The
   initialiser defaults `stream` to `nil`. So a tracker constructed the ordinary way reports
   `.disconnected` forever, whatever the router is actually doing — and a surface that trusts
   `phase` shows a disconnected chrome over live data.

## Why it is its own item

DESIGN.md §5 requires nine states with real copy for the unhappy paths. M2 (Activity) and M3
(Servers board) are both scheduled against this type, and neither can meet §5 while the type it
reads from is structurally incapable of expressing failure. M1 worked around it by polling the
client directly, which is the right local call and the wrong thing to do three times.

## Scope

- Give `TrackerState` a way to carry the last poll outcome, so a surface can distinguish
  *never loaded* from *loaded and now failing* from *loaded and current*. A stale snapshot plus a
  live error is a real state and the most common one in practice — do not collapse it to an error.
- Decide and document what `phase` means for a tracker with no stream. "No stream configured" is
  not the same condition as "the stream dropped", and `.disconnected` currently claims the second.
- Preserve the distinctions F3 already draws. `unauthorized` must not become "an error".
- Red-green every guard: each must be observed failing before it counts. In particular, prove a
  test exists that fails when `try?` is reintroduced.

## Out of scope

- Daemon lifecycle (start/stop the router). Registered separately; a surface offering to start a
  router the control API cannot start is the inert-button problem, not this.
- Any change to the control API's wire shape. R3 owns that, and F3's 23 recorded fixtures are the
  contract R4 will diff against — this item consumes them, it does not alter them.
- The two surfaces themselves. M2 and M3 own their own rendering.

## Acceptance

A surface built on `ServerStateTracker` can render, from the tracker alone and with no direct
client access: the router not running, an unauthorized token, a stale snapshot with a live poll
failure, and a healthy live state. Each demonstrated by an exercised test rather than by a build
gate.
