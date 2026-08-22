# M15 acceptance — the Settings window, driven; and the two checks that came back blind

Branch `ai/m15`, worktree `.worktrees/M15`. The driven pass is `34cdcd4`, 2026-08-22. The gap-fix
pass that wrote this file is `f7ee25e`, the same day, from base `aae3033`.

**This file did not exist until the gap-fix, and its absence is the first thing it has to record.**
`planning/practices/UI_VERIFICATION.md` rule 2 asks for one per item at exactly this path, and nine
other items carry one — M1, M2, M3, M4, M11, M13, M14, M23, M27. M15 drove a great deal of window
and wrote none of it where the next runner would look, which is the specific failure rule 2 exists
to prevent: *"a relaunched runner reads it and skips what you proved; without it, your successor
repeats every check you ran, and the user watches it happen again."* Nothing below is new
measurement invented to fill a file — every row is a check that ran, and the two that did not
produce a reading say so in their own section rather than appearing here as passes.

Every row was read over the accessibility plane **by pid**, against an app launched with `open -g`.
Nothing activated anything. Both scripts record the frontmost application before and after and fail
themselves if it moved: `m8-settings-menubar.sh` ran with `Ghostty` frontmost throughout, and
`mac-shell.sh` ended on `Ghostty` having never been in front.

## The ledger

| Screen | How verified | Commit | Result |
|---|---|---|---|
| Settings opens, and `⌘,` is what opens it | `m8-settings-menubar.sh` A1 — `⌘,` posted to the process, then the app's windows re-read by pid | `34cdcd4`, re-run `f7ee25e` | a second window titled `Settings` on a backgrounded app |
| Its titlebar — close live, minimise and zoom dimmed **in place** | A1 — `AXCloseButton`, `AXMinimizeButton`, `AXZoomButton` for presence **and** `AXEnabled` | `34cdcd4`, re-run `f7ee25e` | close present, enabled 1; minimise and zoom **present**, enabled 0. Dimmed, not hidden — which is the tell §3.4 asks for |
| The window title, and the console's left alone | §3.7 — title read off the named window; the console's read separately | `34cdcd4`, re-run `f7ee25e` | `Settings`, and the console kept `Checks` |
| The source list — seven pane rows, each by name | A2 — row count, then each of the seven titles in the AX tree | `34cdcd4`, re-run `f7ee25e` | 7 rows; Router, Harnesses, Session analyst, Updates, Security, Menu bar, Advanced all present |
| Router pane — its groups, its rows, its endpoint | A30, A6 — the `Router` and `Warm set` group headers, the four rows by label, the endpoint matched as a loopback URL carrying a port | `34cdcd4`, re-run `f7ee25e` | all present; the endpoint renders as a loopback URL rather than a placeholder |
| Warm set, empty — states its count | §5 | `34cdcd4`, re-run `f7ee25e` | the count, not "No items" |
| Menu bar pane — the one preference this app owns | A30 — the `Menu bar` group and the checkbox with its label | `34cdcd4`, re-run `f7ee25e` | group and labelled checkbox on screen |
| Security pane — the token, and Forget | A30, A9 — the `Control token` group; `Forget the stored token` present **rather than hidden**, and its disabled-reason present exactly when it is dimmed | `34cdcd4`, re-run `f7ee25e` | present; the enabled/reason pairing held in both directions |
| What the rendered panes must not say | A5, A7 — any memory figure; anything credential-shaped | `34cdcd4`, re-run `f7ee25e` | neither. The router observes no memory figure and none is drawn |
| Close is live — **pressed, not read** | the close button actuated over the AX plane, then both windows re-read | `34cdcd4`, re-run `f7ee25e` | the Settings window went and the console stayed. This is what stands in for the Escape check below |
| The status item | A15, A14 — menu-bar extras read by pid | `34cdcd4`, re-run `f7ee25e` | 1 extra present; macOS reports its own `status menu` description, so the label is asserted at the value level and the limit is recorded |
| The console shell, after Settings left the navigation list | `mac-shell.sh` — sidebar 256.0pt, unified toolbar 52.0pt, AppKit titlebar 32pt, seven destination rows sharing 32.0pt | `34cdcd4`, re-run `f7ee25e` | 7 of 7 destinations in the tree, and **the navigation list carries no Settings row** |
| The menu bar, both directions | `mac-shell.sh` A19 — every inventoried command present; nothing present that is neither inventoried nor named in the system list | `34cdcd4`, re-run `f7ee25e` | 34 of 34 inventoried commands; no unlisted item |
| **No command declared twice, and no chord on two items** | `mac-shell.sh` **A19b — added by this gap-fix, and counted rather than matched** | `f7ee25e` | 59 menu items over 59 distinct menu/title pairs; the 36 chords read are on one item each; 23 items carry no command character and are counted out loud |
| The shortcuts bind as the document states | A20 — `AXMenuItemCmdChar` and the `AXMenuItemCmdModifiers` bitmask decoded into Apple's display order | `34cdcd4`, re-run `f7ee25e` | 25 of 25 |
| The rendered window against the mock, both states | `mock-fidelity-gate.sh settings` — `MeasureDump` renders `ideal` and `empty` headless and eight layers run over the dumps | `34cdcd4`, re-run `f7ee25e` | seven layers clean; `breadth` 97 findings, **every one adjudicated to a numbered divergence**; `font-weight-face` inconclusive with its substitute recorded |
| Invisibility | frontmost recorded before and after, in both scripts, and asserted unchanged | `34cdcd4`, re-run `f7ee25e` | the app was never frontmost in either run |

