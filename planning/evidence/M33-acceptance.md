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
| `MCPRouterApp` target block removed | `e3f7e7f15946` | **exit 1**, citing anchor `- path: MCPRouter`, `app/project.yml:43` at `570910a` — *"[uncovered-path] … declares 'MCPRouter' for target 'MCPRouter', and no SwiftPM target declares this path … this is M33 recurring."* |
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
| `planning/citation-gate.py` | 1 | **partly inherited, and this row was wrong.** See *The row that certified over something it had not read* below. Rebased onto `main` today: `exit: control 0 · blocking 0 · ratchet 1`, `BARE 1332 over N5 1493 against baseline 1291 — 9 file(s) above`, and this file is not among the nine. |

**Both of this branch's new scripts are now registered sweeps.** `G8`'s
`planning/sweep-control-gate.py` reached `main` while this was in flight; it discovers new
undisposed sweeps and blocks on them. `planning/m33-branch-sweep.py` (V2,V3,V4) and
`scripts/build-description-report.py` (V2,V3) are both sweeps by its readers, and unregistered they
took that gate from `main`'s 5 UNDISPOSED / 6 FINDINGS to 7 / 8. Both carry a real `--selftest`
control, so both are registered in `planning/sweep-controls.json` as `disposition: control` with
the command that proves it — not `grandfathered`, which is a backlog entry rather than a pass. The
gate now reads 5 / 6 on this branch, identical to `main`.

Armed, because a registry row that has never been shown to redden is a claim rather than a check.
Inverting one arm of the branch sweep's guard — `ARMED.search('path: "MCPRouterIOS"') is None`
becomes `is not None`, so the regex is asserted to match the thing it exists to exclude:

```
  FAIL  planning/m33-branch-sweep.py           control exited 1 — it said: selftest: 6/7 arms bit
FINDINGS sweep-control: 7
```

Restored byte-identically, sha256 `829ee2a6287dedb261bce31d7d4413c74f61b215655f5c41e83ee76db8398f30`
before and after, and the gate returns to 5 / 6.

**On the over-baseline figure this item has been quoted against.** The number circulated through
this session's briefs was **10 files / BARE 1341**. It is a *working-tree* reading. Measured both
ways at the same `main` commit `bf8f58d` — once in the main checkout, which carries 25 uncommitted
paths, and once in a detached checkout of the same commit, which carries none:

```
$ python3 planning/citation-gate.py   # in the main checkout, working tree dirty
ratchet: BARE 1341 over N5 1501 against baseline 1291 — 10 file(s) above, 2 below

$ git checkout --detach main && python3 planning/citation-gate.py   # same commit, clean
ratchet: BARE 1332 over N5 1490 against baseline 1291 — 9 file(s) above, 2 below

$ diff <clean list> <dirty list>
>   planning/test-campaign/RUN-2026-08-20.md  10, baseline 1
```

One file and nine bare citations, and the file is uncommitted. So **9 / 1332** is the repository's
figure and **10 / 1341** is one checkout's, which is why this record quotes the first. It is
written down because two separate corrections in this run turned out to be the same mistake made
twice: a gate read against a working tree and reported as a property of the branch.

## The row that certified over something it had not read

The gate row above used to read *"**inherited** — `blocking 0`, ratchet only, 3 files above
baseline and all three are M29's"*. Every clause of it was false at `b5f2227`, the commit that
wrote it, and the way it was false is this item's own subject: a lane reporting clean over
something it did not look at. That tree is measured below rather than described, because a figure
asserted against a tree nobody names is the same defect at reduced scale.

**Re-derived, and the derivation is printed rather than described.** An earlier draft of this
section named a command and asserted corrected numbers beside it, which is the same defect one
layer out — an out-of-family reviewer called it *"restates post-fix numbers against a pre-fix
tree"* and was right. So here is the output. Run in this worktree at `141394c`, whose base is `main`
at `bbe8df1`:

```
$ python3 planning/citation-gate.py | grep -E '^exit:|^ratchet: [0-9]+ file'
ratchet: 10 file(s) hold more bare citations than the baseline allows:
exit: control 0 · blocking 1 · ratchet 1

$ python3 planning/citation-gate.py | sed -n '/^ratchet: [0-9]* file/,/A bare citation/p'
ratchet: 10 file(s) hold more bare citations than the baseline allows:
  ORCHESTRATOR.md  69, baseline 68
  planning/evidence/M29-decisions-grok.md  1, baseline 0
  planning/goals/tests-reader-control.sh  1, baseline 0
  planning/plans/plan-G6.md  1, baseline 0
  planning/plans/plan-M29.md  23, baseline 0
  planning/progress/G6.md  3, baseline 0
  planning/specs/spec-M29.md  6, baseline 0
  planning/tailings-2/crossref.json  3, baseline 0
  planning/tailings-2/worklist.json  4, baseline 0
  planning/verification/G6-shared-ledger-withdrawals.py  1, baseline 0
  A bare citation is unfalsifiable; carry anchor and tree.
```

`planning/evidence/M33-acceptance.md` is not in that list. It was, before the `:94` fix below.

**The ten are `main`'s own**, and that is measured rather than attributed. `bbe8df1` is the base
this worktree sits on; with none of M33's files in the tree it returns the same ten files:

```
$ git checkout --detach bbe8df1 && python3 planning/citation-gate.py \
    | sed -n '/^ratchet: [0-9]* file/,/A bare citation/p'
ratchet: 10 file(s) hold more bare citations than the baseline allows:
  ORCHESTRATOR.md  69, baseline 68
  planning/evidence/M29-decisions-grok.md  1, baseline 0
  planning/goals/tests-reader-control.sh  1, baseline 0
  planning/plans/plan-G6.md  1, baseline 0
  planning/plans/plan-M29.md  23, baseline 0
  planning/progress/G6.md  3, baseline 0
  planning/specs/spec-M29.md  6, baseline 0
  planning/tailings-2/crossref.json  3, baseline 0
  planning/tailings-2/worklist.json  4, baseline 0
  planning/verification/G6-shared-ledger-withdrawals.py  1, baseline 0
  A bare citation is unfalsifiable; carry anchor and tree.
```

The tenth — `planning/goals/tests-reader-control.sh` — is `main`'s own too, added at `9c51170`
after this section was first written and repaired later at `ea39b46`, which is an ancestor of
`main` today but **not** of `bbe8df1`. So the row moved twice under this section, which is the
argument for printing the list rather than the count: a count is what the original row was. **Nine**
is the same reading one commit earlier, at `b151f14`:

```
$ git checkout --detach 9c51170^   # b151f14
$ python3 planning/citation-gate.py | sed -n '/^ratchet: [0-9]* file/,/A bare citation/p'
ratchet: 9 file(s) hold more bare citations than the baseline allows:
  ORCHESTRATOR.md  69, baseline 68
  planning/evidence/M29-decisions-grok.md  1, baseline 0
  planning/plans/plan-G6.md  1, baseline 0
  planning/plans/plan-M29.md  23, baseline 0
  planning/progress/G6.md  3, baseline 0
  planning/specs/spec-M29.md  6, baseline 0
  planning/tailings-2/crossref.json  3, baseline 0
  planning/tailings-2/worklist.json  4, baseline 0
  planning/verification/G6-shared-ledger-withdrawals.py  1, baseline 0
  A bare citation is unfalsifiable; carry anchor and tree.
```

| clause | what the gate actually says at `141394c` |
|---|---|
| `blocking 0` | **`blocking 1`** — the `exit:` line's third field, not a file count. Anchor "exits 0 and silent on a fault", `planning/features-to-triage/LEDGER.md:124` at `bbe8df1`, cites this file's `:214` at `b5f2227` with an anchor whose pipes are backslash-escaped, because the citing row is itself a markdown table row. The cited line's pipes are not escaped, so the anchor cannot match and the gate classes it `ABSENT` — a stated frame that does not hold — and marks it `DANGEROUS`, because the line it landed on reads perfectly well. |
| `ratchet only` | Not only. The `exit:` line reads `blocking 1 · ratchet 1`, and both those 1s are exit-field flags rather than counts. Blocking is the class that means a *false* claim; the ratchet class means an unfalsifiable one. |
| `3 files above baseline` | **10** at `141394c` and at `bbe8df1`; **9** at `b151f14`, before `main` added its own; **4** at `b5f2227`, the commit that wrote this row. All four readings are fenced — the first two and the third above, the fourth below. Three is the count of the M29 files alone, and of nothing else. |
| `all three are M29's` | Three of the ten are M29's — `planning/evidence/M29-decisions-grok.md`, `planning/plans/plan-M29.md`, `planning/specs/spec-M29.md`. The other seven are listed above and none is M29's. **And at the tree this record was written, one of them was `planning/evidence/M33-acceptance.md` — this file.** It carried one bare citation at `:94`. So the row certified that every file above baseline belonged to another item, while the file making the certification was one of them. |

