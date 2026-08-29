---
status: to-triage
found-by: intake divergent pass, from launchd having no Windows counterpart in the router · 2026-08-30
registry-target: none
no-target-reason: SURF-015 records the daemon and pool as measured under launchd on macOS, and no case in the registry covers how the router starts or is supervised on Windows
---

# What starts the router on Windows, and what restarts it when it dies

- origin: intake divergent pass, 2026-08-30
- audience: anyone on Windows whose agents expect the endpoint to be there
- platforms: windows, router
- proposed-by-ai: true

## What and why

The router's value is that harnesses point at one endpoint and it is always there. On macOS launchd
provides that: it starts the job at login, restarts it under KeepAlive, and watches the config file
for changes. WIN17 records that the router's source reasons about launchd in four files, including a
deliberate non-zero exit whose entire purpose is to make launchd restart the job.

Windows has no launchd, and the substitution is a real choice rather than a lookup, because the
candidates differ in what the user has to have and what they can see:

- **A Windows Service** gives true machine-level lifecycle and restart-on-failure, but installing one
  needs administrator rights and it runs outside the user's session — which is wrong for a daemon
  whose job includes opening a browser for OAuth (see WIN17) and reading per-user harness configs.
- **A Scheduled Task at logon** runs in the user's session and needs no elevation. Restart-on-failure
  is weaker and its stdout is lost, which makes diagnosing a crash harder.
- **A startup entry, or the client supervising the daemon itself**, is simplest and ties the router's
  life to the client's — which changes the product, because today the router serves harnesses whether
  or not anybody has the app open.

The last point is the one to decide first, because it is a product question wearing an
infrastructure question's clothes: does the Windows router run when the client is closed? On macOS
it does. If it does not on Windows, that is a parity gap that no surface brief would reveal.

The config-watching behaviour needs an answer too. Whatever replaces the launchd file watcher has to
notice a config change, and `src/livereload.ts` already reasons about manifest writes arriving from
other processes.

## Acceptance sketch

- The router starts without the user launching it by hand, and the mechanism is named with what the alternatives would have been better at.
- It keeps running when the client is closed, or the decision that it does not is explicit and recorded as a parity gap.
- It restarts after a crash, and the restart guarantee is stated honestly — including if it is weaker than launchd's.
- A config change is noticed without a manual restart.
- Installation does not silently require administrator rights; if it does, the user is told why.
- Logs go somewhere a user can find, since a scheduled task's stdout is otherwise lost.
- Stopping and disabling the router is possible without editing files by hand.

## Assumptions made writing this

- Assuming the router should outlive the client on Windows as it does on macOS, since that is what "one endpoint that is always there" means; the brief asks for the decision to be explicit rather than presuming it.
- Assuming a per-user rather than machine-wide install, matching how harness configs are per user.
- Assuming this is separable from WIN19's packaging question, though the two will be decided together in practice.
