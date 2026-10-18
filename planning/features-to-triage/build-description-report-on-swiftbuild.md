---
status: to-triage
found-by: ai/build-system-pin, 18 Oct 2026, while making `make test` pass on SwiftPM 6.4
registry-target: none
no-target-reason: no registry case or requirement covers SwiftPM's swiftbuild layout, and the M33 report has never been run against it
---

# Port the build-description report to swiftbuild's `.build/out` layout before native is removed

- origin: `make test` on Xcode 27 / SwiftPM 6.4 ran the suite, then exited 2 with `the build description could not be reported: no build plan at .../app/.build/debug.yaml`. Found 18 Oct 2026.
- audience: anyone running `make test` on SwiftPM 6.4 or later, and whoever removes the `native` build system.
- platforms: mac

## What and why

SwiftPM 6.4 defaults to the `swiftbuild` build system on Xcode 27. Measured on Swift 6.4.0 (`swiftlang-6.4.0.34.1`) with a fresh library package: `swift build --build-system swiftbuild` completes and writes `.build/out/` and `.build/debug/`, and writes no `.build/*.yaml` plan. The same command with `--build-system native` writes `.build/debug.yaml` and prints `'--build-system native' has been deprecated and will be removed in a future release`.

`scripts/build-description-report.py` (M33) reads llbuild's plan at `.build/<config>.yaml` and the objects under `.build/<triple>/<config>/<Target>.build/`. Under swiftbuild there is no plan, so the report has nothing to describe and `make test` fails after the suite has already passed.

The stopgap in this change sets `SWIFT_BUILD_SYSTEM ?= native` in the Makefile and passes it to every `swift build` / `swift test` the Makefile runs, plus the two `swift build` calls inside the report. That keeps the gate reading the plan it was written for. It does not port the report, and the deprecation means the stopgap has an end date that the toolchain sets, not us.

## Acceptance sketch

- With `SWIFT_BUILD_SYSTEM=swiftbuild`, `python3 scripts/build-description-report.py` names a build description for the tree it compiled, or refuses with a reason that names the layout it could not read. It does not fail with `no build plan`.
- The report's per-target object checks read `.build/out/` objects and attribute every declared source to its target, including the poison arms that `--selftest` already runs.
- `make test` exits 0 under swiftbuild, prints a `build-description:` line, and the native flag can be removed from the Makefile and the report without changing any other gate.

## Assumptions made writing this

- The `.build/out/` layout above is the one measured on a library package in this probe. The layout of the real app package, with its test targets, was not inspected here.
- That the SwiftPM project will remove `native`. The deprecation warning says so, but no removal date is given.
- That porting is the right fix, rather than dropping the M33 description check under swiftbuild. The description check is what catches a suite that compiled a stale tree, so dropping it is a decision for its owner.
