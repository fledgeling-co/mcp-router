# G5 gap-fix 2 — the note that measured its own denominator and lost itself doing it

**Branch** `ai/g5` · **Base** gap-fix 1's tip `090056e` · **Status** ready to verify — not verified
here.

Documents only, and narrower than gap-fix 1: **no vendored tree, no pin, no gate, no campaign data.**
`git status planning/test-campaign/` is empty and stays empty. Three files changed —
`planning/progress/G5-gapfix.md`, `ORCHESTRATOR.md`, `planning/features-to-triage/LEDGER.md` — plus
this note.

---

## BL-1 — the progress note was not in the working tree

`git status` opened this pass with `planning/progress/G5-gapfix.md` **deleted**. The commit was
intact; the file that `ORCHESTRATOR.md` and `LEDGER.md` both point at was simply not on disk, and
gap-fix 1's sweep reads all four documents from disk, so in that state it raises `FileNotFoundError`
rather than a failing assertion — it does not report a missing document, it stops being a sweep.

`git checkout -- planning/progress/G5-gapfix.md` restored it, and the restored file is **byte-identical
to the commit**: `sha256 bbe4530f21949391a73b70bc2976e452ab66fb9af3035b6f4fe78d5d96ea3b73` from the
working tree and from `git show HEAD:` alike, `git diff HEAD` empty. Nothing was lost but the file's
presence.

**The cause is the measurement, and it is worth naming rather than fixing quietly.** Gap-fix 1
isolated a denominator shift — swiftformat reporting 285 skipped files against 284 at the delivered
tip — by moving the new document out of the tree and running the same command again. That is the
right technique, and it is why the 285 figure is trustworthy. The document never came back.

**No reading in gap-fix 1's gate table is affected, and that is measured rather than assumed.** All
five saved `make lint` captures under `/tmp/g5gf/` (gone) — 15:31, 15:37, 15:43, 15:48 and 15:52 — read
`0/542 files require formatting, 285 files skipped`. Every gate whose output that table records ran
with the file present; the 284 probe saved no capture and ran after the last of them. So the window
in which the tree was missing its own record contains no recorded gate.

A line saying so is now in `G5-gapfix.md`, in the Gates section beside the denominator paragraph that
caused it.

## BL-2 — a stated measurement that had gone stale

The backtick-parity paragraph read *"`LEDGER.md` reads **1205** backticks now against **1193** both at
the delivered tip `64e1631` and on current `main`"*. The `main` half is false, and the interesting
part is that it was **true when it was written**:

| `main` at | time | `LEDGER.md` backticks |
|---|---|---|
| `41fe42f` | 15:25 | **1193** |
| `54666f7` | 15:42 | 1203 |
| `6051f4b` | 15:47 | 1189 |
| `3a9b641` | 15:51 | 1172 |
| `eadccf9` | 15:54 | 1152 |
| `a6fd1e6` | 16:01 | 1128 |
| `d57ecdb` | 16:03 | 1141 |
| `43e4199` | 16:07 | 1147 |
| `adfa923` | 16:09 | 1161 |

Gap-fix 1 measured `main` at 15:25 and wrote the number down; another session committed to `main`
eight times in the following 45 minutes. The verifier read 1128, this pass reads 1161, and both are
right about the `main` in front of them.

So the clause is withdrawn rather than re-numbered. **A parity claim names what a branch adds to its
own base**, and the base — `64e1631` at 1193 — is the only figure the argument needs. `main` was never
load-bearing, and a reference that moves nine times in 45 minutes cannot be quoted as a fixed point.
**The number is withdrawn; the argument is untouched.**

## BL-3 — a present-tense claim about a cache that has moved

The **DISPATCH — WORKTREE SUBMODULE** hazard row said *"the pin's 0.5.0 and the cache's **0.9.1** both
read 58 of 76"*. The measurement is right and the tense is not: 0.9.1 is a version the cache once held,
not what the cache holds.

Measured here against a `cp -R` copy of the registry under `/tmp/g5gf2/` (gone), so the campaign directory was
never the target:

| cache tree | `.claude-plugin/plugin.json` | `strict-check.py` on today's registry |
|---|---|---|
| `0.9.2` | `0.9.2` | 62 of 76 (82%) |
| `0.9.3` | `0.9.3` | 62 of 76 (82%) |
| `0.9.4` | `0.9.4` | 62 of 76 (82%) |
| `0.9.6` | `0.9.6` | **62 of 76 (82%)**, ratchet 58 |

The row now says that 0.9.1 names a version rather than the cache's current state, and that each version
from 0.9.2 on reads 62 against the ratchet's 58. The trap it describes is unchanged — it is a property of
every version through 0.9.1, and it sits behind the cache rather than in it.

> **Corrected at gap-fix 3.** This section originally labelled `0.9.6` *"newest"* and had the rewritten
> hazard row say *"the cache holds 0.9.6 today"* — a present-tense claim about a cache four agents write
> to, written at 16:18 and false by 17:38 the same day, when the cache took `0.9.8`. **It restaged the
> defect this pass had just fixed one section above**, where BL-2 withdraws a moving reference rather than
> re-numbering it. Re-numbering to `0.9.8` would have restarted the same clock, so the claim is withdrawn
> instead: the version column above is a reading per named version, taken at gap-fix 2 and re-taken at
> gap-fix 3, and what the cache holds now is read with
> `jq -r '.plugins["test-campaign@fledgeling-plugins"][0].version' ~/.claude/plugins/installed_plugins.json`
> rather than quoted here. At gap-fix 3 that read `0.9.8`, which reads 62 of 76 like every version from
> 0.9.2 on. See `planning/progress/G5-gapfix-3.md`.

