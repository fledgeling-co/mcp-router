---
status: to-triage
found-by: reckon 1.7.0, 2026-08-29
---

# A stale incremental build fabricates test failures, and can as easily fabricate a pass

- origin: reckon 1.7.0, `DEF-035` · 2026-08-29
- audience: whoever takes a suite result as evidence, and anyone reviewing a change that adds an enum case
- platforms: mac
- proposed-by-ai: true

## What and why

Adding a case to an enum made the suite fail with issues that cannot be true of the source — two of
them assert a guard that returns the same value unconditionally. Stashing the changed files made them
pass; unstashing brought them back, which reads exactly like a real regression. It is not one. A
choice is encoded in the spare inhabitants of the enum's tag, so adding a case shifts that encoding,
and object files compiled against the old layout compare a value that no longer means what they think.
Deleting the build directory and rebuilding passes cleanly.

The failing direction cost a diagnosis. The other direction is the reason this is worth scheduling:
**the same staleness can produce a green**. Any test evidence taken across a change of this shape is
untrustworthy in both directions, and nothing currently distinguishes a suite result taken on a clean
tree from one taken over stale objects. A campaign that treats a suite run as evidence has no way to
tell which it is holding.

## Acceptance sketch

- A suite result records whether it was produced from a clean build, and a result that was not is not
  usable as evidence.
- A change that alters a type's layout invalidates the artefacts compiled against the old one, rather
  than leaving it to whoever notices impossible failures.
- The impossible-failure case reproduces on demand, so the guard against it can be watched failing.
- A green suite taken over stale objects is refused for the same reason a red one is disbelieved.

## Assumptions made writing this

- Assuming the remedy is to make staleness visible to whoever reads the result, rather than forcing a
  clean build on every run, which would be correct and unaffordable.
- Assuming the existing in-campaign mitigation is a stopgap that covers the enum case specifically,
  and the general property is what is missing.
