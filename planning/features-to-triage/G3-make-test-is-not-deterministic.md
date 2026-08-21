# G3 — `make test` is green on the second run, which is not a gate

**Requirement:** the fleet's evidence contract. Every item in this fleet quotes `make test`
in its bundle. **Found by:** the R6 and M23 verifiers independently, on the same night, in
different worktrees — not by reading the test.

## What is wrong

`app/Tests/RouterCoreTests/PoolReapingTests.swift:61`, the test named *P6 — a per-server
idle window overrides the default*, released a lease on a server configured with
`idleMs: 25`, slept 150 milliseconds and asserted the upstream had been reaped:

```swift
let lease = try await pool.lease("a")
await pool.release(lease)
try? await Task.sleep(nanoseconds: 150_000_000)
#expect(await !pool.isLive("a"))
```

Under whole-suite load the reap had not happened at the 150ms mark and the assertion
failed. Run in isolation it passed, four times running. R6's first `make test` exited 2
and its second exited 0 on an unchanged tree; M23's exited 2 twice.

The pool is not wrong. `armReap` computes `ContinuousClock.now + idleMs`, starts a task
that sleeps that long, and the woken task re-checks four invariants before closing
anything. All of that is correct and none of it promises to finish inside a window the
test picked. **The defect is the test's model of when to look.**

## Why this is not "a flaky test is annoying"

A gate that is green on the second run is not a gate. It teaches every future reader that
the correct response to red is to run it again — which is precisely the move that hides a
real regression, and this repository has already recorded the cost of the label: M5 found
a data race in `StubHTTP` that had been *"mislabelled a flake"*, and the ledger's own note
is that the label was the dangerous half.

## Why sleeping longer was the wrong fix

Three reasons, one of them measured during this item.

**It moves the threshold rather than removing it.** 150ms buys nothing on a machine that
is busier than the one the number was chosen on, and no number is safe on a machine
somebody else is also using.

**Nobody can say where the threshold is.** On the morning of 2026-08-21 another project
left 32 orphaned busy-loops on this machine; it sat at load average 548 across 3001
processes for 2h48m, and a `make test` run inside that window exited 1 with *"Test run
with 1543 tests in 193 suites failed after 4.480 seconds with 1 issue"*. Which test failed
is unrecoverable — the output was piped through `tail -6`, which kept four passing lines
and the summary. This test is the strongest candidate and a strongest candidate is not a
name, so that failure stays **unattributed**.

**And the threshold could not be found deliberately.** See *The reproduction that failed*
below: at load average 114 with the test process at the lowest priority the old test still
passed three times out of three. So the failure point is somewhere between load 114 and
load 548, and choosing a sleep value means choosing a load average to be correct at.

## The fix: read the arming, or await the event

Two kinds of observation replace every one of them, and neither one contains a duration.

**Read what the arming chose.** A claim about *which* idle window applies is a claim about
the integer the pool resolved to, not about what has happened 150ms later. Each arming now
carries `idleMilliseconds` — the same local that computes the deadline and drives the
sleep — and P6 asserts it exactly: 25 for the server that asked, 600_000 for the one that
did not. No clock is read, so there is nothing a slow machine can move and nothing a later
reader can widen. Under mutation it reads `(armed.idleMilliseconds → 600000) == 25`.

That is the second design. The first compared the two armings' *deadlines*, which the
out-of-family panel took apart: two deadlines captured minutes apart can order wrongly for
a reason that is not the pool's, and a window of 599 seconds compares as smaller than a
600-second default while being just as wrong.

**Await the event itself.** Where the claim really is about the outcome, the pool awaits
its own task and returns when the outcome has landed. `awaitReap(_:epoch:)` returns once
the reap has run: `Task.sleep` is at-least, and `deadline` is computed *before* the task
exists, so the woken timer's own deadline check cannot fail. A busy machine makes the test
slower instead of wrong. `awaitSessionEnded(_:handle:)` is the same shape for eviction, and
`waitingCallers` reaching the expected count is the same shape for cohort arrangement.

