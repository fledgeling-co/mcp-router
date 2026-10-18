---
status: completed
found-by: `campaign.py check` (test-campaign 0.14.1, full scope), 2026-08-29
---

# An effect class the census cannot name reads as no effect at all

- origin: test-campaign 0.14.1 run against `planning/test-campaign`, full scope · 2026-08-29
- audience: whoever writes a requirement and expects its declared effect to be counted
- platforms: n/a
- proposed-by-ai: true

## What and why

One requirement declares an effect class the census does not recognise. The unrecognised class drops
out of the count rather than failing the run, so the requirement reads as declaring no effect —
indistinguishable from a requirement that promises nothing observable and therefore needs no witness.

The direction of the failure is what makes this worth fixing rather than noting. A counter that
exists to find claims nothing answers is, for this one class, answering "nothing claimed". A typo, a
renamed class, or a vocabulary that moved under the registry all land in the same silent bucket, and
each one removes a requirement from the population of things anybody has to prove.

It is one requirement today, which is the cheapest moment to close it.

## Acceptance sketch

- A requirement declaring an effect class the census does not recognise makes the check red, naming
  the requirement and the class it used.
- The requirement now in that state either declares a class the census knows, or its class is added
  to the vocabulary because it is real.
- The recognised classes are printed where somebody writing a requirement can read them, so the
  correct spelling is discoverable without reading the tool.
- Inventing a class name on any requirement turns the check red, watched rather than assumed.

## Assumptions made writing this

- Assuming an unrecognised class is a mistake to refuse rather than an extension point to allow,
  since the alternative is a vocabulary anybody can silently opt out of.
- Assuming the fix is fail-closed in the census rather than a lint over the registry, so the failure
  arrives on the run that would otherwise have miscounted.
