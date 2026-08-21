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
| Lint | `make lint` | exit 0 — **red on arrival; see §1.1** |
| Gate selftest | `./scripts/acceptance/mock-fidelity-selftest.sh` | **22 cases, all three exits observed**, exit 0 |
| Conversion gate | `./scripts/acceptance/mock-fidelity-gate.sh servers` | **exit 1 — 124 findings** |

Run as four separate commands with `$?` captured immediately after each, for the reason §1.1
records. Final run: `LINT=0 TEST=0 SELFTEST=0 GATE=1`.

### 1.1 · `make lint` was red on arrival, and the first check here said it passed

Worth recording in full, because it is the failure this whole item is about, committed by the
instrument's own author.

`make lint` was run first thing on the inherited tree as
`make lint 2>&1 | tail -30; echo "exit=${PIPESTATUS[0]}"`. It printed `no-raw-design-values: clean`,
`no-wire-codable: clean`, and `exit=`. It was read as a pass. It was not one: `PIPESTATUS[0]` after
the pipeline had already been consumed reports nothing, the `echo` succeeded, and the harness
recorded the whole command as exit 0. Fifteen `error:` lines were sitting in the same output, above
the `tail -30` window, and `make: *** [lint] Error 1` was on the line before the one that was read.

The gate that caught it was running the same command again with its exit code taken directly. The
lesson is the one the `tokens` layer already encodes and that this check did not: **a command whose
success and whose silence look identical has not been checked.** Twenty-nine violations were open —
type and file lengths past their caps, a force unwrap, a four-member tuple, a cyclomatic complexity
of 13, six formatting errors. They are closed in the commit that follows, by splitting five
oversized files along real seams rather than by raising a cap.

The conversion gate exiting 1 is the correct result and not a failure of this item. Servers has not
been converted to the mock — that is M16's work — so the instrument reports the real distance
between the two. An instrument that returned 0 against an unconverted board would be the thing this
item exists to prevent.

## 2 · The gate's own reading

