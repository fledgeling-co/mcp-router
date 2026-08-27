---
status: completed
shipped-by: 8cfb9e3
---

# G1 — Stop the checks blaming the app for being out of date

**Source:** `red-checks` = `all-three` (confirmed).

Measured by the orchestrator on 2026-08-15: seven of eight acceptance checks came back red on a clean
main, and **six went green after a rebuild with no source change at all.** Three of them said a screen
"is not built" when the screen is built and the build was simply old. That is a stale build reported
as a product defect, and it is the single most time-wasting thing in this repository.

Three pieces:

1. **`D-m11-a`** — M11 added a freshness check to `mac-shell.sh` and it is the only honest one, but it
   compares **source mtimes** to the built app. A rebase rewrites mtimes without changing content, so
   `xcodebuild` correctly skips relinking and the check blocks **permanently**; `make build-mac`
   exiting 0 does not clear it. Only deleting the derived product and rebuilding does. Rebase-then-gate
   is the orchestrator's standard cycle, so this blocks every merge. **Compare content, not mtime.**
2. **Give every acceptance script the same guard.** One honest check and six misleading ones is worse
   than none, because the six teach the reader to distrust a real red.
3. **`D-i2-guard`** — `i2-phone-discover.sh` greps for `PhoneShell.Tab.awaitingKey`, which I3
   deliberately removed when the last tab shipped and the phone placeholder stopped existing. The check
   fails honestly ("treat as a broken reader, not a pass"), which is correct behaviour; it just needs
   repointing, the way the Mac tripwires were repointed when the eighth board landed.

**Done means:** a stale build blocks with a named reason on every script, a rebase does not produce a
permanent block, and the phone browse guard reads something that exists.
