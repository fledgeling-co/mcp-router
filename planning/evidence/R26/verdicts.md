# R26 — verdict lines

Verdict lines with the command that produced them, not the capture. A raw gate capture quotes
`path:line` in its findings, and `planning/citation-gate.py` holds a new file to a baseline of
zero, so recording a green run here is what turns the next one red.

## The suites

    swift test --package-path app --filter AuthExpiry
    → Test run with 26 tests in 3 suites passed

Three suites: `R26 auth expiry policy` (9), `R26 auth expiry monitor` (10), `R26 control routes` (7).

## The socket lane

    bash scripts/acceptance/r26-auth-expiry.sh
    → r26-auth-expiry: 30 ok, 0 failed  (exit 0)

Scratch `MCP_ROUTER_HOME`, port 8978, five declared upstreams, four credential records planted on
disk by the lane. Enrolled in `scripts/acceptance/acceptance-lanes.sh`.

## The arms

    python3 planning/test-campaign/bin/arm-r26-auth-expiry.py
    → presence control: 26 passed, 0 failed
    → 8 of 8 arms bit; survived: none

| arm | what it plants | what went red |
|---|---|---|
| `vacuity` | a missing `expires_in` returns `valid` instead of `unknown` | E5, E6, E17, E21 |
| `clamp` | the policy clamps an out-of-range value instead of refusing it | E1, E2, E22 |
| `escalation` | the throttle stops treating a changed kind as due | E13 |
| `moved-expiry` | the throttle stops treating a replaced credential as new | E14 |
| `recovery` | a server that stops deserving a notice keeps its delivery record | E15 |
| `reading-consumes` | the GET claims as well as reads | E24 |
| `wiring` | `authExpiry:` is deleted from `RouterServiceDispatch` | the LANE, 503s, with the unit suite still green |
| `spawn` | the lane's stdio fixture is marked `warm` | both process-table readings, non-zero |

**One arm changed the work rather than confirming it.** `clamp` first reported `E22` SURVIVED:
that test injected its refusals as a literal, so it asserted the JSON shape of a refusal and could
not fail when the resolution stopped producing one. The test now resolves from configuration text,
and the arm bites. This is recorded because the arm's value here was finding an unfailable oracle,
not confirming a green.

**What the arms do not prove**, stated rather than implied: that these eight are the eight that
matter. Each shows the named assertion can fail for the reason its name gives.
