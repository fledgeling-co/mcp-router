---
status: to-triage
found-by: `campaign.py check` (test-campaign 0.14.1, full scope), 2026-08-29
reckon-sources: [REQ-016]
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


---

## WE3 ADJUDICATION, 2026-09-03 — **(B). The fix was in this repository's registry, the reported state is closed, and the mechanism is worse than the brief knew.**

This is the row the wave's brief named as the clearest candidate for (B), and it is — with a
larger finding underneath it.

### The reported state is closed, measured rather than assumed

All **44** requirements declare an `effect`, and **0** declare one outside `campaign.py`'s
`EFFECT_CLASSES`. REQ-016, which this brief was filed against, declares `outbound-socket`, which
is in the vocabulary; its remaining finding is a missing *provider*, not an unrecognised class,
and that is `effect-provider-gate.py`'s axis and DEF-440's. `vacuity-check.py --gate` on this tree
reports `uncensused: examined=17 findings=1`, and the one finding names REQ-016 by name. Same
vocabulary in the pinned 0.9.2, in 0.16.0 and in 0.17.0 — nine classes, identical tuples — so this
is not a version's accident.

### The direction of the failure, watched rather than described

The brief's first acceptance clause asks that inventing a class name turn the check red, *watched
rather than assumed*. Planted `outbound-sockett` — one letter — on REQ-016 and ran the pinned
instrument:

```
vacuity-check.py --gate, before:  uncensused: examined=17 findings=1   (REQ-016 named)
vacuity-check.py --gate, after:   uncensused: examined=16 findings=0   (clean)
```

The typo produced no finding. It removed a requirement from the population anybody has to prove
and the census went **greener**. That is exactly the direction the brief predicts and it is now on
the record with the numbers. `campaign.py check` does catch it — `1 requirement(s) declaring an
effect class the census does not recognise` — which is worth knowing and is not the enforcement,
for the reason this repository already wrote down for `raster-claim-gate.py`: `campaign.py` is not
in `make lint`, and a rule enforced only in a shared plugin cache leaves with the cache.

### Armed, in `make lint`

`planning/effect-class-vocabulary-gate.py`. R1 blocks on requirements — watched red on the planted
letter, green on revert, transcript at
`planning/evidence/WE3/effect-class-vocabulary-gate.baseline.txt`. The vocabulary is parsed out of
the pinned `vendor/test-campaign/.../campaign.py` under a recorded SHA-256 rather than copied into
the gate, so this file cannot become a third vocabulary able to drift from both; a re-vendor that
moves the tuple exits 2 NOT COMPARED. The brief's third clause — that the recognised classes be
printed where somebody writing a requirement can read them — is answered by the gate printing all
nine on every run, clean or not.

### The finding underneath: it was never one requirement

The requirement axis is clean. The **case** axis was never counted: **31 of the 49 cases naming a
`witness.effect` name a class the vocabulary does not carry** — `machine-state` ×25, `file` ×2,
and `os-record`, `process`, `notification`, `ui-state` — every one of them `effect-witness · pass`.
`campaign.py:702` at `5934c38f` does check that field, and its report folds all 31 into a line reading `40
effect-witness claim(s) with no recorder, no effect class, or a count of zero`, then caps the
detail at twelve lines which are twelve lines about four other cases. **Not one of the 31 is
printed anywhere.**

They are deliberately not remapped. Some are a rename (`process` over `Get-ScheduledTaskInfo` is
`subprocess`); some are a harder question a rename would bury (`machine-state` over *"the router's
own /servers listing, read over the control API"* is a recorder **inside** the product, so whether
that case belongs at `effect-witness` at all is a judgement about the case). Picking the nearest
legal spelling for all 31 would turn 31 rows green while answering neither question. Filed as
**DEF-502**; R2 of the gate is a ratchet holding the exact roster, so a 32nd row fails and an
adjudicated row lowers the floor.

Status word not changed: DEF-502 is open and the brief's second clause ("the requirement now in
that state either declares a class the census knows, or its class is added because it is real") is
answered for requirements and open for cases.
