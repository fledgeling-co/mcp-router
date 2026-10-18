---
status: completed
found-by: WIN2's independent verifier, note 2 of 2 · 2026-08-30
registry-target: none
no-target-reason: the registry has since gained nineteen Windows rows, so the original reason - that it holds no Windows surface or requirement - is no longer true. It is still true that no registry entity records a CONTRAST MEASUREMENT against a Windows control fill; the Windows surface rows declare controls and routes, and no case measures a disabled pairing's contrast ratio on a Windows surface. Corrected 2026-09-03, we4.
---
# The Windows disabled-control pairing is named but never measured, and its macOS twin was

- origin: WIN2 verification, 2026-08-30
- audience: anyone deciding whether a disabled Windows control is legible
- platforms: windows

## What and why

DESIGN.md §11 rule 4 specifies the disabled state of a Windows control as `TextFillColorDisabled`
over `ControlFillColorDisabled`. That pairing is measured nowhere, and `ControlFillColorDisabled`
does not appear with a value in any table in §12.

§12 does measure `TextFillColorDisabled` against the four **grounds** — 3.35/3.27/3.09/3.06 dark and
2.49/2.51/2.52/2.49 light — but a disabled control does not sit on a ground, it sits on the disabled
control fill. So the one pairing the rule actually specifies is the one pairing with no number.

This is precisely the measurement §3 went to the trouble of making for macOS. That section publishes
`--t4` on `--f3` at **2.94:1 dark and 2.62:1 light**, states it is below the 4.5:1 body floor and
below 3:1, and claims the WCAG 1.4.3 exemption for a disabled control explicitly rather than
implying it. The Windows arm mirrors the rule and stops one measurement short of the evidence.

Nothing turns on the outcome — the exemption is claimed either way — which is exactly why this is
worth closing rather than arguing. An absent number in a document whose whole discipline is that
figures carry their provenance is a gap in the discipline, not in the design.

**This is a missing measurement, not a wrong one.** It must be closed by reading
`ControlFillColorDisabled` from the WinUI theme resources, computing the ratio against
`TextFillColorDisabled` in both appearances, and citing the file the values came from — never by
supplying a plausible figure. §3's own note that inventing a ratio would be "a fabricated number in
a palette's clothes" applies here with full force.

## Acceptance sketch

- `ControlFillColorDisabled` appears in §12 with its dark and light values and the source file they were read from.
- The ratio of `TextFillColorDisabled` on `ControlFillColorDisabled` is published for both appearances.
- The WCAG 1.4.3 exemption is claimed explicitly for the Windows arm, as §3 does for macOS.
- If the pairing turns out to be unreadable rather than merely unpublished, that is stated, as §3 states it for the macOS pairing.
- No figure appears without the file it was read from.

## Assumptions made writing this

- Assuming the fix is a measurement rather than a design change, since the rule itself matches Windows convention and only its evidence is missing.
- Assuming §12's existing four-ground table stays as it is; this adds the control-fill pairing rather than replacing anything.
