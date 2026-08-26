# G10 — `make acceptance` runs every lane, and what running them found

`planning/practices/UI_VERIFICATION.md` rule 2 asks for a committed ledger. This is G10's.

**This table was rewritten on 2026-08-26 from a fresh run, and the numbers moved.** The first
version of this record reported `fail: 0`, `mac-shell.sh 2 BLOCKED` and an aggregate of 2 — figures
taken before this branch's own commit repaired that lane's oracle, and left standing after it. A
record that describes a state its own branch has already left is the same defect as a lane nobody
dispatches: it reads like evidence and is not. What follows is what the delivered branch prints.

## What the item was, and what was actually left

The brief's first defect — `set v to value of e as text`, `shells.sh:216` at `03c34c3` reading
`value` where the shell puts its labels in the accessibility `description`, with an emptiness guard
that could not fire on `missing value` — was repaired and merged before this run at `ebfa81f`. **It
had never been executed against the running app**, and the ledger row said so: not missing
information, unfinished verification.

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

Defect 2 was already written down in this repository, for a different lane:
`in AppleScript binds a snapshot of a tree this app`, `mac-shell.sh:66` at `03c34c3` records that
`entire contents` binds a snapshot of a tree this app rebuilds every two seconds, that a property
read off a rebuilt element raises `-1728`, and that its own first version failed that way against a
perfectly good window. Every read in `shells.sh` sat inside a `try`, so each `-1728` was swallowed
and the element vanished from the output — indistinguishable from an element that was never there.

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
| iOS shell, both appearances | `xcrun simctl` boot/install/launch, screenshot per appearance | `0349374` | pass — carried by `shells.sh`'s 12 assertions in the run below |

## Every lane enrolled in `make acceptance`, run

Eight lanes, in the order the recipe on `main` ran them. The list is unchanged and in its original
order — the brief forbids closing this by reordering, and the aggregator's `LANES` array is the same
eight in the same sequence as the recipe it replaced.

**`make acceptance`, 2026-08-26.** The aggregator exited **1**; `make` reports a failing recipe as
its own exit 2, which is why the target's exit and the script's exit are stated separately here. The
first version of this record printed "aggregate exit 2" without that distinction, at a time when the
script really was exiting 2, and the two readings were indistinguishable.

`enrolled: 8   run: 8   pass: 5   fail: 1   blocked: 2   vacuous: 0`

**The conditions this table was measured under, because five of its eight rows are decided by them.**

| Condition | On the run below | How it is known |
|---|---|---|
| `MCPRouterCLI` in `app/.build/debug/` | **absent** | the two BLOCKED rows print the path and say so — the row is its own evidence |
| the session composites a window | **yes** | `shells.sh` resolved a window id through `CGWindowListCopyWindowInfo` and captured its backing store; a session that composites nothing cannot reach either |

A verifier re-ran these same eight lanes on this same branch and **five of the eight rows came out
differently**, in both directions and traceably:

| Lane | Here | On the verifier's machine | The condition that decided it |
|---|---|---|---|
| `p1-auth-routes.sh` | BLOCKED | **PASS** | `MCPRouterCLI` was already in a shared `.build` there |
| `r7-harness-reconciliation.sh` | BLOCKED | **PASS** | same |
| `shells.sh` | PASS | **BLOCKED** | 0 windows after 15s on both Debug and Release; isolated, `shells.sh` exits 1 with `the macOS window never appeared` |
| `mac-shell.sh` | FAIL | **BLOCKED** | same |
| `menu-badge-lane.sh` | PASS | **BLOCKED** | same |

**Neither table is wrong, and re-running until they agree is not the repair** — these two conditions
are properties of the machine, not of the tree, and two honest runs of the same commit will keep
disagreeing while they differ. The defect was one level up: a per-lane table with no environment
beside it is a measurement whose conditions are unrecoverable, and a ledger that cannot be compared
with the next run is not doing the job `UI_VERIFICATION.md` rule 2 asks of it.

So the aggregator now states both facts itself, above the lanes and again under the counts line, as
`ACCEPTANCE-ENV:` — `scripts/acceptance/acceptance-lanes.sh`, with the window plane probed by
`scripts/acceptance/window-plane.swift` counting on-screen windows before MCP Router launches.
`acceptance-lanes-selftest.sh` arm 12 requires both facts in both places, and requires the footer
copy specifically, because a stamp printed only above a long run is one that is lost the moment
somebody pastes the summary. Measured on this tree, one hour after the table below:
`MCPRouterCLI in .build: present — built 2026-08-26 22:32`, `window plane composites: yes — 27
on-screen windows, 26 named`. Both differ from the run below, which is the point of printing them.

