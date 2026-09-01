# Goal: Reconcile, Intake, and Ship All Remaining Backlog Work

- **slug:** all-remaining-work
- **armed:** 2026-09-01 13:30 local
- **project:** C:/Dev/mcp-router
- **bound:** 80 turns / 2026-09-03T09:00:00Z / stuck after 3 identical failures

## Objective

Drive all remaining work across test-campaign, tailings, reckon, intake, and ship-fleet to verified, production-ready completion. Reconcile evidence against stated requirements, intake all remaining findings into triage-ready briefs, execute scheduled waves via the ship-fleet and ship-feature pipelines, and verify until the ledger is completely clear with 0 unbuilt, 0 broken, 0 unmeasured, and 0 undecided.

## Worklist

| ID | Item | Gate | Status |
|---|---|---|---|
| F-001 | Settle test-campaign gates and oracles across all surfaces | `PYTHONIOENCODING=utf-8 python C:/Users/rhode/.claude/remote/plugins/9f1dcc6b2a6d2938/skills/test-campaign/scripts/strict-check.py planning/test-campaign` | in-progress |
| F-002 | Classify and resolve all tailings session assertions | `PYTHONIOENCODING=utf-8 python C:/Users/rhode/.claude/remote/plugins/987f2fe48b4f1e14/skills/tailings/scripts/worklist.py check planning/tailings-5` | in-progress |
| F-003 | Reconcile ledger with 0 unbuilt, 0 broken, 0 unmeasured, 0 undecided | `PYTHONIOENCODING=utf-8 python C:/Users/rhode/.claude/remote/plugins/b0ea86c2daca5c19/skills/reckon/scripts/reckon.py check planning/reckoning/2026-09-01/ledger.json` | pending |
| F-004 | Brief target resolution and triage queue consistency | `PYTHONIOENCODING=utf-8 python planning/brief-target-gate.py` | pending |
| F-005 | Execute Wave 1 scheduled work items via ship-fleet | `PYTHONIOENCODING=utf-8 python planning/goals/win-gates.py ledger` | pending |
| F-006 | Resolve Wave 2 dependencies and product work | `git status --porcelain` | pending |
| F-007 | Final cross-family verification and reconciliation check | `PYTHONIOENCODING=utf-8 python C:/Users/rhode/.claude/remote/plugins/b0ea86c2daca5c19/skills/reckon/scripts/reckon.py check planning/reckoning/2026-09-01/ledger.json` | pending |

Total: 7.

## Gates

Run by the guard at the end of every turn. Exit 0 is the only thing that counts.

| Name | Command | Passes when |
|---|---|---|
| brief-exists | `test -s docs/goals/goal-all-remaining-work.md` | exit 0 |
| brief-targets | `PYTHONIOENCODING=utf-8 python planning/brief-target-gate.py` | exit 0 |
| reckon-clean | `PYTHONIOENCODING=utf-8 python C:/Users/rhode/.claude/remote/plugins/b0ea86c2daca5c19/skills/reckon/scripts/reckon.py check planning/reckoning/2026-09-01/ledger.json` | exit 0 |
| strict-ratchet | `PYTHONIOENCODING=utf-8 python C:/Users/rhode/.claude/remote/plugins/9f1dcc6b2a6d2938/skills/test-campaign/scripts/strict-check.py planning/test-campaign` | exit 0 |

## Blocked-item policy

Follow /clarify: clarify internal decisions, ask user only for genuine taste/cost/scope/risk decisions. Parked items must have explicit reason documented.

## Resources

| Resource | Reserved for this run | Conflicts with |
|---|---|---|
| Port 3000 | yes | other router instances |
| Windows display server | yes | interactive glass tests |

## Delivery

- **Driver:** /ship-fleet:ship-fleet and /ship-feature:ship-feature
- **Model / effort:** gemini-3.7-flash / medium
- **Concurrency cap:** 8
- **If an agent dies:** resume via workflow-resume or reload checkpoint

## Stop conditions

- All gates pass and all remaining work is merged, verified, and reconciled.
- The turn (80), deadline (2026-09-03T09:00:00Z) or stuck bound (3) is reached.

## Open questions

