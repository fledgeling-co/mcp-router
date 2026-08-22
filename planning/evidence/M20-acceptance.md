# M20 acceptance — the menu bar measured for the first time, the popover measured at all

Branch `ai/m20`, worktree `.worktrees/M20`. **Gap-fix 1 is `f9ba8fe` … `2393c78`**, 2026-08-23, on
top of the merge `e4aec36`, with `main` merged a second time at `8aecd90` after it moved to
`55dbeca` mid-pass. **Every gate below was re-run on `8aecd90` and held**, and that merge touched no
Swift file — `git diff --name-only $(git merge-base bcc69dd main) main -- app/ '*.swift'` counts 0 —
which is why every Swift figure here is M20's alone. The delivered pass was `0bdfcbe` and `bcc69dd`.

**This file did not exist until the gap-fix, and its absence is the first thing it has to record.**
`planning/practices/UI_VERIFICATION.md` rule 2 asks for one per item at exactly this path.
`plan-M20.md` step 24 promised it and the first pass wrote nothing, which matters more here than
usual: that pass shipped a tree that **did not compile**, so every claim it made about a running app
was a claim about a binary nobody had built. Nothing below is measurement invented to fill a file —
every row is a check that ran on this tree, and the ones that produced no reading say so in their own
section rather than appearing here as passes.

Every menu-bar row was read over the accessibility plane **by pid**, against an app launched with
`open -g` through the repo's own `mac_app_launch`. The frontmost application was `Google Chrome`
before the launch and `Ghostty` after it, and **the app was never in front** (rule 1). One launch, one
pass, quit (rule 4).

## The ledger

| Screen | How verified | Commit | Result |
|---|---|---|---|
| The menu bar carries eight app menus, in bar order | `axkit dump <pid> menu`, `$1==1 && $2=="AXMenuBarItem" && $4!="Apple"` | `1520f0a` | `MCP Router\|File\|Edit\|View\|Router\|Library\|Window\|Help\|`, count 8 — byte-identical to `mac-shell.sh:394`'s `EXPECTED_ORDER`, which had never been run |
| The Router menu — eight commands, their availability and their reasons | same dump, filtered to the Router bar item's children | `1520f0a` | 8 items; `Reveal Router Log in Finder` enabled=1, the other seven enabled=0 |
| The Library menu — four commands | same | `1520f0a` | 4 items, all enabled=0. `Export Library…` is gone from File and present here |
| **Every dimmed item carries its own reason** (criterion 2, a11y half) | `AXHelp` read on each dimmed item of the two new menus | `1520f0a` | 11 dimmed, **0 with an empty `AXHelp`**, 10 distinct sentences — nine naming what is unbuilt, and `Select a server first.` shared by `Wake Selected Server` and `Review Held Changes…` by design. This is M11's defect (`enabled=0` with an empty `AXHelp`) staying fixed across twelve new items |
| `⌘R` still resets the selected server (criterion 3) | `AXMenuItemCmdChar` and `AXMenuItemCmdModifiers` on `Reset Server` | `1520f0a` | `char=R mask=0` — `⌘R`. The mock's `Re-index Manifest ⌘R` was correctly not taken |
| `⌃W` is the only chord either new menu carries | the same two columns over both menus | `1520f0a` | `Wake Selected Server char=W mask=12`; every other item in both menus has no command character. Mask 12 is control-without-command |
| The View menu carries the design of record's digits | same columns over the View bar item | `1520f0a` | `Discover 1 · Skills 2 · Servers 3 · Activity 4 · Checks 6 · Cleanup 7 · Inbox 8`, with `⌘5` and `⌘9` genuinely unbound |
| **`⌥⌘Q` is already taken, in this app's own bar** | every row whose `AXMenuItemCmdChar` is `Q`, with its modifier mask and `AXIdentifier` | `1520f0a` | §5 below. `Quit and Keep Windows` at mask 2, `NSAlternateQuitMenuItem` |
| The popover's decision band — **three separately focusable controls** (criterion 4) | `MeasureDump --surface popover --state ideal`, structure dump | `affcfee` | §6 below. Three sibling leaf nodes at three disjoint frames on one horizontal axis |
| The popover's counts, and the absence of a fourth (criterion 5) | the same dump, plus a reflection over `MenuBarPresentation.Counts` | `affcfee`, `6228941` | three cells, `Running now 1 · Declared 4 · Tools 2`; the type has four fields and none of them is a memory figure |
| The popover's other three states | `MeasureDump --state empty\|loading\|error` | `affcfee` | `empty` 4 nodes (counts, no band), `loading` and `error` 1 node each (neither counts nor band) — the absent-not-empty rule holding on the rendered surface |
| Both notification families register the buttons their values name (criterion 6) | `ArrivalNotifierFactoryTests`, over `UserNotificationArrivalNotifier.categories()` | `e697812` | 4 categories, identifiers distinct, every registered button resolving in its own family and in neither the other's; no route of either family installs |
| The five drift guards, each seen red | `python3 scripts/red-green.py --only <id>` | `1520f0a` | §7 below. Five of five **KILLED** |
| The conversion gate for this surface | `./scripts/acceptance/mock-fidelity-gate.sh popover` | `affcfee` | **exit 3, could not run** — §8. Recorded as a difference, not a pass |
| Invisibility | frontmost read before the launch and after the quit | `1520f0a` | `Google Chrome` → `Ghostty`. The app was never frontmost |

