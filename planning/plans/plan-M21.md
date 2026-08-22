# plan-M21 — the token layer, the split accent, and re-authoring `DESIGN.md`

**Spec:** `planning/specs/spec-M21.md`
**Design of record:** `design/mcp-router-console.html` — settled 2026-08-22, recorded in `ORCHESTRATOR.md`'s DESIGN OF RECORD block. Do not reopen it.
**Branch:** `ai/m21` · **Worktree:** `.worktrees/M21`
**Tier:** Standard.
**Base:** `main` at `8863264`.

Deliver what is planned below, at the scope stated. Make routine judgement calls yourself and
record them in the branch's progress note; check in only where two readings would produce
materially different work. Delegate to a subagent only for a wide multi-file investigation you
cannot finish in a handful of tool calls, and keep the count at or below two.

---

## What this item is

The palette moves from *Instrument Panel* (graphite, dark-authored, 18 colour tokens, two
appearances) to *Patchbay* (light-first, 40 colour tokens, four resolved appearance contexts),
and `DESIGN.md` §1–2 is re-authored to say so. M23 has already measured the work:
`planning/fidelity/token-register.json` holds 89 rows, of which **45 carry an `M21-*` citation**
— 38 colour rows and 7 metric rows. The other 44 belong to M23's already-matched set, to the
icon catalogue, or to composite values nothing in Swift models.

The 38 colour rows split three ways, by the citation M23 filed them under:

| Citation | Rows | What it is |
|---|---|---|
| `M21-direction-split` | 16 | Tokens that exist in both and disagree: `--accent --attn --f1 --f2 --f3 --fail --ground --line --line-strong --live --panel --raised2 --t1 --t2 --t3 --t4` |
| `M21-ink-twins` | 7 | The text-safe family, absent from Swift: `--accent-ink --accent-text --attn-ink --badge-bg --fail-ink --live-ink --shield-good` |
| `M21-owns-the-mock-token-block` | 15 | Everything else the mock authors and Swift does not: `--accent-wash --accent-wash-line --chrome --desktop --focus --focus-halo --jack-off --jack-ring --menubar --scrim --sunken --tl-close --tl-min --tl-off --tl-zoom` |

Plus 7 metric rows under `M21-metric-rows`: `card-radius grid-unit jack-lane scrollbar
sidebar-row-large sidebar-row-medium toolbar-compact`.

**This item delivers the token layer, not the re-skin.** Every existing call site keeps the token
name it already names, so the app's appearance changes wherever a value changed — that is the
point. Choosing *which* surfaces move from `--accent` to `--accent-ink` is per-surface work owned
by M16, M17, M18, M19 and M22. §"Residual exposure" below states what that leaves open.

**It is Standard rather than Large** because it adds one new axis to an existing type, one new
parser section, and one new test suite. No new target, module, board, route or store.

---

## Sequencing against M16, and what goes red in between

**M21 lands first. M16 second.** Three reasons, in the order they bind:

1. **M16 needs tokens M21 authors.** `--jack-off`, `--jack-ring` and the `jack-lane` metric are
   the Signal Path's own values, and M23 filed all three under an `M21-*` citation.
   `scripts/lint/no-raw-design-values.sh` forbids a geometry or colour literal anywhere under
   `app/Sources/MCPRouterUI/Boards`, so M16 building first would have to add those tokens itself
   — which is this item.
2. **M16 must edit `DESIGN.md` §1's signature paragraph**, which is the paragraph M21 re-authors.
   Reversing the order puts two items in one paragraph.
3. **The parity oracles do not intersect.** `DesignTokenParityTests` reads the `Grounds and
   lines`, `Label tiers`, `Colour`, `Type` and `Chrome geometry` tables.
   `BreakerGeometryParityTests` reads `Breaker geometry` and nothing else. M21 can re-author the
   first five and leave the sixth untouched.

**What goes red between the two merges: nothing in the suite,** and that is a constraint on M21
rather than an observation about it. M21 leaves `### Breaker geometry` byte-identical, leaves
`BreakerGeometry.swift`, `BreakerGeometryTests.swift`, `BreakerParityTests.swift` and
`Breaker.swift` in place, and writes one sentence above the breaker table recording that it
documents the outgoing signature and retires under M16.

**What is inconsistent in that window, stated rather than hidden:** §1 will name the Signal Path
as the signature while §2 still carries the breaker's nineteen rows and the app still draws
levers. `PRD.md` §9.2 already names the Signal Path, so the window closes a PRD/DESIGN
disagreement rather than opening one.

**What would go red if M21 removed the breaker table early:**
`DesignDocParser.tableLines(in:under:"Breaker geometry")` throws
`ParseError.sectionNotFound("Breaker geometry")`, so **both** tests in
`BreakerGeometryParityTests` fail — `nameSetsMatchExactly` and `valuesMatchTheDocument` — with a
parse error rather than a value mismatch. That reads as a broken parser, not a retired element,
which is the uninterpretable red gate this ordering exists to prevent.

---