**The `shells.sh` window failure the verifier hit is inherited, not this branch's.** It reproduces at
`03c34c3`, the tree this item started from, and nothing on this branch touches window resolution —
`git diff 03c34c3..ai/g10 -- app/Sources/` is empty, so no product code was changed at all. A
session that cannot composite is an environment this lane cannot run in, which is what its exit 2
is for.

| Lane | Exit | Assertions | Verdict | What it means |
|---|---|---|---|---|
| `shells.sh` | 0 | 12 | PASS | the item's own lane, green end-to-end after five repairs — both AX needles, `#1C1C1E` on the Mac, `#FFFFFF` in the gallery, `#1C1C1E`/`#FFFFFF` on the phone |
| `control-client.sh` | 0 | 4 | PASS | **and it asserted something this time.** See below — its previous PASS was a dead shell |
| `p1-auth-routes.sh` | 2 | 0 | BLOCKED | `no MCPRouterCLI at app/.build/debug/MCPRouterCLI (run: make build or swift build --package-path app)` |
| `mac-shell.sh` | 1 | 11 | FAIL | a genuine red, reached because the oracle now builds. Two independent reds, enumerated below |
| `r7-harness-reconciliation.sh` | 2 | 0 | BLOCKED | `no router binary at app/.build/debug/MCPRouterCLI` |
| `m22-boards.sh` | 0 | 16 | PASS | **the enrolment M22 made deliberately, dispatched by the gate** |
| `menu-badge-lane.sh` | 0 | 8 | PASS | first dispatch since `shells.sh` went red |
| `menu-badge-lane-selftest.sh` | 0 | 3 | PASS | both tripwires fire, neither fires on today's dump |

### `control-client.sh` was not passing. It was dying.

Recorded PASS in the first version of this table. Run on its own on `main`, it prints one line and
nothing else:

    parity-lock.sh: line 205: BASHPID: unbound variable

and exits 0 having run **none of its three checks**.

> **The tree this was measured on, corrected 2026-08-27.** The line above cited `main` at
> `520fed38`. That is not a commit: no commit on any ref in this repository begins `520fed`, and
> `git cat-file -t 520fed38` answers `blob` — an accidental prefix collision with a file object, so
> the anchor named nothing a reader could check out. It is the same defect as the stale restoration
> hash below, and it survived that sweep because a hash that *resolves to something* passes an
> existence check.
>
> The finding itself is unaffected and is re-anchored by reading rather than by re-running: the bare
> `BASHPID` stands at `scripts/acceptance/parity-lock.sh:205` on `03c34c3`, the tree this item
> started from, and still on `main` at `82753e0` today — verified in both with `git show
> <tree>:scripts/acceptance/parity-lock.sh`. The repair is on this branch only. `BASHPID` arrived in bash 4.0; macOS ships
3.2.57 as `/bin/bash`; the lane is `#!/bin/bash` and sets `-u`. Measured on this machine, bash 3.2
preserves the status of an explicit `exit 1` and of a `set -e` death, and **loses** it for a `set -u`
death — the EXIT trap's last command supplies the status instead, and that trap ends in a `rm -rf`
that succeeds.

`parity-lock-selftest.sh` did not catch it because it is `#!/usr/bin/env bash`, which finds
Homebrew's bash 5.3.9. The same file was green in the selftest and dead in the lane. Run under
`/bin/bash` it died at its own line 88.

Repaired, the lane runs its three checks against a real router and the aggregate reads 4 assertions
against it. That is the difference between a lane that passes and a lane that was never asked
anything.

### A lane that asserts nothing is no longer allowed to be a pass

Repairing one script does not repair the class. **Exit 0 is a claim, and the aggregator was taking
it on trust.** A lane can reach 0 having proved nothing through a dead shell, an early return, a
loop over an empty list, or a skip that forgot to change its code, and from outside all four read
identically.

So the runner now counts each lane's assertions off the lane's own stdout — the `ok`/`PASS`
vocabulary these eight already speak, or an `ACCEPTANCE-ASSERTIONS: <n>` line for a lane whose
output is not prose. Exit 0 with zero assertions is classed **VACUOUS** and counted with the
failures, never with the blocked: exit 2 is a lane *reporting* that it could not run, which is
honest; exit 0 with nothing behind it is a lane making a claim it did not earn.

