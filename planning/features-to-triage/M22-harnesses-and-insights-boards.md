# M22 — the Harnesses and Insights boards

**Depends on:** M1. **Related:** R6, R7 (Harnesses); PRD §8 (Insights).
**Source:** `design/mcp-router-console.html`, PRD §9.4.

Two boards the mock draws that have no prior brief. Both are surfaces for work already
specified elsewhere; what is missing is the Mac side of it.

## Harnesses

The surface R7 argues for. Every harness detected on the machine, and — the part that matters —
**how each one currently reaches the router, and what it duplicates**.

A row carries the harness name, its config path and version, and a status that is one of four
readings rather than a boolean: routed over HTTP, routed through a stdio shim, routed but still
declaring direct upstreams, or not routed. Each reading gets its own honest sentence. Grok's
row says it reaches the router through `mcp-remote`, that this is one extra process per session,
and that this is a real cost being named rather than hidden behind a tick.

Above the list sits the finding, when there is one: *"Antigravity runs 18 servers of its own,
ten of which this router already fronts."* Its action opens the reconcile sheet (M18), which
shows the diff of the real file before anything is written.

Per-row actions: open config, verify now, reconcile, and — for a harness whose transport forces
a shim — an explanation rather than a fix, because there is no fix on this side.

The counts on this board are read from the harness config files, so they are only as fresh as
the last drift check. Settings carries that interval (M15), and a stale reading here is worse
than no reading.

## Insights

The counted-usage board PRD §8.2 specifies. Four visualisations, and every number on it is
counted from calls the router served:

1. **Four headline counts** — children at rest, resident memory across all children, tool calls
   over the window, and the failure rate with its numerator and denominator both shown.
2. **Calls by harness** — a bar per harness. The value of this chart is the row reading zero:
   a harness at zero is one still using its own servers, which is the same finding the
   Harnesses board shows from the other side.
3. **Calls per hour** — a sparkline over the last 24 hours.
4. **Duty cycle per server** — the share of wall-clock time each child was alive. This is the
   product's argument in one chart, and it needs the caption that makes it legible: before the
   router, every one of these sat at 100%.

Below them sits the analyst's own configuration and its last run — which model judged, how many
lines it read, how many findings it produced — with a link into the analyzer sheet.

**No number here is modelled.** A window with too little history says so (its empty state) rather
than extrapolating, and the resident-memory figure is labelled *measured, not modelled*. There
is no fabricated saving anywhere on this board; the saving is the duty-cycle chart, and it is
counted.

## Converting this to SwiftUI

**Harnesses** is a `List` of cards, one per detected harness, with the reading as an enum of
four cases so a fifth transport cannot be added without the view failing to compile. The status
sentence belongs to the case, not to a string built at the call site.

**Insights** uses Swift Charts for the sparkline and the bar rows, with two constraints the mock
makes explicit:

- A bar's fill is a token, and the token is the text-safe ink rather than the published hue.
  The mock uses `--live-ink` and `--attn-ink` for bar fills because the kit greens and ambers
  fall below 3:1 against a near-white track. Charts will happily paint the brighter one.
- A zero-valued row must still render its label and its zero. The Antigravity row reading zero
  is the finding; a chart that drops empty series hides it.

The headline counts are a `Grid` of four cards. Each carries its provenance line — *measured,
not modelled* on the memory figure, and the numerator beside the failure rate — because those
lines are the difference between a number and a claim.

Acceptance: a structure dump of Insights contains a labelled node per harness including the ones
at zero, and the bar fills read as the ink tokens rather than the kit hues (M23).
