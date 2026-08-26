# M33 acceptance — the report line, and the branch sweep

M33's target (`MCPRouterApp` over `app/MCPRouter/` in `app/Package.swift`) was armed and merged
before this branch. Two clauses of the brief were left open and are what this records:

1. `make test`'s output must **say which build description it compiled**, and the brief is
   explicit that a second lane passing silently over a directory it does not read leaves the
   reader where they started — so the line must be unable to go missing while the target passes.
2. A sweep for branches whose green `swift test` covered nothing under `app/MCPRouter/`,
   **reported with a denominator**.

Every number below was read from a run, and every check was watched going red before it was
believed.

---

## 1. What `make test` now prints

Three blocks run after the suite: the report's own poison arms, then the report, then a `grep`
over what the report actually emitted.

```
executed 1980 tests
  control  clean inputs must be OK                                                bit
  poison   app target dropped from Package.swift -> uncovered-path                bit
  poison   declared app target with no object -> uncompiled-target                bit
  poison   object older than its source -> stale-object                           bit
  poison   iOS lanes removed from `make all` -> uncovered-path                    bit
  poison   declared target absent from this build's plan -> unbuilt-target        bit
  poison   two sources sharing a basename -> basename-collision                   bit
  null     empty describe JSON -> refuses rather than reports clean               bit
  null     project.yml with no source paths -> refuses rather than reports clean  bit
  null     Makefile with no `all:` -> refuses rather than reports clean           bit
selftest: 10/10 arms bit
build-description: app/Package.swift (SwiftPM, package `MCPRouterKit`) — this is the description `make test` compiled
  objects read from app/.build/arm64-apple-macosx/debug

  compiled by this lane:
    ControlDiff          executable  Sources/ControlDiff        1/1 sources
    ControlProbe         executable  Sources/ControlProbe       1/1 sources
    MCPRouterApp         executable  MCPRouter                  1/1 sources
    MCPRouterCLI         executable  Sources/MCPRouterCLI       9/9 sources
    MCPRouterKit         library     Sources/MCPRouterKit       112/112 sources
    MCPRouterKitTests    test        Tests/MCPRouterKitTests    84/84 sources
    MCPRouterUI          library     Sources/MCPRouterUI        142/142 sources
    MCPRouterUITests     test        Tests/MCPRouterUITests     72/72 sources
    MeasureDump          executable  Sources/MeasureDump        1/1 sources
    RouterCore           library     Sources/RouterCore         130/130 sources
    RouterCoreTests      test        Tests/RouterCoreTests      93/93 sources

  declared by app/project.yml and NOT compiled by this lane:
    MCPRouterIOS         MCPRouterIOS               -> covered by `make test-ios`, `make test-ios-glass`
    MCPRouterIOSTests    MCPRouterIOSTests          -> covered by `make test-ios`, `make test-ios-glass`
    MCPRouterIOSUITests  MCPRouterIOSUITests        -> covered by `make test-ios`, `make test-ios-glass`

  read app/project.yml: kept 4 of 198 lines for `project.yml target source paths`; dropped 135
  inside a target but not a `- path:` entry, 53 outside the targets block, 4 a target name, 1 the
  `targets:` key itself, 1 a top-level key ending the targets block

build-description-verdict: OK — 1 project.yml path(s) compiled by this lane, 3 deferred to make test-ios + make test-ios-glass, 0 covered by nothing
```

**The brief's premise turned out to be understated.** `project.yml` declares **four** source paths,
not one. Arming `MCPRouterApp` closed `MCPRouter/`; `MCPRouterIOS/`, `MCPRouterIOSTests/` and
`MCPRouterIOSUITests/` are in the same position and are *not* compiled by this lane. They are not a
defect, because `make all` runs `test-ios` and `test-ios-glass` over them — but a reader of a green
`make test` had no way to know that, which is the thing the brief asked for. The report says it,
and the excuse is checked rather than asserted: if the iOS lanes ever leave `make all`, those three
paths become `COVERED BY NOTHING` and the gate goes red.

## 2. Proof the line cannot go missing while the target passes

A two-way planted control on `make test` itself, not on the script in isolation.
Baseline `scripts/build-description-report.py` sha256 `bfa8023b5f8d`.

