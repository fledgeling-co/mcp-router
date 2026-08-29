---
status: to-triage
found-by: intake, from the owner's directive that Windows reach feature and UI parity with macOS · 2026-08-30
registry-target: none
no-target-reason: the campaign registry holds no Windows surface, case, requirement or defect, so nothing in it could answer a question about which Windows UI framework the client is built on
---

# Decide which UI framework the Windows client is built on, before any Windows surface is drawn

- origin: owner directive, 2026-08-30 — "i want windows to have feature and ui parity with macos"
- audience: every later Windows brief, all of which inherit this answer and none of which can be finished without it
- platforms: windows

## What and why

Thirteen Windows surfaces are briefed alongside this one. Each of them draws controls, and the
control vocabulary is a property of the framework, not of the surface. Picking per-surface means
picking thirteen times and getting thirteen answers, so this is settled once, first, and the rest
inherit it.

Three candidates, each losing on something real:

- **WinUI 3 / Windows App SDK.** The native answer: Mica, Fluent controls, per-monitor DPI and the
  UI Automation plane come for free, and the result is the Windows 11 look the directive asks for
  without it being reimplemented. Costs a workload install this machine does not yet have, and it
  is the heaviest of the three to build headlessly.
- **WebView2-hosted.** Measured on this machine: Edge WebView2 is an OS component on this Windows 11
  build, so it needs no runtime install. It is also the only option that can render the existing
  mock HTML more or less directly, which is a real saving given the mock is the source of layout and
  vocabulary. It loses the native control vocabulary and, more seriously, publishes a DOM rather
  than a UI Automation tree — see WIN20, which is what lets the campaign measure a Windows surface
  at all.
- **Avalonia.** Cross-platform and buildable with the .NET 8 SDK already present, no workload
  needed. It draws its own controls rather than hosting the system's, so Fluent conformance becomes
  something this repo maintains rather than something it inherits.

The reason this is a brief and not an assumption line: the three differ on what a Windows surface
*is* to the test campaign, and DESIGN.md §5 holds that the states are the design. A framework whose
disabled, empty and error states are drawn by the system is a different product from one where they
are drawn here.

## Acceptance sketch

- One framework is named, with the losing two named alongside and what each would have been better at.
- The answer says what the choice costs to install on a clean Windows 11 box, measured rather than assumed.
- The answer says which automation plane the choice publishes, and WIN20 is reconciled against it.
- A trivial window built with the chosen framework opens, draws, and is photographed on this machine — so the lane is proved before thirteen surfaces are committed to it.
- Whether the router daemon ships inside the client or beside it is answered, since two of the three candidates change that calculus.

## Assumptions made writing this

- Assuming the Windows client is a separate application rather than a port of the Swift sources, since no Swift toolchain targets Windows and the shared contract is the loopback control API.
- Assuming the three candidates above are the field; a fourth (MAUI, Tauri, Electron) is not ruled out but none was named by the directive and none obviously beats all three.
- Assuming this repository hosts the Windows client rather than a sibling repo, because the mock HTML, DESIGN.md and the control API contract all live here.