## Registered, not fixed

Four rows added to **Deferred children** in `ORCHESTRATOR.md`. The first three are the verifier's; the
fourth was found here.

- **`D-g5-a`** — the absent half of gap-fix 1's sweep was never repository surface, and its corpus was
  four hand-listed files. `planning/claim-sweep.py` is the tool for that job and is on `main`, not on
  this branch. The verifier ran the corpus check over 1366 tracked files and nothing leaked. **Recorded
  as luck confirmed afterwards rather than as coverage.**
- **`D-g5-b`** — the sweep's fixed point is per-file, not general. Control W1 is quoted unwrapped at
  `G5-gapfix.md:84`, which is safe only because each control is keyed to one file and W1 guards
  `G5.md`. A corpus-wide sweep would collapse on it.
- **`D-g5-c`** — `strict-ratchet.json` holds `"checked": 58, "total": 70` and should read 62. Already
  in three documents; given an id so it can be pointed at. `planning/test-campaign/` belongs to another
  session.
- **`D-g5-d`** — *found here.* Documents call the installed version `0.9.4`, and the tree behind the
  label carries **two manifests that disagree**: `.claude-plugin/plugin.json` reads `0.9.4` while the
  top-level `plugin.json` reads `0.9.3`. An upstream packaging slip, not this repository's. **The
  readings stand and only the label is wrong**, so the rows are left as records of what was measured
  when they were written. *Written here as "two documents"; **four** carry it in ten places, corrected
  in the register row at gap-fix 3. The label also named an instant rather than a state — the install
  moved to `0.9.8` the same evening — so the count was corrected and the ten labels were left alone.*

## The sweep

Gap-fix 1's sweep at `/tmp/g5gf/sweep.py` (gone) is **unchanged and re-run against the edited tree** — 27
present, 2 absent, 11 controls, exit 0. Leaving it alone is deliberate: its note describes it by those
counts, and editing it would make that description stale while removing the evidence that this pass did
not break gap-fix 1's corrections.

This pass has its own at `/tmp/g5gf2/sweep2.py` (gone), same shape, over the three corrections and the four
register rows: **14 present, 2 absent, 8 controls, exit 0.**

**Armed in both directions rather than asserted.** `grep -Fc` returns **0** on all three wrap controls
and the sweep returns 1 on each, so the wrap tolerance is demonstrated rather than claimed. Against a
mutated copy carrying four planted faults — the two withdrawn clauses reinstated, one present string
shortened and one wrap control unwrapped — it printed **exactly four `FAIL` rows and exited 1**, every
other row still `ok`. A sweep that failed everything would be no better evidence than one that failed
nothing.

**Its assertions are keyed per file, and here that is load-bearing.** This note quotes both withdrawn
clauses, because they are the subject of the sections that withdraw them, so an absent-check run over a
corpus would collapse on the document reporting the withdrawal. That is `D-g5-b`'s property met by
construction rather than by luck — and it is why `D-g5-b` is worth registering: the property is a
consequence of the keying, not of the phrasing.

Neither sweep is committed, for the reason gap-fix 1 gives: a checker for one commit's prose is not
repository surface. That reason is exactly what `D-g5-a` qualifies.

## Gates

**No gate was re-run beyond the two the work order names.** Nothing in this pass touches Swift, the
vendored tree, the pin or the campaign, and re-vendoring or re-running the suite would put this item's
strongest evidence back in question for no reading it could change.

| Gate | Read | Acceptance |
|---|---|---|
| `planning/ledger-reconcile.py` | **reconciled — no findings across A–L**, exit 0 | 0 across A–L ✔ |
| `/tmp/g5gf/sweep.py` — gap-fix 1's, unchanged | 27 present, 2 absent, 11 controls, **exit 0** | exit 0 ✔ |
| `/tmp/g5gf2/sweep2.py` (gone) — this pass's | 14 present, 2 absent, 8 controls, **exit 0** | exit 0 ✔ |

**Every denominator the reconciler moved is accounted for by the four register rows.** Against gap-fix
1's saved capture at 15:52:

| Reconciler counter | gap-fix 1 | now | delta |
|---|---|---|---|
| J — table rows in both files | 480 | 484 | **+4** |
| K — deferred-register rows | 213 | 217 | **+4** |
| L — lines in both files | 1812 | 1816 | **+4** |
| H — rows with a status cell | 88, 21 skipped | 88, 21 skipped | **0** |
| merged `ai/*` branches | 27 | 29 | +2, **not this branch's** |

H not moving is the check that the new rows are shaped right: `D-<parent>-<letter>` rows carry four
cells and are excluded from the status check by design, so four additions that left H at 88 are four
rows in the register's own shape. The branch count moved because `main` gained two merges from other
sessions during this pass.

**The backtick warning persists and its parity is again unchanged.** The reconciler now reads
`LEDGER.md odd number of backtick quotes (1207)` against gap-fix 1's 1205: this pass adds **2**, an even
number, so it cannot have changed whether the count is odd. The pointer text was written that way on
purpose — a documents-only pass should not make a pre-existing warning disappear, because a warning that
vanishes without being fixed is indistinguishable from one that was.

## Open

**`D-g5-a` through `D-g5-d` are registered and none is fixed here**, by instruction for the first three
and by scope for the fourth.

**`strict-ratchet.json` still holds 58.** Unchanged from gap-fix 1, and still the campaign owner's.

**X7 and X8 are untouched**, as in both earlier passes. Editable here since G5; closable only upstream.
