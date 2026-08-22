# M19 acceptance — a renderer measured headless, and the pass that could not be driven

Branch `ai/m19`, worktree `.worktrees/M19`, cut from `main` at `87e16dc` and merged with `main` at
`9d4da76` for the gap-fix, giving `1e43252`. Every figure below was re-measured on that tree.

**This file covers two runs.** The first was verified **Needs More Work** at `54bb0aa` — the verdict
is `planning/verification/M19-verdict.md` in `.worktrees/M19V`. Nothing it measured about the
product moved: the renderer, the parser, the shield handling and the untrusted-input boundary were
all measured separately and hold. What it found was in the evidence.

| Finding | What it was | Where it is answered |
|---|---|---|
| F1 | `MarkdownBlock.plainText` constructed nowhere, so the only guard on *no block falls back* could not fail | `fc54d75` — the parser builds one, with a presence control on each side |
| F2 | red-green arm A2 reddened by trapping rather than by an assertion | `b4dc441` — nine arms, output classified, each through its own named test |
| F3 | `readme.pairing.tsv` said twenty-four rows where there are twenty | `6a79e71` |
| F4 | `readme.layers.json` declared five `VOUCHED_CONTROLS` pairings where eight were added | `6a79e71` |
| F5 | table body cells measured by nothing, undeclared | `6a79e71`, and *What is not evidenced here* below |
| F6 | D1's citation blamed rendering three documents at once, where the obstacle is a missing seam | `6a79e71` |
| F7 | heading nodes measured a padded box, the defect this item fixed for column headers | `fc54d75` |

**The first thing this file has to record is what it could not do.** `UI_VERIFICATION.md`'s ledger
exists so a relaunched runner skips what was already proven against a *running app*. There was no
driven pass here and there could not be: M19 builds the capability document panel and adds **no
entry point to the shipped app**, because the control API serves no document and a `Read me…`
button would open a panel that says so for every capability in a Release build. So no window was
opened, nothing was clicked, and nothing came to the front. What replaces a driven pass is a real
render — `MeasureDump` hosts the panel in an `NSHostingView` under `NSApplication`'s `.prohibited`
activation policy, lays it out, and reports what the resolved views say about themselves. That is
rendered evidence rather than a build gate, and it is weaker than driving the real app, which is
stated here rather than left for a reader to notice.

`UI_VERIFICATION.md` rule 2 — only test the screen you changed — is satisfied trivially in the
other direction: no existing screen's files changed, so no existing screen was re-tested.

## The ledger

| Screen | How verified | Commit | Result |
|---|---|---|---|
| The panel, rendered | `MeasureDump --surface readme --state ideal`, `.prohibited` activation policy, never ordered front | `b781751` | 42 instrumented nodes, one dump, exit 0 |
| Every block kind the mock draws | `mock-fidelity-gate.sh readme` breadth layer against a census derived from `#sh-readme` on the run | `b781751` | 51 mock affordances · present 26 · absent 23 · divergent 1 · unclassified 1 · extra-cited 4 |
| The type ladder, as laid out | gate `type-metrics` layer, 9 per-role comparisons over 11 text nodes | `fc54d75` | clean — Callout 15pt · Body 16pt · Title3 19pt · Title2 20pt · Title1 26pt |
| Declared stacking axes against where children landed | gate `structure` layer | `b781751` | clean — 7 axes corroborated over 42 nodes |
| Frames | gate `geometry` layer | `b781751` | clean — 42 frames, root matches its hosted size, no zero-area frame |
| Colour tokens against `DESIGN.md` | gate `tokens` layer (runs the parity suite) | `b781751` | clean — 70 matched, 19 pending, of 89 register rows |
| No raw design value in the new directory | gate `literals` layer, executing `no-raw-design-values.sh` | `b781751` | clean — 132 files scanned, 91 under the geometry and boundary rules |
| Copy, mock against build | gate `copy` layer | `b781751` | 27 paired strings, 1 finding — the declared D7 |
| The shield fills | `CapabilityDocumentSheetTests.shieldFillsAreTokens` + `MarkdownSecurityTests.shieldCarriesNoColour` | `bb61d01` | both fills are `ColorToken`; `Shield` reflects exactly `key`, `tone`, `value` |
| The fixture parses with nothing falling back | `CapabilityDocumentFixtureTests`, with its presence control beside it | `fc54d75` | 0 `plainText` blocks across all three tabs, and the same filter returns 1 over a document that does fall back |
| The untrusted-input boundary | `MarkdownSecurityTests`, 13 tests | `bb61d01` | every non-https scheme stripped; four image refusals each distinct; a symlink out of the package refused |

Gate verdict: **exit 1, 30 findings**, which is the same exit `settings` carries and for the same
reason — every finding is a declared divergence. 29 ledger rows, 29 carrying a `Dn ·` number,
splitting D1 20 · D2 3 · D3 1 · D4 1 · D5 1 · D6 1 · D7 1 · D8 1. The thirtieth is the copy layer
reading D7 in its own words, which is one difference seen by two layers rather than a thirtieth
row; `readme.layers.json` says which number describes which population.