| arm | plant | script alone | `make test` |
|---|---|---|---|
| A | `MARKER` renamed so the report exits **0** and emits no `build-description: ` line | exit **0** | **exit 2** — `error: this target compiled a tree and did not say which description it compiled.` |
| B | report forced to exit non-zero (tests `pipefail` through `tee`) | exit 1 | **exit 2** |
| — | **restored**, sha `bfa8023b5f8d` (identical) | exit 0 | **exit 0**, both lines present |

Arm A is the one that matters: the script is *passing* and the target still fails, because absence
of the line is itself the failure. `.SHELLFLAGS := -eu -o pipefail -c` is set at the top of the
Makefile and again in the block, so arm B's failure is carried through the pipe rather than lost.

The `grep` is `'^build-description: '` with the trailing space, so the `build-description-verdict:`
line cannot satisfy it — a **red** report cannot stand in for the presence of the header.

## 3. Proof the gate catches M33 itself, on the real manifest

| step | `app/Package.swift` sha256 | gate |
|---|---|---|
| before | `250fc6929837` | exit 0 |
| `MCPRouterApp` target block removed | `e3f7e7f15946` | **exit 1** — `[uncovered-path] app/project.yml:43 declares 'MCPRouter' for target 'MCPRouter', and no SwiftPM target declares this path … this is M33 recurring.` |
| restored | `250fc6929837` (identical, `git status` clean) | exit 0 |

## 4. A false green an out-of-family review found, and closed

Sent to **gemini-3.7-flash-high** via `agy --new-project` (reply confirmed on-subject: it argued
about `Package.swift`, `app/MCPRouter/` and the object oracle by name). It found a way through the
first cut that is M33 rebuilt one level up:

> A target still **declared** but which the lane has stopped building keeps every object from the
> last build, and a source nobody edits keeps an object **newer than itself** forever. Objects read
> fresh, mtimes read clean, and the gate reports a directory compiled that this build never touched.

That is the shape the review lane warned about when the target was armed. Closed by requiring the
**build plan** (`.build/<config>.yaml`, regenerated per build) as well as the object: objects say a
compile once happened, the plan says *this* build asked for it. New finding `unbuilt-target`, armed
in the selftest.

Two smaller ones from the same review, both fixed: the build root is now resolved with
`swift build --show-bin-path` rather than globbing `.build/*/<config>` and letting sort order pick
between a Rosetta and a native tree; and a whole-module build (one object per module, not per
source) is **refused** rather than reported as nothing-compiled.

**One recommendation rejected, with the reason.** Gemini proposed replacing the object oracle with a
static manifest-parity diff between the two descriptions. It is strictly better at catching drift
and strictly unable to catch a declared target the lane never builds — the half this item was armed
against. Both are kept.

## 5. Known limits, stated rather than implied

- The `unbuilt-target` arm is proved on **fixtures**, not on the live tree: producing a
  declared-but-unbuilt target naturally would mean changing SwiftPM's behaviour. `uncovered-path`
  **is** proved live (§3).
- The selftest proves the classifier's logic can go red. It does **not** prove the harvesting is
  correct — that `swift package describe` was parsed right, or that the triple resolved is this
  build's. §3's live control is what covers the harvesting for the one finding it exercises.
- The gate reads `debug`. Under `release` or any whole-module build it refuses (exit 2) rather than
  reporting.
- `basename-collision` has no instance in this package today (0 collisions across all 11 targets);
  it is a guard against the lookup becoming quietly wrong, not a live finding.

---

# M33 branch sweep — frame: `main` at `03c34c3`, 2026-08-26T21:21:44+10:00

Population: every local branch ref plus every two-parent merge on `main`, deduplicated by tip sha.
`affected` = the unit changed a file under `app/MCPRouter/` while `app/Package.swift` at its tip declared no target rooted there, so its `swift test` compiled none of what it changed.

