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

**`codex: usage limit -> claude (downgrade)`.** Every `codex exec` call — down to a one-word probe —
returned `You've hit your usage limit ... try again at Aug 20th, 2026 1:29 PM`. That is
account-level and past this fleet's horizon, verified by the orchestrator on 2026-08-14, so all
three gates ran in-family instead: a fresh `claude -p` opus-5 reviewer per gate, briefed
adversarially (told to refute, and that finding nothing counts as a failed review rather than a
pass). **The weakness this leaves is real and is recorded here rather than smoothed over:** every
reviewer in this pipeline is now Claude auditing Claude, and the cross-family check that exists
precisely to catch what one family's blind spots share did not run.

The trap worth carrying forward: `codex exec` **exits 0 on a usage limit**. A gate keyed on `$?`
records a pass for a review that never ran. The honest tells are the `ERROR` line in the log and a
missing or empty `-o` file.

| Stage | Model | Verdict | Accept / Reject |
|---|---|---|---|
| Triage spec review | `claude -p` opus-5, adversarial (codex downgraded) | Spec accepted; assumptions 1–5 recorded above are its output | 5 accepted / 0 rejected |
| Plan review | `claude -p` opus-5, adversarial (codex downgraded) | Plan accepted at Small tier; file list and step order unchanged | — |
| Work Phase D completeness critic | `claude -p` opus-5, adversarial (codex downgraded) | **18 findings** — see disposition below | 16 accepted / 2 deferred |

### Phase D critic — disposition

The critic was told to refute and that finding nothing would count as a failed review. It returned
18 findings, and the important ones were right: two acceptance criteria were being proved by tests
that pass against the original defect, and one was being proved by a substring search.

| # | Finding | Severity | Disposition |
|---|---|---|---|
| 1 | A14's red-green ledger did not exist | blocker | **Accepted** — this section |
| 2 | Out-of-family gate rows read `*see below*` | major | **Accepted** — table above |
| 3 | A15 asserted by hand, by no test | major | **Accepted** — `fixturesAreUnmodified` |
| 4 | A10 exercised 2 of 5 error cases; `.malformedResponse` nowhere | major | **Accepted** — `everyErrorCaseSurvivesTheLoop`, with an exhaustive `caseName(of:)` switch so a sixth case breaks the build |
| 5 | A10's test hand-injected the error, so it passed against `try?` | major | **Accepted** — now ‹real loop› |
| 6 | A11's test likewise — the criterion closest to the original bug | major | **Accepted** — now ‹real loop› |
| 7 | A12 was a substring search for nine names, not a derivation check | blocker | **Accepted** — the sheet's table is parsed, and `specimensMatchTheSheetsDerivation` bridges specimens to it |
| 8 | The *Disabled* specimen carried `.phase(.live)` — the sheet's **non**-disabled condition | major | **Accepted** — Disabled/Default corrected; finding 7's bridge is what now catches this class |
| 9 | Four unbounded `for await` loops would hang, not fail | major | **Accepted** — one `bounded` helper, used throughout |
| 10 | M55 survived, so synchronous registration has no killing test | major | **Accepted as recorded** — see the ledger note below; not silently closed |
| 11 | `consumeStream()` had no test at all | major | **Accepted** — `streamEventsReachTheTracker` drives a real `ControlEventStream` over `HTTPStub` |
| 12 | Cancelling `run()` published `.disconnected` — a drop that did not happen | major | **Accepted** — guard added, mechanised as `M59` |
| 13 | `AsyncStream` was `.unbounded`; the dedup does not bound a flapping router | major | **Accepted** — `.bufferingNewest(8)` |
| 14 | `continuations` removal hops through an unstructured `Task` | minor | **Deferred** — inherent to `onTermination`, which is `@Sendable` and runs off-actor. Bounded by the actor's lifetime; no leak is observable from outside the type. Worth an item if a surface ever holds many short-lived subscriptions |
| 15 | `hasLoaded` duplicated a fact `loadKind` carries | minor | **Accepted** — now computed, so the disagreeing pair is unrepresentable |
| 16 | `try?` in the matrix test's fixture decode | minor | **Accepted** — now `try`; a missing fixture no longer reports as a modelling collapse |
| 17 | `SteppingClock` ignores its `duration`, so the poll interval is unmeasured | minor | **Deferred** — the interval is F3's `pollInterval` plumbing, not F4's; the §5 copy naming 5s belongs to M2/M3's surface. Suggested child item below |
| 18 | `runLoop` cancels without awaiting, so a loop can outlive its test | minor | **Deferred** — bounded by the parked `SteppingClock`; no cross-test interference observed across the full suite or ten mutation runs |

