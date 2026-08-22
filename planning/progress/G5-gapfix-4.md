# G5 gap-fix 4 — the label bound a number to a machine that moves hourly

**Branch** `ai/g5` · **Base** `43b44a2` · **Status** ready to verify — not verified here.

Twelve sites across six files bound a version number to the word **installed**. All twelve are
rewritten to name the version and drop the adjective. The rule is the one these documents already
owned and had applied to the cache claim alone: a reading belongs to a **named version**, and which
version is installed is a question answered with a command. Seven further sites use *installed* with
no number; those name a role rather than a value, cannot rot, and are untouched.

The guard is `planning/installed-claim-sweep.py`, committed. It goes **13 blocking rows → 0** across
this edit, and it is keyed on a version-shaped token rather than on any number, so re-numbering a
caught site to the next release trips the identical row.

Nothing here moves a measurement. The readings, the pin, the checksum and every gate are where
gap-fix 3 left them.

---

## Why the label is a defect and re-numbering is not the fix

`installed 0.9.4` reads as a label and behaves as an assertion about this machine right now. The
plugin cache is a directory four agents write to, and on 2026-08-22 it took four versions:

```
0.9.4  dir mtime  22 Aug 15:19          installed_plugins.json, read 2026-08-22T10:27:46Z:
0.9.6  dir mtime  22 Aug 17:38            .version      0.9.9
0.9.8  dir mtime  22 Aug 19:54            .lastUpdated  2026-08-22T09:54:03.754Z
0.9.9  dir mtime  22 Aug 19:54            file mtime    22 Aug 19:54
                                          occurrences of 0.9.4 in that file: 0
```

Gap-fix 3's verification blocked on `G5.md:159` at `a9603e5` (`:170` at `43b44a2`), which asserted
that `installed_plugins.json` **records 0.9.4 since 2026-08-21**. It records `0.9.9` and contains no
`0.9.4` at all. Writing `0.9.9` there would have been the third re-numbering of one claim inside a
day, and the cadence above says how long it would have lasted.

The distinction that makes the fix cheap: **`0.9.4 reads 62 of 76` cannot rot** — the tree is on disk
and re-reads the same, which arm 3 of the gap-fix 3 verdict re-derived across nine versions.
**`installed 0.9.4 reads 62 of 76` rots the moment the cache moves**, and takes the reading's
credibility with it. So the readings survive intact once the adjective goes. Nothing had to be
re-measured and nothing was.

## What was found, and how each class was treated

Counted by `planning/installed-claim-sweep.py` over 1,126 tracked text files at `43b44a2`, excluding
the 85 files of `vendor/test-campaign/`.

**Twelve sites bind a version number to *installed*, in six files.** Thirteen blocking rows, because
`M28-decision-docket.md:244` binds in both directions within one sentence.

