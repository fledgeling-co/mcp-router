# G4 gap-fix 3 — the two gates broke the doctrine they were written to enforce

Parent `G4` (merged `de1315d`) · branch `ai/g4b` · worktree `.worktrees/G4B` · base `e4f4e9a`
Answering the orchestrator's merged-tree gate run, 2026-08-22. **`main`'s `make lint` was red.**

Both of G4's gates were green on `ai/g4` and red once other verified work stood beside them — the
fleet's fourth merge-only break. `swiftlint` was clean over 549 files, so these two were the whole
of it. Neither was wrong about its subject; one carried a stale literal and one drew its
enumeration boundary in the wrong place, and both are failures the item itself had already written
down about somebody else.

Three files changed, all under `planning/`. No Swift, no `Makefile`, no change to either lint
script.

---

## 1 · BL-1 — the RAW arms restated a directory list instead of reading it

`lint_tree(script, dirs, …)` created exactly the directories its caller named. M15 widened
`GEOMETRY_DIRS` in `no-raw-design-values.sh` from three to four by adding `Settings`; the three RAW
arms still passed three. `no-raw-design-values.sh` requires **every** listed directory, so it
exited at `:149` with *the geometry checks did not run*, the plant was never reached, the script
stayed green, and each arm honestly reported that it could not discriminate:

```
$ python3 planning/null-run-gate.py BASE-raw RAW-import RAW-bridge NULL-raw      # base e4f4e9a, exit 1

 HELD  BASE-raw     poison  no-raw-design-values.sh  the scratch tree is clean, so a red under a plant is the plant
         exit 1, expected 0; output does not carry 'no-raw-design-values: clean'
      no-raw-design-values: scanning 6 files
      error: …/app/Sources/MCPRouterUI/Settings does not exist — the geometry checks did not run
 HELD  RAW-import   poison  no-raw-design-values.sh  MCPRouterKit importing a UI framework
 HELD  RAW-bridge   poison  no-raw-design-values.sh  a shell growing its own colour bridge again
```

This is the item's own thirteenth instance one level up. M15's arm 6b found that
`no-raw-design-values.sh` reads *the directories currently in `GEOMETRY_DIRS`* rather than *the
design surfaces*; G4 filed it as **derive the denominator from the data, never from a literal
beside it**, and then shipped a literal beside it.

`script_dirs(script)` now reads every `"$ROOT/…"` the script itself names, in order and
de-duplicated, and `lint_tree(script)` with no `dirs` derives. Over-inclusion is the free direction
— a scratch directory nothing scans costs one empty `mkdir` — and under-inclusion is the failure
above, so the sweep is deliberately loose.

### The derivation is armed

A scratch copy of the repository, with a fifth directory added to `GEOMETRY_DIRS` that exists
nowhere in this repository, run by a **byte-identical** `null-run-gate.py`:

```
$ diff planning/null-run-gate.py $SC/planning/null-run-gate.py
  (no output — not edited for the fifth directory)
$ ls app/Sources/MCPRouterUI/Quarterdeck
  ls: app/Sources/MCPRouterUI/Quarterdeck: No such file or directory

$ script_dirs("no-raw-design-values.sh")   # against the widened copy
    app/Sources/MCPRouterUI · app/MCPRouter · app/MCPRouterIOS
    app/Sources/MCPRouterUI/Shell · app/Sources/MCPRouterUI/Activity
    app/Sources/MCPRouterUI/Boards · app/Sources/MCPRouterUI/Settings
    app/Sources/MCPRouterUI/Quarterdeck                                 ← followed, unedited
    app/Sources/MCPRouterKit

$ python3 $SC/planning/null-run-gate.py BASE-raw RAW-import RAW-bridge NULL-raw   # exit 0
  armed          4 assertions, 4 changed verdict under a poisoned or null input
```

`no-wire-codable.sh` is **not** derived from, and the reason is written beside `WIRE_DIRS`: it
spells its directories as bare names under its own `ROOT=` and tolerates a missing one
(`[ -d ] && present+=`), erroring only when none exist. A stale literal there cannot produce the
early exit above, so a derivation would buy nothing and lose the arms' ability to say which two
directories they mean to plant in.

