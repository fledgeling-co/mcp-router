# DESIGN.md — MCP Router

The design authority for the Mac app, the iPhone companion, and anything else that
renders. Where this file and a general craft rule disagree, this file wins; where this
file and Apple's macOS 27 UI kit disagree, **the kit wins** — native correctness is never
traded for style.

The reference implementation is `design/mocks/prototype.html`. It is interactive, carries
every surface, and is deep-linkable (`?pane=&tab=&sheet=&sel=&only=mac|phone`). When this
document and the prototype disagree, the prototype is stale and this document is the spec.

---

## 1 · Direction

**Instrument Panel** — a specialisation of the corpus's *Terminal Dark*: graphite ground,
one system accent bound to interaction, three indicator colours that only ever do their
own job, monospace reserved for instrument data.

Runner-up was *System Native*, rejected because an app whose whole subject is "which of
your capabilities are live right now" wants a board you read at a glance, not a settings
pane you navigate.

**Named risk:** a skeuomorphic control (the breaker) inside a native app.
**Signature element:** the breaker column on Servers — one lever per declared server,
snapping up the instant an agent calls it and easing down when the reaper closes it. It is
a literal rendering of the mechanism the product exists for, and it is the only loud thing
in the app. Everything else stays quiet so it can be.

**The known weakness, stated rather than hidden:** Terminal Dark is one of the two looks a
model defaults to on any brief. The subject genuinely earns it, so the direction stands —
but distinctiveness has to come from *subject-mining*, and right now the breaker is the
only mined element. Anything built from here should add a second one rather than another
stock table. See §9.

---

## 2 · Tokens

Every value below is either an Apple `(specified)` kit value or a stated deviation from
one. Nothing here was picked by eye.

**Both appearances are authored.** Light is not an inversion of dark, and the reason is
measured rather than aesthetic: every dark indicator hue, placed unchanged on the light
ground, lands between 1.71:1 and 2.91:1 — against the 4.5:1 a label needs. All four are
re-solved. The tiers, lines and fills are authored to reproduce **dark's measured contrast
ratio**, not to copy its alpha, because a dark hairline on a light ground and a light
hairline on a dark ground are not equally visible at the same opacity. That is why the
alphas differ (`--t2` is 55% in dark and 62% in light) while the hierarchy reads the same
in both. Every ratio in the Light column below was measured on `--ground`, not estimated.

### Grounds and lines

| Token | Dark | Light | Contrast (light) | Use |
|---|---|---|---|---|
| `--ground` | `#1E1E1E` | `#ECECEE` | — | window background (kit: dark window / light window) |
| `--panel` | `#232326` | `#F5F5F7` | 1.08:1 | one tonal step up — same direction in both |
| `--raised` | `#2C2C2E` | `#FFFFFF` | 1.18:1 | resting control surfaces |
| `--raised2` | `#3A3A3C` | `#E0E0E4` | 1.12:1 | hovered / emphasized control surfaces |
| `--line` | `#FFF` @7.5% | `#000` @10% | 1.25:1 | hairline dividers |
| `--lineS` | `#FFF` @14% | `#000` @19% | 1.56:1 | control bezels |
| `--f1` | `#FFF` @10% | `#000` @13% | 1.35:1 | fills — bezels |
| `--f2` | `#FFF` @8% | `#000` @10% | 1.25:1 | fills — tracks |
| `--f3` | `#FFF` @5% | `#000` @6% | 1.14:1 | fills — inactive |

Dark is authored, never inverted. Chrome is graphite, never pure black — and its light
counterpart is a light grey, never pure white.

**The one reversal in the system:** `--raised2` is *lighter* than `--raised` in dark and
*darker* in light. Emphasis always moves away from the ground; in light the resting
surface is already white, so darker is the only direction left. Everything else steps the
same way in both appearances.

### Label tiers

| Token | Dark | Light | Contrast (light) | Use |
|---|---|---|---|---|
| `--t1` | `#FFF` @100% | `#000` @95% | 16.58:1 | primary text |
| `--t2` | `#FFF` @55% | `#000` @62% | 5.85:1 | secondary text, metadata |
| `--t3` | `#FFF` @50% | `#000` @58% | 5.09:1 | section headers, column headers, tertiary |
| `--t4` | `#FFF` @25% | `#000` @33% | 2.27:1 | **disabled controls only — never live text** |

**Deviation, deliberate:** the kit's tertiary tier is 25%. On a `#1E1E1E` ground that
measures 2.29:1, and Contrast Dilution is this direction's named #1 defect. Tertiary text
therefore sits at 50%; 25% is retained only where dimming *is* the message. The light
column carries the same deviation, expressed as the ratio rather than the alpha.

### Colour

