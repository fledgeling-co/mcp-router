# M16 — acceptance evidence

`The Signal Path replaces the Breaker Column` · branch `ai/m16` · worktree `.worktrees/M16`
Spec `planning/specs/spec-M16.md` · Plan `planning/plans/plan-M16.md` · Brief
`planning/features-to-triage/M16-signal-path.md`

Append to this file, never rewrite it. Read it **before** testing anything: if a row exists and
`git diff <that SHA>..HEAD` does not touch the files behind it, that row *is* the evidence, and the
right thing to do is skip the check and say so.

---

## What was verified, and what was deliberately not

**One screen changed in this item: the Servers pane.** Its band, its table row's leading mark, its
column-header gutter and its inspector's header. Three other surfaces changed by one line each and
were **not** re-driven, because the change is a value swap behind an existing, already-verified
drawing: the sidebar's badge bump now reads the plug's transition rather than the breaker's rise
(`ShellAppearanceTests` asserts the value and the Reduce Motion branch), the loading skeleton stands
a circle where it stood a rounded rectangle at the same row height, and the design gallery's
Breaker section became a Signal Path section. `mac-shell.sh` covers the shell and this branch does
not touch the files behind its rows.

**The instrument is M23's gate, not a screenshot.** The house rule is explicit — *"A surface built
from the console mock is converted under M23's five measurement layers, not by eye. A screenshot
comparison is not evidence."* — so the Servers board was rendered headless through
`NSHostingView` at 1280×820 in all four of its declared states and measured. No window was opened
and no focus was taken, which is `UI_VERIFICATION.md` rule 1 satisfied by construction rather than
by care.

**What the gate cannot reach, and what covers it instead.** The harness renders with nothing
selected, so the brief's *"one selection, three representations"* is a claim about a mechanism
rather than about a frame. Three assertions in `ServersBoardSurfaceTests` cover it at the model,
which is where the mechanism lives, and one of them is armed below.

---

## The acceptance criteria, and the value read for each

Measured at `753670e` unless stated. Every frame below is quoted from
`planning/fidelity/dumps/servers.ideal.json`, written by the gate run at that commit.

| # | Criterion | Evidence |
|---|---|---|
| AC1 | A structure dump of `servers.ideal` contains a `signal-path` node with one jack per declared server | `servers.ideal/board-column/signal-path` · role `signature` · four children under `signal-path-rail/jacks`, one per fixture server |
| AC2 | The jacks lay out in two or more columns at the target width | **four columns** — x = 140, 280, 420, 560 at y = 109, all on one row. Track pitch 140 = 132 + 8, which is the documented minimum plus the grid unit. Field width 1112, which is what `jackFieldWidth(inBoardWidth: 1248)` predicts |
| AC3 | Every jack carries its state word in its accessibility label | node text `fixture-stdio dormant`, `fixture-http dormant`, `fixture-tools 5:00 left`, `fixture-oauth needs sign-in`. `JackView` sets `accessibilityValue(row.condition.word)` — the **full** form, whichever the width drew |
| AC4 | Selecting a jack selects the row and the inspector, and the reverse holds | `ServersBoardSurfaceTests` — `oneSelectionReachesAllThree`, `theBandIsUnfilteredAndItsSelectionStillResolves`, `theBandAndTheTableAgree` |
| AC5 | The hub reads the router's own port and the warm count, withholding the count when the reading is not current | hub node text `Router :8971 0 at rest` — 8971 is the recorded fixture's port, not a constant. `atRestIsWithheldOnAStaleReading` covers the withholding |
| AC6 | No breaker symbol remains in `app/Sources` or `app/Tests` | `grep -rn 'Breaker' app/Sources app/Tests` returns only `RouterCore`'s unrelated *deadlock breaker* and comments recording the retirement |
| AC7 | `DESIGN.md` documents the Signal Path's construction and no longer documents the breaker's | `### Signal Path geometry` carries 10 rows; `### Breaker geometry` is gone; §1, §7 and §8 no longer name the element |
| AC8 | The suite discovers more than the base's 1725 and everything is green | **1743 tests in 216 suites**, `make lint` exit 0 with 0 violations in 554 files, `no-raw-design-values.sh` clean over 127 files |
| AC9 | The gate records the band and the jacks as measured rather than absent | **Not met as written, and the criterion was mis-specified.** See below |

