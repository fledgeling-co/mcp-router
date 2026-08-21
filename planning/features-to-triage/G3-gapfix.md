# G3 gap-fix — the fix trades a 150ms false red for a ten-minute nameless one

**Parent:** G3 — `make test` is not deterministically green
**Status:** Untriaged · gap-fix
**Verdict that produced it:** Needs More Work, 2026-08-21, rung `metamorphic`
**Worktree:** `.worktrees/G3`, branch `ai/g3`, base `d544968`

## What the verifier confirmed

The item does what it was filed for, and the verifier says so: eleven of fourteen fixed
sleeps removed, six clean `make test` runs at 1-minute load between 8.4 and 28.6, lint 0/493,
parity 358/358, `acceptance-r6` `examined=6 failures=0`. The `release()` → `armedReap()` race
the panel found is **structurally closed** — both are synchronous actor methods, so there is
no suspension point between them, and the verifier could not reopen it naturally in 80,797
rounds at a 1 ms window under 48 spinners. Widening the gap to 40 ms turns both call sites
red, which is the proof that the atomicity is load-bearing rather than decorative.

`D-g3-a` and `D-g3-b` are now empirically confirmed rather than argued: both directions of
window loss were forced (sleeps removed; sleeps overshot to 800 ms) and both ran exit 0.

## B-g3-1 — the blocking finding

`UpstreamPool.swift:203–206` and `:211–215` await an unstructured `Task` with no deadline.
The effective bound on `awaitReap` is therefore the pool's own armed window, and P6
configures that at 600 000 ms.

The verifier ran the mutation the brief assigns — reap at the *default* window while the
arming records the *requested* one — and measured:

- `make test` killed at a 150 s bound: `exit=142`, **no failing test name**.
- left to run: `Test run with 1583 tests in 197 suites failed after 601.184 seconds with 1
  issue`, and the issue is `PoolReapingTests.swift:98`, not the `armed.idleMilliseconds == 25`
  claim at `:87`, which **passed silently**.

So the assertion the item is built on — read the resolved integer — is a valid proxy for
"the reap happens at that window" only because one local drives both the arming and the
deadline, and nothing enforces that. Split them and the assertion passes, the await blocks
on a ten-minute timer, and the eventual red lands on the residual clock-dependency line
whose message says *"and the default window has not come round"* — which misdescribes the
defect.

Under any CI bound below ten minutes this is a nameless timeout. That is the failure mode
this item's own thesis ranks as worse than a flake, so it cannot ship in the fix for it.

The runner met this exact mechanism inside this item — the 63.968 s P4 incident — and closed
it **locally in P4** by setting both windows to 30 ms at `PoolTests.swift:127–129`, leaving
P6, the headline test, exposed with a 600 000 ms default by design.

## What to build

Bound both awaits the way `waitUntil` is already bounded — a deadlock breaker that throws
naming the condition. This item argued for reducing that breaker from 30 s to 10 s on
precisely this ground, so the instrument is written and the argument is the item's own.

The narrower alternative the verifier names is replacing `awaitReap` at
`PoolReapingTests.swift:93` with `try await waitUntil("own to be reaped") { await !pool.isLive("own") }`,
which is bounded, cancellation-aware and already exists. Take whichever, but the property is
the same and it is what the acceptance reads: **a regression in this class produces a named
red inside the CI bound, not a timeout.**

## Acceptance

1. Re-run the verifier's mutation — deadline and sleep driven by `defaultIdleMs` while the
   arming still records `idleMs`. `make test` goes red **inside 150 seconds** and names an
   assertion about the window, not `PoolReapingTests.swift:98`.
