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
the deadline the pool installed, not about what has happened 150ms later. And it is a
claim about a **relationship** between two armings, so it is asserted as one: P6 now arms
two servers in one pool — one asking for its own 25ms window, one inheriting the pool's
600-second default — and requires `own.deadline < inherits.deadline`. Both deadlines come
off the same clock inside the same millisecond, so whatever the machine is doing moves
both terms together and drops out of the comparison. That is what makes it hold anywhere
rather than on an idle box. Under mutation the two land **22 microseconds apart in the
wrong order** and it fails, which is the point: it discriminates at a scale no sleep could
have been set at.

**Await the event itself.** Where the claim really is about the outcome, the test awaits
the task the outcome happens inside. `await armed.task.value` returns when the reap is
complete: `Task.sleep` is at-least, and `deadline` is computed *before* the task exists, so
the woken timer's own deadline check cannot fail. A busy machine makes the test slower
instead of wrong. The same shape covers eviction (`await watcher.value` on the handle's
end-watcher) and cohort arrangement (`waitingCallers` reaching the expected count before
the fake transport's gate is opened).

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
| `armedReap(_:)` | the installed `ReapTimer` | The deadline and the timer's task are the only two things that say which window the pool chose and when it acted. Both are private state of the actor; from outside, the sole alternative is to sample `isLive` at a moment of the test's choosing, which is the defect |
| `endWatcher(_:)` | the handle's end-watcher task | Eviction happens *inside* that task. Nothing else it touches changes before the eviction lands, so there is no other observable to wait on |
| `waitingCallers(_:)` | `pendingWaiters` | A cohort test must open its gate once the joiners have arrived. Arrival is recorded only here |

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

`waitUntil` in `PoolTestSupport.swift` polls every 2ms and gives up after 30 seconds. The
30 seconds is a **deadlock breaker, not the observation**: it is three orders of magnitude
above the events involved, and its expiry is reported as a failure naming the condition,
so a mutation that stops the event happening fails with a reason instead of hanging the
suite. Nothing about a verdict depends on it short of thirty seconds of total starvation,
by which point every other lane has failed too.

## Mutation evidence

`SWIFT_PRACTICES` §7: an assertion nobody has watched fail is not known to bite. Four
mutations, each applied to the pool and then restored.

| Mutation | What went red | How fast |
|---|---|---|
| `let idleMs = defaultIdleMs` — the per-server window is ignored | P6 per-server on `armed.deadline (…346916) < other.deadline (…287708)`; P6 zero-disables on a timer that should not exist | 0.304s |
| `reapIfStillDue` stops calling `reap` | P6 per-server and P4 in-flight, both on `!isLive` | 0.081s |
| the `config.warm == true` guard removed | P5 on a warm server that armed a timer | 0.026s |
| `sessionEnded` stops evicting | P8, P8a, and both lifecycle P8s, on `!isLive`, `shutdownCount == 1`, `opens == 2` and handle identity | — |

The second mutation is the one that proves the awaited half bites, and the first proves
the compared half does. Both halves of the replacement assertion have been seen to fail.

**One mutation caught a defect in the fix itself, which is the reason to run them.** The
first cut of P4 guarded its `await` with `#require(window < .milliseconds(60000))` — the
pool's configured default. Under mutation the armed window *is* that default minus a few
microseconds, so the guard passed and the test then awaited a sixty-second timer: the
suite took **63.968 seconds** to agree with a mutation it was supposed to catch. A gate
that takes a minute to agree has stopped being a gate. The guard is gone rather than
improved — P4's pool now sets both windows short, so the await is bounded whichever value
the pool picks and no number is needed to protect it.

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