## Phase A — four appearance contexts on `ColorToken`

`app/Sources/MCPRouterKit/Design/ColorToken.swift`.

The mock authors six appearance blocks and the parser reads six
(`MockTokenParser.Appearance`: `light dark lightOverride darkOverride lightContrast
darkContrast`). `.is-light` mirrors `:root` and `.is-dark` mirrors the dark media block, so there
are **four distinct value sets**: light, dark, light+increased-contrast, dark+increased-contrast.
`ColorToken` grows from 18 cases to 40 and carries all four.

Only **9 of the 40 colour tokens** are re-solved under `prefers-contrast`: `--t2 --t3 --line
--line-strong --accent-text --live-ink --shield-good --attn-ink --fail-ink`. The other 31 take
their base value in the contrast context.

Four value pairs, following the shape already there (`hex`/`opacity`, `lightHex`/`lightOpacity`):

```
var hex / opacity                          // dark
var lightHex / lightOpacity                // light
var contrastHex / contrastOpacity          // dark + increased contrast
var lightContrastHex / lightContrastOpacity // light + increased contrast
```

The 31 non-overriding tokens return their base from an explicit `default:` arm rather than from
a computed fallback, so the parity test in Phase C compares four columns for every token and
nothing inherits unwatched. That is the invariant behind the brief's "author all four rather
than letting two inherit"; see decision **D1** for why it is not an asset catalogue.

**Two token spellings change to the mock's**: `--lineS` → `--line-strong` and `--onAccent` →
`--on-accent`. The Swift case identifiers (`lineStrong`, `onAccent`) stay. This collapses
`MockTokenRegister.colorNameMap` to an identity map, which removes the translation table that
`MockTokenRegister.swift:47-51` already names as the place a fuzzy match would pair
`--accent-ink` with `--accent`.

**22 new cases**, from the register's `swift: "absent"` rows:

`accentInk accentText accentWash accentWashLine attentionInk badgeBackground chrome desktop
failInk focus focusHalo jackOff jackRing liveInk menubar scrim shieldGood sunken trafficClose
trafficMinimise trafficOff trafficZoom`

**Values come from `planning/fidelity/token-register.json`, not from the HTML.** Every one of the
40 colour rows and 7 metric rows already records its value in every appearance the mock
authors, under `observed`, keyed `mock.light`, `mock.dark`, `mock.lightContrast`,
`mock.darkContrast`. Re-deriving them by reading
the CSS is a second parse of the same source with no oracle behind it.

Two shape changes the register makes visible. The label tiers stop being an alpha over the
ground and become solid hexes — `--t1` is `#17171A` light and `#FFFFFF` dark, where the built
token is `#000000@0.95` / `#FFFFFF@1.0`. Lines and fills stay `rgba`, so `opacity` remains
load-bearing for `--line --line-strong --f1 --f2 --f3 --scrim --jack-ring --accent-wash
--accent-wash-line`.

**`isReservedMeaning` extends to the ink family.** An ink is the same exclusive meaning at a
different lightness, so `accentInk accentText liveInk attentionInk failInk shieldGood
badgeBackground` all return `true`. Leaving them unreserved would open a hole in the
exclusivity rule exactly the size of the new tokens.

`app/Sources/MCPRouterUI/ColorToken+SwiftUI.swift` resolves the fourth axis. On AppKit,
`NSAppearance.bestMatch(from:)` over `[.aqua, .darkAqua, .accessibilityHighContrastAqua,
.accessibilityHighContrastDarkAqua]`; on UIKit, `traits.userInterfaceStyle` crossed with
`traits.accessibilityContrast == .high`. `components(for:)` gains a contrast argument. This file
and `TypeToken+SwiftUI.swift` stay the only two paths the lint exempts; the exemption list does
not grow.

---

## Phase B — `DESIGN.md` §1 and §2

**§1 · Direction.** *Patchbay* replaces *Instrument Panel*: a light-first precision routing
console, white ground with a graphite chrome step, the system accent on selection and focus,
three indicator hues each carrying a text-safe twin, `ui-monospace` reserved for anything a user
could paste into a terminal. The runner-up is *Blueprint Graphite*, set aside because the prior
direction was already dark graphite and because the densest reading surfaces are easier on a
light ground (`PRD.md` §9.1). The signature is the **Signal Path**; the breaker column is
recorded as the outgoing signature that M16 retires.

Line 8 — *"The reference implementation is `design/mocks/prototype.html`"* — becomes
`design/mcp-router-console.html`, with the paragraph's precedence rule kept: where this document
and the mock disagree, the mock is stale and this document is the spec.

**§2 · Tokens.** Three tables gain two columns each and a fourth table joins them.

