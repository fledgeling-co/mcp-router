# DESIGN.md — MCP Router

The design authority for the Mac app, the iPhone companion, and anything else that
renders. Where this file and a general craft rule disagree, this file wins; where this
file and Apple's macOS 27 UI kit disagree, **the kit wins** — native correctness is never
traded for style.

The reference implementation is `design/mcp-router-console.html` — the design of record,
settled by the owner on 2026-08-22 and recorded in `ORCHESTRATOR.md`'s DESIGN OF RECORD
block. It is interactive and carries every Mac surface; it is not deep-linkable, so a
citation into it is a line number rather than a query string. §1 and §2 below were
re-authored *from* it under M21, which is why the precedence still runs this way: when
this document and the mock disagree, the mock is stale and this document is the spec.
`design/mocks/prototype.html` is the superseded prototype and is cited only where a
surface it drew has not yet been converted.

---

## 1 · Direction

**Patchbay** — a light-first precision routing console: a white ground with a graphite
chrome step above it, the system accent bound to selection and focus, three indicator hues
that only ever do their own job — each carrying a text-safe twin — and monospace reserved
for anything a user could paste into a terminal.

Runner-up was *Blueprint Graphite*, set aside for two reasons rather than one. The
direction it would have replaced was already dark graphite, so choosing it would have been
a refinement wearing a decision's clothes; and the densest reading surfaces here are a
servers table, an activity log and a schema diff, which are easier on a light ground
(`PRD.md` §9.1).

**Named risk:** a routing metaphor drawn literally inside a native app, and a light-first
default in a category whose users mostly run dark. The second is bounded rather than
argued away — dark is authored to the same standard, not derived, and every value in this
section is stated for both.

**Signature element:** the **Signal Path** on Servers — a lane of jacks, one per declared
server, showing what is plugged into the router right now. It is a literal rendering of
the mechanism the product exists for, and it is the only loud thing in the app. Everything
else stays quiet so it can be. `--jack-off`, `--jack-ring` and the `Jack lane` metric are
its values and are authored in §2, and its construction is `### Signal Path geometry`
below. **M16 draws it**, and retired the breaker column it replaces in the same change.

**The known weakness, stated rather than hidden:** the previous direction's weakness was
that Terminal Dark is one of the two looks a model defaults to on any brief. This one
trades that for the opposite risk — a light, quiet, system-native console is the *other*
default — and answers it the same way, by subject-mining. The Signal Path is the mined
element; a board whose other surfaces are stock tables has one signature and eight
defaults. See §10.

---

## 2 · Tokens

Every value below is either an Apple `(specified)` kit value or a stated deviation from
one. Nothing here was picked by eye.

**Four appearance contexts, all four authored.** Light, dark, and each of those again under
increased contrast. Light is the primary one — this is a light-first direction, so dark is the
authored counterpart rather than the source. What light and dark reproduce in each other is not an
alpha but a *job*: the label tiers are solid hexes in both, because a tier that composites over
whatever surface it lands on has a different contrast on each of the seven grounds here. Lines,
fills, the scrim and the two washes stay `rgba`, because a hairline genuinely is a modification of
the ground beneath it. **Increased contrast is authored per appearance**, not once for both: `--t2`
has to go darker in light and lighter in dark, so a single scheme-agnostic override paints
low-contrast ink in whichever appearance it was not written for — the opposite of what was asked
for, in the mode it was asked for.

**The Role column is a contract, not a label.** It names the one job a token does, and therefore
which pair its contrast is measured as. `ContrastFloorTests` reads
`ColorToken.contrastRole` and measures the pairing the role implies — `text` against all four
grounds at 4.5:1, `fill` under `--on-accent` at 4.5:1, `nonText` at 3:1 (WCAG 1.4.11) — and
`DesignTokenParityTests` holds the column and the code to the same value. Three roles have no
floor and say why in their own words rather than being skipped: `disabled` is exempt under WCAG
1.4.3, `pairedWithAWord` is exempt under 1.4.11 because §6 requires a word beside every state that
has a colour, and `hairline` has no floor a 6%-alpha fill could meaningfully clear. A skipped check
and a passed check are the same shade of green.

**The two Contrast columns are one fixed measurement**, computed with the same WCAG 2.x
arithmetic the code uses and checked from this document by
`LightAppearanceTests`: each token composited over `--ground` in that appearance, except
`--on-accent`, which is measured over `--accent`. They are *not* the role's own floor — a `fill`
measured against the ground is a number about a pairing nothing draws. Read the column for drift
and the role for whether the value is doing its job.

### Grounds and lines

