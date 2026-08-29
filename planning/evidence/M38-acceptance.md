# M38 — acceptance evidence

Branch `ai/n5`, worktree `.worktrees/N5`, base `08a24ed`. Every figure below was produced by the
command named in its row. Verdict lines only: `citation-gate.py` holds a newly tracked file to a
baseline of zero bare `path:line` citations, so committing a raw gate capture turns the next lint
red — the same reason `planning/evidence/R33-acceptance.md` gives.

## Gates

| Gate | Command | Exit | What it read |
|---|---|---|---|
| Swift suite, whole | `make test` | **0** | 2163 tests in 276 suites (baseline `main` 2160 / 275; this branch adds 3 tests in 1 suite) |
| the new witness alone | `swift test --filter ControlApproveCatalogTests` | **0** | 3 tests in 1 suite |
| live-reload lane | `node scripts/e2e-live-reload.mjs` | **0** | **26/26** checks (baseline 24/24; this branch adds 2 arms and 2 controls, and the earlier fixed-window control became quiescence-based) |
| TypeScript build | `npm run build` | **0** | — |
| registry drop | `python3 planning/registry-drop-gate.py` | **0** | 4 registry views against `08a24ed0b`; no id dropped, 262 held |
| brief targets | `python3 planning/brief-target-gate.py --quiet` | **1 — INHERITED** | see below |
| shipped briefs | `python3 planning/shipped-brief-gate.py` | **0** | every terminal brief witnessed by a commit on `main` |
| carrier parity | `python3 planning/carrier-parity-gate.py` | **0** | 6 one-sided landings, 6 dispositioned, 0 findings |
| pool mutation, armed | `zsh app/Scripts/pool-mutation-gate-selftest.sh` | **0** | 14 of 14 cases |
| whole lint | `make lint` | **killed twice by SIGTERM**, see below | swiftlint 0 violations in 725 files |

### `make lint` whole did not finish, and the reason is the machine rather than the tree

Two runs, both killed. The first refused at the `tools` stage on a **module-cache provenance
guard** this item tripped itself: `.worktrees` is a symlink, `swift build` run directly from
`app/` fills the cache under the physical `/Volumes/LLMs/…` spelling while `make` pins `PWD` to
`CURDIR`, and the preflight refuses a cache whose spelling it cannot establish. Recorded rather
than glossed — the fleet's own rule is *build via `scripts/worktree-preflight.sh`*, and running
`swift build` from `app/` for a fast filtered run is what put it there. `rm -rf app/.build` and a
re-preflight cleared it, which is what the refusal itself says to do.

The second run got through swiftlint (**0 violations, 0 serious in 725 files**) and 33 of the 37
members, and was then **`Terminated: 15`** at 50 minutes inside `shipped-brief-gate.py`, with three
other runners' `make lint` alive on the same machine and one of them 30 minutes into a single
selftest. A SIGTERM is not a verdict, so **the four members it had not reached were run
individually** and all four reported: `shipped-brief-gate` 0, `carrier-parity-gate` 0,
`pool-mutation-gate-selftest` 0 (14/14), `brief-target-gate` 1.

**So every member has a verdict and exactly one is red**, and that one is inherited.

### The red member is three briefs this branch does not touch

`brief-target-gate.py` blocks on:

| brief | landed on `main` as |
|---|---|
| `a-security-guard-that-cannot-fail-now-guards-a-live-entry-point.md` | `1de14a6` |
| `the-carrier-gate-pins-a-landing-to-a-sha-that-keeps-moving.md` | `3f3a31f` |
| `the-ledger-gate-nothing-runs-and-nothing-checks-against-git.md` | `8303aa1` |

All three landed on `main` on 2026-08-29 from other branches. **The gate was already exit 1 on this
worktree before this item edited anything** — 84 undeclared against a floor of 82, measured on the
pristine tree. This branch moves it **84 → 83** by declaring its own brief's targets, and adds one
brief which is declared rather than undeclared.

## Red-green — every new assertion watched failing

`scripts/red-green.py`, arms `APP-1`…`APP-5`. Ids outside `M01…M59` on purpose: that file's
mutation namespace collides with this fleet's item ids.

| arm | what it removes | outcome | which tests went red |
|---|---|---|---|
| APP-1 | the promotion never writes the pending tools | **KILLED** | the quarantine arm and the second-approve arm |
| APP-2 | the promotion is written to every entry | **KILLED** | the quarantine arm, on its sibling control |
| APP-3 | R21 undone — the write failure is discarded and 200 answered | **KILLED** | the refused-write arm, at `(result.status → 200) == 500` |
| APP-4 | the no-pending guard dropped | **KILLED** | the second-approve arm |
| APP-5 | the store never notices the file moved | **KILLED** | both catalog arms, at `["held__old", "sibling__steady"]` |

Files restored after every arm and hash-verified: `AuthRoutes.swift` sha256
`f71e08d2…8eef` before and after; `ManifestStore.swift` sha256 `3e5b5786…9b4b` before and after.

**The lane's own arms were proved the same way.** Deleting the `announceTools(deps, …)` call from
`src/control.ts`, rebuilding and re-running took `scripts/e2e-live-reload.mjs` to **23/26**, with
the three approve checks red:

```
FAIL  the attached session is told the approved surface is live — 0 notification(s)
FAIL  and the announcement is the APPROVAL, not the poller reporting an outside rebuild
FAIL  CONTROL: an approve that promoted nothing announces nothing — 1 notification(s), 1 new log line(s)
```

### `APP-3`'s first form measured nothing and reported like a pass

Kept here rather than tidied away, because it is the failure this fleet keeps finding one level up.
The first form kept the catch block's braces balanced with `if false {`, which does not compile. A
hand harness reading the run only for `recorded an issue` lines then reported **SURVIVED** — a
mutation that never ran, filed as a decoration exposed. The registered form compiles and kills, and
it lives in `red-green.py` rather than in a shell script beside it because that file's `COMPILE_RE`
already demotes a non-compiling mutation to `WRONG-TEST`.

## The measurement behind the change

Taken from the lane's own run, with the router's stderr captured:

```
09:13:29.664Z info  live-reload: the tool manifest was rebuilt outside this process -> notified 1/1
09:13:32.666Z info  live-reload: the tool manifest was rebuilt outside this process -> notified 1/1
09:13:36.863Z info  live-reload: approved "first"'s new tool surface -> notified 1/1
        (it arrived 11ms after the approval)
```

The first two lines are the three-second poller, and they are why the missing announcement read as
working. The third is the route saying what it did.

**The notification count is not the oracle**, and the lane says so in its own comment: the poller
delivers one either way, so `NOTICES.length >= 1` passes with and without the change. The log line
is the discriminator. The count and the latency are printed as corroboration.

## One known load flake, re-run in isolation

The first `make test` run failed once at
`ChildPathSpawnTests` — *upstream "seeing" did not initialize within 8000ms*, an R6 spawn timeout
under a machine carrying eight runners. Re-run alone: **2 tests in 1 suite passed in 4.2s**. It
touches nothing this branch changed. A fourth member of the family `ORCHESTRATOR.md` already names.

## What is not measured here

- **The Swift router's half of live-reload**, which does not exist: R29 shipped the family as
  TypeScript-only with the Swift router answering 404. Oracle lines 1–4 are TypeScript-only.
- **The Mac sheet**, which is M8's and M29's and is cited as built rather than re-measured
  (spec §1). Nothing in this branch touches `MCPRouterUI`.
- **`make mock-fidelity`**, unchanged and not run: no UI surface moved.
