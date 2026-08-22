---
status: to-triage
found-by: lukerhodes-2f via M18's gap-fix, 2026-08-23
---

# The design of record cannot draw the state `DESIGN.md` requires of every control

`DESIGN.md` states, in the line every runner is pointed at:

> Every control additionally carries default / hover / focus-visible / active / disabled.

and, two rules earlier:

> Disabled dims in place and never disappears.

`design/mcp-router-console.html` — the design of record, settled 2026-08-22 — cannot draw that
state for a primary button. Verified independently by the orchestrator after
`lukerhodes-2f` raised it:

```
.btn:disabled,.btn.disabled{color:var(--t4);background:var(--f3);box-shadow:none;border-color:var(--line);}
.btn.primary{background:var(--accent-ink);border-color:var(--accent-ink);color:var(--on-accent);}
```

Both selectors are specificity **0-2-0** and `.primary` is declared **second**, so it wins on
`background`, `border-color` **and** `color`. A disabled primary therefore keeps its accent
fill, its accent border and its `--on-accent` label, and differs from a live one only by
`box-shadow: none` — which `:disabled` sets and `.primary` never overrides.

So the state is not merely undrawn. It is drawn **as though it were enabled**, which is the
failure mode `DESIGN.md` names: a control that does not dim, and a user who cannot tell an
unavailable action from an available one.

## Why this is filed rather than fixed in passing

It reaches three items and none of them own it. `M18` hit it building `ProminentButtonStyle`,
whose Swift had the identical defect from the identical cause — a disabled branch that never
reached the accent fill. `M19` and `M22` both ship surfaces with a primary action.
`lukerhodes-2f` has given both the precedent `M18` set so they do not each retake the decision,
but a precedent is not a fix and the mock still cannot be measured against.

It also breaks the measurement chain rather than only the render. `M23`'s conversion is
mock-driven and `mock-fidelity` compares a built surface to the frame the mock draws. A build
that correctly dims a disabled primary would **diverge from the design of record** and be
reported as a finding — so the instrument currently rewards reproducing the defect.

## What triage has to settle

- **The CSS fix is one line** (`.btn.primary:disabled`, or reordering so the disabled rule wins)
  and is the smallest part of this.
- **What "dims in place" means for an accent-filled control** is the real question, and the
  answer belongs in `DESIGN.md` rather than only in the stylesheet — dim the fill, dim the
  label, or both. `--t4` is documented at 3.37:1 / 2.79:1 and exempt **only** under the
  `disabled` role, so whatever lands states its ratio and claims the exemption explicitly.
- **Whether any built surface already reproduces the defect**, having been converted faithfully
  from a mock that carries it. That sweep is the part most likely to be skipped and the part
  that decides whether this is one CSS line or a set of build corrections.

## Do not close this by relaxing the rule

`DESIGN.md:491`'s enumeration is what makes a missing state a finding at all. Deleting
`disabled` from it would make the mock conformant and every affected surface invisible, which
inverts the check — the same shape as deleting a row from a gate table to make an inventory
agree with an implementation (`M29`).
