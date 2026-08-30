# WIN20 — acceptance: the Windows automation plane, measured

Every figure here was taken on **LUKESFF**, Windows 11 Pro 10.0.26200, **2026-08-30**, against
`MCPRouter.AutomationProbe` — **WIN20's own WinUI 3 probe window, not the MCP Router Windows
client**, which has no drawable window yet (WIN3 has landed no `.csproj`). The brief anticipates
exactly this and asks that it be said plainly; it is said here, in the spec, in the expectation
manifest, in the assert report and in the registry proposal, so no artifact can be read on its own
and mistaken for a measurement of the product.

Spec: `planning/specs/spec-WIN20.md`. Plan: `planning/plans/plan-WIN20.md`.

---

## The gates, with their real exit codes

Each row was run at the commit this file lands on. Nothing below is reported from memory.

| Gate | Command | Exit | Reading |
|---|---|---|---|
| The Windows lane | `powershell -File scripts/windows/verify.ps1` | **0** | passed 10 · failed 0 · not-run 7 |
| Probe restore | `MSBuild app/windows/AutomationProbe/AutomationProbe.csproj -t:Restore` | **0** | inside the lane |
| Probe build | `MSBuild app/windows/AutomationProbe/AutomationProbe.csproj -t:Build` | **0** | inside the lane, from clean |
| The live automation lane, run A | `powershell -File scripts/windows/uia/run-probe-lane.ps1` | **0** | 36 control-view elements · 65 raw-view · 90 passed · 0 failed · 2 unoracled |
| The live automation lane, run B | as above | **0** | identical figures — 36 / 65 / 90 / 0 / 2 |
| The armed assertions | `python scripts/windows/uia/uia-selftest.py --dump planning/evidence/WIN20/run/uia-control-view.json` | **0** | 25 arms, 0 misbehaved |

### What could NOT be run, and why

Recorded as not-run, which is neither a pass nor a failure. None of these was attempted and
reported green.

| Not run | Why |
|---|---|
| `make lint`, `make test` | every Makefile verification target shells to `xcodebuild`. `make`, `swift`, `swiftlint`, `swiftformat` and `xcodebuild` are all absent on this machine |
| the Swift macOS app and its 2329 tests, the iOS lanes, every glass and capture lane | same cause |
| `campaign.py`, `strict-check`, `reckon` | they measure an app that cannot be launched here — which is also why §8 of the spec proposes registry rows rather than writing them |
| `planning/null-run-gate.py`, `sweep-control-gate.py`, `carrier-parity-gate.py` | their control arms shell to a `.sh` member or a macOS binary; they correctly refuse a verdict here |
| `planning/registry-drop-gate.py` | NO VERDICT — neither baseline ref carries `cases.json` or `inventory.json`, so 0 of 8 registry views were comparable |
| router typecheck, platform e2e | `node_modules` is absent in this worktree |
| cross-family review | `codex`, `agy`, `grok` and `cursor-agent` are all absent — `Get-Command` returns nothing for any of them. **Not run. Not a pass.** |
| Narrator / screen-reader announcement | acceptance clause 6. The same tree serves Narrator by construction, but nothing here drove one |

### One stated constraint that turned out to be false, and was measured rather than repeated

This runner was told the `claude` CLI on this machine "returns *your organization has disabled
Claude subscription access*". **It does not.** Measured 2026-08-30:
`claude --model claude-fable-5 -p "Reply with the single word OK."` printed `OK` and exited **0**.

That changes one thing and not the other. The four out-of-family binaries are genuinely absent, so
the **cross-family gate is still not run and is still not a pass**. But a *same-family* adversarial
review was available the whole time and is not a substitute anybody should have to guess about, so
it was run: `planning/evidence/WIN20/review-fable.md`, `claude-fable-5`, asked to find ways this
gate could report exit 0 having measured nothing. In-family review does not satisfy a cross-family
gate and is not offered as one.

---

## The tree, as it actually reads

36 elements in the control view, 65 in the raw view, off a window that was drawn and never
foregrounded. The rows that carry the acceptance:

| AutomationId | ControlType | Name | State read off the plane |
|---|---|---|---|
| `probe.destination.activity` … `.cleanup` (7) | ListItem | Activity · Servers · Skills · Discover · Inbox · Checks · Cleanup | `isSelected` on each |
| `probe.destination.settings` | ListItem | Settings | `isSelected: false` |
| `probe.navigation` | Custom | Destinations | `selection: ["Servers"]`, `canSelectMultiple: false` |
| `probe.command.addServer` / `.refresh` | Button | Add server · Refresh | — |
| `probe.command.holdQueue` | Button | Hold queue | `toggleState: On` — **held** |
| `probe.serverList` | List | Servers | `selection: ["GitHub"]` |
| `probe.server.filesystem` / `.github` / `.braveSearch` | ListItem | Filesystem · GitHub · Brave Search | `isSelected` false / **true** / false |
| `probe.button.removeServer` | Button | Remove server | `isEnabled: false` — **disabled** |
| `probe.button.pairServer` | Button | Pair server | `isEnabled: true` |
| `probe.switch.pauseRouting` | Button | Pause routing | `toggleState: On` |
| `probe.status.busyRing` | **ProgressBar** | **"Busy Starting upstream"** | **busy**, carried in the name |
| `probe.status.busyWord` | Text | Starting upstream | — |

