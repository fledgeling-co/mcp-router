---
status: to-triage
found-by: M38's runner, 2026-08-29, while shipping the staged tool diff's decision
reckon-sources: [REQ-006, CASE-0284]
---

# The phone can be told a tool surface changed, and there is no honest way for it to accept one

M38 shipped four of its brief's five acceptance lines. The fifth — *mobile companion clients
receive notification of pending tool diffs and can review changes remotely* — is filed here
rather than built, and the reason is a standing constraint rather than an estimate.

## The measurement

`ORCHESTRATOR.md` records the constraint as **the phone queues; it never installs — deliberately
narrower than "remote install"**, and `REQ-006` is the honesty guardrail that carries it: *no path
from the phone or a notification can put a server on the Mac without explicit human review there.*

Approving a tool surface is not a queued suggestion somebody later acts on at the Mac. It is a
write that changes what **every attached session is served**, measured at 11 milliseconds in
`scripts/e2e-live-reload.mjs` (`CASE-0284`) — so a phone that could approve would be a phone that
can change what a model reads mid-turn, from a device that cannot reach the router's loopback
control API and whose only channel to the Mac is the pairing transport.

That is a new capability class with its own trust boundary, and it is the exact shape `REQ-006`
exists to refuse. Inventing it inside a review-surface item is how a control that does nothing —
or worse, a control that does something nobody sanctioned — gets shipped.

## What this item is

A decision before it is a build, in M29's shape. Whoever triages it has to answer:

- **Does the phone review, or only get told?** Being shown the diff and pressing *Approve on the
  Mac* is expressible inside `REQ-006` today. Approving from the phone is not.
- **If it approves, what carries the authorisation?** The pairing record establishes that two
  devices met; it does not establish that this write was reviewed by a person. `M6`'s inbox
  round-trip is the nearest prior art and it queues.
- **What does the phone show when it cannot read the schema?** `SchemaDiff` is Mac-side and its
  card is `#if os(macOS)`. A phone that renders the description half only would reproduce exactly
  the defect M8 fixed — a review surface that manufactures the appearance of review.

## Do not close this by drawing the screen

The iOS app has no held-change surface at all, so there is no row to delete and nothing to make
consistent. What would make this worse is a phone sheet that shows a diff and hands the decision
back to the Mac while looking like it took it.
