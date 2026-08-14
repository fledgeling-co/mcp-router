# M8 — acceptance evidence

`Settings, the menu-bar popover, and the quarantine's missing half` · branch `ai/m8` ·
worktree `.worktrees/M8`
Spec `planning/specs/spec-M8.md` (A1–A33, incl. A16b, A19b, A27a–A27f) ·
Plan `planning/plans/plan-M8.md` ·
Design `design/mocks/html/m8-settings-popover.html`

Append to this file, never rewrite it. Read it **before** testing anything: if a row exists and
`git diff <that SHA>..HEAD` does not touch the files behind it, that row *is* the evidence, and the
right thing to do is skip the check and say so.

---

## What was verified, and what was deliberately not

**Three surfaces changed in this item**: the Settings pane (new), the menu-bar status item and its
popover (new), and `ToolChangeCard` inside M3's held-change sheet (one view, extended).

**Not re-verified, and why.** The Servers board, the sidebar, the readout, the window frame, the
menu-bar inventory and the bare keys are M1's and M3's, and this branch does not touch the files
behind them except for two additive members on `ShellModel`, one additive branch in `ShellWindow`'s
`pane`, and the poll-ownership change — all three of which *are* covered below. Their evidence is
`planning/evidence/M1-acceptance.md` and `planning/evidence/M3-acceptance.md`, and re-running them
against unchanged code has exactly one possible outcome.

**The Activity and Skills boards were not touched at all** — M2 and M4 own them, and they landed on
their own branches.

## The pass was invisible, and that is measured rather than asserted

`Ledger` was frontmost before the run and `Ledger` was frontmost after it, asserted inside the
script itself. The app was launched with `open -g` and **never activated**: there is no
`osascript … to activate`, no `set frontmost to true` and no bare `open -a` anywhere in
`scripts/acceptance/m8-settings-menubar.sh`. Every read went over the accessibility plane by pid.
One launch, one pass, and the app was terminated at the end.

**A finding worth recording for the next runner:** driving `MCP Router ▸ Settings` through System
Events *succeeds and changes nothing*. `ShellCommands` reaches the model through
`@FocusedValue(\.shellModel)`, and a backgrounded app with no key window has no focused value, so
`ShellCommandRouter.perform(command, on: nil)` runs — which is a deliberate, tested no-op. A
menu-driven check of a background app therefore measures focus rather than the surface. Pressing the
sidebar row with `axkit select` is process-directed, needs no focus, and is what this script uses.

---

## Behavioural evidence — the running app

Command: `./scripts/acceptance/m8-settings-menubar.sh` · commit `6d6cb08` (+ this file) ·
scenario `populated` · **21 passed, 0 failed**

| Screen | How verified | Commit | Result |
|---|---|---|---|
| Settings — installed | `axkit select <pid> Settings` then `axkit dump <pid> window`; asserted the sentinel `isn't built yet` is **absent** | `6d6cb08` | pass (A2) |
| Settings — four groups | AX tree carries `AXGroup` "Router", "Menu bar", "Warm set", "Control token" | `6d6cb08` | pass (A30) |
| Settings — Router rows | AX static text: `Endpoint`, `Home`, `Idle reaper`, `Counting since` | `6d6cb08` | pass (A30) |
| Settings — observed port | rendered `http://127.0.0.1:8971/mcp` — the fixture's port, **not** the 8879 default | `6d6cb08` | pass (A6) |
| Settings — no memory figure | regex `[0-9]+ ?(MB\|KB\|GB)` over the whole rendered tree: no match | `6d6cb08` | pass (A5) |
| Settings — no credential on screen | regex `sk-\|Bearer \|[A-Za-z0-9]{32,}` over the rendered tree: no match | `6d6cb08` | pass (A7) |
| Settings — window title | `axkit title <pid>` → `Settings` | `6d6cb08` | pass (§3.7) |
| Settings — disabled forget | `AXButton "Forget the stored token"`, enabled `0`, `AXHelp "There is no stored token to forget."` | `6d6cb08` | pass (A9) |
| Settings — empty warm set | rendered `None of 4 servers` plus the "started when something first calls it" sentence | `6d6cb08` | pass (§5 Empty) |
| Settings — menu-bar control | `AXCheckBox` value `1`, label `Show MCP Router in the menu bar` | `6d6cb08` | pass |
| Menu bar — status item exists | System Events, menu bar 2 of the process: 1 item | `6d6cb08` | pass (A15) |
| Menu bar — item description | macOS reports its own `status menu`; see the limitation below | `6d6cb08` | recorded |
| Focus | `axkit front` before and after: `Ledger` both times | `6d6cb08` | pass |

**The measured limitation, stated rather than asserted away.** `MenuBarStatusItem` sets
`.accessibilityLabel(...)` on its label view and macOS does **not** forward it to the
`AXMenuBarItem`: measured on this machine on 2026-08-14, the item's AX description is the system's
own `status menu` whatever the view says. The label's *content* is therefore proven at the value
level — `MenuBarPresentationTests.labelCountsServers` asserts both `MCP Router` and
`MCP Router, 2 items need a decision`, including that a server with three problems counts once — and
the script reports what the platform exposes rather than failing for something no API here can
change. A14 is met in substance and its platform half is a known gap.