## Two checks came back negative and are **not** evidence of anything

Recorded here so the next runner does not read the absence as a defect, re-run them, and get the
same nothing. `UI_VERIFICATION.md` rule 1 prescribes reporting a check that cannot be done rather
than taking the screen to do it.

**Escape closing the window.** `.onExitCommand { dismiss() }` ships at `SettingsWindow.swift:81`. A
posted keycode 53 left the window open — **and it left the window open before the handler existed
too.** A reading that is identical with and without the thing it is testing is a measurement of the
instrument, not of the product: `.onExitCommand` needs the window to hold the keyboard, and this
harness never activates the app, so the keystroke reaches no first responder. Settling it needs the
activation rule 1 forbids. What is asserted instead is that **close is live**, by pressing the
button rather than reading its `AXEnabled` — the row above.

**Arrow-key traversal of the source list.** The same shape. Moving focus into the list and reading
`AXSelectedRows` back needs the window to hold the keyboard. The seven rows and the single selection
*are* asserted over the accessibility plane; **which key moved the selection is not.**

**Requirement 11 — a sheet opened from a pane attaches to the Settings window — has no subject
here.** §4 leaves no pane opening a sheet, so there is nothing to attach. It is M18's, and the mock
affordance it would answer (`Choose…`) is the one finding under divergence D6.

## What a later runner may skip, and what it may not

**Skip, citing this file:** every row in the ledger, for as long as
`git diff <that commit>..HEAD` is empty for the files behind it — `app/Sources/MCPRouterUI/Settings/`,
`app/Sources/MCPRouterKit/Shell/SettingsPane*.swift`, `app/MCPRouter/MCPRouterApp.swift`,
`app/Sources/MCPRouterUI/Shell/`. Re-running a passing check against unchanged code has one possible
outcome, and a check whose result you can predict is not evidence.

**Do not skip:** anything under a file that moved. And do not treat the two negative readings above
as settled either way — they are open, they are not failures, and the honest way to close them is an
instrument that can hold the keyboard without taking the screen, not another posted keycode.

## The gates behind these rows

Measured from the worktree root at `f7ee25e`, 2026-08-22, on a machine carrying other fleet
sessions at a load average above 500 throughout.

| Gate | Result | Exit |
|---|---|---|
| `make lint` | `0 violations, 0 serious in 543 files`; `no-raw-design-values` 125 scanned, 84 under the geometry rules, clean; `no-harness-config-writes` 334 examined, 27 selftest cases held | 0 |
| `make test` | **1710 tests in 212 suites passed** — on the third run; see below | 0 |
| `scripts/acceptance/mac-shell.sh` | **54 ok lines, 0 failures** (52 before this gap-fix; the two new lines are A19b) | 0 |
| `scripts/acceptance/m8-settings-menubar.sh` | **35 passed, 0 failed**, frontmost `Ghostty` before and after | 0 |
| `scripts/acceptance/mock-fidelity-gate.sh settings` | 97 findings, by design — every one carries a divergence number | 1 |
| `python3 planning/ledger-reconcile.py` | `reconciled — no findings across A, B, B-range, C, D, E, F, G, H, I, J, K, L` | 0 |

**`make test` needed three runs, and the two that failed are recorded rather than dropped.** Run 1
lost `OAuthWireTests.cancellationResumesTheWaiter`; run 2 lost
`CallbackLifecycleTests.aListenerBindsOnce`; run 3 was green. Both are timing-bound loopback tests in
`RouterCore`, neither is touched by this diff, and both were then run in isolation on the same
machine — **8 of 8** and **4 of 4** green. The test count did not move across any of the three runs.
The `CallbackLifecycleTests` one is the same flake M15's own progress file recorded on two of eight
arm runs. This is reported as a flake under load, not as a pass: a suite that needed three attempts
is worth a reader knowing about.
