---
status: completed
shipped-by: 08b9bdf
---

# M13 — The scroll-edge separator, A34

**Source:** `red-checks` = `all-three` (confirmed, accepted recommendation).

`scripts/acceptance/mac-shell.sh` exits 1 at A34: *"the top row is not one colour once scrolled
(`#2F2F2F` covers 0.707) — that is content, not a separator"*. This is the **only genuinely red
product check on main**.

It was unreachable until M11, because A22 was failing ahead of it and stopped the run. Revealed, not
caused, by M11: its diff over `ScrollEdge.swift`, `ShellWindow.swift` and `Boards/` is empty, verified
by the orchestrator.

The mechanism is the one the script's own comment predicted. A34 is driven on Servers as "the first
destination still using the shell's scroll view", and M6 landed the eighth board, so its rows now
scroll under the sampled row.

**The diagnosis is not settled and that is the first job.** Whether the separator is broken or the
check samples the wrong row are indistinguishable from the failure message. Settle it before fixing
anything; if the check is wrong, change the check and say so.
