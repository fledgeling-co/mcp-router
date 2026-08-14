# D1 — The deferred register: router side

**Source:** `deferred-plan` = `schedule-all` (confirmed). The owner **chose differently from the
recommendation**: I suggested picking off the handful that are real gaps, and the answer was to
schedule the lot. So this is a batch, not a triage.

Twelve children, all router side. Take them in this order; the first four are real gaps and the rest
are smaller.

| Child | What |
|---|---|
| `D-w1` | Nothing renders `watch.log`, so a server that keeps failing to be adopted is **invisible**. The adoption protocol is the one part of the product with no window onto it |
| `D-w3` | `manifest.json`'s other writers are still unlocked. R2-W closed the seconds-wide window; the **microsecond** one between R3's and R5's writers remains, and it is the harder half |
| `R7` | Skills write endpoint (remove, disable) with preconditions and undo. Cleanup lists absent skills and can offer no action, because the control API is read-only for skills. M7's A16 asserts that gap rather than hiding it |
| `R8` | Server soft-delete with a restore endpoint. Removal is irreversible today, which is why it needs a named-consequence dialog |
| `R6` | Router-side behavioural eval runner, **servers only**. The router can start a server and call a tool; it cannot execute a skill, and a runner promising both would promise something the product does not do |
| `D-h` | Rename `callsServed` to what it measures. It is an **acquisition** counter, not a served-call count, and it is wire-visible, so the client and the Mac surfaces move with it |
| `D-d` | Make caller attribution deterministic rather than `lsof`-raced |
| `D-a` | Record the HTTP status alongside each recorded fixture |
| `D-g` | Parity vectors for divergences D1, D3 and D4. R1 recorded three deliberate divergences with **no vector**, so their absence currently reads as agreement |
| `D-r2r-b` | The control API has never been compared **over a socket**. Eleven `control` rows are proven against an in-process oracle that is not the wire |
| `D-r2r-a` | `mcp-router tools` has no empty state |
| `D-i` | The lost router restart in the TypeScript watcher. Declared so the Swift watcher does not reproduce it; R2-W already diverged deliberately, so **check whether this is now moot before doing anything** |

Two of these overlap the parity work (`D-g`, `D-r2r-b` both move rows), so coordinate with P1 to P4
rather than racing them on the same files.
