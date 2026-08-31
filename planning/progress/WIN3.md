# WIN3 — the Windows app shell

**Status:** Developer Review. Built on `ai/win3`, rebased onto `main` at `bf062b4a`, gated, **not
verified**. A runner cannot verify its own build.

**Spec:** `planning/specs/spec-WIN3.md` · **Plan:** `planning/plans/plan-WIN3.md`

---

## 1 · What landed

A WinUI 3 window holding ten destinations and the command surface over them, and nothing that is
not the shell. `app/windows/` is new and holds three projects:

| Project | What it is |
|---|---|
| `MCPRouter.Shell.Model` | Plain `net8.0`, no WinUI. The destination catalogue, the command catalogue, the accelerators, the availability model. Everything a gate needs to read |
| `MCPRouter.Shell` | The WinUI 3 app: Mica, the caption band and its MenuBar, the NavigationView, the board placeholder, the self-test |
| `MCPRouter.Shell.Tests` | xunit over the model, `DESIGN.md` §13 and `design/mcp-router-console.html`. 173 tests |

Plus `scripts/windows/build-shell.ps1`, `scripts/windows/run-shell-selftest.ps1`, and two fixes to
`scripts/windows/verify.ps1` (§4).

## 2 · The decision the item existed to make

DESIGN.md §3 rule 9 makes the macOS menu bar the complete command surface. Windows has no global
menu bar, so that surface cannot exist here, and §11 rule 9 already restates the guarantee against
what Windows does have — one enumerable in-window surface, every command on it carrying an access
key.

**Taken: a MenuBar, in the window's own caption band.** `spec-WIN3.md` §3.1 carries the table; the
short version is that a CommandBar is a *view's* command set by construction and per-board
CommandBars give thirteen enumerable places instead of one, which is the completeness property
failing rather than being restyled. What the losing options would have been better at is recorded
there rather than dropped: a single app-level CommandBar is closer to the idiom most new Windows
11 apps reach for, and per-board bars have the best per-board ergonomics and the only construction
that scales as thirteen surfaces grow their own actions.

**Cross-family review of this call did not run.** `codex`, `agy` and `grok` are absent on this
machine, and the `claude` CLI returns *"your organization has disabled Claude subscription
access"*. Recorded not-run. It is the one decision in this item that most wanted a second family.

## 3 · Evidence

Every command below was run on this machine on 2026-08-30, from the `ai/win3` worktree.

| What | Command | Result |
|---|---|---|
| Windows lane | `scripts/windows/verify.ps1` | **exit 1** — 26 passed, 4 failed, 4 not-run |
| The same lane on `main` | `scripts/windows/verify.ps1` from `C:\Dev\mcp-router` | **exit 1** — 19 passed, **the same 4 failed**, 4 not-run |
| Shell build | `scripts/windows/build-shell.ps1` | exit 0, and `MCPRouter.Shell.exe` on disk |
| Model gates | `dotnet test app/windows/MCPRouter.Shell.Tests` | exit 0 — **173 passed, 0 failed** |
| Shell self-test | `scripts/windows/run-shell-selftest.ps1` | exit 0 — 10 destinations walked, 2 appearances forced, 12 PNGs written, 0 failures |
| Citation gate | `python planning/citation-gate.py` | ratchet 1, **blocking 0**; no file of this item's is among the four offenders |