---

## A14 — the red-green ledger

Every guard was observed failing before it counted. Mutations live in `scripts/red-green.py` and are
applied to the **implementation** only; a mutation that edits a test proves nothing. Run one at a
time in the foreground with `python3 scripts/red-green.py --only M5x`.

| Mutant | Clause | The guard it removes | Result |
|---|---|---|---|
| **M50** | A1 | `try?` reintroduced in `pollLoop()` — the original defect, exactly | **KILLED** (41.4s) |
| **M51** | A3 | `.stale` collapsed into `.failed` | **KILLED** (10.9s) |
| **M52** | A3 | a failed poll deletes the servers it already had | **KILLED** (9.8s) |
| **M53** | A6 | a stream-less tracker born claiming `.phase(.disconnected)` | **KILLED** (8.3s) |
| **M54** | A8 | a phase fabricated for a tracker with no stream | **KILLED** (10.1s) |
| **M55** | A11 | registration deferred out of `updates()` | **SURVIVED** — see below |
| **M56** | A11 | an unchanged state republished every interval | **KILLED** (8.0s) |
| **M57** | A4 | `run()` twice starting a second poll loop | **KILLED** (8.4s) |
| **M58** | A11 | a poll failure recorded but never published | **KILLED** (18.6s) |
| **M59** | A7 | a cancelled `run()` reporting the stream as dropped | **KILLED** (8.6s) |

**9 of 10 killed.** A14's specifically-named requirement — "reintroducing `try?` in `pollLoop()`
makes a named test fail" — is M50, killed, red on
`‹real loop› a router that is not running is reported, not retried in silence`.

**M55 is a recorded survivor, not a pass.** The mutation defers registration into
`Task.detached { await self.register(...) }`. `firstStateIsTheStateAtSubscription` asserts the
invariant that would expose the loss — the first state a subscriber receives must be the one
current when `updates()` returned — over 40 consecutive trials, and the deferred registration won
all 40. The reason is ordering, not coverage: the detached task is created while `updates()` still
holds the actor, so its `await self.register(...)` is enqueued ahead of anything an external caller
can enqueue afterwards.

It is **not** marked equivalent, because it is not. That ordering is an implementation detail of the
actor executor and `Task.detached` runs at unspecified priority, so a priority difference or a
loaded machine can still make it lose. The synchronous `register` is kept because it is a
language-level guarantee rather than an observed schedule, and the 40-trial test is the guard that
catches the deferral on any run where it does lose. What no test can do is force the loss on
demand — a test that tried would be flaky by construction, which is worse than a recorded survivor.

**Two mutation-gate hazards found the hard way**, both now fixed in the harness and worth carrying:

- A mutation can make the suite **hang** rather than fail. M58's first run returned
  `«suite did not terminate»` because the tests it should have killed blocked on `for await`
  forever. A count bound cannot help — a bound that only advances on arrival never advances when
  nothing arrives. Every subscriber assertion now goes through a wall-clock `bounded` helper.
- Running the gate as a **background task and polling its output for a sentinel** killed two
  earlier sessions: the task was killed without writing the sentinel and the poll never returned.
  Run mutants in the foreground, or in bounded chunks whose exit code is read directly.

---

## Status

**Delivered on `ai/f4`, stopped before merge** — the orchestrator serializes finalization.

`make all` green: lint, build, **306 tests**, parity 224/224 vector cases (floor 224). Mutation
ledger 9/10 killed with the survivor recorded above. Acceptance evidence in
`planning/evidence/F4-acceptance.md`.

### Deferred children discovered

| Suggested item | Why | Depends on |
|---|---|---|
| Assert the poll actually sleeps for `pollInterval` | Critic finding 17. `SteppingClock` ignores its `duration`, so nothing catches the interval being wrong, and §5's *Disabled* copy — "this window polls every 5s" — is a claim about that value. Belongs with the surface that displays it | M2 or M3 |
| Bound `continuations` growth for short-lived subscriptions | Critic finding 14. Removal hops through an unstructured `Task` because `onTermination` is `@Sendable`; harmless today, worth revisiting if a surface churns subscriptions | M2, M3 |
