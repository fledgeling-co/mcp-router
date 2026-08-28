---
status: to-triage
found-by: tailings 0.1.0 over this session's transcript, 2026-08-29
---

# A verification ran in the same model family as the work it was checking, and nothing said so

- origin: tailings audit of this session's own transcript · 2026-08-29
- audience: whoever reads a verdict and takes "reviewed out of family" at face value
- platforms: n/a
- proposed-by-ai: true

## What and why

One verification in this session was routed to a lane in the google family while the session
doing the work was itself running a google model. The point of routing a review out of family
is that every other reviewer in this pipeline is the same model checking its own kind; a lane
that lands back in the writer's family gives up that property, which makes it a degraded
verification rather than a failed one.

The degradation was not recorded anywhere. That is the part that costs something later: this
project has already established the practice that a lane failure or downgrade is logged as a
downgrade rather than silently passed, and a verdict that does not carry its own lane cannot be
weighed by anyone reading it afterwards. A reader would have to compare two model identifiers,
neither of which the verdict prints, to discover that the check was weaker than the label.

## Acceptance sketch

- Every recorded verdict names the model and family that produced it, next to the family of the
  model that produced the work.
- When those two families are the same, the verdict itself says the check was same-family, in
  the place the verdict is read rather than only where it was written.
- Choosing a different family is possible from the record alone — a reader can see which
  families were available and which one was taken.
- The instance from this run either carries the note or has been re-checked in another family.

## Assumptions made writing this

- Assuming the session model was correctly identified as google — the audit read it from the
  session rather than being told, and both identifiers it compared were the same model id.
- Assuming a same-family verdict stays valid-but-marked rather than being discarded, matching
  how in-family fallbacks were handled when the out-of-family lane hit an account limit before.
- Assuming this is one item, not two: recording the family and refusing to pick it silently are
  the same change seen at write time and read time.