**The fourth reading — 4 at `b5f2227`, the tree that made the claim.** The row above says three
files are above baseline and all three are M29's. Here is what the gate returned at the commit that
wrote it:

```
$ git worktree add --detach /tmp/m33-claimtree b5f2227
$ python3 planning/citation-gate.py | sed -n '/^ratchet: [0-9]* file/,/A bare citation/p'
ratchet: 4 file(s) hold more bare citations than the baseline allows:
  planning/evidence/M29-decisions-grok.md  1, baseline 0
  planning/evidence/M33-acceptance.md  1, baseline 0
  planning/plans/plan-M29.md  23, baseline 0
  planning/specs/spec-M29.md  6, baseline 0
  A bare citation is unfalsifiable; carry anchor and tree.
```

Four, not three; and the second line of that list is this file. The clause below about the
certifying file being one of the certified is read off that output rather than asserted beside it.

**One caveat on reproducing it.** `b5f2227` is dangling — the rebase onto `bbe8df1` rewrote it, and
`git name-rev` answers `undefined`. The object is in this repository, so the checkout above works
here; a clone that never received it cannot run this fence at all. The same caveat governs the
`ABSENT` finding below, and for the same reason.

**The bare citation at `:94` is fixed rather than absorbed.** It now carries anchor `- path:
MCPRouter` and the tree `570910a`, per `planning/practices/CITATIONS.md` — *"a citation must resolve
where it is **read**, not merely where it was written."* The ratchet baseline in
`planning/citation-ratchet.json` is untouched: the rule is that counts may only fall, and absorbing
debt is an owner decision.

**`blocking 1` is not this branch's to close, and correcting `:214` does not move it.** An earlier
draft of this paragraph said that correcting the row moved the text the LEDGER points at. It does
not: the LEDGER cites `:214` **at `b5f2227`**, a frozen blob, and editing this file at `HEAD` leaves
that blob exactly where it is. The citation was already `ABSENT` before this gap-fix and is
`ABSENT` after it, for the same reason both times — escaped pipes in the anchor against an
unescaped cited line. The one fix available from this branch is to unescape them in
`planning/features-to-triage/LEDGER.md`, which this runner may not write, or to teach
`citation-gate.py` to unescape `\|` when the citing line is a table row — and that second one
reclassifies every table-row citation in the corpus, which is an owner's call and not a side effect
of this item.

**Why this section's own anchors are delimited with double quotes, and not with backticks.** Two
of the citations this section added were classed `TREE_ONLY` rather than anchored on their first
run: the anchor text contained nested backticks, which defeat the anchor parser, so the gate read a
tree and no anchor. `planning/practices/CITATIONS.md` says to delimit with double quotes when the
anchor itself contains backticks, so the LEDGER anchor above reads `"exits 0 and silent on a
fault"`. Without this paragraph the change looks like a style preference; it is a parser limit, and
a reader who copies the backtick form back in will silently lose the anchor while the citation
still appears to carry one. `TREE_ONLY` does not block — which is exactly why it needed writing
down rather than being left to the commit message, where it was the only place it lived.

**Two things about that blocking row are worth stating precisely, because both were nearly claimed
wrongly.**

* It is **latent on `main`**, and the mechanism is checked rather than assumed:
  `git cat-file -e main:planning/evidence/M33-acceptance.md` fails and `git ls-tree` is empty for
  that path at `bbe8df1`, so the cited path is not resolvable there, the citation drops out of the
  gate's N5 denominator, and `main` reads `blocking 0`. It becomes checkable the moment this branch
  lands.
