# R19 gap-fix 5 — evidence

Every file here is a captured run, not a transcription. Measured 2026-08-29 in
`.worktrees/K2` on `ai/k2`, base `main` at `83e5380`, branch at `b8903ef`.

## The arms, and how to tell a real one from a silent green

| arm | site | blob before → armed → reverted |
|---|---|---|
| **A** node | the failed row dropped from `current` after `apply(current)` and before `saveManifest(manifestPath, current);`, `src/watch.ts:269` at `95865f4` | `9c2012b3…` → `f8f46525…` → `9c2012b3…` |
| **B** Swift | `Self.removeEntry`'s effect as `90f2be9` deleted it, ahead of `try? ManifestIO.save(manifest, toPath: manifestPath, fileSystem: fileSystem)`, `app/Sources/RouterCore/Watch/WatchIndexing.swift:209` at `95865f4` | `a57946b1…` → `14596ee6…` → `a57946b1…` |

**A first cut of arm B did not bite, and that is recorded rather than tidied.** It filtered
`manifest.servers` by the elements of `step.failed`, which `ManifestBookkeeping.build` populates as
`"<name>: <message>"` and not as bare names, so nothing matched and `make test` reported **2100 tests
in 267 suites passed, exit 0** — indistinguishable from a fix holding. It is the same defect the
fourth verification found in this record's arm-A instruction, one layer up, and it is why every
green cell below has an unarmed control run beside it on the same tree in the same session.

## Files

| file | what it is |
|---|---|
| `armB-indexfailure.log` | `swift test --filter IndexFailureRecordTests` under arm B — 2 tests in 1 suite failed, 11 issues |
| `armB-make-test.log` | `make test` under arm B — 2100 in 267 failed, **14 issues**, make exit 2. Two suites of the 226 go red: `A failed index leaves a record` (11) and `Config watcher` (3, `WatchAdoptionTests.swift:152-154`) |
| `armAB-make-test.log` | `make test` under arms A and B at once — the same 14, measured rather than inferred |
| `unarmed-parity-*.log`, `unarmed-control-differential.log` | the five node-reaching instruments with nothing armed |
| `armA-parity-*.log`, `armA-control-differential.log` | the same five under arm A |
| `instrument-census-control.log` | the census gate's 17 arms, nine of which require a class **not** to fire |
| `instrument-census-subject.log` | the 24 of 444 instruments that name the manifest write path |
| `lint.log` | `make lint` whole — exit 0, 0 violations over 708 files |
| `test-final.log` | `make test` with everything reverted — 2100 in 267, exit 0 |

## The one red that is not this branch's

`unarmed-parity-cli.log` is **exit 1 with nothing armed**: four `cli-help` rows disagreeing over a
`sessions` verb in the reference's usage block that this router's does not carry. It reproduces on
`main` at `83e5380` and this branch changes no CLI code. The consequence for reading this lane here
is stated rather than worked around — **the arm-A discriminator is the `cli-watch` row and the verb
count moving 14 → 13, not the exit code**, which is 1 in both columns.
