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

### Criterion 2, answered: it is neither one fix nor two, and the donor is defective

The brief proposes making `isBounded` strip comments before its same-line test "the way `isCall`
already does", and asks whether that closes both directions or one. Traced against the six measured
defects, it closes **three of six**, and the shared cause it points at is not the real one.

- It closes the three `D-g3-l` misses — the trailing `// TODO`, the block comment and the URL — all
  of which turn on the raw line's text.
- It does **not** close `D-g3-m`. That defect is in `isCall`, the function being copied *from*:
  `isCall` truncates at the first `//` with no notion of a string literal, so
  `let u = "http://x"; await pool.awaitReap(a)` is never seen as a call at all. Copying its
  treatment into `isBounded` propagates the bug rather than curing it.
- It closes **none** of the three `D-g3-n` false fires. Two are indentation and one is `isComment`'s
  three-prefix test; comment truncation reaches neither.

So the "one fix for both directions" reading is false on the evidence — the two directions do not
share the mechanism the brief attributes to them. What they do share sits one level up: **`isCall`
and `isBounded` each carry a hand-rolled model of Swift's comment grammar, and both models are
wrong.** Counted that way it is one fix — replace the model, in one place, feeding both — which is
what shipped. Counted as patches it is three, and it still leaves the other direction untouched,
because indentation-as-block-structure needs its own independent replacement that no amount of
comment handling can reach.

That is why the same-line test was deleted rather than repaired. `M11` reinstates it and reds
exactly the three `D-g3-l` controls, which is the measurement behind this paragraph rather than an
argument for it.

### How the control set was established as complete rather than longer

The population to cover is not "shapes somebody might write", which is open. It is the two grammars
the scanner now implements, which are closed and enumerable. **53 controls**, split by family and
each asserting both directions — which lines are call sites, and which of those must report.

Each was then held to the standard this repo applies to any guard: **it must have been seen to
fail.** Thirty-one single-mechanism mutations of the classifier, applied one at a time and restored
from a `cp` backup:

| mutation | mechanism removed | controls red |
|---|---|---|
| M1 | block comments close at their innermost terminator | 1 |
| M2 | literal stripping | 9 |
| M3 | interpolation tracking | 1 |
| M4 | escape handling | 2 |
| M5 | the declaration terminators on an opener | 2 |
| M6 | the opener span, cut back to the call's own line | 3 |
| M7 | brace-depth bookkeeping | 2 |
| M8 | line comments | 1 |
| M9 | position-preserving blanking of non-ASCII | 1 |
| M10 | the `(` boundary after the call's name | 1 |
| M11 | the old same-line `awaitEvent(` shortcut, reinstated | 3 |
| M12 | block comments | 2 + 1 readability |
| M13 | `isBounded` always true | 35 |
| M14 | `isBounded` always false | 15 |
| M15 | the leading-dot requirement on a call | 1 |
| M16 | block comments never close | 4 |
| M17 | the statement boundary at a line break | 1 |
| M18 | the left word boundary on both markers | 2 |
| M19 | the trailing closure belonging to the call that closes last | 1 |
| M20 | the newline rule on a multi-line literal opener | 1 |
| M21 | the readability report | 3 readability |
| M22 | continuing past an empty statement span | 1 |
| M23 | the brace-balance half of the readability report | 1 readability |
| M24 | `\r` skipped before a multi-line literal's line break | 1 |
| M25 | a line comment at EOF counting as a clean end | 1 |
| M26 | control-flow keywords opening a body rather than a wrap | 4 |
| M27 | `init`/`deinit`/`subscript` as terminators | 1 |
| M28 | an unclosed argument list reading as a wrap | 1 |
| M29 | the right word boundary on both markers | 1 |
| M30 | tabs skipped between the dot and the name | 1 |
| M31 | an argument list ending in `:` being a reference | 1 |
| M32 | a line break after a word no statement can end on | 1 |
| M33 | `Task` as an escaping context | 1 |
| M34 | the wrapper having to be unqualified | 1 |

