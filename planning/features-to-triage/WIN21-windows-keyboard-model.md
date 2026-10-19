---
status: completed
found-by: intake divergent pass, from DESIGN.md section 8 being a macOS keyboard specification · 2026-08-30
registry-target: none
no-target-reason: the registry has since gained nineteen Windows rows, so the original reason - that nothing in it describes a Windows surface - is no longer true. It is still true that no requirement, case, surface or defect describes a Windows KEYBOARD MODEL: searching the registry for accelerator, shortcut or keyboard against any Windows row returns nothing. Corrected 2026-09-03, we4.
---

# DESIGN.md specifies a macOS keyboard, so the Windows client has no keyboard specification at all

- origin: intake divergent pass, 2026-08-30
- audience: keyboard-first users on Windows, and anyone testing the Windows client without a mouse
- platforms: windows
- proposed-by-ai: true

## What and why

DESIGN.md section 8 is "The keyboard", and like section 3 it is written for macOS. Its shortcuts are
Command-based, and its completeness guarantee leans on rule 9 — the menu bar being the complete
command surface — which Windows does not have. So on Windows the keyboard is currently unspecified,
and an unspecified keyboard becomes whatever the framework's defaults happen to be.

The substitutions are not mechanical. Command maps to Control for most shortcuts, but not all:
Control-based combinations that are free on macOS are already taken on Windows, and the reverse.
Windows also has two affordances macOS does not — **access keys** (Alt plus a letter, with the
letter underlined on the control) and a stronger convention around F6 for pane cycling — and a
Windows app without them reads as unfinished to a keyboard user.

There is a measured reason to care beyond convention. The campaign's macOS shortcut case is recorded
as not applicable, because posting Command-1 through Command-7 to a background process does not
change SwiftUI's focused scene, and proving the shortcuts would require the window frontmost, which
that campaign refuses. So on the Mac the keyboard is largely *unproven*. If the Windows client
publishes a UI Automation tree (WIN20), its keyboard is testable in a way the Mac's is not — which
makes this one of the few places Windows can be better rather than merely equal.

## Acceptance sketch

- A Windows keyboard specification exists in the design authority, with the same force as the macOS one and each shortcut traceable to Windows convention rather than transliterated from Command.
- Every board is reachable by keyboard, and the mapping from the Mac's board shortcuts is recorded including where it could not be direct.
- Access keys are provided on menus and command surfaces, with the accelerator letter shown.
- Focus is always visible, follows a sensible order, and never becomes trapped; F6 or an equivalent cycles panes.
- Every command reachable by pointer is reachable by keyboard, which is the property rule 9 provided on macOS and which nothing currently provides on Windows.
- The shortcuts are actually exercised rather than asserted, using the automation plane from WIN20.

## Assumptions made writing this

- Assuming a Windows keyboard section is added to DESIGN.md alongside the Windows floor from WIN2 rather than in a separate document.
- Assuming shortcuts follow Windows convention where the two conflict, since the directive puts the Windows idiom in charge of how things are done.
- Assuming keyboard completeness is worth preserving as a guarantee even though the mechanism that provided it on macOS does not exist here.
