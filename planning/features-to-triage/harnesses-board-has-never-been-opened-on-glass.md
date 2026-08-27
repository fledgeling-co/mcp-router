# The Harnesses board has never been opened on glass

- origin: the orchestrator, from the G14 surface-enumeration finding · 2026-08-27
- audience: Anyone relying on the campaign's coverage number to know what has been exercised
- platforms: mac
- proposed-by-ai: false

## What and why

The Harnesses board shipped with M22 and no test case has ever opened it. It is absent from the
campaign's surface list entirely, so it does not appear as an uncovered surface — there is no row
for it to be uncovered in, and every completeness gate reports clean over a list that never
named it.

It is not unmeasured in every sense. Its structure is compared against the design of record by
the mock-fidelity lane, which carries a layers manifest for it. So what is known is that it draws
what the mock draws. What nobody has established is that it loads, that its rows populate from a
real router, that its failure and empty states render, or that a person can reach it from the
sidebar — the things the on-glass lane exists to establish for the other seven boards.

The cost is that a coverage figure covering seven of nine destinations reads exactly like one
covering nine, and the person reading it has no way to tell.

## Acceptance sketch

- The board is enumerated as a campaign surface with a route and a lane that can observe it.
- Selecting it from the sidebar reaches it, and the window title becomes its destination name.
- Its populated, empty and failure states each render and are each photographed.
- Its rows reflect what a real router reports rather than a fixture, on the lane that can tell.
- Each case states the oracle rung it stands on, and a case proving only that something rendered
  is recorded as that and not as proof the board works.
- The campaign's own gate counts the board in its denominator afterwards.

## Assumptions made writing this

- Assuming the board belongs on the macos-glass lane like the other seven, rather than being
  proved by unit and fidelity lanes alone.
- Assuming its states are the same populated/empty/failure set the other boards use, rather than
  a bespoke set, until someone reading the board says otherwise.
