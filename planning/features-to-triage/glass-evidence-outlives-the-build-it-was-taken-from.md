---
status: in-progress
found-by: reckon 1.7.0, 2026-08-29
---

# Committed glass evidence outlives the build it was taken from, and nothing goes red when it does

- origin: reckon 1.7.0, `DEF-058` and `DEF-059` with `CASE-0001`, `CASE-0016`, `CASE-0101`,
  `CASE-0111` rolling up to them · 2026-08-29
- audience: whoever reads a green macos-glass lane and takes it for a statement about the shipped app
- platforms: mac
- proposed-by-ai: true

## What and why

The macos-glass lane was green over window evidence captured from a build that predates M22, and four
of its cases assert a shell that no longer ships. Re-capturing against the current build turns those
four red, and in each of them the product is right and the recorded evidence is stale: M22 added
destinations and renumbered accelerators, and M15 moved Settings out of the sidebar, so the committed
menu map and the committed sidebar selection both describe an app that is gone.

`DEF-059` is the same illness one step further on. Because the `Settings` selection silently stopped
taking, the shutter photographed whichever board the loop last visited and filed it under a surface it
was not pointed at — a wrong picture with a right-looking filename.

The cause is one thing: **a committed capture carries no tie to the build it came from**, so nothing
can notice when the build moves past it. The failure is silent in the worst direction. Between the
capture and the re-run, the lane reported green over assertions that had already stopped being true,
and the only reason anybody knows is that somebody re-took the pictures by hand.

Editing the stale assertions back to green is the one move that must not be taken here: the stale
assertion is the instrument that found this.

## Acceptance sketch

- Every committed capture records which build it was taken from, and a lane run against a different
  build says so rather than passing.
- A selection or navigation step that does not take fails the case, instead of letting the capture
  proceed and be filed under the surface that was asked for.
- The four cases currently failing pass over evidence re-taken from the current build, with the
  assertions updated to what the product now does rather than the other way round.
- A green glass lane can state the age of the evidence behind it, in a place a reader meets before the
  verdict.

## Assumptions made writing this

- Assuming the fix binds a capture to its build rather than requiring a full re-capture on every run,
  which would be honest and too slow to survive.
- Assuming the product is right in all four cases, as the re-measurement found, so the work is
  re-capturing and correcting assertions rather than changing the app.
- Assuming this is separate from the resolved re-anchoring brief, which re-measured the campaign once;
  this is the mechanism that would have made the re-measurement unnecessary.

## What landed, and what is still owed

**The mechanism is in; the re-capture is not, and the two halves must not be read as one.**

`planning/test-campaign/bin/glass-build-gate.py` binds every artifact the `macos-glass` lane cites to
the build it was taken from. The identity is the git blob identity of the Mac app's own build
inputs — `app/MCPRouter`, `app/Sources/MCPRouterKit`, `app/Sources/MCPRouterUI`, `app/project.yml`,
`app/Package.swift`, `app/Package.resolved` — the set `scripts/acceptance/build-freshness.sh`
compiles from, read out of that file rather than copied, so a Mac input added there and missed here
fails as INPUT DRIFT instead of quietly narrowing every verdict below it. Blob ids are line-ending
normalised, so the verdict is the same on macOS and on Windows for one commit.

It is RED on this tree, over all 56 artifacts in 7 capture groups spanning 20-29 Aug, and the finding
is true: `evidence/runs/glass-build-gate.log`, exit 2. `CASE-0342` carries it, failing.

Going forward the stamp is written by the capture channel rather than reconstructed:
`bin/capture-mac-glass.sh` now calls `glass-build-gate.py --emit` in the run that takes the pictures,
recording the bundle's own `CFBundleShortVersionString` and `CFBundleVersion` and the
`sources`/`binary` digests from `.mcprouter-build-stamp`, which the Makefile writes only after
`xcodebuild` exits 0. The rows committed today are marked `reconstructed-from-git` and are
deliberately the weaker claim — git can prove which commit last wrote each artifact, so a
reconstructed row establishes the build the evidence CANNOT BE NEWER THAN rather than the build it
came from.

Watched both ways, because this gate is red on the tree it ships on and its green cannot be observed
by running it: `evidence/runs/glass-build-gate.selftest.log` — green over a capture stamped with the
current tree, red over a stale one, red over one no record covers, red over a row that cannot be
dated. `make lint` runs the selftest; `make glass-build` runs the gate, and it stays out of `lint`
and `all` for the reason `role-intersection` does, so a standing red does not get softened inside a
week.

**Owed, and owned by a macOS host with Xcode and a display server.** None of this was possible on the
Windows host the work was done on — no Swift toolchain, no `xcodebuild`, no display server:

1. The re-capture itself. `CASE-0001`, `CASE-0016`, `CASE-0101` and `CASE-0111` stay `fail` and each
   carries an `owed` block naming the re-capture, its owner and what blocks it. No assertion, stamp
   or recorded identity was edited to restore a green; the stale assertion is the instrument.
2. `SURF-011` still has no route to the Settings SCENE — `axkit select Settings` has failed since M15
   and `bin/capture-mac-glass.sh` correctly withholds the photograph rather than filing a
   neighbouring board under it. `DEF-059`.
3. `SURF-001`'s menu map, to be re-read from `Destination.selectionDigit` rather than by hand.
   `DEF-058` §1.
4. The acceptance line "a green glass lane can state the age of the evidence behind it, in a place a
   reader meets before the verdict" is not delivered. The gate prints the age; `evidence.html` does
   not yet carry it.