| Token | Role | Dark | Light | Contrast (dark) | Contrast (light) | Use |
|---|---|---|---|---|---|---|
| `--desktop` | ground | `#2A3140` | `#8A9BB4` | 1.31:1 | 2.83:1 | what the window sits on — a screenshot backdrop, never a surface the app draws into |
| `--ground` | ground | `#1C1C1E` | `#FFF` | — | — | window background (kit: dark window / light window) |
| `--chrome` | ground | `#262629` | `#F1F1F4` | 1.13:1 | 1.13:1 | titlebar and toolbar — one tonal step off the ground, in both appearances |
| `--menubar` | ground | `#1F1F22` | `#F6F6F8` | 1.03:1 | 1.08:1 | the menu bar and the popover hanging off it |
| `--panel` | ground | `#232326` | `#F7F7F9` | 1.09:1 | 1.07:1 | sidebars and inspectors |
| `--raised` | ground | `#2C2C2E` | `#FFF` | 1.22:1 | 1.00:1 | resting control surfaces |
| `--raised2` | ground | `#3A3A3C` | `#E8E8EC` | 1.50:1 | 1.22:1 | hovered / emphasized control surfaces |
| `--sunken` | ground | `#161618` | `#EDEDF0` | 1.06:1 | 1.17:1 | a well a control sits *in* — a track, a search field |
| `--scrim` | chrome | `#000` @52% | `#000` @28% | 1.14:1 | 1.99:1 | behind a modal sheet |
| `--line` | hairline | `#FFF` @9% | `#000` @10% | 1.30:1 | 1.25:1 | hairline dividers |
| `--line-strong` | hairline | `#FFF` @16% | `#000` @18% | 1.65:1 | 1.53:1 | control bezels |
| `--f1` | hairline | `#FFF` @10% | `#000` @6% | 1.34:1 | 1.14:1 | fills — bezels |
| `--f2` | hairline | `#FFF` @7% | `#000` @4% | 1.22:1 | 1.09:1 | fills — tracks |
| `--f3` | hairline | `#FFF` @5% | `#000` @3% | 1.15:1 | 1.07:1 | fills — inactive |
| `--jack-off` | chrome | `#3C3C40` | `#D6D6DC` | 1.55:1 | 1.45:1 | a Signal Path jack with nothing plugged into it (M16) |
| `--jack-ring` | hairline | `#FFF` @16% | `#000` @14% | 1.65:1 | 1.38:1 | the ring around a jack |
| `--tl-close` | chrome | `#FF5F57` | `#FF5F57` | 5.69:1 | 2.99:1 | the window close button, at the system hue |
| `--tl-min` | chrome | `#FEBC2E` | `#FEBC2E` | 10.08:1 | 1.69:1 | the window minimise button, at the system hue |
| `--tl-zoom` | chrome | `#28C840` | `#28C840` | 7.64:1 | 2.23:1 | the window zoom button, at the system hue |
| `--tl-off` | chrome | `#3A3A3C` | `#D2D2D6` | 1.50:1 | 1.51:1 | all three of the above when the window is not key |
| `--focus` | nonText | `#0091FF` | `#0088FF` | 5.26:1 | 3.52:1 | the focus ring (§8) |
| `--focus-halo` | hairline | `#0091FF` @42% | `#0088FF` @35% | 1.93:1 | 1.54:1 | the ring's outer glow |
| `--accent-wash` | hairline | `#0071E3` @10% | `#0071E3` @10% | 1.09:1 | 1.15:1 | an accent tint behind a mark — never behind text |
| `--accent-wash-line` | hairline | `#0071E3` @22% | `#0071E3` @22% | 1.24:1 | 1.36:1 | the wash's own edge |

Dark is authored, never inverted. Chrome is graphite, never pure black — and its light counterpart
is a light grey, never pure white. `--desktop` is the only value here the app never paints: it is
what the window is photographed against, and it is in the palette so a screenshot cannot invent one.

**The one reversal in the system:** `--raised2` is *lighter* than `--raised` in dark and *darker*
in light. Emphasis always moves away from the ground; in light the resting surface is already
white, so darker is the only direction left. Everything else steps the same way in both
appearances.

**Five tokens are the same value in both appearances, and that is authored rather than skipped.**
The three traffic lights are the system's own hues and do not change with appearance on the
platform itself; the two accent washes are a 10% and 22% tint of `--accent-ink`, and a tint is
defined by what it modifies, so the ground underneath does the appearance-switching for it.
`LightAppearanceTests` exempts exactly these five, by name and with this reason, rather than
relaxing the rule.

### Label tiers

| Token | Role | Dark | Light | Contrast (dark) | Contrast (light) | Use |
|---|---|---|---|---|---|---|
| `--t1` | text | `#FFF` | `#17171A` | 17.01:1 | 17.89:1 | primary text |
| `--t2` | text | `#B8B8C0` | `#55555C` | 8.63:1 | 7.39:1 | secondary text, metadata |
| `--t3` | text | `#98989F` | `#63636B` | 5.94:1 | 5.95:1 | section headers, column headers, tertiary |
| `--t4` | disabled | `#6E6E76` | `#9A9AA2` | 3.37:1 | 2.79:1 | **disabled controls only — never live text** |

**Deviation, deliberate:** the kit's tertiary tier dims far enough to land near 2.3:1 on a graphite
ground, and Contrast Dilution is this direction's named #1 defect. `--t3` is therefore held at
5.94:1 dark and 5.95:1 light — a tier below `--t2` in weight, not in readability. `--t4` is the
only tier under the floor in either appearance, and it is the only one whose entire job is to say
*this control is unavailable*: it is claimed as exempt under WCAG 1.4.3 by the `disabled` role
rather than by a check that quietly skips it.

**The tiers are solid, and they used to be an alpha.** The previous direction wrote them as white
or black over the ground at 25–100%, which reads correctly on one surface and drifts on the other
six. A solid hex measures the same on `--panel`, `--raised` and `--chrome` as it does on
`--ground`, which is what makes the four-ground floor check in `ContrastFloorTests` meaningful
rather than a measurement of the ground.

### Colour

