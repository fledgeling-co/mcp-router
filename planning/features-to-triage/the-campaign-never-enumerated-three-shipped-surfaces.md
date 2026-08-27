---
status: to-triage
found-by: the orchestrator, 2026-08-27, asked whether the campaign covers every surface
---

# The campaign never enumerated three surfaces that shipped

`campaign.py check` exits 0 over "24 enumerated, 0 with no case". That number is true and it is
the wrong denominator: **the campaign's surface list has not grown since the surfaces it names
were written.** Three shipped surfaces are absent from it entirely, so they cannot appear as
uncovered — there is no row for them to be uncovered *in*.

This is the skill's own first failure mode, quoted from its header: *"Covering a subset and
reporting it as the whole … a denominator would have shown `1/6` on sight."*

## The measurement

`Destination.swift` ships **nine** destinations. The campaign's surface titles name **seven** of
them:

| Destination | Campaign surface |
|---|---|
| activity, servers, skills, discover, inbox, evals→Checks, cleanup | SURF-002 … SURF-008 |
| **harnesses** | **none** |
| **insights** | **none** |

And the capability-document viewer — M19's renderer, M30's route — has no surface either. Probing
every surface `title` and `name` in `inventory.json` for `readme`, `document`, `capability` and
`markdown` returns **NO** on all four.

The three absent surfaces are not unbuilt. Each is measured *against the mock* by
`mock-fidelity`, which carries `planning/fidelity/harnesses.layers.json`,
`insights.layers.json` and `readme.layers.json`. So the build is compared to its design of
record on those surfaces, and **no case in the on-glass campaign ever opens them, actuates them,
or photographs them.** Structure is checked; behaviour and flow are not.

## Why the gate could not say so

`campaign.py check` reads the surface inventory and asks which of *those* surfaces has no case.
Every one of the 24 has at least one, so it reports clean. The check is correct; its input is
the thing that went stale. A surface that was never enumerated is invisible to a completeness
check keyed on enumeration, which is the same shape as `M32`'s census defect — an element
outside every rule cannot be reported by a gate that reports by rule.

**The distinguishing test for triage:** the campaign's surface list should be derived from, or
reconciled against, the product's own destination enum and sheet inventory, rather than
hand-maintained. `M32` solved the analogous problem for mock elements by making the census total.

## What is NOT a gap, recorded so triage does not chase it

Three requirement rows look like holes and are honest records of product state:

- **`REQ-015`** (pairing sheet shows a code and QR) carries two FAILs. The build genuinely ships
  no pairing transport — `InboxCopy.noEndpointTitle` is *"Pairing is not available in this
  build"*. `DEF-001`. The FAILs are the correct verdict and stay until the feature ships.
- **`REQ-016`** (a pairing exchange actually contacts the other device) is recorded
  `contradicted` with `effect: outbound-socket` and **no provider in production source**. The
  vacuity check flags it, correctly: there is no provider because the feature is unimplemented.
  Recording it as contradicted is the honest form.
- **`REQ-020`** (`install.sh` flips to the Swift binary) is `class: deferred`, pending the owner's
  parity cutover decision at 82/83. It has no case because it has no build.

## The one real requirement gap, and it is a harness limit

**`REQ-008`** — the menu-bar popover's readout, attention rows and inbox band — has two cases and
**neither passes**. Both are `n/a`, and four cases across the campaign are `n/a` for one cause:
`NSStatusItem` is not an `AXPress` target while the app is backgrounded, and
`planning/practices/UI_VERIFICATION.md` rule 1 forbids the harness taking the screen.

So a whole shipped surface is unreachable by construction, and the campaign says so rather than
pretending otherwise, which is right. What it has not done is decide whether that is permanent.
The options are an opt-in lane that *does* activate and is run deliberately when nobody is at the
machine, a different actuation path that does not require frontmost, or a recorded decision that
this surface is proved by unit and fidelity lanes alone and never on glass.

## Scope

- Enumerate `harnesses`, `insights` and the capability-document viewer as campaign surfaces, and
  write and **run** cases for each on the lanes that can observe them. A case written and not run
  is the paper-campaign failure this skill exists to prevent.
- Give each a flow where one exists — the document viewer in particular has a real one
  (open a capability → read its README → follow to changelog) that no `FLOW-*` covers.
- Reconcile the surface list against `Destination.swift` mechanically, so the next shipped
  destination cannot be absent from the denominator.
- Decide `REQ-008`'s status: opt-in activating lane, alternative actuation, or a recorded
  limitation with the reason.
