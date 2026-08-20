# M21 — the token layer, the split accent, and reconciling `DESIGN.md`

**Depends on:** F2 (the design system in SwiftUI).
**Source:** `design/mcp-router-console.html`, PRD §9.1 and §9.9.

Two things to settle: a colour system that clears the contrast floor without abandoning the
platform's own hues, and a `DESIGN.md` that now describes a direction the mock does not build.

## `DESIGN.md` and the PRD disagree

`DESIGN.md` specifies *Instrument Panel* — Terminal Dark with a Breaker Column signature. The
mock builds *Patchbay* — light-first, with the Signal Path (M16). Both documents are in the
repo and an implementer reading `DESIGN.md` alone will build the wrong thing.

This needs a decision rather than a merge: either `DESIGN.md` is re-authored against the mock,
or the mock is treated as an exploration and discarded. It should not be left as it is. The
mock was built under an explicit instruction to ignore the existing direction, so `DESIGN.md`
being out of date is expected rather than an oversight — but it is still out of date.

## The accent has to be split, and the reason is measured

Apple's published system Blue `#0088FF` measures **3.52:1** against white, below the 4.5:1
floor for 13px text. Shipping it under a white label ships a known accessibility failure with
the platform's name on it.

The resolution is two tokens with different jobs:

- `--accent` keeps the published hue, and carries rings, plugs, dots and tints — none of which
  is text.
- `--accent-ink` carries any accent surface with text on it: `#0071E3` light (**4.70:1**),
  `#0A6FD6` dark (**4.93:1**).

Every indicator hue needs the same twin, because the same problem appears at every status
colour: `--live-ink`, `--attn-ink`, `--fail-ink`, each solved against all three grounds
(`--ground`, `--chrome`, `--panel`), plus `--shield-good` and `--badge-bg` for the two filled
badges that carry white.

## Six appearance contexts, not two

Light, dark, an explicit light and dark override for the in-app appearance switch, and **two
separate increased-contrast blocks**. The last is the one that gets missed: a single
scheme-agnostic `prefers-contrast` block paints dark ink on a graphite ground in whichever of
the two appearances it was not written for. Author increased contrast per appearance.

## The invariants worth gating in the Swift port

- Every colour lives in a token. The mock carries 89 in its token block and **zero colour
  literals outside it**; the equivalent in SwiftUI is that no `Color(hex:)` appears outside the
  palette type.
- Contrast is measured in all four appearance contexts, not one. Current measurement on the
  mock: 5,788 pairs, 0 failures, 0 unresolved.
- Disabled text is exempt under WCAG 1.4.3 incidental, and that exemption is claimed
  explicitly rather than by the check quietly skipping those pairs.
- Colour is never the only signal — every state that has a colour also has a word.
- No `cursor: pointer` equivalent: on macOS the hand cursor over a control is the non-native
  tell an experienced user names first.

## What is unmeasured

Motion, type fidelity, and the three accessibility media queries are specifications in the
mock rather than measurements. The capture engine available here runs no CSS animation, loads
no web fonts, and accepts `Emulation.setEmulatedMedia` without applying it. Any claim about
those needs a real browser or a built app.

## Converting this to SwiftUI

The four appearance contexts map exactly onto what an Xcode asset catalogue already models: an
Any/Light/Dark appearance axis crossed with a High Contrast variant gives light, dark,
light+contrast and dark+contrast. Author the colour set with all four filled rather than
letting two of them inherit, because the mock's two separate `prefers-contrast` blocks exist
precisely because a shared one is wrong in one of the two.

- `ColorToken` stays the only place a colour literal appears. The parity test asserts that by
  grep, which is the analogue of the mock's `literals_outside=0` and the check that keeps the
  system from becoming decorative.
- The split accent becomes two cases, not one with a modifier: `accent` for rings, plugs and
  tints, `accentInk` for any filled surface carrying text. A single token with call-site
  judgement is how the 3.52:1 label ships.
- `MetricToken` gains the mock's metric rows. The parser for them is simpler than the Markdown
  table parser `DesignDocParser` already implements, because the block is `name value tier`.
- Contrast is asserted in code across all four contexts, not spot-checked. The mock measures
  5,788 pairs; the Swift side can measure every token pair that actually co-occurs, which is a
  smaller and more useful set.

Acceptance: the token parity test passes against the mock, the colour-literal grep returns
nothing outside the palette, and a deliberately mismatched token makes the test fail — a parity
test never observed failing is a test nobody has written (M23).
