---
status: completed
shipped-by: 15926c5
---

# M16 — the Signal Path replaces the Breaker Column

**Depends on:** M3. **Supersedes:** M3's signature element only; M3's state-correctness rules
stand unchanged.
**Source:** `design/mcp-router-console.html`, PRD §9.2.

`DESIGN.md` and M3 specify a Breaker Column — one physical lever per server, snapping up when
live. The mock replaces it with a patchbay that reads left to right, because a breaker answers
"is this on" and the question this product exists to answer is "what is wired to what, and what
is it costing right now".

## What it is

Three parts on one rail:

1. **Harnesses** — the wired clients, each with a state dot: routed over HTTP, routed through a
   stdio shim, or not routed. This is R7's finding stated as a picture.
2. **The hub** — `Router :8879 · 0 at rest`. The product's central claim as a live readout.
3. **The jacks** — one per upstream, on a 44px lane, packed into as many columns as the width
   allows.

A jack carries a plug, the server name, and its condition **in words**: `3:41 left`,
`tripped`, `2 held changes`, `dormant`, `needs sign-in`. The plug colour and the jack's border
change with the state; neither is the only signal. The plug lights the moment something calls
the server and goes dark when the reaper closes the child.

Selecting a jack selects that server in the table below and in the inspector, and the reverse
holds. One selection, three representations.

## Why the metaphor is allowed to be here

A metaphor that stops matching its data becomes decoration. This one is bound to observed
state at every point: the plug states are the real child lifecycle, the arrow count is the
measured topology, and `0 at rest` is a number the router reports rather than a slogan. If the
pooling model changes, the signature changes with it rather than being kept for its looks.

## Constraints found by building it

**It must not grow with the server count.** Laid out as a single column, eleven upstreams ran
the band 500px deep and pushed the table off the board. It is a grid of tracks that packs to
the width available, and the rail's gutters are tight enough that two jacks fit beside an open
inspector.

**The sub-label must fit.** Truncating `3:41 left` to `3:41 …` removes the only part of the
label that was carrying information. Where the width is tight, drop the redundant word — the
plug colour already says "awake" — rather than clipping the countdown.

Deep link: `?only=mac&pane=servers`.

## Converting this to SwiftUI

The jack field is a `LazyVGrid` with `GridItem(.adaptive(minimum: 132, maximum: .infinity))`,
which is the direct translation of the mock's `repeat(auto-fill, minmax(132px, 1fr))` and gives
the same packing behaviour at every width. Do not lay the jacks out with a fixed column count;
the mock's one-column failure at the real window width is what that produces.

- A jack is one `View` with a `JackState` enum driving plug fill, border and label. One view,
  five states, so a new state cannot be added to the model without the view failing to compile.
- The rail is an `HStack` of harness column, arrow, hub, arrow, jack grid. The arrows are
  `Image(systemName: "arrow.right")` at a fixed 20pt width.
- The plug transition is `.animation(.easeOut(duration: 0.2), value: state)` on the fill and the
  ring. The mock specifies the duration and curve; motion is the one layer the mock's own capture
  engine could not execute, so this is a spec to implement rather than a measurement to match.
- Selection is shared state across the jack grid, the table and the inspector — one
  `@Binding var selectedServer: ServerID?`, three readers.

Acceptance: a structure dump at the target window width shows the jacks in two or more columns,
and each jack node carries its state word in its accessibility label (M23). Colour alone is not
the state, on screen or in the tree.