| Table | Change |
|---|---|
| `### Grounds and lines` | Re-keyed; gains `--chrome --desktop --menubar --sunken --scrim --jack-off --jack-ring --tl-close --tl-min --tl-zoom --tl-off --focus --focus-halo --accent-wash --accent-wash-line` |
| `### Label tiers` | Re-keyed to solid hexes |
| `### Colour` | Re-keyed; gains the seven ink twins |
| `### Increased contrast` | **New.** Nine rows, the tokens the mock re-solves. Two value columns, Dark and Light |
| `### Chrome geometry` | Gains `Card radius 10pt · Compact toolbar 40pt · Grid unit 8pt · Jack lane 44pt · Scrollbar 12pt · Sidebar row medium 32pt · Sidebar row large 40pt` |
| `### Breaker geometry` | **Untouched**, plus one sentence recording that it retires under M16 |
| `### Type` | Unchanged. The mock's `body-type 13px` already matches `TypeToken.body` and the register classifies it `matched` |

The contrast overlay is a separate table rather than four value columns on each base table
(**D2**): 31 of 40 colour rows would repeat their base value twice, and a repeated cell is a cell that
drifts. As an overlay, *which* tokens override is itself an assertable set.

The `Contrast (light)` column stays and a `Contrast (dark)` column joins it, because light is now
the primary appearance and a ratio documented in one direction is a ratio checked in one
direction. Every value in both columns is computed with `Contrast.ratio` in Phase D and written
from that computation, never copied from the mock's own gate.

**Four strings in `DESIGN.md` are load-bearing for checks outside §2 and survive the re-author
verbatim.** `ShellAppearanceTests.indicatorUsesAreJustified` greps the document for the four
indicator meanings — *"selection, focus, the one primary action"*, *"a child process is
running"*, *"wants a human decision"*, *"failed or tripped"* — and
`MockTokenLiteralTests.citationsResolve` requires `DESIGN.md:309`'s *"an authored asset in the
catalogue."* to still be present. §4 is not re-authored here.

**`planning/features-to-triage/M21-token-layer-and-design-md.md` is not edited or moved.** Four
of M23's five citations quote lines 15, 33, 47 and 79 of that file verbatim, and
`citationsResolve` opens the file and matches the quote.

§10's list of what is owed loses two entries, and the plan should say why rather than delete
them quietly. `--fail` on `--raised` still measures **4.06:1** and `--accent` on `--raised` still
measures **4.31:1** in dark, because the mock ships the same three values. The split closes both:
`--fail-ink` `#FF5A5D` on `--raised` is **4.56:1** and `--accent-text` `#6FB6FF` on `--raised` is
**6.51:1**.

---

## Phase C — the parser and the parity suite

`app/Tests/MCPRouterKitTests/DesignDocParser.swift`:

- `ColorRow` gains `contrastHex/contrastOpacity`, `lightContrastHex/lightContrastOpacity` and
  `documentedDarkContrast`.
- `colorRows(in:)` keeps its `["Grounds and lines", "Label tiers", "Colour"]` walk and resolves
  the new columns by header name, as it already resolves `dark`, `light` and
  `contrast (light)`. Columns are resolved per table, so a table without `contrast (dark)` is
  not an error.
- **New** `contrastRows(in:) -> [ColorRow]` reading `### Increased contrast`.

`app/Tests/MCPRouterKitTests/DesignTokenParityTests.swift`:

- `colorsDocumentToCode` compares four value pairs per row instead of two.
- **New** `contrastOverlayNameSetsMatchExactly` — the overlay's row set and the set of
  `ColorToken` cases whose contrast value differs from their base are the same set, symmetric
  difference empty. This is what stops a token overriding in code without a documented row, and
  a documented row overriding nothing.
- `colorNameSetsMatchExactly`, `metricNameSetsMatchExactly` and the type checks are unchanged in
  shape and move with their tables.

`app/Tests/MCPRouterKitTests/LightAppearanceTests.swift`:

- `lightIsAuthored` extends to the contrast contexts: for each of the 9 overriding tokens, the
  contrast value differs from its base in the same appearance.
- `lightContrastMatchesTheDocument` gains a dark twin and the floor rises from `checked >= 17` to
  the count the re-authored document actually carries.
- `darkOnAccentDeviationIsPinned` is **replaced, not deleted** (**D5**). The 3.23:1 shortfall was
  accepted because there was one accent token and a native filled control carries a white label.
  With the split, a filled accent surface carrying text is `accentInk`: white measures
  **4.93:1** dark and **4.70:1** light, so the deviation is resolved rather than ported. The
  replacement asserts both figures clear 4.5 and that `--accent` is not the fill under
  `--on-accent` anywhere in `ColorToken`'s own declarations — otherwise removing the old test
  removes the only thing that noticed.
- `hoverPolarityReverses` holds unchanged: the mock's `--raised2` is `#E8E8EC` on a `#FFFFFF`
  light ground and `#3A3A3C` on a `#2C2C2E` dark one.

---

## Phase D — the contrast floor, measured across four contexts

**New** `app/Tests/MCPRouterKitTests/ContrastFloorTests.swift`, using the existing `Contrast`
helper in the same directory.

The test measures **the pairing each token's role implies**, not a cross-product (**D7**). A
cross-product reports failures that are not failures and hides one that is: `--shield-good` in
the dark contrast context measures **2.58:1** against the ground and **6.60:1** under white,
because it is a fill and never text. So each token declares one role:

