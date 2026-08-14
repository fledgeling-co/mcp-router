# R4 — acceptance evidence

**Branch:** `ai/r4` · **Worktree:** `.worktrees/R4`
**Spec:** `planning/specs/spec-R4.md` · **Plan:** `planning/plans/plan-R4.md`

R4 ships **no GUI**. Its user-facing surface is the parity gate's terminal report, so the
"screen" rows below are that report's states rather than app windows. Nothing in this item
launches the Mac app, boots a simulator, or takes the user's screen — there was nothing to take
it for.

Append to this file; never rewrite it. A row whose SHA-to-HEAD diff does not touch the files
behind it **is** the evidence — read it before re-running anything.

---

## The headline

**Parity did NOT pass, and it did not pass by a wide margin: 50 of 81 enumerated rows.**
`scripts/acceptance/parity-gate.sh` exits **1**. The cutover was **not performed** — no change to
`docs/install.sh`, no deletion of `src/*.ts`. That refusal is this item's primary deliverable and
the gate's own exit code is its evidence.

---

## Acceptance clauses

| # | Criterion | Evidence type | Command / observation | Result |
|---|---|---|---|---|
| A1 | The manifest enumerates every control route `control.ts` dispatches | red-green | `PARITY_MANIFEST=<manifest minus one row> parity-manifest-check.sh` | **exit 1**, `control.ts answers "POST /usage/reset" and the manifest has no row for it`. Green on the real manifest: `81 rows, consistent with control.ts and the fixture directory` |
| A1b | …and no row that no route answers | red-green | manifest plus a bogus `GET /invented` row | **exit 1**, `the manifest carries control row "GET /invented", which control.ts does not answer` |
| A2 | The manifest enumerates the MCP surface, the ten CLI verbs, spawn/reap, the log, what the installer does, and inherited on-disk state | inspection | 5 `mcp` + 10 `cli` + 6 `pool` + 5 `install` + 1 `state` + 1 `log`, read out of `src/router.ts`, the ten `case` arms in `src/index.ts`, and `docs/install.sh` | 28 rows. The `install` and `state` groups were absent from the first census and their absence RAISED the coverage figure — added after the spec review found them |
| A3 | Every row carries exactly one verdict, and every blocked row names a reason and an owner | red-green | blocked row with owner `-` | **exit 1**, `blocked with no owning item — a gap with no owner is a gap nobody has` |
| A3b | A verdict outside the closed set fails | red-green | a row with verdict `maybe` | **exit 1** |
| A3c | Two rows sharing an id fail | red-green | duplicated `pool-p1` | **exit 1**, `duplicate row id "pool-p1"` — one lane's result would otherwise overwrite the other's |
| A4 | The gate exits non-zero while any row is blocked, and says so in words | exercised | `scripts/acceptance/parity-gate.sh` | **exit 1**, `parity: 50 of 81 rows proven (4 of them by suite only, not by wire comparison), 31 blocked. This is NOT a pass.` |
| A5 | Coverage prints as a fraction, never a bare pass count | exercised | same run | `50 of 81` overall, the suite-only share named in the same sentence, plus a per-group breakdown across nine groups |
| A6 | The gate exits **2** when the environment cannot run a lane | exercised | `mv dist dist.hidden; PARITY_LANES=divergence parity-gate.sh` | **exit 2**, `no built reference at dist/index.js. Run npm run build.` `dist` restored and verified |
| A6b | A lane whose script is missing is an environment failure, not a silent skip | exercised | `PARITY_LANES=ghost parity-gate.sh` | **exit 2**, `ghost — no lane script at scripts/acceptance/parity-ghost.sh` |
| A7 | A lane that fails to run is recorded as blocked, never dropped | red-green | both runs above | blocked rose to **70+**; the denominator held. The fraction fell, it did not improve |
| A7b | A lane that exits 0 having recorded nothing is treated as not run | red-green | a stub lane printing one line and exiting 0 | **exit 2**, `stub exited 0 without recording a single row. Treated as not run.` |
| A7c | Observed unplanned: a lane that crashes mid-run | measurement | an `unbound variable` crash in `control-differential.sh` | the gate reported `control 1 of 15 proven, 14 blocked` — the crash shrank the numerator, never the denominator |
| A8 | Every control route the Swift handler can answer is compared byte-for-byte, status included | exercised request | `parity-control.sh` | **49 comparisons, 47 ok**, covering 11 of the 15 manifest rows. NOT every route: `approve` and `auth` POST are asserted as known defects, and `usage/stream` and `registry/search` are reported informationally and stay blocked. "49" counts comparisons, not manifest rows — the two denominators are deliberately distinguished here because an earlier draft blurred them |
| A9 | The two defects are asserted as known divergences with an owner, and fail if either side changes | red-green, both directions | `known_defect` in `control-differential.sh` | `POST …/approve ts=409 swift=405 (D-j)`, `POST …/auth ts=400 swift=405 (D-j)`. Either side moving reports `STALE` |
| A9b | A stale defect record cannot hide in the blocked list | red-green | gate reconciliation | a blocked row whose lane result begins `stale` is counted as a **mismatch**. Without this a blocked row stayed blocked whether or not its reason was still true |
| A10 | Every fixture with a stable oracle is replayed against the live reference, and its status asserted (D-a) | exercised request + red-green | `parity-fixture.sh` | **23 replayed, 23 match, 0 drifted.** `registry-search` is NOT replayed — it has no stable oracle — and stays blocked rather than counted. The status is now compared against `planning/parity/fixture-status.tsv`, not merely captured: a body-identical fixture under a changed status fails its row. An earlier draft claimed all 24 were replayed and that the status was checked; neither was true |
| A11 | D1, D3 and D4 are each accounted for explicitly; absence is never read as agreement (D-g) | red-green | `parity-divergence.sh`, `parity-suite.sh` | **D1 ok** on the wire — the reference serves an empty list, Swift refuses the config. **D3 is blocked (D-k)**: its declared subject is the `src/index.ts` writer, reachable only via CLI verbs Swift lacks. The lane measured the control-API writer instead, found both sides preserve the key, and that is recorded as its own row `div-r1-d3-control` rather than as proof of D3. **D4 is `proven-by-suite`** — not observable on the wire per spec-R1 line 149 — and its cited test is now executed by the suite lane rather than merely named |
| A12 | Declared divergences are asserted as expected, and go red if stale | red-green, both directions | `diverges()` × 5 (R3 D1–D5), D6 in the pool lane | all 6 **ok**. R3 D1–D5: `reference DIED (URIError) · swift 400`. D6: `callsServed counted 1 acquisition for 5 concurrent calls` |
| A13 | The gate never touches the real `MCP_ROUTER_HOME`, `~/.claude.json`, or ports 8975/8976 | measurement | scratch-home guard in `control-differential.sh`; `lsof` port refusal in every lane | Every lane runs in `mktemp -d` on ports 8963–8973. The user's router on 8975/8976 was never contacted, stopped or restarted. **Network egress is NOT measured**: the earlier wording claimed the gate never touches the network, which no check here establishes — `registry/search` reaches live registries by design, which is why that row is blocked rather than compared |
| A14 | The harness does not stop or mutate a router it did not start | inspection | each lane starts and kills only its own pid | no lane takes a pid it did not spawn |
| A15 | The cutover is **not** performed, and the gate's output is the stated reason | the gate's exit code | `git diff main..ai/r4 -- docs/install.sh src/ package.json` | **empty**. The gate exits 1 at 50 of 81. Noted honestly: this clause is satisfied by inaction and cannot fail — it is an outcome, not a criterion, and the gate's exit code is the thing actually carrying it |

