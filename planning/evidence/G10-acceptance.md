# G10 — `make acceptance` runs every lane, and what running them found

`planning/practices/UI_VERIFICATION.md` rule 2 asks for a committed ledger. This is G10's.

## What the item was, and what was actually left

The brief's first defect — `shells.sh:216` reading `value` where the shell puts its labels in the
accessibility `description`, with an emptiness guard that could not fire on `missing value` — was
repaired and merged before this run at `ebfa81f`. **It had never been executed against the running
app**, and the ledger row said so: not missing information, unfinished verification.

Running it is what this item was for, and it was still red.

## `shells.sh`: one defect fixed, five in the file

Each was found by fixing the previous one and running it again. All five are the harness being
wrong about the app rather than the app being wrong, which is `G4`'s class — in an acceptance gate,
five times over.

| # | Defect | Evidence it was the harness, not the product |
|---|---|---|
| 1 | reads `value`, not `description` | merged at `ebfa81f` before this run; `mac-shell.sh` asked correctly and passed |
| 2 | walks with System Events `entire contents` | the walk returned 61 lines carrying neither `Activity` nor `Running`; `axkit dump` returned 104 rows carrying both, same window, same minute |
| 3 | resolves the window by the title `"MCP Router"` | no such window has ever existed — the console titles its window after the selected destination; CGWindowList reported `Cleanup`. Screen Recording IS granted: 34 of 35 on-screen windows report a name |
| 4 | samples the ground at x=200 image px | 100pt on a 2x display, inside a 256pt sidebar. One capture, 1960×1240: (200,930) `#28282A`; (600,930), (1200,930), (1600,930), (1200,1150) all `#1C1C1E` = `ColorToken.ground` exactly |
| 5 | never checked the build was the tree's | iOS failed `#1E1E1E` vs `#1C1C1E`. `.ground` was `#1E1E1E` until `c920afb` (2026-08-22); the simulator bundle was built 2026-08-20. The phone painted the token it was compiled with |

Defect 2 was already written down in this repository, for a different lane: `mac-shell.sh:66`
records that `entire contents` binds a snapshot of a tree this app rebuilds every two seconds, that
a property read off a rebuilt element raises `-1728`, and that its own first version failed that way
against a perfectly good window. Every read in `shells.sh` sat inside a `try`, so each `-1728` was
swallowed and the element vanished from the output — indistinguishable from an element that was
never there.

Defects 3 and 5 share one shape worth naming: **both reported a harness problem as the wrong
outcome class.** The window lookup blamed "Screen Recording permission, or the window is
off-screen"; the stale bundle was reported as a failed assertion against the product. That is the
confusion the 1-vs-2 exit split exists to prevent, and it was happening inside the file whose header
explains the split.

## Screens verified

| Screen | How verified | Commit | Result |
|---|---|---|---|
| Console main window (Cleanup board restored) | `axkit dump <pid> window`, 104 rows; needles `Activity` and `Running` matched in columns 4-6 | `db150ed` | pass |
| Console main window, rendered ground | `screencapture -o -x -l <CGWindowID>`, sampled (1470, 930) image px, clear of the 256pt sidebar | `db150ed` | pass — `#1C1C1E` = `ColorToken.ground` |
| Design gallery, light appearance | launched `open -g -n --args --gallery-appearance light`, opened from the Window menu by pid, captured by window id | `db150ed` | pass — `#FFFFFF` = `ColorToken.ground` light |
| iOS shell, both appearances | `xcrun simctl` boot/install/launch, screenshot per appearance | `0349374` | see the lane table — gated on `Debug-iphonesimulator` freshness |

## Rule 1

Both macOS launches use `open -g`. Every read goes through the accessibility plane by pid or through
`CGWindowListCopyWindowInfo`; nothing activates anything. `shells.sh` now records the frontmost
application before the first launch and asserts MCP Router is not frontmost at the end — a violation
`fail`s, because this lane taking the screen is a defect in the lane rather than an environment it
could not run in. The three sibling Mac lanes already did this; this one did not.

Measured across every run in this item: frontmost was `ghostty` at the start and at the end, and MCP
Router never took it.

## Every lane enrolled in `make acceptance`, run

Eight lanes, from `Makefile:484` on `main`. The list is unchanged and in its original order — the
brief forbids closing this by reordering, and the aggregator's `LANES` array is the same eight in
the same sequence as the recipe it replaced.

Aggregate exit **2**, `enrolled: 8  run: 8  pass: 5  fail: 0  blocked: 3`.

