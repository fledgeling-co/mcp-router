---
status: to-triage
found-by: reckon 1.7.0, 2026-08-29
---

# Observe a delivered banner, and observe it being withdrawn

- origin: reckon 1.7.0, `REQ-009` standing on the project's own word · 2026-08-29
- audience: whoever needs the inbox's notification contract checked rather than described
- platforms: mac
- proposed-by-ai: true

## What and why

The product promises that disposing of an inbox item immediately withdraws its notification banner, and
that a multi-item banner carries a Review affordance only. That promise carries evidence `reported`:
the project's own account of itself, never watched.

It is unobserved because it is genuinely hard to observe. A banner lives outside the app's own window,
it is transient, and the interesting half is a **disappearance** — proving that something stopped being
shown is not the same shape of check as proving something is drawn. The capability worth buying is the
ability to see what the system is currently presenting on the app's behalf, and to see it change.

That instrument is not only for this promise. Anything the product asserts about what a person is shown
while the app is in the background rests on the same missing ability.

## Acceptance sketch

- A delivered notification can be observed from outside the app, including what affordances it carries.
- Disposing of the item is shown to withdraw its banner, with the withdrawal itself recorded rather
  than inferred from a later absence.
- A banner covering several items is observed carrying Review and nothing else.
- A run where a banner outlived its item fails, instead of passing because nobody looked.

## Assumptions made writing this

- Assuming the check watches the system's presented notifications rather than the app's internal
  intent to post one, since the promise is about what a person sees.
- Assuming this is separate from the menu-bar popover's testability, which is already filed: the
  popover is a surface that cannot be opened, and this is a banner that cannot be watched.
