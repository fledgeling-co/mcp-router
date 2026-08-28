---
status: to-triage
found-by: reckon 1.7.0, 2026-08-29
---

# Drive every data surface off its happy path, and read what it actually offers

- origin: reckon 1.7.0, `REQ-017` (evidence `unknown`) and `REQ-018` (evidence `reported`) · 2026-08-29
- audience: whoever meets one of these surfaces on a bad day
- platforms: mac
- proposed-by-ai: true

## What and why

Two promises about the unhappy path have no observation behind them, and one of them has no evidence of
any kind. `REQ-017` — every data surface ships the nine specified states with real copy on the unhappy
paths — carries evidence `unknown`, the only requirement in the reckoning that does. `REQ-018` — undo
is the contract for reversible acts, and a named-consequence dialog is reserved for genuinely
destructive ones and is never the default — carries the project's own word.

They are one capability because they are answered by the same act: **put a surface into a state nobody
reaches by using the app normally, and read what it draws and what it offers.** The nine states are
what it draws; the undo-versus-dialog contract is what it offers when the person acts. An instrument
that can reach an error, an empty, a loading or a degraded state answers both, and answers the next
promise of this kind without being rebuilt.

A categorical promise is the kind that is satisfiable by one instance, so the thing to record is the
fraction: which surfaces, in which states, with copy written for that surface rather than a shared
line that says nothing.

## Acceptance sketch

- Each data surface can be driven into each of its specified states on demand, and what it draws there
  is recorded per surface rather than in aggregate.
- Copy on an unhappy path is checked as being written for that surface, so a shared placeholder does
  not count as the state being shipped.
- The reversible acts are enumerated, and each is observed offering undo rather than a dialog.
- Each named-consequence dialog is observed being reserved for something genuinely destructive, and
  never standing in for an undo.
- `REQ-017` gains evidence of any kind, and `REQ-018` stops standing on the project's own word.

## Assumptions made writing this

- Assuming the fraction is the deliverable rather than a pass or fail, since a categorical promise
  reads as satisfied the moment one instance exists.
- Assuming this is evidence work rather than build work: the states were delivered by an earlier item,
  and what is missing is anybody having watched them.
- Assuming the two promises share an instrument rather than being scheduled apart, because reaching
  the state is the expensive half and both need the same reach.
