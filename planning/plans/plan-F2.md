# F2 — Implementation plan

**Spec:** `planning/specs/spec-F2.md`
**Plan size:** Large
**Branch:** `ai/f2` · worktree `.worktrees/F2`
**Written:** 2026-08-14

## Task

Turn `DESIGN.md` into code so no surface hardcodes a colour, size or radius. Ship the authored
light appearance alongside the existing dark one, the eight-role type ramp, the 21-icon set, the
control ladder, the breaker as a reusable view with its two springs, and the nine state containers.
Add a Debug-only gallery to both apps that renders every one of those in both appearances, so the
claims are observable rather than asserted. Replace the two private `swiftUIColor` bridges F1 left
in the shells, which F1's own comments say this item removes.

## Approach

Three layers, in dependency order.

1. **Values** stay in `MCPRouterKit` (no UI framework), extended from one appearance to two, plus
   the geometry that is currently prose. `DESIGN.md` gains a Light column and individual geometry
   rows; the parser and parity suite are widened to read both appearances and proven by breaking.
2. **Presentation** is a new `MCPRouterUI` product that depends on `MCPRouterKit` and imports
   SwiftUI. Both app targets link it. This is the only compliant home: `planning/practices/SWIFT_PRACTICES.md` §8
   requires `MCPRouterKit` to stay free of UI frameworks so the router's tests can import it, and
   putting the shared views in each app would make two systems.
3. **Gallery** is a `#if DEBUG` surface in `MCPRouterUI`, hosted by both shells.

