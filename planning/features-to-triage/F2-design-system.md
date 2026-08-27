---
status: completed
shipped-by: 22d1802
---

# F2 — The design system in SwiftUI

**Depends on:** F1.

Turn `DESIGN.md` into code, so no surface ever hardcodes a colour or a font size.

- Colour: label tiers `--t1..t4`, grounds, fills, and the four system hues, as an
  asset catalogue with light + dark. **Light must be authored, not inverted** — it does
  not exist yet and DESIGN.md §10 records that as owed.
- Type: the eight-role SF ramp as `Font` extensions. Nothing off the ladder.
- The icon set: SF Symbols at matched weights where one fits, authored assets where
  none does. The prototype's 21-symbol sprite is the inventory.
- Control styles matching the kit ladder (Mini 16 → XL 36), the inset-rounded selection
  fill at radius 8, and the focus ring.
- **The breaker** as a reusable `View` with its three lit states and the two springs
  from DESIGN.md §7. This is the app's signature element and its construction is
  load-bearing: the slot must be wider and taller than the toggle so it reads in the
  dormant state, which is where two prototype rounds failed.
- The nine state containers from DESIGN.md §5 — empty, loading, partial, error, offline
  — as composable views, so a surface cannot ship populated-only by accident.

Reference: `design/mocks/prototype.html`, `DESIGN.md` §§2–7.
