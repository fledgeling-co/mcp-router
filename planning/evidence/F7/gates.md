# F7 — gates, with the command that produced each line

Tree: `ai/n3` at the commit this file is committed in, base `08a24ed`. Machine: load 400-700 across
16 cores with eight runners live, which is where two of the notes below come from.

| gate | command | exit | what it said |
|---|---|---|---|
| whole lint | `make lint` | **1** | one member failing, and it fails identically on the base — see below |
| swiftformat | `swiftformat --lint . --config .swiftformat` | 0 | `0/754 files require formatting` |
| swiftlint | `swiftlint lint --strict --config .swiftlint.yml` | 0 | `Found 0 violations, 0 serious in 740 files` |
| no-raw-design-values | `./scripts/lint/no-raw-design-values.sh` | 0 | `108 files under the geometry and boundary rules · clean` |
| no-wire-codable | `./scripts/lint/no-wire-codable.sh` | 0 | clean over six directories, `2 exemption(s) recorded` |
| no-harness-config-writes | `./scripts/lint/no-harness-config-writes.sh` | 0 | `458 file(s) examined … none writes one` |
| worktree-preflight-selftest | `./scripts/worktree-preflight-selftest.sh` | 0 | `11 held, 0 did not` |
| warden selftest | `./scripts/warden/selftest.sh` | 0 | `7 held, 0 did not` |
| reader-accounting | `python3 planning/reader-accounting.py` | 0 | — this item adds no Python reader |
| null-run-gate | `python3 planning/null-run-gate.py` | 0 | `armed` |
| py39-annotation-gate | `python3 planning/py39-annotation-gate.py` | 0 | `78 tracked .py files … control: HELD` |
| citation-gate | `python3 planning/citation-gate.py` | 0 | `control 0 · blocking 0 · ratchet 0`; BARE 694 against baseline 1291 |
| sweep-control-gate | `python3 planning/sweep-control-gate.py` | 0 | `109 discovered sweep(s), all disposed; 33 declared control(s) run and passing` |
| scope-invariance-gate | `python3 planning/scope-invariance-gate.py --quiet` | 0 | `70 tracked .py files, 0 unanchored enumerations` |
| instrument-census | `python3 planning/instrument-census.py` | 0 | `464 instruments` |
| runnable-path-gate | `python3 planning/runnable-path-gate.py` | 0 | `no runnable tracked file names a /Users/ or /Volumes/ path` |
| hooks install --gate | `bash planning/hooks/install.sh --gate` | 0 | `pre-push in sync` |
| registry-drop-gate | `python3 planning/registry-drop-gate.py` | 0 | `no id dropped — registry holds 267`; high-water raised 262 → 267 in this commit |
| evidence-citation-gate | `python3 planning/evidence-citation-gate.py` | 0 | every claimed evidence path exists |
| foreign-path-gate | `python3 planning/foreign-path-gate.py --quiet` | 0 | PASS |
| target-resolution-gate | `python3 planning/target-resolution-gate.py --quiet` | 0 | `floor[ids]: 0 … exit: 0` |
| capture-manifest | `python3 planning/test-campaign/bin/capture-manifest.py` | 0 | `74 row(s)` |
| raster-claim-gate | `python3 planning/test-campaign/bin/raster-claim-gate.py` | 0 | `26 pixel claim(s)` |
| forced-state-assert --control | `python3 planning/test-campaign/bin/forced-state-assert.py --control` | 0 | `planted 38 mutation(s) … every planted defect was seen` |
| effect-class-census --control | `… effect-class-census.py --control` | 0 | `7 of 7 arms as expected` |
| effect-class-census | `… effect-class-census.py` | 0 | `findings: 0` over 515 production files |
| blind-vocabulary-arm | `… blind-vocabulary-arm.py` | 0 | `6 of 6 checks as expected` |
| vocab-differential --control | `… vocab-differential.py --control` | 0 | `14 of 14 arms as expected` |
| vocab-differential | `… vocab-differential.py` | 0 | `findings: 0` |
| pin-class-gate | `python3 planning/pin-class-gate.py` | 0 | `0 carried, 28 compliant` |
| shipped-brief-gate | `python3 planning/shipped-brief-gate.py` | 0 | every terminal brief witnessed |
| **brief-target-gate** | `python3 planning/brief-target-gate.py --quiet` | **1** | `84 undeclared over 84 file(s) against floor 82 — 3 above` |
| carrier-parity-gate | `python3 planning/carrier-parity-gate.py` | 0 | reports the split |
| pool-mutation-gate-selftest | `zsh app/Scripts/pool-mutation-gate-selftest.sh` | 0 | `14 passed, 0 failed, of 14` |
| tests | `make test` | **0** | `2199 tests in 281 suites passed` |
| arming | `python3 planning/test-campaign/bin/arm-f7-analyst.py` | 0 | `12 of 12 arms killed`, over a presence control that ran first |