* **`b5f2227` is dangling.** `git name-rev b5f2227` answers `undefined`: it was this branch's tip
  before the rebases and is an ancestor of nothing now. The object survives in this repository, so
  the gate resolves it and blocks. In a clone that never received it, the same citation classes
  `NOTREE`, which does not block. So whether merging this branch turns the finding red depends on
  the object database rather than on the tree — which is another way of saying the LEDGER row needs
  rewriting whatever else happens.

---

## 4. Gap-fix: the staleness oracle was measuring a quantity SwiftPM does not maintain

The transcript in section 1 above is **superseded from `cb18ebb` onward**, and should be read as
what the gate printed at `b394eac`. The arm it lists as
"object older than its source -> stale-object", `planning/evidence/M33-acceptance.md:27` at
`b394eac`, no longer exists, because the condition it named is not evidence of anything. The
selftest now runs thirteen arms rather than ten.

### What went wrong

`make test` exited 2 on this branch over `Sources/MCPRouterUI/Controls.swift`, reporting
`MCPRouterUI 141/142 sources <-- NOT COMPILED` and `[stale-object] … The green describes a previous
tree`. The object was not stale. `nm` on
`app/.build/arm64-apple-macosx/debug/MCPRouterUI.build/Controls.swift.o` found 30 `Palette`
symbols — `Palette` being the public struct M31 had just added to that file — so the object was
current in content. What was older was only its mtime.

This is a false alarm rather than a false pass, which is the safer of the two directions and still
wrong: a gate that goes red over a correct tree is a gate that gets switched off.

### The mechanism, measured rather than reasoned

The reading first reached for was the shared `.build`: `.worktrees/M31` compiled that source at
19:21 on 26 Aug, merging M31 to `main` stamped main's *source* at 00:00 on 27 Aug, and the object
is content-current and mtime-older in every other worktree. That reading is true but it is the
special case. The general law is one level down, and a single worktree reproduces it:

* **Append a comment to the source and rebuild.** `swift build` prints
  `[4/8] Compiling MCPRouterUI Controls.swift`, so the compile really happened. Source mtime
  1787781918; object mtime 1787781815, unmoved, and object sha256 `c31902c414343e26`, unchanged.
  The object is left 103 seconds older than the source it perfectly describes.
* **Append a real declaration instead and rebuild.** Object mtime moves to 1787781790 and its
  sha256 changes to `7a24aa4f9233196e`, and `nm` finds the planted symbol.

So an object's mtime tracks changes to the object's **content**, not the occurrence of a compile.
The frontend writes the file only when the bytes differ. Anything that stamps a source without
changing its meaning — a comment, a re-wrap, a `git checkout`, a merge — strands the object in the
past permanently, and no rebuild will move it. The shared-`.build` case is one instance of that
law, and in this repository it is the routine one.

Two further measurements settle that llbuild does not share the gate's opinion. `swift build` run
three times over the reported state compiled nothing on every run — 3.47s, 0.14s, 0.15s, each
ending `Build complete!` with no `Compiling` line — while `Controls.swift.o` sat mtime-older than
its source throughout. llbuild considered the tree up to date and it was right.

### Why the replacement is not another file's mtime

The sibling artifacts of the same frontend job looked like an easy substitute, because two of them
plainly move when the object does not. On the comment-only recompile above, against a source at
1787781918:

| output | mtime after the recompile | moved? |
| --- | --- | --- |
| `Controls.dia` | 1787781919 | yes |
| `Controls.d` | 1787781919 | yes |
| `Controls.swift.o` | 1787781815 | no |
| `Controls.swiftdeps` | 1787781815 | no |

`.swiftdeps` is written only-if-changed exactly as the object is, and nothing in the shape of the
four says which two behave which way — a priori `.swiftdeps` was the *more* plausible compile stamp
of the pair, being the driver's own incremental state. Resting the gate on `.dia` and `.d` would be
resting it on an undocumented accident that a toolchain bump could reverse silently, in the
direction of reading clean.

llbuild's own build database at `app/.build/build.db` would answer the question directly, and was
rejected for a different reason: its per-rule results are a custom binary encoding, and a misparse
would read as clean. That is the one failure mode this file may not have.

### What it asks instead