The `ASSERTIONS` column in the table above is that count. It is also why the two BLOCKED rows
reading 0 are not flagged — they said so in their exit code.

**The count is a presence test, not a tally.** `control-client.sh` makes three checks and the table
credits it with four, because it echoes its probe's output and one of those lines is `OK`. That
direction is harmless: a spurious match can only push a count above zero, and zero is the only value
the gate acts on. The direction that is not harmless is a lane asserting nothing that happens to
echo a subprocess line beginning `ok` — it would pass. That hole is named here and in the runner's
header rather than covered by a claim that the number is exact, and `ACCEPTANCE-ASSERTIONS:` is the
way a lane states its count precisely.

Presence control, `acceptance-lanes-selftest.sh`, **13 arms all held**. Arm 8 plants a silent exit 0
and requires VACUOUS; **arm 9 is its control** — the same lane with one `ok` line added must be a
PASS again, so the check cannot be satisfied by reddening every zero; arm 10 plants the shape this
was *found* in, a shell killed by `set -u` whose EXIT trap launders the status; arm 11 requires a
declared `ACCEPTANCE-ASSERTIONS:` count to be honoured in both directions, a declared **0** included.

With `lane_assertions()` planted to credit every lane with one assertion it never made, **11
assertions across arms 8, 10 and 11** go red. An earlier version of this paragraph said 8 across arms
8 and 10: it was written before arm 11 existed and was not re-measured when it was added, so it
understated the control's reach by three assertions and one arm. **Understating a control is the same
class of error as overstating it** — it is the number a reader uses to decide whether the control is
worth trusting. Re-measured on the delivered tree by planting the fault and counting `SELFTEST FAIL`
lines: 11, in arms 8, 10 and 11.

Restored byte-identically, sha256 of `scripts/acceptance/acceptance-lanes.sh`
`9faef3d588fec2b8fdfb5394f0eef6c3be47e62d8fcfe17883bdb2b703987cb8` either side of both plants, and
`git diff` empty after each restore.

**Arm 12 was watched going red twice, under two different plants.** Dropping the footer
`environment_stamp` call: 2 red — `expected 4 ACCEPTANCE-ENV lines … saw 2` and `the counts line is
not followed by both ACCEPTANCE-ENV facts, saw 0`. Dropping the window-plane line from the stamp
itself: 3 red, including `no ACCEPTANCE-ENV line names whether the session composites windows`. Both
restored to the same sha256 above, `git diff` empty, 13 arms held again after each.

### `mac-shell.sh` holds two independent reds, and the first version of this record named neither

`mac-shell.sh` had been blocked for four days and nothing had reached it: its availability oracle is
built from a hand-picked file list, and two files it needs were missing. That was repaired on this
branch, which moved the lane from BLOCKED to a reachable assertion FAILURE — a move the first
version of this record did not follow.

`fail` exits, so the lane stops at its first red and every red behind it is invisible. Run with
`fail` recording instead of exiting, it prints **four** FAIL lines over 54 passing assertions, and
they are **two** defects:

| Red | Independent? | Standing or conditional? | Class |
|---|---|---|---|
| `the window title is 'Insights', which is not a destination name (§3.7 forbids the app's name)` | yes | **conditional** — see below | the seven-name allow-list is stale by two since M22 shipped Harnesses and Insights — cited in full below the table |
| `File / Export library… is not in the menu bar at all — §3.4 forbids hiding a disabled command` | yes | standing | the row hard-names the File menu and a lowercase title; `MenuCommand` moved `exportLibrary` to Library at M20 and titles it `Export Library…` |
| `File / Export library… is offered as usable, but no export feature exists in either target` | no — cascade | standing | `EXPORT_LINE` came back empty, so the enabled field read empty and this fired on its own message |
| `File / Export library… is dimmed and says nothing — §3.4 requires a discoverable reason` | no — cascade | standing | same empty line, one field over |

**The first red is state-dependent, and an earlier version of this record wrote it up as standing.**
The assertion reads the title of whichever board the app *restored into*, so it fires only when that
board is Harnesses or Insights — the two names missing from the allow-list. It fired here because
this run restored into Insights. A verifier's run of the same lane on this same branch restored into
Checks, and the same assertion **passed**, printing `window title is 'Checks'`.

