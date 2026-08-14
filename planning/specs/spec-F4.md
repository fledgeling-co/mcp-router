# spec-F4 — ServerStateTracker cannot report failure

**Status:** Ready for Work · **Category:** foundation · **Depends on:** F3 (merged) · **Blocks:** M2, M3
**Branch:** `ai/f4` · **Worktree:** `.worktrees/F4`
**Design reference:** `design/mocks/html/f4-tracker-states.html` · `DESIGN.md` §5, §6
**Practices:** `planning/practices/SWIFT_PRACTICES.md` (binding), `planning/practices/CODING_PRACTICES.md` (language-agnostic rules)

---

## Feature description (verbatim from the brief)

> `app/Sources/MCPRouterKit/Control/ServerStateTracker.swift`, on `main`. Found by the M1 runner
> during its plan gate and verified in source by the orchestrator before scheduling.
>
> Two faults, both of which make a failure state unrenderable:
>
> 1. **Every typed error is discarded.** `pollLoop()` is
>
>    ```swift
>    if let response = try? await client.servers() { apply(poll: response) }
>    ```
>
>    `try?` throws away the whole of `ControlAPIError` — `routerNotRunning`, `unauthorized`, a 5xx,
>    a decode failure. The loop simply retries. F3 went to real trouble to make those errors typed
>    and distinguishable (there is a test asserting `unauthorized` is a different value from
>    `routerNotRunning`), and this is the one place that consumes them, throwing all of it away.
>
> 2. **`phase` is pinned to `.disconnected` when there is no stream.** `run()` starts
>    `consumeStream()` only `if stream != nil`, and `apply(phase:)` is called from nowhere else. The
>    initialiser defaults `stream` to `nil`. So a tracker constructed the ordinary way reports
>    `.disconnected` forever, whatever the router is actually doing — and a surface that trusts
>    `phase` shows a disconnected chrome over live data.
>
> **Why it is its own item.** DESIGN.md §5 requires nine states with real copy for the unhappy
> paths. M2 (Activity) and M3 (Servers board) are both scheduled against this type, and neither can
> meet §5 while the type it reads from is structurally incapable of expressing failure. M1 worked
> around it by polling the client directly, which is the right local call and the wrong thing to do
> three times.
>
> **Scope.** Give `TrackerState` a way to carry the last poll outcome, so a surface can distinguish
> *never loaded* from *loaded and now failing* from *loaded and current*. A stale snapshot plus a
> live error is a real state and the most common one in practice — do not collapse it to an error.
> Decide and document what `phase` means for a tracker with no stream. "No stream configured" is not
> the same condition as "the stream dropped", and `.disconnected` currently claims the second.
> Preserve the distinctions F3 already draws. `unauthorized` must not become "an error". Red-green
> every guard: each must be observed failing before it counts. In particular, prove a test exists
> that fails when `try?` is reintroduced.
>
> **Out of scope.** Daemon lifecycle (start/stop the router). Any change to the control API's wire
> shape — R3 owns that, and F3's 23 recorded fixtures are the contract R4 will diff against. The two
> surfaces themselves; M2 and M3 own their own rendering.
>
> **Acceptance.** A surface built on `ServerStateTracker` can render, from the tracker alone and
> with no direct client access: the router not running, an unauthorized token, a stale snapshot with
> a live poll failure, and a healthy live state. Each demonstrated by an exercised test rather than
> by a build gate.

---

## The shape of the fix

Two facts, tracked independently, because they fail independently.

```swift
/// What the last poll produced, and whether anything is behind it.
public enum LoadState: Equatable, Sendable {
    case loading                      // no poll has completed
    case loaded                       // the last poll succeeded
    case failed(ControlAPIError)      // failed, and none has ever succeeded
    case stale(ControlAPIError)       // failed, but an earlier one succeeded — `servers` is that snapshot
}

/// Whether an event stream exists at all, and what it is doing if it does.
public enum StreamCondition: Equatable, Sendable {
    case notConfigured                // polling-only, by design — not a fault
    case phase(StreamPhase)           // F3's type, unchanged
}

public struct TrackerState: Equatable, Sendable {
    public var servers: [MCPServer]
    public var load: LoadState
    public var stream: StreamCondition
}
```