| Role | Measured against | Floor |
|---|---|---|
| `onGround` — text | `--ground`, `--chrome`, `--panel`, `--raised` in the same context | 4.5:1 |
| `fill` — carries `--on-accent` | `--on-accent` composited over it | 4.5:1 |
| `hairline` — lines and fills | `--ground` in the same context | none; the ratio is recorded, not gated |
| `disabled` — `--t4` only | `--ground` | **exempt**, WCAG 1.4.3 incidental, claimed by name |
| `chrome` — traffic lights, desktop, scrim | — | not a text or fill pair |

The exemption is a named case in the role enum with the WCAG clause in its doc comment, so a
reader sees the claim rather than an absent row. A skipped check and a passed check are the same
shade of green, which is the failure this shape avoids.

Measured on the mock's values, for the plan's own record and as the expected outcome of the
first run:

| Token | Light on ground | Dark on ground | Note |
|---|---|---|---|
| `--accent-text` | 6.05 | 7.95 | text |
| `--live-ink` | 6.88 | 8.42 | text; dark equals `--live`, deliberately |
| `--attn-ink` | 6.51 | 7.62 | text; dark equals `--attn`, deliberately |
| `--fail-ink` | 5.88 | 5.57 | text |
| `--accent-ink` | 4.70 | 4.93 | **fill**, measured under white |
| `--badge-bg` | 5.50 | 4.88 | fill |
| `--shield-good` | 6.88 | 5.40 | fill |
| `--accent` | 3.52 | 5.26 | ring/dot only — the 3.52 is the failure the split exists for |
| `--t4` | 2.79 | 3.37 | disabled, exempt |

`--accent-ink` as *text* on `--chrome` measures **4.17:1** and on `--panel` **4.39:1**, both
under the floor. That is why the mock carries a third accent token and this plan takes it
(**D3**).

---

## Phase E — M23's register, its name maps and its two ratchets

`app/Tests/MCPRouterKitTests/MockTokenRegister.swift`:

- `colorNameMap` gains an entry per new `ColorToken` case.
  `MockTokenParityTests.theNameMapCoversTheWholePalette` requires every case to appear in
  `colorNameMap.values`, so a new case without an entry is red on the first run. With the two
  renames from Phase A the map is identity throughout.
- `metricNameMap` gains the 7 new metric rows. **Nothing in M23 watches a new `MetricToken`
  case** the way `theNameMapCoversTheWholePalette` watches `ColorToken`; add the mirror test
  (`theMetricNameMapCoversTheWholeLadder`) in the same change, because a gap you noticed and did
  not close is a gap the next item inherits.
- **The matching rule needs the fourth axis.** `MockTokenRegister.swift:243-251` requires
  agreement in *every* appearance the mock authors, and reads the Swift side as
  `appearance.isDark ? darkValue : lightValue`. With `ColorToken` carrying contrast values, the
  read becomes a four-way selection on `Appearance`. Without it the 9 overriding tokens can
  never leave `pending`, whatever their values.
- **The two ratchets extend, never shrink.** `mustMatchColors` (`--raised`, `--on-accent`) and
  `mustMatchMetrics` (11 names) gain every row that becomes `matched`. Extending is the
  ratchet's stated intent.

Then regenerate and commit the register:

```
cd app && MCP_ROUTER_WRITE_TOKEN_REGISTER=1 swift test --filter MockToken
```

`theCommittedRegisterMatchesWhatIsOnDisk` compares the live register to the committed JSON key by
key, so until it is regenerated every changed row is three red expectations — `classification`,
`observed`, `citation`. Regenerating is part of the change, not a follow-up.

**The `tokenRows: 89` floor in `planning/fidelity/servers.layers.json` counts mock rows, so
growing `ColorToken` does not move it.** It exits **3**, not 1, on a shrunken census. Nothing in
this item edits `design/mcp-router-console.html`, so the floor holds; if a mock property is ever
folded, the floor is lowered deliberately with the reason in the commit.

Expected census after this item: **89 rows, 64+ matched, ≤25 pending, 0 uncited** — the 45
`M21-*` rows move, the 14 asset rows keep `DESIGN-assets-live-in-the-catalogue`, and the 5
composite rows keep a citation. Any `M21-*` row that stays `pending` needs its citation kept and
its reason recorded; an uncited pending row is a gate finding at exit 1.

---

## Phase F — the documents that still point at the old direction

- `ORCHESTRATOR.md`:18 — *"Design authority: `DESIGN.md` at the root. Reference implementation
  `design/mocks/prototype.html`"* → the console mock. Leave the edit uncommitted for the
  orchestrator if the branch cannot carry it without conflicting.