The staleness underneath it is standing and is not in doubt: `Destination.swift` ships nine cases —
`activity`, `servers`, `skills`, `harnesses`, `discover`, `inbox`, `evals` (titled `Checks`),
`cleanup`, `insights` — against the seven the allow-list names, and `harnesses` and `insights` are
absent from it by reading, on any run, whatever the app restored into. What is conditional is the
*red*, not the defect. Writing a conditional red up as a standing one overstates the evidence in a
way a reader cannot detect, and it is the same class as the understated control count above: both
are a number that decides how much weight the finding carries.

The allow-list the first red trips over is `Activity|Servers|Skills|Discover|Inbox|Checks|Cleanup`,
`mac-shell.sh:346` at `03c34c3` — seven names against the nine destinations the app now ships. It
is quoted here rather than in the table because a markdown cell would need its pipes escaped, and
an escaped anchor is one the citation gate reads as absent from the line it names.

One defect producing three lines of output is worth knowing before anybody counts reds. Both real
ones are hand-written expectations about the product's intended surface that the product has moved
past, and both are reported rather than fixed, for the reason this item took throughout: **clear
what prevents measurement, report what measurement finds.** They are written up as a brief at
`planning/features-to-triage/mac-shell-hand-named-rows-went-stale-when-m20-and-m22-shipped.md`.

### The AXHelp red was the harness's, and it is closed

A verifier's run of this lane failed on a reason-string assertion rather than on the window title:
`Router / Re-index Manifest` carried `Re-indexing the whole manifest hasn't been built yet.` where
the oracle expected `This feature hasn't been built yet.`

**Harness defect, settled at the source rather than argued.** The oracle printed
`availability.reason`, `CommandAvailability`'s generic sentence. The running app writes
`command.reason(in: context)` into `AXHelp`, and `reason(in:)` specialises `.featureUnbuilt` per
command deliberately — `D-m14-a`'s resolution, taken because one command carried that answer when
the sentence was written and nine carry it now, so the generic line would appear nine times across
two menus and name none of the nine features. The product is doing what its own source says it was
changed to do; the oracle was reading the neighbouring function.

Measured twice. Compiled standalone, the repaired oracle emits
`Re-indexing the whole manifest hasn't been built yet.` — the app's string, exactly — for each of
the nine `.featureUnbuilt` commands. Run against the live app, the availability block builds its
oracle over **32 app-declared commands with nine boards installed** and produces **zero**
reason-string reds.

The assertion is stronger for the repair, not weaker: the lane now requires the specific sentence
for each of the nine rather than one generic string shared between them, so a command that starts
returning `.featureUnbuilt` without naming its subject fails here.

### The lane no longer leaves an app running when it fails

The first version of this record noted, as an exception, that an isolated failing re-run left an
MCPRouter instance behind and briefly frontmost, quit by hand. The cause was structural: the app was
quit by a `terminate` on the last line of the script, and every `fail` exits before it.

The EXIT trap now terminates the instance this run launched, waits for it to actually go, and
escalates through SIGTERM to SIGKILL — and returns the status it was entered with, because a cleanup
that can rewrite FAIL to PASS on bash 3.2 is the very defect above. Measured on the run in the table:
`mac-shell.sh` exited 1, and **0** MCPRouter processes were left running afterwards.

### The two lanes that stayed blocked, and why

`p1-auth-routes.sh` and `r7-harness-reconciliation.sh` both need `app/.build/debug/MCPRouterCLI`,
which `make acceptance` never builds — its prerequisites are `build-mac` and `build-mac-release`
only. Same shape as the iOS bundle in defect 5: a lane asserting against an artifact the target does
not produce. Both remain BLOCKED, with `swift build --package-path app --product MCPRouterCLI` as
the thing that would settle them — recorded as a result, not as a pass and not as a failure.

## Rule 1

Both macOS launches use `open -g`. Every read goes through the accessibility plane by pid or through
`CGWindowListCopyWindowInfo`; nothing activates anything. `shells.sh` records the frontmost
application before the first launch and asserts MCP Router is not frontmost at the end — a violation
`fail`s, because this lane taking the screen is a defect in the lane rather than an environment it
could not run in.

Across the run in the table: frontmost was `RelayApp` before the sweep and `Google Chrome` after it,
and **MCP Router was neither at any point**. The two differ because this machine carries five
concurrent runners and a person; what rule 1 asserts is that MCP Router never took the screen, and
`shells.sh` asserts that itself and reported it held. The exception the first version of this record
had to carry — a leftover instance, momentarily frontmost — is closed by the cleanup above rather
than repeated.
