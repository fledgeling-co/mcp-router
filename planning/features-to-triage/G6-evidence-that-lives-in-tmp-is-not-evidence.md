---
status: to-triage
found-by: the 08:55:13Z crash, 2026-08-23
---

# A sweep that proves a guard is armed, kept in `/tmp`

Every `/tmp` artifact this fleet cited is gone. Measured 2026-08-23, after the terminal died:

| Path | Cited by | State |
|---|---|---|
| `/tmp/g5gf3/sweep3.py` | G5 gap-fix 3's report; **`G5V2`'s verify brief, arm 1** | gone |
| `/tmp/g5gf2/sweep2.py` | G5 gap-fix 2's report and its **accepted verdict** | gone |
| `/tmp/g5gf/sweep.py` | G5 gap-fix 1's report | gone |
| `/tmp/m18-build2.log` | `GAPFIX-BRIEF.md:64`, written by the orchestrator | gone |

## Why this is a defect and not just tidying

These were not scratch files. A sweep is the instrument that proves a guard is **armed** — that
an assertion changes verdict under input built to break it. It is the difference between a
check that bites and a check that cannot fail, which is the distinction most of `G4`'s
twenty-two instances turn on.

Two concrete consequences, both already real rather than hypothetical:

- **A verdict already given rests on an artifact nobody can re-run.** G5 gap-fix 2's
  verification recorded *"both sweeps run clean, the fixture is intact — four planted faults,
  four `FAIL` rows"*, and additionally that the verifier planted three faults of its own that
  each produced a correct `FAIL`. All of it pointed at `/tmp/g5gf2/sweep2.py`. The verdict was
  sound when given and is now unfalsifiable.
- **A live verifier was sent to run a file that does not exist.** `G5V2`'s brief opens arm 1
  with *"Run it"* against `/tmp/g5gf3/sweep3.py`, and calls that arm the claim that decides the
  item.

## The asymmetry that makes it worse than a stale number

`G4` is about assertions naming a quantity they do not read, and its instances are stale
literals — wrong, and **checkable**: run the thing, compare, see the disagreement. A dead path
is not checkable. It produces no wrong answer to catch, only an absence, and an absence reads
identically to "not yet run". A reader who cannot find the file cannot tell whether the
evidence was weak, strong, or never gathered.

## The fix is already precedent in this repo

`R17`'s equivalent sweep lives at `planning/claim-sweep.py`, is committed, survived the crash,
and is wired where anyone can run it. `G5`'s lived in `/tmp` and did not. The two were written
days apart to solve the same shape of problem and only one is still evidence.

So the rule is not new, it is unenforced: **an artifact that a record cites as evidence is
committed, or the record does not cite it.** A `/tmp` path in a durable document is a citation
with an expiry date nobody wrote down.

## Scope

- Commit the surviving sweeps if any can be reconstructed from their reports, and say plainly
  which were reconstructed rather than recovered — a rebuilt instrument is not the one whose
  results were recorded.
- Sweep the records for `/tmp` citations and either commit the target or withdraw the claim.
  `planning/claim-sweep.py` is the right shape of tool for finding them and is itself the
  example to follow.
- Decide whether this earns a gate. A check that fails a record citing a path outside the
  repository is cheap and mechanical, and this item is the argument for it.

**This is the orchestrator's defect, not a runner's.** The briefs that cited `/tmp` paths were
written here, and `GAPFIX-BRIEF.md:64` is mine.

## The matching rule, and the second half of the same mistake

`lukerhodes-2f` supplied the rule that pairs with "load-bearing instruments get committed":
**a brief cites a repo path or it cites nothing.** Two briefs failed it today, both written by
this fleet hours earlier rather than inherited — `GAPFIX-BRIEF.md:64` (`/tmp/m18-build2.log`)
and `VERIFY-BRIEF.md:29` (`/tmp/g5gf3/sweep3.py`). Neither was a stale inheritance; both were
fresh.

Then the opposite error, measured 2026-08-23 across every worktree. The dispatch artifacts this
orchestrator wrote — `WORK-ORDER.md`, `GAPFIX-BRIEF.md`, `VERIFY-BRIEF.md` — went **inside the
tree under test**, and are now inconsistently handled:

| Tracked | Untracked |
|---|---|
| M12, M19, M20, G5V2 | M16, M18 (×2), M22, M17, G5, R19, R19V |

Four of twelve are committed and would merge into `main` carrying the orchestrator's own prompts
as though they were project artifacts. Nobody decided that; it is the residue of writing working
material into the subject. `M20` caught it and handled it well — `bcc69dd` isolates the file so
the commit can be dropped before merge — but that is a per-runner workaround for something the
dispatcher caused, and eleven other runners did not each invent it.

So the two failures are one root. `/tmp` is too volatile to cite and the worktree is too durable
to write into, and the fleet never decided where its own working material lives. The answer is
"beside the work, not in it": a path inside the repository that the item's own diff does not
touch, or an ignore entry that makes the choice for everyone rather than per runner.

Whoever triages this should settle **both** directions at once. Fixing only the `/tmp` half
moves the briefs into worktrees and makes the tracked-artifact problem universal instead of a
third of the time.

## The third axis: a citation that resolved when written and not where it is read

Found 2026-08-23 by `lukerhodes-2f`, which had made the error itself and reported it unprompted.

`/tmp` paths rot **in time**. Bare line numbers rot **across revisions**, and the failure looks
identical to whoever lands on them: a pointer into nothing, indistinguishable from evidence that
was never gathered.

The measurement. Gap-fix 3's verdict cites its blocker as `G5.md:159`. That is **correct at
`a9603e5`**, the base gap-fix 3 worked from and the frame `D-g5-d`'s own ten citations use. It
becomes `:170` at `43b44a2` and stays there. Both the recovery session and this orchestrator
independently declared it "not revision drift" after checking `43b44a2`, `3e63811` and the
worktree — **three frames, all on the same side of the edit.** Three concordant readings from
one side of a change are one reading, and ruling out drift on that basis is an absence check
with no presence control, which is a guard this document set already ships.

It is systemic rather than incidental: **six of `D-g5-d`'s ten citations fail the same way**, and
gap-fix 3's own verdict carries `:159` bare in its opening sentence, its arm-4 paragraph and its
work order — the three places a reader acts.

**The fix is not renumbering, which would hide it.** A number chased to the current revision is
correct until the next edit and carries no way to tell. Carry the frame — `G5.md:159` at
`a9603e5` — and the pointer stays checkable from either side. Where a frame is impractical, quote
the phrase relied on, which this repo already requires of cross-file citations for exactly this
reason.

So this item now has three axes and one root: **a record's pointer must resolve where it is
read, not merely where it was written.** `/tmp` fails it in time, a bare line number fails it
across revisions, and a dispatch artifact written into the subject fails it by changing what it
points at. A guard for the first two is mechanical and cheap; the argument for building it is
that two independent agents hit the third axis within an hour of writing the item about the
first.
