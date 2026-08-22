---
status: to-triage
found-by: M20's verifier (F5), 2026-08-23; rescued from a verdict that had no destination for it
---

# `swift build` exits 0 and silent on a fault `xcodebuild` calls fatal

Measured with a **two-way planted control** at tree `1d9ffad`: one fault, and
`swift build --build-tests` exits **0 and silent** while `xcodebuild` exits **65 and fatal**.

The cause is a structural gap in the two build descriptions:

- `app/Package.swift` declares **no target at `MCPRouter/`**.
- `app/project.yml:42-43` does: `sources: - path: MCPRouter`.

So the SwiftPM lane **cannot compile the file this item's assembly lives in.** `swift test` alone
therefore cannot gate an M20-shaped change, and every green `swift test` on a branch that touches
`app/MCPRouter/` is silent about that directory rather than clean over it.

## It is the mechanism behind M18's recurrence, and probably others

M20's verifier names this as the mechanism behind the M18 recurrence, and the fit is exact: M18's
tree had also *never compiled* while its runner reported gates it believed were meaningful. Any item
whose work lands under `app/MCPRouter/` inherits the same blindness.

**So this is the eighth entry in the `instrument that cannot fail` register**, and it is the one with
the widest blast radius, because `swift test` is the gate almost every brief in this fleet names
first.

## Scope

- Decide whether `Package.swift` gains the target or whether `xcodebuild` becomes mandatory for any
  change under `app/MCPRouter/`. The first closes it at the source; the second closes it at the gate
  and costs a slower lane on every item.
- Whichever lands, **`make test`'s own output should say which description it compiled**, because the
  defect is not that a lane is missing — it is that the missing lane reports success.
- Sweep for branches whose green `swift test` covered nothing under `app/MCPRouter/`. M18 and M20 are
  known; nobody has checked the rest.

**Do not close this by adding an `xcodebuild` call without the report line.** A second lane that also
passes silently on a directory it does not read leaves the reader exactly where they started.