**34 of 34 mutations red, and all 53 controls red under at least one of them.** M11 is the
instructive one the brief asked about: it reinstates the single line this pass deleted and reds
exactly the three `D-g3-l` shapes, which is the direct in-repo demonstration that those controls
discriminate the defect they were written for.

**M17 is worth reading twice, because it changed its answer.** When the statement boundary at a line
break was first added it reds nothing: the trailing-closure ownership rule already rejected every
shape it was written for, and it was kept only because it makes the opener the statement it claims
to be. Two rounds later the third lane found `if` on the line above its condition, and the fix for
that — a line break is a boundary only when the word before it can end a statement — is what makes
the boundary load-bearing. Removing it now reds a control. A mechanism with no demonstrated power
is not necessarily dead; sometimes it is waiting for the defect that needs it, and the honest
handling is to say which of the two you have evidence for.

Three controls were rewritten during this because they did **not** discriminate as first drafted.
`"\(d["k"]) x"` re-synchronises by accident when interpolation tracking is removed, so the needle
was moved inside the nested literal, where the two readings actually disagree; and no fixture had a
non-ASCII byte in code position, so nothing could catch a delexer that dropped bytes instead of
blanking them. And the `func awaitEvent(…)` fixture carried a trailing `async throws`, which M19's ownership rule
rejects on its own, so the `func ` terminator it was written for was never what decided it; the
signature now ends at its closing paren. All three came from running the matrix rather than from
reading the code.

### What reading the grammar buys, and where it still approximates

**Bought, and each of these is measured rather than argued.** The comment and literal grammar is
Swift's own, so "text that looks like code and is not" is closed by construction rather than by
listing shapes — removing literal stripping reds nine controls at once. Block structure is brace
nesting, which is Swift's own, so indentation, tabs, `#if` placement and where a brace sits cannot
change the answer at all. Delexing is position-preserving — same byte length, same line breaks — so
a reported line number is the source's line number, asserted over every fixture rather than assumed.
And losing sync is now a **named red** instead of a silent miss, which is what caught a raw literal
blanking the tail of a real file.

**Still approximated, and this is where both reviewer rounds found their defects — not in the
lexer.** `statement` and `verdict` decide *which call a brace belongs to* using paren matching plus
a keyword list. That is an approximation of Swift's statement and trailing-closure grammar, and it
is the scanner's remaining soft edge. Named consequences: an accessor block (`get`, `set`,
`willSet`, `didSet`) is not a terminator where `func`, `init`, `deinit` and `subscript` are; a
second **labelled** trailing closure on the wrapper would read as unbounded; and a generic spelling
`awaitEvent<T>(…)` would too. None of the three is reachable with `awaitEvent`'s current signature,
and each of those three fails toward a red on correct source rather than toward a miss.

> **Corrected in gap-fix 3.** That last clause was written about three named shapes and read as a
> claim about the layer, and as a claim about the layer it is false. The next verifier measured
> **two misses and one false fire** in exactly this residue, each pinned by a one-token control: a
> statement label before a control keyword read an unbounded call as bounded; a labelled
> string-literal final argument produced no call site at all; and `Task` inside a string
> interpolation reddened a correct wrap. Two to one toward the dangerous direction, on the first
> serious attempt. **The layer fails both ways and the direction is not predictable from it** —
> which matters, because a claim about which way a residue fails is what decides whether the residue
> is tolerable. All three are fixed and controlled; the three shapes named above are unchanged and
> still unreachable.

