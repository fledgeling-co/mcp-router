# P4 — acceptance evidence

Item: **P4 — derive the manifest rows, and fix the directory-dependent normaliser** (`D-n`, `D-o`).
Branch `ai/p4`, worktree `.worktrees/P4`. Spec `planning/specs/spec-P4.md`, plan
`planning/plans/plan-P4.md`.

There is **no UI in this item**, so no screen was driven and no app was launched. The acceptance
surface is the parity harness itself, and the whole of it is re-runnable:
`scripts/acceptance/parity-manifest-selftest.sh`.

The diff is **four shell files and nothing else** — verified, not asserted:
`git diff --name-only main..HEAD` returns only `scripts/acceptance/parity-{fixture,gate,manifest-check,manifest-selftest}.sh`.

---

## 1. The headline: what a row deletion used to do

Four rows deleted one at a time, each measured against the **pre-P4** check taken from `main`, in a
scratch tree:

| row deleted | verdict | pre-P4 check | census reported | with P4 |
|---|---|---|---|---|
| `cli-import` | proven | **exit 0** | **82 rows** | exit 1 |
| `mcp-health` | proven | **exit 0** | **82 rows** | exit 1 |
| `div-r1-d3-control` | proven | **exit 0** | **82 rows** | exit 1 |
| `control-auth-post-http` | **blocked** | **exit 0** | **82 rows** | exit 1 |

Each silently took the denominator from 83 to 82 while the check reported a clean manifest. The
last one is the sharpest: it is **blocked**, so its deletion leaves the numerator untouched and
moves 73/83 to 73/82 — the coverage figure goes **up**. And it sits inside `control`, the group
already reconciled against source, because it deliberately shares the subject
`POST /servers/:name/auth` with `control-auth-post` and the reconciliation `sort -u`'s subjects.
Found by the out-of-family spec review; reproduced here before it was believed.

## 2. Row deletion: 39 of 83 protected before, 83 of 83 after

`parity-manifest-check.sh` can only derive a group that some source file exposes. `divergence`,
`install`, `pool`, `state` and `log` name declarations and scenarios, so 28 rows sat outside it.
Two additions close that, and a third measurement says how far they get:

1. **`parity-gate.sh` now reports an orphan result.** The lanes already record which ids they
   tested, so a result whose id the manifest does not carry means the row was deleted while the
   work that proves it kept running. No list to maintain — it is the same reconciliation read in
   the other direction. Reaches every row a lane speaks for.
2. **The census is pinned** — `# rows: 83`, a comment in `surface.tsv`, checked by
   `manifest-check`. This reaches what neither of the above can: a **blocked** row in an underivable
   group, which no lane speaks for and no file exposes.

Classified over all 83 rows. A row in a derived group counts as protected only if its subject is
**unique** in that group — a shared subject is exactly how `control-auth-post-http` slipped through:

| protected by | rows |
|---|---|
| source derivation (`control` · `fixture` · `cli` · `mcp`, unique subject) | 53 |
| the lane-orphan check (any row a lane speaks for) | 25 |
| a citation in another row's note | 1 — `control-auth-post-http` |
| the pinned census (blocked, underivable, uncited) | 4 |
| **nothing** | **0** |

The four the pin exists for, each measured red with the pin naming the reason
(*"the manifest holds 82 rows and pins itself at 83"*):

```
divergence  div-r1-d3                owner D-k
install     install-claude-json      owner D-k
install     install-import-servers   owner D-k
install     install-rollback         owner R4-C
```

`div-r1-d3` came from the Phase D critic, which noticed its citation runs only one way: its note
names `div-r1-d3-control`, and nothing names it back.

**The pin gates addition as well as deletion, and that is deliberate.** A duplicate blocked twin
sharing an existing subject satisfies every derivation above — `cli-auth-2` with subject `auth`
exited 0 at 84 rows before, and now reports *"holds 84 rows and pins itself at 83"*.