```
mock-fidelity: surface 'servers' across 4 states
  tokens             ran · 25 matched, 64 pending, of 89 rows · clean
  literals           ran · scanning 117 files · clean
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
| seven colour-constructor spellings and a bare hex, against the real lint | literals | all **caught**; clean-tree control still clean |

All fourteen run in about a second and join `make all`. The lint cases drive the *real*
`scripts/lint/no-raw-design-values.sh` through a scratch root rather than the stub, because that
layer's whole value is that it executes the script; the probe never touches `app/Sources`, so a run
killed mid-loop cannot leave a file behind that breaks the build.

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
which is the only honest tell since `codex exec` exits 0 on a usage limit. Two further lanes were started and neither landed. `grok-4.6` at xhigh streamed four lines
of preamble over fifteen minutes and was killed by its own `alarm` at 900s (exit 144).
`gemini-3.7-flash-high` refused at its permission gate — *"user denied permission to run command:
git -C … log -n 5 --oneline"* — and wrote a zero-byte output file. Both are recorded as lanes that
did not land, not as lanes that passed; one out-of-family review informed this work, not three.

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
- **Two of the three review lanes did not land.** `grok-4.6` timed out at 900s and
  `gemini-3.7-flash-high` was refused by its own permission gate. One out-of-family review informed
  this work, not three.
- **`make lint` had twenty-nine open violations when this item started**, and nothing in the
  pipeline had reported them. The gates in §1 are now each run with their exit code read directly.

---

# M23 gap-fix — the three blocking findings, and the mutation that arms each

Second pass on the same branch, against `planning/features-to-triage/M23-gapfix.md`. `main` was
merged in first (`47f34ff`) for R6 and R10; the `Makefile` conflict was resolved by keeping both
sides' targets, and `LEDGER.md` auto-merged onto `main`'s newer M23 row.

Every number below is quoted from the run that produced it. The mutations were applied to a `cp`
backup and restored from it — never with `git checkout`, which destroyed uncommitted work in this
tree once before.

## 8 · Gates, this pass

| Gate | Command | Result |
|---|---|---|
| Conversion gate | `./scripts/acceptance/mock-fidelity-gate.sh servers` | **exit 1 — 132 findings** |
| Gate, tokens unmeasurable | `MCP_ROUTER_WRITE_TOKEN_REGISTER=1 ./scripts/acceptance/mock-fidelity-gate.sh servers` | **exit 3** — tokens INCONCLUSIVE, ledger written |
| Gate, planted `TimeoutExpired` | `timeout=1` on the tokens layer's `swift test` | **exit 3** by the same path |
| Gate selftest | `./scripts/acceptance/mock-fidelity-selftest.sh` | **26 cases** (from 22), all three exits observed, exit 0 |
| Out-of-family review | `grok-4.6` at xhigh · `gpt-5.6-sol` at high | both landed; two holes closed because of them — `M23-gapfix-review.md` |
| Lint | `make lint` | exit 0 |
| Full suite, run 1 | `make test` | exit 0 — **1580 tests in 198 suites passed** |
| Full suite, run 2 | `make test` | exit 0 — **1580 tests in 198 suites passed** |

`make test` was run twice because `PoolReapingTests.swift:61` is non-deterministically red under
whole-suite load (G3 in `ORCHESTRATOR.md` — a 150ms sleep against a 25ms idle reap, a wall-clock
assumption rather than a product defect). Both runs were green here, so the flake did not fire.

## 9 · G1 — `present` is earned, on two axes

**Was:** status came from `mock_text == app_text`. In **6 of the 10** `present` rows of
`planning/fidelity/servers.ledger.md` both sides were the empty string, so agreement between two
absences read as a match. And `affordance["kind"]` was written into the ledger and compared to
nothing, so mock kind `card` paired to build role `skeleton` read `present` as well.

**Now:** `present` requires two strings that both exist and agree. Everything the instrument could
not compare is `unclassified`, which is a finding naming what it could not read. And the pair is
audited on the control before the label: the build node's `role` and `kind` are checked against the
mock's kind through `VOUCHED_CONTROLS`, a declared table in the gate rather than in the manifest
the gate reads — the same placement, and for the same reason, as `ALLOWED_OPTIONAL`.

Ledger counts moved `present 10 → 3`, `unclassified 1 → 6`, `divergent 16 → 18`.

**Two findings this surfaced on the real surface, neither of them the instrument's:**

- `loading`: `v-loading/card/unlabelled` is a mock `card` answered by a node reporting role
  `skeleton`. Registered `D-m23-g`'s sibling case; M17 owns the loading state.
- `error`: `v-error/button/start-the-router` is answered by `state-action-disabled` while the mock
  draws it `btn primary lg` with no disabled attribute — a control the build changed, read as
  `present` until now. Registered `D-m23-g`.

**Mutation A — restore `mock_text == app_text`:**

```
FAIL  a pair with no string on either side returns 1 — expected exit 1, got 0
mock-fidelity-selftest: FAILED — an exit the gate is supposed to reach was not reached.
```

Exit **0**, not 1: with the old comparison the whole scratch tree reads clean. Restored from
`/tmp/m23-backups/mock_fidelity.py.fixed`; 26/26 green again.

**Mutation B — `vouched = True`, i.e. the kind is never compared:**

```
FAIL  a mock card answered by a build skeleton returns 1 — expected exit 1, got 0
```

The fixture's labels agree exactly, so nothing but the control check can speak there. Restored.

## 10 · G2 — the exemption is a quota, not a blanket

**Was:** any descendant of a paired node was `covered-by-pair`. The mock's `v-loading` draws three
skeleton rows and the build draws four; the fourth produced no finding at all.

**Now:** where at least one build node of the same role under the same paired ancestor was paired
to an affordance, the mock has declared how many there are, and the surplus is reported:

```
loading: servers.loading/board-column/skeleton/skeleton-row-3 is in the build and not in the mock
— role 'skeleton-row' answers mock kind(s) skeleton-row, of which the mock's census for this
state names 3; 3 of the 4 node(s) of that role under servers.loading/board-column/skeleton
answer one, and this one answers none
```

Planting a fifth child in `servers.loading.json` reported **two**, naming `skeleton-row-3` and
`skeleton-row-4`. Restored from the `cp` backup; back to one, and `git diff
planning/fidelity/dumps/` is empty.

The quota is asked of the **mock's census**, not of how many siblings happened to get paired. The
first draft used pairing success, and both review lanes showed that left the original hole
reachable — see `planning/evidence/M23-gapfix-review.md`.

Where the mock's census never reaches that granularity — a build `row-name` inside a paired
`table-row`, say — the exemption is unchanged, and `covered-by-pair` went `17 → 16` rather than
collapsing.

**Mutation C — restore the blanket exemption (`if declared == 0` → `if True`):**

```
FAIL  a build child past the mock's count returns 1 — expected exit 1, got 0
```

## 11 · G3 — a layer that measured nothing exits 3

**Was:** with `MCP_ROUTER_WRITE_TOKEN_REGISTER=1` inherited, the Swift suite prints
`MOCK-FIDELITY-TOKENS: register rewritten at <path>` and returns before the census.
`dict(part.split("=", 1) for part in …)` raised an uncaught `ValueError`, python exited **1**, and
`write_report` never ran — a stale committed ledger on disk beside an exit code meaning
"differences were found". `subprocess.TimeoutExpired` escaped identically.

**Now:** `run()` converts both `TimeoutExpired` and `OSError` to `Inconclusive`, and the marker
parse and the zero-literals count are guarded, quoting the tool's own words rather than
paraphrasing them:

```
  tokens             INCONCLUSIVE
      tokens: the MOCK-FIDELITY-TOKENS marker does not carry the name=value census fields, so the
      register was never read (ValueError('dictionary update sequence element #0 has length 1; 2
      is required')). The suite printed, verbatim:
      MOCK-FIDELITY-TOKENS: register rewritten at …/planning/fidelity/token-register.json
```

`GATE_B_EXIT=3`, and the ledger **was** written — `31948` bytes, mtime advanced, with
`| `tokens` | **INCONCLUSIVE** | …` as its first layer row. The register the run rewrote was
restored from backup and is byte-identical to the committed one.

**Planted `TimeoutExpired`** — `timeout=1` on the tokens layer's `swift test` — gave
`GATE_C_EXIT=3` by the same path.

**Mutation D — remove the `Inconclusive` wrapper from the marker parse:**

```
FAIL  an unparseable token marker returns 3, not 1 — expected exit 3, got 1
```

The uncaught `ValueError` returns, and with it exit 1.

## 12 · What this pass found and did not fix

Six rows in `ORCHESTRATOR.md`'s deferred register. `D-m23-f` — the gate's tokens layer runs
`swift test` in the same SwiftPM `.build` the MEASURE product links against, so a run leaves
`MCPRouterUI` compiled without `MEASURE` and the next run's `swift build --product MeasureDump`
can fail to link `SurfaceRecorder`. It happened twice here, both times after a `swift test` killed
mid-compile, and it is why two attempts at the final gate run exited 3 before `rm -rf app/.build`
cleared it. The gate reports it as INCONCLUSIVE, which is the right exit for the wrong reason: the
instrument broke its own precondition.

`D-m23-g` — the error state's primary action is `state-action-disabled` where the mock draws
`btn primary lg`; read `present` until now, a finding since, and M17's to fix. `D-m23-h`,
`D-m23-i`, `D-m23-j` and `D-m23-k` come out of the review and are described there.

`D-m23-a` through `D-m23-e` stay deferred, `D-m23-c` (dark-only dumps) and `D-m23-b` (the unread
resolved-colour layer) expressly.

---

# Second gap-fix appendix — 2026-08-21

`planning/features-to-triage/M23-gapfix-2.md`. The first pass's three fixes all reproduce and all
three arms fire; what came back is not *"the fixes did not land"* but *"the properties they assert
do not yet hold, by routes of the same class"*. Each closed the route its finding named. So the
question this appendix has to answer for every fix is not "does the example work now" but "what
else of this shape is still reachable" — and each fix below is armed by the route the finding
named **and** by one nobody named.

## 13 · The five blockers, and the eleven the review added

`B2` first, because it closes a class rather than a list.

### B2 — the exception boundary is the class, not the doors

`measuring()` is a context manager that converts any `Exception` to `Inconclusive` with the
traceback quoted into the reason, and `Context(...)`, `ctx.load()`, every layer call and the report
write are inside one. `KeyboardInterrupt` and `SystemExit` derive from `BaseException` and are
deliberately outside it: an operator pressing ^C is not an unmeasurable surface.

Listing doors does not close this, which is why the boundary is the class — `KeyError` on a
hand-authored manifest, `TypeError` on a quoted floor, `IndexError` on a malformed argument and
`UnicodeDecodeError` on a pairing file are one event, which is that the verdict does not exist.

| Route | Named by | Exit before | Exit now |
|---|---|---|---|
| manifest missing `floors` — `KeyError` in `Context.__init__` | the finding | 1 | 3 |
| dump node missing `role` — `KeyError` inside `layer_breadth` | the finding | 1 | 3 |
| type ladder role missing `size` — `KeyError` in `layer_type_metrics` | **this runner** | 1 | 3 |
| `children` not a list — `TypeError` from a frame inside a layer | **this runner** | 1 | 3 |
| a manifest naming a layer the gate cannot run | **the review** | 3, stale ledger | 3, ledger replaced |
| a ledger that cannot be written at all | **the review** | 3, silent | 3, reported |

The second half of the failure is the ledger: a reader who opens `servers.ledger.md` after a run
that raised finds the last good table, with its `clean` cells, and nothing saying the run that just
happened measured nothing. `write_unmeasured_report` replaces it. It does not say *when* the run
stopped, because it is now also the failure path for `write_report` after eight layers have run,
and a file claiming "before any layer ran" would be the gate telling a reader something it knows to
be untrue.

**Arm.** Narrowing the `except` to `()` returns all four malformed artifacts to exit 1 and the
stale ledger to disk.

### B1 — a count with no floor under it, and then the floor with nothing under it

`layer_literals` reads the lint's scan count precisely because a lint that scanned nothing and a
lint that found nothing print the same exit code — and compared it to nothing. It now compares it
to `floors["lintFiles"]`, 118, the census measured on the run that wrote it.

Two routes past that, both from the review, both of the same shape as the defect:

- **A floor of `0` is not a floor.** `observations < 0` is false for a layer that measured nothing,
  so `"lintFiles": 0` restores the defect *through its own fix*. The comparison cannot catch this,
  because the comparison is what is being defeated. Floors are validated as positive integers at
  `Context.__init__`, once, rather than at each of the four sites. `bool` is excluded explicitly:
  `isinstance(True, int)` is true in Python and `observations < True` is a floor of one wearing the
  wrong type.
- **B1's property is layer-wide.** Writing one floor per layer closes a list. A required layer that
  ran, raised nothing and measured nothing has produced its pass and its cannot-discriminate in the
  same shape, which is `G4-assertions-that-do-not-read-their-own-quantity.md` exactly, so that is
  now inconclusive for every layer at once — including the ones a future surface adds.

| Route | Named by | Exit before | Exit now |
|---|---|---|---|
| `scanning 0 files` | the finding | **0** | 3 |
| `scanning 2 files`, floor 3 — non-zero and below | **this runner** | 0 | 3 |
| `"lintFiles": 0` | **the review** | 0 | 3 |
| `copy` running with an empty population | **the review** | 0 | 3 |

The last uses `copy` rather than `type-metrics` deliberately: type-metrics carries a guard of its
own, so it would not have isolated the general floor.

**Arm.** `if False:` on the floor returns `scanning 0 files` to exit 0. `if False:` on the general
floor returns the empty-population case to exit 1, not 3.

### B3 — `present` requires something readable, not something truthy

`" ".join(x.split())` drops `\xa0` and keeps U+200B, U+FEFF, U+00AD, U+2060 and the directional
marks, so `if mock_text and app_text` called two zero-width spaces equal and wrote `present`.
`readable()` removes whitespace, eleven invisible categories and a short list of blank codepoints,
and is used only for *is there anything here to compare* — never for the comparison, since two
strings differing by an invisible codepoint are still different.

The category test is a class and picks up every future member. `BLANK_CODEPOINTS` — the four
Hangul fillers and U+2800 BRAILLE PATTERN BLANK — is a list and picks up nothing else, because
Unicode publishes no "renders blank" property. The two errors are not symmetric: filtering too much
costs a finding that names what was not measured, filtering too little is a false `present`, so the
list errs long. That asymmetry is the whole answer to `Co`, and the residue is `D-m23-p`.

| Codepoint | Category | Named by |
|---|---|---|
| U+200B ZERO WIDTH SPACE | `Cf` | the finding |
| U+FEFF, U+00AD | `Cf` | **this runner** |
| U+3164 HANGUL FILLER | `Lo` — a letter | **the review**, all three lanes |
| U+034F COMBINING GRAPHEME JOINER | `Mn` | **the review** |

U+034F is the interesting one: adding `Mn Me Mc` to the categories closes it as a class rather than
as a codepoint, and cannot hide content, because a combining mark draws on the base character in
front of it — `readable("é")` still keeps the `e`.

**Arm.** Restoring truthiness returns all four to exit 0. Removing `BLANK_CODEPOINTS` returns
U+3164 alone. Removing the mark categories returns U+034F alone.

### B4 — one control answers one affordance

`pairs[state]` is keyed by affordance, so N affordances could name one build node and each earn
`present` off one measurement of one control. The claimants are now counted in a pre-pass, before
any row is written: if a pairing is ambiguous then neither claimant was measured, and letting
whichever came first keep `present` would pick a winner by inventory position.

Counted, not filtered — `[o for o in claimants if o != my_id]` looks like the same test and is not.
Two inventory entries sharing an id both name the node, the comprehension removes both occurrences,
and each row sees an empty list. The number of claimants is the quantity the check is named for.

| Route | Named by | Exit before | Exit now |
|---|---|---|---|
| two headings on one control | the finding | 0 | 1 |
| a heading and a sentence — different kinds | **this runner** | 0 | 1 |
| two inventory entries carrying one id | **the review** | 0 | 1 |

The third is reachable only from an inventory tool that does not disambiguate; `mock-affordances.py`
appends `#N`, so the selftest reaches it through a wrapper that strips the suffix rather than by
pretending the shipped tool can emit one. `D-m23-w`.

### D-m23-l — an unvouched pair reads `unclassified`

The coordinator's own correction. `divergent` is reserved for a difference that was measured, and
*this gate has never established the two are the same control* is not that. Four outcomes, one of
which is a claim that a measurement happened. On the filled ledger `divergent` falls 18 → 16 and
`unclassified` rises 6 → 8: the two rows the verifier identified, and no others.

It matters ahead of when it bites — the nine mock kinds `VOUCHED_CONTROLS` does not name
(`D-m23-h`) each land here, and a correct build would have read `divergent`.

**Arm.** Restoring `divergent` returns the ledger to `divergent 18 · unclassified 6`.

### The five the review added beyond the blockers

Duplicate layer names in the manifest (the dict keeps the last, so an appended optional entry
demotes a required layer — the list length is now compared to the dict's); the run order drifting
from the layer table (`declared[name]` sits one line outside the boundary, and the two lists are now
checked against each other); the manifest-validation exits leaving the ledger; the suppressed ledger
write; and the unmeasured ledger claiming a stage it does not know. All five are armed. The full
review, its factual probe and its negative control are in `M23-gapfix-2-review.md`.

## 14 · Gates, this pass

| Gate | Result |
|---|---|
| `mock-fidelity-gate.sh servers` | exit **1** — 132 findings, 116 breadth + 16 copy |
| ledger | `absent 80 · covered-by-pair 16 · divergent 16 · extra 10 · extra-cited 2 · present 3 · structure-unpaired 14 · unclassified 8` |
| `MCP_ROUTER_WRITE_TOKEN_REGISTER=1` | exit **3**, tokens INCONCLUSIVE, ledger written |
| `mock-fidelity-selftest.sh` | exit **0** — 47 cases, all three exits observed |
| `make lint` | exit **0** |
| `make test` ×2 | exit **0** twice, 1603 tests in 200 suites |
| `ledger-reconcile.py` | exit **0** — no findings across A–I |

The test count is 1603/200 where the work order quotes 1580/198; the difference arrived with `main`
in the merge at the top of this pass, not from anything here.

## 15 · What this pass found and did not fix

`D-m23-s` (copy measures unvouched pairings — `D-m23-l` one layer over, deferred because filtering
copy's population moves the finding count acceptance 6 pins at 16), `D-m23-t`, `D-m23-u`, `D-m23-v`
and `D-m23-w` are new rows in ORCHESTRATOR.md's deferred register; `D-m23-p` is rewritten to the
residue that is actually left. Everything from the first pass stays deferred.
