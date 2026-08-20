# X3 — the iOS unit lane read an empty accessibility tree because the engine was off

**Category:** ios · test instrument **Found:** 2026-08-20, mid-campaign, by `make all` going red
on a suite nothing in the branch had touched. **Closed:** 2026-08-20, same day, armed three ways.

`make test-ios` went from 35 passing to 52 failures with no change to this repo, and stayed there
over ten consecutive runs. Registered as **DEF-029** in `planning/test-campaign/inventory.json` and
carried as **CASE-0126**.

## The cause

The process-wide accessibility engine was off. SwiftUI's `_UIHostingView` builds its accessibility
container either way; with the engine off it vends an **empty array** — `accessibilityElements` is
`[]`, not `nil` — so every label-based assertion in the target read empty and reported its own
honest verdict, `nothing was measured, so this proved nothing`. From inside the suite that is
indistinguishable from a product rendering no copy, which is why ten runs of reading the failures
told nobody anything.

A probe settled it in one step. Hosting a view and reading the container reported zero elements;
calling `_AXSSetAutomationEnabled(true)` first took the same probe to one.

**The engine had been on by accident.** Something else on this machine had switched it on, which is
why this suite was green for months while depending on ambient host state no file in this repo
controls, and why it went red with no change to the branch. Enabling it deliberately is the fix for
that, not only for the outage: a lane that cannot switch on its own instrument is not measuring, it
is being measured for.

## The fix, in three parts

The third part exists because the first two were not enough, and the way they were not enough is
the more interesting half of this item.

**1 · Switch the engine on, once per process, before the first `host()`.**
`_AXSSetAutomationEnabled` is resolved out of `/usr/lib/libAccessibility.dylib` — falling back to
`AccessibilityUtilities.framework` — through `dlopen`/`dlsym`. A test-target dependency on a private
symbol, never linked into the app.

**2 · Read `accessibilityElements` before `accessibilityElementCount()`.** SwiftUI publishes through
the array and leaves the indexed API at zero: measured on iOS 26.5, one hosted `Text` reported
`accessibilityElements.count == 1` and `accessibilityElementCount() == 0` in the same breath, so
reading only the indexed API walked past every element SwiftUI had.

Those two took `make test-ios` from 52 failures to 0 — and then `make all`, run immediately
afterwards on the same device, came back with **39**.

**3 · Warm the engine in a process before the graded one.** The state is device-scoped and the call
lands on the *next* process, not the one that makes it. On a device left disabled, the run that
re-enables it fails a deterministic set of **15 test cases** — identical set, measured three times,
`comm` in both directions — and the run after it, unchanged, is clean. The 15 are exactly the cases
that host a `ScrollView`; the tests passing alongside them are geometry, counts and negative
assertions, all of which an empty tree satisfies, so the green half of that run was vacuous too.

`test-ios` therefore runs a throwaway single-test process first and discards its exit code, because
a warm device makes it a no-op and a cold one makes it fail for the reason the graded run exists to
report. Measured end to end: three consecutive runs with the call mutated to `(false)` drive
`MCPRouter-Unit` into the disabled state — 54 failures each, the whole suite red, correct for a dead
engine — and the very next `make test-ios`, with the warm-up in the recipe, is **36 tests, 0
failures, 1.4s**.

## The instrument check is itself instrumented

`testTheAccessibilityEngineCanBeSwitchedOn` blocks on a probe that hosts `ScrollView { Text }` and
reads it back through the same walk every other assertion uses, with a 20-second deadline. On a dead
engine the deadline fires and the case fails with `no hosted Text published a label within 20s` —
measured, not assumed.

Two narrower probes were built first, and both were wrong in opposite directions. A bare `Text`,
read either way, reports the engine live at t=0 of a run in which 15 cases go on to read empty. A
`ScrollView` read through the accessibility-container path alone reports the engine dead on a device
where all 35 other tests pass. **A probe that answers differently from the thing it stands for
answers a different question**, so the shape and the reader are both stated here rather than assumed.

## The three arms

| Arm | Device | Result | What it proves |
|---|---|---|---|
| Symbol renamed to `_AXSSetAutomationEnabledXXX` | `MCPRouter-Unit`, engine already live | 1 failure — the instrument test alone | The resolution assertion bites. It does **not** prove the other 35 depend on the engine |
| Call mutated to `_AXSSetAutomationEnabled(false)` | `MCPRouter-Arm`, created for the arm | **53 failures across 36 tests** | Every surface test in the target depends on the engine being on |
| Fix intact, first run ever on the device | `MCPRouter-Arm2`, engine never live | **36 tests, 0 failures** | A fresh device needs no warm-up; only an explicitly disabled one does |

Both arm devices were deleted afterwards. Recreate either by name: `make test-ios
IOS_UNIT_DEVICE=MCPRouter-Arm` builds a fresh one.

## Two hardening changes, neither of which is the fix

Both close real hazards this investigation surfaced, and the run stayed red with both in place.

- `test-ios` creates and owns `MCPRouter-Unit`, mirroring `test-ios-glass`'s `MCPRouter-Glass`, in
  place of `c.sort(key=lambda d: d['state'] != 'Booted')` — the exact picker DEF-020 condemned,
  still live in this recipe. Both lanes now share one device-lookup and one runtime-selection
  helper, so they cannot drift.
- The accessibility walk retains every element it visits, so `ObjectIdentifier` is unique among live
  objects as its use assumes.

A third — waiting on a *product* surface's tree over a two-second deadline — was written, measured
to change nothing, and **removed**. It cost 130 seconds a run and bought no measurement. The wait
that is kept differs from it in the one way that matters: it waits on a probe whose answer is known,
so a timeout is a fact about the instrument rather than about the view.

## What was refuted along the way

Each cost a run and each looked plausible: device contention (a fresh lane-owned simulator on a
different runtime failed identically), address recycling in the walker's `seen` set (retaining every
element changed nothing), publication timing on a product surface (the tree was absent, not late),
this branch (an untouched `HEAD` checkout in its own worktree failed the same way), and machine
saturation (still red at load 52 with no other `xcodebuild` running). The last of those was reported
to the owner as the cause before the probe ran, and it was wrong.