> **Consequence for other items, flagged rather than buried.** Any item that adds or removes a
> parity row must move the pin in the same change, or `manifest-check` exits 1 with a message
> saying so. That is a new step in a shared file. It is proposed on the grounds that the
> denominator **is** R4-C's cutover target — P1 moved it 82 → 83 and the ledger had to record
> that as a fleet-level event — so moving it should be a line someone wrote rather than a side
> effect. **The orchestrator can drop this one hunk without touching anything else in P4**; the
> other 79 rows stay protected by the derivations and the orphan check.

The orphan check proven red-green by hand, since it lives in the gate and the selftests run no lanes:

```
# RED  — a manifest with pool-p1 removed, pool lane still reporting it
PARITY_MANIFEST=<trimmed> PARITY_LANES=pool bash scripts/acceptance/parity-gate.sh
  -> "a lane reported a result for a row this manifest does not carry:  pool  pool-p1"
  -> "1 row(s) were tested by a lane and are not in the manifest. Exit 1."
# GREEN — same lane, untrimmed manifest: the orphan block is absent
```

## 3. The two selftests, both committed and both wired

`make parity-selftest`, and in `make all`. Hermetic and offline — they copy the tree into scratch
directories and run no lane, no router and no build. They exist because
`parity-lane-selftest.sh` already made the argument: *a paragraph in an evidence file is re-run by
nothing.*

**`parity-manifest-selftest.sh` — 36 cases, exit 0.** One green baseline and 35 reds, grouped as
cli verbs, mcp surface, cited row ids, the pinned census, and the dispatch shapes that used to be
silent. **Every case asserts the message, not only the exit code** — a mutation that reddens
through some other check proves nothing about the one it was aimed at, and two cases were caught
doing exactly that and re-aimed rather than swapped:

- *a verb dispatched outside the switch* was asserting the pre-rewrite wording.
- *two handler registrations on one line* reddened through the SDK lookup (`answers "ping"`) rather
  than through the handler count it exists for. Re-aimed at a registration whose **symbol** the
  regex cannot read, which is the only shape that count catches.

**`parity-normalise-selftest.sh` — 14 cases, exit 0.** It lifts the comparison program out of
`parity-fixture.sh`'s heredoc at run time rather than reimplementing it, because a copy proves the
copy. Its worth is measurable: run against **main's** normaliser it reports **8 of 14 cases wrong**
— five false DIVERGEDs from a directory name, and three real differences the old rules hid.

```
  WRONG captured in a directory called 'mcp-router'              exit 1, wanted 0
  WRONG captured in a directory called 'my_project'              exit 1, wanted 0
  WRONG captured in a directory called 'my-tree'                 exit 1, wanted 0
  WRONG captured in a directory called 'a.b c'                   exit 1, wanted 0
  WRONG captured in the checkout root, not a worktree            exit 1, wanted 0
  WRONG project is alphanumeric and NOT basename(cwd)            exit 0, wanted 1
  WRONG two records, one honest, one lying, same project string  exit 0, wanted 1
  WRONG a per-project calls count moved 1 -> 900                 exit 0, wanted 1
normalise selftest: 6 behaved, 8 did not
```

Without it, A7 and A12 would have lived only in a throwaway script, and re-widening `project` to a
character class would go green from every directory. The Phase D critic raised exactly that.

**A harness bug the message assertions caught.** The first draft of this file incremented a case
counter inside `$(scratch)` — a **subshell**, so the counter never reached the caller. Every case
reused one directory and inherited the previous case's mutation, and fifteen cases reported red
against a cumulatively broken tree. Exit-code-only assertions would have shipped it looking
perfect. Fixed with `mktemp -d`, and recorded in the file's own comment.

## 4. The normaliser, old against new

Measured with the lane's own heredoc, extracted from the shipped script, against `usage.json`:

