---
status: completed
found-by: intake, from the owner's directive that Windows reach feature and UI parity with macOS · 2026-08-30
registry-target: none
no-target-reason: the registry has since gained nineteen Windows rows (SURF-029..SURF-047, SURF-050, REQ-031, REQ-035..REQ-038), so the original reason - that it holds no Windows surface at all - is no longer true. It is still true that no registry entity states WHICH UI FRAMEWORK the client is built on: SURF-030 records the shell the decision produced, not the decision. Corrected 2026-09-03, we4.
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

## Decided — 2026-08-30

**WinUI 3 / Windows App SDK**, by the owner, after the three candidates were probed on this
machine. The probes, so nobody re-derives them:

| Candidate | Result on this machine, 2026-08-30 |
|---|---|
| WinUI 3 (`Microsoft.WindowsAppSDK` 1.6) | `dotnet restore` succeeds. `dotnet build` **fails**: `MSB4062`, the `ExpandPriContent` task cannot be loaded from `Microsoft.Build.Packaging.Pri.Tasks.dll` under the .NET SDK's `Microsoft/VisualStudio/v17.0/AppxPackage/`. Retried unpackaged with `WindowsPackageType=None`, `EnableMsixTooling=false`, `DisableMrtCore=true` — **same error**, so the PRI step is unconditional and not a packaging-mode artefact. |
| Avalonia 11 + Fluent theme | Builds clean on the bare .NET 8.0.424 SDK in 7.3 s, no workload, no install. |
| WebView2-hosted | Not probed. Edge WebView2 is an OS component on this build, so it needs no runtime install. |

What the losing options would have been better at, recorded rather than dropped: **Avalonia** starts
today with nothing installed, and **WebView2** is the only candidate that could render the existing
4,814-line design of record more or less directly. Both were set aside for the same two reasons —
neither publishes the native Windows 11 control vocabulary the directive asks for, and neither gets
a UI Automation tree for free, which WIN20 shows is what decides whether the campaign can measure a
Windows surface at all or has to file thirteen of them as never-measured.

The cost is accepted deliberately: WinUI 3 needs Visual Studio Build Tools 2022 installed
(`Microsoft.VisualStudio.2022.BuildTools`, with the managed-desktop and UWP build-tool workloads and
the Windows 11 SDK). The owner authorised that install on 2026-08-30.

**The lane is proved, and it is not `dotnet build`.** Measured after the install, same probe project:

| Invocation | Result |
|---|---|
| `dotnet build` | **fails** — `MSB4062`, still looking under `C:\Program Files\dotnet\sdk\9.0.316\Microsoft\VisualStudio17.0\AppxPackage\`, which does not exist |
| `MSBuild.exe` from `…2\BuildTools\MSBuild\Current\Bin` with `-t:Restore,Build` | **Build succeeded, 0 errors, exit 0** |

So the Windows lane invokes Visual Studio's `MSBuild.exe`, and WIN18 inherits that as a measurement
rather than a preference. `dotnet build` resolves `MSBuildExtensionsPath` to the .NET SDK, which
carries no `AppxPackage` tasks however complete the Visual Studio install is; the two do not
converge by installing more.

**Two false greens on the way in, recorded because the next person will hit them.** `winget install`
reported exit 0 while printing `Installer failed with exit code: 1`, and `setup.exe modify` run
without elevation reported exit 0 while logging `Exit Code: 87` and leaving the component absent. In
both cases the wrapper's status said nothing about whether the work happened. The install only took
effect run elevated, and the check that settled it was the presence of
`Microsoft.Build.Packaging.Pri.Tasks.dll` on disk, not any exit code.

## Assumptions made writing this

- Assuming the Windows client is a separate application rather than a port of the Swift sources, since no Swift toolchain targets Windows and the shared contract is the loopback control API.
- Assuming the three candidates above are the field; a fourth (MAUI, Tauri, Electron) is not ruled out but none was named by the directive and none obviously beats all three.
- Assuming this repository hosts the Windows client rather than a sibling repo, because the mock HTML, DESIGN.md and the control API contract all live here.