The one shape `script_dirs` would read wrong is a `"$ROOT/…"` naming a **file**, which would be
created as a directory. The script names none today, and one appearing goes loud rather than quiet:
the read fails, `set -euo pipefail` kills the script, and the arm reports that it could not
discriminate rather than reporting a pass. Stated in the docstring rather than left to be found.

---

## 2 · BL-2 — the accounting gate enumerated the filesystem, not the repository

`main`'s red was `planning/test-campaign/bin/witness-fixture/fixture-server.py`, which `git status`
shows as `??` and which belongs to another session's in-progress work. The gate walked
`(ROOT / d).rglob("*.py")`, so a file that is not in the repository reddened a shared branch, and
nobody reading the red could act on it.

It now enumerates `git ls-files`, the way `claim-sweep.py` already did, and **closes its count back
on it**:

Measured on the fix at `dbd8af8`, **before this document was tracked**. Committing it moves the
total and the `elsewhere` column by one and leaves the 22 unchanged, so the numbers below are
quoted against a named tree rather than against whatever the file count is when you read them:

```
$ python3 planning/reader-accounting.py                                          # exit 0

reader-accounting — raw-input readers in planning/ and scripts/

  enumerated   1325 paths tracked by `git ls-files` — 22 Python under planning/ and scripts/ + 0 tracked but absent
               from the working tree + 1303 elsewhere = 1325
  files          22 Python files, 0 unparsed
  …
  unaccounted     0 drop silently and say nothing

$ git ls-files | wc -l
1325
```

`planning/test-campaign/bin/glass-assert.py` is one of the 22 and contributes the run's largest
block of unresolved subjects (8), which is what makes the "the boundary moved, not one directory"
sentence checkable rather than asserted.

The partition is three-way rather than two, because a tracked path with no file behind it is a
staged deletion or a half-finished checkout and a denominator that quietly shrinks is the failure
this gate is for. `scanned_python` branches every path into one of the three and discards none, so
the gate is not itself a silent drop; `tracked_files` slices `-z`'s trailing terminator rather than
filtering it, for the same reason — a comprehension's `if` over raw input is a silent drop by
shape, and this gate says so about everybody else's.

**The boundary moved, not one directory.** A tracked file under `planning/test-campaign/` is still
fully in scope — the exclusion list the brief ruled out was not written. What changed is that the
population is the repository rather than the working directory.

The cost is real, is new, and is now in the docstring's *what this gate does NOT do* list: a silent
drop written this morning is invisible until it is tracked. The alternative cost is the one that
was measured.

### Verifying the change with the finding it was raised for

`main`'s untracked file does not exist in a fresh worktree, so the class was reproduced with an
untracked leaky reader planted **outside** `planning/test-campaign/`:

| | Before (`rglob`) | After (`git ls-files`) |
|---|---|---|
| `planning/zz-untracked-probe.py` (deleted after; never committed) present | 23 files, `unaccounted 1`, **exit 1** | 22 files, `unaccounted 0`, **exit 0** |
| probe removed | 22 files, exit 0 | 22 files, exit 0 |

---

## 3 · Two consequences, both raised by the gates rather than by a plan

**The `node_modules` declaration outlived its reader.** `planning/reader-accounting.py::main` was
declared for a `node_modules` filter in the census comprehension. `git ls-files` does not name
untracked or ignored paths, so the filter went and the declaration had nothing left to describe.
The gate said so on the first run after the change. The row went and the pin moved `18 → 17` in the
same change, which is what the file's own header demands; the reason is recorded in the header
rather than only in this document.

**The scratch-repository helper was itself a new silent drop.** The first cut of `make_repo` wrote
`sorted(str(p.relative_to(root)) for p in root.rglob("*") if p.is_file())` — an `rglob` filtered by
a comprehension `if`, which is exactly what the gate flags. It went red, unprompted, naming
`planning/null-run-gate.py::make_repo`. It now partitions files and directories into two lists and
drops nothing, and the directory count is used in the failure message rather than being decorative.
This is case C from G4's own verification table happening a second time, on the same day.

---

## 4 · The accounting arms now get a repository, and only they do

