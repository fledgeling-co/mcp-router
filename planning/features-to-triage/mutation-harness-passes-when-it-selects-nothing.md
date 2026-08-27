---
status: completed
shipped-by: 6c0249b
---

# The mutation harness reports success when its filter selects nothing

- origin: found by the M29/G7 re-verify agent, reproduced by the orchestrator · 2026-08-26
- audience: Anyone relying on the mutation harness to show an assertion can fail
- platforms: n/a
- proposed-by-ai: false

## What and why
The harness that proves an assertion is capable of failing accepts a filter naming which checks to
run. When the filter matches nothing, it reports that it ran no checks, killed none of them, and
succeeded. Measured: a filter naming a check that does not exist returns success with a count of
zero on both sides.

This is the failure the harness exists to catch, occurring in the harness. Its entire purpose is to
stop a check being trusted before anyone has watched it fail, and a run that selected nothing
produces the same success as a run that selected everything and killed it. The agent that found it
had already been caught by it twice in one session: two filters that matched nothing passed quietly
and were taken as evidence until a third attempt happened to match.

The cost is worse than an ordinary false pass, because this tool is what other checks are measured
against. A report saying the mutation harness succeeded is meant to be the strongest evidence
available, and a filter typo silently converts it into the weakest.

## Acceptance sketch
- Running the harness with a filter that selects nothing fails rather than succeeding.
- The failure says the filter matched nothing, distinguishing it from checks that ran and passed.
- A filter that selects some checks still runs exactly those and reports on them.
- A run with no filter is unchanged.
- The harness's own tests include a filter-matches-nothing case, so this cannot return silently again.

## Assumptions made writing this
- Assuming the remedy is that selecting nothing is a failure, rather than a warning, because a
  warning printed among ordinary output is what let this pass unnoticed twice already.
- Assuming an empty selection is always a mistake here, since running the harness at all is a
  request to measure something specific.
