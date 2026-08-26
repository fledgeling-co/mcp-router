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
  each produced a correct `FAIL`. All of it pointed at `/tmp/g5gf2/sweep2.py` (gone). The verdict was
  sound when given and is now unfalsifiable.
- **A live verifier was sent to run a file that does not exist.** `G5V2`'s brief opens arm 1
  with *"Run it"* against `/tmp/g5gf3/sweep3.py` (gone), and calls that arm the claim that decides the
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
and `VERIFY-BRIEF.md:29` (`/tmp/g5gf3/sweep3.py` (gone)). Neither was a stale inheritance; both were
fresh.

**This section DESCRIBES a defect. It does not prescribe the practice.** A runner read it as the
latter on 2026-08-23 and reported that *"`main`'s tip says briefs go inside the tree they are
about"*, which is the opposite of what this item holds. It took the reversible option and left
its briefs untracked, which was right — but it had to guess, and a record that can be read as
documenting current practice is a record that will be. **The rule this item argues for is
"beside the work, not in it"**, stated in full below.

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

## A neighbouring defect, deliberately NOT folded in — see `G7`

`G7` covers a citation that resolved when written and does not resolve where it is read — a bare
line number that was correct against the revision its author had. It shares this item's root and
is **not** part of it, and the test that separates them is this item's own coupling argument.

`G6`'s two halves are coupled because each fix displaces the other's problem: move a brief out of
`/tmp` and it lands in a tree under test. That displacement is what makes them one item.

`G7` has no such relationship in either direction. Fix `G6` completely — every artifact
committed, every brief citing a repo path — and `planning/progress/G5.md` still rots at `:159`,
because that file already satisfies `G6`'s rule perfectly: committed, durable, repo-pathed, and
the exact artifact the defect lives in. Carry the frame on every citation and not one `/tmp` file
comes back. Neither fix moves the other's problem and neither helps.

So they are orthogonal rather than nested. **`G6` is about whether the artifact survives; `G7` is
about whether the pointer resolves.** A durable artifact with an imprecise pointer fails, and a
precise pointer to a dead artifact fails. Both must be fixed and neither implies the other, which
is the property that makes something its own item.

The shared root is real and worth stating once: **a record's pointer must resolve where it is
read, not merely where it was written.** `/tmp` fails that in time, a bare line number fails it
across revisions, and a dispatch artifact written into the subject fails it by changing what it
points at. But an abstraction shared is not a remedy shared, and these remedies have nothing in
common — `G6`'s is a location decision a dispatcher makes once, `G7`'s is a citation discipline
every writer applies every time. Folding them would put a third, uncoupled axis into an item
that already says its two coupled halves must be settled together.

Argument and test both from `lukerhodes-2f`, 2026-08-23.
## Committing the instrument is necessary and is not sufficient

Measured 2026-08-23. **Five sweeps ran over one phrase in one file and returned four different
answers. None of the first four was right.**

| instrument | count |
|---|---|
| line-anchored `grep` (orchestrator) | **0** |
| `[\s#]+ → space` (recovery session) | **2** |
| comment-joining normaliser (M16) | **2**, a *different* two |
| per-line scan for a shorter substring (M16) | **2**, a third subset |
| letters-and-space only (orchestrator, fifth) | **3** — lines 44, 284, 861 |

Each failure is specific and none is careless. The line-anchored sweep cannot span a hard wrap.
`[\s#]+` joins both prose wraps but leaves quote characters, and `:861` splits the phrase across
**two adjacent f-string fragments**, so `" "` sits mid-phrase. The per-line scan missed `:44`
because `:44` and `:284` wrap at **different words**.

**The number is only known because three parties disagreed loudly enough to go and look.**

That is this item's premise, refined by M16 and worth stating as a limit on it: **a sweep that
returns a count nobody cross-checks is a measurement with no witness.** Committing the instrument
makes a sweep re-runnable, which is necessary — a re-runnable sweep would still have produced
exactly one of the four wrong numbers above, and nobody would have questioned it.

So the missing half is that **a sweep should report which normalisation produced its count**, so
that two runs are comparable rather than merely both being numbers. A bare integer from an
unnamed reader is not evidence; it is an assertion wearing a measurement's clothes.

## The second direction has landed three times, and one predates this fleet

Recorded 2026-08-23 after R19's gap-fix 3 surfaced it and the orchestrator measured it.

This item recorded the dispatch-artifact problem as a **state** — *tracked in 4 of 12 worktrees*. The
commit history says it is worse than a state: `git log --all --diff-filter=A` shows a dispatch
artifact **added in three commits**:

| commit | item |
|---|---|
| `bcc69dd` | M20's work order — *kept as the dispatch record* |
| `9b13a49` | M19, inside a feature commit |
| `30f639d` | an earlier item, **before this session wrote any of these briefs** |

So the hazard is **older than this fleet** and this session inherited it rather than introducing it.
`bcc69dd` is the only one that handled it deliberately — isolating the file so it can be dropped
before merge — and even that is a per-runner workaround for a dispatcher's choice.

**The correction to this item's framing**: *4 of 12 tracked* understated it. Tracked-in-a-worktree is
recoverable by not committing; **committed into a branch is already shipped**, and three have been.
Whatever triage decides about where working material lives, it also owes a sweep of what has already
landed.

## And a wrong actionable message worth its own note

`parity-manifest-check.sh` went red **once in 12 runs** on an unchanged tree, naming a fixture that
was tracked and present throughout. A fork-starvation hypothesis did not reproduce in **200**
attempts, so **the cause is unidentified and is recorded as unidentified.**

What makes it worth recording rather than shrugging at: **the message it prints is *stale manifest*,
which is actionable and wrong.** A flaky gate that prints nothing costs a re-run. A flaky gate that
names a plausible cause costs whoever believes it — and this one names a condition a reader can
"fix", which is the expensive kind of wrong.
