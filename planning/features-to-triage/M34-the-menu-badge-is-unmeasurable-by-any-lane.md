---
status: to-triage
found-by: M20's verifier (F4), 2026-08-23; rescued from a verdict that had no destination for it
---

# The one new user-visible behaviour in M20's Slice A cannot be measured by any lane we have

This is **evidence work rather than product work** — the behaviour may well be correct, and nothing
available can say so.

The badge is the answer to the brief's *dimmed in place with the reason in the shortcut column*
(`app/Sources/MCPRouterUI/Shell/ShellMenuReasons.swift:68` at tree `1d9ffad`, anchor *"This is what
puts the reason where the brief asks for it."*). **The only thing reading it is a unit test over a
menu the test itself built.**

Four lanes, each closed for a different reason, all measured:

- **The accessibility tree exposes no badge attribute.** 19 attributes on each probed item, five
  direct probes absent — and `AXHelp` is correct on both, so the instrument is sound rather than
  broken.
- **`scripts/acceptance/mac-shell.sh` has no menu-badge assertion.** It was extended for the menu
  count and order. Every `badge` hit in that file is a pre-existing **sidebar-row** badge
  (`:286 :310 :314 :316 :317 :321 :324 :331 :825`) — so a grep for `badge` in the acceptance lane
  reports coverage that does not exist.
- **Actuation does not work.** `axkit.swift`'s own header records that `AXPress` on a menu item
  returns `.success` **and does nothing** in a background app.
- **Photography is forbidden.** Taking the screen to open the menu is what `UI_VERIFICATION.md`
  rule 1 forbids.

**Six items carry a chord and a badge at once, and nothing measures which the trailing area shows.**
That is the specific claim nobody can currently settle.

## Scope

The remedy is a hook or a lane, not a fix to M20. Options, none costed:

- A badge assertion in `mac-shell.sh` that reads whatever the trailing area actually exposes, if
  anything does.
- An in-process render of the real menu rather than a test-built one, which is the shape
  `ImageRenderer` served for M18's disabled-state question — noting it draws nothing inside a
  `ScrollView`, so its limits need establishing here too.
- Recording the limit permanently in structural terms and accepting the row as `unmeasured`, which is
  the honest floor if the first two do not hold.

**The trap to avoid** is the one already in the file: a grep for `badge` in the acceptance lane
returns nine hits and none of them is this. An absence check with a false positive above it reports
coverage.
