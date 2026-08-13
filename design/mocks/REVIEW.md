# Design review — Conduit prototype

**Verdict: the "low-fi" read was correct and had four measurable causes, all now fixed.**
19 of 21 surfaces reviewed. The two static contact sheets (`mac-surfaces.html`,
`ios-surfaces.html`) were **not** reviewed — they are superseded by `prototype.html` and
should be deleted or regenerated rather than repaired.

Driver: obscura `serve` + CDP at DPR 2, 1200×860 (Mac) and 420×800 (phone). Serving over
HTTP, cache disabled. Findings below are ordered by severity.

---

## What "low-fi" actually was

Four causes, each measured before and after rather than judged.

### 1 — High · The signature element did not read

The breaker column is the one element carrying the direction, and at 1× a running server
and a dormant one were the same grey box.

**Measured:** 16px of lever travel inside a 40px housing, lever `#3A3F46→#2A2E34` against
housing `#1A1C1F→#141619` — roughly a 6% luminance delta. State was encoded in position
alone, at a magnitude below casual perception.

**Fixed:** the housing now exposes a recessed track that lights from behind when the server
is energised (green), tripped (red) or held (amber). State is carried by colour, position
and glow at once. Housing rebalanced 32×46 → 38×42, which stops it reading as a battery;
lever shortened to 15px so more lit track is visible in the up state; moulded ridges added
so a 38px lever reads as a physical thumb-grip.

### 2 — High · Unicode glyphs standing in for an icon system

`▤ ⎔ ◇ ✦ ⌸ ◐ ⇣ ⚙ ⌕ › ✓ ⚠ ✕ ⛶` were doing the work of an icon set across the sidebar, menu
bar, tab bar, status chips, chevrons and empty states. They render at inconsistent weights
and optical sizes because each glyph resolves to a different fallback font — `⎔` came back
as a bare circle. This is the loudest low-fidelity tell available and `design-craft` names
it explicitly.

**Fixed:** a drawn 16px SVG sprite (21 symbols, one 1.4 stroke weight, one grid,
`currentColor`) replaces every one. Verified programmatically across 13 surfaces: zero
glyphs remain in any `.main`, `.side`, `.pbody` or `.tabs` subtree.

### 3 — Medium · No light model

Every plane was a flat fill, so "graphite anodised" existed in the palette and nowhere in
the pixels. **Fixed:** the window catches light on its top edge and carries a radial
sheen; the sidebar sits below the surface with an inset shadow; the toolbar sits on it;
buttons, segmented controls, icon tiles and column headers each got their own inset/drop
pair. Rows gained a 1.4%-alpha zebra and a hover state, so the list reads as a surface with
texture rather than lines on a void.

### 4 — Medium · No typographic scale

Pane titles were 15px against 12.5px body — a 1.2 ratio doing no hierarchical work.
**Fixed:** titles to 19px/-0.35px tracking. The sidebar at-rest readout introduces a third
step at 27px.

---

## Layout integrity

### 5 — Medium · Column headers misaligned with their columns *(computable)*

`.cols` used `gap: 9px` while `.brk` rows used `gap: 13px`.

**Measured:** header lefts `[235,278,439,518,571,642,715]` against row lefts
`[235,282,447,530,587,662,739]` — drift of exactly 4px per column, 24px by `LAST USED`.

**Fixed:** `.cols.brk-cols{gap:13px}` and the spacer widened to match the new 38px housing.
**Verified:** drift is now `[0,0,0,0,0,0,0]`.

### 6 — Medium · 266px of sidebar void and 126px of unexplained list void

**Fixed:** the sidebar void now carries an at-rest readout — child processes running against
servers declared, plus the real last-60s trace as a sparkline. It states only numbers the
router actually observes; no invented memory saving, because the router never runs the
world where all eight are resident and so has nothing to subtract from. The list gained a
footer stating the denominator (`8 of 8 servers · 115 tools in every session's tool list`),
which closes the table's shape and surfaces a count the filter tabs otherwise hide.

### 7 — Medium · State contradiction: "warm · kept alive" with a dead LED

