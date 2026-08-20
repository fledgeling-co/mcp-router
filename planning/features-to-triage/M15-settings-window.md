# M15 — Settings becomes its own window

**Depends on:** M1. **Supersedes:** the Settings half of M8.
**Source:** `design/mcp-router-console.html`, PRD §9.5.

M8 specifies Settings as a board in the console's source list. The mock moves it to a separate
window, because that is what the platform does and because seven panes will not fit a board.

## What changes

**A window, not a board.** Its own 33px titlebar, its own 200px source list, its own detail
scroll. It is removed from the console's navigation list entirely, so the list now ends at
Insights with the health card directly beneath.

**Seven panes:** Router, Harnesses, Session analyst, Updates, Security, Advanced, Menu bar.
Seven is past the point where a preferences tab bar works — the corpus puts the cut at five —
which is what makes a source list correct here rather than merely available.

**Minimise and zoom are greyed while close stays live.** This is the tell that identifies a
macOS settings window at a glance, and it is present on every settings surface in the corpus
pattern set. Build them as disabled controls that dim in place, not as hidden ones.

**No Save button.** Every control applies on change, which is the platform convention and is
already true of the controls M8 lists.

**Reached from the app menu, `⌘,`, `⌘0`, or the Window menu**, where a tick tracks whether it is
open. Escape closes it.

## Pane contents

Each pane opens with its name and one line saying what it governs, then grouped inset cards:
label left, control right on a shared axis, inset hairlines between rows.

| Pane | What it governs |
|---|---|
| Router | endpoint, idle window, warm set, start at login, resolved child PATH (R6) |
| Harnesses | adopt automatically, warn about duplicates, reconcile without asking (off by default), drift check interval |
| Session analyst | on/off, primary and fallback model, which harnesses to read, frequency, notify |
| Updates | app and skill check intervals, channel, what an update is allowed to do unattended |
| Security | control token, trust decay policy, schema quarantine, retention window |
| Menu bar | show the status item, what earns a badge, approve from the popover |
| Advanced | log level and location, local store, reset, build identity |

## What is likely to go wrong

**Two source lists sharing one row style.** The console's list and the settings list use the
same row metrics and the same selection treatment. In the mock this was a real bug: the
console's board switcher cleared the settings list's selection through an unscoped query, and
the selected pane rendered with no fill. Each list owns its own selection and its own arrow-key
traversal.

**Whose chrome is it.** While Settings is frontmost it owns its own state; the console's
toolbar subtitle and sidebar tallies are not Settings' to change.

**Sheet attachment.** A sheet opened from a Settings pane — the analyst configuration, the PATH
inspector — attaches to the Settings window, not to the console. The mock draws both windows in
one page and cannot demonstrate this; the implementation has to get it right without that
reference.

Deep links: `?window=settings`, `?window=settings&pane=analyst`.

## Converting this to SwiftUI

Use the **`Settings` scene**, not a hand-built `Window`. On macOS the standard settings window
is what carries the disabled minimise and zoom, the correct titlebar height, and the `⌘,`
binding, so building those by hand reproduces something the platform already gives. Confirm on
the target macOS version that the scene disables both buttons; if it does not, disable them
explicitly rather than hiding them.

- The pane list is a `NavigationSplitView` whose sidebar is a `List` with `.listStyle(.sidebar)`.
  Selection is the same accent fill at radius 8 the console's source list uses, so it comes from
  the shared row view rather than a second implementation.
- Each pane is its own `View` in `MCPRouterUI/Settings/`, and the seven are an enum so the count
  is a compile-time fact rather than a list someone can forget to extend.
- The grouped cards are `Form { Section { … } }` with `.formStyle(.grouped)`, which produces the
  inset rounded card, the shared control axis and the inset hairlines without hand-drawing them.
- No Save button means every control binds straight to the settings store.

**The trap that produced a real bug in the mock:** two source lists sharing one row view. Give
each list its own selection binding; a shared or global one lets the console's board switcher
clear the settings pane selection.

Acceptance: a structure dump of the Settings window contains seven pane rows, exactly one
selected, and the pane body matching that selection (M23).
