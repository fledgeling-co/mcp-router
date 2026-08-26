# G5 gap-fix 3 — the rule the document derives, applied to the claim it broke

**Branch** `ai/g5` · **Base** `a9603e5` · **Status** ready to verify — not verified here.

Documents only. Four documents changed, no vendored file, no pin, no gate, no campaign data. The
vendored tree still checksums `b9acf61682d9757616c6e0cc15924e4137c5839c13d6a749d8093e3065977ce9`
over 85 files, and `planning/test-campaign/` is untouched by `git status` and by digest.

---

## BL-1 — a moving reference, withdrawn instead of re-numbered

Gap-fix 2 corrected the **DISPATCH — WORKTREE SUBMODULE** hazard row's tense, and replaced one
present-tense claim about the plugin cache with another: *"it holds `0.9.6` today"*, written at
16:18 and false by 17:38 the same evening. One section above, the same document derives the rule
that a reference which moves cannot be quoted as a fixed point and must be **withdrawn rather than
re-numbered** — and applies it to `main`. The row then re-numbered a cache four agents write to.

Re-measured here at 18:30 on 2026-08-22, and again at 18:22 an hour before that — same answer:

```
jq -r '.plugins["test-campaign@fledgeling-plugins"][0].version' ~/.claude/plugins/installed_plugins.json
  → 0.9.8            lastUpdated 2026-08-22T07:38:26.730Z   (17:38 local)

ls ~/.claude/plugins/cache/fledgeling-plugins/test-campaign
  → 0.5.0 0.6.0 0.8.0 0.9.1 0.9.2 0.9.3 0.9.4 0.9.6 0.9.8     nine versions
     0.9.6 born 2026-08-22 15:19:05 · 0.9.8 born 2026-08-22 17:38:26
```

So `0.9.8` is what the number would become, and writing it down would restart the same clock on a
one-day fuse. **The claim is withdrawn.** What replaces it is the reading per *named* version, which
does not move, plus the command that reads the cache for anyone who needs today's state.

Every version measured against a `cp -R` copy of the registry at `/tmp/g5gf3/tc`, so the campaign
directory was never the target:

| version | `effect-witness` in `strict-check.py` | reading on this registry |
|---|---|---|
| `0.5.0` | 0× | 58 of 76 (76%) |
| `0.9.1` | 0× | 58 of 76 (76%) |
| `0.9.2` | 2× | **62 of 76 (82%)** |
| `0.9.3` | 2× | **62 of 76 (82%)** |
| `0.9.4` | 2× | **62 of 76 (82%)** |
| `0.9.6` | 2× | **62 of 76 (82%)** |
| `0.9.8` | 2× | **62 of 76 (82%)** |
| `vendor/test-campaign` (0.9.2) | 2× | **62 of 76 (82%)** |

The ratchet reads `"checked": 58, "total": 70`. `0.9.8` changes nothing: the trap the row describes
is a property of every version through `0.9.1`, and the vendored `0.9.2` is the only reading in that
table that cannot move, because it is checksummed.

Withdrawn verbatim, so the sweep's controls have something real to guard and a later reader can
see what the strings were:

- `ORCHESTRATOR.md:571` — *"it holds 0.9.6 today"*, and its dependent clause *"and 0.9.6 reads 62 of
  76 (82%) against the ratchet's 58"*.
- `ORCHESTRATOR.md:751` — *"the cache's current 0.9.6 included"*.
- `ORCHESTRATOR.md:752` — *"It is stale — the cache's newest version is 0.9.6"*.
- `G5-gapfix-2.md:80` — the table label *"— newest"*, and *"the cache holds 0.9.6 today"* at `:83`.
- `G5-gapfix-2.md:112` — *"Two documents call the installed version 0.9.4. It is stale"*.

**Four sites carried the claim, not three.** The brief named `ORCHESTRATOR.md:571`, `:752` and
`G5-gapfix-2.md:80`. `ORCHESTRATOR.md:751` — the `D-g5-c` register row — also read *"the cache's
current 0.9.6 included"*, and `G5-gapfix-2.md:112`, the summary bullet for `D-g5-d`, carried the
same *"it is stale"* framing. All are rewritten; the two progress-note sites keep what was written
and add a marked correction beneath it, because a note that quietly acquires the right answer stops
being a record of what happened.