`.failed` and `.stale` carry the same error and mean opposite things. `.failed` means the pane *is*
the error — nothing has ever loaded. `.stale` means the servers are real and only the refresh is
broken, so the data stays and the error goes above it. A two-case ok/error model cannot express the
second, which is why the brief names it as the state most likely to be collapsed.

`StreamCondition` wraps `StreamPhase` rather than adding a case to it. `StreamPhase` is F3's, it is
`String`-raw-valued and `CaseIterable`, and R4 diffs F3's 23 recorded fixtures against the Swift
router — widening a type that contract already pins would move the contract. Wrapping expresses
"there is no stream" without touching what a stream reports about itself.

---

## Acceptance criteria

Each is testable and each maps to an exercised test, not a build gate.

| # | Criterion |
|---|---|
| **A1** | A poll failure with `.routerNotRunning` and no prior success puts the tracker in `.failed(.routerNotRunning)`, readable from `state()` alone with no client access. |
| **A2** | A poll failure with `.unauthorized` puts the tracker in `.failed(.unauthorized)`, and that value is `!=` `.failed(.routerNotRunning)`. F3's distinction survives the tracker. |
| **A3** | A successful poll followed by a failing poll yields `.stale(error)` **with the earlier servers still present**. The snapshot is not cleared and the state is not `.failed`. |
| **A4** | A successful poll yields `.loaded` with the router's servers in the router's order — the healthy live state. |
| **A5** | `.loading` is the initial value and is distinguishable from `.loaded` with an empty server list. An empty array alone never means "still loading". |
| **A6** | A tracker built with no stream reports `stream == .notConfigured`, never `.phase(.disconnected)`. |
| **A7** | A tracker built **with** a stream reports `.phase(...)`, and a phase event moves it. `.notConfigured` and `.phase(.disconnected)` are different values. |
| **A8** | `apply(phase:)` on a tracker with no stream does not fabricate a stream condition — a polling-only tracker cannot be made to claim a stream state. |
| **A9** | Recovery works: `.stale(error)` → a successful poll → `.loaded`, with the banner-clearing transition observable through `updates()`. |
| **A10** | Every typed `ControlAPIError` case reaches the tracker intact — including `.server(status:message:hint:)` with its hint, which is the difference between a dead end and a next step. |
| **A11** | Subscribers on `updates()` are notified of a poll **failure**, not only of a success. A surface that only re-renders on success can never show a failure state. |
| **A12** | The nine `DESIGN.md` §5 states are each derivable from a `TrackerState` value, per the table in `design/mocks/html/f4-tracker-states.html`, and that mapping is asserted to be total. |
| **A13** | The copy for the two full-pane conditions in the F4 mock is the copy `ControlAPIError` ships — asserted verbatim, extending F3's `ControlCopyTests` pattern to the new specimen file. |
| **A14** | A red-green pass exists for every guard, and specifically: reintroducing `try?` in `pollLoop()` makes a named test fail. Recorded in the ledger below. |
| **A15** | Nothing in F3's recorded fixtures under `app/Sources/MCPRouterKit/Control/Fixtures/` is altered. `git diff --stat` on that directory is empty. |

---

## State matrix — DESIGN.md §5, with real copy for the unhappy paths

Rendered specimens: `design/mocks/html/f4-tracker-states.html`.