Three readings in that table are findings rather than confirmations, and each is armed:

1. **An active `ProgressRing` publishes as `ControlType.ProgressBar` and WinUI prepends the
   localised word "Busy" to its automation name.** It exposes no usable `RangeValuePattern` state.
   Busy is therefore readable — and it is readable as a *string*, so a harness looking for a pattern
   would find nothing and fall back to pixels. The gate asserts the marker; stripping "Busy" from
   the name fires it.
2. **A `NavigationView` publishes as `ControlType.Custom`, and its items as `ListItem`** inside a
   `Group` named "Destinations". The selection is legible from both ends — the container's
   `SelectionPattern` and each item's `SelectionItemPattern` — which is why the gate asserts both.
3. **A `ToggleSwitch` publishes as `ControlType.Button` with a `TogglePattern`**, not as a distinct
   control type. DESIGN.md §11 rule 6 makes the switch *the immediacy control* on Windows; the plane
   does not distinguish it from a toggle button, so a rule about which control a setting uses cannot
   be checked from the automation plane alone. Recorded, not filed as a defect.

## Never foregrounded — the measurement, not the promise

| sample | foreground hwnd | foreground pid | the target |
|---|---|---|---|
| before | 33950124 | 309940 | hwnd 101321550, pid 327340 |
| midwalk | 33950124 | 309940 | — |
| after | 33950124 | 309940 | — |

The probe shows itself with `AppWindow.Show(activateWindow: false)` (`SW_SHOWNOACTIVATE`), never
`Window.Activate()`. The walk calls no pattern method — no `Invoke`, `Toggle`, `Select`, `Expand` or
`SetFocus` — so it cannot move what it is reading.

The asserted invariant is **the target never held the foreground**, not *the foreground never
changed*. `planning/evidence/M34-oracle-lane.md` records the cost of the second phrasing: a check
that failed because frontmost went from Chrome to ghostty, neither of them the app under test.

**The assertion fired on a real run, and it was the lane's fault rather than the surface's.** That
is worth recording in full, because it is the only evidence that the check works on something other
than a doctored fixture.

An earlier run timed out waiting for the probe's window — WinUI cold start here is slow and variable,
and the 45-second default was too short — and `Stop-Lane` exited **without stopping the probe it had
started**. The leaked window later took the foreground. The next run stopped that stale probe a
moment before launching a fresh one, at which point Windows handed the foreground to the new probe,
because the previous owner had just died. `foreground.targetNeverFront` failed with
*the target held the foreground at midwalk, after*. Nothing had activated anything; the harness had
manufactured the condition through its own housekeeping.

Three fixes, none of them to the assertion:

- the probe process id is captured as soon as it launches and **every** exit path stops it, so no run
  can leak a window into the next one;
- the window-wait default is 180s, measured — one run took 53 seconds from launch to a window on the
  plane and the next took 19;
- the lane now **establishes the precondition before the probe exists**: it settles, reads who owns
  the foreground, writes it into the transcript, and returns NO VERDICT if nobody does. "The target
  never held the foreground" is only a measurement if something else held it, and on an empty desktop
  Windows will hand the foreground to the first window that appears.

The two runs recorded above both show `foreground before launch: … name=WindowsTerminal`.

## Unoracled, with the reason

| control | on-screen | reason | what would open a rung |
|---|---|---|---|
| `probe.command.exportLog` | Export log | `CommandBar.SecondaryCommands` are not realised while the overflow is closed. Absent from the control view **and** the raw view — not hidden, not built | the harness opens the overflow, which mutates the surface it is measuring and gives up the never-activated guarantee; **or** the command is also reachable from a surface realised at rest. The second is the fix |
| `probe.command.resetRouter` | Reset router | as above | as above |

This is a live finding against **DESIGN.md §11 rule 9** — every command reachable from one
enumerable in-window surface. On this construction the overflow half of a CommandBar is not
enumerable at rest. It belongs to WIN3's construction, not to the harness, and it is recorded here
so WIN3 inherits it rather than rediscovering it.

**The list is two-way.** A declared-unoracled control that turns up in either view *fails* the gate
(selftest arm 18). An absence-assertion passes for free the day it stops being able to fire.

## Falsifiability — 25 arms, both directions

`uia-selftest.py` hands each assertion a doctored dump and requires it to fire, then requires the
real dump to fire **none** of them. The control is the second half: a suite where every arm fires is
as uninformative as one where none do.