- `PRD.md` §9.1 — the paragraph saying `DESIGN.md` is historical *until it is re-authored*
  becomes a statement that it has been, naming this item. §9.9's *"89 in its token block"* is
  M23's parsed row count, not a `:root` count; the `:root` block holds **45** properties, the
  file holds **59** distinct names across **188** declarations. §9.9's and §9.10's *"5,788
  pairs"* is stale: M24's `6c513b0` reports `contrast examined=6548 failures=0 unresolved=0`.
  §9.11's first bullet, *"`DESIGN.md` still describes the superseded direction"*, is removed.
- `planning/test-campaign/` is **not touched** — `campaign.json`'s `designOfRecord` is stale and
  another session owns that directory. `ORCHESTRATOR.md` already records it for that owner.

---

## Test strategy

### Seams

Seven existing, one new. Tests are written at these and nowhere else.

| Seam | File | What it holds |
|---|---|---|
| Document → data | `app/Tests/MCPRouterKitTests/DesignDocParser.swift` | `DESIGN.md`'s tables as typed rows |
| Document ↔ code | `app/Tests/MCPRouterKitTests/DesignTokenParityTests.swift` | Exact two-way name-set equality plus per-row values, now over four contexts |
| Value → meaning | `app/Tests/MCPRouterKitTests/LightAppearanceTests.swift` + `Contrast.swift` | The documented ratio is the ratio the value measures |
| **Floor (new)** | `app/Tests/MCPRouterKitTests/ContrastFloorTests.swift` | Every role-implied pair clears 4.5:1 in four contexts, with the disabled exemption named |
| Mock ↔ code | `app/Tests/MCPRouterKitTests/MockTokenParityTests.swift` + `MockTokenRegister.swift` | Classification, the name maps, the two ratchets, the committed fingerprint |
| Literal gate | `scripts/lint/no-raw-design-values.sh` | No colour or size outside the two binding files. Unchanged; the exemption list does not grow |
| Exclusivity | `app/Tests/MCPRouterUITests/ShellAppearanceTests.swift`, `PhoneIndicatorTests.swift` | An indicator hue is only ever its own meaning; extended to the ink family |
| Census | `scripts/acceptance/mock-fidelity-gate.sh` → `mock_fidelity.py` `tokens` layer | 89 rows, matched/pending/uncited, exit 3 on a shrunken census |

### Acceptance criteria, each falsifiable at `8863264`

| # | Criterion | The observation that shows it false, at base |
|---|---|---|
| AC1 | `DESIGN.md` §2 and `ColorToken` agree on 40 colour names and every value in four contexts | `DesignTokenParityTests.colorNameSetsMatchExactly` passes over 18 names today; adding `accentInk` alone reddens it |
| AC2 | Nine tokens carry a documented increased-contrast row, and exactly those nine differ from their base in code | `DesignDocParser.contrastRows` does not exist; `### Increased contrast` is not in the document |
| AC3 | Every `onGround` token clears 4.5:1 on `--ground --chrome --panel --raised` in all four contexts; every `fill` clears it under `--on-accent`; `--t4` is exempt by name | `ContrastFloorTests` does not exist. `--accent` on the mock's light `--ground` is 3.52:1 today |
| AC4 | `MetricToken` and §2's chrome table agree on 21 names | `metricNameSetsMatchExactly` passes over 14 today; the 7 mock metric rows classify `pending` with `swift: "—"` |
| AC5 | The committed register reports ≥64 matched and 0 uncited over 89 rows | `planning/fidelity/servers.ledger.md` reads `tokens clean · 25 matched, 64 pending, of 89 rows` |
| AC6 | Every `ColorToken` case resolves through `colorNameMap`, and every `MetricToken` case through `metricNameMap` | `theNameMapCoversTheWholePalette` passes at 18 cases; no `MetricToken` equivalent exists |
| AC7 | `make lint` is clean with the exemption list at two paths | It is clean today — this AC is a ratchet, and its falsifier is adding a third exemption |
| AC8 | `BreakerGeometryParityTests` is green on the merged branch | It is green today — this AC is what proves the M16 seam was respected |
| AC9 | A deliberately mismatched token is observed red, and the arming is recorded | No such record exists for this item |

**AC9 is arming, not a test to write.** `mock-fidelity-selftest.sh` has no automated case that
drives a mismatched mock token to exit 1 — M23's token mutations at
`planning/evidence/M23-acceptance.md:132-140` were hand-run against a byte copy and restored.
Follow that method: mutate one `ColorToken` value, run the parity suite, record the failure
message verbatim in the progress note, restore, and confirm `git diff --quiet`. Arm three:
a value change, a name added to `ColorToken` with no documented row, and a documented row with
no case. Each is a different assertion.

Run any review lane against a copy or from `/tmp`, never against the worktree —
`ORCHESTRATOR.md`:296 records a lane that applied its proposed mutation to the tree under test
between two gates.

### Anti-vanity discipline

The expected values come from `planning/fidelity/token-register.json` and from `Contrast.ratio`,
not from re-reading the source the code reads. A ratio asserted by recomputing it the way the
production code computes it cannot disagree with the code; the ratios in `DESIGN.md` are computed
once, written down, and then checked from the document.