The awaiting happens **inside** the actor rather than by handing a task out, and that works
because an actor releases its executor at a suspension point — the timer gets the actor it
needs. Naming the epoch or the handle is what makes each wait exact: an arming that is no
longer installed returns immediately, because the only ways it can have gone are that it
already fired or that something superseded it, and the caller's next assertion is what
tells those apart.

The precedent is in the same file. P6a — *a woken timer from a previous arming cannot
reap* — already refused to test its guard through timing, and its comment says why: *"a
timing test here passed even with the guard removed, which made it worthless as
evidence."* That is the same argument arriving from the other side. A window hard to hit
on purpose is also a window hard to miss on purpose.

## What changed in production, and why the test could not be fixed without it

Three read-only accessors on `UpstreamPool`, next to `currentIdentities` — which exists
for exactly this reason and carries exactly this argument in its own doc comment — plus
`Sendable` on `ReapTimer`, whose every member already was.

| Added | Returns | Why a test cannot do without it |
|---|---|---|
| `releaseObservingReap(_:)` | a `ReapArming` | The release and the reading of what it armed must be **one** actor operation. Two hops leave a gap a 25ms window can expire inside, which is this item's own defect one layer in |
| `armedReap(_:)` | a `ReapArming?` | For asserting there is **no** arming — a claim no amount of waiting can establish. Safe as a second hop precisely because nothing can appear in the gap |
| `awaitReap(_:epoch:)` | — | The reap runs inside a task the actor owns. Nothing else changes before it lands, so there is no other observable to wait on |
| `awaitSessionEnded(_:handle:)` | — | Same, for eviction |
| `waitingCallers(_:)` | `pendingWaiters` | A cohort test must open its gate once the joiners have arrived. Arrival is recorded only here |

`ReapArming` is a new value type carrying the epoch and the resolved window. `ReapTimer`
gains `idleMilliseconds` and **loses** `Sendable`: it holds the live task and no longer
travels anywhere.

None of them is `public`; they are reachable through `@testable import` and nothing in
`RouterCore`, the app or the CLI calls them. No behaviour changed — this is the fix
touching no product code, which is what the item said it was.

One argument the accessors rest on, stated so it can be checked rather than assumed:
`waitingCallers` cannot be observed early because `lease()` writes `pendingWaiters += 1`
and then enters `acquire()`, which runs to `await flight.task.value` with no intervening
suspension point. The actor is therefore never released between the increment and the
joiner parking on the shared flight, so any observation of the count from outside is an
observation of a caller that has already joined.

## The sibling survey

Every fixed sleep in the three pool suites, classified. **Exposed** means load can make it
report a failure that is not there.

| Where | Test | Was | Class | Now |
|---|---|---|---|---|
| Reaping:37 | P5 warm is never reaped | 150ms, then still live | negative | **Fixed** — no timer is armed at all, which a late reap cannot satisfy |
| Reaping:48 | P6 idleMs zero disables reaping | 120ms, then still live | negative | **Fixed** — same |
| Reaping:61 | P6 per-server window wins | 150ms, then reaped | **exposed** | **Fixed** — two armings compared, then the timer awaited. *The filed defect* |
| Reaping:107 | P8 self-closed is evicted | 60ms, then evicted | **exposed** | **Fixed** — awaits the end-watcher |
| Reaping:126 | P8a stale close cannot evict | 60ms, then evicted | **exposed** | **Fixed** — awaits the end-watcher |
| Reaping:178 | P11 a cohort counts once | 20ms before opening the gate | **exposed** | **Fixed** — waits for two waiting callers |
| Pool:66 | P2 one open for three callers | 20ms before opening the gate | **exposed** | **Fixed** — waits for three waiting callers |
| Pool:126 | P4 no reap while in flight | 120ms, then still live | negative | **Fixed** — no timer is armed while a call is outstanding |
| Pool:130 | P4 …and it closes after | 120ms, then reaped | **exposed** | **Fixed** — awaits the timer's task |
| Lifecycle:41 | P8 a self-ended session is closed | 80ms, then shut down | **exposed** | **Fixed** — awaits the end-watcher |
| Lifecycle:61 | P8 eviction precedes the log | 60ms, then a lease | **exposed** | **Fixed** — waits for the eviction, *not* the watcher (below) |
| Pool:92 | P2a a late start is closed | 20ms before opening the gate | safe | Left. Losing the window lets the start install and shutdown force-reaps it, so the assertion holds either way — the test proves less, never fails |
| Pool:98 | P2a …the session was shut down | 50ms before asserting | safe | Left. Dead weight: both the lease attempt and `shutdown()` are already awaited above it |
| Lifecycle:108 | P9 a second shutdown awaits the first | 30ms before the second call | safe | Left. Losing the window means the follower arrives after teardown finished, and shutdown is idempotent, so it passes vacuously |

