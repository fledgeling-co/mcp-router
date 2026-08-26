# M34 — the menu badge, measured

The item was filed because the one new user-visible behaviour in M20's Slice A could not be measured
by any lane the project had: **six commands are dimmed with a badge explaining why and carry a
keyboard chord as well, and nothing could say which the trailing area shows.** Four lanes were
recorded closed. Two of them were closed for the wrong reason, one of those two is now open, and it
is the one that settles the question.

Everything below was measured on 2026-08-26 against tree `7ae54be`, macOS 26.1, with the frontmost
application recorded before and after every run and asserted unchanged.

## The correction

The brief's first closed lane reads *the accessibility tree exposes no badge attribute — 19
attributes on each probed item, five direct probes absent*. Both halves are true, and the conclusion
drawn from them is not.

**The badge is on the accessibility plane, folded into `AXTitle`**: a badged item's title reads
`Title, Badge`. The earlier probe enumerated the attribute *names* on each item, found the same
nineteen this one finds, found no badge among them, and stopped. The badge is in `AXTitle`'s
**value**, which a list of names cannot see.

That is one layer up from the trap the brief itself names — *a grep for `badge` in the acceptance
lane returns nine hits and none of them is this* — and it is the same shape: an absence check with a
correct-looking measurement above it.

macOS corroborates it in the same dump without being asked. The Apple menu's own badged item reads
`App Store…, 29 updates`.

## What each lane does now

| Lane | Verdict | Evidence |
|---|---|---|
| Accessibility plane, AppKit-built menu | **Open** | `menu-badge-lane.sh` — badge folds into `AXTitle` at construction and post-hoc, enabled and disabled |
| Accessibility plane, SwiftUI-built menu | **Closed**, narrowly | same lane — the badge never reaches the plane, while an in-process readback shows SwiftUI still holds it |
| AppKit layout (`NSMenu.size`) | **Open — this is the one that settles it** | `MenuBadgeTrailingAreaTests` |
| `AXPress` actuation | Closed, unchanged | `axkit.swift` header |
| Photography | Closed, unchanged | `UI_VERIFICATION.md` rule 1 |

The app's menu bar is built by SwiftUI, so the plane stays closed **for this app**. That limit is
much narrower than the one the brief inherited, and it is now a tripwire rather than a note.

## The trailing area — the claim M34 was filed to settle

`NSMenu.size` lays a menu out and returns the width AppKit reserves, in-process, with no window and
no tracking session. Nothing is drawn on the user's screen, which is what closed the photography
lane. Measured on `Install Command-Line Tool`, in points:

| | plain | chord only | badge only | both |
|---|---|---|---|---|
| width | 194 | 235 | 300 | **319** |

319 is strictly greater than both 300 and 235, so AppKit reserves trailing space for the badge **and**
the chord. **Neither displaces the other.** `MenuBadgeTrailingAreaTests` makes that per-command over
all six, each against its own two controls — *wider than the badge alone* and *wider than the chord
alone* fail on opposite mistakes, and either alone would pass a build in which the other had been
displaced.

The set is counted as well as checked, and the count is **six** — the brief's number, now measured
rather than asserted. Without it a set that quietly empties makes every width check pass over
nothing; the mutation below shows exactly that happening.

## That the walker reaches the real menu

The layout oracle builds its own `NSMenu`, which is the criticism M34 makes of the existing unit
test. It is evidence about the platform's layout rule, not about this app's wiring. The wiring is a
separate chain, and each link was measured:

1. **SwiftUI's `.help()` does not reach a menu item's `AXHelp`.** A SwiftUI fixture item carrying
   `.help("swiftui help string")` reports no `AXHelp` at all.
2. **The running app's menu items carry their reasons in `AXHelp`** — 11 of them, each the right
   sentence, e.g. `Wake Selected Server` → *Select a server first.*
3. Therefore only `ShellMenuReasons` can have written them, so **the walker reaches the real
   SwiftUI-built menu**. Its badge line is three lines below its help line in the same matched block.
4. **A post-hoc badge on a SwiftUI-built item is retained**, read back in-process as
   `item.badge?.stringValue`. The badge is unexposed, not lost.