## The four the gate caught that a screenshot would not have

Recorded because they are the argument for the instrument. The table declared a vertical axis while
its instrumented children separate horizontally; a column-header node wrapped the padded cell
rather than the text, so Callout measured 23pt against Body's 16pt and inverted the ladder; the
fixture's opening paragraph carried a sentence the mock's does not; and the blockquote used
straight quotes where the mock uses typographic ones. All four are invisible at a glance and all
four are now clean.

## Red-green — nine arms, each through the test it names

`python3 scripts/m19-red-green.py`, at `b4dc441`. Mutations are applied to the implementation and
never to a test, one at a time, and every file is restored. Each arm runs **only** the one test it
names, so *the suite went red* cannot stand in for *this guard bit*.

| Arm | The test it kills | How it went red |
|---|---|---|
| A1 | the read me carries every block kind the mock draws | assertion |
| A2 | no block in any tab falls back to raw text | assertion |
| A3 | every other scheme is stripped, and the words stay | assertion |
| A4 | every route out of the package is refused, each with its own reason | assertion |
| A5 | a parsed shield carries no colour from the badge | assertion |
| A6 | a shield's fill is one of the app's own two text-safe fills, never the badge's | assertion |
| A7 | the panel fabricates no action, and the seam a caller uses is the only way in | assertion |
| A8 | a ragged table is padded and truncated to its header's width | assertion |
| A9 | a fourth heading level falls back to plain text rather than being drawn or dropped | assertion |

The *how* column is the column that was missing. Until the gap-fix A2 mutated a range to `(1 ... 0)`
and reddened by **trapping** — `Fatal error: Range requires lowerBound <= upperBound`, which exits
non-zero with no assertion having fired — and the pass, reading only the exit code, reported it
exactly like the seven arms that bit. It now classifies the output, requires the named test to be
green before the mutation and to record an issue by name after it, and refuses an arm whose run
trapped or whose filter selected no test.

**Two did not bite on the first run of the original pass, and both were the arm's fault rather than
the guard's** — which is the reason to run it rather than assert it. `| - | - | - |` is still a valid
GFM delimiter row, so the table A1 meant to destroy parsed fine; and A8 was aimed at a line
`swiftformat` had since wrapped, so it could not arm at all and said so rather than passing.

The geometry lint was armed separately and by hand: `.frame(height: DocumentMetrics.shieldHeight)`
replaced with `.frame(height: 20)` in `ShieldView.swift` reddened `no-raw-design-values.sh` with
`geometry literal; read the value from MetricToken`, and the file was restored. That is what proves
`MCPRouterUI/Document` genuinely joined the geometry rules rather than merely being named in the
list.

The gate's own selftest was armed by the same accident: adding `Document/` to `GEOMETRY_DIRS`
turned `mock-fidelity-selftest.sh`'s clean-tree control case red, because its scratch tree did not
carry the directory. That coupling is invisible in both files and the control case is the only
thing that surfaces it.

## What is not evidenced here, stated rather than implied

- **No driven pass against the running app**, for the reason at the top. When M18 wires the panel
  to a sheet, that pass is owed and this file is where it goes.
- **One measured state.** The panel builds three — a published tab, an unpublished tab, and a
  source that cannot answer — and the gate measures one, because the mock draws one frame for this
  sheet and `mock-affordances.py` exits 3 rather than inventing another. The other two are covered
  by `CapabilityDocumentSheetTests` and are **not** rendered evidence.
- **A table's body cells are measured by nothing, on either side.** No census rule matches `tr` or
  `td`, so the mock's four body rows never enter the inventory, and `MarkdownTableView` instruments
  header cells only — a body cell takes no node at all, for the reason written at the call site. So
  **no finding is possible about the content of any table in any document this panel will show**,
  on a surface whose ledger reports clean on four of eight layers. The rows do render, established
  from geometry rather than from the census: `block-5-table` measures 115pt, a header cell is 15pt
  of text with 4pt of padding above and below, and 115 / 23 is 5 rows exactly — the header plus
  four. `readme.layers.json` carries the same declaration.
- **One measured tab of three.** Separate from the states above, and the sharper of the two gaps.
  The mock gives each tab body an id and this item's own `stateFrames` censuses them at 22, 14 and
  6; what stops the gate reaching them is that `CapabilityDocumentSheet` takes no `tab` parameter,
  so the harness cannot ask it to draw the changelog. Declined on cost and recorded as that in
  `readme.layers.json`'s D1, which used to describe the closure as structurally impossible.
- **Neither increased-contrast context has been photographed**, which is `DESIGN.md` §2's standing
  gap rather than this item's. The dump is taken in dark.
- **`make lint` could not run as a target in this worktree**: its `tools` prerequisite requires
  `node_modules` and `dist/index.js`, which a fresh worktree does not have. Every component it
  runs was run directly instead — `swiftformat --lint` 0 of 577 requiring formatting, `swiftlint
  --strict` 0 violations in 570 files, the four shell lints, and both Python gates — and that is
  recorded as a difference from the target rather than as the target passing.
