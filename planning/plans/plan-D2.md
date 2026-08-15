# plan-D2 — Deferred register: Mac surfaces and design authority

Implements `planning/specs/spec-D2.md`. Six children implemented, three refused with a reason,
thirteen dispositioned as out of scope. Branch `ai/d2`, worktree `.worktrees/D2`, base `main`
`42ea4d3`.

**Docs stay in the main tree and are not committed on the branch**, with one declared exception:
`planning/specs/spec-M1.md`, whose inventory table `MenuCommandTests` parses as a **test oracle**.
M14 set that precedent (`ORCHESTRATOR.md:237`) and M9 + D-m14-b both move rows in it, so the branch
would not compile-and-pass without it.

---

## Phase 1 — the shell's vertical alignment (D-m13-a)

**File:** `app/Sources/MCPRouterUI/Shell/ShellWindow.swift`

`outerScroll`'s frame gains `alignment: .top`. Its doc comment gains the measurement and the reason
the fix is at the shell rather than on `ServersBoard`: six boards already carry a private
compensating `.topLeading` frame, so the same defect was patched six times without once being
fixed where it originates.

**Explicitly not changed:** the six boards' own
`.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)` modifiers. They do a
second job — letting `ConnectionFailurePane` fill the pane in the `.failed` branch — which the
shell's alignment does not replace. Removing them would be a drive-by change that reddens the
failure-pane layout on six boards.

**Not changed:** `ServersBoard`. The shell fix covers it, and adding a seventh private compensator
would re-create the thing this phase removes the need for.

---

## Phase 2 — the nested scroll view (D-m13-b)

**File:** `app/Sources/MCPRouterUI/Boards/SettingsBoard.swift`

Remove the inner `ScrollView` at line 70. The four groups become direct children of the board's
`VStack`, which the shell's `outerScroll` then scrolls — the same arrangement as Servers, Skills,
Discover, Inbox, Evals and Cleanup.

`boardsThatScrollThemselves` is **unchanged at `[.activity]`**, and its doc comment gains a note
recording that this was measured rather than assumed: Settings was checked against the set's own
sticky-chrome criterion and did not meet it.

**Risk this phase carries, and how it is discharged:** the scroll-edge separator reads the shell's
scroll view. Removing an *inner* scroll view cannot break that — the outer one was already the
scroller, which is what the 699-in-568 geometry proved — but the separator is re-verified on
Settings by `mac-shell.sh`'s existing A34 rather than taken on argument.

---

## Phase 3 — the label (M9)

**Files:** `app/Sources/MCPRouterKit/Shell/Destination.swift`, then every reader of the label.

`Destination.evals.title` becomes `"Checks"`. The case, `rawValue` and `deepLinkSlug` stay `evals`.
A comment records why the identifier and the label deliberately differ, so nobody "fixes" the
mismatch and breaks frame restoration and the prototype's `?pane=evals` deep link.

Readers to move, found by grep and each verified individually rather than sed-replaced:

- `planning/specs/spec-M1.md` — the View-menu inventory row (**test oracle**, committed on branch)
- `scripts/acceptance/mac-shell.sh` — the destination walk (×2) and the selection assertion (×2)
- `scripts/acceptance/m7-evals-cleanup.sh` — pane open, title assertion, failure copy
- `scripts/acceptance/m6-inbox-pairing.sh` — the destination walk
- any `MCPRouterKitTests` / `MCPRouterUITests` case asserting the title

**Not moved:** file names (`EvalsBoard.swift`, `EvalsBoardModel.swift`, `EvalsInspector.swift`,
`EvalsBoardRow.swift`), type names, and `M7BoardMetrics`. They are internal, invisible to a user,
and renaming ~45 files during a concurrent D1 run is merge-conflict risk bought for nothing.

---

## Phase 4 — the shortcut (D-m14-b)

**File:** `app/Sources/MCPRouterKit/Shell/MenuCommand.swift`

`exportLibrary` moves from `KeyChord("E")` to `nil`, joining the other no-shortcut cases. The
comment already in that switch — recording that `⌘?` was invented by an earlier draft and is
**reserved by the system**, verified by binding `⌘J` to prove the Help menu does not strip
shortcuts — is the precedent this follows, and the new comment names the same class: `⌘E` is
Finder's Eject and Cocoa's *Use Selection for Find*, and `DESIGN.md` §8's table never granted it.

`spec-M1.md`'s row changes `⌘E` → `—` in the same commit as the title change.

**Not changed:** the title, the ellipsis, or `.featureUnbuilt`. Removing an ungranted shortcut and
keeping a correct title are separate decisions and only the first survived triage.

---

## Phase 5 — the design authority (M10)

