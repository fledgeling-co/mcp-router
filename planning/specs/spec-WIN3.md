# spec-WIN3 — the Windows app shell

| | |
|---|---|
| ID | WIN3 |
| Status | **Developer Review** — built on `ai/win3`, gated, not verified. A runner cannot verify its own build |
| Category | windows · new surface · the shell every board is drawn inside |
| Depends on | WIN1 ✓ (WinUI 3, and the MSBuild lane) · WIN2 ✓ (DESIGN.md §11–13) · WIN18 ✓ (`scripts/windows/verify.ps1`) |
| Blocks | WIN4–WIN11, WIN13–WIN16 (the thirteen surfaces) · WIN19 · WIN21 · WIN22 |
| Brief | `planning/features-to-triage/WIN3-windows-app-shell.md` |
| Source of layout, IA and vocabulary | `design/mcp-router-console.html` (design of record, settled 2026-08-22) |
| Source of the visual language | `DESIGN.md` §11 · §12 · §13 |
| Triage | 2026-08-30 |

---

## 1 · What this item is

A WinUI 3 window that holds ten destinations and a command surface, and draws nothing that is
not the shell. Nine boards plus Settings, each drawing an honest empty state that names the item
which will fill it. Every later Windows surface is drawn inside this window and inherits its
chrome, its keyboard, its theme handling and its title rule.

It is not a client of the router. Nothing here reads the control API, and that is deliberate —
see §6.

## 2 · The question this item exists to answer

DESIGN.md §3 rule 9 makes the macOS menu bar the complete command surface: every command is
reachable from it, which is what makes the app keyboard-complete and inspectable. Windows has no
global menu bar, so the surface the rule names does not exist. §11 rule 9 already restates the
*guarantee* against what Windows has — one enumerable in-window surface, every command on it
carrying an access key, so `Alt` enumerates the whole command set without a pointer — and leaves
open which surface carries it.

**Decided: a MenuBar, drawn in the window's own title-bar band.** §3.1 records the alternatives
and what each would have been better at.

## 3 · The decisions

### 3.1 The command surface — a MenuBar, not a CommandBar

§11 rule 9 permits two constructions: "a MenuBar at the top of the app window, or a CommandBar
whose overflow carries the secondary commands". They are not equivalent under the guarantee.

| Option | What it would have been better at | Why it loses here |
|---|---|---|
| **MenuBar** (taken) | — | — |
| **A single app-level CommandBar** | Closer to the Windows 11 idiom most new apps reach for, and it puts the two or three commands a user actually wants within one click rather than two | A CommandBar is a *view's* command set by construction — its overflow carries that view's secondary commands. Making one carry the whole app's command set means every board's bar holds every command, which is the completeness guarantee bought by making the surface useless as a per-board bar |
| **Per-board CommandBars** | The best per-board ergonomics of the three, and the only one that scales as the thirteen surfaces each grow their own actions | Fails the guarantee outright. Thirteen surfaces means thirteen enumerable places, and "every command is reachable from one place" is exactly what stops being true. This is the option that loses a property rather than restyling one |
| **A title-bar overflow button (`…`)** | Smallest chrome footprint of the four | The command set is enumerable only after a click, and a flyout of forty items with no grouping is a worse inspection surface than a menu bar. It also has no published Windows guidance behind it, so it would be this document inventing an idiom |

The MenuBar sits **in the title-bar band**, left of the board title, rather than in a row of its
own. Windows 11's own apps put commanding in the caption band (Notepad, Paint, File Explorer),
and a second full-width chrome row under a 32-epx title bar spends 32 epx to say nothing.

**What this costs, stated rather than argued away.** A MenuBar reads as the more classic of the
two Windows idioms, and a reader who expects a CommandBar will notice. That is accepted: the
guarantee §3 rule 9 makes is a property of the product, and the directive is parity of feature
with Windows in look — not the reverse.

**Cross-family review of this call was not available.** `codex`, `agy` and `grok` are absent on
this machine and the `claude` CLI returns *"your organization has disabled Claude subscription
access"*. Recorded as **not-run**, never as a pass.

### 3.2 Every command is on it, including the ones with nothing behind them

The design of record's menu bar declares roughly forty commands. The shell can perform six of
them. The other thirty-odd are on the surface, **disabled, with a discoverable reason** naming
the item that will build them — DESIGN.md §5's `Disabled` row, §11 rule 4's "disabled dims in
place and never disappears", and M14's precedent on the Mac.

A command dropped until its feature lands would make the completeness guarantee true only of a
command set that shrinks to fit, which is the guarantee failing quietly.

Two menus in the design of record do **not** cross, and each is a Windows fact rather than a cut:

- **The app menu.** Windows has no per-app menu; `About`, `Settings` and `Exit` are redistributed
  — `About` to Help, `Settings` to the navigation pane's own footer item (§13: "the navigation
  view carries an optional entry point for app settings … which is where a Windows user looks"),
  `Exit` to File.