## The one failing member is inherited, and that is measured rather than asserted

`brief-target-gate` names three briefs, none of them this branch's:

```
planning/features-to-triage/a-security-guard-that-cannot-fail-now-guards-a-live-entry-point.md
planning/features-to-triage/the-carrier-gate-pins-a-landing-to-a-sha-that-keeps-moving.md
planning/features-to-triage/the-ledger-gate-nothing-runs-and-nothing-checks-against-git.md
```

All three are committed on `main` (`1de14a6`, `3f3a31f`, `8303aa1`). Run on a **pristine detached
checkout of the base commit** with nothing of this branch in it:

```
$ git worktree add --detach /tmp/n3-base 08a24ed && cd /tmp/n3-base
$ python3 planning/brief-target-gate.py --quiet
floor: 84 undeclared over 84 file(s) against floor 82 — 3 above, 1 below
exit: 1
```

Byte-identical figures. This branch moves the count by zero.

## `make test` — two runs, and what the first one found

| run | result |
|---|---|
| 1 | 2199 in 281, **2 issues** |
| 2 | 2199 in 281, **1 issue** |
| 3 | 2199 in 281, **passed, exit 0** |

The first issue was this item's own and is fixed: `ShellIntegrationTests` enumerates every file
under `Boards/` against a written list, and `InsightsAnalystPanel.swift` was not in it. That is the
gate working — a new board file that nothing registered.

The second is *"the group's 50ms budget expired and it had still not returned: the cancelled child"*,
`app/Tests/RouterCoreTests/OAuthWireTests.swift:265` at `08a24ed` — one of the three load flakes this
fleet has named. Green
in isolation (`--filter OAuthWireTests`, 18 tests in 5 suites, 3.1s) and green on the third full
run. It also fired on the **baseline** run of `main` taken before any of this branch existed.

Baseline for comparison, measured on this worktree at `08a24ed` before any change:
**2160 tests in 275 suites.** This branch: **2199 in 281** — 39 tests and 6 suites added.

## Three obligations the gates raised at COMMIT, and what each cost

Every one of these went red only once the new files were **tracked**, which is the rule this fleet
already writes down, and each is closed rather than waived.

| gate | what it wanted | what was done |
|---|---|---|
| `carrier-parity-gate` | this landing touched one router and not the other and carried no row | a row in `planning/parity/carriers.tsv` naming the commit, `swift-only`, `divergent-recorded`, with the reason: `src/control.ts` answers the whole `/insights` family 404 by design (`div-m22-insights`), so there is nothing to diff bytes against and two routers being equally silent is not agreement |
| `citation-gate` | three new files each held one bare citation against a baseline of zero | all three framed with anchor **and** tree; the first framing was itself refused as `DANGEROUS` because the quoted anchor spanned two lines and the cited line held only part of it — corrected to an anchor that sits inside the line it names |
| `instrument-census` | four new instruments unrecorded | `--write`; 464 → 469 |

Two more went red on the machine rather than on the branch, and both are the conditions this fleet
has already measured. `sweep-control-gate` reported `scripts/acceptance/acceptance-lanes.sh`'s
control as *did not finish in 120s*; run directly, `acceptance-lanes-selftest.sh` reports
**13 arms, all held**, exit 0. And it reported `carrier-parity-selftest` failing its `clean` arm —
which was **not** the machine: it was the missing carrier row above, and it cleared the moment the
row landed (`8 arms, all as declared, and the tracked ledger is byte-identical`).

## Two environment facts, so a verifier does not diagnose them as a branch

1. **`swift build` needs `--disable-sandbox` here.** SwiftPM's own sandbox refuses to create build
   outputs on `/Volumes/LLMs`, surfacing as `Operation not permitted` on a randomly chosen `.o` —
   a different file each run, which reads exactly like a corrupt tree. `make test` works once a
   build exists. The Makefile is unchanged.
2. **Build under the physical spelling.** `scripts/worktree-preflight.sh` refuses a module cache of
   unknown provenance, and a `swift build` run from the logical `/Users/…/.worktrees/N3` path fills
   it under the other spelling. The recipe that works: `rm -rf app/.build`, `mkdir -p app/.build`,
   run the preflight so it stamps the empty cache, then build with `PWD` pinned to the physical
   path — which is what `make` does for itself.