| the live body carries | OLD | NEW | |
|---|---|---|---|
| `project` `"mcp-router"` (the repo root's own name) | **1** | **0** | D-o: a false DIVERGED caused by a directory name |
| `project` `"my_project"` | **1** | **0** | underscore, same class |
| `project` `"my-tree"` | **1** | **0** | hyphen in a worktree name |
| `project` `"a.b c"` | **1** | **0** | dot and space; every legal name |
| `project` = the whole `cwd` | 1 | 1 | *both* red — proves only that the rejected `[^"]+` was not shipped |
| `project` = `""` | 1 | 1 | *both* red — the old class already refused it |
| **`cwd`=`…/P4`, `project`=`"F3"`** | **0** | **1** | **alphanumeric and wrong. The old class normalised both sides and HID it** |
| **two records, one honest, one lying, same `project` string** | **0** | **1** | **the case that defeats collect-then-substitute** |
| `projectNames[0].calls` `1` → `900` | **0** | **1** | **a per-project call count was invisible** |

Rows five and six are marked as proving less than they look like they prove, because they redden on
the old table too. The three bold rows are the ones that distinguish the designs.

## 5. The gate, from three directories

`fixture` is the group D-o lives in, and A9 is judged on its **per-row verdicts**, not on the total —
§2 of the spec shows the totals already agreed at 73 while D-o was live, so a total-equality
criterion would have been green before any work started.

| run | cwd | script | `fixture` group | `usage` fixture |
|---|---|---|---|---|
| **before** | `mcp-router` | main's | 22 proven, 1 blocked, **1 DIVERGED** | **DRIFTED** |
| **before** | `.worktrees/P4` | main's | 23 proven, 1 blocked, 0 DIVERGED | matches |
| **after** | `mcp-router` | `.worktrees/P4`'s | **23 proven, 1 blocked, 0 DIVERGED** | **matches** |
| **after** | `.worktrees/P4` | its own | **23 proven, 1 blocked, 0 DIVERGED** | **matches** |
| **after** | `.worktrees/p4-hyphen-check` | its own | **23 proven, 1 blocked, 0 DIVERGED** | **matches** |

All **24 fixture rows are byte-identical** across the three after-runs (`diff` of the extracted
per-row verdicts: no line differs). The before-drift was
`.records[0].project: recorded="<project>" live="mcp-router"`.

**The repo-root run had to use the worktree's script.** `REPO_ROOT` comes from `BASH_SOURCE`, not
from `cwd`, so `bash scripts/acceptance/parity-gate.sh` at the repo root runs *main's* harness and
would have compared the old normaliser against the new one. The `project` a call is attributed to
comes from the **process cwd** (`call-through-router.mjs` inherits it), so the decisive invocation
is `cd <repo root> && bash .worktrees/P4/scripts/acceptance/parity-gate.sh`. Raised by the
out-of-family plan review; the first plan had the wrong command written down.

`.worktrees/p4-hyphen-check` is a third directory whose **name contains hyphens**, which is the
literal D-o trigger, and it is inside the sandbox this runner is allowed to write to. Its
`control` and `divergence` lanes exited 2 for want of a Swift `ControlDiff` build (a fresh worktree
has none — `D-p4-b`); its `fixture` lane is complete and identical.

### Totals, and why they wobble by one

| run | exit | proven | blocked | DIVERGED |
|---|---|---|---|---|
| cwd `mcp-router`, worktree script (12:38) | 1 | 72 | 9 | 2 — `div-r2-d6`, `install-launchd-serve` + `-watch` |
| `.worktrees/P4` (12:48) | 1 | 72 | 9 | 2 — `div-r2-d6`, `install-launchd-watch` |
| `.worktrees/P4`, final tree | 1 | **74** | 9 | **0** |
| `.worktrees/P4`, final tree, again | 1 | 73 | 9 | 1 — `install-launchd-watch` |

**73 before, 73–74 after, and the movement is one row of pre-existing instability.** The `fixture`
group reads 23 of 24 proven, 1 blocked, **0 DIVERGED in every single run from every directory** —
that is the number P4 changed, and it does not move.

Every diverged row across the four runs is `div-r2-d6` or an `install-launchd-*` row, and **P4's
diff touches neither `parity-pool.sh` nor `parity-install.sh`** — `git diff --stat main..HEAD` over
those two paths is empty. Both are load-sensitive, measured rather than assumed:

- `div-r2-d6` — the pool lane run in isolation **8 times, 4 from the repo root and 4 from the
  worktree: 8 of 8 read `callsServed=1`, exit 0.** Inside a full gate run it read 4, then 3.
  Registered `D-p4-a`. **Not called flaky** — that label invites re-running until green over a real
  acquisition race, which is the `D-p` mistake.
- `install-launchd-watch` — the install lane run in isolation 3 times: **fail, ok, fail**, with
  `install-launchd-serve` ok all three. That is `D-p1-e` observed again ("unstable on BOTH
  binaries, agreed 1 in 6"). `install-launchd-serve` diverged only inside a full gate run, so it
  has the same character under load and is folded into `D-p1-e`.

The two before-runs each carried one such divergence too, on *different* rows — which is why the
two 73s agreeing was a coincidence rather than agreement, and why A9 is judged on the fixture
group's rows rather than on the total.

**The denominator did not move: 83 before, 83 after**, and it is now pinned at that. Both
derivations agree with source, so they confirm the existing rows rather than editing them. No
manifest row was added, edited or deleted — the only change to `surface.tsv` is a comment header.

## 6. Gates, each captured directly

| gate | exit | note |
|---|---|---|
| `bash -n` × 4 changed scripts | 0, 0, 0, 0 | |
| `shellcheck -S warning` × 4 | 0, 0, 0, 0 | 0 findings |
| `parity-manifest-check.sh` from `.worktrees/P4` | **0** | 83 rows |
| `parity-manifest-check.sh`, cwd = repo root | **0** | 83 rows |
| `parity-manifest-check.sh` from `.worktrees/p4-hyphen-check` | **0** | 83 rows |
| `parity-manifest-selftest.sh` | **0** | 23 cases |
| `parity-lane-selftest.sh` | **0** | every lane went red against a broken router |
| `make lint` | **0** | 0 violations / 438 files. Exit code checked, not the "0 violations" line — swiftformat runs first and short-circuits |
| `make test` | **0** | **1379 tests in 169 suites passed** |

`make build-mac` and `make test-ios` were **not run**, and that is a declaration rather than an
omission: the diff contains no Swift, no TypeScript and no project file.

1379 is the same count `main` carries, which is the expected outcome for a diff that changes four
shell scripts and nothing else. The `Executed 0 tests, with 0 failures` line in the log is the
XCTest shim, not the suite — the swift-testing runner reports separately, and reading only the
first would be this repo's own recorded "green zero" trap.

## 7. Reviews — all three out-of-family, lane logged

Lane: `grok --model grok-4.6 -p`. **codex was not probed**: it is account-limited to 2026-08-20 by
the owner's standing instruction. grok **exits 0 when session init fails**, so the lane was
smoke-tested before it was relied on and each response was checked for real review content rather
than an error payload. No downgrade was needed; all three gates ran out-of-family.

| gate | verdict | outcome |
|---|---|---|
| spec | **AMEND**, 6 findings | all 6 accepted, all verified against the tree, none rejected |
| plan | **AMEND**, 2 critical + 4 high | all accepted; the design changed before the code was finished |
| Phase D critic | **AMEND**, 5 findings | all 5 accepted; three closed in code, two corrected in the record | |

The two that changed the design:

1. **The spec review found the auth-pair hole** (§1) — D-n's exact failure mode inside the group
   the first draft used as its proof that the mechanical rows were safe.
2. **The plan review found that the normaliser undid its own per-object test.** The first
   implementation collected the project values that passed the `basename(cwd)` test and then
   substituted each one *globally*, so a body with one honest record and one lying record sharing a
   project string had both rewritten — the same shape as the `[^"]+` widening the spec had already
   rejected. Nothing is substituted on the strength of the walk now: the walk asserts the invariant
   on each side independently, and a body that breaks it is reported as the difference.

The plan review also found five extractors that gave **wrong** answers rather than empty ones,
which no zero-guard can see: only the first quoted string on a `case` line was read; a
double-quoted arm vanished entirely; `usage()` was parsed with exactly one space; the
`url.pathname` count shared the extractor's own idiom; and the handlers had no count at all.

3. **The Phase D critic then showed three of those five were only half fixed**, and it did it by
   mutating scratch copies rather than by reading. Ten dispatch shapes still passed silently:
   `cmd==='doctor'` without spaces, `process.argv[2] === 'doctor'`, `['doctor'].includes(cmd)`,
   `cmd !== 'help'`, a second path beside a recognised one on the same line, and a `/health`
   compare commented out while a comment still satisfied the extractor. Each now reddens, and each
   has a case in the selftest. The fixes were to stop pattern-matching one spelling and start
   **accounting for every mention** — every use of `cmd`/`argv[2]` and of `url.pathname` must be
   one of the shapes the check understands, comments are stripped before extraction, and the
   handler count counts occurrences rather than lines.

It also made two corrections to the *record* rather than the code, both accepted:

- **The three "after" gate logs were runs of the first commit, not of the final tree.** They print
  the pre-rewrite `manifest-check` success line, which is how it was spotted. §5's table now
  distinguishes them by time and the final-tree runs are reported separately.
- **The hyphenated worktree is not a complete gate** — 53/83 with `ControlDiff` missing. Only its
  `fixture` group supports an identity claim, which is what §5 claims and nothing more.

Two of its findings I had reached independently before reading it: the four unprotected rows, and
that `parity-manifest-selftest.sh` was not wired into anything. Both are closed.

## 8. Status

**Ready to merge**, and the gate still exits 1 by design — the cutover requires 83 of 83 and this
tree has 73–74. P4 does not move the cutover decision; it makes the number underneath it mean what
it says.

Merged-tree gates are the orchestrator's to re-run. This branch is 0 commits behind `main`, so the
branch tree and the merged tree are the same tree.

## 9. Deferred children registered by this item

| # | Child | Absorbed by |
|---|---|---|
| `D-p4-a` | `parity-pool.sh`'s D6 assertion is contention-sensitive: 8 of 8 isolated runs read 1, a loaded gate run read 4 then 3, and the lane reports a hard `fail` which the gate renders as an undeclared DIVERGENCE | D1 / R4-C |
| `D-p4-b` | A fresh worktree cannot run the gate without `npm install && npm run build` (and `swift build` for `ControlDiff`); every lane exits 2 with an accurate message and an undiscoverable sequence | G1 |
| `D-p4-c` | Derive the 5 `install` rows from `install.sh` — they name scenarios rather than tokens, so it needs a design, not a regex | D1 |
| `D-p4-d` | `spec-R4.md`'s prose D-table lists only D1–D7, while `surface.tsv` carries fifteen divergence rows. A reader who trusts the doc under-counts | R4-C |

## 10. `D-v1g`, measured

`D-v1g` said B23 and B44 are wrong as written and **two real divergences are missing from R4's
D-table**, so they read as agreement. Measured against the census the gate actually reconciles:
`surface.tsv` carries `div-r3-d1` … `div-r3-d5` — PATCH bodies `42`, `"hi"` and `true` (B44's
subject) and a bare `%ZZ` and a truncated escape (B23's). They are enumerated, and the `divergence`
group reads 14 of 15 proven.

So the half of `D-v1g` about the gate is **stale**: it is true of `spec-R4.md`'s prose D-table,
which lists D1–D7 only, and not of the file the gate reads. The other half — that `spec-R3.md`'s
B23/B44 clause prose is wrong — is a documentation defect in another item's spec, moves no parity
row, and P4 does not edit another item's spec. **No row added; the denominator is unmoved.**
Registered as `D-p4-d` and reported to the orchestrator with the correction that the finding should
be re-pointed at the prose rather than at the census.