Twenty arms must produce exit 1 (a wrong name, a missing control, a duplicate id, a wrong control
type, a disabled control reporting enabled, an unselected selection, two items selected in a
single-selection list, a container naming the wrong selection, a container with no SelectionPattern,
a held toggle reading Off, a toggle that stopped publishing TogglePattern, a stripped busy marker, an
offscreen busy indicator, the target taking the foreground mid-walk, an unbracketed walk, a minimised
window, a tree from the wrong window, a declared-unoracled control turning up, an emptied expectation manifest, and a manifest that declares no floor of its own).

Four must produce exit **3** — an empty tree, no target window, a truncated walk, and a dump file
that is not there. Those four are the ones that keep a green tick from being spent on a window that
never existed, and they are armed as 3 rather than as 1 on purpose.

## Three things that were wrong and were caught by running the lane

None of these would have shown in a green run, and two were caught by the lane's own refusals.

1. **`MSBuild -t:Restore,Build` in one invocation cannot build a WinUI project from clean.** The
   project is evaluated before restore writes `obj/*.nuget.g.props`, so the Windows App SDK targets
   carrying the XAML markup compiler are never imported and the build fails
   `CSC : error CS5001: Program does not contain a static 'Main' method` — an error naming a missing
   entry point that is really a missing markup pass. From clean: one invocation exits 1, two exit 0,
   every time. `scripts/windows/verify.ps1` restores and builds separately now.
2. **`scripts/windows/verify.ps1` excluded every `.csproj` when run from a worktree.** The filter
   matched `\.worktrees\` against the absolute path, and every ship-feature runner verifies from
   inside `.worktrees/<ID>` — so it removed everything in the tree and printed
   `no .csproj yet - WIN3 has not landed the shell` while looking straight at one. It matches
   relative to `$root` now.
3. **The lane's hardcoded probe path was wrong, and the lane said so instead of passing.** It looked
   in `bin/x64/Debug/...`; `verify.ps1` builds with no `-p:Platform`, MSBuild defaults to AnyCPU, and
   the output lands in `bin/Debug/...`. The lane returned exit 3 — *no probe binary* — rather than a
   verdict. It searches for the newest `AutomationProbe.exe` now and writes the path it chose into
   the transcript.

A fourth and a fifth, in the harness itself, both above: the leaked probe process and the
window-wait that was too short for a WinUI cold start. A sixth, found by reading rather than by
running — **an emptied expectation manifest would have passed.** Every check iterates a list out of
that file, so a manifest trimmed by an edit or a bad merge produces zero failures and exit 0: a green
tick meaning *nothing was asked*, which is the empty-tree hole arriving from the oracle's side
instead of the subject's. The manifest declares its own floor now (`minimums`), the floor is asserted
before anything is graded against it, and two selftest arms cover both halves — an emptied manifest,
and a manifest with no floor to catch it.

A seventh, in the dump's own serialisation: `$list | Sort-Object` unrolls to a bare string when the
list holds one item, so `ConvertTo-Json` wrote a JSON *string* where every other row had an array.
A consumer iterating `patterns` would have iterated the characters of one pattern name and seen
plausible nonsense rather than an error. Wrapped in `@()`.

## The session-0 refusal, which is the reason any of this is trustworthy

An agent shell on this machine runs in **session 0** on window station `Service-0x0-…`. There, a
WinUI 3 process dies inside `Application.Start` with `STATUS_STOWED_EXCEPTION` (`0xC000027B`) before
any of our managed code runs, and a UIA walk **returns an empty list rather than an error**.

An empty tree satisfies every assertion about names and states for free. So:

- `probe-lane.ps1` refuses any station that is not `WinSta0`, with exit 3 and the reason;
- `uia-assert.py` returns exit 3 for an empty tree, an absent target, or a truncated walk;
- `run-probe-lane.ps1` schedules the lane into the interactive session with `schtasks /IT` and judges
  the outcome by `lane.json` on disk — **never** by `schtasks`' exit code, which prints
  `SUCCESS: Attempted to run` whether or not anything ran.

Confirmed: the interactive task reports `SESSION=1`, `STATION=WinSta0`, `INTERACTIVE=True`.

## Artifacts

| Path | What it holds |
|---|---|
| `planning/evidence/WIN20/run/uia-control-view.json` | the control-view tree, 36 elements |
| `planning/evidence/WIN20/run/uia-raw-view.json` | the raw-view tree, 65 elements |
| `planning/evidence/WIN20/run/assert-report.json` | 85 passed, 0 failed, 2 unoracled, each with its reason |
| `planning/evidence/WIN20/run/lane.json` | the lane's own verdict and exit code |
| `planning/evidence/WIN20/run/lane.log` | the transcript, including the binary it chose |
| `planning/evidence/WIN20/run/probe-startup.log` | the probe's own startup trace |
| `planning/evidence/WIN20/registry-rows.proposed.json` | SURF-029, REQ-036/037, CASE-0293…0296 — proposed, not written |