| Lane | Exit | Verdict | What it means |
|---|---|---|---|
| `shells.sh` | 0 | PASS | the item's own lane, green end-to-end after five repairs — both AX needles, `#1C1C1E` on the Mac, `#FFFFFF` in the gallery, `#1C1C1E`/`#FFFFFF` on the phone |
| `control-client.sh` | 0 | PASS | first dispatch since `shells.sh` went red |
| `p1-auth-routes.sh` | 2 | BLOCKED | `no MCPRouterCLI at app/.build/debug/MCPRouterCLI (run: make build or swift build --package-path app)` |
| `mac-shell.sh` | 2 | BLOCKED | `could not build the availability oracle` — two files missing from its hand-picked list; repaired, see below |
| `r7-harness-reconciliation.sh` | 2 | BLOCKED | `no router binary at app/.build/debug/MCPRouterCLI` |
| `m22-boards.sh` | 0 | PASS | **the enrolment M22 made deliberately, dispatched by the gate for the first time** |
| `menu-badge-lane.sh` | 0 | PASS | first dispatch since `shells.sh` went red |
| `menu-badge-lane-selftest.sh` | 0 | PASS | both tripwires fire, neither fires on today's dump |

### What running them found that halting had hidden

**`mac-shell.sh` had been blocked for four days and nothing had reached it.** Its menu availability
oracle is built from a hand-picked five-file list, and two files it needs were missing:
`KeyChord.swift`, which landed at `0bdfcbe` on 2026-08-22 with M20's menu bar in the same change
that made `MenuCommand.swift` refer to `KeyChord`; and `MenuCommandAvailability.swift`, where
`CommandContext` and `availability(in:)` actually live. The lane's own comment records this exact
failure happening on 2026-08-21 for a different file and predicts the recurrence. What it could not
predict is that nobody would see it, because `make acceptance` stopped at `shells.sh` four lanes
earlier.

That is the item's thesis, measured: **a lane enrolled in the gate, blocked for four days, silent.**

With both files added the oracle builds, and the lane runs 11 assertions before reaching a genuine
red:

    FAIL: the window title is 'Insights', which is not a destination name (§3.7 forbids the app's name)

**Reported, not fixed, and deliberately.** `Insights` is a real destination — M22 shipped the
Harnesses and Insights boards — so §3.7 is satisfied and the lane's seven-name allow-list at
`mac-shell.sh:346` is stale by two. The lane contradicts itself in the same run: it passes
*9 destination rows share one height* and then *all seven destinations are in the accessibility
tree*. Whether nine destinations is the intended set is M22's question and the allow-list is M1's
lane, so extending it here would be changing what another item's gate asserts rather than repairing
a broken instrument. The line taken throughout: **clear what prevents measurement, report what
measurement finds.**

`p1-auth-routes.sh` and `r7-harness-reconciliation.sh` both want `app/.build/debug/MCPRouterCLI`,
which `make acceptance` never builds — its prerequisites are `build-mac` and `build-mac-release`
only. Same shape as the iOS bundle in defect 5: a lane asserting against an artifact the target does
not produce.

### Rule 1 across the sweep

`FRONT_BEFORE_SWEEP=ghostty`, `FRONT_AFTER_SWEEP=ghostty`. `shells.sh` asserts it itself and reports
*MCP Router never became frontmost — 'ghostty' at the start, 'ghostty' at the end*.

One exception, recorded rather than smoothed over: the **isolated** re-run of `mac-shell.sh` after
the oracle repair read `FRONT_AFTER=MCPRouter`. That lane `fail`ed at the title assertion above,
which sits before its own frontmost check and before its cleanup, so it left the app running and
momentarily frontmost. Frontmost was `ghostty` again when next read, and the leftover instance was
quit by hand. Nothing in the eight-lane sweep did this.

### The two lanes that stayed blocked, and why

`p1-auth-routes.sh` and `r7-harness-reconciliation.sh` both need
`app/.build/debug/MCPRouterCLI`. Building it was attempted three times over roughly twenty minutes
and refused each time by harbourmaster:

    swift build --package-path app --product MCPRouterCLI
    {"status": "REFUSED", "reason": "no berth available", "weight_wanted": 2,
     "available": 0, "ceiling": 3, "in_use": 6,
     "pressure": {"cpu": "critical", "memory": "tight", "overall": "critical"}}

A different fleet's `.worktrees/M33` was compiling `MCPRouterKitTests`, `RouterCore` and
`MCPRouterApp` throughout, at a load average of 78 on 16 cores. Exit 75 is scheduling information
rather than a failing gate, so it was not looped on. **Both lanes remain BLOCKED, with the exact
command above as the thing that would settle them** — recorded as a result, not as a pass and not as
a failure.
