---
status: to-triage
found-by: investigation of the campaign registry after the G15-G19 merge run, 2026-08-27
---

# Five armed cases and the floor that would have caught them left in the same stash

- origin: session investigation of `campaign.py check` going red on `main` · 2026-08-27
- audience: whoever needs the campaign's OAuth coverage to exist, and its floor to mean something
- platforms: n/a
- proposed-by-ai: false

## What and why

`stash@{0}`, taken at 14:51:30 during the G15-G19 merge run and described as *"campaign worktree
state (orchestrator-managed)"*, holds a campaign registry that `main` does not. Two things are in it.

The first is five cases. `CASE-0155` through `CASE-0159`, all `pass`, all `armed`: three at
`effect-witness`, one `metamorphic`, one `raster-visual`. They are the only cases that have ever
covered `SURF-021` through `SURF-024` — OAuth discovery, `/authorize`, `/token` and the authority
guard — and the only cases citing `REQ-021` through `REQ-025`. Their witnesses are not thin. Two run
`lsof(8)` over the kernel socket table with a decoy port as the control, and establish that the
router owned the accepted half of a live connection rather than merely holding the port. One reverts
the authority guard and watches nine of ten routes go red. Those ids appear in no commit, no branch
and no other worktree, so this stash is the only copy inside the repository.

The second is the floor. `strict-ratchet.json` reads `checked: 70, total: 85` in the stash and
`checked: 58, total: 70` on `main`. The floor was rolled back by twelve in the same event that
dropped the coverage, which is why nothing objected: `strict-check` now reports *"checked ROSE from
58 to 86"* and reads as good news, when the floor it should be measured against is 70. A ratchet
exists to make exactly this fall visible, and it was carried off in the same movement as the thing
it was watching.

The consequences are already on the board. `campaign.py check` exits 1 naming `4 surface(s) with no
case at all` and `5 requirement(s) no case traces to`. `REQ-021` through `REQ-025` remain recorded
`observed`, so the remaining-work reckoning classes all five `verified-done` on nothing. And
`campaign-reanchor-to-current-tree.md` was closed earlier today with a RESOLVED note citing *"the
ratchet held at 70"* — a sentence that is no longer true of `main`, so a brief that was retired on
evidence is now retired on evidence that has gone.

The tree is not simply the older half. It carries 109 cases against the stash's 85, because
G15-G19 added twenty-four. So the remedy is a union rather than a revert, and every one of the
thirteen stashed files differs from its counterpart on disk.

## Acceptance sketch

- The five cases and their recorded witnesses are back in the registry, with the four OAuth surfaces
  and five requirements they cover reading as measured rather than as uncited.
- The twenty-four cases G15-G19 added are still present afterwards; nothing is restored by replacing
  the tree's registry with the stash's.
- The strict floor sits at or above the highest value either lineage has earned, and the reason for
  the number is recorded where the next reader meets it.
- `campaign.py check` no longer reports a surface or a requirement that only lost its coverage.
- The remaining twelve stashed files are each either merged, or recorded as deliberately superseded
  with the reason.
- `campaign-reanchor-to-current-tree.md`'s resolution is re-checked against `main` as it now stands,
  and either re-earned or reopened.

## Assumptions made writing this

- Assuming the union is the correct shape (both lineages' cases kept) rather than a revert to the
  stash, since the stash predates twenty-four cases that are themselves evidence.
- Assuming the evidence files the five cases cite are usable: all three are present on disk
  (`r14-authserver-probe.txt`, `witness-authserver-socket.txt`, `surf-022-consent-auth-states.png`)
  but none is tracked by git, which is the condition `G24` already describes.
- Assuming the floor should be raised to what the campaign can currently prove rather than restored
  to 70, since 70 was itself a floor rather than a ceiling.
