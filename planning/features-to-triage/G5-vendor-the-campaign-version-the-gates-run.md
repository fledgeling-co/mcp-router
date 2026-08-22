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