> **Corrected at gap-fix 4**, per the gap-fix 3 verdict's F3. The heading says _four_ and the
> sentence beneath it names two sites _beyond the brief's three_, which is five — matching the
> five-entry list above it. Both readings are reachable: `G5-gapfix-2.md:112` carries the `0.9.4`
> staleness claim rather than the `0.9.6` one, so scoping "the claim" to `0.9.6` gives four. But then
> that site is not an addition to the brief's three and does not belong in the sentence that says it
> is. **Five sites were rewritten; four of them carried the `0.9.6` claim.** The count above is left
> as written with the correction marked beneath, by the convention this paragraph states one line
> earlier.

## BL-2 — `D-g5-d` said two documents; four carry the label, in ten places

Counted over tracked Markdown at `a9603e5`, excluding the vendored tree:

```
ORCHESTRATOR.md:314                              the G5 row, in the same file as the register row
planning/features-to-triage/LEDGER.md:67, :295
planning/progress/G5.md:76, :94, :123, :143, :159, :163
planning/progress/G5-gapfix.md:22
```

The row named only `G5-gapfix.md`'s four-version table and the `LEDGER.md` G5 row. `G5.md:159` is the
sharpest of the ten because it asserts what `installed_plugins.json` *records*, in the present tense,
and that file has read `0.9.8` since 17:38.

**The count is corrected and the ten labels are left alone**, which is the same rule as BL-1: the
label names an instant that has passed, and re-numbering ten sites to `0.9.8` would put ten new fuses
in the repository. The register row now carries the list, so the label can be pointed at when the
campaign owner raises it. Registered, not fixed — as before.

The row's other half is re-measured and holds, and it recurs one version further on:

```
0.9.4   top-level plugin.json 0.9.3   .claude-plugin/plugin.json 0.9.4    disagree
0.9.8   top-level plugin.json 0.9.7   .claude-plugin/plugin.json 0.9.8    disagree
diff -rq 0.9.3/skills 0.9.4/skills → one file, vacuity-check.cpython-314.pyc
```

That makes it an upstream packaging pattern rather than one slip, and it belongs upstream with X7 and
X8. The row now says so.

## BL-3 — a recorded output the command does not print

`G5.md:19` recorded `→ no differences` beneath a `diff -r --exclude=__pycache__`. Run today it prints
two lines:

```
Only in …/cache/fledgeling-plugins/test-campaign/0.9.2: .in_use
Only in …/cache/fledgeling-plugins/test-campaign/0.9.2: .orphaned_at
```

`--exclude` matches basenames, so `__pycache__` was the only thing that flag removed. What the two
lines name is the harness's own bookkeeping — a `.in_use` lock directory holding PIDs `41169` and
`62113`, and an `.orphaned_at` marker — four filesystem entries, every one created on **2026-08-21**,
a day before this vendoring:

```
.in_use            2026-08-21 00:21:17      .in_use/41169   2026-08-21 13:28:16
.orphaned_at       2026-08-21 14:38:41      .in_use/62113   2026-08-21 14:16:35
```

So the command as written could not have printed what was recorded beneath it; the `→` was an
annotation of the conclusion. **The conclusion is right** — the block now carries the command that
actually returns exit 0 and no output, and says why the old one did not.

## BL-4 — a reproduction instruction that does not reproduce

`vendor/README.md:35` documented `tar -x -C /tmp/tc-check` with nothing creating the directory:

```
git -C "$UP" archive 28ecd67… plugins/test-campaign | tar -x -C /tmp/tc-check --strip-components=2
  → tar: could not chdir to '/tmp/tc-check'          exit 1
```

This matters more than its size: it is the procedure an X7/X8 upstream fix gets re-pulled and
re-checked with. `rm -rf … && mkdir -p …` is now the first line — `rm -rf` rather than a bare `mkdir
-p` because the second run of this procedure meets a directory the first one filled, and diffing a
new archive into a stale extract compares against the wrong tree. The cache comparison and the
"read the cache, don't quote it" note were added beside it.