**Not driven in the running app, and named as such:** the popover's contents. A `MenuBarExtra` in
`.window` style renders its content only while open, and opening it requires clicking the status
item, which is a synthetic event needing the app frontmost — the one thing this pass may not do.
Its every state is instead proven as a value through `PopoverContent.make`, which is why that type
exists (see `PopoverContentTests`, 9 tests). A human wanting to see it open should click the icon.

---

## Gate evidence

`make all`, run on the final tree:

```
Done linting! Found 0 violations, 0 serious in 262 files.
Test run with 816 tests in 112 suites passed after 1.729 seconds.
** TEST SUCCEEDED **   (macOS app build + iOS)
executed 12 iOS tests
parity: 358 vector cases compared (floor 358)
```

Lint reached zero by **splitting three files, not by raising a limit**: `ToolChangeCard` out of
`ServerSheets.swift` (463 lines), `ShellRestoration` out of `ShellModel.swift` (410), and
`TrackerState` into `TrackerState.swift` as an extension (431). All four resulting files are
enrolled in `ShellTestSupport.shellFiles` / `.boardFiles`, which is the pin that stops a file
escaping every source-level gate.

---

## The red-green proving pass

Every guard this item adds was deliberately broken, seen red, and restored. A guard that has never
failed is a decoration.

| Guard | The mutation | Result |
|---|---|---|
| A4 — tracker retention | clear `port`/`since` in `apply(pollFailure:)` | 4 tests, **2 issues** → restored, 4 pass |
| A12 — the bar's dot | `statusItemDotToken = .fail` | 13 tests, **3 issues** |
| A17 — no skills count | add `skills` to `Counts` | 13 tests, **1 issue** |
| A18 — band absent not empty | `band: rows` instead of `rows.isEmpty ? nil : rows` | 9 tests, **2 issues** |
| A16b — the idle bucket | idle read as `state == .idle` | 9 tests, **2 issues** |
| A27c — schema key order | compare the raw strings instead of decoding | 10 tests, **3 issues** |
| A27d — unreadable schema | decode falls back to `[:]` instead of failing | 10 tests, **2 issues** |
| A24 — the quarantine route | drop the `await loadHeldChanges` | 15 tests, **1 issue** |
| A27f — the poll's owner | `.task { await model.run() }` back in `ShellWindow` | 15 tests, **2 issues** |

Tree verified clean afterwards: `grep -rn "RG-BREAK\|// RG" app/Sources` → no matches, and the full
suite green.

The A5 source guard additionally carries its **own** red-green as a permanent test —
`memoryGuardCanFail` asserts that a literal containing `MB` is caught and that a doc comment saying
"megabytes" is not.

---

## The scaffold gate was broken before this item, and is fixed

`scripts/acceptance/mac-shell.sh` decided "do any destinations still lack a board?" with
`case "$INSTALLED" in *"= []"*)`. That was correct only while the registry was empty. **M3 shipped
`installed = [.servers]` and from that commit the pattern stopped matching**, so `SCAFFOLDS_REMAIN`
became `0`, and the gate's else branch demands the placeholder sentence be *absent* from the Release
bundle — while seven destinations are still scaffolded and it is correct for it to be present. The
gate would have failed the run, for the opposite of the right reason.

It now counts installed destinations against `Destination`'s own cases. Verified at all four
boundaries by simulation rather than by four Release builds:

```
[]                                    -> installed=0 remain=1
[.servers]                            -> installed=1 remain=1
[.servers, .settings]                 -> installed=2 remain=1   ← today
[all eight]                           -> installed=8 remain=0   ← the flip
```

This is a shared script and the change is reported to the orchestrator rather than assumed welcome.

---

## The out-of-family gates

**`codex: usage limit → claude (downgrade)`, all three.** Every `codex exec` call returns
`You've hit your usage limit … try again at Aug 20th, 2026 1:29 PM`, which is account-level and past
this fleet's horizon; the orchestrator verified it and instructed runners not to spend a probe
rediscovering it. Each gate ran instead as a fresh `claude -p --model claude-opus-5` reviewer,
briefed adversarially — told to refute, and that finding nothing is a failed review rather than a
pass.

**The weakness travels with the evidence: every reviewer in this item's pipeline is Claude auditing
Claude.** On this occasion it still found the two things that mattered most.

| Gate | Verdict | Tally |
|---|---|---|
| Spec review (round 1) | **REJECT** | ACCEPT 7 / REJECT 15 |
| Plan review | **REJECT** | ACCEPT 7 / REJECT 14 |
| Phase D completeness critic | see below | — |

Both disqualifying findings were **verified against the source before being acted on**, rather than
taken on the reviewer's word:

1. **The quarantine surface was half-built.** `diffTools` (`src/manifest.ts:80-93`) holds a change
   when the description **or** the input schema differs and ships both on `ToolShape`;
   `ToolChangeCard` rendered only the description. A schema-only rewrite drew two identical fields
   and no indication of change. The first draft of spec-M8 certified that surface as complete. M8
   now ships the schema half.
2. **Nothing polled while the window was closed.** `ShellModel.run()` was driven only by
   `ShellWindow.swift:45`'s `.task`. A menu-bar app's normal state is window-closed, so the status
   item this item adds would have frozen silently.

The remaining findings and their dispositions are in `spec-M8.md`'s gate section — thirteen upheld
and acted on, one (the prototype deep links) partly upheld and recorded.
