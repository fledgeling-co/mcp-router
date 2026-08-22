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
| AC6 | No breaker symbol remains in `app/Sources` or `app/Tests` | Case-sensitive `grep -rn 'Breaker' app/Sources app/Tests` → **10 hits, none of them a declaration or a call.** Eight are `///` doc comments recording the retirement (`SignalPathGeometry.swift:11` and `:121`, `JackPresentation.swift:20` and `:67`, `ServersBoardMetrics.swift:29`, `ServersBoardSurfaceTests.swift:166`, `SignalPathParityTests.swift:7` and `:64`); two are string literals inside the assertions that forbid the symbol — `!source.contains("BreakerToggle(")` at `ServersBoardSurfaceTests.swift:179` and `!source.contains("Breaker(state:")` at `:183`. **Zero hits under `RouterCore` with this reader.** `RouterCore`'s unrelated *deadlock breaker* is lowercase, so it appears only under `grep -i` (`UpstreamPool.swift:214`, `PoolTestSupport.swift:182` and `:207`, `PoolAwaitBoundTests.swift:14`; `-i` returns 29 in total). Presence control, same reader, same paths: `SignalPathGeometry` **22**, `JackState` **32**, `StatePlug` **9** — the sweep is not blind |
| AC7 | `DESIGN.md` documents the Signal Path's construction and no longer documents the breaker's | `### Breaker geometry`'s nineteen rows are gone and `### Signal Path geometry` carries **ten** in their place, both in §2 (heading at `:385`, rows counted to the table's first blank line). §7's two breaker motion rows became one plug row; §8's `Space` row was re-pointed from the breaker to **Keep warm** — that row survives, its subject changed. So **no construction is documented anywhere**. But **the element is still named four times, and this row asserted it was named nowhere in three of the sections.** `grep -n -i 'breaker' DESIGN.md` → `:42` (§1, retirement prose — *"retired the breaker column it replaces in the same change"*), `:296` (§2, the `Servers row` cell recording that its derivation retired), `:523` (§7, *"the two breaker rows this table used to"* carry), `:587` (§10, the 36pt row height still owed). Sections resolved by line range from `grep -n '^## ' DESIGN.md`: §1 19–52, §2 53–422, §7 514–542, §8 543–561. **§8 is the only one of the three this row named that carries no mention** — 0 over `sed -n '543,561p' DESIGN.md \| grep -i breaker`, with the presence control that the same reader over the same range returns 1 for `keyboard`. So the criterion is met on its intent, and *"§1, §7 and §8 no longer name the element"* — which this row asserted until gap-fix 1 — is **false for §1 and §7** |
| AC8 | The suite discovers more than the base's 1725 and everything is green | **1743 tests in 216 suites**, `make lint` **exit 0** with 0 violations in 554 files, `no-raw-design-values.sh` clean over 127 files. The 1725 is a per-file `@Test`-line census over `87e16dc`, controlled against the tip's executed 1743 — see the gate-output note below and `planning/progress/M16.md`. `make lint` here is **the target**, in a worktree that has the `node_modules` and `dist/index.js` its `tools` prerequisite needs; in a fresh worktree the target dies at `tools` and only its eight components can be run, which is not the same measurement |
| AC9 | The gate records the band and the jacks as measured rather than absent | **Not met as written, and the criterion was mis-specified.** See below |

### AC9, stated honestly

The plan asked for the breadth finding count to fall from 116. It did not: it is **116 before and
116 after**, and what changed is the composition.

The gate classifies every breadth row into one of **eight** categories, and five of the eight
append a finding. Both columns are read from the tracked ledger — the `now` column from
`planning/fidelity/servers.ledger.md` at this tip, the `base` column from the same path at `87e16dc`
(blob `86e5823`, `git show 87e16dc:planning/fidelity/servers.ledger.md`) — and both were re-counted
row by row rather than copied from the summary line, with

    awk -F'|' '/^\| (ideal|empty|error|loading) \|/ {gsub(/^ +| +$/,"",$5); c[$5]++; n++} \
               END {for (k in c) print k, c[k]; print "ROWS", n}'

which reproduces all eight counts and both row totals.

| | finding? | base | now |
|---|---|---|---|
| absent | yes | 80 | **75** |
| divergent | yes | 16 | **21** |
| extra | yes | 10 | 10 |
| extra-cited | yes | 2 | 2 |
| unclassified | yes | 8 | 8 |
| covered-by-pair | no | 16 | **24** |
| structure-unpaired | no | 14 | 14 |
| present | no | 3 | 3 |
| **findings** | | **116** | **116** |
| **rows** | | **149** | **157** |

`extra-cited` was missing from this table until the gap-fix, and its absence is why neither column
reached its own 116: 80 + 16 + 10 + 8 = 114 and 75 + 21 + 10 + 8 = 114. It is a finding category
in both of its branches — on this tree `layer.findings.append` fires at `mock_fidelity.py:969` and
`:981`, under the branches opening at `:967` (anchor `"extra-cited" if citation else "extra"`) and
`:978` (anchor `if path in ctx.extra_allowed.get(state, {}):`) — and there are exactly two rows, both
on `ideal`: `servers.ideal/board-column/controls/filter-bar` and
`servers.ideal/board-column/controls/search-field`, each cited to
`design/mcp-router-console.html`. The omission was uniform across both columns, so the
composition story and the *"116 before and after"* claim were unaffected; the table simply could not
be reconciled by the reader it was written for.

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
| `make lint` | **exit 0** · `0 violations, 0 serious in 554 files` · `0/561 files require formatting` · `no-raw-design-values: clean`, 127 files scanned, 86 under the geometry and boundary rules. **The target itself, not just its eight components** — re-confirmed exit 0 at `2123e0e`. It needs `node_modules` and `dist/index.js` for its `tools` prerequisite (`Makefile:82-87`, anchors `[ -d node_modules ]` and `[ -f dist/index.js ]`), which this worktree has and a fresh one does not; where they are absent the target dies at `tools` and only its components can be run |
| `swift test` | **1743 tests in 216 suites passed** — against **1725 in 215** at the base. The 1725 is a per-file census of `@Test` lines over `87e16dc`'s `app/Tests`, not a `swift test list` line count: see `planning/progress/M16.md`'s *"the derivation is now in the units of the thing being counted"* for the reader and its control. This row named `swift test list` until the gap-fix, and that instrument emits build-progress lines as well as test names |
| `scripts/acceptance/mock-fidelity-gate.sh servers` | **exit 1**, 137 findings — five of the eight layers clean, `copy` and `breadth` carrying the surface's remaining divergence, `font-weight-face` inconclusive-substituted as always |
| `scripts/acceptance/mock-fidelity-selftest.sh` | **exit 0** · 68 cases · all three exits observed |
| `python3 planning/ledger-reconcile.py` | **exit 0** · reconciled, no findings across A–L |

`make all` was not run: the work order rules it out, and the orchestrator runs the whole-repo gate.