| unit | tip | origin | .swift under app/MCPRouter/ | resources | Package.swift armed | verdict |
| --- | --- | --- | --- | --- | --- | --- |
| `F1` | `54632ff` | merge | 1 (MCPRouterApp.swift) | 10 | **no** | **affected** |
| `F2` | `aa89293` | merge | 1 (MCPRouterApp.swift) | 0 | **no** | **affected** |
| `M1` | `800abaa` | merge | 1 (MCPRouterApp.swift) | 0 | **no** | **affected** |
| `M8` | `ad35d45` | merge | 1 (MCPRouterApp.swift) | 0 | **no** | **affected** |
| `ai/i6` | `25a7fc9` | merge | 1 (MCPRouterApp.swift) | 0 | **no** | **affected** |
| `ai/m15` | `554a473` | merge | 1 (MCPRouterApp.swift) | 0 | **no** | **affected** |
| `ai/m20` | `4c0ea42` | merge | 1 (MCPRouterApp.swift) | 0 | **no** | **affected** |

**examined=100 affected=7 covered=0 n/a=93**

93 of the 100 changed no .swift file under `app/MCPRouter/` and are `n/a` rather than `clean`: they made no coverage claim about it either way. The denominator that matters for the defect is the 7 that did.

### What the sweep corrected in the brief's framing

**M18 does not reproduce.** The brief names M18 and M20 as the known cases. `ai/m18`'s own range
(`2c5b6ad..72873b6`, via merge `4391f86`) changes **no file at all** under `app/MCPRouter/`, so
whatever explains M18's recurrence, it is not this directory going uncompiled. Recorded as a
correction rather than forced into the affected set. **M20 does reproduce** (`ai/m20`, `4c0ea42`).

**The denominator survived two bugs that would have distorted it**, both found by checking the
number rather than accepting it:

- *Backflow merges.* 56 of the 147 two-parent merges on `main` are `Merge main into ai/xxx`
  (25 spelled that way, 31 as `Merge branch 'main' into ...`). Their second parent is main's own
  tip, so leaving them in examined **main as though it were a branch** and attributed its files to
  it a second time — inflating `affected` from 7 to 9. Excluded, with the two that reached the
  affected set named in the code (`2c5b6ad`, `adfa923`).
- *Merged refs collapsing.* For a branch that is merged but whose ref still exists,
  `merge-base(main, tip)` is the tip itself, so its range is empty and it reports as having touched
  nothing whatever it did. `ai/m18` is exactly that shape — **the collapse would have silently
  answered the question the sweep was asked**. Merged refs now resolve through the merge that first
  contains them.

Accounting: 147 two-parent merges − 56 backflow = 91 branch tips, + 9 live refs not among them =
**100**.

### Proof the sweep can say `covered`

The live census reports `covered=0`, so that verdict had never been observed. A branch was planted
on top of `ai/m33` (whose `Package.swift` **is** armed) carrying one commit touching
`MCPRouterApp.swift`, built with plumbing so no working tree was disturbed:

```
| `tmp/m33-covered-control` | `11ded16` | ref | 1 (MCPRouterApp.swift) | 0 | yes | **covered** |
**examined=101 affected=7 covered=1 n/a=93**
```

The seven stayed `affected`. Deleted, the census returned to `examined=100 affected=7 covered=0`
with the source blob byte-identical (sha256 `3ae480004c9b` both ends). `--selftest` covers the
same four verdicts hermetically, 7/7 arms.

### Resources are not counted as a coverage failure

`Package.swift` excludes `Info.plist`, the entitlements and `Assets.xcassets` from the app target,
so a branch that only changed an app icon made no claim this lane could have checked before the fix
or after it. On this history the split changes no verdict — `F1` is the only unit with resources
under the directory (10 icon files) and it also changed `MCPRouterApp.swift`, so it is affected on
the source rather than on the icons.

---

## Gates

| gate | exit | note |
|---|---|---|
| `make test` | **0** | 1980 tests in 252 suites; report present |
| `scripts/build-description-report.py --selftest` | **0** | 10/10 arms |
| `planning/m33-branch-sweep.py --selftest` | **0** | 7/7 arms |
| `planning/reader-accounting.py` | **0** | went **red** on this branch and was fixed, not declared past: the three new readers account for their drops with `input_accounting.Tally`; `accounts` 4 → 6, `unaccounted` 0 |
| `planning/null-run-gate.py` | 0 | unchanged |
| `planning/citation-gate.py` | 1 | **inherited** — `blocking 0`, ratchet only, 3 files above baseline and all three are M29's |
