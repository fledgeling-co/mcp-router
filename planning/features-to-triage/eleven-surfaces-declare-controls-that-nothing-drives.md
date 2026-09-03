---
status: to-triage
found-by: `campaign.py check` (test-campaign 0.14.1, full scope), 2026-08-29
---

# Eleven surfaces declare their controls and no passing case drives one of them

- origin: test-campaign 0.14.1 run against `planning/test-campaign`, full scope · 2026-08-29
- audience: whoever needs a green campaign to mean the buttons work, not that they draw
- platforms: n/a
- proposed-by-ai: true

## What and why

The control census now has a denominator and it has no numerator. Eleven surfaces declare the
controls they carry, and **no passing effect-rung case actuates any of them**: SURF-001 declares 20
and 0 are actuated, SURF-002 declares 23 and 0, SURF-004 declares 21 and 0, and eight more surfaces
read the same way.

This is the inert-UI signature. A control renders, carries its accessible name, satisfies a contrast
gate and accepts a click whether or not its handler does anything, so every check the campaign
currently runs over these surfaces passes identically on a working board and on a board of dead
buttons. The failure mode is documented rather than hypothetical: a campaign once reported 32 of 32
passing over an app whose every button ran an empty closure.

An earlier brief asked for the declarations, and they exist now — that half landed. What it bought
was the ability to see the hole rather than the hole itself, which is the whole point of a
denominator and is also why this is worth picking up rather than filing as satisfied. Sixty-four
declared controls on the three named surfaces alone have never been shown to do anything.

The expensive part is not the clicking. It is that actuation only counts when the effect is read
somewhere other than the control that was struck — a button whose proof is that the button now looks
pressed is the same tautology one level in.

## Acceptance sketch

- Every control declared on the eleven surfaces is either driven by a passing effect-rung case or
  carries a stated reason it cannot be, so nothing sits in the denominator unexplained.
- The census reports a non-zero actuated count per surface, and the three named surfaces move off
  zero first.
- Driving a control is proved by reading the state it was supposed to change through a channel other
  than the one that struck it.
- Replacing one real handler with an empty closure turns the case that covers it red, watched rather
  than assumed.
- A control whose only promised effect is navigation or a message is recorded as that, rather than
  counted as actuated on the strength of the click landing.

## Assumptions made writing this

- Assuming this is one unit of work despite spanning eleven surfaces, because what is missing is an
  actuation-and-read-back path rather than eleven unrelated cases; triage may still split it per
  surface if the read-back channel differs between them.
- Assuming the fix raises the numerator rather than trimming the declared lists, since a control
  removed from the denominator is a control nobody will ever ask about again.
- Assuming the declarations themselves are correct, having come from the design of record, so a
  control the build never drew surfaces here as an unactuatable entry rather than as a bad list.


---

## WE3 ADJUDICATION, 2026-09-03 — **neither (A) nor (B): naming `campaign.py` here names the FINDER, not the fix.**

This row was scheduled among fifteen that name a script this fleet may not edit. Its
`found-by` is `campaign.py check`, and that is the whole of its connection to a vendored script.
Nothing about the finding is a defect in the instrument: the census is right, the denominator is
right, and the numerator is genuinely zero. `campaign.py` measured the product correctly and the
product is what is short.

**The work is product work in this repository, and it is large.** The acceptance sketch asks for
an actuation-and-read-back path per control across eleven surfaces, where actuation only counts
when the effect is read through a channel other than the one that struck the control, plus a
mutation arm (replace one handler with an empty closure and the covering case must go red). That
is a wave's worth of case-building, not an adjudication, and building it was not this runner's
assignment.

**One thing measured here that bears on it, and cuts the wrong way.** The effect-witness rung is
where read-back-through-another-channel is recorded, and **31 of the 49 cases that name a
`witness.effect` name a class the census cannot recognise** — 25 of them `machine-state`, and
several of those record their recorder as *"the router's own /servers listing, read over the
control API"*, which is a channel **inside** the product. So some of the actuation evidence this
brief would be closed by already exists in a form that does not yet satisfy the rung's own rule
about an independent recorder. Filed as **DEF-502** with the roster; adjudicating those 31 against
`references/effect-boundary.md` is a prerequisite for counting them toward this brief's numerator,
not a separate chore.

No status change and no work claimed. Recorded so the next runner does not spend the first hour
establishing that this row is not blocked on a vendored script.