**Deliberate deviation from the brief.** The brief says "as an asset catalogue with light + dark".
The light values instead live in `ColorToken` as a second pair, and the SwiftUI layer builds a
dynamic colour from them. Reason: an asset catalogue stores its values in JSON the parity suite
does not read, so the light half would be unwatched — precisely the defect the cross-family review
raised as its highest finding. Acceptance criterion 1 ("changing any light value turns the drift
check red") is unachievable with catalogue-resident values. The dynamic colour is built with
`NSColor(name:dynamicProvider:)` / `UIColor(dynamicProvider:)`, which is what a catalogue compiles
to anyway.

## Reference implementation

`app/Sources/MCPRouterKit/Design/ColorToken.swift` and
`app/Tests/MCPRouterKitTests/DesignTokenParityTests.swift` — F1's bidirectional, exact-name-set
parity pattern. Extend it; do not replace it. `scripts/acceptance/shells.sh` is the model for
behavioural evidence: it samples a rendered pixel and walks the accessibility tree, and reads its
expected colour out of the token rather than pinning a copy.

## Prerequisites

- `make generate` after `app/project.yml` changes (the `.xcodeproj` is generated and untracked).

---

## Requirements & Decisions

### Functional

1. Every colour token carries a dark **and** an authored light value; light is never derived.
2. `DESIGN.md` records both appearances, one row per token, plus the three fill entries.
3. The parity suite compares **both** appearances in both directions, and fails on light drift.
4. Geometry currently written as prose becomes individually recorded values with parity coverage.
5. The eight type roles bind to `Font`, with a monospace variant for instrument data.
6. All 21 prototype icons resolve; an unmapped name cannot compile.
7. Control ladder (16/20/24/28/36), selection fill (radius 8, 4pt insets), focus ring (2pt, accent).
8. The breaker: one dormant + three lit states, slot ≥ toggle wide and strictly taller, two springs,
   Reduce Motion honoured.
9. The nine state containers ship with the spec's real copy.
10. A Debug-only gallery in both apps renders all of the above in both appearances.
11. A lint gate fails the build on a raw colour or font-size literal outside the binding layer.
12. Both shells drop their private `swiftUIColor` bridge and draw from `MCPRouterUI`.

### Constraints & Decisions

- Locked by triage: light matches dark's **measured ratios**, not its alphas; `--raised2` reverses
  direction in light; amber shifts to 40° from red; the primary label stays white in dark as a
  kit-mandated deviation at 3.23:1; the breaker housing grows to 30×48 so the lamp cannot clip.
- `MCPRouterKit` gains **no** UI-framework import. Breaker *geometry* is a value type there so its
  invariant is testable headlessly; the breaker *view* lives in `MCPRouterUI`.
- `design/mocks/prototype.html` is not edited.

---

## Steps

> **Steps 1–5 are ONE checkpoint, committed together.** They are written separately for clarity, but
> the tree must not be left red between them. The reason is specific and was caught by the plan
> review: renaming `ColorToken.hex` breaks `DesignTokenParityTests:29`, which is a **compile**
> failure, not a parity failure — and a suite that cannot compile hides every other regression in
> the same window, including step 2's. Land values, document, parser and tests as one green move.

### 1. Extend `ColorToken` to two appearances
- **File:** `app/Sources/MCPRouterKit/Design/ColorToken.swift` · **Modify**
- **Details:** Keep `hex`/`opacity` as the **dark** accessors (do not rename — two call sites in the
  shells and the parity suite depend on them, and renaming buys nothing). Add `lightHex` and
  `lightOpacity`. Values from the spec's reviewed table: ground `#ECECEE`, panel `#F5F5F7`, raised
  `#FFFFFF`, raised2 `#E0E0E4`, line `#000 @10%`, lineS `@19%`, t1 `@95%`, t2 `@62%`, t3 `@58%`,
  t4 `@33%`, f1 `@13%`, f2 `@10%`, f3 `@6%`, accent `#0069CF`, live `#1B7B3C`, attn `#9F5A00`,
  fail `#CD2738`. Add cases `f1`, `f2`, `f3`, `onAccent` (`#FFFFFF` in both appearances).
- **Fulfils:** Functional 1.

### 2. Record the geometry that is currently prose
- **File:** `app/Sources/MCPRouterKit/Design/MetricToken.swift` · **Modify**
- **Details:** Add cases for the five control sizes, `Sidebar selection radius` (8), `Sidebar
  selection inset` (4), `Focus ring` (2). Remove `Control ladder` and `Sidebar selection` from
  `metricRowsNotMachineChecked` once `DESIGN.md` carries them as individual rows — the existing
  `exclusionsAreJustified` test asserts an excluded row really is prose, so it will now confirm the
  list no longer holds these two.
- **Fulfils:** Functional 4, 7.

### 3. Rewrite `DESIGN.md` §2 for two appearances and individual geometry
- **File:** `DESIGN.md` · **Modify**
- **Details:** Every colour table becomes `| Token | Dark | Light | Contrast (light) | Use |`, one
  row per token. **Fills go into the existing `### Colour` table, not a new `### Fills` heading** —
  `tableLines` scans exactly three headings (`Grounds and lines`, `Label tiers`, `Colour`), so a new
  heading would be silently invisible. Geometry gains one row each for the five control sizes,
  selection radius, selection inset and focus ring. Add a paragraph stating the authored-light rule
  (match the measured ratio, not the alpha) and the two deliberate deviations (the `--raised2`
  reversal; the white label at 3.23:1 with the kit-precedence reason). Replace §10's "Light
  appearance is unauthored" bullet with what remains owed.
- **Fulfils:** Functional 2.

### 4. Breaker geometry as a headless value type
- **File:** `app/Sources/MCPRouterKit/Design/BreakerGeometry.swift` · **Create**
- **Details:** A `Sendable` struct holding housing 30×48, lamp boss 8, slot 22×34 inset (4, 11, 4,
  3), toggle 22×15, travel 4→19, and the two spring parameters (rise: response 0.18, overshoot;
  fall: response 0.6, critically damped). Expose `slotIsAtLeastAsWideAsToggle` and
  `slotIsStrictlyTallerThanToggle` so the invariant is a value, not a drawing.
- **Why here:** it must be testable without a UI harness, and `MCPRouterKit` is the headless target.
- **Fulfils:** Functional 8.

### 5. Widen the parser and the parity suite to both appearances
- **Files:** `app/Tests/MCPRouterKitTests/DesignDocParser.swift`,
  `app/Tests/MCPRouterKitTests/DesignTokenParityTests.swift` · **Modify**
- **Details — four specific traps the current parser has, each confirmed by reading it:**
  1. `cells(of:)` ends with `.filter { !$0.isEmpty }` after a non-omitting split, so **one empty
     cell shifts every later column index**. Stop dropping internal empties: trim only the leading
     and trailing pipe fields, keep interior cells even when blank.
  2. `colorRows` reads `c[1]` unconditionally and its own comment says a further column "is ignored
     by position". Resolve **Token / Dark / Light by normalised, case-insensitive header name, per
     table**, since the three tables need not share a column order.
  3. There is no validation of header presence, duplication, or row width. **Fail loudly** — a
     missing or duplicated `Light` header, or a row shorter than its header, throws rather than
     silently reading the wrong cell. A parser whose failure mode is "reads the neighbouring
     column" is the same class of defect as the silent-empty-read this repo already recorded.
  4. `ColorRow` gains a light hex/opacity pair.
- **Tests to add:** light parity in both directions; exact name-set parity including the new fill
  and `onAccent` rows; a **reordered-column** case and an **empty-cell** case proving the header
  lookup is not positional; breaker-invariant tests over `BreakerGeometry`.
- **Red-green proof (required by `planning/practices/SWIFT_PRACTICES.md` §7):** corrupt one light
  value, one fill value, one geometry value and the breaker slot height; watch each go red;
  restore. Record it in the progress note.
- **Verify:** `make test` green at the end of this checkpoint, with a higher executed-test count.
- **Fulfils:** Functional 3, 4, 8.

### 6. Create the `MCPRouterUI` product
- **Files:** `app/Package.swift`, `app/project.yml` · **Modify**
- **Details:** Add a `MCPRouterUI` library target at `Sources/MCPRouterUI` depending on
  `MCPRouterKit`, Swift 6 language mode, plus a `MCPRouterUITests` test target. In `project.yml`
  add the `MCPRouterUI` product to both app targets' dependencies. No external packages.
- **Verify:** `make generate && make build` both platforms.
- **Fulfils:** Functional 12 (enabling).

### 7. Colour and type bindings
- **Files:** `app/Sources/MCPRouterUI/ColorToken+SwiftUI.swift`,
  `app/Sources/MCPRouterUI/TypeToken+SwiftUI.swift` · **Create**
- **Details:** `ColorToken.color` returns a `Color` backed by
  `NSColor(name:dynamicProvider:)` on macOS and `UIColor(dynamicProvider:)` on iOS, selecting the
  dark or light pair from the appearance. `TypeToken.font` returns
  `.system(size:weight:)` at the token's size and emphasis, and `.monospaced` variant for instrument
  data. These two files are the **only** place a raw colour component or size literal is permitted;
  step 12's lint exempts them by name.
- **Fulfils:** Functional 1, 5.

### 8. The icon set
- **File:** `app/Sources/MCPRouterUI/Icon.swift` · **Create**
- **Details:** An exhaustive `enum Icon: CaseIterable` with the 21 cases from the prototype sprite
  (`activity, servers, skills, discover, inbox, evals, cleanup, settings, search, chev, check,
  warn, bang, shield, bolt, tray, book, list, compass, layers, conduit`), each mapping to an SF
  Symbol name at a matched weight, or to a bundled asset where no symbol fits. Exhaustiveness means
  a missing case is a compile error, not a blank glyph.
- **Verify:** a test asserts every case resolves to a non-empty symbol name and that
  `Icon.allCases.count == 21`.
- **Fulfils:** Functional 6.

### 9. Control styles, selection and focus ring
- **File:** `app/Sources/MCPRouterUI/Controls.swift` · **Create**
- **Details:** A `ControlSize` ladder reading `MetricToken`; a `selectionFill` modifier (inset
  rounded, radius 8, 4pt side insets, accent label — never full-bleed, per `DESIGN.md` §3.1); a
  `focusRing` modifier at 2pt bound to `--accent`. Every value read from a token.
- **Fulfils:** Functional 7.

### 10. The breaker view
- **File:** `app/Sources/MCPRouterUI/Breaker.swift` · **Create**
- **Details:** `Breaker(state:)` over `enum BreakerState { dormant, running, wantsYou, tripped }`,
  drawing plate, lamp boss, slot and toggle from `BreakerGeometry`. Rise uses the overshoot spring,
  fall the critically damped one. When `accessibilityReduceMotion` is set, the transition is removed
  and the state change still applies. Accessibility label states the state in words, so colour is
  never the only signal.
- **Fulfils:** Functional 8.

### 11. The nine state containers
- **File:** `app/Sources/MCPRouterUI/StateContainer.swift` · **Create**
- **Details:** One composable view per state carrying the spec's exact copy. `offline` is its own
  case saying the router is not running and offering to start it — never a generic error banner
  (`planning/practices/SWIFT_PRACTICES.md` §3). Model the set as an enum so a surface that switches over it must handle
  every case.
- **Fulfils:** Functional 9.

### 12. The literal lint gate
- **Files:** `scripts/lint/no-raw-design-values.sh` · **Create**; `Makefile` · **Modify**
- **Details:** Fail when a file under `app/Sources/MCPRouterUI` or the two app shells contains a hex
  colour literal, an `NSColor`/`UIColor`/`Color(.sRGB` construction, or `.system(size: <number>`.
  Exempt exactly the two binding files from step 7, by explicit path, so the exemption is visible.
  Wire into `make lint`.
- **Verify:** add a raw literal to a shell, watch `make lint` fail, remove it. Record it.
- **Fulfils:** Functional 11.

### 13. The gallery
- **Files:** `app/Sources/MCPRouterUI/Gallery/DesignGallery.swift` (+ per-section views) · **Create**
- **Details:** Wrapped in `#if DEBUG`. Six sections — Colour, Type, Icons, Controls, Breaker,
  States — with a System/Dark/Light switch driving `.preferredColorScheme` so both appearances are
  reviewable without changing the machine setting. `NavigationSplitView` on macOS,
  `NavigationStack` on iOS. Breaker section exposes a real toggle so the springs can be watched —
  `DESIGN.md` §10 records that motion has never been observed running. Stable accessibility
  identifiers on each section for the acceptance harness.
- **Layout reference:** `design/mocks/light-appearance.html`.
- **Fulfils:** Functional 10.

### 14. Adopt in both shells, delete the bridges
- **Files:** `app/MCPRouter/MCPRouterApp.swift`, `app/MCPRouterIOS/MCPRouterIOSApp.swift` · **Modify**
- **Details:** `import MCPRouterUI`; delete both private `extension ColorToken { var swiftUIColor }`
  blocks; draw via the shared bindings; add a Debug-only entry to the gallery.
- **Fulfils:** Functional 12.

### 15. Extend the acceptance harness
- **File:** `scripts/acceptance/shells.sh` · **Modify**
- **Details:** Add assertions that the gallery opens in a Debug build, that a sampled pixel matches
  the **light** ground when the light appearance is selected (the only assertion proving light
  actually renders), and that a Release build does not contain the gallery's identifier string.
  Keep the existing distinct exit codes: 2 = environment could not run, 1 = assertion failed.
- **Fulfils:** Functional 10, and acceptance criteria 1 and 9.

---

## Edge cases

- **Parser column order.** Reading Dark/Light by header name rather than index; a reordered column
  must not silently repoint the comparison.
- **`swift test` builds `MCPRouterUI`.** SwiftUI is present on macOS so this compiles; the point of
  the split is the *rule*, not a compiler limitation. `MCPRouterKit` keeps no UI import so the
  router's own tests stay clean.
- **Reduce Motion must not remove the state**, only the animation.

## Acceptance criteria

The spec's eleven, plus the assumption coverage the plan review found missing.

- [ ] Light differs from dark for every colour, and breaking one light value turns the suite red.
- [ ] Both directions of parity hold, for both appearances, over the full name set.
- [ ] Eight type roles at their stated size and line height, **and nothing renders off the ladder** —
      enforced by step 12's lint, not by inspection.
- [ ] 21 icons each resolve to a glyph that **actually draws** (a non-empty symbol name is not
      enough — a wrong SF Symbol name renders blank); an unmapped case fails to build.
- [ ] Control sizes, selection radius/insets and focus ring all come from tokens and are checked
      against the authority.
- [ ] Breaker: 4 states; slot ≥ toggle wide and strictly taller in every one; breaking it goes red.
- [ ] **Every breaker dimension is parity-checked against the authority**, not only the invariant.
- [ ] Springs correct; Reduce Motion drops the animation, keeps the state change.
- [ ] Nine states render with the spec's copy, in both appearances.
- [ ] Gallery present in Debug in both apps, absent from Release.
- [ ] A raw colour or font-size literal outside the two binding files fails `make lint`.
- [ ] Neither shell carries a private colour bridge.
- [ ] **Light reproduces dark's measured contrast ratio** per tier — asserted numerically, since
      that is the whole authored-not-inverted claim.
- [ ] **Hover polarity is asserted**: `raised2` is lighter than `raised` in dark and darker in light.
- [ ] **`onAccent` is white in both appearances**, with its dark ratio recorded as a known
      kit-mandated deviation rather than silently passing a contrast assertion.
- [ ] **The lamp sits inside the housing bounds** — asserted from geometry, so it cannot clip.
- [ ] **`MCPRouterKit` imports no UI framework** — asserted by a source check, so the separation
      cannot rot.

## Verify

- `make all` (tools, lint, build both platforms, test) green; executed-test count rises.
- `make acceptance` green — pixel + accessibility evidence, not a build gate.
- Red-green proof recorded for: one light value, one fill, the breaker slot height, the lint gate.

## Out of scope

- Editing `design/mocks/prototype.html` (shared reference; other items cite it).
- Fixing surfaces that misuse an indicator colour decoratively — the phone prototype paints trend
  deltas in `--live`/`--fail`, which `DESIGN.md` §2 forbids. Reported to the orchestrator; owned by
  the Discover items (M5/I2).
- The pre-existing dark-appearance shortfall where `--fail` (4.06:1) and `--accent` (4.31:1) sit
  under AA as text on `--raised`. Reported, not changed: altering a shipped dark value is a
  shared-surface change this item was told to report rather than make.
- Any router, control-API or install-script change.

---

## Plan review gate — 2026-08-14

**Mechanical path check:** pass. Every backtick path resolves, except those explicitly marked
**Create**.

**Cross-family review:** `gpt-5.6-sol`, read-only, grounded in the repository.
**Logged downgrade:** the first attempt at `max` effort hit its 540s deadline and wrote an empty
output file — an over-scoped review that burned its turn budget. Per the effort ladder that is a
lane failure, not a pass, so it was retried **once at `high` with a narrowed scope** (four files,
three questions). Wire-verified on the retry: `model: gpt-5.6-sol`, `reasoning effort: high`. The
gate therefore ran one tier below what it specifies, and this note is here so the next reader knows
which pass they got.

**Verdict: MATERIAL DEFECTS** — 3 High, all accepted and fixed above. Accepted 3 · rejected 0 ·
escalated 0. Each was verified against the source before acceptance rather than adopted on the
reviewer's word.

1. **The ordering was unsound.** Step 1 as first written renamed `ColorToken.hex`, which
   `DesignTokenParityTests:29` calls — so the intermediate state was a **compile** failure, not the
   "expected parity failure" the plan claimed, and a suite that cannot compile hides every other
   regression in the same window (including step 2's). *Fixed:* `hex`/`opacity` are kept as the dark
   accessors, and steps 1–5 are declared one green checkpoint.
2. **The parser change was under-specified, in a way the repo has been bitten by before.**
   `cells(of:)` filters out empty cells after a non-omitting split, so a single blank cell shifts
   every subsequent column index; `colorRows` reads `c[1]` unconditionally; nothing validates header
   presence, duplication or row width. *Fixed:* four named traps in step 5, header-name resolution
   per table, loud failure, and tests for reordered and empty columns. Confirmed by reading the
   source, not taken on trust.
3. **The acceptance list was not the "verbatim" set it claimed.** It had dropped "nothing renders
   off the ladder" and weakened the icon check to a non-empty string, and six triage assumptions had
   no acceptance coverage at all. *Fixed:* restored and extended to seventeen criteria.