Eleven removed, three left, one helper poll added. The three left are **vacuous-on-loss,
not false-red**: load can make each prove less than it means to, never report a failure
that is not there. Each is a deferred-register row.

`Lifecycle:61` is the one that could not use the watcher. Its whole point is to take a
lease *while the close is still being logged*, and the log is deliberately blocked for
300ms — awaiting the watcher would wait the log out and destroy the window. Eviction
precedes the log and `isLive` reports it, so it waits on the eviction instead.

## What is still a number, and why it is not a threshold

`waitUntil` in `PoolTestSupport.swift` polls every 2ms and gives up after ten seconds. Those
ten seconds are a **deadlock breaker, not the observation**: the events are actor hops
measured in microseconds, so it is four orders of magnitude of headroom, and its expiry is
reported as a failure naming the condition — a mutation that stops the event happening
fails with a reason instead of hanging the suite. Nothing about a verdict depends on it
short of ten seconds of total starvation, by which point every other lane has failed too.

It was thirty seconds first, and the mutation gate is what argued it down: killing eviction
made the run take 33 seconds to say so, and a gate that slow is one nobody runs.

## Mutation evidence

`SWIFT_PRACTICES` §7: an assertion nobody has watched fail is not known to bite. Four
mutations, each applied to the pool and then restored.

| Mutation | What went red, and on what | Gate |
|---|---|---|
| `let idleMs = defaultIdleMs` — the per-server window is ignored | P6 per-server on `(armed.idleMilliseconds → 600000) == 25`; P6 zero-disables on `ReapArming(epoch: epoch#1, idleMilliseconds: 20) == nil` | 6s |
| `reapIfStillDue` stops calling `reap` | P6 per-server and P4 in-flight, both on `!isLive` | 4s |
| the `config.warm == true` guard removed | P5, on a warm server that armed a 20ms timer | 3s |
| `sessionEnded` stops evicting | P8, P8a and both lifecycle P8s, on `!isLive`, `shutdownCount == 1`, `opens == 2`, handle identity, and `waitUntil` naming the condition it gave up on | 13s |
| `release` stops re-arming | P6 per-server and P4 on `releaseObservingReap → nil`, P4a on the epoch counter, P6a on a missing epoch | 4s |
| *(restored)* | — | **exit 0**, 3s |

The first three mutations cover the read-the-arming half and the second covers the
awaited half, so both halves of the replacement have been seen to fail. The fifth is the
one that proves `releaseObservingReap` is not merely returning something.

**Two defects in the fix were caught by running the mutations, which is the reason to run
them.** The first cut of P4 guarded its `await` with `#require(window <
.milliseconds(60000))` — the pool's configured default. Under mutation the armed window
*is* that default minus a few microseconds, so the guard passed and the test then awaited
a sixty-second timer: the suite took **63.968 seconds** to agree with a mutation it was
supposed to catch. The guard is gone rather than improved — P4's pool now sets both
windows short, so the await is bounded whichever value the pool picks. The second: killing
eviction cost 33 seconds, 30 of them inside `waitUntil`'s deadlock breaker, which is what
argued that number down to ten. A gate that takes half a minute to agree is one nobody
runs.

