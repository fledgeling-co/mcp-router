
---

# Delivered — gap-fix 3

## The three shapes, each with its red and its green

Every one was found by a reader constructing source, and every one is pinned by a **one-token**
control: change the single token and the scan changes its answer. Both directions are in the tree.

| shape | before | control (one token changed) | after |
|---|---|---|---|
| `check: if awaitEvent(x) {` around a bare call | `3:BOUND` — a **miss** | label deleted → `3:UNBOUND` | `3:UNBOUND` |
| `await p.awaitReap(name: "own")` | `[]` — **no call site at all** | literal → identifier → `2:UNBOUND` | `2:UNBOUND` |
| `try await awaitEvent("reap at \(Task.currentPriority)") { … }` | `3:UNBOUND` — a **false fire** | `Task` → `Clock` → `3:BOUND` | `3:BOUND` |

**What each was.** `firstWord(of:)` returned `check`, so the `bodyKeywords` guard — added in round two
*because a lane broke exactly this* — never fired and a control-flow body read as the wrapper's
trailing closure. It now steps past a prefix that introduces a statement without being one, which
closed a `case`/`default` clause with it: `case .a: if awaitEvent(x) {` was the same miss through a
door nobody had opened, measured on the pre-fix scanner.

The second is one level up from where it showed. The delexer blanked comments and literals to the
same byte, and `awaitReap(name: "own")` therefore delexed to `awaitReap(name:    )` — the shape of
an unapplied method reference, which `callEnd` discards. **A comment is nothing and a literal is a
value**, and whitespace where a value stood is indistinguishable from absence. Literal bytes now
become `ScanByte.elided`, and so do non-ASCII code bytes, which was the same miss's other door:
`p.awaitReap(name: 名前)` was invisible for the same reason and is now a control.

The third ran the `escapes` test over the opener statement instead of over the callee receiving the
closure. An interpolation is code, so the word really was there. It now reads the owner of the brace.

## The directional claim, corrected

`G3-gapfix-2.md` said the remaining approximation's consequences "each fail toward a red on correct
source rather than toward a miss". That was **true of the three unreachable shapes it named and
false as a statement about the layer**, and the paragraph read as the second. A claim about which
way a residue fails decides whether the residue is tolerable, so the wording is corrected where it
was made, in the suite's doc comment, and in the register.

The corrected claim: **the layer fails both ways, and the direction is not predictable from it.**
The evidence is a count rather than an argument — of the twelve shapes measured against the
delivered scanner this pass, **eight fail toward a miss and four toward a red**:

- Blocking three: 2 misses, 1 false fire.
- The nine the lanes broke it with and this pass did not take (`D-g3-ah`): 6 misses, 3 reds.

A shape found in this layer is a defect until it is measured, not an inconvenience.

## Family C is stated, not closed

The count was one number over three populations of different kinds, and stating the split honestly
is the answer taken. `AwaitBoundControl`'s doc comment now reads:

- **Family A**, the lexical grammar — 19 controls, **closed**: a citable production list, one control
  per production.
- **Family B**, block structure — 12 controls, **closed**: brace nesting, which is what Swift uses.
- **Family C**, Swift's statement and trailing-closure grammar — 38 controls, **open**. `verdict`,
  `statement`, `firstWord`, `continuesStatement` and five keyword lists implement no grammar. Each
  control is a shape somebody wrote down, and the set of shapes somebody might write is exactly the
  open population the other two families escape. The count is a floor on coverage, not a bound on
  the space.

The mutation matrix is stated separately for the same reason: **69 controls, each seen to fail under
at least one of twelve single-mechanism mutations** proves that no mechanism in the code as written
is decorative. That is mutation adequacy of the implementation, and it is a different claim from
covering the grammar the implementation *should* have. Family C is where the two come apart, and
every defect of this round was in Family C.

`AwaitBoundScan` is now three files, split at that seam — the scan, the statement layer, and the
delexer — because the scan file passed SwiftLint's 400-line `file_length` default.

## `D-g3-q`: the derivation is withdrawn

Gap-fix 2 saw `PoolTests.swift:144` green 4 of 4 at 0% idle and derived a load-dependence from it.
The verifier ran the same mutation at 15.5% idle falling to 0.6% under 1-minute load 127 — *heavier*
contention than gap-fix 2 had — and got **both sites red 4 of 4**. Heavier load producing the site
that load was said to suppress refutes the explanation on its own terms. The register reverts to the
previous verifier's reading, and the deferral rests on **scope alone**, which was available the whole
time and needs no contested number: the remedy is `D-g3-g`, which is deferred, and the probe showing
`PROBE-EARLY-RETURN` 3 of 3 stands.

## The lanes

