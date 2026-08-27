---
status: completed
shipped-by: 9e8a754
---

# D2 — The deferred register: Mac surfaces and the design authority

**Source:** `deferred-plan` = `schedule-all` (confirmed, chosen against the recommendation).

Fourteen children across the Mac app and `DESIGN.md`. Three of them are **shared-surface changes that
individual runners deliberately declined to make alone**, which is why they are here: a runner editing
a merged shared surface unilaterally is how a design authority stops being one.

| Child | What |
|---|---|
| `M9` | **Rename the `Evals` destination to `Checks`.** M7's residual objection, which it could not fix from inside. Every reading on both panes is an observation with its input beside it and the vocabulary carries no grading verb; the word `Evals` in the sidebar, title, menu and deep link still says "test results". `Destination.title` is a merged shared surface |
| `M10` | Amend `DESIGN.md` §6:279-280. Its mandated "not evaluated" skill string describes a state that no longer exists |
| `M12` | Staleness and an as-of time inside a destructive dialog. A `.stale` reading is shown in the present tense with no marker, and calls accruing between load and POST are discarded uncounted, so the figure is a lower bound presented as a count |
| `D-m11-b` | Menu commands render enabled but no-op with the window closed (`@FocusedValue` nil). Reverting to `.none` would falsely claim the surface was never built; the residue belongs to `ShellCommandRouter` |
| `M5-a` | Router-side registry snapshot store, and the trending band it makes possible. The only honest route to a velocity figure |
| `M5-b` | Registry search for skills and marketplaces. The prototype's toggle has no endpoint behind it |
| `M5-c` | GitHub token in settings, to lift star coverage past the unauthenticated 60/hour limit |
| `D-b` | Surface the call-log stream's skipped-record count, so a lossy stream stops looking clean |
| `D-c` | Expose `usage(limit:server:cwd:)` in Activity's filters; the client takes all three, the board offers one |
| `D-f` | A machine-readable token block in `DESIGN.md`. F2's parity gate parses prose tables today |
| `D-m6-b` | Envelope versioning for the pairing protocol, so mismatched builds can detect each other |
| `D-m6-d` | The popover has no inbox band, and it is the app's most visible surface |
| `D-m6-e` | An accent-substrate token, replacing M6's hand-rolled `0.16` selection alpha |
| `D-m6-g` | The readout repaints the whole window once a second |

`D-m6-c` (renaming `ScaffoldPane.swift`) is **excluded deliberately**: five acceptance scripts read it
by name, so it belongs with G1's gate work, not here.
