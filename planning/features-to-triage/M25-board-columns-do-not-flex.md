# M25 — three boards are wider than the pane they sit in, so their trailing chrome is cut

**Category:** mac · **Found:** 2026-08-20, by measurement through the accessibility API
**Defect:** DEF-015 (half closed) · **Surfaces:** SURF-004 Skills, SURF-005 Discover, SURF-006 Checks

## What was measured, and what the first half of the fix already did

Every board draws fixed-width columns declared in `M7BoardMetrics` and its siblings — `nameColumn
= unit * 7.5`, `reasonColumn = unit * 9`, and so on, with `unit = 24`. A fixed `.frame(width:)`
reports a hard minimum, so each row's minimum propagated up through the detail pane to
`NavigationSplitView`, which reported the widest board's sum as its own minimum. Nothing read it
back: this app opts into no minimum window size and `windowResizability` defaults to `.automatic`.
The window proposed 980pt regardless, and SwiftUI placed the oversized child **centred**.

| board | window | AXSplitGroup, before | after |
|---|---|---|---|
| Servers, Activity, Cleanup, Inbox, Settings | 980pt | 980pt | 980pt |
| Checks | 980pt | 988pt | 980pt |
| Skills | 980pt | 1044pt | 980pt |
| Discover | 980pt | 1119pt | 980pt |

`ContentZone` now carries `.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)`, which
breaks the chain. The sidebar is whole again — its section headers rendered as `unning` and `brary`
before, while the nav rows beside them were untouched — and `capture-mac-glass.sh` fails on any
board whose split group exceeds its window.

## What is left

The boards still want more room than the detail pane gives them; they are simply no longer allowed
to take it from the window. The leading alignment decides who loses, and it is the trailing chrome:
Discover's search field reads `Search the regis`, and a body sentence loses its last word. One edge
instead of two, and the navigation is safe — but content still goes missing without saying so.

Discover is the one that decides the cost. At 1119pt it wanted 139pt more than the window, roughly
150pt more than the pane, which is a whole column's worth. Its columns are the ones to read first.

## The decision this needs

**Flex the columns.** Replace `.frame(width:)` with `.frame(minWidth:idealWidth:maxWidth:)` on the
columns that can give, so a narrow pane takes space from the widest column rather than from the
right edge. Keeps every control reachable at any window size. Cost: three boards' column work, and
a judgement per column about which one yields — the reason column on Cleanup is already the one
DEF-011 records as truncating where the design shows the whole sentence, so "which column gives" is
a question this codebase has met before.

**Or scroll the table body horizontally.** The AppKit-native answer for a table too wide for its
pane: the columns keep their widths and the body scrolls. Nothing is ever cut, and nothing has to be
re-judged. Cost: a horizontal scroller inside a board that already owns a vertical one, and a header
that has to scroll with it or it stops labelling the right columns.

**Or declare a minimum window width.** One line, and nothing ever needs to fit. Cost: users on a
1280pt-wide screen get a window they cannot shrink below ~87% of it. Referred to the xAI lane
(grok-4.6, xhigh), which rejected this one by name: Discover's +139pt is evidence the metrics are
wrong rather than the window, and Finder, Mail and Xcode all compress or scroll instead.

Guarded today by `ShellDetailWidthTests` and by the capture gate, neither of which can see this half
— both compare the split group against the window, and pane-level overflow stays inside the window.
An assertion for it needs a per-board content-width readback, which is work this brief should carry
rather than a gap to leave unnamed.
