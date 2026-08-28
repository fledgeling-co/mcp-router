---
status: to-triage
found-by: `vacuity-check.py --gate` (test-campaign 0.14.1), 2026-08-29
---

# REQ-016 claims an outbound socket and names nothing that could open one

- origin: test-campaign 0.14.1 run against `planning/test-campaign`, full scope · 2026-08-29
- audience: whoever needs an effect claim to point at code that can perform it
- platforms: n/a
- proposed-by-ai: true

## What and why

REQ-016 declares an `outbound-socket` effect and records no provider. Nothing in production source
is named as able to perform it, so the requirement asserts a behaviour with no candidate
implementation behind the assertion. Every other declared effect is bound: providers are 8 of 9
named, and the 8 resolve over 492 production files.

An unbound effect claim passes quietly in both the directions that matter. If the socket really is
opened, the requirement cannot say by what, so a change that removes the call has nothing pointing at
it. If it is not opened at all, the requirement is a promise the product does not keep and the
campaign records it as observed anyway.

One requirement out of nine, and the machinery to hold it already works for the other eight.

## Acceptance sketch

- REQ-016 names production code able to perform its outbound-socket effect, and that name resolves in
  the production tree — or the requirement stops declaring the effect because the product does not
  perform it.
- The provider count reads 9 of 9 named and 9 resolved.
- A requirement declaring an effect with no provider fails the gate rather than being reported and
  carried forward.
- A provider that stops resolving — renamed, deleted, moved out of the production tree — fails the
  same way rather than reverting to unbound.

## Assumptions made writing this

- Assuming the honest answer might be that REQ-016 should not declare the effect, so the deliverable
  is the requirement and the source agreeing rather than a provider found to satisfy the count.
- Assuming resolution stays static over the production tree, as it is for the other eight, rather
  than requiring the socket to be observed opening; that observation belongs to the effect-witness
  rung, not to this gate.
