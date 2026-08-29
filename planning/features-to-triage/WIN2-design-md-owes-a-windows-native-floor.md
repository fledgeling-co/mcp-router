---
status: to-triage
found-by: intake, reading DESIGN.md section 3 against the directive's "modern windows 11 aesthetic" · 2026-08-30
registry-target: none
no-target-reason: the design authority's native floor is macOS-only and no requirement, case or surface in the registry describes a Windows one, so the registry cannot say whether a Windows surface conforms
---

# DESIGN.md has no Windows native floor, so no Windows surface can be judged conformant or defective

- origin: intake, 2026-08-30, reading DESIGN.md section 3 against the owner's directive
- audience: every Windows surface brief, and anyone who later has to say whether one is right
- platforms: windows

## What and why

DESIGN.md section 3 opens: "These are not stylistic preferences. Each is a rule from the macOS 27
kit, and a violation is a defect rather than a variation." It then lists ten rules. A Windows 11
client built to the directive violates most of them **by construction**, not by carelessness:

- Rule 3 requires Liquid Glass on floating chrome. The Windows 11 equivalent material is Mica, and
  it applies to the window base rather than to floating chrome — the opposite placement.
- Rule 7 requires borderless monochrome SF Symbols. Windows 11 uses Fluent icons, and SF Symbols is
  a licensed Apple font that cannot ship on Windows.
- Rule 9 requires "the menu bar is the complete command surface — every command reachable from it."
  Windows 11 has no global menu bar. There is no Windows surface on which this rule can be satisfied.
- Rule 5 pins 13pt body and 24pt controls, which are macOS metrics. Windows 11 ramps type in
  effective pixels against Segoe UI Variable, and 13pt is not a point on that ramp.
- Rule 8 forbids the pointer hand in app chrome as "a web-content signal" — a rule whose reasoning
  is sound on macOS and whose cursor set is not the Windows one.

So today a Windows surface cannot be assessed. It cannot pass, because the floor describes controls
it does not have; and it cannot fail, because a rule it structurally cannot satisfy is not a defect.
That is the gap. Per G23 the answer is to **change the DESIGN, not the build**: the design authority
gains a Windows floor stated to the same standard as the macOS one, rather than Windows surfaces
being quietly exempted from having a floor at all.

What must not happen is the macOS floor being loosened to accommodate Windows. The two are separate
floors over one shared direction. Section 1's Patchbay direction, section 2's tokens, section 5's
"the states are the design", section 6's vocabulary and section 9's forgiveness are platform-neutral
and stay shared — the directive says the mock decides *what* is on the surface. Only section 3,
section 4's icon set, section 7's motion idiom and section 8's keyboard are macOS-shaped and need a
Windows twin.

## Acceptance sketch

- DESIGN.md distinguishes the shared direction from the per-platform floors, and says which sections are which.
- A Windows floor exists with the same force of language as the macOS one — rules whose violation is a defect, each traceable to published Windows 11 design guidance rather than invented here.
- Every one of the ten macOS rules is either given a Windows counterpart or recorded as having none, with the reason. Rule 9 in particular is answered rather than dropped.
- The accent, indicator hues and label tiers in section 2 are checked against the Windows system accent, which the user can change and which cannot be assumed to match the macOS one.
- The contrast ratios sections 2 and 3 publish are re-measured for the Windows palette rather than carried across, since a ratio measured against one ground is not a ratio against another.
- Nothing in the macOS floor is weakened by this change.

## Assumptions made writing this

- Assuming the Patchbay direction and the Signal Path signature are kept on Windows rather than re-chosen, since the directive asks for parity and names only the aesthetic as differing.
- Assuming DESIGN.md stays one file with per-platform sections rather than splitting into two files, because sections 1, 2, 5, 6 and 9 are genuinely shared and duplicating them would let them drift.
- Assuming "modern Windows 11 aesthetic" means the current Fluent guidance (Mica, rounded corners, Segoe UI Variable, system accent), which is what the phrase conventionally denotes; a specific WinUI version is left to WIN1.
