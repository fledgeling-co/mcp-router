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