There are no e2e or visual states here. The four contexts have never been rendered — `PRD.md`
§9.10 records that the sanctioned engine accepts `Emulation.setEmulatedMedia` and does nothing —
so increased contrast stays a specification. That is stated, not waived silently.

### The affected-test sweep

Grep for `ColorToken.`, `MetricToken.`, `--onAccent`, `--lineS`, `3.23`, `5,788`, `Instrument
Panel`, `breaker` and `prototype.html` across `app/Tests`, `app/Sources`, `scripts/` and
`planning/practices/`. Every hit is in scope: update it to the new contract and run it. The known
set is `ShellAppearanceTests`, `PhoneIndicatorTests`, `DesignSystemTests`,
`LightAppearanceTests`, `SWIFT_PRACTICES.md` §5 (which names the four indicator tokens and now
also owes the ink rule), and `scripts/acceptance/shells.sh`.

---

## Parity inventory — the old palette's load-bearing behaviours

| Behaviour | Disposition |
|---|---|
| Exact two-way name-set equality against `DESIGN.md` | **Keep**, widened to four contexts |
| A measured ratio documented per token | **Keep**, extended to a dark column |
| Light authored rather than derived | **Keep**, restated as: no context inherits unwatched |
| `--on-accent` white in both, exempt by name | **Keep** |
| `--raised2` polarity reversal | **Keep** — holds unchanged under the mock's values |
| Dark `--on-accent` on `--accent` at 3.23:1, accepted | **Resolved.** Filled text surfaces move to `accentInk` at 4.93:1 dark / 4.70:1 light. The pinning test is replaced, and the replacement asserts the new figures |
| `isReservedMeaning` over four indicator hues | **Port and widen** to the seven ink tokens |
| §10's two dark shortfalls on `--raised` | **Closed** by the ink twins; the measurements are recorded above |
| The catalogue-free dynamic provider | **Keep** — see D1 |
| Breaker geometry and its parity test | **Untouched** — M16's |

---

## Decisions taken here

**D1 — the dynamic colour provider stays; no `Assets.xcassets` colour sets.** The brief proposes
the catalogue, and `Assets.xcassets` holding zero colour sets is the reason the mechanism reads
as unbuilt. `ColorToken.swift`:18-21 already made and recorded this decision for two appearances:
a catalogue keeps its values in JSON `DesignTokenParityTests` never opens, so half the system
drifts unwatched. Four contexts strengthen that reason. What the catalogue would have been better
at is Xcode-native tooling and free system resolution; what it costs is the one check this whole
file exists to support.

**D2 — `### Increased contrast` is an overlay table, not four columns on three base tables.**
Nine of 40 colour rows override. As columns, 31 rows repeat their base value twice. As an overlay, the
override set is itself assertable, and the shape mirrors the mock's own two override blocks.

**D3 — three accent tokens, not two.** The brief names `--accent` and `--accent-ink`. The mock
authors `--accent-text` as well, and the measurement requires it: `--accent-ink` as text on
`--chrome` is 4.17:1 and on `--panel` 4.39:1. Collapsing the two would ship the failure the split
exists to prevent, one ground over. This is a widening against the brief and it is named as one.

**D4 — the inks are reserved meanings.** `isReservedMeaning` covers all seven.

**D5 — the 3.23:1 pinning test is replaced rather than deleted**, and the replacement asserts the
figures that supersede it. `SWIFT_PRACTICES.md` §7: if the test is wrong, fix it and say why in
the same change.

**D6 — M21 before M16**, for the three reasons in the sequencing section.

**D7 — the floor test measures by role, not by cross-product.**

---

## Open

- **The 9 contrast-overriding tokens cannot become `matched` without the four-way read in
  `MockTokenRegister`.** Phase E specifies it. If that read turns out to need more than a
  selection on `Appearance` — for instance because the register wants to record which contexts
  were compared — the fallback is to keep those 9 `pending` with their existing citation and say
  so in the census. That is a worse outcome and should be a decision, not a default.
- **Whether `PRD.md` §9.1's re-authored paragraph belongs in this branch or the orchestrator's
  merge.** Planned here as part of the branch; it is a two-paragraph edit to a file no other item
  in flight is editing.
- **How many of the 45 rows actually reach `matched` is not known until the register is
  regenerated.** The plan expects all 45. A row that does not is a finding with a reason, not a
  number to adjust.

---

## Out of scope, and the scope-narrowing check

Every line here was checked against the spec's seven triage assumptions.

