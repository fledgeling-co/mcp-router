# plan-G1 — Stop the acceptance checks blaming the app for being out of date

Branch `ai/g1` · worktree `.worktrees/G1` · base `7babd97`
Spec: `planning/specs/spec-G1.md`

**Parity BEFORE, measured on this tree: 77 of 83 proven, 6 blocked, 0 DIVERGED** (exit 1 by
design). `install` read 4 of 5 with the single block being R4-C's uninstall row — so
`install-launchd-watch` **agreed on this run**. That is the upper end of the brief's "76 or 77
depending on the run", and it is the number this item must not move.

---

## 0 · What the spec gate changed, before any code

One out-of-family adversarial pass, `grok --model grok-4.6`, lane smoke-tested first with a
content assertion (`LANE_ALIVE_7731` + `42`) because grok exits 0 on a session-init failure.
Verdict **AMEND**, six findings. Every one was checked against the repo rather than taken:

| # | Finding | Checked | Disposition |
|---|---|---|---|
| 1 | A sidecar stamp is not bound to the bytes that launch | partly true | **Taken, differently** — §2.1 |
| 2 | A Swift-only digest is blind to the fixture JSON that drives every scenario | **TRUE** — `app/Package.swift:39` ships `.copy("Control/Fixtures")` and `.copy("Control/Authored")`; every `MCPROUTER_SCENARIO` is those files | **Taken in full** |
| 3 | The launch taxonomy files environment deaths as product, and does not bind the PID to this bundle | **TRUE** — `m8-settings-menubar.sh:53-66` already path-binds and the others do not | **Taken in full** |
| 4 | "One missing wait" does not explain P1's table | **TRUE** — `planning/evidence/P1-acceptance.md` shows `yes,yes,no` ×2 and `yes,no,yes` ×3; the terms vary **independently** | **Taken — the spec's single-cause claim is withdrawn** |
| 4b | `agent_pid` reads `pid = 0` for a stopped job, so the predicate is inverted | **FALSE, measured** — a real scratch agent after exit prints `state = not running` and **no `pid` line**; `agent_pid` returns empty | **Rejected with the measurement** |
| 5 | `D-i2-guard` is a third deliverable and the spec omits it | **TRUE** — `planning/features-to-triage/G1-gate-hygiene.md` names it, and `awaitingKey` is gone from `PhoneShell.swift` (comments only) | **Taken — it is the seventh red** |
| 6 | The proofs cannot fail as written | **TRUE** | **Taken** — §4 |
| 7 | Unifying the launchers would regress `m8` and misses `shells.sh` | half true — `shells.sh` never calls `open` at all | **Half taken**: m8's path-binding is adopted *into* the shared launcher; `shells.sh` is out of scope and said so |

Finding 5 is the one that mattered most: **I had not read the item's own brief file.** It names
three pieces and I had two. `D-i2-guard` is the red a rebuild cannot clear, which is exactly why
it survived as the seventh.

---

## 1 · Order of work

Freshness first, because every later proof needs a trustworthy "is this build the tree's build"
answer. Then the launcher, then the two iOS scripts, then the two arithmetic fixes, then the
watch lane last because it is the only one whose verdict is decided by measurement.

---

## 2 · The changes

### 2.1 `scripts/acceptance/build-freshness.sh` — one reader, content only

Sourced, in the manner of `board-registry.sh`, and the only place freshness is decided.

**The digest covers every input the product is built from**, not just Swift:

```
app/Sources/**/*.swift
app/Sources/MCPRouterKit/Control/Fixtures/**      <- finding 2
app/Sources/MCPRouterKit/Control/Authored/**      <- finding 2
app/MCPRouter/**  app/MCPRouterIOS/**             (Info.plist, entitlements, assets)
app/project.yml  app/Package.swift  app/Package.resolved
```

Content only: `find … -type f | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256`. Paths are
repo-relative so two worktrees agree.

**The stamp binds to the product as well as to the tree.** This is finding 1, taken by a
different route than grok proposed. It recommended embedding the digest inside the `.app`; that
is rejected with a reason — the Release configuration sets the hardened runtime, and writing a
file into a signed bundle after the build invalidates its signature. Instead the stamp records
**two** hashes:

```
sources <sha256 of the input tree>
binary  <sha256 of Contents/MacOS/MCPRouter>
```

