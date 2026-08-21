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

---

## Delivered — gap-fix 2, 2026-08-21

### The scanner was rebuilt rather than patched

Six controls added to the delivered scanner would have made the set longer. Every one of the seven
defects found so far — the panel's two and the verifier's five — is an instance of exactly two
approximations standing in for Swift's own grammar:

- **comment and literal lexing** done by a line's first three characters and a truncation at the
  first `//` (`D-g3-l`, `D-g3-m`, and the block-comment half of `D-g3-n`);
- **block structure** read from indentation (`#if` at column 0 and tabs, the rest of `D-g3-n`; the
  panel's wrap-counting was the same mistake one layer up).

Both are gone. `Delexer` (`PoolAwaitBoundDelexer.swift`) implements Swift's comment and
string-literal grammar — line, block, **nested** block, single-line, multi-line, raw at any hash
count, escapes, interpolation, and a literal nested inside an interpolation — blanking each byte in
place so the output has the same length and the same line breaks as the input. `AwaitBoundScan`
then walks **brace balance** outward from the call and reads the statement each enclosing `{`
terminates, back to the previous `{`, `}` or `;`. Indentation is consulted nowhere.

Three named residues of the old scan close as side effects: a newline between the call's name and
its paren is now matched, `awaitEvent (` with a space is read as the wrapper, and a `{` or `}`
inside a literal is no longer block structure. `func ` is still tested before `awaitEvent(` on an
opener, and that is still load-bearing — it is what stops `func awaitEvent(…) {` wrapping its own
body.

### How the control set was established as complete rather than longer

The population to cover is not "shapes somebody might write", which is open. It is the two grammars
the scanner now implements, which are closed and enumerable. **32 controls**, split by family and
each asserting both directions — which lines are call sites, and which of those must report.

Each was then held to the standard this repo applies to any guard: **it must have been seen to
fail.** Sixteen single-mechanism mutations of the classifier, applied one at a time and restored
from a `cp` backup:

| mutation | mechanism removed | controls red |
|---|---|---|
| M1 | block comments close at their innermost terminator | 1 |
| M2 | literal stripping | 7 |
| M3 | interpolation tracking | 1 |
| M4 | escape handling | 2 |
| M5 | the `func ` terminator on an opener | 1 |
| M6 | the opener span, cut back to the call's own line | 1 |
| M7 | brace-depth bookkeeping | 2 |
| M8 | line comments | 1 |
| M9 | position-preserving blanking of non-ASCII | 1 |
| M10 | the `(` boundary after the call's name | 1 |
| M11 | the old same-line `awaitEvent(` shortcut, reinstated | 3 |
| M12 | block comments | 2 |
| M13 | `isBounded` always true | 19 |
| M14 | `isBounded` always false | 11 |
| M15 | the leading-dot requirement on a call | 1 |
| M16 | block comments never close | 2 |

**16 of 16 mutations red, and all 32 controls red under at least one of them.** M11 is the
instructive one the brief asked about: it reinstates the single line this pass deleted and reds
exactly the three `D-g3-l` shapes, which is the direct in-repo demonstration that those controls
discriminate the defect they were written for.

Two controls were rewritten during this because they did **not** discriminate as first drafted.
`"\(d["k"]) x"` re-synchronises by accident when interpolation tracking is removed, so the needle
was moved inside the nested literal, where the two readings actually disagree; and no fixture had a
non-ASCII byte in code position, so nothing could catch a delexer that dropped bytes instead of
blanking them. Both facts came from running the matrix, not from reading the code.

### What is outside the claim

Complete with respect to those two grammars; **not** complete with respect to Swift. Stated in the
source rather than implied: a call reached through a stored function reference or a bare
`awaitReap(…)` with no receiver carries nothing to match; a call inside a nested `func` within a
wrap reports unbounded, because the walk stops at the enclosing `func`; `#if` branches are read as
though every branch compiles; the three directories in `D-g3-u` are outside the scanned trees; and
a bare call added to `PoolAwaitBoundTests.swift` itself is excluded with the needles it is spelled
with. `D-g3-t` is unchanged — the gate asserts the wrap exists and says nothing about its contents.

The controls are deliberately **not** excluded from the scan. Every needle in them sits inside a
literal, so a scan that reads one as code is a scan whose literal handling is broken, and the
standing-constraint test then reds naming the control file — a true report rather than a false one.

### `D-g3-q`, deferred with a reason that was tested

Both accessors replaced with an immediate `return`: **only `PoolReapingTests.swift:101` reds, 4 of
4 runs at 0% idle.** `PoolTests.swift:144` stayed green where the verifier saw it red 4 of 4, so
four of the five sites showed no mutation power here and that site's power is load-dependent.

The reason was measured rather than argued. A probe printing which branch `awaitSessionEnded` takes
reports `PROBE-EARLY-RETURN` **3 of 3** and `PROBE-AWAITS-WATCHER` **0** — at every one of the three
`awaitSessionEnded` sites the handle is already gone and the accessor awaits nothing, whatever the
caller does. That is `D-g3-g`'s mechanism, so `D-g3-g` is the remedy and no call-site change can
substitute for it. `D-g3-g` stays deferred by this pass's scope, so `D-g3-q` does too.

### Gates

`make test` **0** and **0**; `make lint` **0** over 497 files; `make parity` **0**;
`make acceptance-r6` **0**. The assigned mutation — deadline and sleep on `defaultIdleMs` while the
arming still records `idleMs` — reds at **exit 2 after 11.280 s**, at `PoolReapingTests.swift:98:29`
naming *timed out after 10.0s waiting for: `own` to be reaped under the arming it just made*. All
mutated files restored from a `cp` backup. The machine sat at **0.0% idle** throughout, with two
sibling runners live in the same repo.
