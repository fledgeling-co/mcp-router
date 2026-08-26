# M20 gap-fix 1 — it does not compile, and three of four slices are only in the plan

Verified **Needs More Work** at `984f00a` in `.worktrees/M20V`. Read
`planning/verification/M20-verdict.md` there first — it carries five findings with anchor, tree and
line, and the replacement arithmetic.

## Blocker 1 — the tree does not compile, and nothing has ever run against it

A bare `nil` in statement position at `MenuCommandAvailability.swift:110` fails `MCPRouterKit`.
`make test` exits **2** at its enumeration guard, so **no test in the suite has ever run against
this branch.**

Context you should have: this branch's contents were committed *on crash recovery* by a session
that finished its turn at 08:10 owing the commit and never gated what it wrote. `0bdfcbe` is
labelled in-body as an unverified checkpoint and that label was accurate.

`return nil` is the fix and the verifier confirmed it: everything then goes green — **1730 tests in
216 suites**, the macOS target builds, and the running menu bar holds every Slice A claim it could
reach (eight menus in the order `mac-shell.sh:394` expects **and had never run**, eleven dimmed
items carrying nine distinct unbuilt sentences, `⌃W` the only new chord, `⌘R` still on Reset
Server). It reverted its probe and hash-verified against HEAD, so that is a measurement rather than
a suggestion.

## Blocker 2 — three of the plan's four slices produced nothing

Seven names the plan promises **each occur in exactly one file, and that file is `plan-M20.md`**.
Establish which slices those are from the verdict, then either build them or withdraw them from the
plan with a reason. **Do not leave a plan asserting work that does not exist** — that is the same
class as a record asserting a state the tree does not hold, which this fleet has spent the day on.

## The record owes more than the guards do

You **armed** the A3 and A4 drift guards the plan claimed had been seen red. They had not been, and
both bite under mutation. So the guards are fine and **the plan's claim about them was false** —
fix the record, not the code.

## Five non-blocking, and the load-bearing one is in `DESIGN.md`

`DESIGN.md:623` refuses `⌥⌘Q` under a rule that does not reach it: *Review Held Changes…* **can**
fire. And *"eight of their ten commands"* is **nine of twelve**, repeated wrongly in three further
places — while the same source file gets the same arithmetic **right** twice. Correct the count and
say which of the two the rule actually needs.

## Do not re-derive these; they are measured

- `bcc69dd`'s isolation of `WORK-ORDER.md` **does** permit dropping it — reverse-applies cleanly,
  nothing after it touches that path.
- `make lint` and `make build-mac` both fail at `tools` in this worktree (no `node_modules`).
  Components run individually and green. Record that as **targets not run**, not as passing.
- **A count that varies is not a count.** An earlier draft's *"1734 discovered"* returns
  **1742 / 1734 / 1733** on the same tree because it counts SwiftPM build chatter. Read counts from
  the xUnit report.

## An abandoned draft is in this worktree — do not inherit its figures

A 548-line uncommitted verdict draft from a verifier session that died sits here. **Six of its
numbers were wrong** and the verifier that replaced it re-derived rather than carrying them across.
Its two blocking conclusions survived. Treat it as a lead, never as evidence.

## Mechanics

`.worktrees/M20`, branch `ai/m20` at `bcc69dd`, 3 commits. **`main` moves constantly** — merge and
re-gate; the verifier had to merge twice mid-gate (`6b8b3b1` → `c22f3f4`), and neither merge touched
Swift, which is why the Swift figures are M20's alone.

Do not run `git submodule update --init`. Do not run `make all`. Cite anchor **and** tree **and**
line. Name the normaliser behind any count. Presence-control every absence check. Read the file
back once after patching.

Commit on `ai/m20`, write `planning/progress/M20.md`, report ready-to-verify, stop.

---

## ADDENDUM, 2026-08-23 — F4 and F5 are NOT yours, and my brief should have said so

My brief carried five of the verdict's seven findings — F1, F2, F3, F6, F7 — and **said nothing
about F4 or F5.** That was an omission, not a scoping decision, and I am naming it rather than
letting you discover the gap.

Both now have destinations and **neither is yours to fix**:

- **F5** → `M33`. `swift build --build-tests` exits **0 and silent** on a fault `xcodebuild` calls
  fatal, because `app/Package.swift` declares no target at `MCPRouter/` while `app/project.yml:42-43`
  does. It is the mechanism behind M18's recurrence and reaches every branch touching that
  directory. Out of scope here; do not attempt it.
- **F4** → `M34`. The menu badge is unmeasurable by any lane we have — four closed, each measured.
  Evidence work rather than product work.

**One thing from F4 you should know while you work**, because it can mislead you: every `badge` hit
in `scripts/acceptance/mac-shell.sh` is a pre-existing **sidebar-row** badge (`:286 :310 :314 :316
:317 :321 :324 :331 :825`). If you grep that file for `badge` looking for menu coverage, you will
find nine hits and none of them is the menu. Do not read them as coverage you can build on.

F1, F2, F3, F6 and F7 remain the work.