## 5 · `⌥⌘Q`, measured rather than argued

`DESIGN.md` §8 refuses `⌥⌘Q` to `Review Held Changes…` on the ground that AppKit has already claimed
it. That is the claim this section is the evidence for, read off the running app's own menu bar.

Every row in the bar whose `AXMenuItemCmdChar` is `Q` — columns are title, char, modifier mask,
`AXIdentifier`:

```
Lock Screen              char=Q mask=4  _lockScreenRequested:
Log Out Luke Rhodes…     char=Q mask=1  _logOutRequested:
Log Out Luke Rhodes      char=Q mask=3  _logOutNowRequested:
Quit MCP Router          char=Q mask=0  terminate:
Quit and Keep Windows    char=Q mask=2  NSAlternateQuitMenuItem
```

**The mask legend is established from this same dump rather than assumed**, off chords whose spelling
is independently documented:

```
Reset Server          char=R mask=0    ⌘R      DESIGN.md §8
Add Marketplace…      char=N mask=1    ⇧⌘N     spec-M1.md:67
Hide Others           char=H mask=2    ⌥⌘H     AppKit standard
Close All             char=W mask=2    ⌥⌘W     AppKit standard
Show Sidebar          char=S mask=4    ⌃⌘S     DESIGN.md §8
Wake Selected Server  char=W mask=12   ⌃W      this item
```

So mask 2 is `⌥⌘`, and `⌥⌘Q` is bound in this app's bar to AppKit's alternate Quit. Every mask-2 chord
in the whole bar belongs to AppKit — `hideOtherApplications:`, `closeAll:`, `miniaturizeAll:`,
`NSAlternateQuitMenuItem` — and **the app itself declares no `⌥⌘` chord at all.** The `Q` key is
enclosed rather than merely adjacent: `⌃⌘Q`, `⇧⌘Q` and `⇧⌥⌘Q` are all system-owned above.

**What this does not establish, stated so nobody reads it as more than it is.** The tie-break was not
actuated: confirming empirically that the App menu's alternate wins over a Router item means quitting
the app, and there is no Router item to lose to it — the chord was never granted. The *binding's
existence* is measured; the resolution order is AppKit's documented menu-order search. There is no
branch where granting it is clean: if Router did win, the cost flips to overriding a system-standard
behaviour.

Lanes: `agy` / `gemini-3.7-flash-high` and `claude-fable-5` at high effort both returned Option A
independently and both named the alternate-Quit mechanism, which neither the brief nor the verdict
had. `codex` / `gpt-5.6-sol` is usage-limited until 2026-08-27 and `grok-4.6` answers `402`, both as
`spec-M20.md`'s own review record predicted. The candidate reason this pass went in with — *one
modifier from Quit, so the miss case quits the app* — is a weaker version of the real one and was
replaced by it: `⌥⌘Q` is not near a Quit, it **is** one.

## 6 · Criterion 4, off the structure dump

`app/.build/debug/MeasureDump --surface popover --state ideal --settle 1.5 --width 420 --height 760`,
12 nodes. The tree, with each node's frame in the surface's coordinate space:

```
popover.ideal            surface       x=0     y=0   w=420  h=760
  count-running-now      footer-counts x=16    y=10  w=70.5 h=34   "Running now 1"
  count-declared         footer-counts x=98.5  y=10  w=49   h=34   "Declared 4"
  count-tools            footer-counts x=159.5 y=10  w=29   h=34   "Tools 2"
  inbox-band             banner        x=6     y=48  w=328  h=106  "2 waiting from Luke's iPhone"
    inbox-row-q-2        table-row     x=6     y=66  w=328  h=44   "DeepWiki"
      inbox-review       state-action  x=179.5 y=76  w=72   h=24   "Review…"
      inbox-decline      state-action  x=255.5 y=76  w=68.5 h=24   "Not now"
    inbox-row-q-1        table-row     x=6     y=110 w=328  h=44   "Local notes"
      inbox-approve      primary-action x=106.5 y=120 w=69  h=24   "Approve"
      inbox-review       state-action  x=179.5 y=120 w=72  h=24   "Review…"
      inbox-decline      state-action  x=255.5 y=120 w=68.5 h=24   "Not now"
```

**Three controls, three disjoint frames, one horizontal axis** — `106.5+69 = 175.5 < 179.5`, and
`179.5+72 = 251.5 < 255.5`. Three separate `Button`s rather than a menu or a segmented control,
because a control that has to be opened before its options are reachable is one focusable thing and
not three.