Every command in that file was then run verbatim from the file:

```
checksum block          b9acf61682d9757616c6e0cc15924e4137c5839c13d6a749d8093e3065977ce9   85 files
archive block           diff -r /tmp/tc-check vendor/test-campaign      → exit 0, no output
archive block, re-run   into the directory the first run left           → exit 0, no output
cache block             diff -r --exclude=… vendor/test-campaign "$C"   → exit 0, no output
```

---

## The checksum, re-derived three ways

Not asked for, and re-run because everything above rests on it being a fixed point:

```
worktree   cd vendor/test-campaign && find . -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256
           b9acf61682d9757616c6e0cc15924e4137c5839c13d6a749d8093e3065977ce9      85 files

cache      ~/.claude/plugins/cache/fledgeling-plugins/test-campaign/0.9.2
           b9acf61682d9757616c6e0cc15924e4137c5839c13d6a749d8093e3065977ce9
           (excluding __pycache__/, .in_use/ and .orphaned_at)

upstream   git archive 28ecd6753386ff6d480a98d6646a5b73c62dc299 plugins/test-campaign
           b9acf61682d9757616c6e0cc15924e4137c5839c13d6a749d8093e3065977ce9      85 files
           diff -r against vendor/test-campaign  →  exit 0, 0 lines
```

## Gates

Measured on this branch tip at load 156–191, so no timing here is representative.

| Gate | Read | Acceptance |
|---|---|---|
| `make lint` | **exit 0** | exit 0 ✔ |
| `make lint` — swiftformat | **0/542 files require formatting**, 288 skipped | 0/542 ✔ |
| `make lint` — swiftlint | **0 violations, 0 serious in 535 files** | 0 ✔ |
| `make lint` — `no-raw-design-values` | clean, 77 files under the rules of 118 scanned | clean ✔ |
| `make lint` — `no-wire-codable` | clean, 2 exemptions | — |
| `make lint` — `no-harness-config-writes` | 327 examined, 8 name a config, 22 write, 8 in the seam, none writes one | — |
| `make lint` — selftest | **27 case(s) held** | held ✔ |
| `planning/ledger-reconcile.py` | **exit 1** — check E, `G4-B (ai/g4b)` | pre-existing, see below |
| `/tmp/g5gf3/sweep3.py` (gone) | 22 present, 9 absent, 5 controls, **exit 0**; 7 planted faults give 10 `FAIL` | exit 0 ✔ |
| `vendor/test-campaign` checksum | `b9acf616…`, three ways | matches ✔ |

**The reconciler's exit 1 is not this pass's.** Run against a detached worktree at `a9603e5` and
against the working tree, its output is identical but for one line:

```
HEAD  exit 1 … warning: LEDGER.md odd number of backtick quotes (1207)
now   exit 1 … warning: LEDGER.md odd number of backtick quotes (1209)
```

Check **E** — *a branch merged into `main` with no row in either file: `G4-B (ai/g4b)`* — fires at
both, because `main` merged G4-B after this branch's base. `G4-B` and `ai/g4b` appear **zero** times
in either file at `a9603e5` and zero times now, and the row-id sets are identical across the edit
(370 ids in `ORCHESTRATOR.md`, 95 in `LEDGER.md`). The verifier's F5 recorded the same thing, and it
was clean on the merged tree.

The backtick count moves **1207 → 1209** and the odd-parity warning persists, which is BL-2 of
gap-fix 2 behaving as it was reasoned to: the count is a whole-file property, the branch's
contribution is the `gap-fix 3 at \`planning/progress/G5-gapfix-3.md\`` pointer, and an even delta
cannot clear an odd count.

`null-run-gate.py` and `reader-accounting.py` were **not run — they do not exist on this branch.**
Both are on `main` (`planning/null-run-gate.py`, `planning/reader-accounting.py`) and reached the
verifier's readings through the merged tree, not through `ai/g5`. `make all` was excluded by the
brief. `parity-manifest-check.sh` touches no path this pass changes and `D-r17-d` has it false-REDing
under this concurrency; not re-run.

