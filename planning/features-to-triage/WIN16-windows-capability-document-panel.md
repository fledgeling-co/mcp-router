---
status: completed
found-by: intake, parity target for SURF-028 · 2026-08-30
reckon-sources: [SURF-043]
target-note: SURF-043 `Windows capability document panel - three tabs over one package` carries `note: WIN16.`; the row did not exist when the `none` was declared on 2026-08-30.
---
# The Windows capability document panel — three tabs over one package, and the update gate

- origin: owner directive, 2026-08-30; parity target for the Mac capability document panel
- audience: anyone on Windows deciding whether to install or update a capability
- platforms: windows

## What and why

This is the detail surface every other board hands off to. Discover opens it instead of offering an
inline install (WIN7); Skills opens it through `See what changed...` (WIN6); Inbox's review sheet is
its sibling (WIN10). The registry records it as three tabs over one package — the design of record
shows Capabilities, Changelog and Flags worth knowing, across versions.

It also carries **the update gate**, which the mock calls "the heart of the product":

> A new version never applies live: it lands as a shadow copy, the evals re-run against it, and it
> promotes itself only if the capability diff is empty. Most updates are empty and promote silently
> with no notification at all. This one is not, so it stopped and is showing you exactly what grew — 
> the checklist first, because a 400-line diff gets click-through-approved and a four-line capability
> delta does not.

The ordering is the guarantee. **Capability diff before content diff**, because a short list of what
gained access is read and a long textual diff is waved through. A Windows implementation that leads
with the content diff, or shows them side by side with equal weight, loses the property even though
every element is present.

The panel answers "is this version still the thing I agreed to run?", and its named worst state is a
version that grew a capability the user never granted.

## Acceptance sketch

- Three tabs render over one package: capabilities, changelog, and flags worth knowing, with version history across versions.
- When an update is held, the capability delta is shown first and the content diff is subordinate to it, never the reverse.
- A held update states exactly what grew, in the plain-language style the review sheet uses.
- Approving the update promotes the shadow copy; declining leaves the installed version live and the new one not live.
- An update with an empty capability diff does not stop here — it promotes without demanding attention.
- The panel is reachable from Discover, Skills and Inbox and is one surface rather than three near-copies.
- Loading, unreachable-upstream and no-changelog states draw.

## Assumptions made writing this

- Assuming shadow-copy promotion is the router's behaviour and the client shows and confirms it, rather than the client performing the promotion.
- Assuming `GET /servers/:name/document` on the control API is the data source, since a document route already exists.
- Assuming this panel and the Inbox review sheet share their capability-rendering rather than being written twice, since divergence between them is how the plain-language guarantee would rot.