| Site at `43b44a2` | Bound | Now reads |
|---|---|---|
| `ORCHESTRATOR.md:314` | `installed 0.9.4` | ``Identical to what `0.9.4` gives on the same data.`` |
| `ORCHESTRATOR.md:752` | `installed campaign version 0.9.4` | the `D-g5-d` heading, rewritten — see below |
| `planning/features-to-triage/LEDGER.md:67` | `installed 0.9.4` | ``the same numbers `0.9.4` gives`` |
| `planning/features-to-triage/LEDGER.md:295` | `installed 0.9.4` | `0.9.2 and 0.9.4 both` |
| `planning/features-to-triage/M28-decision-docket.md:244` | `the installed cache says 0.9.2` | *the cache copy every gate this campaign reports actually ran is `0.9.2`* |
| `planning/features-to-triage/G5-vendor-…-gates-run.md:17` | `Installed in the machine's plugin cache \| 0.9.2` | *What every gate this campaign reports actually ran, from the machine's plugin cache* |
| `planning/progress/G5.md:87` | `Installed 0.9.4, same data` | `0.9.4, same data` |
| `planning/progress/G5.md:105` | `0.9.4 — installed` | `0.9.4 — a later cache copy` |
| `planning/progress/G5.md:134` | `installed 0.9.4` | `0.9.4 — a later cache copy` |
| `planning/progress/G5.md:154` | `the installed 0.9.4 reads` | `0.9.4 reads` |
| `planning/progress/G5.md:170` | ``installed_plugins.json` records 0.9.4` ` | withdrawn; the `jq` command replaces it |
| `planning/progress/G5-gapfix.md:22` | `0.9.4 — installed` | `0.9.4 — a later cache copy` |

**Seven sites use *installed* with no number and are untouched.** Five existed at `43b44a2` —
`G5.md:8` (*"what the installed version returns"*), `G5.md:178` (*"still loads the installed
version"*), `G5-gapfix-3.md:267`, and `vendor/README.md:5` and `:75` (*"whatever version happens to
be installed on the machine"*). This edit adds two more of the same shape, at `G5.md:107` and
`G5-gapfix.md:27`, because that is the form the fix is modelled on. The guard counts them as `role`
and reports them rather than reddening: a gate that banned the word would push these documents away
from the correct answer.

**Two sites quote a withdrawn claim and stay as records.** `G5-gapfix-2.md:112` and
`G5-gapfix-3.md:60` are a past pass's account of the defect — one registering it, one quoting the
registration verbatim inside a *Withdrawn verbatim* list. Their truth does not depend on what the
cache holds, and rewriting them would erase the record of what the strings were. The guard classes
hits in those two files as `record`, reported with file and line, never blocking.

**One of `D-g5-d`'s ten citations was already correct and was left.** `G5.md:163` at `a9603e5`
(`:174` at `43b44a2`) reads *"it reproduces 0.9.4's numbers on this data"* — a named version with no
adjective on it. Nine of the ten bound; the tenth did not.

### Two counts the brief and the verdict each had slightly wrong

The brief listed **four** binding sites in `G5.md`. There are **five**: `:87` carries
`Installed 0.9.4, same data` in a table header, with a capital I, and a sweep looking for the
lowercase string does not see it. It is fixed with the other four.

The gap-fix 3 verdict's F5 cites the vendor triage row at `:16`. It is at **`:17`**, at `a9603e5`
and at `43b44a2` alike, so that citation resolves at neither frame. Gap-fix 3's own note cites `:17`
correctly at its `:266`. Recorded rather than acted on, since the row itself is fixed either way.

## The frame on `D-g5-d`'s citations

The brief's correction of 2026-08-23 withdrew an instruction to re-number `G5.md:159` to `:170`, and
it is right. Checked with a presence control this time rather than three readings from one side of
the edit:

```
                                       @a9603e5   @43b44a2
ORCHESTRATOR.md:314                      HIT        HIT
LEDGER.md:67                             HIT        HIT
LEDGER.md:295                            HIT        HIT
G5.md:76  :94  :123  :143  :159  :163    HIT ×6     MISS ×6
G5-gapfix.md:22                          HIT        HIT