## What three out-of-family reviewers found

The whole diff went to `gpt-5.6-sol`, `gemini-3.7-flash-high` and `grok-4.6` inline, with
the pool's mechanics described rather than left to be discovered. All three delivered.
Codex refused the first invocation — *"Not inside a trusted directory"* — and produced no
`-o` file at all, which is the signal to check rather than its exit code; re-run from
inside the repo it answered.

**They found this fix carrying the defect it was written to remove, and I had not.** Codex
marked it CRITICAL, Gemini MAJOR, Grok reached it from the other end. `release()` and then
`armedReap()` are two actor hops, and a 25-millisecond window can expire inside the gap:
the timer fires, the reap clears it, and the test reads `nil` for a pool that behaved
perfectly. A narrower window than the original 150ms, and exactly the same shape.

Everything they raised, and what was done:

| Finding | Lanes | Taken |
|---|---|---|
| `release` then observe is itself a race | all three | **Yes** — `releaseObservingReap` does both in one actor operation |
| Comparing deadlines does not prove which window was chosen; 599s passes | codex, grok | **Yes** — the arming carries the resolved integer and it is asserted exactly |
| Handing a live cancellable `Task` to a test is the wrong seam | all three | **Yes** — no task leaves the actor; `awaitReap` and `awaitSessionEnded` await from inside |
| `waitUntil` records an issue and carries on, so one timeout reports as a cascade | gemini | **Yes** — it throws |
| Its poll swallows cancellation and becomes a 30-second busy spin | codex, grok | **Yes** — cancellation-aware, and the message says which exit it took |
| Capturing the end-watcher after `release` is the same race again | codex | **Yes** — the tests name the handle they expect to lose instead |
| The `waitingCallers` argument is correct but is an unenforced invariant on `acquire` | codex, grok | **Partly** — it is stated in the accessor's doc comment; nothing enforces it |
| `isLive("inherits")` is a residual clock dependency, do not call it clock-free | grok | **Yes** — labelled in the source as the 600-second dependency it is |
| `await task.value` proves completion, not a reap | codex, grok | **Noted** — true, and the `!isLive` that follows is what makes it a reap witness |
| Inject a clock into the reaping path instead | gemini, grok | **No** — deferred as `D-g3-e`, with the reason |
| `try? await Task.sleep` can complete without reaping | codex, grok | **No** — not a defect: the only early return is cancellation, and `cancelReap` also clears the epoch the woken task checks |

All three independently confirmed the `waitingCallers` actor-isolation argument, which was
the question I was least sure of.

## The reproduction that failed, and what it tells you

Deliberate, bounded, and it did not reproduce. Reported because a failed reproduction is a
measurement.

Sixteen self-bounded busy loops on a sixteen-core machine — each `end=$((SECONDS+W)); while
[ $SECONDS -lt $end ]; do :; done`, so a generator cannot outlive its collector however the
collector dies, which is the bug that wrecked this machine this morning. First pass cost
the suite 8% (4.001s → 4.332s) and both trees passed. Second pass kept the same process
count and ran the test process at `nice -n 20` instead, so it took the small share of CPU a
genuinely busy machine leaves. Load average climbed 53 → 114 with 0% idle across six runs.

**The tree as it stood before this item passed three times out of three**, at load averages
53, 74 and 87. The fixed tree passed three times out of three at 97, 101 and 113.

So the old test survives load average 114 and did not survive load average 548. Nobody can
say where in that range it turns over, and that is the whole argument for the shape of this
fix: a sleep long enough for 114 is not evidence about 548, and the number that would be is
not knowable in advance.

## Scope

`app/Sources/RouterCore/Pool/UpstreamPool.swift` and `PoolEntry.swift` (observation only),
and the four pool test files. No product behaviour changed, no parity surface touched, and
the reference router is not involved.