---

## Project gates, at `ai/r4`

| Gate | Command | Result |
|---|---|---|
| Swift build + tests | `make test` | **456 tests in 68 suites passed** — identical to main's baseline |
| Parity vectors | `make parity` | **358 vector cases compared (floor 358)** — unchanged |
| Lint | `make lint` | **exit 0**. SwiftLint `0 violations, 0 serious in 151 files`; swiftformat `0/152 files require formatting` |
| Lint examined a non-zero file count | `swiftformat --lint . --config .swiftformat` | **152 files**, 60 skipped. `.swiftformat` excludes `.worktrees`, but the pattern does not match when `.` *is* the worktree root, so the gate really looked. Verified rather than assumed |
| Shell | `shellcheck -S warning` on all 8 harness scripts | **clean** |
| The gate itself | `scripts/acceptance/parity-gate.sh` | **exit 1**, 50 of 74 — the expected result |

### Affected-test sweep

R4 adds shell scripts, a manifest and two planning files. It changes **no shipped Swift code**,
which the numbers confirm: `make test` is 456/68 and `make parity` is 358, both identical to
main. Nothing moved, so nothing was re-baselined.

Two existing scripts were edited, both additively:

- `scripts/capture-control-fixtures.sh` — an opt-in `STATUS_DIR`, and one **bug fix**:
  `FIXTURE_OAUTH_PORT` was never passed to the OAuth fixture server, so the manifest pointed at
  one port and the upstream listened on another. It agreed by coincidence at the default and
  broke at any other port, failing with `no in-flight authorization was captured` rather than
  naming the cause.