10/10 resolve at a9603e5 · 4/10 resolve at 43b44a2
```

All ten were true when written. Six stop resolving after gap-fix 3's own edit to `G5.md` added
eleven lines above them, and they stop resolving *silently* — a bare line number reads the same
whether or not it points at anything. So `D-g5-d`'s citation list now carries its frame,
**cited at `a9603e5`**, rather than being re-numbered to a tip that will move again. Re-numbering
would have produced a pointer that works today and fails the same way after the next edit.

The `D-g5-d` row is rewritten at the heading, the citation list and the disposition. Its heading no
longer binds a number to *installed*; its third column moves from `new item` to
`label fixed at G5 gap-fix 4; manifests upstream`. The manifest half — top-level `plugin.json` and
`.claude-plugin/plugin.json` disagreeing at `0.9.4` and again at `0.9.8` — is unchanged, belongs
upstream with X7 and X8, and is what keeps the row open.

## The guard

`planning/installed-claim-sweep.py`, committed, superseding rather than sitting beside
`planning/verification/G5-gapfix-3-sweep.py`: it carries that script's nine cache-claim patterns
forward and adds three of its own, so there is one instrument rather than two with a partial overlap.

Twelve blocking patterns, every one keyed on `\d+\.\d+\.\d+` with optional markdown emphasis rather
than on a literal number. `I1` and `I2` catch the binding in a sentence, in either order, through a
closed vocabulary of connectives. `T1` catches it across a markdown table's cell wall, which the
connective vocabulary excludes on purpose — a `|` between two words is a column boundary, not a
connective — and it is line-anchored, because a table row cannot wrap. `B1`–`B9` are gap-fix 3's.

Four classes, and only one of them blocks. `block` is prose only; `nonprose` reports the same
binding in Swift fixtures, the console mockup and `fleet-runner.js`, where a version beside an
`installed` field is sample data rather than a claim about this machine. `record` covers the two
notes whose job is to quote what was withdrawn. `role` counts the correct form.

The wrap-tolerant reader is `planning/claim-sweep.py`'s — R17's instrument, built after a hard wrap
hid a claim from `grep` four consecutive times, and it also handles the blockquote-marker case a
naive whitespace collapse misses. That file is on `main` and not on this branch, so the sweep imports
it when present and carries an inline copy otherwise, printing which path it took. On `ai/g5` it
prints `inline copy`.

### It fires, and it stays quiet on the correct form

Two proofs, because a gate that reds on nothing is indistinguishable from a gate that cannot fire.

`--selftest` runs the patterns against in-memory fixtures and is committed with the script, so a
later reader can re-run it without touching the tree:

```
$ python3 planning/installed-claim-sweep.py --selftest
selftest: 105 checks over 12 patterns
          21 defect samples, each of which must be caught
          7 correct forms, none of which may be caught
selftest: 105 case(s) held        exit 0
```

The seven correct forms are the load-bearing half: `G5.md:8`'s *"the installed version returns"*,
the fixed table row `| 0.9.4 - a later cache copy |`, a reading against a named version, a claim
bound to a past instant, and `installedAt: "2026-03-02…"`, which is a date rather than a version. A
guard that reddened on any of those would push the documents away from the fix.

The selftest found one real hole while being written: `B9` was written against the single em dash
that had actually gone wrong, and the hyphen form escaped it. `B9` now takes `[—–-]`.

Then the end-to-end run, which the selftest cannot prove — the `git ls-files` walk, the line numbers
and wrap tolerance, on real files. Each plant applied to the tracked tree and reverted:

```
plant                          exit   result  new blocking row
P1 the defect on a fresh fuse  1      CAUGHT  planning/progress/G5.md:105   installed 0.9.9
P2 the original string back    1      CAUGHT  planning/progress/G5.md:105   0.9.4 — installed
P3 the blocker, re-numbered    1      CAUGHT  planning/progress/G5.md:174   installed_plugins.json` records **0.9.9**
P4 a different file entirely   1      CAUGHT  ORCHESTRATOR.md:314   installed 1.0.0
P5 hard-wrapped mid-claim      1      CAUGHT  planning/progress/G5.md:107   installed 0.9.9
P6 the table-cell form         1      CAUGHT  planning/features-to-triage/G5-vendor-…:17   | Installed …
P7 an untouched third file     1      CAUGHT  planning/features-to-triage/LEDGER.md:67   installed 0.9.9
N1 correct: role, no number    0      held    —
N2 correct: named version      0      held    —

every planted file restored byte-for-byte: True
post-plant sweep: exit 0, 0 blocking
```

`P1` and `P3` are the defect on a fresh fuse: `0.9.9` is the version the cache took at 19:54, so a
document re-numbered to the then-current release during gap-fix 3's verification would have gone
stale the same evening, and the guard catches it as readily as `0.9.4`. `P5` crosses a hard wrap,
which is the failure that produced `claim-sweep.py` in the first place.

### What the guard does not check, stated rather than left to be discovered

`RECORDS` — this script, a gap-fix 4 verdict if one is written, and `vendor/test-campaign/` — are not
read at all, so a genuine re-assertion inside one of them is invisible here. That is the same trade
`claim-sweep.py` documents, and it is what keeps the output a fixed point when a progress note pastes
it.