| Token | Role | Dark | Light | Contrast (dark) | Contrast (light) | Meaning — exclusive |
|---|---|---|---|---|---|---|
| `--accent` | nonText | `#0091FF` | `#0088FF` | 5.26:1 | 3.52:1 | selection, focus, the one primary action — as a ring, plug, dot or tint, never as text |
| `--live` | pairedWithAWord | `#30D158` | `#34C759` | 8.42:1 | 2.22:1 | a child process is running |
| `--attn` | pairedWithAWord | `#FF9230` | `#FF8D28` | 7.62:1 | 2.31:1 | wants a human decision |
| `--fail` | pairedWithAWord | `#FF4245` | `#FF383C` | 4.96:1 | 3.57:1 | failed or tripped |
| `--accent-ink` | fill | `#0A6FD6` | `#0071E3` | 3.45:1 | 4.70:1 | the accent as a **fill** carrying `--on-accent`. Never text — see the note below |
| `--accent-text` | text | `#6FB6FF` | `#0060C4` | 7.95:1 | 6.05:1 | the accent as **text** on a ground |
| `--live-ink` | text | `#30D158` | `#14682F` | 8.42:1 | 6.88:1 | a child process is running, as text |
| `--attn-ink` | text | `#FF9230` | `#8A5000` | 7.62:1 | 6.51:1 | wants a human decision, as text |
| `--fail-ink` | text | `#FF5A5D` | `#C8102E` | 5.57:1 | 5.88:1 | failed or tripped, as text |
| `--shield-good` | fill | `#1B7A38` | `#14682F` | 3.15:1 | 6.88:1 | the filled badge on a verified publisher, carrying `--on-accent` |
| `--badge-bg` | fill | `#B85400` | `#B34700` | 3.49:1 | 5.50:1 | the filled count badge, carrying `--on-accent` |
| `--on-accent` | fillLabel | `#FFF` | `#FFF` | 3.23:1 | 3.52:1 | the label drawn on an accent fill |

All four indicator hues are macOS 27 system hues, at the platform's own published values in both
appearances — this direction does not re-solve them, it adds a text-safe twin instead. **Nothing
else in the app may be any of these colours**, twins included: that exclusivity is what makes one
amber dot in a menu bar mean something. `ColorToken.isReservedMeaning` covers all eleven, because
an ink is the same exclusive meaning at a different lightness, and leaving the twins unreserved
would open a hole in the rule exactly the size of the new tokens. Per-item identity colour, if ever
needed, comes from the remaining system hues and is never the accent.

`--attn` is additionally pulled toward yellow. Solved on hue alone it lands close to `--fail` at
near-identical lightness, which is exactly where protan and deuteran vision compresses — and those
two tokens mean "wants a decision" and "failed". Colour is never the only signal carrying either.

**Why there are three accent tokens and not two.** `--accent` is the published system blue and
measures 3.52:1 on the light ground: correct as a ring, a plug or a selection tint, and a known
failure under a 13pt label. `--accent-ink` is the fill that carries `--on-accent`. `--accent-text`
is the accent *as text*, and it exists because `--accent-ink` used as text measures 4.17:1 on
`--chrome` and 4.39:1 on `--panel` — collapsing the two would ship the failure the split exists to
prevent, one ground over.

**The suffix `-ink` means two opposite things, and the Role column is the answer.** On
`--live-ink`, `--attn-ink` and `--fail-ink` it means *text*; on `--accent-ink` it means *fill*.
The spelling is the design of record's and this document does not rename it — a Swift-only rename
would put the two palettes back behind a translation table, which is the thing this item removed.
What closes the trap instead is that `--accent-ink` declares the role `fill`, and a call site that
reaches for it as text is measuring the wrong pair against a floor that will not hold.

**Deviation, deliberate, and against us — now in both appearances.** `--on-accent` on `--accent`
measures **3.23:1 in dark** and **3.52:1 in light**, under the 4.5:1 a 13pt semibold label wants.
The light figure is new and is a consequence of taking the platform's published blue rather than a
darkened one. Every native filled accent control on macOS carries a white label, and this
document's own precedence says the kit wins where it and this document disagree — so white stands,
recorded with its measurement rather than hidden.

**The resolution exists and is not yet applied.** On `--accent-ink`, the fill the design of record
actually puts under a white label, `--on-accent` measures **4.70:1 light** and **4.93:1 dark**. M21
authored that token and moved no call site; choosing which surfaces take it is M16–M22's work, per
surface. Until then the pairing above is what ships, and
`LightAppearanceTests.darkOnAccentDeviationIsPinned` measures it every run rather than letting it
drift further. Exposure is bounded by §3 rule 4 — one prominent accent-filled action per view — and
that control is distinguished by shape and position too, never by colour alone.

### Increased contrast

The nine tokens the system's increased-contrast setting re-solves, and the only nine. Every other
token takes its base value in that context, from an explicit arm rather than by inheriting, so
nothing is resolved by a rule nobody watches.
`DesignTokenParityTests.contrastOverlayNameSetsMatchExactly` holds this table's row set and the set
of `ColorToken` cases whose contrast value differs from their base to be the same set, in both
directions: a token that starts overriding without a row here is red, and a row here that overrides
nothing is red too.

An overlay table rather than two more columns on the three tables above, because 31 of 40 rows
would repeat their base value twice — and a repeated cell is a cell that drifts. As an overlay,
*which* tokens override is itself the assertion.

| Token | Dark | Light | Why this one re-solves |
|---|---|---|---|
| `--t2` | `#F2F2F5` | `#2A2A30` | the two middle tiers collapse onto one value: tier separation is the gradation the request is asking to stop paying for |
| `--t3` | `#F2F2F5` | `#2A2A30` | the same value as `--t2`, deliberately — hierarchy still reads from weight and position |
| `--line` | `#FFF` @30% | `#000` @30% | a white-on-graphite hairline cannot raise contrast by changing hue, only by covering more ground |
| `--line-strong` | `#FFF` @48% | `#000` @46% | the same, one step firmer, so a bezel stays distinguishable from a divider |
| `--accent-text` | `#9CCDFF` | `#004E9E` | 8.13:1 light and 10.20:1 dark on `--ground`, against 6.05 and 7.95 at the base value |
| `--live-ink` | `#6BE38B` | `#0F4F24` | 9.70:1 light and 10.52:1 dark on `--ground` |
| `--attn-ink` | `#FFB566` | `#6B3E00` | 9.07:1 light and 9.77:1 dark on `--ground` |
| `--fail-ink` | `#FF8A8C` | `#9E0C24` | 8.29:1 light and 7.51:1 dark on `--ground` |
| `--shield-good` | `#166B31` | `#0E4F23` | a fill, so it darkens rather than lightens: 9.72:1 light and 6.60:1 dark under `--on-accent` |

