---
status: to-triage
found-by: tailings 0.1.0 over this session's transcript, 2026-08-29
---

# A gate printed a class and the report written after it does not carry the number

- origin: tailings audit of this session's own transcript · 2026-08-29
- audience: whoever reads a progress record and takes it for what the gates said
- platforms: n/a
- proposed-by-ai: true

## What and why

Four times in one session a gate printed a non-zero class and the record written straight
afterwards did not carry it: `unjoined 128` twice, `206 skipped`, and `UNCHECKED 23`. In each
case the gate had already done the work of naming the class and counting it, and the write-up
that a reader would go to instead reported around it. That is the propagation failure the
instrument exists to catch: a figure nobody restates becomes a figure nobody knows, and the
record then reads cleaner than the run it describes.

The same discipline is missing in the other direction three times over: a command exited
non-zero and the claim that followed described the work as clean without naming it. Those three
were conversational rather than written to a file, so they cost less, but they are the same
habit and the same fix — the summary is written from what the writer meant to happen rather
than from what the tool printed.

Worth separating from `the-reckoning-cannot-see-a-merge`, which explains why the unjoined class
is large. This is not about the size of the class. It is about the class disappearing between
the gate and the paragraph about the gate.

## Acceptance sketch

- A record that reports a gate's run names every class the gate printed, and those classes add
  up to the total the gate printed.
- Where a class is deliberately left out, the record says which one and why, so the omission is
  a decision a reader can see rather than an absence they cannot.
- A claim that a step came out clean names any command that exited non-zero on the way to it,
  or says the command was re-run and what it said the second time.
- The four instances from this run are answerable from the record alone: a reader can find
  where 128, 206 and 23 went.

## Assumptions made writing this

- Assuming the fix is a reporting rule that can be checked after the fact, rather than a change
  to any gate's own output — every one of the four gates printed its class correctly.
- Assuming the three unnamed-failure instances belong here rather than in their own brief:
  they are the same practice seen from the failure side, and splitting them would give two
  briefs one habit.
- Assuming a person writes these records, so the outcome is a habit plus something that can
  audit it, not an automated rewriter.