- `scripts/acceptance/control-differential.sh` — `diverges()` now records the divergence row it
  asserts, not only the control route. Before this, R3's D1–D5 were asserted in that file and
  read as `no lane reported` in the census.

---

## The gate's nine states (DESIGN.md §5)

R4's surface is a terminal report, and §5 applies to it as a data surface. Verified states:

| State | How it was reached | Observed |
|---|---|---|
| Partial — the live state | the normal run | `parity: 50 of 74 rows proven, 24 blocked. This is NOT a pass.` then blocked rows grouped by owner |
| Error — a lane failed to run | `mv dist dist.hidden` | `no built reference at dist/index.js. Run npm run build.` + `A skipped lane is recorded as blocked, not as a pass.` |
| Disabled — a lane blocked by a missing prerequisite | the `mcp` and `cli` groups | `0 of 5 proven, 5 blocked`, each row's reason adjacent |
| Loading — a lane mid-run | the normal run | `running control (1 of 4 lanes)` — named lanes, never a bare spinner |
| Empty — nothing reported | stub lane | `stub exited 0 without recording a single row. Treated as not run.` |
| Overflow — a long route name | `awk` column widths | truncated in the row, printed in full in the detail below it |
| Default / Success — every row proven | **not reachable today** | would require 74 of 74. Deliberately unverified: faking it would need a fake manifest, and this file would then record a state the gate has never produced |

The single copy decision worth recording: the partial state says **"This is NOT a pass"** in words
rather than relying on the exit code. Exit codes are read by CI; the sentence is for the person who
ran it in a terminal, saw 50 green rows, and would otherwise stop reading.

---

## The three review gates, and the numbers they moved

`codex: usage limit -> claude (downgrade)` — the out-of-family lane is account-limited until
Aug 20 and `codex exec` exits 0 on that limit, so all three gates ran in-family as fresh
adversarial `claude -p` opus-5 reviewers. Every reviewer in this pipeline is therefore Claude
auditing Claude, which is a real weakness on the one item whose output would justify a cutover.

All three returned **REJECT**. None of them disputed the refusal to cut over; all three disputed
the coverage number, which was the right target.

| Gate | Verdict | Findings | Non-empty output |
|---|---|---|---|
| Spec review | REJECT | 13 | 5,894 bytes |
| Plan review | REJECT | 13 | 7,070 bytes |
| Phase D completeness critic | REJECT | 15 | 8,850 bytes |

The output size is recorded because an empty reviewer file is the failure mode this fleet was
warned about: a gate keyed on an exit code records a pass for a review that never ran.

### New clauses the reviews created

| # | Criterion | Evidence type | Result |
|---|---|---|---|
| A16 | A `proven-by-suite` row's cited test is EXECUTED, not merely present on disk | red-green | `parity-suite.sh` runs all 8 citations; all pass. Against a fabricated name it reports `matched NO test — a green zero, not a pass` and fails the row |
| A17 | A lane's own weaker claim survives reconciliation | red-green | The token set is closed: only `ok` proves. Previously a lane recording `blocked` was counted **proven**, because only `fail` was treated as negative |
| A18 | A result may not be credited to a row in another group | measurement | Reconciliation matches group AND id. This immediately surfaced the pool lane writing `div-r2-d6` — a `divergence` row — under the `pool` group |
| A19 | A route dispatched in a shape the extractor cannot read is caught | red-green | An independent dispatch-line count. Adding `if (pathname === '/oauth-callback' …)` to `src/control.ts` produced `16 dispatch lines but 15 routes could be extracted`; `src/control.ts` restored and re-verified clean |
| A20 | Two failures may not compare equal | inspection | A `000` from an unreachable reference now exits 2 rather than being diffed against a failing oracle |
| A21 | A fixture's HTTP status is asserted, not just captured | red-green | Compared against `planning/parity/fixture-status.tsv`; a status change fails the row even when the body is byte-identical |

### What is still weak, stated rather than hidden

- 39 of 81 rows are mechanically derived from source; **42 are hand-maintained**. Deleting one of
  those 42 raises the coverage fraction and no guard fires. Reported as **D-n**.
- `proven` means three different strengths of claim across the `control`, `fixture` and `pool`
  groups. Per-group reporting mitigates it; one headline number still spans them.
- **Nothing runs this gate** — no Makefile target, no CI job. Deliberate, since a deliberately
  failing gate in CI would redden `main` permanently, but it means the harness works only when
  someone remembers to run it.