`obscura` was seeded `warm: true, st: 'idle'`, so it rendered its lever down and its pilot
lamp dark while its own subtitle said it was kept alive. A second instance: a warm server
that *was* running showed a reap countdown, which states the opposite of what the toggle
does.

**Fixed:** warm implies running, the reaper skips warm servers, and the subtitle branches on
warm before the running branch — `warm · never reaped`.

### 8 — Low · Uneven rows in the phone triage scan list

**Measured:** capability lines compute 20px on `warn` rows and 16px on `ok`/`bad` rows from
a single `height: 16px` rule. Three targeted fixes (drawn icon in place of the glyph, flex
in place of block, explicit height) did not move it.

**Not diagnosed.** Per the skill's own budget, an issue surviving three targeted fixes means
the diagnosis is wrong, so it is reported rather than chased. The user-visible symptom —
rows of different heights in a list whose whole job is scanning — is fixed by pinning the
row to a fixed 86px. **Verified:** all eight rows now measure 86px. The 4px remains an open
question in the stylesheet, noted in a comment at the rule.

### 9 — Low · Three ellipses in five phone rows

The `by` line carried author, licence *and* install count at 302px wide. **Fixed:** the
install count is dropped — it already lives in Discover — and the capability summaries were
shortened (`Reads your project · 1 host`, `Shell · network · whole repo`).

---

## Open questions (Tier 3 — no severity, no gate)

- The at-rest sparkline is honest but thin at 60 samples. Worth a longer window?
- The Mac list still ends in ~130px of empty space below the table footer. Real macOS list
  views do this; the alternative is a shorter window. Deliberate, flagged.
- The `.tfoot` denominator exists only on Servers. Skills and Discover would carry it well.

## Needs verification by a human

- **Whether the breaker reads as a breaker** to someone who has not been told it is one.
  I can measure that its three states are now distinguishable; I cannot measure whether the
  metaphor lands.
- **Motion.** obscura executes no CSS animations, so every spring, the lever snap, the
  600ms release, the badge bump and the commit-bar rise are **unverified**. They are
  specified in the file and have never been seen running.
- **Web fonts / real type rendering.** obscura loads no web fonts; the system stack is
  deliberate here, but its rendering on a real Mac is unconfirmed.
- **Contrast ratios.** Not run as a gate this pass — the palette changed under every fix,
  so any number taken mid-pass would be stale. This is the largest open gate.
- **Keyboard traversal and focus order** across the sidebar → table → inspector → sheet
  path. Not driven.

## Coverage

| Reviewed | 19 of 21 surfaces |
|---|---|
| Visually, at DPR 2 | shared chrome, Servers, Skills, Discover, Activity, Cleanup, Inspector, Popover, Sheets, phone chrome, phone Triage, phone Discover |
| Programmatically only (glyph, overflow, void sweep) | Inbox, Evals, Settings, phone Detail, Queue, Library, Settings+Pair |
| **Not reviewed** | `mac-surfaces.html`, `ios-surfaces.html` — superseded by the prototype |

Stages `states`, `flow` and `intent` were exercised on the twelve visually-reviewed
surfaces only. The seven programmatic-only surfaces have had their gates and systematisation
checked and their craft **not** looked at.

---

# Round 2 — the canon pass (design-craft · ux-craft · mac-design-studio)

Round 1 fixed what was visibly wrong. It could not fix what was *systematically* wrong,
because it ran without `mac-design-studio`'s bundled references — which is where the
Apple kit's specified values live. Every finding below is a measured divergence from
`native-foundation.md`, not a matter of taste.

## Why it read as a web app in dark mode

| | Before | After | Source |
|---|---|---|---|
| Distinct font sizes | **25** | **8**, all on the SF ramp | kit type ramp (specified) |
| Status + accent palette | GitHub Primer `#3FB950 / #E3A008 / #F85149 / #5B8DEF` | macOS 27 dark `#30D158 / #FF9230 / #FF4245 / #0091FF` | system hues (specified) |
| Text colour | four hand-picked opaque greys | `#FFF` @100/55/50/25% label tiers | label tiers (specified) |
| Tracked-uppercase header systems | **5** | **0** — sentence case | native grammar rule 2 |
| Sidebar width | 190px | 256pt | chrome anatomy (specified) |
| Toolbar / titlebar | undefined | 52pt / 33pt | chrome anatomy (specified) |
| Sidebar selection | radius 6, no inset | radius 8, 4px side insets | native grammar rule 1 |
| Icon tiles | `linear-gradient(140deg,#2E4A7A,#1E2E4A)` | 6 authored 512px icons + drawn monograms | design-craft §5 |

