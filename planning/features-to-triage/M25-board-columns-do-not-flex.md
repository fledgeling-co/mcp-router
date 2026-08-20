# M25 — closed: the width came from the controls row, not the columns

**Category:** mac · **Found:** 2026-08-20 · **Closed:** 2026-08-20
**Defect:** DEF-015 (closed) · **Surfaces:** SURF-004 Skills, SURF-005 Discover, SURF-006 Checks

This brief was written from one measurement and closed by a second one that contradicted it. Both
are recorded, because the first was wrong in a way worth being able to recognise again.

## What the first measurement said

Comparing each board's `AXSplitGroup` width against its `AXWindow` width found three boards laying
out past the window at a 980pt size — Checks 988, Skills 1044, Discover 1119 — each with its origin
moved left by exactly half its excess, so the clipping was symmetrical and the sidebar's own section
headers were being cut to pay for the detail pane. `ContentZone` gained
`.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)`, which broke the minimum-width chain
and put every board back at 980 of 980, with the leading alignment deciding that the trailing chrome
loses rather than the navigation.

That left content still cut at the pane's right edge, and this brief said the fix was to flex three
boards' table columns.

## What the second measurement said

A pane-level probe — every leaf's right edge against the window's, from the same dumps — says the
columns are not the driver.

| board | content wants | pane has | driver |
|---|---|---|---|
| Discover | 823pt | 684pt | controls row: a `.fixedSize()` segmented picker at 567pt beside a search field pinned at 240pt |
| Skills | 748pt | 684pt | the same shape — a 516pt picker and a 216pt pinned field |
| Checks | 1152pt of content inside a 1160pt pane | — | **not a content defect.** The only thing past the edge is `KeyClaimProbe`, the `#if DEBUG` test surface, overhanging by 4pt |

Cutting Discover's `nameColumn` from 216pt to 96pt — a 120pt reduction — moved its content width by
**zero**. That is what ruled the columns out, and it took one build to find out.

## The probe was wrong first, and the pixels caught it

Its first version read the frame's **y** where it meant **x**: a dump row's last five fields are x,
y, w, h and a flag, and it took `r[-4]`. It reported clipped elements on seven of eight boards,
including Settings, whose capture is whole from edge to edge. Seven of eight is close to uniform,
which is the signature of a dead predicate rather than a broken product — and opening one screenshot
settled it in under a minute. The split-group gate was unaffected because it only ever compared
widths.

## What was done

Each board gained a `searchMinWidth` of four units, and its field is declared
`minWidth:idealWidth:maxWidth:` rather than `width:`. The picker cannot give a point back — that is
what `.fixedSize()` means, and it is right, because a segmented control has nowhere to put a
truncated label — so the field is the only control in the row that can. It renders at full width
wherever there is room, and shows about eight characters at the narrowest window this app is used
at: less than anyone wants, and more than nothing, since it still takes focus, accepts a query and
submits.

Measured after: every board reads `split=980` in a `window=980`, and no leaf on any of the eight
sits past the pane edge except a 1pt scrollbar, plus the Debug key probe's 4pt on Checks.

Guarded by `ShellDetailWidthTests`, four assertions across two tests, all armed. `capture-mac-glass.sh`
fails on any split-group overflow and refuses to pass on `examined=0`.

## What is deliberately left

`KeyClaimProbe`'s 4pt overhang on Checks. It is a `#if DEBUG` surface that exists so A21 has
something to prove the shell does not swallow three bare keys, it is absent from any build a user
runs, and moving it risks the thing it exists to measure. Recorded so the next reader of a Debug
capture knows what the 4pt is.