The check then requires the stamp to exist, its `binary` to equal the hash of the executable
actually present, and its `sources` to equal the tree's digest now. An old bundle copied back
beside a fresh stamp fails on the binary hash; a stale tree fails on the source hash; a deleted
product fails on absence. No mtime appears anywhere, so a rebase is invisible to it — which is
the whole of `D-m11-a`.

**Per configuration.** `make build-mac` stamps `Debug/`, `make build-mac-release` stamps
`Release/`, `make build-ios` stamps `Debug-iphonesimulator/`. Grok's finding that a Debug-only
stamp would be consulted for a Release judgement is real and this closes it.

The stamp is written **after** `xcodebuild` exits 0, by the same make recipe, so a failed build
leaves the previous stamp and the next check blocks.

**The hole that is NOT closed, stated rather than hidden:** if `xcodebuild` exits 0 having
skipped work its own dependency graph did not see, the stamp records the current tree against a
product that does not reflect it. An embedded digest written by a script phase would have the
same hole, because a phase with no declared outputs runs on every build. This check is exactly
as good as `xcodebuild`'s own up-to-date answer, and no better.

API:

```
build_freshness_require <config>   # blocks(2) on: no product | no stamp | binary moved | tree moved
build_freshness_digest             # prints the tree digest
build_freshness_write <config>     # writes the stamp; called by the Makefile only
```

### 2.2 `scripts/acceptance/mac-app.sh` — one launcher

Replaces the launcher in `mac-shell.sh`, `m2`, `m5`, `m6`, `m7` (five copies) and adopts m8's
PID binding rather than overwriting it. `m8` moves onto the shared one too, so its path check
becomes the shared behaviour instead of the one script that got it right.

Sequence, every step waiting on an observable:

1. **Wait out the previous instance.** Poll until no process whose executable is under this
   `MAC_APP` remains, bounded. Still there → BLOCKED 2 naming the previous instance. This runs
   **before** `open`, and it is the `-600` the orchestrator saw.
2. **`open -g -a`, exit status checked.** Non-zero → BLOCKED 2 quoting `open`'s own stderr and
   saying nothing ran.