**What is specified here and not measured.** No engine available to this project applies
`prefers-contrast`, so these two contexts have never been rendered. Every ratio above is computed
from the values by the same arithmetic the app uses, and the values are the design of record's own
— but nothing has photographed them. That is stated rather than waived: an increased-contrast
screenshot is a real gap, and it needs a real browser or a built app.

### Type — SF Pro, `-apple-system` stack, never bundled

| Role | Size | Line height | Emphasis |
|---|---|---|---|
| LargeTitle | 26 | 32 | Bold |
| Title1 | 22 | 26 | Bold |
| Title2 | 17 | 22 | Bold |
| Title3 | 15 | 20 | Semibold |
| **Body** | **13** | **16** | Semibold |
| Callout | 12 | 15 | Semibold |
| Subheadline | 11 | 14 | Semibold |
| Caption | 10 | 13 | Semibold |

Eight sizes, nothing off this ladder. 13pt body is the loudest native-vs-web
discriminator; a 16px body means it is not a Mac app. Emphasis is Semibold, not Bold.

**Monospace (`SF Mono`) is for instrument data only** — numerals, counts, durations,
error codes, status subtitles. It is the instrument voice and loses its meaning if it
leaks into prose.

### Chrome geometry `(specified)`

| Element | Value |
|---|---|
| Grid unit | 8pt |
| Titlebar | 33pt |
| Unified toolbar | 52pt (8 + 36 XL controls + 8) |
| Compact toolbar | 40pt (4 + 32 regular controls + 4) |
| Sidebar | 256pt; rows 24/32/40 |
| Sidebar row medium | 32pt |
| Sidebar row large | 40pt |
| Control mini | 16pt |
| Control small | 20pt |
| Control regular | 24pt |
| Control large | 28pt |
| Control extra large | 36pt |
| Sidebar selection radius | 8pt |
| Sidebar selection inset | 4pt |
| Focus ring | 2pt |
| Popover radius | 20pt · concentric children |
| Card radius | 10pt |
| Table rows | 24–28pt for dense lists |
| Servers row | 56pt |
| Jack lane | 44pt |
| Scrollbar | 12pt |

Selection is an inset rounded fill at the radius and side inset above. The control ladder
and the selection fill used to be written as prose in one cell each — unreadable to the
parity check, and therefore free to drift. They are individual rows now because the design
system builds controls from them. The Servers board's 56pt row is a row of its own for the
same reason: the loading skeleton has to match the populated row's height exactly or the
board jumps when data lands, and a height buried in another cell's prose cannot be checked.

**That cell used to read `56pt (4 + 48 breaker housing + 4)`.** The derivation retired with the
lever under M16 and the value did not move, because the table's own conversion is another item's
and a row height changed here would move the skeleton, the column headers and the inspector's
neighbour in a diff nobody asked for. What sets it now is the two-line name block the row draws.
The console mock's own table row is 36pt; §10 records that as owed.

**`Card radius` used to live inside the popover cell**, written as `card radius 10–14` beside the
popover's own number. That is the same defect one size down — a value in a cell no parser reads,
next to a value one does — so it is a row now and the popover cell states only its own radius.

**Two of these rows are authored ahead of the surfaces that draw them.** `Jack lane` is the Signal
Path's (M16) and `Scrollbar` is the shared one; `no-raw-design-values.sh` forbids a geometry
literal anywhere under `Boards/`, so a board arriving before its token would have to bring the
token with it — which would put a design decision in a board's diff.

Concentric corners throughout: child radius = parent radius − padding. Everything above is a
multiple of the grid unit or a documented exception to it.

### The sidebar foot `(specified)`

The last two elements in the sidebar, below the destinations, on **every** board — they belong to
the shared wrapper rather than to a surface. Written out because the build had lost one of them
entirely and half of the other, and neither absence was visible to any check.

| Element | What it draws |
|---|---|
| The readout card | A plate — `--f3` fill, `--line` hairline — holding the label `Child processes`, the counts `n of m`, the 60-second trace and its footer. Its margin is the same on **all four** edges; there is no divider above it, because a rule above a bordered plate is two separations doing one job — which means nothing but that margin holds it off the last destination row |
| The foot line | The loopback address the app is talking to — `127.0.0.1:<port>` — in monospace at `--t3`, over a divider |

Its geometry is **derived from the table above rather than added to it**, the way the boards'
metrics are: the card's margin is twice the selection inset, its padding is the selection radius,
its radius is the selection radius plus half the inset — landing on this document's own card radius
of 10 — and the foot line is one dense row plus that inset above and below. The chrome-geometry
table is the token table, and a value composed from tokens does not earn a token of its own.

**The port is the observed one, never a constant.** Both this line and Settings' `Endpoint` row
compose from `LoopbackAddress`, which takes the port the router answered on. The prototype *drew*
the literal `127.0.0.1:8879` while the fixture router answered on 8971 — the honesty rule broken
outward, since a user who moved the port would be told to reach for the wrong one. It was amended
on this branch and now draws `127.0.0.1:${S.port}` from a `port` value, with the annotation saying
why; this paragraph is the record of what it used to say, not a live description of it.

