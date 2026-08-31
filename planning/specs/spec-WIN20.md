# WIN20: a Windows automation plane, so the campaign can measure a Windows surface at all

**Category:** harness · **Brief:** `planning/features-to-triage/WIN20-windows-automation-plane-for-the-test-campaign.md`
**Related:** WIN1 (framework decision — this is the measurement behind it), WIN3 (the shell, not yet
drawable), WIN18 (the Windows verification lane, extended here), WIN2/§11–§13 (the Windows floor).

The campaign does not judge a surface by screenshot. Each case stands on a rung of oracle, and every
rung above `touch` needs a channel that publishes what a surface actually contains. On macOS that is
the accessibility plane. Thirteen Windows surfaces have no such channel recorded anywhere in the
registry, which is why the brief says they can only ever be reported `never-measured` — the class
`reckon` names as neither a pass nor a failure, and the one that turns a partial campaign into a
finished-looking product.

**What this item establishes is the channel, measured on a real window.** It does not measure the
product, because there is no product window to measure: WIN3 has landed no `.csproj` and no drawable
shell. Everything below was taken against a WinUI 3 probe window this item builds, and every artifact
says so in its own text rather than leaving a reader to infer it.

---

## 1 · What was measured, and on what

Measured on **LUKESFF**, Windows 11 Pro 10.0.26200, **2026-08-30**.

| reading | figure |
|---|---|
| framework under test | WinUI 3 / Windows App SDK **1.8.260804001**, unpackaged, self-contained |
| target | `MCPRouter.AutomationProbe`, `app/windows/AutomationProbe/` |
| UIA client | `System.Windows.Automation` (.NET Framework), Windows PowerShell 5.1, **out of process** |
| elements, control view | **36** |
| elements, raw view | **65** |
| graded assertions | **90 passed, 0 failed, 2 unoracled** |
| armed assertions in the selftest | **26 arms, 0 misbehaved** |

---

## 2 · The acceptance, clause by clause

The brief's acceptance sketch has six clauses. Each one below names what settles it and where the
number came from. Two are answered by the probe, not by the product, and say so.

| # | Clause | Verdict | Evidence |
|---|---|---|---|
| 1 | every surface's controls are individually addressable, names matching the on-screen vocabulary | **met, on the probe** | 20 controls asserted by `AutomationId`; each resolves to exactly one element and each `Name` equals the manifest's word. `assert-report.json` |
| 2 | disabled · selected · held · busy readable from the plane, not from pixels | **met, on the probe** | `isEnabled=false`; `SelectionPattern`+`SelectionItemPattern`; `TogglePattern.ToggleState=On`; the busy marker in the name. §4 below |
| 3 | enumerate out of process without activating or foregrounding | **met** | the walk is a UIA client in a separate process; three bracketed `GetForegroundWindow` samples, none of them the target. §5 |
| 4 | a surface whose controls are not addressable is `unoracled` with the reason | **met** | 2 rows, and the rule is two-way: a declared-unoracled control that turns up FAILS. §6 |
| 5 | the framework's automation behaviour measured on a real window before thirteen surfaces are built on it | **met, and this is the item's point** | §1 |
| 6 | screen readers benefit as a consequence | **not measured here** | the same tree serves Narrator by construction, but nothing in this item drove a screen reader. Recorded as unmeasured rather than claimed. |

---

## 3 · Addressability, and what "individually" costs

Every control carries an explicit `AutomationProperties.AutomationId`, and the gate requires each id
to resolve to **exactly one** element. The duplicate case is a failure rather than a warning: two
controls under one id are not individually addressable, which is the clause word for word.

The names are **not** generated from `MainWindow.xaml`. `scripts/windows/uia/probe-expectation.json`
is written by hand from DESIGN.md §11 and from REQ-003's eight destination words, so a Windows
destination and its Mac twin are the same word rather than two. A manifest generated from the thing
it checks moves whenever the subject moves and can never fail.

---

## 4 · The four states, and the one that is not where you would look

| state | channel | reading |
|---|---|---|
| disabled | `IsEnabled` property | `probe.button.removeServer` reads `false` while `probe.button.pairServer` reads `true` |
| selected | `SelectionPattern` on the container **and** `SelectionItemPattern` on the item | the NavigationView publishes `selection: ["Servers"]`; the ListView publishes `["GitHub"]`; every sibling reads `isSelected: false` |
| held | `TogglePattern.ToggleState` | `probe.command.holdQueue` and `probe.switch.pauseRouting` both read `On` |
| busy | **the Name, not a pattern** | `probe.status.busyRing` publishes `ControlType.ProgressBar` and the name `"Busy Starting upstream"` |

**Busy is the finding.** An active WinUI `ProgressRing` publishes as `ControlType.ProgressBar` and
WinUI **prepends the localised word "Busy"** to the automation name. It exposes no `RangeValuePattern`
state a reader could use, so the busy state is carried in a string. That is readable, and it is
readable in the way a screen reader announces it — but a harness that went looking for a pattern would
find nothing and would have to fall back to pixels. The gate asserts the marker explicitly for that
reason, and the assertion is armed (strip "Busy" from the name and it fires).

The selected state is asserted twice, on two different providers — a NavigationView and a ListView —
because one provider agreeing with itself is one measurement, not two.

---

## 5 · Never foregrounded, and the shape of the claim

The acceptance says *without activating or foregrounding*. Two things make that a measurement rather
than a promise:

