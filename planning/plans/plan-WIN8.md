# plan-WIN8 — the Windows Checks board

**Spec:** `planning/specs/spec-WIN8.md`
**Brief:** `planning/features-to-triage/WIN8-windows-checks-board.md`
**Design of record:** `design/mcp-router-console.html` `#b-checks` (layout, vocabulary) ·
`app/Sources/MCPRouterKit/Checks/CheckCopy.swift` (the check sentences, per DESIGN.md §6) ·
`DESIGN.md` §11–13 (the Windows floor)
**Branch:** `ai/win8` · **Worktree:** `.worktrees/WIN8`
**Tier:** Large.
**Base:** `main` at `22d7abf6`.

Deliver what is planned below, at the scope stated. Anything that survives a routine judgement
call goes in the progress note as a parked item with its reason.

---

## 1 · Slices, in dependency order

### S1 · The domain, headless first

`MCPRouter.Checks.Model`, plain `net8.0` (the `MCPRouter.Shell.Model` precedent): every claim this
item makes about checks, stamps, staleness and copy is testable with no display.

- `CheckVerdict` (`confirmed` / `notMet` / `notObserved` / `notApplicable`), `CheckId` (the six,
  closed), `CheckResult` (verdict + reason + statement, never a bare verdict), `SubjectKey`,
  `Stamp` (failable: no version → no stamp → nothing stored), `StoredRun`.
- `ServerChecks` — the six, ported with the Mac's semantics: `unknown` is a first-class answer;
  zero calls is never confirmed; a failed index suspends `declares tools`; `+ `input()` for every
  check, because the footer promises the input is showable.
- `CheckCopy` — every sentence, one place, ported from the design of record.
- `CheckHistoryStore` — bounded 20, stamped, load error kept; JSON shape as the Mac's; written to
  `%APPDATA%\MCPRouter\check-history.json` (directory injectable for tests).
- `ChecksBoardModel` — the state machine: load (reconcile store ↔ live versions), rows
  (`Not checked` / current / `Stale` / `Could not run`), invalidation notices, `Run` /
  `RunAll` / `RunStale`, selection, per-subject failures reported against the row.

**Gate:** the S2 fixtures green.

### S2 · The gates, before the surface

`MCPRouter.Shell.Tests` gains a project reference and the seven fixtures the spec's §4.4 table
names. `VersionBoundTests` is the item: stamp A → current; live → B → stale + notice naming both
versions + tally never re-shown; `RunStale` calls only stale rows; run at B → current; A survives
in history, labelled. `ControlClientTests` exercises the real HTTP path against a loopback
`HttpListener` fixture (decode, 404→named absence, refused→`RouterNotRunning`, bearer header
sent, 401→`Unauthorized`).

### S3 · The read/write path

`ControlClient` + `ControlApiError` + `ServerRecord`: loopback, port adopted from the first
`/servers` answer, bearer token from the router's `control.token` for reindex only, never logged.
Error mapping per spec §4.2.

### S4 · The surface

`Views/ChecksBoard.xaml(.cs)`: head (title, permanent subtitle, `Run all` accent/default,
`Run the stale suite` standard + reason), invalidation InfoBars, the five-column table with
Consolas instrument voice, the detail (last-complete-run heading, per-check rows, the failing
exchanges, bounded history), the footer, and §5's nine states. AutomationIds per §4.3.

### S5 · The wiring

- `ShellWindow.ShowDestination`: `checks` → the board; every other destination keeps its
  placeholder.
- `ShellWindow.Invoke`: `library.runChecks` → navigate + run all.
- `CommandCatalog`: `library.runChecks` → `Available`. Nothing else in the catalogue moves.

### S6 · Evidence

- MSBuild Restore then Build per affected `.csproj` (never `dotnet build` on WinUI).
- `dotnet test` on `MCPRouter.Shell.Tests` (the lane's own invocation).
- The python gates the new files can move, with `PYTHONIOENCODING=utf-8`.
- Report exact commands and exit codes; what could not run stays **not-run** with its reason
  (spec §7). No gate is reported green that did not run.

---

## 2 · Test strategy

**What can be proved on this machine:** the build; every behavioural claim in S1–S2 (headless,
including real loopback HTTP against the fixture); sentence case and the copy rules.

**What cannot:** a live router conversation (none is running; §7 gap 1–2), a photograph of the
board (spec-WIN3 §7 gap 1), the automation lane (needs WinSta0). All recorded not-run, never as a
pass.

**What is never done:** no test is edited to pass; no baseline is raised or waived; no gate that
cannot run here is reported as anything but not-run.

---

## 3 · Order of work

S1 → S2 (red where the fixtures can be written first) → S3 → S4 → S5 → S6 → the progress note in
the spec. The domain and its gates precede the XAML so the semantics are pinned before anything
draws them.
