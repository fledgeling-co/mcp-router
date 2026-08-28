# M34 — what a menu-badge assertion can honestly stand on

M34's first pass built two fixtures and a layout oracle, and merged at `6fab22a`. It left one thing
resting on a measurement taken once by hand: **that the walker reaches the app's real menu.**
`planning/evidence/M34-acceptance.md` records that against `pid 63976`, in prose. A measurement
taken once and written down is a claim about a day.

This pass answers the oracle question the item was re-opened on — *what could a menu-badge
assertion stand on, and where does that stop* — and turns the reachable part into a lane. Nothing
here is a scoring change: no case was marked `n/a`, and nothing activates the app.

Measured 2026-08-29, macOS 26.1, against the Debug build at `34cde4f`, launched `open -g` and never
frontmost.

## The badge is three claims, not one

The item reads as a single question and is not. Separating it is what makes two thirds of it
answerable and the last third honestly refusable.

| Claim | Channel | Rung | Status |
|---|---|---|---|
| A dimmed command explains itself on the app's own menu | `AXHelp` off the running app | outcome | **open — `menu-reason-plane.sh`** |
| The reason determines the badge beside it | the model, over every context | structural | **open — `MenuReasonBadgePairingTests`** |
| A badge and a chord both get trailing room | `NSMenu.size`, in-process | metamorphic | open — `MenuBadgeTrailingAreaTests` (merged at `6fab22a`) |
| The badge **as drawn**, on the menu the user opens | — | — | **unoracled — `CASE-0197`** |

The first two are new here. The third is the merged work, now joined to the campaign. The fourth is
the honest floor, and it is recorded as `unoracled` rather than `n/a` — the check applies, and
nothing available performs it.

## What the running app's menu actually exposes

220 menu items, read off the accessibility plane with the app backgrounded.

- **11 carry a reason**, each one a sentence `MenuCommandAvailability` declares. The lane derives
  its accepted vocabulary from that source file at run time — `sed` over `reason`'s two generic
  arms and `unbuiltSubject`'s nine — so a list cannot drift from the code it is about.
- **No item's `AXTitle` carries a badge.** AppKit folds a badge into the title and SwiftUI does
  not; the merged lane measured that on fixtures, and this measures it on the product.
- **`AXSize` is exposed on all 220 items and reads `0.0x0.0` on every one.**

That last row is the finding this pass turns on, and it is the shape of M34's own original error one
layer along. `AXSize` is *present*. A probe that enumerated attribute names would report the
geometry channel as available, and a lane built on that reading would compare zeroes and pass.
The channel is named, not open: a menu that is never opened is never laid out, and a background
app's menu is never opened.

So `assert_geometry_channel_closed` asserts the zero rather than assuming it. The day it carries
real numbers, `MenuBadgeTrailingAreaTests`' relation can be re-made against the menu the user
actually gets instead of one the test builds — which is the stronger measurement, and the lane says
so in its failure text.

## Falsifiability

`menu-reason-plane-selftest.sh` hands each of the five assertions a doctored dump and requires it to
fire, then requires **none** of them to fire on the dump today's platform produces. That third case
is the two-way control: every assertion here asserts an absence, and a check that cannot fire and a
check that correctly does not fire look identical from outside.

| Arm | Result |
|---|---|
| a reason `MenuCommandAvailability` does not declare | refused |
| a badge folded into `AXTitle` | caught |
| a menu item reporting `319.0x22.0` | caught |
| a dump of one item | refused — the probe read almost nothing |
| a dump carrying no reason at all | refused — the walker annotated nothing |
| all five against a real dump | silent |

**Two defects in this work were found by arming it, and neither would have shown in a green run.**

1. `assert_the_badge_is_not_on_this_plane` used `exit 0` inside an `awk` rule. `awk`'s `exit` runs
   the `END` block, and `END { exit 1 }` overrode the hit — so the tripwire watching for the one
   event this lane exists to notice **could never fire**. It passed every real run.
2. The rule-1 check asserted *frontmost is unchanged*. It failed on a run where frontmost went from
   `Google Chrome for Testing` to `ghostty` — neither of them this app, neither of them this lane's
   doing. `mac-shell.sh:207` had already settled this: the invariant is *this app never comes to
   the front*, not *the front never moves*. A rule-1 check that cries wolf is worse than none.

The two controls were inline when the lane was first written, so the selftest could arm three
assertions of five and the other two were taken on trust. They are functions now.

## A third defect, in the lane's own plumbing

`pgrep -f "$APP/Contents/MacOS/MCPRouter"` matched nothing against an app that had started
perfectly. `.worktrees` is a symlink onto another volume on this machine, so a worktree has two
spellings, and a bundle launched through the logical one produces a process whose argv carries the
physical one. `worktree-preflight.sh` is an entire gate about the two ways that breaks a *build*;
it breaks a process lookup too, and more quietly — the lane reported *the app never appeared in the
process table*. The bundle is resolved with `pwd -P` before any lookup now.

## What this leaves

- **The reason count is state-dependent and is deliberately not pinned.** Two consecutive runs read
  11; an earlier run of the same build read 13. The lane asserts `> 0` and reports the number.
  Pinning it would fail on a selection change, which is the app working.
- **`Reset Server` and `Remove Server` were observed dimmed with no reason on the plane**, while the
  Router and Library menus' commands all carried theirs. Not chased here: it needs the app's
  selection state controlled to tell a walker that missed them from a context in which they are
  legitimately enabled and dimmed by AppKit for another cause. Recorded as an observation, not filed
  as a defect, because this pass did not establish which.
- **Rendering is still not measured and cannot be by these channels.** `NSMenu.size` is width
  reserved, not pixels painted, and CASE-0197 names the three conditions that would open a rung.

## Gates

| Gate | Command | Exit |
|---|---|---|
| The new lane, against the running app | `scripts/acceptance/menu-reason-plane.sh` | 0, 6 assertions, twice |
| Its selftest | `scripts/acceptance/menu-reason-plane-selftest.sh` | 0, 10 arms |
| The merged badge lane | `scripts/acceptance/menu-badge-lane.sh` | 0, 8 assertions |