3. **Wait for a process bound to THIS bundle** (`pgrep -x MCPRouter` + `ps -o comm=` prefix
   match, m8's method). None → BLOCKED 2.
4. **Wait for a window.** If the bound PID disappears while waiting → **FAIL 1**: the app
   started and exited. If it is alive and never draws → **FAIL 1**.
5. **Read the AX tree.** Unreadable while the window exists → BLOCKED 2 (permission/harness).

Finding 3's refinement is taken: a PID that vanishes is only FAIL when it is *this* bundle's
PID, which step 3 guarantees. Six arms, not five; the pre-`open` arm is new and is in the
matrix.

### 2.3 The eight checks

| Script | Freshness | Launcher | Other |
|---|---|---|---|
| `mac-shell.sh` | Debug **and Release** | shared | Release precondition hoisted into preflight; M11's mtime block **deleted**, superseded |
| `m2` `m5` `m6` `m7` `m8` | Debug | shared | — |
| `i2` | — (builds its own) | — | guard repointed to `content(for:)`; build/test split; no-simulator → exit 2 |
| `i3` | — (builds its own) | — | build/test split; no-simulator → exit 2 |

`i2`/`i3`: `build-for-testing` first — non-zero is **BLOCKED 2** naming the build.
`test-without-building` second — non-zero is **FAIL 1** naming the surface. A missing simulator
or a lost destination is **BLOCKED 2**, where today both scripts `fail` (exit 1) in a sentence
that calls it an environment failure.

**`D-i2-guard`.** `awaitingKey` and `AwaitingTab` are gone from `PhoneShell.swift` — present
only inside the doc comment that records their removal. i2's reader therefore matches nothing
and exits 1 with *"treat as a broken reader, not a pass"*, which is honest and permanently red.
Repointed at `private func content(for tab: Tab)`, asserting the `.discover` arm resolves to
the real screen. i3 already reads that shape; i2 is brought onto it.

### 2.4 `parity-manifest-check.sh` — count findings, not lines

`note()` prints and counts. New `detail()` prints only. The **existing** multi-line sites are
converted — 102-104, 183-184, 238-241, 290-293, 320-322, 436-437, 468-469 — so the proof
exercises production code rather than a finding invented for it (finding 6).

### 2.5 `parity-gate.sh` — one notice, no number moved

A single pre-lane notice when `dist/index.js` is absent, naming `npm run build`. The lanes keep
their own messages, their own exit 2 and their own blocked classification. **Nothing that
computes coverage is touched.** The register's premise for `D-p4-b` — that a fresh worktree
"cannot run" the gate — is wrong and the plan says so: it runs, exits 2, and prints the remedy
nine times.

### 2.6 `parity-install.sh` — the watch lane, and a verdict declared in advance

Changes:

- wait for the first run's process to be **gone** before judging `oneshot`, using the same
  predicate (measured correct: no `pid` line once stopped);
- stage the second file only **after** that wait, so launchd cannot drop a WatchPaths event for
  a job it considers already running;
- write the staged file **atomically** (temp + `mv`) rather than `cat >`, so a truncate-then-write
  cannot present as two events or as a mid-write parse;
- treat a second run that starts but writes no state as **lane could not run**, not `reran=no`.

**The criterion is fixed now, before the measurement, so it cannot be moved afterwards:**
8 consecutive runs of the watch lane, load recorded per run. All 8 agreeing at `yes,yes,yes` on
both binaries → the row stays `proven`. Anything else → the row is marked `blocked` in
`surface.tsv` with the mechanism in its note, per P1's recommendation. **Neither outcome is
called "flaky".**

`surface.tsv`: the `install-launchd-watch` row only. **The row count does not change, so the
`# rows: 83` pin does not move.**

---

## 3 · Mutations — every one rebuilt first, and re-aimed if it cannot redden

The repo's own trap: an acceptance script reports a STALE BUILD as a product defect, so a
mutation that fails to compile reports green against the old binary. Each mutation below is a
**harness** mutation, so the trap takes a different form — the mutated script must actually be
the one executed.

| # | Semantic claim | Mutation | Must go |
|---|---|---|---|
| M1 | Freshness reads a **recorded** digest, not two live ones | delete the stamp file | BLOCKED 2, "no record of what this build was built from" |
| M2 | Freshness binds to the **product** | overwrite `Contents/MacOS/MCPRouter` with a copy of another binary, stamp untouched | BLOCKED 2, naming the binary |
| M3 | Freshness covers **resources**, not just Swift | edit one JSON under `Control/Fixtures`, no rebuild | BLOCKED 2 — this is the one a Swift-only digest passes |
| M4 | A rebase does **not** block | `touch` every input file, no content change | **PASS** — and this is the arm that must NOT redden |
| M5 | `open` refusing is not the product's fault | `PATH` shim ahead of `open` exiting 1, with the shim asserted to have run | BLOCKED 2 naming LaunchServices |
| M6 | The app dying on launch **is** the product's fault | kill the bound PID inside the window wait | FAIL 1 naming the app exiting |
| M7 | The counter counts findings | feed a manifest triggering one existing multi-line site | reported count 1, and the old code's answer recorded beside it |
| M8 | i2's guard reads something that exists | rename `content(for:)` in a scratch copy | the guard fails — proving it reads the live shape |

M4 is the inverse mutation and is included deliberately: a freshness check that blocks on a
rebase is the defect being fixed, so a proof that only shows blocking would certify the old
behaviour.

---

## 4 · Why the proofs can fail (finding 6, taken)

The spec's §3 proofs were tautological in three places and are re-cut:

- **The touch test could pass with no stamp at all** (`hash(sources) == hash(sources)`). M1 and
  M2 now force the recorded side to be read, so M4 only passes if a real record was consulted.
- **The counter proof used a newly-added finding**, which would go green while every existing
  multi-line site kept double-counting. M7 uses an existing site.
- **The `open` shim may never fire.** M5 asserts the shim ran (it writes a marker) before
  believing the BLOCKED it produced.
- **§3.4 refused to define N.** It is 8, fixed above, with the verdict rule fixed with it.

---

## 5 · Gates and the numbers to report

`make lint` (expect 0) · `make test` · `make build-mac` ·
`scripts/acceptance/parity-manifest-check.sh` (expect 0) · `make parity-selftest` (expect 0) ·
`parity-gate.sh` — report the **number**, 77 of 83 before, and after.

Watch for the `make lint` order trap: `swiftformat --lint` runs first and short-circuits, and
`make format` can push a file past the 400-line cap. The new shell helpers are not Swift, so
neither applies to them; the risk is nil for this diff and is named so the next reader knows it
was considered rather than missed.

## 6 · Not done, deliberately

- `shells.sh` keeps its own launch path. It never calls `open` and its zombie handling is its
  own; folding it in would be a change with no defect behind it.
- The `SWIFT_BIN` SwiftPM binary used by `parity-install.sh` is not stamped. No acceptance
  script judges a *screen* from it, so the stale-build class does not reach it.
- `DESIGN.md`'s 33pt-vs-32pt titlebar note that `mac-shell.sh` prints is a shared-surface
  design finding and is left alone.

---

# ADDENDUM — the plan gate, the critic, and where measurement beat the plan

Written by the re-run after the original attempt died on capacity with 0 commits. The spec and this
plan survived in the main tree and were **re-verified rather than trusted**: every deterministic
claim in spec §0 was checked against the repo again (launcher copies, `note()` counting,
`observe_watch`, M11's `MENU_SOURCES`, `REL_APP` at line 32 vs 1235, the i2 guard), and all held.
The base moved from `7babd97` to `9b6077b` (P3 merged), so every number was re-measured.

## The plan gate (grok-4.6, out of family) — verdict REJECT, 11 findings

It had never run: §0 above records only the SPEC gate. Lane smoke-tested with a content assertion
first. Two dispatches died at SIGALRM having emitted only streamed preamble — grok explores the repo
when given tool access and exceeded 900s and then 2400s — so the third was tightly scoped with
"do not explore any repository" and returned 6.6KB in under 25 minutes. **Exit 0 with an empty
output file is the lane failure this fleet already knows about, and it happened twice here.**

Taken: the stamp not binding its configuration (a Debug bundle copied to the Release slot read
fresh); the non-atomic stamp write; a crash dying before the first poll misclassified as BLOCKED;
a missing toolkit reading as a product failure; **a compile error classified as environment**, when
"your code does not compile" is a true claim about the product; **the i2 guard repeating I3's exact
defect**; and **promotion-on-a-streak being re-run-until-green wearing a criterion**.

Rejected with citations: the RouterCore exclusion is by LINKAGE (`project.yml` lists only
`MCPRouterKit` and `MCPRouterUI` as the Mac app's dependencies); the freshness exit code is
specified and measured as 2, never 1; "activate once if no window appears" would violate
`UI_VERIFICATION.md` rule 1 outright; and worktrees each own their `app/.derived`, so bundle paths
differ per worktree.

## The Phase D critic (grok-4.6) — verdict AMEND, 9 findings

Its first finding was the sharpest and was taken: **isolated helper mutations are not harness
proofs** — M1–M6 would pass with the helpers unused. That produced the end-to-end proof through
`mac-shell.sh` (evidence §1), which the plan had never specified. Also taken: hashing the mach-o
alone let a swapped resource read fresh (now the whole bundle), and a source edited *during* a build
was stamped as though the product contained it (now guarded by a pre-build digest).

Rejected with measurements: `ps -o comm=` does return the full path (120 chars here), which is how
the `/private/var` symlink bug was found in the first place; and m8 never had Release *coverage* to
lose, because its assertions are written against Debug fixture scenarios and demonstrably fail
against Release.

## Four places the measurement contradicted a written prediction

1. **The brief's launch mechanism.** It predicted 40 poll iterations concluding "the shell window
   never appeared". Measured: `set -euo pipefail` aborts at `open`, so the old script exits 1 with
   nothing but `kLSServerCommunicationErr -600` and that sentence is never printed.
2. **`-600` is not only the dying-process race.** It fired twice here *after* the previous instance
   was confirmed gone, so waiting for death is necessary and not sufficient. Hence the bounded
   retry on the transient signature only.
3. **The BEFORE parity number.** The brief said 78 of 83 with 1 DIVERGED; measured 79 of 83 with 0,
   because `install-launchd-watch` agreed on that run. The BEFORE is itself unstable, which is the
   row's whole problem.
4. **`D-p4-b`'s premise.** The gate does run unbuilt; it says the same thing 22 times, not 9.

## Not done, and why

- **No iOS mutation for i2.** The claim that the XCTest suite reddens if Discover were a placeholder
  is asserted by construction and not proven; registered as `D-g1-d` rather than claimed.
- **`parity-lane-selftest` is invoked by `parity-selftest` only when `dist/` exists**, with a loud
  skip otherwise, so the gate stays runnable in a fresh worktree. Whether it should be mandatory is
  a judgement for whoever owns the cutover number.