Also outside: **Swift 5.7 regex literals** (`/…/`, `#/…/#`) are not lexed, so one carrying a block
comment opener or an odd quote count desynchronises the delexer — the readability guard turns that
into a named red except where the file happens to resynchronise, which was the CRLF shape and is now
closed. `#if` branches are read as though every branch compiles. A call through a stored function
reference or a bare `awaitReap(…)` with no receiver carries nothing to match. A call inside a nested
`func` within a wrap reports unbounded, because the walk stops at the enclosing `func`. The three
directories in `D-g3-u` are outside the scanned trees, and a bare call added to
`PoolAwaitBoundTests.swift` itself is excluded with the needles it is spelled with. `D-g3-t` is
unchanged: the gate asserts the wrap exists and says nothing about what runs inside it, so a closure
captured and escaped from the wrap satisfies it.

The controls are deliberately **not** excluded from the scan. Every needle in them sits inside a
literal, so a scan that reads one as code is a scan whose literal handling is broken, and the
standing-constraint test then reds naming the control file — a true report rather than a false one.

### `D-g3-q`, deferred on scope

**Withdrawn in gap-fix 3: the narrowing this section derived does not reproduce.** This pass ran
both accessors replaced with an immediate `return` and saw only `PoolReapingTests.swift:101` red, 4
of 4 at 0% idle, and wrote `PoolTests.swift:144` up as load-dependent — needing the 30 ms window not
to have elapsed while the machine is busy. The next verifier ran the same mutation at 15.5% idle
falling to 0.6% and a 1-minute load of 127, which is *heavier* contention than this pass had, and
got **both sites red 4 of 4**. Heavier load producing the site this pass said load suppressed
refutes the explanation on its own terms, so the register goes back to the previous verifier's
reading: gutting the two accessors reds `PoolReapingTests.swift:101` and `PoolTests.swift:144`, and
the three `awaitSessionEnded` sites never move.

**The deferral never needed that measurement.** It rests on scope: the remedy is `D-g3-g`, which is
deferred, and a call-site change cannot substitute for it. That much is measured and stands — a
probe printing which branch `awaitSessionEnded` takes reports `PROBE-EARLY-RETURN` **3 of 3** and
`PROBE-AWAITS-WATCHER` **0**, so at every one of the three sites the handle is already gone and the
accessor awaits nothing whatever the caller does. Deferring on scope alone was available the whole
time and needs no contested number; deriving a narrower claim from one machine's timing was the
error, and the orchestrator relayed it into the ledger as fact before anyone re-ran it.

### Gates

Measured on the delivered tree, each to a full log rather than through a pipe:

| gate | exit | output |
|---|---|---|
| `make test` | **0** | `Test run with 1587 tests in 199 suites passed after 4.941 seconds` |
| `make test` again | **0** | `Test run with 1587 tests in 199 suites passed after 4.130 seconds` |
| `make lint` | **0** | `Done linting! Found 0 violations, 0 serious in 497 files` |
| `make parity` | **0** | `parity: 358 vector cases compared (floor 358)` |
| `make acceptance-r6` | **0** | `examined=6 failures=0` |

The assigned mutation — deadline and sleep on `defaultIdleMs` while the arming still records
`idleMs` — reds at **exit 2**, `Test run with 1587 tests in 199 suites failed after 10.589 seconds
with 1 issue`, at `PoolReapingTests.swift:98:29` naming *timed out after 10.0s waiting for: `own` to
be reaped under the arming it just made*. That is the whole property: a named red inside the CI
bound where the unbounded form measured 601.184 s. Every mutated file was restored from a `cp`
backup and the restoration diffed before the gates ran.

One red on an earlier gate run, recorded rather than re-rolled away:
`CallbackLifecycleTests.swift:238` — *the callback listener was cancelled before it bound* — went
red once in six runs, in a file this pass does not touch and which carries three fixed sleeps. It is
the third measured instance of `D-g3-c`'s class and is recorded under `D-g3-s`. Machine idle ranged
from **0.0%** to **44.6%** across the session with two sibling runners live in the same repo.

### The out-of-family round found four more, and the readability guard found a fifth

Each lane was asked to **break** the scanner in both directions rather than to review it. That
question has produced a defect on every round of this item, and it did again — four real ones, all
fixed here and registered as `D-g3-y`:

- the opener span ran back to the enclosing brace, so `log(awaitEvent(x))` on an earlier line bounded
  a later `if` block;
- the span's `awaitEvent(` could belong to an inner call, so `withTimeout(awaitEvent("x")) { … }` and
  `guard awaitEvent(…) != nil else { … }` both read as wraps — the trailing closure now has to belong
  to the call whose arguments close **last**;
- both markers matched mid-identifier, so `mock_awaitEvent(` was a wrap and `if myfunc {` was a
  `func`;
- and, prompted by a lane pointing at Swift 5.7 regex literals as a desync route rather than by any
  lane naming it, a **readability guard**: delexing that ends mid-comment or mid-literal, or leaves
  unbalanced braces, now reports the file as unread instead of as clean.

That guard immediately reported `PrimitiveBodyTests.swift`. A raw literal at `:140` holding two
quote characters — hash, quote, quote, quote, quote, hash — was being read as a multi-line opener
that never closes, blanking the rest of a real file. Swift requires a multi-line literal's content
to start on the next line; the rule now says so. **This is the shape of miss the whole gate exists
to not have**, and nothing but the guard would have shown it: a desynchronised scan finds no call
sites, which looks exactly like a file that had none.

Eight controls and seven mutations were added for that round, and nine more controls with eight
more mutations for the round below. The lanes are recorded in the run
report: gemini delivered, codex was out of credits until 27 August with its header verified, and
grok failed twice — hallucinated output on the direct CLI and out of usage on the `cursor-agent`
fallback.

### A third round on the finished scanner, and three more

The final state went back to the Google lane with the same instruction. Three more real defects,
all fixed here and folded into `D-g3-y`:

- **An `if` on the line above its condition.** `if` ⏎ `awaitEvent("ready") {` is legal Swift, and the
  statement boundary added in round one stopped at that line break, so the span began below the `if`
  and the body read as the wrapper's trailing closure. A line break is now only a boundary when the
  word before it is one a statement can end on.
- **A closure handed to `Task`.** `awaitEvent("x") { Task.detached { await pool.awaitReap(a) } }` is
  lexically inside the wrap and outlives it. This is the one place the scan can tell lexical
  containment from an execution bound, and it now does.
- **Somebody else's method of the same name.** `analytics.awaitEvent("x") { … }` bounded nothing and
  read as a wrap, because `.` counts as a word boundary. The wrapper is a free function, so a
  qualified spelling is now rejected.

Two of the lane's findings were **not** taken, with the reason recorded rather than left implicit.
`awaitEvent<T>(…)` and a second labelled trailing closure would both be read as unbounded — but
`awaitEvent`'s signature has no generic parameter and one closure parameter, so neither is
reachable, and both fail toward a red on correct source rather than toward a miss. The same holds
for a closure passed as an earlier argument alongside a trailing one. All three are listed above
under what is still approximated. **Read these three as three shapes and not as the layer's
direction** — see the correction in that section: the layer they sit in was measured failing toward
a miss twice and toward a red once in the pass after this one.

The lane's last finding is a genuine trade and is kept deliberately: a Swift 5.7 regex literal
carrying an unbalanced brace would trip the readability guard and red CI on correct source. There
are **no regex literals in the four scanned trees today** (checked), the guard's message names a
regex literal as the first thing to look for, and the alternative is the silent miss it was added
to remove. Named as `D-g3-y`'s open edge rather than pretended away.

### The lanes

| lane | family | outcome |
|---|---|---|
| `gemini-3.7-flash-high` | Google | **Delivered twice.** Round one found the opener span, the trailing-closure owner and both word boundaries; round three found the three above |
| `claude-fable-5` at high | Anthropic, substituting for codex | **Delivered.** Ported the implementation into a harness and *ran* every break rather than tracing it — five defects including the CRLF desync that keeps the readability guard green |
| `gpt-5.6-sol` at high | OpenAI | **Down.** `ERROR: You've hit your usage limit … try again at Aug 27th`. Header verified before the refusal: `model: gpt-5.6-sol`, `reasoning effort: high` |
| `grok-4.6` at xhigh | xAI | **Down, four ways.** The direct CLI returned output about an unrelated repository at a 5.6 KB packet; the `cursor-agent --force --model grok-4.6` fallback returned `You're out of usage`; and two runs at a **3.7 KB** packet emitted only narration before the 900 s alarm killed them |