- **The re-skin.** Choosing which call sites take `accentInk` over `accent` is M16/M17/M18/M19/
  M22. **Narrowing against assumption 1** (*"a single colour plus judgement at each call site is
  exactly how a label at 3.52:1 ships"*): this item delivers the tokens and leaves the judgement
  distributed. See "Residual exposure".
- **A word beside every colour.** Assumption 4 is a standing per-surface rule enforced by each
  board's own copy tests. M21 extends `isReservedMeaning` and audits no surfaces. **Narrowing
  against assumption 4**, stated so the owner can reject it.
- **`Assets.xcassets` colour sets** — D1.
- **Motion, type fidelity and the three accessibility media queries as measurements.** No engine
  available here executes CSS animation, loads a web font, or applies `setEmulatedMedia`. They
  stay specifications.
- **The breaker column and `### Breaker geometry`** — M16's.
- **`planning/test-campaign/`** — another session's.
- **The `Type` ladder** — already matched.

### Residual exposure

M21 gives every surface a text-safe token and does not make any surface take it. A board that
keeps drawing a 13pt label in `--accent` on `--ground` still ships 3.52:1, and no check in this
item catches it: `ContrastFloorTests` proves the palette can clear the floor, not that each call
site does. The existing `ShellAppearanceTests.noUndeclaredIndicatorUse` source grep is the shape
that would close it app-wide, and extending it past the shell is M17's surface work. Recorded
here rather than fixed, because fixing it means editing roughly seventy view files that four
other items are about to rewrite.

---

## Gate note

**Mechanical path check.** Every backtick-quoted path in this plan resolves. Nine citations are
written as bare basenames and were resolved by search — `Breaker.swift`, `BreakerGeometry.swift`,
`BreakerGeometryTests.swift`, `BreakerParityTests.swift`, `campaign.json`, `Contrast.swift`,
`mock_fidelity.py`, `mock-fidelity-selftest.sh`, `PhoneIndicatorTests.swift` — and one,
`app/Tests/MCPRouterKitTests/ContrastFloorTests.swift`, is absent because this item creates it. The
`ColorToken.swift` line citation was corrected from `:19-24` to `:18-21` during the check.

## Out-of-family review — record and disposition

### The gate did not run during planning

Recorded first because it is the reason this section arrives separately from the plan above. The
planning session attempted the review three times on 2026-08-22 and got nothing back from any of
them:

| Lane | Attempt | Result |
|---|---|---|
| `agy` / `gemini-3.7-flash-high` | 08:04, plain `-p` | Zero-byte report. `Error: permission check failed for command "pwd; ls -la": user denied permission to run command` |
| `agy` / `gemini-3.7-flash-high` | 08:06, `--sandbox --dangerously-skip-permissions --print-timeout 13m` | Zero-byte report. `Error: timeout waiting for response` |
| `claude-fable-5` at high effort | 08:04, in parallel as the second reading | Zero-byte report and zero-byte log; still running when the session ended |

`codex` / `gpt-5.6-sol` is recorded down until 2026-08-27 and was not attempted; `grok-4.6`'s
balance is exhausted and it was not attempted.

The gate was run afterwards, on 2026-08-22, against the same `/tmp/m21-review` packet — the plan
copy is byte-identical to the committed file, and the packet's own `BEFORE.sha` guard re-verified
clean after both lanes finished. **Both lanes answered this time**, so the review stands on two
families rather than one.

One process note. `ORCHESTRATOR.md`'s rule at `:296` requires a `-p` lane asked to break something
to get a read-only sandbox or a throwaway copy. The packet was a throwaway copy, but `agy` ran under
`--dangerously-skip-permissions` and its citations resolve to paths in the live worktree, so it read
the real tree rather than only the copy. It wrote nothing: the sha guard is clean and `git status`
shows no change to any file this item touches.

### Verdict: AMEND, from both lanes

Eight questions each. `agy` / `gemini-3.7-flash-high` returned OK on four and DEFECT on four;
`claude-fable-5` returned OK on two, DEFECT on five and a QUESTION on the eighth.

| # | Question | gemini | fable | What it found |
|---|---|---|---|---|
| 1 | Completeness | DEFECT | OK | Both name spec assumption 4 (*a word beside every colour*) as touched by no AC. They differ on whether that matters: fable reads it as covered by the plan's own declared narrowing, gemini as a narrowing with no validating gate. **Both independently name the same undeclared omission** — the brief's non-native-cursor prohibition at `spec-M21.md:72-74` has no AC, no seam and no out-of-scope line |
| 2 | Silent shrinkage | DEFECT | DEFECT | gemini: the five composite shadow rows — `--shadow-card --shadow-pop --shadow-sheet --shadow-tile --shadow-window` — all carry `citation: "M21-owns-the-mock-token-block"`, and the plan neither models nor declares them. fable: the cursor omission again, plus that nothing asserts the mock's mirror blocks *stay* mirrors except the register fingerprint |
| 3 | Analogues | OK | DEFECT | Both opened the files and confirmed all four cited claims: `colorRows` resolves columns by header name; `DesignTokenParityTests` asserts symmetric-difference equality in both directions; `BreakerGeometryParityTests` reads `Breaker geometry` and nothing else; `theNameMapCoversTheWholePalette` requires every `ColorToken` case in `colorNameMap.values`. fable contradicted a claim the plan makes about itself — see the census finding below |
| 4 | Ordering | OK | OK | **M21 before M16 is confirmed by both**, on the plan's own reasoning plus one gemini adds: M16 landing first would have to author `--jack-off`, `--jack-ring` and `jack-lane` in `ColorToken`, which reddens two-way parity against `DESIGN.md` immediately. fable found a red gate inside M21's *own* first run that the plan does not predict — see below |
| 5 | Decision D2 | OK | OK | The overlay table is right, and both name the same advantage the column form would have had: a token's whole story in one row, no cross-reference, one parsing pass. fable adds that the plan's *stated* reason is wrong on its own terms — `colorsDocumentToCode` compares every value column against code, so a drifted repeated cell goes red either way. The decision survives; the reason should become the one the plan also gives, that the override set becomes assertable |
| 6 | Decision D6/D3 | DEFECT | DEFECT | Both recomputed the contrast arithmetic independently and both found it correct, so the three-token split stands. **They then named two different fourth problems, and both are real** — below |
| 7 | The parity inventory | DEFECT | DEFECT | **The strongest agreement in the review, reached independently.** The 3.23:1 pin must be *ported*, not replaced. `--accent` dark stays `#0091FF`, M21 migrates no call sites, so white-on-accent keeps shipping until M16–M22 move them, and deleting `darkOnAccentDeviationIsPinned` removes the only automated measurement of the live pairing during exactly that window |
| 8 | The option not listed | OK | QUESTION | Both proposed the same shape: make the role data a declared, parity-checked contract rather than knowledge private to a test file. fable would add a Role column to §2's tables or a declared pairing map in `ColorToken`; gemini would rename to a three-tier taxonomy (`-ui` / `-fill` / `-text`) across every hue |

### The three findings that are checkable, and were checked

Verified against this repository rather than taken on the lanes' word.

- **The census in the plan's opening paragraph is wrong: 50 rows carry an `M21-*` citation, not
  45.** `token-register.json` splits them 38 colour, 7 metric and **5 composite** — the shadow rows
  gemini named — under `M21-direction-split` (16), `M21-ink-twins` (7),
  `M21-owns-the-mock-token-block` (20) and `M21-metric-rows` (7). The plan's *"45 carry an `M21-*`
  citation — 38 colour rows and 7 metric rows"* omits the composites, and §"Out of scope" does not
  declare them either.
- **Five tokens carry only `mock.light`, so the register is not an oracle for their dark values.**
  `--accent-wash`, `--accent-wash-line`, `--tl-close`, `--tl-min` and `--tl-zoom` each have
  `observed` keys `mock.light` and `swift` and nothing else, because the mock authors them once in
  `:root`. The plan's rule that *"values come from `planning/fidelity/token-register.json`, not from
  the HTML"* has five rows it cannot satisfy, and inventing their dark values is the second parse
  with no oracle the plan forbids itself.
- **`LightAppearanceTests.lightIsAuthored` will redden on those same five tokens.** It iterates
  `ColorToken.allCases where token != .onAccent` and expects each to differ between appearances
  (`LightAppearanceTests.swift:35-40`). Growing `ColorToken` to 40 cases brings in tokens that are
  identical in both by design, so the exemption list has to widen **by name** — which is what that
  test's own docstring argues for, calling a blanket exemption *"a hole waiting for the value that
  walks into it"*. This is the red gate finding 4 says the plan did not predict.

### The fourth problem in D3, where the lanes disagree

Both accept the three-token split and the measurement behind it. Neither problem is the other's.

- **fable — a missing rung.** The role table has two floors where the WCAG ladder has three. There
  is no 3:1 non-text rung (1.4.11), so `--accent` used as a ring or a dot measures **3.12:1 on light
  `--chrome`** with nothing holding it there, and `--focus` at 3.52:1 falls under no role at all. A
  small accent drift then ships a real non-text failure that `ContrastFloorTests` cannot see.
- **gemini — an inverted suffix.** `--accent-ink` is a background *fill* carrying white text, while
  `--live-ink`, `--attn-ink` and `--fail-ink` are *text* colours sitting on ground surfaces. The
  same suffix means opposite things across the palette, so a developer reaching for `--accent-ink`
  as text by analogy with the status twins ships a contrast failure by following the naming.

Each lane's own nomination for the single most important change differs accordingly: fable's is
porting the 3.23:1 pin, gemini's is disambiguating `--accent-ink`'s role.

### Disposition: none yet, and that is deliberate

**Nothing in this review is dispositioned into the plan body above.** These verdicts arrived after
the planning session ended, and this record is the handover rather than a second planning pass. The
plan is unchanged, including the 45-row census that finding 2 shows is 50.

What a runner picks up, in the order the review weighted it: port `darkOnAccentDeviationIsPinned`
rather than replacing it, and drop the compensating assertion fable showed is unenforceable —
`ColorToken.swift` declares values only, with no fill/label pairing for it to read; widen
`lightIsAuthored`'s exemption list by name before growing the palette; decide the dark values for
the five light-only tokens as a recorded decision rather than a derivation; declare or model the
five composite shadow rows and correct the census; add the 3:1 non-text rung, or say why the role
table stops at two; and settle whether `--accent-ink` keeps a suffix that means the opposite of
every other `-ink`. The cursor prohibition needs an out-of-scope line either way.