**The four failing gates are `main`'s and not this item's**, and that is checked rather than
assumed: `target-resolution-gate.py` and `carrier-parity-gate.py` produce byte-identical output on
`main` and on this branch. `citation-gate.py` differs only by the other runners' live edits
(`WIN17`'s brief and `planning/goals/win17-gapfix.js`), and `spec-WIN3.md` was on that list until
its one bare citation was given an anchor and a tree — it is off it now. `sweep-control-gate.py`
fails on both. **No ratchet was raised and no test was edited to pass.**

The lane's delta from `main` is +7 passes: three projects × (restore, build), plus the model tests.

### What the self-test holds, and what it cannot

`selftest.json` and twelve PNGs, at
`%LOCALAPPDATA%\mcp-router-win3-selftest`. Read from that report: system theme `Dark`,
rasterization scale `1.5`, 10 destinations, 44 commands on the surface.

The captures are `RenderTargetBitmap` renders of the XAML tree. They **do not** contain the Mica
backdrop, which composites below XAML, and they **do not** contain the system caption buttons,
which are not XAML at all. Those two claims are therefore **unphotographed** — the report says so
in its own text rather than letting a picture that cannot contain them stand as evidence that it
did.

## 4 · Three things the lane got wrong, found by using it

1. **`MSBuild -t:Restore,Build` in one invocation cannot build a WinUI project from a cold
   `obj/`.** It fails `CS0103: The name 'InitializeComponent' does not exist in the current
   context`, because the Build target evaluates before Restore has written the WindowsAppSDK
   targets that add the XAML markup-compile passes. Two separate invocations succeed on the same
   tree. Measured both ways. `verify.ps1` shipped with them combined — correct for a repo with no
   WinUI project in it, wrong from the moment this item landed one.
2. **`verify.ps1`'s project glob excluded any path containing `\.worktrees\`.** Run from inside a
   worktree — which is how every runner runs it — the exclusion matched the tree being verified
   and found nothing, then reported `NOT-RUN — no .csproj yet`. A lane that cannot see the code it
   is pointed at, saying the code does not exist. The exclusion is now taken against the path
   relative to the repo root.
3. **WIN1's WindowsAppSDK 1.6 pin does not run on this machine.**
   `Microsoft.WindowsAppRuntime.1.6` is not installed (1.5, 1.7, 1.8 and 2.x are), and an
   unpackaged 1.6 build launches into a *"This application could not be started"* dialog with a
   live process behind it — a process that is alive, has a window, and has done nothing. The shell
   pins **1.7** and builds `WindowsAppSDKSelfContained`, so it depends on no machine-installed
   runtime at all.

## 5 · Two defects the self-test found in this item's own code

Both were green to every other check and would have shipped.

1. **Settings was unreachable.** `NavigationView.SettingsItem` is created by the control's
   template, which has not been applied while the window's constructor runs, so it was `null`
   there and the pane-footer item was never registered. `SelectDestination("settings")` then found
   nothing and returned silently, leaving whichever board was showing. The self-test caught it as
   *"settings: window title is 'Insights', expected 'Settings'"*. The wiring moved to `Nav.Loaded`,
   and the silent return is now a throw.
2. **Two brushes were resolved from `Application.Current.Resources`,** which resolves under the
   *app's* theme rather than the element's. The light-appearance capture came back as light content
   sitting on a dark ground with the navigation pane unreadable. Both are now XAML
   `{ThemeResource}` lookups, and the window-activation handler that held one of them is gone
   entirely — DESIGN.md §11 records that macOS's `--tl-off` has no Windows counterpart, and the
   same argument reaches the title beside the caption buttons.

## 6 · Named gaps, carried rather than closed

1. **Nothing here has been photographed on the interactive desktop, and it cannot be from this
   session.** Measured: this agent session is **Session 0** on window station
   `Service-0x0-12a65c80$`, `UserInteractive` false. A WinUI process started from it dies with
   `0xC000027B` — a stowed `E_INVALIDARG` from `Microsoft.UI.Xaml.dll` — **before the App
   constructor runs**; there is no window and no log. Started from a scheduled task created with
   `/it` it reaches `OnLaunched` and activates its window, which is why the self-test works. But
   that task's own window station enumerates **zero** top-level windows and
   `GetUserObjectInformationW` returns an empty name, so `EnumWindows` and `CopyFromScreen` see
   nothing from there either. Closing this needs a person at the desktop, or a channel WIN20's
   automation plane finds that this probe did not. **The same crash was observed in WIN20's own
   `AutomationProbe.exe` in the Windows Application log during this run**, at a different
   WindowsAppSDK version, which is what says it is the session and not the project.
2. **The sidebar foot readout is not built.** DESIGN.md §2's `The sidebar foot (specified)` puts a
   `Child processes` card and a `127.0.0.1:<port>` line below the destinations on every board, and
   calls them the shared wrapper's — so they are the shell's. Every value in both is
   router-observed, this shell has no control client, and §6 forbids displaying a number the
   router does not observe. Built now, all four of its states would collapse to the one §2 calls
   *Nothing has ever answered*, which draws nothing. Carried to the item that lands the Windows
   control client.
3. **`Ctrl+5` and `Ctrl+9` are unbound.** DESIGN.md §13 omits them because Harnesses and Insights
   do not exist on macOS. On Windows both boards open, so the stated reason has expired — but
   binding a chord the design authority does not carry would be this build editing its own spec,
   and the parity gate reads that table in both directions. Routed to **WIN21**, the Windows
   keyboard model, which is blocked on this item. Both boards stay reachable by the pane, by the
   View menu and by `Alt` `V` and their access key, so §11 rule 9's guarantee is untouched.
4. **The icon set is Segoe Fluent `SymbolIcon`s, not the design of record's sprite.** §13 prefers
   the sprite drawn as a `PathIcon`, and that route is closed: the mock's sprite is **stroked**
   (`fill:none` plus a 1.4 stroke) and `PathIcon` fills its path, so the marks would render as
   solid blobs. `ImageIcon` over an `SVGImageSource` would draw them correctly and would break
   §13's other requirement, that icons are monochrome and drawn in `Foreground` — an
   `SVGImageSource` carries its own colour. Converting the strokes to filled outlines is icon-set
   work rather than shell work. One concrete consequence is worth naming: **Insights currently
   draws a magnifier, which collides with Find and Search in this same app.**
5. **A disabled command's reason is reachable only through the accessibility plane** for the three
   commands that also carry a chord. A disabled control takes no pointer input, so a tooltip on it
   never shows; the other unbuilt commands say `Not built` in the accelerator column, which those
   three have spent on their chord. Every one of them carries the full sentence in
   `AutomationProperties.HelpText`.
6. **Increased contrast / High Contrast is unmeasured**, as DESIGN.md §11 already records for the
   whole Windows floor.

## 7 · Not done here, by design

No control API client and no live values anywhere. No Signal Path — DESIGN.md §13 makes the plug's
accent collision the first thing to settle and that is WIN4's. No notification-area presence
(WIN11), no toasts (WIN22), no packaging (WIN19), and no UI Automation harness (WIN20, running in
parallel).