| Token | Dark | Light | Contrast (light) | Meaning — exclusive |
|---|---|---|---|---|
| `--accent` | `#0091FF` | `#0069CF` | 4.54:1 | selection, focus, the one primary action |
| `--live` | `#30D158` | `#1B7B3C` | 4.51:1 | a child process is running |
| `--attn` | `#FF9230` | `#9F5A00` | 4.52:1 | wants a human decision |
| `--fail` | `#FF4245` | `#CD2738` | 4.51:1 | failed or tripped |
| `--onAccent` | `#FFFFFF` | `#FFFFFF` | 5.35:1 | the label drawn on an accent fill |

All four indicator hues are macOS 27 system hues — the dark column the dark set, the light
column re-solved in OKLCH so the hue angle survives the darkening. **Nothing else in the
app may be any of these three indicator colours** — that exclusivity is what makes one
amber dot in a menu bar mean something. Per-item identity colour, if ever needed, comes
from the remaining system hues and is never the accent.

`--attn` is additionally pulled toward yellow. Solved on hue alone it lands 21.5° from
`--fail` at near-identical lightness, which is exactly where protan and deuteran vision
compresses — and those two tokens mean "wants a decision" and "failed". The shipped pair
sits 39.8° apart, and colour is never the only signal carrying either.

**Deviation, deliberate, and against us:** `--onAccent` on `--accent` measures **3.23:1 in
dark**, under the 4.5:1 a 13pt semibold label wants; near-black would give 6.49:1. Every
native filled accent control on macOS carries a white label, and this document's own
precedence says the kit wins where it and this document disagree. So white stands, recorded
with its measurement rather than hidden. Exposure is bounded by §3 rule 4 — one prominent
accent-filled action per view — and that control is distinguished by shape and position
too, never by colour alone.

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
| Titlebar | 33pt |
| Unified toolbar | 52pt (8 + 36 XL controls + 8) |
| Sidebar | 256pt; rows 24/32/40 |
| Control mini | 16pt |
| Control small | 20pt |
| Control regular | 24pt |
| Control large | 28pt |
| Control extra large | 36pt |
| Sidebar selection radius | 8pt |
| Sidebar selection inset | 4pt |
| Focus ring | 2pt |
| Popover radius | 20 · card radius 10–14 · concentric children |
| Table rows | 24–28pt for dense lists |
| Servers row | 56pt (4 + 48 breaker housing + 4) |

Selection is an inset rounded fill at the radius and side inset above. The control ladder
and the selection fill used to be written as prose in one cell each — unreadable to the
parity check, and therefore free to drift. They are individual rows now because the design
system builds controls from them. The Servers board's 56pt row is a row of its own for the
same reason: the loading skeleton has to match the populated row's height exactly or the
board jumps when data lands, and a height buried in another cell's prose cannot be checked.

Concentric corners throughout: child radius = parent radius − padding.


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
- Buttons are verb-first and name the action. "Send 2 to Mac", never "Submit" or "OK".
- One name per state across both devices. A skill with no evaluation reads
  "not evaluated" on the Mac and on the phone; never "no eval" on one of them.
- Errors state what happened and how to fix it, next to the thing that failed.
- Helper text is one quiet secondary sentence under its control.
- Numbers the router does not observe are never displayed. There is no fabricated memory
  saving anywhere in this app, because the router never runs the world where every server
  is resident and so has nothing to subtract from.

---

## 7 · Motion

Springs, not durations. Interruptible. Transform and opacity only.

| Moment | Feel |
|---|---|
| Breaker snapping up | fast spring, ~0.18s, slight overshoot — the call already happened |
| Breaker easing down | slow ease, ~0.6s, no overshoot — the reaper is unhurried |
| Sheet / popover entry | materialize from its anchor, never a centre fade |
| Row selection | immediate; no transition on the selection fill |
| Badge count change | a small scale bump, never a colour flash |
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
| `Return` | commits the view's one default action |
| `Esc` | dismisses the sheet, then clears selection |
| `Space` | toggles the selected row's breaker |

Focus rings are visible, accent-bound, 2px. Tab order runs sidebar → table → inspector.

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

- **A second subject-mined element.** The breaker is the only one. A board whose other
  surfaces are stock tables has one signature and eight defaults.
- **Density is inconsistent** — 56px table rows against 120px featured cards holding
  three short lines. The cards are the emptiest thing on the busiest surface.
- **Two contrast shortfalls in the dark palette, measured and not yet resolved.** As text
  on `--raised`, `--fail` is 4.06:1 and `--accent` is 4.31:1 — both under AA. They pass on
  `--ground` (4.86:1 and 5.16:1); it is the raised control surface where they fall short.
  Changing a shipped dark value affects every surface, so it is recorded here rather than
  altered in passing.
- **The prototype uses two indicator colours decoratively.** Its phone Discover list paints
  trend deltas in `--live` and `--fail` (`+218%`, `−8%`), which §2 forbids — those hues mean
  "a child process is running" and "failed or tripped", and nothing else. The prototype is
  stale here; the surfaces that ship Discover own the fix.

