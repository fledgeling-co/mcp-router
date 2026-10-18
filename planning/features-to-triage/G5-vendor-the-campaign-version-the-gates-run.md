# G5 — vendor the `test-campaign` version the gates actually run

**Status:** Ready for AI · **Category:** harness · Standard tier
**Origin:** M28 / DEF-057, answered by the owner 2026-08-22: **vendor `test-campaign` only.**

## The state this fixes

`.claude/plugins/fledgeling-plugins` is a git submodule tracking `main`, and `LEDGER.md` gives the
reason in its own words: *"a runner reads `mockup-fidelity`, `mac-craft`, `design-craft` and
`ux-craft` at a repo-relative path rather than depending on the machine."*

For `test-campaign` that is not what happens. Measured 2026-08-22:

| | |
|---|---|
| Vendored `plugins/test-campaign/.claude-plugin/plugin.json` | `0.5.0` |
| What every gate this campaign reports actually ran, from the machine's plugin cache | `0.9.2` |
| `du -sh .claude/plugins/fledgeling-plugins` | **546 MB** (`plugins/` is 540 MB of it) |
| `du -sh .claude/plugins/fledgeling-plugins/plugins/test-campaign` | **8.9 MB** |

0.5.0 has five scripts and none of the ones the campaign depends on — no `vacuity-check.py`, no
`capture-lineage.py`, no `effect-witness`, no `blindVocabulary`. **A fresh clone following the
documented `git submodule update --init --recursive` reproduces none of this campaign's numbers.**

## And a second cost, measured after the docket was written

**Populating that submodule in a worktree breaks every runner dispatched into it.** 546 MB of
plugin skills land where Claude Code loads them and the runner exits 1 on context with no partial
work. It cost three runner launches on 2026-08-22 before the cause was found, and it is now
recorded as a dispatch hazard in `ORCHESTRATOR.md`. Every worktree in this fleet leaves the
submodule uninitialised on purpose, which means the vendoring claim is not merely stale — it
describes something the fleet actively avoids doing.

## The decision, made

The owner chose **vendor `test-campaign` alone** over bumping the whole submodule or dropping the
reproducibility claim. At 8.9 MB it is 1.6% of the submodule, it delivers the reproducibility
`LEDGER.md` already claims, and it removes the hazard rather than carrying it.

The two rejected options, recorded so they are not rediscovered: bumping the whole submodule keeps
546 MB and the runner hazard; dropping the claim costs reproducibility outright and leaves a fresh
clone unable to re-run anything the campaign reports.

## Acceptance

1. `test-campaign` at the version the gates run is present in this repository at a repo-relative
   path, at a **pinned** version rather than a moving `main`, and the pinned version is stated
   somewhere a reader finds it.
2. The vendored copy is **runnable from the repository with the plugin cache renamed away**, and
   the run is shown. That is the reproducibility test, and it is deliberately not the same as
   criterion 2 in the first draft of this brief — see the finding below.
3. A fresh clone reproduces the campaign's gate numbers. State which numbers you checked and what
   they came out at; a claim of reproducibility that nobody re-ran is what this item exists to
   remove.
4. `LEDGER.md`'s vendoring note is corrected to say what is true afterwards, including which
   skills are vendored and which remain machine dependencies. Do not leave the sentence claiming
   more than the repository delivers.
5. The dispatch hazard in `ORCHESTRATOR.md` is updated if this changes it — and if the 546 MB
   submodule is still present and still breaks worktree runners, say so plainly rather than
   letting the fix read as having removed it.

## The finding that reshaped this item, measured before dispatch

The first draft of this brief asked that *every gate invoking a `test-campaign` script resolve it
from the vendored path*. **There are no such invocations.** Searched across `Makefile`,
`scripts/`, and `planning/test-campaign/bin/` for `campaign.py`, `strict-check`,
`capture-lineage`, `vacuity-check`, `attach-shots` and `witness-worklist`: every hit is a **comment
mentioning a script by name**, and nothing resolves a skill directory — `plugins/cache` and
`fledgeling-plugins` appear nowhere outside `.claude/`.

The campaign is run by an agent invoking the skill, and the skill resolves its own `scripts/`
directory from wherever the skill was loaded, which is the machine's plugin cache. **Vendoring a
copy into the repository does not change where the skill loads from**, so "make the gates read
from it" is not a path edit — there is no path to edit.

That splits into two jobs and only the first is this item:

- **Carry the code, pinned, and prove it runs from here.** Achievable now, and it is what the
  owner's answer bought: a fresh clone can reproduce the numbers by hand.
- **Give the repository its own gate wrappers** that invoke the vendored scripts, so `make` can
  run them and CI could. That is new surface rather than a relocation, and it is filed separately
  as **G5-C1** rather than smuggled in here.

Recorded because the first draft's criterion had **no subject**, which is the same defect that
sent an R17 runner at a gate its branch could not satisfy this morning. A criterion nothing can
satisfy is indistinguishable, to the runner, from one it failed.

## What this does not do, and must not claim to

It does not close **X7** or **X8**. Those are defects *in* `test-campaign` 0.9.2, and fixing them
means a change pushed to `fledgeling-plugins` upstream. Vendoring the code makes them **editable
here for the first time**, which is a real change in what is possible — but an edit that lands
only in this repository's vendored copy and never reaches upstream is a fork, not a fix. Say which
you are doing if you touch them at all; the safe answer for this item is to touch neither and note
that the blocker recorded against them has changed shape.

## Scope

`.gitmodules` or whatever vendoring mechanism is chosen, the vendored tree, the gate invocations
that reference `test-campaign` scripts, `LEDGER.md`'s vendoring note and its X7/X8 note, and the
`ORCHESTRATOR.md` dispatch-hazard row. **No campaign data**: `planning/test-campaign/` belongs to
another session and this item does not re-run or rewrite its registry.


---

## WE3 VERDICT, 2026-09-03 — (A)/DELIVERED. This brief's own acceptance is met; what it did NOT claim to do is what is left.

Adjudicated as one of fifteen scheduled rows naming a script under `vendor/` or
`.claude/plugins/`, on the question of whether naming a vendored script is proof the fix lives
there. For G5 it is not a fix question at all: the vendoring landed, and this row's remaining
weight is a decision the brief itself hands to the owner.

**Acceptance 1 is met and was re-checked rather than taken on trust.** `vendor/test-campaign/`
carries **0.9.2**, both `plugin.json` and `.claude-plugin/plugin.json` agreeing, pinned by commit
and tree checksum in `vendor/README.md`, and holding all four things the brief says 0.5.0 lacked:
`vacuity-check.py`, `capture-lineage.py`, the `effect-witness` rung in `strict-check.py:59` at `5934c38f`, and
`blindVocabulary` support.

**The vendored copy was RUN this session, from the repository, against this campaign** —
`vacuity-check.py --gate` (`uncensused: examined=17 findings=1`, naming REQ-016),
`attach-shots.py --apply --filename-only` against a scratchpad copy, and `campaign.py check`.
That is not the same as acceptance 2's plugin-cache-renamed-away run, which is still owed, but it
is a repository-relative invocation producing real numbers.

**One thing acceptance 3 has to survive that was not known when this was written:** the machine's
cache now holds **0.16.0, 0.16.3 and 0.17.0**, and this campaign's published numbers were produced
on the Mac by **0.14.1**. All seven scripts differ byte for byte between the pinned 0.9.2 and
0.17.0, sha256 compared. So "a fresh clone reproduces the campaign's gate numbers" is a claim
about 0.9.2's numbers, not about the numbers in the artifacts — and whether the pin should move is
the owner's, recorded in DEF-057's `resolution` rather than decided here.

**The brief's closing prediction came true, and half of it was cashed.** It says vendoring makes
X7 and X8 *"editable here for the first time, which is a real change in what is possible"*, and
warns that an edit landing only in the vendored copy is a fork rather than a fix. Nothing under
`vendor/` was touched. What the vendored copy bought instead was the ability to **read the
instrument precisely enough to find where the defect actually was** — and for DEF-054 it was not
in the instrument at all, it was this repository's directory name. That row is fixed. See
`planning/mock-exclusion-gate.py`.

**A new finding against acceptance 4.** `LEDGER.md`'s vendoring note names the submodule as the
mechanism; the submodule's own `test-campaign` reports **two different versions from two manifest
files in the same directory** — `plugin.json` says 0.6.0, `.claude-plugin/plugin.json` says 0.5.0.
This brief and DEF-057 both quote 0.5.0, so both read the second, and both are right about the
file they read. Filed as **DEF-500**.

Status word not changed: `shipped-brief-gate` R6 would refuse a terminal word while DEF-057 is
open, and DEF-057 stays open on the owner's question rather than on any work.