Asking each lane to *break* the scanner rather than review it produced a defect on every round it
was asked — nine across the two that answered, plus one the readability guard found on its own.

### The instrument question, answered rather than assumed

A reviewer argued that a byte scanner is the wrong instrument and that a **compile-time witness** —
a type only `awaitEvent` can mint, required by `awaitReap` — is strictly better. On the property it
is right, and the argument is registered as `D-g3-z` rather than dismissed. It is not taken because
the witness would have to live in `RouterCore` for `UpstreamPool` to name it, and `@testable import`
makes any `internal` initialiser mintable from any test, so making it unforgeable means moving the
bound into `RouterCore` — the layering the accessor's own doc argues against. SwiftSyntax is the same
property with a real parser and costs an exact-pinned pre-1.0 dependency and its build time. The
scan is what fits the constraint today, and what it cannot do is now written down rather than left
to be rediscovered.

### A second out-of-family round, and five more in both directions

The substitute lane (`claude-fable-5`, high) was given the same instruction and did something the
others did not: it ported the implementation verbatim into a harness and **ran** each break rather
than tracing it. Five confirmed defects, all fixed here and registered under `D-g3-y`:

- **A control-flow body reads as a wrap.** `if flags.awaitEvent(ready) { … }` has exactly the shape
  the ownership rule accepts, because a condition carries no closing paren of its own — the same for
  `while`, `for … in`, `switch` and `catch … where`. Five constructed and all five confirmed. The
  opener's first word is now checked against the body keywords.
- **CRLF desynchronises the delexer while leaving it looking clean.** `opensMultiline` skipped
  spaces and tabs before the line break but not `\r`, so in a CRLF file `"""` read as three
  single-line literals and the whole string body was scanned as code. It realigns afterwards, so
  **`endedCleanly` and the brace balance both still passed** — the one break that defeats the
  readability guard as well. A string containing `awaitEvent("ghost") {` then bounds a real call
  below it, and a string containing a call reds on prose.
- **`init`, `deinit` and `subscript` bodies were walked straight through** where `func` terminates.
  A call in the `init` of a type declared inside a wrap ran whenever the type was instantiated and
  read as bounded — the unlisted sibling of the nested-`func` residue.
- **A closure passed as an ordinary argument was a false red.** `awaitEvent("x", { … })` leaves
  `awaitEvent`'s paren unclosed within the opener, and the walk stepped past the only bound there
  is. One formatting choice from the blessed spelling, so it was the most likely of all of them to
  fire on real code.
- **Two smaller false fires:** a tab between the dot and the name made a real call invisible, and an
  unapplied method reference `pool.awaitReap(_:epoch:)` — which awaits nothing — reported unbounded.

The same lane confirmed the round above holds: `withTimeout(awaitEvent("x")) { }`, the `guard` form,
chained trailing closures, second trailing closures, interpolation closures carrying braces, nested
raw and multi-line literals, `#""""#`, `\u{…}`, keypath backslashes and split openers all classify
correctly.

It also corrected one leg of the `D-g3-z` argument, and the correction is taken: a capability
token's source location **can** ride on default `#filePath`/`#line` arguments, so "a breaker that
names its line needs the caller's location" does not block it. What still does is forgeability —
the token type must live in `RouterCore` for `UpstreamPool` to name it, and `@testable import` makes
any `internal` initialiser mintable from any test, so making it unforgeable means moving the bound
into `RouterCore`. That is a real design change with its own evidence to gather, not a gap-fix.