**The foot says where the app is pointed. It does not say how the router is.** The prototype paints
a `--live` dot on this line and the shipped build does not, deliberately. `--live` means *a child
process is running* and it is already spent, correctly, on the count in the card directly above; a
green dot beside a card reading `0 of 4` paints that meaning where nothing is running, which is the
decorative use §2 forbids.

That argument convicted the numeral too, and it took three out-of-family reviews to notice: the
count itself was painted `--live` unconditionally, so `0 of 4` was already the green mark this
paragraph refuses. **The count spends `--live` only above zero** and falls to `--t1` at zero, where
nothing is running but the reading is still the loudest thing the card has to say. The trace keeps
`--live` at every value: its stroke identifies which quantity is plotted, and a flat line at zero
is a reading of the count rather than a claim that something is up. A dot in a neutral tier was the remaining option and it fails §6 instead:
a signal meaning "answering" needs a word for that state, `ControlAPIError` already owns that word,
and "not answering" would be false for `.unauthorized`, where the router answers 401 and the poll
still fails. The router's condition is the card's job.

**The card announces as one element, not two.** The label and the reading it heads are one stop for
a screen reader — `Child processes, 3 of 8 declared servers running` — for the reason A35 already
matches the destination rows as a prefix rather than whole: a row carrying a value announces as one
sentence, and splitting it costs a reader a swipe to reach a label that carries no value on its own.
This is written down because the build has now held all three available forms and two of them were
green on some gate: the shipped defect discarded the label from the accessibility plane entirely,
and the fix for that briefly published two stops because A35's readout line — anchored whole, in the
era when this row had no label to combine with — rejected the combined form. The gate recorded the
absence rather than a decision, and was widened to its own stated tolerance rather than obeyed.

Its states, since a foot with one state is the same third of a design as a board with one:

| Condition | The foot |
|---|---|
| No poll has answered yet | A skeleton at the line's own height, so nothing moves when the first poll lands |
| The last poll answered | The address |
| The last poll failed, an earlier one answered | The address, unchanged — a refresh that did not complete is not evidence the router moved |
| Nothing has ever answered | Nothing, and no divider either. The card above is already carrying this state in `ControlAPIError`'s own words |

The skeleton's job is the **loading → answered** transition, where the foot is the same height
either way and nothing moves. Loading → *never answered* does move, and that is accepted rather
than overlooked: the card above changes height on that same transition by design — the failure form
carries wrapped prose and is allowed to be taller than the counts form — so the whole foot region is
re-laid out for a different state, and reserving a wordless band under a rule would be dead chrome
in the one state that already has the most to say.

**Still owed here, recorded rather than fixed:** the prototype draws the count as a 26px display
numeral over `of N declared`, and the build draws a label-left / value-right row. That is a third
divergence in the same element; it is a type and density decision rather than a missing element, so
it converts under `M23`'s mock-to-SwiftUI contract with the rest of the board, not in passing.

### Signal Path geometry `(specified)`

The signature element's construction, recorded value by value. It is here rather than in prose
for the reason the outgoing signature's table gave: a dimension no check can read is a dimension
free to drift back, and this element's two hardest numbers were **measured** rather than picked —
a single-column field ran the band 500pt deep at eleven upstreams and pushed the table off the
board, and a label column too narrow for `3:41 left` clips the only part of the label that was
carrying information.

| Element | Value |
|---|---|
| Signal Path padding | 12pt |
| Jack minimum width | 132pt |
| Jack inset | 10pt |
| Jack gap | 9pt |
| Jack plug diameter | 16pt |
| Jack plug ring | 3pt |
| Row plug diameter | 8pt |
| Hub width | 76pt |
| Flow arrow width | 20pt |
| Plug transition | 0.2s |

The lane a jack sits on is **not** a row here. It is `Jack lane` in the chrome table above,
because it is the one dimension of this element the mock publishes in its own metrics block, and
a value stated twice is the defect `Card radius` was split out to end.

The jack field is a grid of tracks that packs to the width available — `repeat(auto-fill,
minmax(132px, 1fr))` in the mock, `GridItem(.adaptive(minimum:))` in SwiftUI — never a fixed
column count. **The invariants that make it read as a patchbay:** the plug plus both sides of its
ring fits inside the lane, so nothing clips against the track above; the label column is the
larger half of the jack, so the condition is legible rather than truncated; and the ring is
thinner than the plug's own radius, so it reads as a halo rather than as a second plug.

`Plug transition` is a duration and a curve rather than a spring, and it is the one place in this
document that is. §7 says why.

---

## 3 · The native floor

These are not stylistic preferences. Each is a rule from the macOS 27 kit, and a
violation is a defect rather than a variation.

1. Selection is a flat inset rounded fill with accent text — never a full-bleed bar.
2. Sidebar and section headers are **sentence case**, system font, secondary colour.
   Tracked uppercase is the loudest web tell; do not fix its tracking, remove it.
3. Liquid Glass on floating chrome only — menu bar popover, sheets, menus. Content is
   opaque. No glass on glass. A flat opaque window is legitimately native.
4. One prominent accent-filled action per view, trailing. Cancel leads. Destructive is
   never the default. `…` means "opens a further view"; its absence means "commits now".
   Disabled dims in place and never disappears.
5. Density: 13pt body, 24pt controls. Hierarchy comes from label tiers and weight, never
   from size inflation.
6. Pop-up buttons (double chevron, show a value) are not pull-downs (single chevron,
   static title). Checkbox = independent setting; radio = exclusive set; switch =
   emphasized group toggle. Segmented controls switch views in place and are never
   primary navigation.
7. Toolbar: borderless monochrome SF Symbols, at most three groups, one trailing primary.
   The window title says what you are looking at, not the app's name.
