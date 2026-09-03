---
status: to-triage
found-by: intake, reading src/ for platform assumptions while scoping the Windows client · 2026-08-30
registry-target: none
no-target-reason: the registry has since gained SURF-045 (the daemon's Scheduled Task) and REQ-035, so the original reason - that no case exercises the daemon on Windows - is no longer true of supervision. It remains true of this brief's subject: no registry entity records the daemon's macOS-shaped path, signal and process assumptions in src/, which is what this brief is about and which SURF-045 does not cover. Corrected 2026-09-03, we4.
---
# The router daemon assumes macOS in at least five places, and contains no platform branch at all

- origin: intake, 2026-08-30, reading `src/*.ts` while scoping the Windows client
- audience: every Windows client brief, all of which talk to this daemon
- platforms: windows, router

## What and why

The Windows client's entire contract is the loopback control API, so the daemon has to run correctly
on Windows before any Windows surface means anything. It does not today. Measured by reading
`src/*.ts` on 2026-08-30:

- **`grep -n "process.platform\|win32\|os.platform" src/*.ts` returns nothing.** There is not one
  platform branch in the router. Every platform-specific decision is therefore unconditional.
- **`src/index.ts:376` at `5ea32650` calls `execFile('/usr/bin/open', [body.authorizationUrl])`** to open the
  browser for an OAuth authorization URL. That path does not exist on Windows, so OAuth sign-in
  fails at the last step — and it fails in a callback that ignores its error, so it fails silently.
  This is the sharpest of the five: the `needs sign-in` state on the Servers board would be
  unrecoverable on Windows.
- **launchd is the supervisor throughout.** `src/index.ts`, `src/pool.ts`, `src/router.ts` and
  `src/livereload.ts` all reason about launchd's KeepAlive, the launchd config watcher, and a
  deliberate non-zero exit whose purpose is to make launchd restart the job. Windows has no launchd;
  the restart guarantee those comments depend on simply is not there.
- **`src/lock.ts` uses `LOCK_EX | LOCK_NB` advisory locking**, with its behaviour documented as
  measured on `darwin`. Windows file locking is mandatory rather than advisory and behaves
  differently on the paths that matter here.
- **`src/sessions.ts` reads sockets under `/tmp/cc-socks`.** There is no `/tmp` on Windows.

`ROUTER_HOME` is the one that is already fine: `join(homedir(), '.claude', 'mcp-router')` resolves
correctly on Windows.

This is a router brief rather than a client brief, and it is a precondition for the rest. It is
listed here because it was found while scoping the Windows client and would otherwise be discovered
by whoever built the first Windows surface and could not sign in.

## Acceptance sketch

- The router starts, serves the control API, and spawns and reaps stdio upstreams on Windows.
- Opening an OAuth authorization URL works on Windows, and a failure to open it is reported rather than swallowed.
- The supervision guarantee launchd provides has a named Windows equivalent, or the guarantee is explicitly restated as weaker on Windows.
- Single-instance locking holds on Windows, with its behaviour measured rather than assumed from the darwin measurement.
- Session discovery works on Windows or reports honestly that it cannot, rather than reading an absent path as an empty result.
- Where behaviour differs by platform, the difference is a branch that is visible in the code, not an accident.
- The TypeScript reference parity harness position is stated: whether Windows behaviour is in its corpus, or deliberately out.

## Assumptions made writing this

- Assuming the five findings above are the ones that block, not the complete set; they came from reading rather than from running, since the router has never been started on this machine.
- Assuming the router runs as a user-level process on Windows rather than a system service, which WIN23 revisits.
- Assuming the control API's shape does not change for Windows, so the client contract stays one contract.
