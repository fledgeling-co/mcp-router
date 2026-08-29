# M39 — the whole-gate run

Verdict lines only, with the producing command in each header. No raw gate capture is committed:
a gate quotes `path:line` in its own findings text, and citation-gate holds a new file to a baseline
of zero bare citations, so recording a green run here would redden the next one.

Tree: `5102d8e`, branch `ai/n6`.

## `make lint` — exit 2

Run as `make -f ./Makefile lint`, and the spelling is deliberate: two earlier runs of `make lint`
were killed mid-flight by another runner in this fleet issuing `pkill -f "make lint"`, which matches
any command line containing that substring. `make -f ./Makefile lint` does not.

Thirty-three members. Thirty-one clean, including every member this item could have moved:
swiftformat, swiftlint strict (0 violations over 725 files), `no-raw-design-values.sh` (clean over
148 files, 107 under the geometry and boundary rules), `citation-gate.py` (control 0 · blocking 0 ·
ratchet 0), `instrument-census.py` (census matches the tree, 465 instruments), `evidence-citation-gate.py`,
`target-resolution-gate.py`, `registry-drop-gate.py`, `capture-manifest.py`, `raster-claim-gate.py`,
`effect-class-census.py`, `vocab-differential.py`, `pin-class-gate.py`, `shipped-brief-gate.py`.

Two members failed, and neither is this branch's:

**`sweep-control-gate.py` — one finding, and it is the machine.** It reports
`scripts/acceptance/acceptance-lanes-selftest.sh: its declared control does not pass — control did
not finish in 120s`. Re-run alone, as the fleet's own note instructs:

```
./scripts/acceptance/acceptance-lanes-selftest.sh
```

exit 0, `acceptance-lanes selftest: 13 arms, all held`, 1:59.59 wall. The gate's timeout is 120s and
the control needs ~120s under contention, so the finding is a load artefact rather than a rotted
control. Load averages during the lint run were 516–895 across 16 cores with eight runners live.
Nothing this item added was discovered as a new undisposed sweep.

**`brief-target-gate.py` — exit 1, and it was red before this branch existed.** Measured in this
worktree at `08a24ed`, before any edit: `84 undeclared over 84 file(s) against floor 82 — 3 above,
1 below`, naming three briefs none of which this item touches. After this branch it reads `83
undeclared over 83 file(s) against floor 82 — 3 above, 2 below`: one lower, because M39's own brief
now declares `reckon-sources`. The floor was not rewritten — `--set-floor` rewrites every file's
count, and with eight runners live that would lock in whatever the others happen to be mid-edit.

**The baseline this run was handed says `make lint` exit 0 over 29 members, and that is stale in
both numbers.** Thirty-three members run today, and the brief-target floor has been above its
ratchet since three briefs landed after the baseline was taken.

## `make test` — 2171 tests in 276 suites, 1 issue

```
make test
```

Baseline was 2160 tests in 275 suites. This item adds 11 tests and one suite, which is the whole of
the difference.

The one issue is `OAuthWireTests.swift:263`, *"a waiter that is cancelled is resumed rather than
stranded"* — named in this run's brief as one of three known load flakes. Re-run in isolation:

```
swift test --filter 'OAuthWireTests'
```

exit 0, 18 tests in 5 suites. Nothing under `Pairing` or `Inbox` failed in either run.

## The targeted suites

```
swift test --filter 'PairingSheetTests|MacPairingTests|PairingExpiryTests|InboxConformanceTests'
```

exit 0, 49 tests in 5 suites. `InboxConformanceTests` is in the filter because its A15 colour census
is one of the assertions this item armed — see `arming.md`.