8. Arrow cursor everywhere in app chrome. The pointer hand is a web-content signal.
9. The menu bar is the complete command surface — every command reachable from it.
10. Motion animates transform and opacity only, honours Reduce Motion.

**What "dims in place" means for an accent-filled control.** Rule 4 requires a disabled state of
every control and says it dims in place; §5 requires the same of every surface. Neither says what
dimming *is* for the one control whose resting state is an accent fill, and until M31 the design of
record could not draw it — `.btn:disabled` and `.btn.primary` sat at equal specificity with
`.primary` declared second, so a disabled primary kept its fill, its border and its label and
differed from a live one only by losing its shadow. A state drawn as though it were its own
opposite is worse than a state left undrawn. It is this:

| | Live | Disabled |
|---|---|---|
| Label | `--on-accent` | `--t4` |
| Fill | `--accent-ink` | `--f3` |
| Bezel | none — the live prominent control is a flat fill | `--line` |

The control keeps its height, its padding, its position and its label; nothing moves and the accent
leaves. **The accent fill is not tinted.** §2 publishes no ratio for `--t4` on `--accent-ink`, and
inventing one to license a tint would be a fabricated number in a palette's clothes; measured
below, the pairing turns out to be unreadable rather than merely unpublished. So a
disabled prominent control lands on the same disabled surface as every other disabled control —
which is also what makes it read as *unavailable* rather than as *a second kind of available*.

**The ratio, stated rather than implied.** `--t4` on `--f3` measures **2.94:1 in dark and 2.62:1 in
light** — below the 4.5:1 body floor and below 3:1. That is claimed as exempt under **WCAG 1.4.3**,
which excepts "text or images of text that are part of an inactive user interface component", and
the claim is made here by name rather than by a check that quietly skips the pairing: §2's Role
column gives `--t4` the `disabled` role, `ContrastRole.disabled` carries `floor == nil`, and this
paragraph is the pairing that role is claimed for. These two figures are *not* §2's Contrast
columns, which measure `--t4` over `--ground` at 3.37:1 / 2.79:1; a disabled label is never drawn on
a bare ground, so the column is a number about a pairing nothing paints.

**Every control that resolves an accent fill, not only the button.** The table above is written
for the prominent button because that is the control M31 was filed for, but the cascade accident it
describes belongs to the fill rather than to the button. The design of record paints `--accent-ink`
on five controls, and when M31 was filed four of them lost the same argument. `.tb-btn.on` and
`.segmented .seg[aria-pressed="true"]` kept the fill outright. `.trow[aria-selected="true"]` was
worse: its disabled rule won the label and not the fill, so a disabled selected row drew a dimmed
label on a live accent. `.switch` carried a correct dimming rule spelled `:disabled` while the one
disabled switch in the page spells the state `class="switch disabled"`, so the rule never applied
to it and the control drew at full accent with nothing marking it unavailable. All five now take
the row above: `--t4` on `--f3`, with a `--line` bezel on the controls that carry one.

**What the refusal above costs, stated as a number.** Declining to tint the accent is only a
position until the alternative is measured, so: `--t4` on `--accent-ink` is **1.68:1 in light and
1.02:1 in dark**, computed from the same tokens and the same float compositing that reproduce §2's
published columns. In dark that is a label the same luminance as the fill behind it. A rule that
dims a label and leaves the accent under it does not produce a dimmer control, it produces an
invisible one, which is why the fill and the label move together or not at all.

**A switch dims its track and its knob, and keeps the knob where it is.** A switch has no label, so
the mapping is one step removed: the track is the fill and the knob is the foreground, which puts a
disabled switch on `--t4` over `--f3` like everything else. The knob keeps its travel, so on and
off stay distinguishable while the control is unavailable — the state is carried by position rather
than by the accent, and dropping the accent therefore costs no information.

**A disabled control changes no cursor.** Rule 8 governs and admits no exception here: macOS paints
the arrow over an unavailable control, `not-allowed` is a web-content cursor with no counterpart in
the palette and no SF Symbol to map to, and a `cursor` property appears nowhere else in the design
of record. Unavailability is carried by the dimming and by §5's discoverable reason.

---

## 4 · Icons

**Drawn, never unicode.** A 16px SVG sprite at one 1.4 stroke weight on one grid, using
`currentColor`. On the Swift side this maps to SF Symbols at matched weights; where no
symbol fits, an authored asset in the catalogue.

**Marketplace artwork is authored, never generated chrome.** Entries whose marketplace
ships icons carry the real 512px art; entries whose marketplace does not carry a drawn
monogram plate. A gradient rectangle standing where an authored asset belongs is the
loudest low-fidelity tell available and is not permitted anywhere in this app.

Row tiles are 30pt (radius 7), card tiles 46pt (radius 11), detail 64pt (radius 14).

---

## 5 · The states are the design

Every data surface ships nine states, not one. A populated-only screen is a third of a
design, and shipping only the populated state is the most reliable failure in
AI-generated UI.

| State | Rule |
|---|---|
| Default | the ideal, populated case |
| Empty | first-run gets an illustration, one sentence, one action — never a bare "No items" |
| Loading | skeleton matching the real row geometry; never a spinner over a blank pane |
| Partial | say what arrived and what did not, with the reason |
| Error | what happened + how to fix, adjacent to the thing, non-blaming, never emoting |
| Success | in-place state change; macOS does not toast a click |
| Offline | the router is loopback, so this means *the router is not running* — say so and offer to start it |
| Disabled | dims in place with a discoverable reason |
| Overflow | long names truncate with the full value in the inspector; rows never change height |

Every control additionally carries default / hover / focus-visible / active / disabled.