`nonprose` is a judgement about file type rather than content: a real claim about this machine
written into a Swift comment would be reported and would not block. That is the deliberate cost of
keeping the Swift fixtures, which legitimately pair a version with an `installed` field, out of the
blocking set.

The connective vocabulary is closed, so a binding phrased with a word outside it — *"the deployed
0.9.4"*, *"running 0.9.4"* — is not caught. The `role` class exists partly to make that visible: an
*installed* with no binding and no version nearby is either correct or phrased around the guard.

## Gates

Measured on this worktree at the delivered tip. `make all` was excluded by the brief and the
submodule was left uninitialised.

| Gate | Read | Acceptance |
|---|---|---|
| `make lint` | **exit 0** | exit 0 ✔ |
| `make lint` — swiftlint | **0 violations, 0 serious in 535 files** | 0 ✔ |
| `make lint` — swiftformat | **0/542 files require formatting**, 290 skipped | 0/542 ✔ |
| `make lint` — `no-raw-design-values` | clean | clean ✔ |
| `make lint` — `no-harness-config-writes` | 327 examined, 8 name a config, 22 write, 8 in the seam, none writes one | — |
| `make lint` — selftest | **27 case(s) held** | held ✔ |
| `planning/installed-claim-sweep.py` | **blocking 0 · record 36 · nonprose 2 · role 825**, exit 0 | 0 blocking ✔ |
| `planning/installed-claim-sweep.py --selftest` | **105 case(s) held**, exit 0 | held ✔ |
| `planning/ledger-reconcile.py` | **exit 1**, check E, `G4-B (ai/g4b)` | pre-existing, see below |

The sweep row is measured with this note in the tree: it scans 1,127 files and 21 of the 36
`record` hits are this note's own quotations of what was withdrawn. `blocking 0` is the figure that
does not depend on that, and the base reads **13** under the same script.

**The reconciler's red is the base's, unchanged by this edit.** Run against a `git archive`
extraction of `43b44a2` with `.git` alongside it, the base exits **1** on the same check E with the
same single id. `G4-B` and `ai/g4b` appear **zero** times in either file at the base and zero times
now, this edit touches no line mentioning either, and 9 of the 10 checks are clean at both ends.
`main` merged G4-B after this branch's base, which is the mechanism the last two verdicts recorded.

The reconciler's backtick warning also predates this edit and stays odd on both sides:
`LEDGER.md` reads **1209** at the base and **1211** now, both odd, so the warning prints at both.
`ORCHESTRATOR.md` goes 6146 → 6172.

`parity-manifest-check.sh` was not run — it touches no path this edit changes, and `D-r17-d` has it
false-REDing under this machine's concurrency.

`planning/null-run-gate.py`, `planning/reader-accounting.py` and `planning/claim-sweep.py` are all on
`main` and absent from this branch, so none of them ran here. The sweep's inline reader exists for
exactly that reason.

## Not touched

`planning/test-campaign/` is clean by `git status` and no gate was re-run against it. Nothing under
`vendor/test-campaign/` was edited; the guard excludes its 85 files by name rather than reading them.
`strict-ratchet.json` still holds 58, which is `D-g5-c` and the campaign owner's. No measurement in
any of the seven edited documents was re-taken, because none of them changed.

One thing taken beyond the brief's scope, at the gap-fix 3 verifier's request: **F3**, the *"Four
sites carried the claim, not three"* heading in `G5-gapfix-3.md` that names five sites beneath
itself. Corrected in the marked-correction form that paragraph itself specifies one line earlier —
the count stays as written, with the correction in a blockquote beneath it, because a note that
quietly acquires the right answer stops being a record. The same treatment is applied to
`G5-gapfix.md`'s table.

## Open

`D-g5-d` stays open on its second half, the two manifests that disagree; nothing about it changed
here. `strict-ratchet.json`'s 58 is still the campaign owner's to raise.

Whether this guard should also run in `make lint` is not decided here. It is committed and
re-runnable, and adding it to the target would make every future document edit answerable to it —
which is the point of writing it, but is a change to a gate this item does not own.