### AC9, stated honestly

The plan asked for the breadth finding count to fall from 116. It did not: it is **116 before and
116 after**, and its composition changed —

| | base | now |
|---|---|---|
| absent | 80 | **75** |
| divergent | 16 | **21** |
| covered-by-pair | 16 | **24** |
| extra | 10 | 10 |
| unclassified | 8 | 8 |
| structure-unpaired | 14 | 14 |
| present | 3 | 3 |

Five affordances the build did not answer at all now carry a measured comparison. They read
`divergent` rather than `present` because `present` requires the two labels to be equal, and the
mock's are its own eleven server names against the recorded fixture's four — the same reason every
table row already paired on this surface reads `divergent`. **`divergent` is a finding too**, so an
affordance moving from *not built* to *built and measured* trades one finding for another, and no
fixture this build ships could make that trade a reduction. The criterion should have named the
composition rather than the count.

The other layers moved as the conversion predicts: `structure` 73 → 86 nodes, `geometry` 73 → 86
frames, `type-metrics` 22 → 24 comparisons over 26 text nodes across 5 roles (Subheadline joins the
four already measured), `literals` 118 → 127 files, `copy` 16 → 21 findings over 24 paired strings.

---

## The arms — every new gate seen to fail

`SWIFT_PRACTICES.md` §7: a test that has never failed is not known to work. Each arm was applied to
the working tree, run, restored with `git checkout --`, and confirmed with `git diff --quiet`. A
sweep for every mutant string over `app/Sources`, `app/Tests` and `DESIGN.md` returned nothing.

| # | Mutation | Bit? | The failure, verbatim |
|---|---|---|---|
| 1 | `jackMinimum` 132 → 133 | yes | `SignalPathGeometryParityTests` — `Expectation failed: (shipped → 133.0) == (documented → 132.0)` |
| 2 | `\| Hub width \| 76pt \|` deleted from `DESIGN.md` | yes | two issues — `(documented.symmetricDifference(inCode) → ["Hub width"]).isEmpty → false` and `(rows.count → 9) >= 10` |
| 3 | `guard !server.warm` → `guard server.warm` in `JackCondition` | yes | `no warm server ever shows a countdown, in either form of the word` — `!((c.word → "5:00 left").contains(":") → true)`, plus four more across three tests |
| 4 | `.live` gated on `placard == nil` as well as running | yes | `the plug is lit exactly when a child process is up` — `(jack.isLit → false) == ((state == .running) → true)` |
| 5 | a sixth `JackState` case with no view arm | yes | **compile error**, `switch must be exhaustive` at two sites — which is the brief's claim that a new state cannot be added to the model without the view failing to compile |
| 6 | `bandRows` made to filter like `rows` | yes | `the band is unfiltered, and a jack outside the filter still resolves` — `(board.bandRows(...) → ["alpha"]) == ["alpha", "beta"]` |

Arm 3 is the one worth keeping. It is the defect an out-of-family lane found in the plan before any
code was written: a warm running server drawing `3:41 left` while the hub two inches above reads
`1 at rest`. The arm proves the assertion that closes it is not vacuous.

---

## Gate output

Run from the worktree root.

| Gate | Result |
|---|---|
| `make lint` | **exit 0** · `0 violations, 0 serious in 554 files` · `no-raw-design-values: clean`, 127 files scanned, 86 under the geometry and boundary rules |
| `swift test` | **1743 tests in 216 suites passed** — against `1725 in 215` at the base, measured on this tree with `swift test list` |
| `scripts/acceptance/mock-fidelity-gate.sh servers` | **exit 1**, 137 findings — five of the eight layers clean, `copy` and `breadth` carrying the surface's remaining divergence, `font-weight-face` inconclusive-substituted as always |
| `scripts/acceptance/mock-fidelity-selftest.sh` | **exit 0** · 68 cases · all three exits observed |
| `python3 planning/ledger-reconcile.py` | **exit 0** · reconciled, no findings across A–L |

`make all` was not run: the work order rules it out, and the orchestrator runs the whole-repo gate.