| §5 state | `TrackerState` | Copy (real, not placeholder) |
|---|---|---|
| Loading | `load: .loading` | *(no copy — skeleton at real 56pt row geometry; nothing is known yet)* |
| Default | `.loaded`, servers non-empty | the populated board, router's own order |
| Empty | `.loaded`, servers empty | "No servers yet" / "The router is running and has none declared. Add one and it will start on its first tool call, not before." / **Add a server…** |
| Partial | `.stale(error)` | "These servers are from the last successful check" / "Updates have stopped — *«error.advice»*. What you can see is still accurate as of that check; nothing has been removed." / **Check again** |
| Error | `.failed(.unauthorized)` | "This app isn't authorised to talk to the router" / "The control token was rotated or removed. Re-pair to continue — your servers and their history are untouched." / **Re-pair…** |
| Offline | `.failed(.routerNotRunning)` | "The router isn't running" / "Nothing is listening on the control port, so there is nothing to show yet. Starting it takes a moment and your servers stay exactly as you left them." / **Start the router** |
| Success | `.stale`/`.failed` → `.loaded` | *(no copy — the banner leaves, rows refresh in place; macOS does not toast a click)* |
| Disabled | `stream: .notConfigured` | "Live call log off — this window polls every 5s" (a reason, not a fault colour) |
| Overflow | any, long `server.name` | truncates at the row; full value kept on the model for M3's inspector; row height stays 56pt |

The Error, Offline copy is **not authored here**. It is `ControlAPIError.headline` / `.advice` /
`.actionLabel` from F3, and A13 asserts the mock contains it verbatim.

---

## Triage — 2026-08-14

**Grounding.** `TrackerState` has **zero consumers** outside `ServerStateTracker.swift` and
`ServerStateTrackerTests.swift` (verified by grep across `app/Sources` and `app/Tests`). Reshaping it
is therefore a contained change. `StreamPhase` is used by `ControlEventStream` and the tracker; it is
**not** modified. M1 does not consume the tracker at all — it polls the control client directly as a
local workaround, so this change cannot disturb its worktree.

**Readiness: READY.** The defect is verified in source, the fix shape is determined by the brief's
own scope section, and no essential question requires a human.

### Assumptions recorded (autonomous run)

1. **No timestamp on the stale state.** The tracker does not observe when the last good poll landed,
   and `DESIGN.md` §6 forbids displaying a figure no source measured. "The last successful check"
   carries the meaning without a number. A timestamp would be a reasonable later addition; it is not
   required by any acceptance criterion and adding it would widen the type beyond the brief.
2. **No compatibility shim for `phase`.** The old `TrackerState.phase` property is replaced by
   `stream`, not kept alongside it. A shim returning `StreamPhase?` would reintroduce exactly the
   ambiguity this feature removes, and there are no consumers to break.
3. **`.stale` is entered on the first failure after any success**, not after N consecutive failures.
   A retry threshold would hide a real failure for one interval, and the reconnect policy that owns
   "how hard to try" already lives on the stream, not the poll.
4. **`apply(pollFailure:)` is public**, matching `apply(poll:)` and `apply(record:)`. The tracker's
   existing design lets a caller drive it directly for tests and for surfaces that poll on demand;
   an internal-only failure path would make the failure states untestable from outside the module.
5. **Existing tracker tests are updated, not weakened.** `phaseIsTracked` asserted
   `state.phase == .disconnected` on a stream-less tracker — the exact defect. It becomes an
   assertion of the corrected semantics. This is a changed type, not a loosened test, and the count
   of assertions goes up rather than down.

### Codex cross-family spec review — `gpt-5.6-sol`, effort `max`, read-only

Verdict and disposition recorded in **Out-of-family gates** below.

---

## Out-of-family gates

| Stage | Model | Verdict | Accept / Reject |
|---|---|---|---|
| Triage spec review | `gpt-5.6-sol` @ max | *see below* | *see below* |
| Plan review | `gpt-5.6-sol` @ max | *see below* | *see below* |
| Work Phase D completeness critic | `gpt-5.6-sol` @ max | *see below* | *see below* |

*(filled in as each gate runs)*
