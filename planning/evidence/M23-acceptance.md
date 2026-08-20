# M23 — acceptance evidence

The conversion contract's own audit. Every number below is quoted from the run that produced it;
the commands are here so a later reader re-runs them rather than trusting the table.

| | |
|---|---|
| Item | M23 — the mock-to-SwiftUI conversion contract |
| Branch | `ai/m23` · worktree `.worktrees/M23` |
| Spec | `planning/specs/spec-M23.md` |
| Machine | this one, 2026-08-21 |

M23 ships an instrument. Nothing that renders changed, so `UI_VERIFICATION.md` rule 2 applies at
its widest: no screen was launched, no app came to the front, and the one thing that draws —
`MeasureDump` — runs `.prohibited` and never orders a window front. The screen ledger below records
that rather than a sweep.

## 1 · Gates

| Gate | Command | Result |
|---|---|---|
| Build | `cd app && swift build` | exit 0 |
| Full suite | `cd app && swift test` | **1549 tests in 193 suites passed** |
| Token parity | `cd app && swift test --filter MockToken` | **20 tests in 2 suites passed** |
| Lint | `make lint` | exit 0 |
| Gate selftest | `./scripts/acceptance/mock-fidelity-selftest.sh` | **21 cases, all three exits observed**, exit 0 |
| Conversion gate | `./scripts/acceptance/mock-fidelity-gate.sh servers` | **exit 1 — 124 findings** |

The conversion gate exiting 1 is the correct result and not a failure of this item. Servers has not
been converted to the mock — that is M16's work — so the instrument reports the real distance
between the two. An instrument that returned 0 against an unconverted board would be the thing this
item exists to prevent.

## 2 · The gate's own reading

```
mock-fidelity: surface 'servers' across 4 states
  tokens             ran · 25 matched, 64 pending, of 89 rows · clean
  literals           ran · scanning 116 files · clean
  structure          ran · 73 nodes across 4 states · clean
  geometry           ran · 73 frames · clean
  type-metrics       ran · 24 text nodes · 4 roles · Caption=13pt Body=16pt Title3=19pt Title1=26pt
                          · 2 multi-line node(s) excluded from the per-role check · clean
  copy               ran · 20 paired strings · 16 finding(s)
  breadth            ran · absent 80 · covered-by-pair 17 · divergent 16 · extra 9 · extra-cited 2
                          · present 10 · structure-unpaired 14 · unclassified 1 · 108 finding(s)
  font-weight-face   inconclusive (substituted)
mock-fidelity: EXIT 1 — 124 finding(s)
```

The four dumps carry 39 + 13 + 12 + 9 = **73 nodes**, at the floor the manifest declares. Running
the gate twice reproduced `planning/fidelity/servers.ledger.md` byte-identically
(`git diff --quiet` clean after the second run), so the ledger is a function of the two artifacts
rather than of the run.

## 3 · Acceptance criteria, one at a time

**1. `MockTokenParser` exists and its three assertions pass, including the colour-literal check.**
20 tests, 2 suites, green. The register carries **89 rows** — 40 colour, 18 metric, 14 asset,
12 metric-colour, 5 composite — parsed out of all five `:root` blocks the mock authors, including
the second top-level one at line 822 that holds the WebP asset tokens. 25 matched, 64 pending, 0
unclassified, 0 uncited. The third assertion executes `scripts/lint/no-raw-design-values.sh` rather
than re-spelling it, and the mock's own `literals_outside` reads `stray=0`.

