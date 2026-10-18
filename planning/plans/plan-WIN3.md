# plan-WIN3 — the Windows app shell

**Spec:** `planning/specs/spec-WIN3.md`
**Brief:** `planning/features-to-triage/WIN3-windows-app-shell.md`
**Design of record:** `design/mcp-router-console.html` (layout, IA, vocabulary) · `DESIGN.md` §11–13 (the Windows floor)
**Branch:** `ai/win3` · **Worktree:** `.worktrees/WIN3`
**Tier:** Large.
**Base:** `main` at `44e5c6df`.

Deliver what is planned below, at the scope stated. Anything that survives a routine judgement
call goes in the progress note as a parked item with its reason.

---

## 1 · Slices, in dependency order

### S1 · The lane, before any code

The build lane is the first thing that can be wrong in a way every later slice inherits.

- `app/windows/Directory.Build.props` — `net8.0-windows10.0.19041.0`, `win-x64`,
  `WindowsAppSDKSelfContained`, `Nullable`, warnings-as-errors off for generated XAML.
- `scripts/windows/build-shell.ps1` — **Restore and Build as two MSBuild invocations.** One
  invocation fails on a cold `obj/`; this is measured, not defensive.
- `scripts/windows/verify.ps1` — same fix, in the lane WIN18 built.

**Gate:** a hello-window builds from a clean tree, twice in a row, exit 0 both times.

### S2 · The model, which is where the gates can reach

A plain `net8.0` library with no WinUI reference, so every structural claim about the shell is
testable without a display.

- `Destination` — id, label, group, glyph, accelerator, the sentence its placeholder draws.
- `DestinationCatalog` — the ten, in the design of record's order and grouping.
- `AppCommand` — id, label, menu path, access key, accelerator, `Availability`.
- `Availability` — `Available` · `NeedsSelection` · `Unbuilt(reason)`, the reason naming the item.
- `CommandCatalog` — the whole command surface, one place, ordered as it is drawn.
- `Accelerator` — parses and formats `Ctrl+N`, `Del`, `Ctrl+1`, so DESIGN.md's spelling and the
  app's are one value rather than two.

### S3 · The gates

`MCPRouter.Shell.Tests`, xunit, over the model plus the two documents it claims to follow.

| Test | What it reads | What it holds |
|---|---|---|
| `DesignKeyboardParityTests` | `DESIGN.md` §13's table | Both ways: every chord row is bound to exactly one command; every accelerator the app binds is a row. Non-chord rows (`Alt`, `F6`, `Return`, `Esc`, `Space`) are matched against the declared behaviours, so a row cannot be silently dropped for not being a chord |
| `CommandSurfaceCompletenessTests` | the catalogue | Every command sits on exactly one menu path; no command is reachable only by a chord (§11 rule 9); every destination has a View item |
| `AccessKeyTests` | the catalogue | Every menu title and every item carries an access key; unique within its scope |
| `DestinationCatalogTests` | `design/mcp-router-console.html` | The nine board ids, their labels and their four group headers are the mock's, parsed from it, in its order |
| `SentenceCaseTests` | the catalogue and the destinations | §11 rule 2 — sentence case for **all** UI text, titles and menu items included, with the macOS Title-Case carve-out explicitly not crossing |
| `UnbuiltReasonTests` | the catalogue | Every `Unbuilt` command names a reason, and the reason names an item id that exists in `ORCHESTRATOR.md` |
| `TitleTests` | the catalogue | The window title for each destination is the destination's label; `MCP Router` is not a title any destination produces |

These run on Windows, headless, in seconds. They are the only gates this item has that a machine
can settle, so they carry the weight the absent capture lane cannot.

### S4 · The window

`ShellWindow` — Mica, extended title bar, MenuBar in the caption band, board title, NavigationView
with the ten destinations, board placeholder host.

- `TitleBarController` — drag regions, caption-button colours, and re-resolving both on theme
  change and on a rasterization-scale change.
- `ThemeObserver` — `ActualThemeChanged`, and nothing that sets `RequestedTheme`.
- The MenuBar is built **from `CommandCatalog`** rather than authored in XAML, so the gates in S3
  measure the surface the app actually draws rather than a parallel list.

### S5 · The boards

`BoardPlaceholder` — the destination's name, the sentence describing what the board will show,
and the sentence naming the item that builds it. One control, ten instances, no per-board code.

### S6 · The self-test

`--selftest <dir>` — walk the ten destinations, capture each, then force light and dark and
capture both; write `selftest.json` and exit non-zero if any destination failed to render.

`scripts/windows/run-shell-selftest.ps1` launches it through an interactive scheduled task,
because Session 0 cannot host a XAML window.

---

## 2 · Test strategy

**What can be proved on this machine:** the build (S1), every structural claim (S3), and — if the
interactive task can host the app — the self-test's own JSON and PNGs (S6).

**What cannot:** anything about how the window *looks*. No screenshot of this shell exists or can
be taken from this session. Every visual claim in the progress note is therefore a claim about
code and tokens, and is marked as such. A capture lane is gap 1 in the spec and is not closed by
a stronger sentence.

**What is never done:** no test is edited to pass, no ratchet is raised, and no gate that cannot
run here is reported as anything but not-run.

---

## 3 · Order of work

S1 → S2 → S3 (red first, against an empty catalogue) → S4 → S5 → S6 → the progress note.

S3 before S4 is deliberate: the gates are written against DESIGN.md and the mock, so they fail
until the catalogue matches the documents, and the catalogue is then filled to satisfy the
documents rather than the tests being fitted to whatever the catalogue happened to hold.