Each spec written against this document must include its own state matrix with **real
copy for the unhappy paths**. Placeholder copy hides both layout and comprehension
failures.

---

## 6 · Words

- Sentence case everywhere — headers, labels, buttons.
- **The menu bar is the one exception, and it is this document's own precedence rule rather than
  a carve-out.** Apple's HIG specifies title-style capitalization for menu titles and menu items,
  the header above says the kit wins where it and this file disagree, and macOS contributes
  fourteen of the menu bar's items itself under strings the app cannot rename — `Hide Others`,
  `Select All`, `Bring All to Front`. Until M20 the app's own thirteen were sentence case, so the
  bar carried `Hide Others` directly above `Add server…`: the rule was already broken, in the
  worse direction, by half of one surface. Menu items are Title Case; every other surface,
  including buttons that say the same words as a menu item, stays sentence case. Where a string
  was shared between the two — `Add marketplace…` was one literal on a menu item and two Skills
  buttons — the menu takes its own.
- Buttons are verb-first and name the action. "Send 2 to Mac", never "Submit" or "OK".
- One name per state across both devices, taken from one source rather than spelled twice. The
  worked example is the router being unreachable: `ControlAPIError.routerNotRunning` carries the
  wording, the Mac's popover quotes it verbatim, and the phone's Discover and Triage render the
  same state rather than inventing a second phrasing for it.
  **The example this rule used to carry named a state the product cannot be in.** It read *"a
  skill with no evaluation reads 'not evaluated' on the Mac and on the phone"* — but there is no
  eval runner in this product in any form: no eval endpoint on the control API, no eval field on
  any wire type, and every board that could have drawn one dropped the column as fabricated
  (Servers, Skills, Discover, Inbox). So the clause mandated a reading that the last bullet of
  this same section forbids, and a runner implementing it faithfully would have shipped an
  invented state. The rule is right and only its illustration was dead.
- Errors state what happened and how to fix it, next to the thing that failed.
- Helper text is one quiet secondary sentence under its control.
- Numbers the router does not observe are never displayed. There is no fabricated memory
  saving anywhere in this app, because the router never runs the world where every server
  is resident and so has nothing to subtract from.

---

## 7 · Motion

Springs where this document authors the motion; a duration and a curve where the design of
record does, which is the Signal Path and nothing else so far. Interruptible either way.
Transform and opacity only.

**The distinction is provenance rather than taste.** A spring is what you reach for when you are
deciding how a thing should feel; `design/mcp-router-console.html` had already decided this one
and states it as `200ms cubic-bezier(0.2,0,0,1)`, so restating it as a spring here would be
re-authoring a value the design of record already carries. The two breaker rows this table used to
open with were the app's own, and they retired with the element under M16.

| Moment | Feel |
|---|---|
| Plug lighting or going dark | ease-out, 0.2s, on the fill and the ring — the call has already happened. `### Signal Path geometry` carries the number |
| Sheet / popover entry | materialize from its anchor, never a centre fade |
| Row selection | immediate; no transition on the selection fill |
| Badge count change | a small scale bump, never a colour flash — the plug's timing, because a badge ticking up and a plug lighting are the same event |
| Commit bar entry | rise on transform only |

`prefers-reduced-motion`, `prefers-reduced-transparency` and `prefers-contrast` are
honoured; on the Swift side these are `accessibilityReduceMotion`,
`accessibilityReduceTransparency` and `accessibilityDifferentiateWithoutColor`.

**Never animate opacity from 0 on entry.** Beyond the accessibility argument, content is
unreadable for half of a fade, and a slide reads better regardless.

---

## 8 · The keyboard

Named in every spec, not discovered later.

| Key | Behaviour |
|---|---|
| `⌘N` | Add server… |
| `⌘F` | Focus search |
| `⌘R` | Reset the selected server |
| `⌘⌫` | Remove the selected server (undoable, never confirmed) |
| `⌘,` | Settings |
| `⌃W` | Wake the selected server — keep it resident rather than reaping it when idle |
| `⌘1` | Discover |
| `⌘2` | Skills |
| `⌘3` | Servers |
| `⌘4` | Activity |
| `⌘6` | Checks |
| `⌘7` | Cleanup |
| `⌘8` | Inbox |
| `Return` | commits the view's one default action |
| `Esc` | dismisses the sheet, then clears selection |
| `Space` | toggles the selected row's **Keep warm** |

Focus rings are visible, accent-bound, 2px. Tab order runs sidebar → table → inspector.

**The board digits are in this table for the first time at M20, and two of the nine are missing
on purpose.** They were the one part of the accelerator map that lived only in a `switch`, so
`MenuCommandTests`' both-ways check against this section covered every chord in the app except
the seven a user presses most. `⌘5` and `⌘9` belong to Harnesses and Insights, which M22 ships;
they are absent here rather than reassigned, because a row for a board that does not exist is a
binding this document states and the app cannot honour — and packing the other seven into
`⌘1`–`⌘7` would move every digit on the day M22 lands. The order is the design of record's, set
at `6c513b0`; `PRD.md` §9.4 still lists the older one and is stale against its own mock.

**A chord is granted here only if the command can fire in some context and macOS has not already
claimed the combination.** Two limbs, because one is not enough: the first is about the command and
the second is about the key, and the eight chords the Router and Library menus do not take are
refused by one limb or the other.

Every refusal is stated in this prose and **none of them is a row in the table above**, which is
deliberate and was measured rather than assumed: `MenuCommandTests.designSectionEightParses` reads
that table as the set of bindings the app must hold, so a `⌥⌘Q` row saying *not granted* was read as
a binding and went red on the chord count and on the both-ways check. The table states what is bound;
this paragraph states what is refused and why.