Asked to **break** the scanner rather than review it, which has now produced a defect on every round
of this item. Both lanes that delivered found real ones, and **two of them were regressions this
pass had just introduced** — reading the escape from the brace's owner fixed the interpolation false
fire and lost two shapes the whole-opener word search had covered.

| lane | family | outcome |
|---|---|---|
| `gemini-3.7-flash-high` | Google | **Delivered** at 33 KB, after one failed launch: headless mode auto-denied a tool permission and produced nothing. Re-run with `--disable-slash-commands` and an explicit "answer from this message alone", it returned 8 findings; all 8 reproduced, 3 taken |
| `claude-fable-5` at high | Anthropic, substituting for codex | **Delivered** at 8.6 KB, where 33 KB produced nothing last pass. 8 findings, 6 reproduced (2 were the `.init` defect gemini also found), 2 taken |
| `gpt-5.6-sol` | OpenAI | **Down** to 27 August, per the brief. Not attempted |
| `grok-4.6` at xhigh | xAI | **Down**, as the brief predicted. At the 8.6 KB packet it emitted 481 bytes of narration — "I'll load the voice skill and the scanner source first" — over ten minutes and produced no finding before its alarm. Reported once and not retried |

**Taken:** `_Concurrency.Task { }` and `Task.detached(operation: { })`, the two regressions;
`awaitEvent(.init("x")) { }` reading as a declaration; a receiver's dot at the end of a line putting
the opener span below the receiver; and the qualification test reading past whitespace, since
`collapsed` turns that line break into a space. `keep(Task { })` is a sixth that neither lane named
and only the union of the two owner positions catches.

**Not taken, with directions, as `D-g3-ah`:** a bare `awaitReap(…)` with no receiver; explicit
generic arguments on the call; a typealiased `Task`; an accessor or nested declaration inside a wrap;
a closure stored rather than run; an escaping closure inside the wrapper's own argument list — six
misses. `Self.awaitEvent(…)`, `awaitEvent(setup: { () })` and a backticked wrapper — three reds on
correct source. The last six are unreachable with the signatures as they stand.

## Gates

Each to a full log, `tail` reading the log.

| gate | exit | evidence |
|---|---|---|
| `make test` | **0** | `1587 tests in 199 suites passed after 7.126 seconds` |
| `make test` | **0** | `1587 tests in 199 suites passed after 12.513 seconds` |
| `make lint` | **0** | `Found 0 violations, 0 serious in 500 files` |
| `make parity` | **0** | `358 vector cases compared (floor 358)` |
| `make acceptance-r6` | **0** | `examined=6 failures=0` |
| `python3 planning/ledger-reconcile.py` | **0** | `reconciled — no findings across A, B, B-range, C, D, E, F, G, H, I, J, K`, check K examining 172 register rows |
| assigned mutation | **2** | `failed after 13.189 seconds with 1 issue` at `PoolReapingTests.swift:98:29`, *timed out after 10.0s waiting for: `own` to be reaped under the arming it just made* |

The mutation needed the local capture `D-g3-af` records — written as the brief specifies it, it does
not compile. `UpstreamPoolReaping.swift` was restored from a `cp` backup and `git diff app/Sources/`
is empty.

**Two of four `make test` runs went red, and saying only that two passed would be this item's own
shape.** `CallbackLifecycleTests.swift:238` (*the callback listener was cancelled before it bound*)
and `ControlStreamTests.swift:72` (`arrival < lastSent`, two timestamps that round to the same
second). Both are in files this item does not touch, both are `D-g3-c`'s class, and both are now
recorded under `D-g3-s` as its fourth and fifth measured instances. **`make test` is still not
deterministically green on this machine**, and nothing in this item's scope changes that — the
scope was the pool suites.

## Machine

1-minute load average **421**, idle **0.0%** for the whole pass, two sibling runners live.
**The timings above are not representative and are not offered as comparisons**: the assigned
mutation's 13.189 s sits against 10.589 s measured on the runner's machine last pass and 10.836 s on
the verifier's at load 127. What the numbers establish is the exit code and the named line, not the
duration.

## Left undone, and why

- **`D-g3-af` and `D-g3-ag`** are registered and out of scope by the brief. `D-g3-ag` gained a
  measurement while a control file was being split — the two cited limits are SwiftLint's own
  `file_length` and `type_body_length` defaults, which `.swiftlint.yml` does not configure — but the
  older comments still cite them without a source.
- **`D-g3-ah`'s nine shapes** are measured and left. Six are unreachable with today's signatures;
  the typealiased `Task` and the stored closure cannot be reached by a text scan at all, which is
  `D-g3-z`'s argument for a compile-time witness.
- **`D-g3-a` … `D-g3-z` stay deferred**, except `D-g3-q`'s wording, which B1 required.
- **The two flakes above** are `D-g3-c`'s classification work, not this pass's.
