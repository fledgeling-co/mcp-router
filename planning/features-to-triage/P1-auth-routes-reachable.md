---
status: completed
shipped-by: 496f88c
---

# P1 — Make the two auth routes reachable, and retire the stale defect assertions

**Source:** `mcp-router-status-answers.json`, question `cutover` = `finish-first` (confirmed, own choice).
The owner chose to finish the comparison before switching, so every parity row now has a name and an owner.

`AuthRoutes.approve` and `AuthRoutes.authStart` are both implemented and both unreachable over the
wire: `ControlHandler`'s dispatch never routes to them, so they answer 405 where the reference
answers 409 and 400. Registered as `D-j`. **Blocks 2 parity rows.**

Fixing it also retires `control-differential.sh`'s known-defect assertions for those two routes
(`D-r2r-c`) in the same change. Do both together or the differential goes red on a defect that has
just been fixed, which is the worst kind of red.

**Done means:** both routes reachable over a real socket, the differential's stale assertions gone,
and the parity gate's proven count risen by 2 measured from the same directory before and after
(`D-o` makes the figure depend on the directory name).