2. The unmutated tree stays green, twice, and the three pool suites alone stay near 0.31 s.
3. ~~A route nobody has named: the mutation with the two windows swapped the *other* way —
   arming records the default while the deadline uses the requested one. If that also takes
   ten minutes, the bound is on the wrong side of the await.~~ **Deleted, and the criterion was
   the orchestrator's rather than the runner's** (`D-g3-r`). It could not report what it was
   named for: that mutation leaves the reap deadline on the requested 25 ms window, so it could
   not take ten minutes whichever side the bound sat on — relaxing `:87` so execution reaches
   `:98` gives P6 passing in 2.291 s and the run green. **The assigned mutation carries the
   whole claim**, and it carries it because the observable that separates the two sides is the
   duration: bounded on the caller's side it reds in 11.280 s naming its own condition, and
   unbounded it runs 601.184 s and names a different line. A second mutation would measure the
   same split, so there is no discriminating version of this criterion to build.

## Four follow-ups, and one of them is this brief

`D-g3-g` — `awaitSessionEnded` returns before the shutdown it is named for. `sessionEnded`
(`UpstreamPool.swift:349–363`) nils the handle synchronously, then awaits
`live.session.shutdown()`, releasing the actor; `awaitSessionEnded`'s guard then sees no
handle and returns without awaiting the watcher, so `PoolLifecycleTests.swift:46`'s
`#expect(session.shutdownCount == 1)` can read 0. Natural reproduction: 0/500 uncontended,
0/74,830 under 32 spinners. **Forced** — a 150 ms shutdown delay, waiting for eviction first
— it yields `shutdownCount = 0`. The assertion rests on the test's actor hop reliably beating
the watcher's, which is a scheduler-ordering assumption of exactly the class G3 exists to
remove. Grok reached it independently. Narrower than the 80 ms sleep it replaced, so it is
deferred rather than blocking.

`D-g3-h` — the two negative `armedReap` sites (`PoolReapingTests:42`, `:55`) can mask a
mutation rather than report one. For a *correct* pool nothing can appear in the gap, which is
the brief's argument and it holds. For a *mutated* pool that wrongly arms a 20 ms timer, the
timer can fire and clear itself in the gap and `#expect(armed == nil)` passes — a false green
in the mutation gate, not a false red in CI. Both bit in practice, so this is a bound on the
gate's power rather than an observed miss.

`D-g3-i` — `waitUntil` skips a final condition check when its poll overshoots the deadline.
`PoolTestSupport.swift:199–204` tests `now < deadline` before `condition()`, so a sleep
waking past the mark reports a timeout without re-checking. Needs the condition to land in
the last 2 ms of a 10-second wait.

`D-g3-j` — **the brief's own "What changed in production" paragraph is wrong on three
counts**, and it is in scope here because a work brief that misstates its own diff is the
`G2` shape. It says three read-only accessors where its own table lists five, `grep` finds
five and the ORCHESTRATOR row says five. It says `Sendable` was added to `ReapTimer`; none
was — `struct ReapTimer {` is unchanged at `PoolEntry.swift:74` at both `e32b185` and HEAD.
Fifteen lines later it says `ReapTimer` *lost* `Sendable`, contradicting itself. Separately
the eleven removed sleeps totalled **960 ms**, not 950 (3×120 + 2×150 + 2×20 + 3×60 + 80),
and `D-g3-a` cites `:92`/`:98`, which are **pre-fix** line numbers — on the delivered tree
they are `:96` and `:102`, while `D-g3-b`'s `:114` is post-fix, so two adjacent register rows
currently use different numbering. Fix all of it.

## Scope

`app/Sources/RouterCore/**/UpstreamPool.swift`, the three pool suites, `PoolTestSupport`, and
this item's brief and register rows. `D-g3-a` … `D-g3-f` stay deferred; `D-g3-g`, `D-g3-h`
and `D-g3-i` are registered and are **not** to be taken here — only `D-g3-j`, which is this
document's own arithmetic.

## What the verifier did not close

The session's unattributed red stays unattributed. Six clean runs between load 8.4 and 28.6
say nothing about the load-548 incident, and the verifier states plainly that it closed
nothing there.