`git ls-files` is the instrument's own enumeration, so a scratch tree that is not a repository would
have armed the *cannot-enumerate* path instead of the check each arm is named for. `Arm` gained
`repo: bool`, and `fire()` runs `git init` plus an explicit `git add` of the files the builders
wrote — collected before `git init`, so the index never grows `.git`'s own contents, and named
individually, so an arm's fixture is exactly what its builders wrote.

Five arms declare it: `BASE-accounting`, `ACC-silent-reader`, `ACC-pin`, `ACC-stale`,
`NULL-accounting-empty`. The reconciler's trees stay non-repositories, so check E keeps measuring
nothing and the reason `NOT_ARMED` gives for leaving it out stays true — that entry was tightened
to say *the reconciler's* scratch trees rather than *a* scratch tree, since the sentence is no
longer true of all of them.

`NULL-accounting-empty` still stands on git having no index entry for a directory: its `planning/`
and `scripts/` are empty, so nothing under them is tracked and the gate reaches its usage error.

---

## 5 · Acceptance

| # | Asked | Measured |
|---|---|---|
| 1 | `make lint` exits 0 with both gates wired as they are | **exit 0.** `swiftlint` 0 violations over 549 files · `no-raw-design-values: clean` (125 scanned, 84 under the geometry rules) · `no-wire-codable: clean`, 2 exemptions · `no-harness-config-writes` 337 examined, selftest 27 cases held · `reader-accounting` exit 0 · `null-run-gate` exit 0 |
| 2 | RAW arms derive their directories, and the derivation is armed | §1. A fifth directory (`Quarterdeck`, present nowhere in the repository) added to a scratch copy of the script; all four RAW arms followed it with `null-run-gate.py` byte-identical |
| 3 | `reader-accounting.py` enumerates `git ls-files`, count stated and reconciles | §2. `22 + 0 + 1303 = 1325` = `git ls-files \| wc -l`, both at `dbd8af8` |
| 4 | Both gates still bite — re-run G4's two verification arms | **A:** deleted one `tally.drop(…)` from `ledger-reconcile.py::table_ids` → `unaccounted 1`, named `planning/ledger-reconcile.py::table_ids drops at :72 continue`, exit 1. Restored: exit 0. **B:** check L's marker changed to `^(<<<<<<<X \|=======X$\|>>>>>>>X )` — intact, plausible, unmatchable → `HELD L`, `armed 28, 27 changed verdict`, exit 1. Restored: exit 0 |
| 5 | Reconciler 0 across A–L; `make test` unmoved at 1725 in 215 | **`reconciled — no findings across A, B, B-range, C, D, E, F, G, H, I, J, K, L`**, exit 0. **`Test run with 1725 tests in 215 suites passed`**, `make test` exit 0 |

All 28 standing arms bit: `armed 28 assertions, 28 changed verdict`, `held green 0`, `blocked 0`.

Check E fired once, before the commit, on `G4-B (ai/g4b)` — this branch sitting at `main`'s tip
with no commits on it yet reads as merged. It cleared on the first commit, which is the check
working rather than a finding.

---

## 6 · What this does not reach

Both gates keep every limit G4 stated for them, and this change adds one:

* `reader-accounting.py`'s population is now what the repository tracks. A silent drop is invisible
  until the file is added. That is the trade taken, and it is written in the module docstring
  beside the four limits already there.
* `script_dirs` derives from `no-raw-design-values.sh` only. `no-wire-codable.sh` keeps its literal,
  for the reason in §1 — its own tolerance of a missing directory means a stale list there cannot
  produce this failure.
* Neither fix touches what G4's own summary says its gates cannot do: a bite proves an assertion is
  not vacuous, not that it reads the quantity in its name. Instances 2, 3, 7 and the `egress` one
  in `G4-assertions-that-do-not-read-their-own-quantity.md` all bite here and are still misaimed.
* This worktree is based on `e4f4e9a`, one commit behind `main` at `bc39aa1`. That commit touches
  `ORCHESTRATOR.md` and `planning/features-to-triage/G4-gapfix-3.md` only, so it does not overlap
  the three files changed here.
