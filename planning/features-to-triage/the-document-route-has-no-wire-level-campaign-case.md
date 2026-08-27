# The document route has no wire-level campaign case

- origin: the orchestrator, ideating past the surface gaps · 2026-08-27
- audience: Anyone treating the router's HTTP surface as covered by the campaign
- platforms: n/a
- proposed-by-ai: true

## What and why

M30 added a route to the loopback control API that serves a package's own files. The campaign has
cases for the control API and the auth routes on the router-daemon lane, and none for this route.

It is worth its own slice rather than folding into the viewer's, because the two prove different
things and can fail independently. The viewer's case answers "does a person see the document".
This one answers what the campaign asks of every other route: that the refusals are the refusals
the design says, that the caps each name which cap they hit, and — since this route reads files
from disk on a trust boundary — that an attempt to escape the package is refused rather than
served.

M30's build armed the containment check with planted divergences and a verifier attacked it with
twenty-three adversarial references for zero escapes. That is strong evidence and it lives in the
item's own record. What does not exist is a campaign case that re-runs it, so the property is
proved once rather than continuously.

## Acceptance sketch

- The route is enumerated on the lane that observes the router's wire, alongside the other routes.
- A served document returns its content, and the response carries no filesystem path.
- Each refusal is reachable and names which rule it hit: nothing served, too large, outside the
  package.
- A reference attempting to escape the package is refused, and the case is armed so that removing
  the containment check turns it red.
- The case states its oracle rung, and an effect the route performs names its provider.

## Assumptions made writing this

- Assuming this belongs on the wire lane rather than folded into the viewer's surface case,
  because a route can be correct while the panel is wrong and the reverse.
- Assuming re-running the traversal refusal in the campaign is worth its cost, since a
  containment check proved once and never again is the shape this repository has repeatedly
  found rotting.