## The sweep

`/tmp/g5gf3/sweep3.py` (gone) — **22 present, 9 absent, 5 controls, exit 0** against the tree. Needles are
matched with runs of whitespace collapsed to one space, so a claim that hard-wraps mid-sentence is
still found.

The absent rows are the point of this pass: each withdrawn claim must be gone, **including the
re-numbered form** — `it holds 0.9.8 today` is asserted absent as well as `it holds 0.9.6 today`,
because what is being fixed is re-numbering, not the number.

The five controls guard the withdrawn strings that are quoted **on purpose** in this note and in
gap-fix 2's correction block, so an over-eager absent row cannot pass by deleting the record of what
was withdrawn. Each control is keyed to one file — `D-g5-b`'s limit, and still true here.

**A fixture proves only the faults it carries**, so the sweep was run against a mutated copy at
`/tmp/g5gf3/mut/` (gone) with seven faults planted. Seven faults, **ten `FAIL` rows, exit 1**, every other
row `ok` — and all five controls still `ok`, which is what distinguishes a control from noise:

| planted | rows it fired |
|---|---|
| M1 `it holds 0.9.6 today` reinstated at `:571` | `absent` ORCH:571 quotes a current version · `present` ORCH:571 states the rule |
| M2 the same claim **re-numbered** to `0.9.8` | `absent` ORCH:571 re-numbered the moving reference |
| M3 `D-g5-d` reverted to *"Two documents"* | `absent` D-g5-d says two · `present` D-g5-d says four in ten |
| M4 `G5.md`'s diff block reverted | `absent` G5.md records an unprintable output · `present` G5.md's excludes |
| M5 the `mkdir` dropped from `vendor/README.md` | `present` vendor/README.md creates the extract directory |
| M6 the *"— newest"* table label reinstated | `absent` gap-fix 2's table labels a row newest |
| M7 the gap-fix 3 pointer dropped from `LEDGER.md` | `present` LEDGER G5 row points at this pass |

Four needles are invisible to a line-anchored search and visible to the sweep, so the wrap tolerance
is measured rather than asserted:

```
W1  ORCHESTRATOR.md                   line-anchored=0  wrap-tolerant=1   the checksum anchor
W2  ORCHESTRATOR.md                   line-anchored=0  wrap-tolerant=1   D-g5-c per named version
W3  planning/progress/G5-gapfix-2.md  line-anchored=0  wrap-tolerant=1   the defect class named
W4  planning/progress/G5-gapfix-3.md  line-anchored=0  wrap-tolerant=1   the re-numbered form guarded
```

## Not touched

`planning/test-campaign/` is clean by `git status`, and `cases.json` and `strict-ratchet.json` are
unchanged by digest before and after every reading:

```
cases.json           d5ae0330c74e93e8c1c71a8e57497beaefa5f427081bb17930e32b7db3f1800f
strict-ratchet.json  ba7be05ec91bb1ba502df733b647aade0c5a71d66cb300321201d185c7461fbc
```

Nothing under `vendor/test-campaign/` was edited — `vendor/README.md` sits beside it, not inside it,
and the tree checksum is unchanged. The submodule was left uninitialised. `strict-ratchet.json` still
holds 58; that is `D-g5-c` and the campaign owner's.

## Observed and left alone

- `planning/progress/G5-gapfix.md:61` describes the sentence gap-fix 1 added to the hazard row,
  including *"the cache's 0.9.1"*. It is a past-tense record of what that pass wrote, and gap-fix 2's
  own BL-3 section quotes the same sentence as the thing it corrected, so the chain is readable.
- `planning/features-to-triage/G5-vendor-the-campaign-version-the-gates-run.md:17` says `0.9.2` is
  *"installed in the machine's plugin cache"*, under a **Measured 2026-08-22** heading. Its subject —
  the version every reported gate actually ran — is historical and does not move.
- The ten `0.9.4` labels themselves, per BL-2 above. `D-g5-d` now lists them.