- **The probe never activates itself.** `App.OnLaunched` calls `AppWindow.Show(activateWindow: false)`
  — `SW_SHOWNOACTIVATE` — instead of `Window.Activate()`. A probe that grabbed the foreground at
  startup would make the claim untestable for the first seconds of its life.
- **The walk samples the foreground three times** — before, mid-walk and after — and records each
  sample's `hwnd` and `pid` beside the target's own in the dump.

The asserted invariant is *the target never held the foreground*, **not** *the foreground never
changed*. `planning/evidence/M34-oracle-lane.md` records what the second one costs: a check that
failed because frontmost went from Chrome to ghostty, neither of them the app under test.

Measured: `hwnd 33950124 / pid 309940` at all three samples, against a target of `hwnd 101321550`.

---

## 6 · What is unoracled, and why the list cannot grow quietly

Two controls are reported `unoracled` with the reason, following M34's convention rather than passing
quietly:

| control | reason | what would open a rung |
|---|---|---|
| `Export log` | a `CommandBar`'s `SecondaryCommands` are not realised while the overflow is closed. Absent from the control view **and** the raw view — not hidden, not built. | either the harness opens the overflow, which mutates the surface it is measuring and gives up the never-activated guarantee, or the command is also reachable from a surface realised at rest. **The second is the fix.** |
| `Reset router` | as above | as above |

This bears directly on **DESIGN.md §11 rule 9** — every command reachable from one enumerable
in-window surface. On this construction the overflow half of a CommandBar is not enumerable at rest,
so a Windows surface that hides a command there cannot be measured for that rule without being
touched. The rule and the plane disagree, and the finding belongs to WIN3's construction rather than
to this harness.

**The list is two-way.** A declared-unoracled control that turns up in either view **fails** the gate.
An absence-assertion passes for free the day it stops being able to fire, and from outside "correctly
did not fire" and "could not fire" are the same silence — so the day one of these becomes addressable,
the row has to move rather than sit there collecting a pass.

---

## 7 · Where the lane has to run, and why that is not a detail

**An agent shell on this machine runs in session 0, on window station `Service-0x0-…`.** Two things
follow, and they compose into exactly the failure this repository keeps naming:

- a WinUI 3 process started there dies inside `Application.Start` with `STATUS_STOWED_EXCEPTION`
  (`0xC000027B`), before any managed code of ours runs;
- a UIA walk there cannot see the interactive desktop and returns an **empty list rather than an
  error**.

An empty tree satisfies every assertion about names and states for free. A lane that ran in session 0
and reported green would be reporting a green tick for a window that never existed. So `probe-lane.ps1`
**refuses** that station with exit 3, and `run-probe-lane.ps1` schedules itself into the interactive
session with `schtasks /IT` and judges the result by `lane.json` on disk — never by `schtasks`' own
exit code, which prints `SUCCESS: Attempted to run` whether or not anything ran.

---

## 8 · The registry rows this item owes, and why they are proposed rather than written

`planning/evidence/WIN20/registry-rows.proposed.json` holds the surface, requirement and cases the
campaign needs for the Windows plane. They are a **proposal**, not an edit, for one reason:
`cases.json` and `inventory.json` are generated by `campaign.py`, which measures a macOS app and
cannot run on Windows. Hand-editing an input while its derived view stays stale is the same
"a registry a person edits cannot also be the witness that the edit was earned" failure the repo's own
gates are built against.

One near-miss is recorded because it is the kind that reads as fine: the first surface id tried was
**SURF-018, which looked free** — `surfaces.in.json` stops at SURF-017 for the glass lanes — and
**is taken** in `inventory.json` by an ios-glass surface. The two files disagree because the inventory
is generated from more sources than the input. The proposal uses **SURF-029**.

---

## 9 · Two defects found in WIN18's lane, and fixed here

Both were found by using the lane rather than reading it.

1. **`MSBuild -t:Restore,Build` in one invocation cannot build a WinUI project from clean.** The
   project is evaluated once, before restore writes `obj/*.nuget.g.props`, so the Windows App SDK
   targets carrying the XAML markup compiler are never imported, no `App.g.i.cs` is generated, and the
   build fails `CSC : error CS5001: Program does not contain a static 'Main' method`. The error names a
   missing entry point and is actually a missing markup pass. From clean, one invocation exits 1 and
   two exit 0, deterministically. The lane now restores and builds separately.
2. **The `.csproj` search excluded every project when run from a worktree.** The exclusion matched
   `\.worktrees\` against the **absolute** path, and every ship-feature runner verifies from inside
   `.worktrees/<ID>`, so the filter removed everything in the tree and the lane printed
   `no .csproj yet - WIN3 has not landed the shell` while looking straight at one. It matches the
   path relative to `$root` now. A skip that reads like a fact about the repository is worse than a
   failure, because nobody goes and checks it.

---

## 10 · What this does not establish

- **Nothing about the MCP Router Windows client.** There is no such window yet. Every figure here is
  WinUI 3's behaviour on this machine, and the harness is pointed at the product the day WIN3 lands.
- **Nothing about the thirteen Windows surfaces.** They stay `never-measured` until they exist. What
  changes is that the channel to measure them is now built, armed and enrolled.
- **Nothing about Narrator.** Acceptance clause 6 is recorded unmeasured.
- **Nothing about rendering.** UIA publishes bounding rectangles and realisation, not pixels — the
  same boundary §M34 draws for `NSMenu.size`.
