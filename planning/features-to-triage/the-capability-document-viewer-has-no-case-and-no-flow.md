---
status: completed
shipped-by: 3189d02
---

# The capability-document viewer has no case and no flow

- origin: the orchestrator, from the G14 surface-enumeration finding · 2026-08-27
- audience: Anyone deciding whether the document feature is proved end to end
- platforms: mac
- proposed-by-ai: false

## What and why

M19 built the document viewer — a renderer, a shield parser, an image resolver and a three-tab
panel — and M30 built the route that serves it real files from a package. The campaign has no
surface for it, no case, and no flow.

The gap is sharper here than for a board, because the two halves were proved separately and the
join between them never was. M19's panel was measured against the mock. M30's route was proved by
route tests, parity vectors and a two-router differential. Each is sound. What no case covers is a
person opening a capability, reading its README, and following it to the changelog — the sequence
the feature exists for.

M30's own runner made the point sharply while building the look: every capture of that panel,
M23's included, was a picture of a JSON fixture in this repository rather than a document a router
served. It then built an opt-in path to render a real one and took two captures. That is one
look, taken once, by the person who wrote it — not a case in the campaign that runs again.

## Acceptance sketch

- The viewer is enumerated as a campaign surface, and the document route is reachable from it.
- A flow covers opening a capability, reading its document, and moving between the tabs.
- The panel renders a document the router actually served, not a fixture, and the case says which.
- Its refusals each render and are each distinguishable: nothing served, too large, outside the
  package.
- An image inside a served document draws, rather than showing a placeholder.
- The flow's steps are photographed in sequence, and each capture names the surface it is of.

## Assumptions made writing this

- Assuming a constructed server declaring a package directory is acceptable for the served case,
  labelled as constructed, since no upstream on this machine declares one today.
- Assuming the three tabs are the flow rather than one tab plus navigation, following how the
  panel is drawn.
