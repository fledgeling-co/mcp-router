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

## Why these are `runs/*.txt`

`.gitignore:24` ignores `*.log` at every depth and `:39` negates exactly one directory —
`planning/test-campaign/evidence/` — with the reasoning written out beside it: `*.log` is right
everywhere else, and a repository that tracks every `.log` acquires them by accident. Written as
`.log` here, all seventeen captures sat on disk and in no commit, which is G24's defect exactly.
Renamed rather than negated, because the negation carries a decision this item has no business
widening.

**And they sit in `runs/` rather than beside this file, which is the second half.** `swift test`
prints each failed expectation as a suite file name, a line, a column and a message, and a lane
prints the mutation string it diffed, so a captured transcript carries bare `file:line` tokens by the dozen — three of
these carry 24 between them, and the citation ratchet counted every one against a writer who typed
none of them. `citation-gate.py` already excludes the campaign's run logs for exactly that reason;
`planning/evidence/*/runs/*` extends it to a gap-fix's captures by the same definition. **Scoped to
the subdirectory on purpose**: this README, and every acceptance note beside it, is authored and
still owes anchor and tree. A transcript nobody typed goes in `runs/`; everything else does not.

## Files (all under `runs/`)

| file | what it is |
|---|---|
| `armB-indexfailure.txt` | `swift test --filter IndexFailureRecordTests` under arm B — 2 tests in 1 suite failed, 11 issues |
| `armB-make-test.txt` | `make test` under arm B — 2100 in 267 failed, **14 issues**, make exit 2. Two suites of the 226 go red: `A failed index leaves a record` (11) and `Config watcher` (3, at `#expect(brokenEntry != nil, "a failed index must leave a manifest row, not nothing")`, `app/Tests/RouterCoreTests/WatchAdoptionTests.swift:152` at `95865f4`) |
| `armAB-make-test.txt` | `make test` under arms A and B at once — the same 14, measured rather than inferred |
| `unarmed-parity-*.txt`, `unarmed-control-differential.txt` | the five node-reaching instruments with nothing armed |
| `armA-parity-*.txt`, `armA-control-differential.txt` | the same five under arm A |
| `instrument-census-control.txt` | the census gate's 17 arms, nine of which require a class **not** to fire |
| `instrument-census-subject.txt` | the 24 of 444 instruments that name the manifest write path |
| `lint.txt` | `make lint` whole — exit 0, 0 violations over 708 files |
| `test-final.txt` | `make test` with everything reverted — 2100 in 267, exit 0 |

## The one red that is not this branch's

`unarmed-parity-cli.txt` is **exit 1 with nothing armed**: four `cli-help` rows disagreeing over a
`sessions` verb in the reference's usage block that this router's does not carry. It reproduces on
`main` at `83e5380` and this branch changes no CLI code. The consequence for reading this lane here
is stated rather than worked around — **the arm-A discriminator is the `cli-watch` row and the verb
count moving 14 → 13, not the exit code**, which is 1 in both columns.
