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

### Grounds and lines

| Token | Value | Use |
|---|---|---|
| `--ground` | `#1E1E1E` | window background (kit: dark window) |
| `--panel` | `#232326` | one tonal step up |
| `--raised` | `#2C2C2E` | resting control surfaces |
| `--raised2` | `#3A3A3C` | hovered / emphasized control surfaces |
| `--line` | `#FFF` @7.5% | hairline dividers |
| `--lineS` | `#FFF` @14% | control bezels |

Dark is authored, never inverted. Chrome is graphite, never pure black.

### Label tiers

| Token | Value | Contrast on `--ground` | Use |
|---|---|---|---|
| `--t1` | `#FFF` @100% | 17.0:1 | primary text |
| `--t2` | `#FFF` @55% | 5.97:1 | secondary text, metadata |
| `--t3` | `#FFF` @50% | 5.06:1 | section headers, column headers, tertiary |
| `--t4` | `#FFF` @25% | 2.29:1 | **disabled controls only — never live text** |

**Deviation, deliberate:** the kit's tertiary tier is 25%. On a `#1E1E1E` ground that
measures 2.29:1, and Contrast Dilution is this direction's named #1 defect. Tertiary text
therefore sits at 50%; 25% is retained only where dimming *is* the message.

Fills (bezels, tracks, inactive fills) use `#FFF` at 10 / 8 / 5%.

### Colour

| Token | Value | Meaning — exclusive |
|---|---|---|
| `--accent` | `#0091FF` | selection, focus, the one primary action |
| `--live` | `#30D158` | a child process is running |
| `--attn` | `#FF9230` | wants a human decision |
| `--fail` | `#FF4245` | failed or tripped |

All four are macOS 27 dark system hues. **Nothing else in the app may be any of these
three indicator colours** — that exclusivity is what makes one amber dot in a menu bar
mean something. Per-item identity colour, if ever needed, comes from the remaining
system hues and is never the accent.

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
| Sidebar selection | inset rounded fill, radius 8, 4px side insets |
| Control ladder | Mini 16 · Small 20 · **Regular 24** · Large 28 · XL 36 |
| Popover radius | 20 · card radius 10–14 · concentric children |
| Table rows | 24–28pt for dense lists; the Servers board runs 56 to carry the breaker |

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
- **Motion has never been observed running.** The review driver executes no CSS
  animations, so §7 is specified and unverified. The Swift build is the first chance to
  see it.
- **Light appearance is unauthored.** Everything above is the dark palette. Light is not
  an inversion and must be authored independently before the app can claim to honour
  the system setting.