**File:** `DESIGN.md` §6

The one-name-per-state rule is kept; only its dead example moves. The replacement is drawn from a
state the product genuinely has, and the absence of any evaluation is recorded in the same bullet
so a later runner cannot re-derive the clause from its own absence.

**Because `DESIGN.md` changes, F2's token gate is re-run** — `DesignTokenParityTests` plus
`DesignDocParserTests` and `DesignDocColumnTests`. §6 carries no token table, so the expectation is
no movement; the run is what turns that expectation into evidence. The parser is heading-driven and
reads only §2's four `###` tables, so a §6 prose edit is structurally out of its reach — but that
is the claim being tested, not the reason to skip testing it.

---

## Phase 6 — the check that can fail a correct app (D-g1-b)

**File:** `scripts/acceptance/m8-settings-menubar.sh`

A9 is rewritten to read the forget control's `AXEnabled` from the dump and assert the pairing §3.4
actually specifies:

- disabled → a reason is present
- enabled → **no** reason is present

Both arms fail loudly rather than one silently passing, and neither depends on this Mac's keychain.
The block gains a comment recording the measurement (`21 passed / 0 failed` here against G1's
`20 / 1`, same 21 assertions) and naming the mechanism, so nobody re-files it as flaky.

**Not changed:** `SettingsBoard.swift`. The product is correct and the brief's product change does
not exist to be made.

---

## Phase 7 — the acceptance assertions

**File:** `scripts/acceptance/mac-shell.sh`

Added inside the existing single launch — no second launch, no relaunch per pane, `open -g`
throughout, frontmost asserted unchanged, app quit at the end.

- **D1** for each installed destination: `topmost content-zone element .y − content scroll area .y ≤ 40`
- **D2** for each installed destination: exactly one `AXScrollArea` with `x > 450`
- **D3** sidebar row, window title and View-menu item all read `Checks`; `Evals` appears in neither dump
- **D4** no app-declared menu item publishes `AXMenuItemCmdChar == "E"`

D1's 40pt threshold is a **band, not the measurement**: the real readings are 17pt (Settings,
Inbox) against 209.5pt (Servers today), so 40 sits an order of magnitude clear of both and cannot
be met by accident. It is deliberately not tightened to 20pt, which would redden the two boards
whose column header legitimately sits below a title.

---

## Phase 8 — mutations, each rebuilt first

Without a rebuild every one of these reports **BLOCKED**, not red — G1 recorded that and M14
re-confirmed it. Each is applied, `make build-mac` run, the assertion run, then reverted.

| # | Mutation | Target | If it cannot redden |
|---|---|---|---|
| M1 | drop `alignment: .top` | D1 on Servers | re-aim at the measured y, not the pass/fail |
| M2 | restore the inner `ScrollView` | D2 on Settings | re-aim at the scroll-area count |
| M3 | title back to `"Evals"` | D3 | re-aim at the window title alone |
| M4 | re-add `KeyChord("E")` | D4 | re-aim at the spec-M1 oracle |
| M5 | `canForget` always `true` | D5 disabled arm | re-aim at the help tag |
| M6 | `canForget` always `false` | D5 enabled arm | re-aim at the help tag |

A mutation that will not redden is **re-aimed at the same semantic claim**, never swapped for an
easier one.

---

## Phase 9 — gates

`make lint` · `make test` · `make build-mac` · `scripts/acceptance/parity-manifest-check.sh` ·
`make parity-selftest` · `mac-shell.sh` · `m8-settings-menubar.sh` · `m7-evals-cleanup.sh` ·
`m6-inbox-pairing.sh`.

**`parity-gate.sh` is NOT run this wave.** `D-g1-g`: every lane binds a fixed port and two parity
runs on one machine corrupt each other silently, reproduced deterministically by holding `:8982`.
D1 is live and owns that gate exclusively. `parity-manifest-check.sh` and `make parity-selftest`
bind no port and are safe.

`make lint` runs `swiftformat --lint` first and short-circuits, so a formatting failure hides
swiftlint entirely; the run is repeated until *all four* linters have been seen to run. `make
format` can push a file past the 400-line cap, so line counts are re-checked after any format pass.

The three review gates run **out of family on grok-4.6**: spec, plan, and the Phase D completeness
critic. Grok exits 0 when session init fails, so each is asserted on real content and not on `$?`.

---

## What this plan does not do

No board is rewritten, no test is weakened, no lint limit is raised, no `DESIGN.md` token value
moves, and no file is renamed. The register's remaining thirteen Mac children are dispositioned in
`spec-D2.md` §6 by name, with a reason each — none is skipped silently, and none is done merely
because it is listed.