- **The Window menu.** Windows has no window menu; minimise, maximise and close are the system's
  caption buttons and an app that redraws them is painting chrome that is not its own
  (§11's "three things Windows has no counterpart for").

One command is **removed rather than moved**: View → *Switch appearance*. On Windows the theme is
the system's and the app follows it live (§4.4); an in-app override would make the app the
authority on a setting Windows owns.

### 3.3 `Ctrl+5` and `Ctrl+9` stay unbound, and Harnesses and Insights are still reachable

DESIGN.md §13's keyboard table binds `Ctrl+1`–`Ctrl+4` and `Ctrl+6`–`Ctrl+8`, and states why
`Ctrl+5` and `Ctrl+9` are absent: Harnesses and Insights do not exist, and "a row for a board the
app cannot open is a binding this document states and the app cannot honour".

On Windows both boards *do* open — they draw their empty state like the other eight. So the
reason §13 gives has expired on this platform, and the honest reading is that the two chords
could now be granted.

**They are not granted here.** DESIGN.md is the design authority and its table is read by this
item's parity gate in both directions; a shell runner binding a chord the table does not carry
would be a build editing its own spec. The question — whether the Windows table diverges from the
macOS one on these two rows — belongs to **WIN21**, the Windows keyboard model, which is blocked
on this item and is where a keyboard divergence should be argued.

Nothing is lost meanwhile: §11 rule 9's guarantee is that no command is reachable *only* by a
chord. Harnesses and Insights are reachable by the navigation pane, by View → their menu item, and
by `Alt` `V` and their access key. The gap is a convenience, and it is named rather than hidden.

### 3.4 The title says the board

`Window.Title` and the title drawn in the caption band are both the destination's name —
`Servers`, `Discover`, `Settings` — never `MCP Router`. §11 rule 7, and §3 rule 7 before it. The
app's name appears in the taskbar tooltip the system composes and nowhere the app draws.

### 3.5 The sidebar foot readout is deferred, with its reason

DESIGN.md §2's `The sidebar foot (specified)` puts a `Child processes` readout card and a
`127.0.0.1:<port>` line below the destinations "on **every** board — they belong to the shared
wrapper rather than to a surface", which makes them the shell's.

They are **not built here.** Every value in both is router-observed: a running-child count, a
60-second trace, and the port the router actually answered on. This shell has no control client,
and §6's last bullet — "numbers the router does not observe are never displayed" — forbids
standing a plausible figure in the gap. The four states §2 specifies would collapse to the one it
calls *Nothing has ever answered*, which draws nothing, so building it now would ship an element
that is indistinguishable from its own absence.

Carried to the item that lands the Windows control client. The gap is recorded in §7.

## 4 · What is built

### 4.1 The window

A single unpackaged WinUI 3 window. `SystemBackdrop` is `MicaBackdrop` — §11 rule 3's "apply Mica
or Mica Alt as the base layer of your app", once, and on nothing else. The content layer above it
takes `LayerFillColorDefaultBrush`; the navigation pane and content host are transparent so the
material shows through. When transparency is off or the window is inactive, Windows falls the
backdrop back to `SolidBackgroundFillColorBase` itself and the app inherits that (§13) rather
than implementing it.

`ExtendsContentIntoTitleBar` is true and the caption band is the app's: app icon, MenuBar, drag
region, board title, drag region. The three caption buttons stay the system's.

### 4.2 The ten destinations

A `NavigationView` in left mode, its items and grouping taken from the design of record's sidebar
(`design/mcp-router-console.html:1832–1878`) rather than restated:

| Group | Destinations |
|---|---|
| Store | Discover · Skills |
| Routing | Servers · Activity · Harnesses |
| Maintenance | Checks · Cleanup |
| Attention | Inbox · Insights |
| *(pane footer)* | Settings — the NavigationView's own settings item |

Selection is the platform's: NavigationView draws the 3×16 radius-2 indicator on the leading edge
at `AccentFillColorDefaultBrush` and leaves the label at `TextFillColorPrimaryBrush`, which is
§11 rule 1 satisfied by the control rather than reimplemented.

Each destination draws a board placeholder: the board's name, one sentence saying what the board
will show, and one sentence naming the item that builds it. That is DESIGN.md §5's `Empty` row —
"never a bare 'No items'" — read for a surface whose emptiness is the build's rather than the
data's.

### 4.3 The keyboard

DESIGN.md §13's table, in full, and nothing that is not in it:

- `Ctrl+N`, `Ctrl+F`, `Del` and `Ctrl+1`–`4`, `Ctrl+6`–`8` are menu accelerators.
- `Alt` reveals the access keys — every menu title and every menu item carries one.
- `F6` / `Shift+F6` cycle panes; `Tab` moves within a pane.
- `Return`, `Esc` and `Space` are declared behaviours the shell registers and no later surface has
  to rediscover.

The focus visual is the platform's high-visibility one (§11 rule 11) — 2px over 1px, neutral,
never accent-bound — inherited from the WinUI default rather than restyled.

### 4.4 Theme and DPI

`RequestedTheme` is never set. `ElementTheme.Default` follows the system, `ActualThemeChanged`
fires when the user changes it while the app runs, and the caption-button colours are re-resolved
on that event so the band does not keep the old appearance's foreground. The Mica backdrop
re-resolves itself.

Per-monitor DPI comes from `app.manifest`'s `PerMonitorV2` plus XAML's own scaling. The shell
records `XamlRoot.RasterizationScale` and re-reads it on `XamlRoot.Changed`, so a DPI change is an
observable event rather than a hope.

### 4.5 The self-test

`MCPRouter.Shell.exe --selftest <dir>` drives the shell through all ten destinations in-process,
and for each writes a `RenderTargetBitmap` PNG plus a JSON row carrying the window title, the
selected destination, the resolved theme and the rasterization scale. It then forces light and
dark on the root element and captures both.

It exists because **this repository's agent session cannot photograph a window**: it runs in
Session 0 on a non-interactive window station, where WinUI cannot initialize XAML at all (§7).
An in-process capture is the only evidence channel that does not need the interactive desktop,
and it is honest about what it holds — the XAML tree as composed, not the Mica backdrop and not
the system caption buttons, neither of which is XAML.

## 5 · Layout

```
app/windows/
  MCPRouter.Windows.sln
  Directory.Build.props                shared TFM, RID, self-contained, analysis level
  MCPRouter.Shell.Model/               plain net8.0 — no WinUI, so the gates run headless
    Destination.cs  DestinationCatalog.cs
    AppCommand.cs   CommandCatalog.cs  MenuPath.cs  Accelerator.cs
    Availability.cs
  MCPRouter.Shell/                     the WinUI 3 app
    app.manifest  App.xaml(.cs)  ShellWindow.xaml(.cs)
    Views/BoardPlaceholder.xaml(.cs)
    Shell/TitleBarController.cs  ThemeObserver.cs  SelfTestDriver.cs
  MCPRouter.Shell.Tests/               xunit over the Model + DESIGN.md + the mock
scripts/windows/
  build-shell.ps1                      Restore and Build as two invocations — see §7
  run-shell-selftest.ps1               the interactive-task launcher
```

## 6 · What this item does not do

- No control API client, no router data, no live values anywhere. Every board is a placeholder.
- No Signal Path. DESIGN.md §13's "What the Windows floor still owes" makes the plug's accent
  collision the first thing to settle, and that is WIN4's.
- No notification-area presence (WIN11), no toasts (WIN22), no packaging (WIN19).
- No UI Automation harness. WIN20 owns the automation plane and is running in parallel; §4.5's
  self-test is an in-process capture, not a competing automation plane.

## 7 · Named gaps, each with what it would take to close

1. **Nothing here has been photographed on the interactive desktop.** Measured: this agent session
   runs in Session 0 on window station `Service-0x0-…`, `UserInteractive` false. A WinUI process
   started from it dies with `0xC000027B` (`STOWED_EXCEPTION`, `E_INVALIDARG` from
   `Microsoft.UI.Xaml.dll`) **before the App constructor runs**. Started from an interactive
   scheduled task it reaches `OnLaunched` and activates its window. But an `/it` task's own window
   station enumerates **zero** top-level windows and `GetUserObjectInformationW` returns an empty
   name, so `EnumWindows` and `CopyFromScreen` see nothing from there either. Closing this needs a
   genuinely interactive session — a person at the desktop, or WIN20's automation plane if it
   finds a channel this probe did not.
2. **The sidebar foot readout** — §3.5. Closes with the Windows control client.
3. **`Ctrl+5` / `Ctrl+9`** — §3.3. Closes in WIN21.
4. **Increased contrast / High Contrast** is unmeasured, as §11 already records for the whole
   Windows floor.
5. **`verify.ps1` builds a WinUI project the way that does not work.** WIN18's lane runs
   `MSBuild -t:Restore,Build` in one invocation. Measured on a cold `obj/`, that fails
   (`CS0103: InitializeComponent does not exist`) because the Build target evaluates before
   Restore has written the WindowsAppSDK targets that add the XAML markup-compile passes. Two
   invocations succeed. Fixed on this branch, in the lane and in `build-shell.ps1`.
6. **The Windows App SDK version moved from WIN1's probe.** WIN1 recorded 1.6. Measured here:
   runtime `Microsoft.WindowsAppRuntime.1.6` is **not installed** on this machine (1.5, 1.7, 1.8
   and 2.x are), so a 1.6 unpackaged build launches into *"This application could not be
   started"* — a dialog, with a live process behind it, which is the false green this repo's
   rules already warn about. The shell pins **1.7** and builds `WindowsAppSDKSelfContained`, so it
   depends on no machine-installed runtime at all.