`probe_remaining_work`, `scripts/build-description-report.py:321` at `cb18ebb`, asks SwiftPM
whether the build that just ran left anything undone, by running the build again and requiring it
to do nothing. A build that compiles nothing is a build with nothing left to compile.

Three details are load-bearing:

* **`--build-tests` rather than a bare `swift build`.** `make test` runs `swift test`, which plans
  test targets as well as products; a bare `swift build` plans only products, and both write the
  same `.build/<config>.yaml`. The probe would therefore replace the build plan this same report
  reads two steps later with a narrower one, and every test source would report as absent from it —
  the instrument breaking its own second layer. Measured: after `swift test list` compiled nothing,
  `swift build --build-tests` also compiled nothing and returned in 0.73s, so
  "so the two are a fixed point", `scripts/build-description-report.py:336` at `cb18ebb`.
* **The probe runs before the plan is read**, because it may rewrite that plan and the plan this
  report describes must be the one in force when it is read.
* **An unrecognised build step counts as work, not as clean.** The step list is a whitelist —
  `"^(?:Write\b|Planning build\b|Copying\b)"`, `scripts/build-description-report.py:315` at
  `cb18ebb` — because a blacklist would let an unrecognised compile step read as clean, which is
  the defect this whole file exists to refuse. Unattributable work raises `build-work-remaining`
  rather than being folded into a source.

The probe repairs what it reports, because SwiftPM has no dry-run flag —
`swift build --help` offers none. That is stated in the docstring rather than hidden:
"The probe repairs what it reports", `scripts/build-description-report.py:338` at `cb18ebb`. The
finding stays true after the repair, because it says the suite ran against a tree that was not the
current one, and the next run is green because it genuinely tested the current tree rather than
because the evidence was tidied away.

### Armed in both directions, and over the case it must not fire on

All three runs were made against `Sources/MCPRouterUI/Controls.swift` at sha256
`8fc9dc6dab09c8fd58b90eef211627cdb8553ce37658d07d34e68a0b00e4cf6d`, which is the committed
content, and the file was restored to that sha and to a clean `git status` afterwards.

| # | state planted | source sha256 (first 16) | gate exit | what it said |
| --- | --- | --- | --- | --- |
| A | a real declaration appended, **no build run** | `12667e73b1bc5508` | **1** | RED, 12 findings; `MCPRouterUI 28/142 <-- NOT COMPILED`, `stale-object` naming the recompiled sources, and the cascade into `MCPRouterApp` and `MCPRouterUITests` |
| B | the same tree, gate run a second time | `12667e73b1bc5508` | **0** | `MCPRouterUI 142/142`, verdict OK |
| C | source `touch`ed — content identical, mtime new — then built once so llbuild settles | `8fc9dc6dab09c8fd` | **0** | `MCPRouterUI 142/142`, verdict OK |

Arm C is the reproduction of the reported defect, and it is the row that matters. After it,
`Controls.swift` had mtime 1787782253 and `Controls.swift.o` had mtime 1787781815 — the object 438
seconds older than its source, sha unchanged at `c31902c414343e26`. The old oracle's comparison
over that same state reads `RED (obj older than source)`; the new gate exits 0. A `touch` is not a
contrivance here: it is precisely what `git checkout` and `git merge` do to a file whose content
they leave alone, which is how the shared `.build` produces this state in the first place.

Arm A also demonstrates that the check still bites where it should, and bites wider than before:
the mtime oracle would have flagged `Controls.swift` alone, while llbuild's answer names every
dependent whose object was built against the previous module — 12 findings across three targets.

### Gates

`make test` exit 0 — `discovered 1985 test ids`, `executed 1985 tests`,
`Test run with 1985 tests in 252 suites passed after 10.533 seconds`, `selftest: 13/13 arms bit`,
`build-description-verdict: OK`. `planning/ledger-reconcile.py` exit 0, reconciled across A–L.
`planning/py39-annotation-gate.py` exit 0, 48 files swept, control held.
`planning/citation-gate.py` exit 1 on the ratchet, **inherited**: `main` reads `BARE 1328` and this
branch reads `BARE 1319` against a baseline of 1291, and the ten files above their baseline are all
inherited. Removing this section's own edit and re-running gives `BARE 1319` unchanged, so this
gap-fix adds no bare citation and the baseline is untouched.
