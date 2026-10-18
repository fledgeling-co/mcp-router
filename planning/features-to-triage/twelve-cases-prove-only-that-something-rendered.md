---
status: completed
found-by: `strict-check.py` (test-campaign 0.14.1), 2026-08-29
---

# Twelve cases prove only that something rendered, and they are the movable part of the remainder

- origin: test-campaign 0.14.1 run against `planning/test-campaign`, full scope · 2026-08-29
- audience: whoever reads the checked percentage and takes it for behaviour that was proved
- platforms: n/a
- proposed-by-ai: true

## What and why

`strict-check.py` reports 91 of 114 cases checked, 80%, with the ratchet at 91 and holding. Of the 23
that are unchecked, 7 are status fail and 4 are n/a — the failures are defects somebody already owns
and the n/a cases are genuinely out of scope. The other **12 are unchecked because they prove only
that something rendered**.

The strict floor is doing its job here: it declines to count them, so the 80% is honest. What the
number does not say is that a fifth of the campaign's cases are held out and twelve of them are held
out for a reason that is fixable rather than for a reason that is a defect. A case that establishes an
element exists passes whether the element does anything, which is the same tautology the control
census is stuck behind on the actuation side — and unlike the failing seven, these twelve are cases
where somebody already decided the behaviour was worth covering and then covered the wrong thing.

Raising them is the only path by which the checked count moves without a defect being fixed first.

## Acceptance sketch

- Each of the twelve either reads a state its subject would have to change for the case to be true, or
  is retired because another case already covers that behaviour properly.
- The checked count rises from 91 and the ratchet rises with it.
- Each raised case is watched failing when the behaviour it names is broken, rather than assumed to
  discriminate.
- The 7 failing and 4 n/a cases stay out of the count, and none of them is relabelled to make the
  number move.
- A newly written case that proves only that something rendered still lands unchecked rather than
  being counted.

## Assumptions made writing this

- Assuming a case that is really about presence is retired or absorbed rather than padded with an
  assertion invented to clear the floor, since the floor exists to detect exactly that.
- Assuming the twelve can be raised without touching the seven failures, which belong to whoever owns
  those defects.
- Assuming the ratchet is allowed to rise as they land rather than being set to the finished number in
  advance.