**And the two rows differ, which is the third approval condition biting on a recorded fixture rather
than on a constructed one.** `q-1` resolves to the authored `authored:local-notes`, which asks for
nothing, so it carries all three controls. `q-2` resolves to `smithery:deepwiki` from the **recorded**
`registry-search.json`, whose install block asks for an `Authorization` header marked secret — so it
carries `Review…` and `Not now` and no `Approve`, because the band has no field to type that header
into and an empty one would reach the router as a blank credential.

The dumps live under `planning/fidelity/dumps/`, which `.gitignore:92` excludes, so the tree above is
quoted here rather than referenced — a figure whose only copy is a regenerable artifact is a figure
this ledger does not carry.

## 7 · The five drift guards, each seen red

`plan-M20.md` §6 promised this and the first pass did not do it. Each mutation edits the
**implementation** and never a test; `scripts/red-green.py` restores the file in a `finally` and the
tree was re-checked afterwards.

```
$ python3 scripts/red-green.py --only M20-A3
M20-A3  KILLED   A3   every unbuilt command says what is unbuilt, in words of it   32.7s
$ python3 scripts/red-green.py --only M20-A4
M20-A4  KILLED   A4   a command that can never fire claims no shortcut            27.9s
$ python3 scripts/red-green.py --only M20-B2
M20-B2  KILLED   B2   a row asking for a value it cannot be given is not approva   28.0s
$ python3 scripts/red-green.py --only M20-C1
M20-C1  KILLED   C1   no route of either notification family installs anything     28.1s
$ python3 scripts/red-green.py --only M20-D1
M20-D1  KILLED   D1   the popover's install path re-checks every condition rathe   29.6s
```

`KILLED` means the suite went red **and** every test the mutation named went red — the runner reports
`WRONG-TEST` when something else fails instead, so a green here is not a pass on a coincidence.

What each one breaks, so a reader can judge whether it is the edit a later pass would actually make:
A3 gives `.runAllChecks` another command's unbuilt sentence; A4 grants `.stopRouter` a chord; B2 drops
the requirement check from `InboxBand.canApprove`, leaving only the resolved check; C1 makes
`FindingNotificationRoute.reviewCapability` report that it installs; D1 drops the preference and
requirement guards from `approveFromOutside` — which the band's own `isApprovable` would still hide,
so a clause reading only the view would stay green against it.

Afterwards: `git status` shows the five files modified only by this pass's own committed work, the A3
arm reads `case .runAllChecks: "Running every check at once"` again, `D1`'s guard reads
`guard isApproveFromPopoverEnabled,` again, and no mutation string survives anywhere in the tree.

## 8 · What produced no reading, and why

Stated so a later reader does not mistake an unrun check for a passing one.

- **`mock-fidelity-gate.sh popover` — exit 3, could not run.** `mock-affordances.py` needs a
  `.v-<state>` frame inside the section and `#statusPopover` has none. The generated
  `planning/fidelity/popover.ledger.md` says *"this run did not produce a table"* in its own words and
  is committed as that. Criterion 4 does not depend on it — §6 is the dump the criterion asks for.
- **`make lint` and `make build-mac` as targets.** Both fail at their `tools` prerequisite in this
  worktree: `node_modules` and `dist/index.js` are absent. Recorded as **targets not run**. Their
  components were run directly and are green — `swiftlint --strict` 0 violations over 556 files,
  `swiftformat --lint` 0 of 563 requiring formatting, the four shell lint gates and the two Python
  harness gates clean, `xcodegen generate` + `xcodebuild … -scheme MCPRouter -configuration Debug`
  `** BUILD SUCCEEDED **`.
- **`make all`, the iOS lanes, `parity`.** The whole-repo gate is the orchestrator's. M20 touches no
  iOS or parity file.
- **`scripts/acceptance/mac-shell.sh` end to end.** It requires a Release build as well as Debug, a
  second full `xcodebuild`. The bar was read with the same instrument that script uses (`axkit.swift`)
  through the same backgrounded launch path (`mac_app_launch`), covering its A19 count and order plus
  the item-level enabled/help/chord reads. The rest covers surfaces M20 did not change, which
  `UI_VERIFICATION.md` rule 2 says not to re-run.
- **Whether macOS draws the menu badge.** Structurally unreachable from the accessibility plane —
  19 attributes on each probed item, five direct probes absent, `AXHelp` correct on both as the
  presence control. This is the verdict's F4 and the gap-fix brief's addendum routes it to **M34**.
  Not attempted here.
- **Whether `swift build --build-tests` can see a fault `xcodebuild` calls fatal.** The verdict's F5,
  routed to **M33** by the same addendum. Both lanes were run here regardless, and both are green.
- **The popover opened by a person.** `SURF-009`'s three `n/a` cases stand: NSStatusItem is not an
  AXPress target while the app is backgrounded. §6 is the route that exists; taking the screen to open
  the popover is what rule 1 forbids.
- **A finding notification delivered.** Nothing in either target constructs an `AnalystFinding`, so no
  banner of that family can fire. The category registration, the action set, the routes and the copy
  are asserted as values; the delivered banner is the analyst's item.
