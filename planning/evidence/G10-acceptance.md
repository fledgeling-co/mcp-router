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
