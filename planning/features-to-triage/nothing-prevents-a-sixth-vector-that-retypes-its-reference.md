---
status: completed
shipped-by: 415b1da
found-by: P9's second gap-fix round, 2026-08-27, handed back rather than built
---

# Nothing prevents a sixth vector that re-types its reference

Five parity vectors have now been found carrying a hand-copy of the reference expression they
exist to pin. A vector that re-types its reference **cannot see that reference drift**, so it
reports the committed corpus as matching while the thing it names has moved.

| # | vector | found by | proved blind by |
|---|---|---|---|
| 1 | `auth-pages` | a verifier | mutating a colour in the built reference; regen stayed 0 |
| 2 | `registry-limit` | P9's own audit | its transcription was the only expectation of that code |
| 3 | `string-ordering` | a verifier, overturning P9's exemption | a `localeCompare` swap; regen stayed 0 |
| 4 | `usage-limit` | a verifier | `?? 200 → ?? 3`; regen stayed 0 |
| 5 | `locale-compare` | P9, confirming the sweep instead of assuming it | swapping the registry comparator; regen stayed 0 |

Each is closed. **The sweep that found them is a snapshot**, and P9 said so plainly rather than
implying otherwise: *"nothing prevents one. The sweep is a snapshot and will need repeating."*

## The shape a fix would take

An out-of-family lane proposed it and P9 judged it the right shape: **every vector block declares a
pin class**, and the class is enforced.

- `src-export` — must import a named production export from `dist/` and carry **no local
  implementation**.
- `platform-builtin` — may only call an allowlisted builtin, because what it pins is the platform's
  own semantics and there is no second copy that can drift. Four vectors are legitimately this:
  `json-roundtrip`, `iso8601`, `js-to-number`, `url-parse`, each computing its expectation live
  from the builtin it pins.
- An **unannotated new vector fails**, so the default is refusal rather than silent admission.

## Why P9 did not build it, and why that judgement was right

Its own words: *"it needs its own `null-run-gate.py` arms, `reader-accounting.py` compliance and
`lint` wiring, and bolting an unproven gate into the lint chain at the end of a gap-fix round is
how a gate ends up reporting success without running."*

That is this repository's most-recorded failure, stated by a runner declining to commit it. The
item is scheduled work, not a line to append.

## Two residuals P9 named and did not close

- Fix 3 shares only the ascending comparison. The `?? ''` coalescing and the descending argument
  flip stay at the registry call site and are **unguarded**. Closing that needs a vector over the
  row comparator with a Swift consumer, which is new surface.
- `searchRegistries`' ordering **as a whole** has no reference-driven vector at all, because no
  generator requires that module for it.

## Scope

- Add the pin-class declaration and enforce it, with its own arms proving the enforcement can fail.
- Classify all existing vectors, and make an unannotated one a failure.
- Decide the two residuals: either cover them or record them as knowingly unguarded.
- The enforcement must itself be armed before it is wired into `lint` — an unproven gate in the
  lint chain is the thing this item is about.