That is why those two menus contribute exactly one row between them. **Seven of the mock's ten new
chords sit on commands that are `.featureUnbuilt` in every context** — `⌘R` *Re-index Manifest*,
`⇧⌘R` *Restart Router*, `⌃T` *Trip Selected Breaker*, `⌃⌘R` *Reap Idle Children*, `⌥⌘U`
*Update All Skills*, `⌥⌘D` *Run Doctor* and `⌥⌘K` *Run All Checks* — and the first limb refuses all
seven. `⌘R` in particular stays bound to `Reset the selected server` above, and is deliberately not
re-pointed at the mock's `Re-index Manifest`: this section was re-authored *from* that same mock
under M21, so it is the later reading of one source. `⌘E` on `Export Library…` was refused earlier
on the same limb.

Of the remaining three, `⌃W` is **granted** — *Wake Selected Server* answers
`.needsServerSelection` and fires once a server is selected — and `⌘1` is settled elsewhere, by the
no-duplicate rule: the mock's Library menu re-draws View's `Discover`, and nothing is declared twice.

**`⌥⌘Q` is the one the second limb exists for.** *Review Held Changes…* also answers
`.needsServerSelection`, so it **can** fire and the first limb does not reach it: the rule as it
stood refused a chord for a reason that was not true of it. The chord is refused because **AppKit has
already installed it in this app's own menu bar.** Measured on the running app rather than argued
from the HIG — `planning/evidence/M20-acceptance.md` §5 carries the accessibility read — the App menu
carries `Quit MCP Router` at `Q` with no modifier mask and `Quit and Keep Windows` at `Q` with the
option mask, the latter identified as `NSAlternateQuitMenuItem`: the standard alternate Quit, which
AppKit contributes to any app using the stock App menu. AppKit matches a key equivalent in menu
order, and the App menu precedes Router, so `⌥⌘Q` would never reach a review sheet — it would quit
the app keeping its windows. The `Q` key is enclosed rather than merely adjacent: the same read shows
`⌃⌘Q` on *Lock Screen*, `⇧⌘Q` on *Log Out* and `⌥⇧⌘Q` on *Log Out immediately*, all system-owned.

The count in this paragraph is deliberately the **chord** count and not the command count, and the
distinction is what the earlier wording got wrong. Of the twelve commands the two menus declare,
**nine are `.featureUnbuilt`** and three are not (`revealRouterLog`, `reviewHeldChanges`,
`wakeServer`). That arithmetic is about availability and settles nothing about a key. The rule needs
the chord population — ten chords, seven refused on the command, one granted, one a duplicate, one
claimed by AppKit — because a chord is what this section grants.

---

## 9 · Forgiveness

The Mac's contract is `⌘Z`. **Undo over confirm** — reversible actions are made reversible
and reported, never gated behind "are you sure". Friction scales to blast radius only for
genuinely destructive acts, and then as a named-consequence dialog that is never the
default button.

Two applications that are load-bearing here:

- **The phone queues; it never installs.** Pairing grants a remote party the ability to
  put executable code on a laptop, so the phone's commit bar sends items to the Mac's
  inbox for review. This is narrower than "remote install" and deliberately so.
- **Removing a server is undoable and uncounted.** A never-used server was never deleted,
  so Cleanup does not use a trash metaphor and does not tally what it removed.

---

## 10 · What is still owed

Recorded here rather than in a report, because it is the next design work:

- **A second subject-mined element.** The Signal Path is the only one. A board whose other
  surfaces are stock tables has one signature and eight defaults.
- **Density is inconsistent** — 56px table rows against 120px featured cards holding
  three short lines. The cards are the emptiest thing on the busiest surface. The Servers row is
  now the sharper case of it: 56pt was `4 + 48 breaker housing + 4`, and with the lever retired
  under M16 the row leads with an 8pt plug while the design of record draws its table row at 36pt.
  The value did not move with the derivation, because the table's conversion is not the signature
  element's item.
- **The Signal Path's harness column is specified and not drawn.** The brief's rail is harnesses →
  hub → jacks, and the first of those needs a reading the app cannot reach: `HarnessState` lives in
  `RouterCore`, which neither app target links, and derives from harness config files rather than
  from the control API, which serves no harness route at all. §3 rule A36 forbids a board going
  round it. M22 absorbs `R7-C1` and the route, and the column lands with it. Until then the rail
  reads hub → jacks, which is honest and incomplete rather than either alone.
- **The palette clears the floor; the call sites have not moved yet.** Every surface now has a
  text-safe token to reach for and no surface has been made to reach for it. A board still drawing
  a 13pt label in `--accent` on `--ground` ships 3.52:1, and nothing in the token layer catches
  that: `ContrastFloorTests` proves the palette *can* clear the floor, not that each call site
  does. `ShellAppearanceTests.noUndeclaredIndicatorUse` is the shape that would close it app-wide
  and it reaches the shell only. M16–M22 own the per-surface work; this is the largest thing this
  document currently asks for and does not yet enforce.
- **The two dark shortfalls this section used to carry are closed.** As text on `--raised`,
  `--fail` measured 4.06:1 and `--accent` 4.31:1 under the previous direction. The split resolves
  both: `--fail-ink` is 4.56:1 on dark `--raised` and `--accent-text` is 6.51:1. They are recorded
  as closed rather than deleted, because the pairing that replaced them is the one a reader will
  ask about.
- **The superseded prototype used two indicator colours decoratively.** `design/mocks/prototype.html`'s
  phone Discover list paints trend deltas in `--live` and `--fail` (`+218%`, `−8%`), which §2
  forbids. The console mock does not draw that surface at all, so nothing has replaced the
  judgement yet; the surfaces that ship phone Discover own the fix.

