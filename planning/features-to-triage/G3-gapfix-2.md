# G3 gap-fix 2 — the property holds; the scanner meant to keep it holding does not

**Parent:** G3 — `make test` is not deterministically green
**Status:** Untriaged · gap-fix, second pass
**Verdict that produced it:** Needs More Work, 2026-08-21, rung `metamorphic`
**Worktree:** `.worktrees/G3`, branch `ai/g3`, base `b646364`

## Start here: the fix works, and that is not what is blocking

The shipped property is **established**, by the verifier's own re-run rather than the runner's:

| | measured |
|---|---|
| assigned mutation | exit 2, run failed after **14.151 s**, `PoolReapingTests.swift:98:29`, *timed out after 10.0s waiting for: `own` to be reaped under the arming it just made* |
| control (same mutation, P6's wrap removed, `alarm 60`) | **exit 142, zero `Test run with` lines** |
| gates on the merged tree | `make test` exit 0 on **8 runs**, lint 0/494, parity 358/358, `acceptance-r6` `examined=6 failures=0` |

A regression in this class now produces a named red inside the CI bound. That was the blocking finding and it is closed. Everything below is about the guard built around it, and about two things the briefs claim that are not true.

Numbers ran slower than the runner's (14.151 s against 10.461 s) at 0–11% idle with two sibling runners live. That is contention, not divergence.

## B-1 — the standing-constraint scanner is defeated in both directions

`PoolAwaitBoundTests` exists so "the next call site cannot quietly reopen the hole this item was blocked on", and its own doc says "a false red is what this gate exists to not be". The verifier planted **22 constructed call sites across three files**. Both claims are falsified as delivered.

**It misses genuinely unbounded calls** — these read as fine:

- `await pool.awaitReap(x) // TODO: wrap in awaitEvent("…")`. `isBounded`'s first line tests the **raw** line for `awaitEvent(`, so a comment mentioning the wrapper satisfies the check for the wrapper. Drop the paren and it still reds, which pins the mechanism exactly. **The panel already found the mirror image of this** — `// awaitEvent(` as a false *opener* — and it was fixed in the upward walk, one line below the shortcut that still carries the bug.
- `/* awaitEvent( */` and a URL ending `…/awaitEvent(`, same cause.
- `let u = "http://x"; await pool.awaitReap(…)` is **not seen as a call at all**: `isCall` truncates at the first `//`, so the code half is `let u = "http:`. `isCall` strips comments and `isBounded` does not — fixing one by copying the other's treatment closes both.

**It reds on correct or non-code shapes:**

- A correctly wrapped call inside `#if DEBUG` at column 0. The walk takes the `#if` line at indent 0, sets `depth = 0`, and can never step out.
- A call inside a `/* */` block comment — `isComment` matches only lines starting `//`, `*`, `/*`.
- A tab-indented wrapped call — `indent(of:)` counts spaces only.

What behaves correctly and must keep doing so: same-line wrap, nested `if`, multi-line opener, `.awaitReap (` with a space, a `func` whose signature contains the needle, two wraps then a bare call, and `///` prose.

The scan cannot see `PoolAwaitBoundTests.swift` itself, excluded by `#filePath`. The verifier confirmed the exclusion is **by path and not basename** — a same-named copy at `app/MCPRouter/PoolAwaitBoundTests.swift` fired correctly. That is the right design and needs no change.

## B-2 — `D-g3-j`'s fourth correction did not land, and its row says it did

`D-g3-a` is now right at `:96`/`:102`. `D-g3-b` still cites `PoolLifecycleTests.swift:114`; the 30 ms sleep before the follower shutdown is at **`:116`**, and `:114` is blank. It was correct at `4c0f920` and was shifted by the gap-fix commit `f85f29b` itself. So the two rows remain on different numbering bases — **the exact defect `D-g3-j` was opened for** — while `D-g3-j`'s row asserts "All four corrected".

The other three did land and are confirmed: five test-only members at `UpstreamPool.swift:176/186/217/228/244`, with the brief now correctly saying only two of the five are read-only; `struct ReapTimer {` unchanged at `PoolEntry.swift:74` at both revisions; 11 sleeps summing to exactly 960 ms with the multiset matching `3×120 + 2×150 + 2×20 + 3×60 + 80`.

A register row claiming a correction it did not make is worse than the uncorrected row, because the next reader stops looking. Fix both the line number and the claim.

## B-3 — acceptance criterion 3 is vacuous, and it is mine

I wrote it: *"the mutation with the two windows swapped the other way — arming records the default while the deadline uses the requested one. If that also takes ten minutes, the bound is on the wrong side of the await."*

Measured: relaxing `:87` so execution reaches `:98` under the same mutation gives **P6 passing in 2.291 s and the run green**. Mutation B leaves the reap deadline on the requested 25 ms window, so **it could not take ten minutes whichever side the bound is on**. The 3.9–5.3 s red it produces is the resolved-integer claim at `:87` and carries no information about the bound's side.

The runner's stated reason — "fast because the `#require` throws before the await is reached" — is true of the control flow and is not the cause of the timing. Both of us described a criterion by what it looked like it tested.

The bound's side is established by the assigned mutation alone, which is sufficient. So the remedy is either a criterion that can actually distinguish the two sides, or the honest deletion of this one with a note saying the assigned mutation carries the whole claim. **Take the second unless you can construct the first and watch it fail.** This is G4's shape and it is now the sixth entry there.

## What the verifier settled that the runner had called

**Grok's correction is right and was taken correctly.** `await task.value` on a `Task<_, Never>` has no cancellation path, so a group around *that shape* awaits the loser. `AuthorizationURLBox` at `OAuthFlowStarter.swift:82-119` is `withTaskCancellationHandler` around `withCheckedThrowingContinuation` with an `abandon(ticket)` on cancel — a cancellation-aware wait, which a group does bound. The blanket claim was an overclaim; the narrow one is now in source and brief, and `D-g3-k` is the right register for the construction.

**Gemini's CRITICAL was half right, not refuted — reopen it.** Replacing *both* accessors with an immediate `return` reds `PoolReapingTests.swift:101` and `PoolTests.swift:144` in 4 of 4 runs, caught by the caller's next assertion exactly as the doc claims. It never reds `PoolLifecycleTests:44`, `PoolReapingTests:156` or `:177`. **Three of the five bounded call sites pass whether or not the event is awaited at all.** That is wider than `D-g3-g`, which names one mechanism at one site, and it is registered as `D-g3-q`. The runner overruled this finding as refuted by measurement; the measurement supported half of it.

**Gemini's MAJOR holds up.** The five closures only await, and under the assigned mutation the observer sat parked on a 600 000 ms arming while the other 1583 tests ran. But that safety rests on "put work in the closure and that stops being true", which is a doc comment — the scanner asserts the wrap exists and says nothing about its contents (`D-g3-t`).

## Two flakes, measured rather than surveyed

`CallbackListenerTests.swift:108` (150 ms fixed sleep at `:101`) went red **2 of 3 runs**; `OAuthWireTests.swift:263` (3 s fixed sleep at `:262`) once. Both are the exact shape that filed G3, in files `D-g3-c` predicted and nobody had classified. `D-g3-c` estimated around sixty unclassified sleeps; two are now observed red.

They are **not** in this pass's scope — `D-g3-s` records them and the classification is `D-g3-c`'s. Recorded here because a prediction that comes true is evidence about the parent item, and because a future reader should not rediscover them as new.

## Acceptance

1. Each of the three misses in B-1 reds, and each of the three false fires goes green. Add all six to the controls, keeping the seven shapes that already behave.
2. `isBounded` strips comments before its same-line test, the way `isCall` already does. Argue whether that is one fix for both directions or two.
3. A shape nobody has named yet — the scanner has now been broken by a panel once and a verifier once, so state how you established that the control set is complete rather than merely longer.
4. `D-g3-b` cites `:116`, and `D-g3-j`'s row states what it actually corrected.
5. Criterion 3 either discriminates or is deleted with its reason recorded.
6. `D-g3-q` is taken or explicitly deferred with a reason — three of five call sites having no demonstrated mutation power is a bound on what this gate proves, and it should not be left implicit.
7. The gates stay where they are: `make test` green twice, lint 0, parity 358/358, `acceptance-r6` clean, and the assigned mutation still reds inside the bound naming its own condition.

## Scope

`PoolAwaitBoundTests.swift`, `PoolTestSupport.swift`, `UpstreamPool.swift`, the three pool suites, and this item's briefs and register rows. `D-g3-a`…`D-g3-f`, `D-g3-h`, `D-g3-i`, `D-g3-k`, `D-g3-s` and `D-g3-u` stay deferred. `D-g3-o` (the failure message dumps ~13 KB of source before the actionable line, because `#expect` captures `lines`) is a one-line fix inside a file you are editing anyway — take it. `D-g3-v` is a wording fix in the brief: `ReapTimer` conforms to `Sendable` implicitly under `.swiftLanguageMode(.v6)` since all its stored properties are `Sendable`, so the accurate phrasing is "carries no explicit `Sendable` annotation".
