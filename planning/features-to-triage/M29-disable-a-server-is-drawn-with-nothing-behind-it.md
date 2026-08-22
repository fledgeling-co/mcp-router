---
status: to-triage
found-by: M18's runner, 2026-08-22
---

# "Disable a server" is a gate-table row with no action behind it, and no owner

M18 inventoried every sheet in `design/mcp-router-console.html` and built the gate each
destructive decision passes through. One row of that table has no implementation anywhere and
no item claiming it.

**The measurement.** `ServerPatch` carries no field that disables a server. The control API's
PATCH is the only channel the Mac app has — `command`, `args` and `env` are never writable
through it by standing constraint — and nothing in it expresses *present but not served*. No
ledger row claims the behaviour: it is not R7's, not R16's, not M22's, and M18 declined to
invent it rather than shipping a control that does nothing.

**Why this is not simply "build it".** Disabling a server is a third state between adopted and
removed, and the product currently has two. The router either serves a server's tools or does
not know about it. A third state has to answer questions nobody has answered:

- Does a disabled server keep its manifest row, its digest and its approved tool set? If it
  does, `R18`'s failed-index handling and `R20` both write that row and need to agree with it.
- Does `unionTools` skip it by a new `disabled` flag, or by the same emptiness test that
  `R18`'s verdict has just established is doing a job the error field should do? Adding a third
  reason for a server to serve nothing, into a function that currently infers the reason from
  the data's shape, is how that defect got there.
- Is it per-harness or global? The owner has just decided the product works **per-project**, so
  a server disabled in one project and live in another is now expressible and probably
  intended.

**What this item is.** Not a build order — a decision plus the build that follows it. The
sheet is drawn, so the design has already implied an answer; whoever triages this should read
what the mock draws and say whether that is the intended semantics or an artifact of drawing a
plausible-looking table.

**Do not close this by removing the row from the gate table.** The table is generated from the
sheets that exist in the design of record, and deleting a row to make an inventory agree with
an implementation is the inverse of the check.
