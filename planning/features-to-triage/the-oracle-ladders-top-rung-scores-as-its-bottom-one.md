---
status: to-triage
found-by: reckon 1.7.0, 2026-08-29
---

# The oracle ladder's top rung is scored as its weakest, so the gate penalises the hardest evidence

- origin: reckon 1.7.0, `DEF-053` · 2026-08-29
- audience: whoever decides which evidence is worth buying, and reads the strictness gate to find out
- platforms: n/a
- proposed-by-ai: true

## What and why

Two scripts in the same campaign version disagree about which oracle rungs assert an effect, and both
carry a comment claiming to define it. One lists the effect-witness rung among them; the strictness
check omits it, and its comment ends by pointing at the file it contradicts. The result is that the
campaign's four effect-witness cases — its most expensive evidence, each carrying an independent
kernel recorder — score as though they only prove something rendered.

The direction is what makes this worth scheduling. A gate that undercounts the strongest rung is not
merely inaccurate: it pays less for harder work, so the cheapest way to raise the score is to stop
buying the evidence that costs most. That is the incentive this whole ladder exists to prevent.

The defect is recorded as fixed upstream and awaiting a re-pull, which is the disposition rather than
the work. The work is that two definitions of the same concept lived in one version and neither gate
noticed the other.

## Acceptance sketch

- The rungs that assert an effect are defined once, and every gate that scores evidence reads that one
  definition.
- A case at the effect-witness rung scores as the effect it proves, so the strictness figure reflects
  what the campaign actually bought.
- Two gates in one version disagreeing about a population is itself a failure, rather than something
  found by reading both.
- The re-pull that carries the upstream fix is taken, and the strictness figure is re-derived
  afterwards rather than carried.

## Assumptions made writing this

- Assuming this is distinct from the two existing upstream detector briefs: those cover artifacts that
  under-report and detectors that misattribute, and this is a gate that mis-scores.
- Assuming the fix belongs upstream in the campaign skill and reaches this repository as a version
  bump, in the same way as the other detector defects.