**2. The harness produces a nested structure-and-geometry dump.**
`planning/fidelity/dumps/servers.ideal.json` is a tree, not a list: every node carries `path` (the
parent chain), `children` (ordered along the parent's own axis), `axis`, `alignment`, `frame`
(x/y/w/h in a *named* coordinate space, so a moved window does not diff as a moved element),
`tokens` and `resolved`. The structure layer does not take the declared axis on trust — it checks
each one against where the children actually landed, which is what case 8 of the selftest arms.

**3. Servers has a filled breadth ledger whose every cell names the two artifact values.**
`planning/fidelity/servers.ledger.md`, 173 rows across all four drawn states. Every row carries a
`Mock value` and a `Build value` column; `absent` rows name what the mock said and `build=no paired
node`; `divergent` rows carry both strings. The ledger is generated on every run from the mock and
the dump, so a row cannot be deleted to make a finding disappear — proved rather than asserted, in
§4 below.

**4. The gate returns 0, 1 or 3, and a disabled layer returns 3.**
All three observed, by the selftest, on every run of `make all`.

## 4 · What was observed failing

"A gate never observed failing is a gate nobody has written." Each row is a real mutation with the
exit it produced.

| Mutation | Layer it arms | Result |
|---|---|---|
| clean scratch tree | — | exit **0** |
| the build renders a label the mock does not | copy, breadth | exit **1**, "label differs" |
| a colour literal in a scanned file | literals | exit **1**, "raw design value" |
| a node declares `horizontal`, children stack vertically | structure | exit **1**, "declares axis horizontal" |
| a node laid out to zero width | geometry | exit **1**, "zero-area frame" |
| two nodes naming one type role at different heights | type-metrics | exit **1**, "lost the cascade" |
| a build section no mock affordance accounts for | breadth (reverse) | exit **1**, "in the build and not in the mock" |
| a pairing row deleted | breadth (forward) | exit **1**, "is absent from the build" |
| the dump a required layer reads is gone | preflight | exit **3** |
| `structure` marked `required: false` | manifest guard | exit **3**, "Only ['font-weight-face'] may be" |
| the token suite prints no marker | tokens | exit **3**, "cannot be told from one that did not run" |
| the token census shrinks below its floor | tokens | exit **3**, "below the floor" |
| an unknown surface | gate script | exit **3** |
| seven colour-constructor spellings, against the real lint | literals | all **caught**; clean-tree control still clean |

Three more were run by hand against the real artifacts rather than the scratch tree, because they
mutate files the selftest must not touch. The mock was restored from a byte copy afterwards and
`git diff --quiet design/mcp-router-console.html` confirmed clean each time.

- **A matched pair drifting.** `--accent` changed from `#0088FF` to `#FF00FF` at line 75 of the
  mock: 4 issues, naming both value sets and the classification flip from `matched` to `pending`.
- **A pending row drifting.** `--tl-zoom` changed from `#28C840` to `#FF00FF`: 1 issue —
  `(l.observed → ["mock.light": "#FF00FF", "swift": "absent"]) == (c.observed → ["swift": "absent",
  "mock.light": "#28C840"])`. A `pending` row is not an exemption; it is a fingerprint of two exact
  values still apart.
- **The instrument handed an argument it cannot honour.** `MeasureDump --state loadng` now prints
  `--state 'loadng' is not one of the values ideal, empty, loading, error`, exits **3**, and writes
  no file. It previously fell back to `ideal` and exited 0, writing the ideal frame into a dump
  named for another state.

## 5 · Out-of-family review

`codex exec -m gpt-5.6-sol -c model_reasoning_effort=high -s read-only`, adversarially briefed,
verbatim in `planning/evidence/M23-review-codex.md`. Verdict: REJECT, 8 findings. The lane was
recorded down in `ORCHESTRATOR.md` until 2026-08-20 and is back; the `-o` file came back non-empty,
which is the only honest tell since `codex exec` exits 0 on a usage limit. A second lane
(`grok-4.6` at xhigh) was started in parallel and had not produced a report by the time this was
written — recorded as a lane not landed, not as a lane that passed.

The reviewer worked mostly from `spec-M23.md`. Four findings describe the spec's prose accurately
and the implementation not at all, and each was settled by running the mutation the reviewer
predicted would pass.

| # | Finding | Disposition |
|---|---|---|
| 1 | A `pending` row is an exemption class; drift inside one goes unnoticed | **Refuted by measurement.** The `--tl-zoom` mutation above goes red. The register fingerprints both observed values per appearance context. |
| 2 | `font-weight-face` at `required: false` turns an inconclusive layer green | **Disagreed, with the reason recorded.** Making it required puts the gate at 3 forever and makes 0 unreachable, which is a two-state gate wearing a three-state gate's clothes. The measurable half was split out into `type-metrics`, which arms the exact residue the reviewer names — a role rendering at the wrong size shows as "lost the cascade" (case 10). What genuinely cannot be read is weight and face, and the substitute citation prints on every run. |
| 3 | No output-cardinality or freshness postcondition | **Partly closed.** Cardinality already existed as the manifest's floors and `load_json`'s zero-byte and parse guards. Freshness holds by construction — the gate deletes each dump before re-rendering it. The real gap the finding pointed at was one level up, in the instrument's own argument handling, and that is now the gate's preflight. |
| 4 | The breadth ledger trusts its own mutable denominator; deleting a row returns 0 | **Refuted by measurement.** Selftest case 12 deletes a pairing row and gets exit 1, "is absent from the build". The inventory is re-derived from the mock every run; the TSV declares only which node answers which affordance, never whether the affordance exists. |
| 5 | A first-match `:root` parser misses the second block | **Refuted.** All five `:root` blocks parse; the 14 asset rows in the register come from the second top-level block. Appearance overrides are carried as `darkOverride` / `lightOverride` rather than flattened. |
| 6 | The spec claims the structure layer ran without measuring structure | **Partly accepted.** The layer does corroborate every declared axis against child geometry, which the reviewer did not see. But the probe outputs were quoted in the spec with nothing committed behind them and §8 pointed at an evidence file that did not exist. This file is that file, and §4 above is the arming the finding asked for. |
| 7 | The reused lint is described as more complete than it is | **Accepted and fixed.** Measured: `Color(white:)`, `Color(hue:saturation:brightness:)` and `Color(.displayP3, red:green:blue:)` all passed the lint clean. The rule now covers every `Color` initializer taking raw components or a foreign colour value, and all seven spellings are armed against the real script with a clean-tree control. |
| 8 | The selftest arms selected outcomes, not every layer | **Accepted and fixed.** Five mutations added; structure, geometry, type-metrics and both directions of breadth each now have a case that makes them speak. 21 cases, from 8. |

## 6 · Screens verified

| Screen | How verified | Commit | Result |
|---|---|---|---|
| Servers board | Not launched. No rendering behaviour changed: the diff adds `.measured(…)` call sites, which compile to the identity modifier without `MEASURE`, and `MCP_ROUTER_MEASURE` is unset in every shipping build. Existing evidence stands — `planning/evidence/M1-acceptance.md`. | `a36203c` | skipped, per `UI_VERIFICATION.md` rule 2 |
| Servers board, four states, headless | `MCP_ROUTER_MEASURE=1 MeasureDump --surface servers --state {ideal,empty,loading,error}` under `NSApplication` activation policy `.prohibited`; no window ordered front, no app activated | `a36203c` | 73 nodes measured across four dumps |

## 7 · What this item does not close

- **Weight and face are unread.** A SwiftUI `Font` is opaque. `type-metrics` covers the size
  residue; nothing here covers a wrong weight or a substituted face on a node whose size is right.
  That is the one `required: false` layer and its substitute prints on every run.
- **One surface has a ledger.** Servers, all four drawn states. The other thirty-six board cells,
  twelve sheets and nine menus are M17's, M18's and M20's frames to fill; M23 owns the row shape.
- **`DESIGN.md` versus the mock is still open.** 64 of 89 token rows are `pending` against a
  citation in `M21-token-layer-and-design-md.md`. M21 decides which document is authoritative; until
  it does, the register keeps the gap measured rather than merged.
- **The `grok-4.6` review lane did not land.** One out-of-family review informed this work, not two.