Link 1 is the load-bearing one, and it is a tripwire in the lane: if `.help()` ever starts reaching a
menu item, the app's help tags stop being evidence that the walker ran, and this chain needs
rebuilding. The lane says so in its own failure message.

**The behaviour is correct.** That was never in doubt; what it lacked was anything that could say so.

## Falsifiability

Every assertion added was mutated and watched to fail.

| Mutation | Result |
|---|---|
| `width()` drops the chord when a badge is present | 6 failures, one per command: `(together → 232.0) > (badgeOnly → 232.0)` |
| the badged-and-chorded set filters to empty | count assertion fails; **the width test passes in 0.001s over nothing**, which is why the count exists |
| the AppKit fixture stops setting badges | `AppKit no longer folds a badge into AXTitle for 'Badge Only'` |
| a folded badge renames a SwiftUI item | the readback control fired *before* the tripwire — see below |

The two limit tripwires resisted provocation from the fixture side: folding a badge into a SwiftUI
item's title is undone by SwiftUI's next rebuild, `setAccessibilityTitle` does not override `AXTitle`
on a menu item, and an AppKit-built item planted in a SwiftUI app's menu bar does not get its badge
folded either. That last one is a finding rather than an obstacle — the limit is a property of the
menu bar the process owns, not of the individual item. It also means the failure path is only
reachable through the dump, so `menu-badge-lane-selftest.sh` hands each tripwire a doctored dump and
requires it to fire, and a third case requires neither to fire on the dump today's platform produces.

**One real defect in this work was found by mutating it.** The readback control matched its item by
exact title, so the very event the lane watches for — a badge folded into the title — renamed the
item and made the control fail one line *before* the tripwire could fire. The day the lane opened
would have been reported as *SwiftUI dropped the badge*: a wrong diagnosis, which is worse than
silence. The control now matches by prefix.

## Gates

| Gate | Command | Exit |
|---|---|---|
| Mac build | `make build-mac` | 0 |
| Unit — new + existing menu suites | `swift test --filter "MenuBadgeTrailingAreaTests\|ShellMenuContextTests"` | 0, 8 tests |
| The lane | `scripts/acceptance/menu-badge-lane.sh` | 0, 8 assertions |
| The lane's selftest | `scripts/acceptance/menu-badge-lane-selftest.sh` | 0, 3 assertions |
| swiftformat | `swiftformat --lint . --config .swiftformat` | 0, 650 files |
| swiftlint | `swiftlint lint --strict --config .swiftlint.yml` | 0 violations, 639 files |
| shellcheck | `shellcheck` on both new scripts | 0 |

`scripts/acceptance/mac-shell.sh` was **not** run end to end; it requires a Release build as well as
Debug, and M20's own record notes it was skipped there for the same reason. Nothing in this item
changes a surface it asserts on. What it does change is a warning it now carries — see below.

## What this leaves for someone else

- **`mac-shell.sh` matches menu item titles exactly against the spec inventory.** A folded badge
  makes a title `Command, Badge`. So on the day a SwiftUI item's badge does reach the plane, the
  first gate to report the good news will report it as thirty missing commands. The lane's failure
  message says this; the gate itself does not, and hardening it is not this item's to do.
- **Rendering is still not measured, and cannot be by these lanes.** `NSMenu.size` is the width
  AppKit reserves, not the pixels it paints. A trailing area with room for both is one that
  displaces neither, which is the claim; it is not a claim that both are legible, correctly ordered,
  or drawn at all.

## Ledger

| Screen | How verified | Commit | Result |
|---|---|---|---|
| Menu bar — badge on the accessibility plane | `menu-badge-lane.sh`, two fixtures, frontmost asserted unchanged | `7ae54be` | pass — limit measured and tripwired |
| Menu bar — badge and chord in one trailing area | `MenuBadgeTrailingAreaTests`, `NSMenu.size` over all six commands | `7ae54be` | pass — neither displaces the other |
| Menu bar — the walker reaches the real menu | AX dump of the running Debug app, launched `open -g`, pid 63976 | `7ae54be` | pass — 11 items carry the walker's help tags |