Round 1's own "fix" of pane titles to 19px and the readout to 27px made the type scale
*worse* — neither value is on the SF ramp. They are now 22 (Title1) and 26 (LargeTitle).

**Deliberate deviation:** tertiary text sits at 50% white, not the kit's 25%. On a
`#1E1E1E` ground the kit value measures 2.29:1, and Contrast Dilution is the direction's
named #1 defect. 25% is kept for genuinely disabled controls, where dimming *is* the
message.

**Contrast gate, now run** (it was the largest open gate after round 1): 60 text nodes
examined on Discover, 0 below 4.5:1. Three failures were found and fixed first, all of
them the 25% quaternary tier used as live text.

## The gradient tiles — the finding I should have caught first

`~/Dev/fledgeling-plugins/site/public/icons/` holds 23 authored 512px icons, and the
brief asked for them by name. The prototype shipped four gradient rectangles instead —
design-craft's "the gap wearing chrome", exactly.

Now: real art on every entry whose marketplace ships it, a drawn monogram plate where it
does not. fledgeling-plugins entries carry art and diolog/community entries carry a
monogram, which is true of the real catalogue, so the mock shows it rather than
flattening the difference.

## The breaker — the construction error behind three failed rounds

Rounds 1 and 2 both "fixed" the breaker's legibility and neither landed. The reason was
geometric, not stylistic: **the lit track was inset 11px per side (14px wide) behind a
lever inset 3px per side (30px wide)**, so the lever covered the track completely and the
glow only ever escaped at the top. Compounding it, the housing was darker than its row,
so the unit read as a hole rather than as a raised control — and at 30×40 the three
moulded ridges resolved as a `≡` list glyph.

Rebuilt as a raised metal plate lighter than its row, carrying a slot wider and taller
than its toggle, so slot shows above the toggle when down and below when up — in every
state, lit or not. That is what makes it read on the 6 dormant rows out of 8, which is
where it failed.

**Stopping here on this element.** Three targeted rounds is the budget; the metaphor's
legibility at row scale is now a question for a human, not another edit.

## Phone — two real bugs

- **Every checkbox rendered ticked.** The tick was hidden with `color:transparent` on a
  `currentColor` stroke, which obscura paints white regardless. A security-review screen
  that pre-selects everything is the worst available default. The tick is now rendered
  only when checked. Verified: `[false ×8]`.
- **Three capability lines truncating again.** The redundant chevron duplicated the row's
  own tap-to-expand and cost the 26px the line needed. Removed; strings shortened.
  Verified: 0 ellipsised nodes, rows uniform at 86px.
- `no eval` → `not evaluated` on both devices — one name per state.

## Still open

- **The direction is Terminal Dark under another name.** "Instrument Panel" is near-black
  ground + one accent + three status hues + mono metadata + compact rows, which is
  `design-directions.md` §6 exactly — and the catalogue flags Terminal Dark as one of the
  two looks a model defaults to on any brief. The subject genuinely earns it (a telemetry
  board for a dev tool is its stated best case), so the direction stands. What is missing
  is commitment rule 2: **subject-mining**. One generic electrical breaker is the only
  mined element; every other surface is a stock table. The noun has not become the mark
  and the job has not become a second purpose-built control.
- **No state matrix.** mac-essence conviction 4 — "states are where quality lives". Empty
  states exist on some surfaces; loading, partial, error and offline are specified
  nowhere with real copy.
- **Density is inconsistent.** 56px table rows against 120px featured cards holding three
  short lines. The cards are the emptiest thing on the busiest surface.
- **Motion is still unverified.** obscura executes no CSS animations.
- **Keyboard traversal still not driven**, and no focus ring is shown anywhere.
