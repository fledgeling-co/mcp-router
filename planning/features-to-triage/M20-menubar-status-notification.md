---
status: completed
shipped-by: 01b6ef9
---

# M20 — menu bar, status item, and the notification banner

**Depends on:** M1. **Related:** M8 (popover), M14 (menu items that lie), I6 (arrival
notifications).
**Source:** `design/mcp-router-console.html`, PRD §9.8.

Three pieces of system chrome, drawn in full in the mock.

## The menu bar

Nine menus: Apple, MCP Router, File, Edit, View, Router, Library, Window, Help. Every item is
Title Case with its real accelerator right-aligned, and the ones this build cannot do are
**dimmed in place with the reason in the shortcut column** rather than hidden — `Install
Command-Line Tool · Installed` is the pattern. M14 is the failure this prevents: a shipped menu
item that tells the user the app is not built.

The Router menu is where the daemon's own verbs live — re-index, restart, wake, trip, reap,
review held changes, reveal the log, stop. Stop Router has no accelerator, because its blast
radius is every session on the machine.

The View menu carries the nine boards with a tick on the current one; Settings is not in it,
because Settings is a window and lives in the app menu (M15).

## The status item

A template symbol that takes an **amber dot only while something wants a decision**. An icon
that changes constantly is one the eye filters, and then it filters the one change that
mattered.

Its popover answers one question and closes: what is running now (four counts), what the phone
queued, and the last six calls with their outcomes and durations. The queued item carries
Approve, Review… and Not now inline. That inline band is the point of the popover — a decision
that would otherwise need the main window takes one press.

## The notification banner

The delivery mechanism for an analyst finding (PRD §6.4). One sentence carrying the finding and
its evidence count, and three actions: Install, Details, Dismiss.

**The accessibility constraint is load-bearing and easy to get wrong.** Buttons inside an
`aria-live` region are flattened to plain text by assistive technology: the visual banner works
perfectly, and the actions become unreachable for anyone not using a mouse. The announcement is
a permanent, visually-hidden live region written into when the banner fires; the banner itself
is a group whose buttons sit outside it. A time-limited action only mouse users can reach is a
countdown, not an action.

Deep links: `?popover=1`, `?notification=1`.

## Converting this to SwiftUI

Three system APIs, one per piece.

- **The menu bar** is `CommandGroup` and `CommandMenu` in the app's `commands` block. Items that
  this build cannot perform use `.disabled(true)` and keep their shortcut label, which is how
  they stay dimmed in place with the reason visible. M14 exists because an item that lies about
  being available is worse than one that is dimmed.
- **The status item** is `MenuBarExtra` with `.menuBarExtraStyle(.window)`, since the popover
  holds a layout rather than a menu. The icon is a template symbol; the badge is a separate
  overlay applied only when something wants a decision.
- **The banner** is `UNUserNotificationCenter` with a category carrying three actions. The
  actions are real notification actions, not buttons drawn inside the app — which also removes
  the accessibility problem the mock had to solve in HTML, where buttons inside a live region
  are flattened to plain text and become unreachable.

The Approve / Review… / Not now band inside the popover is in-app UI and does need the
accessibility work: announce the arrival through an accessibility notification, and keep the
controls as real focusable buttons outside whatever announces.

Acceptance: a structure dump of the popover shows three separately focusable controls in the
queued-item band, and the disabled menu items appear in the tree with their reason (M23).
