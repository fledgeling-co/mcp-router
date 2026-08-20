# X7 — the campaign's published artifacts under-report what the campaign knows

**Category:** instrument · **Found:** 2026-08-21, by the campaign auditing its own outputs
**Defects:** DEF-052, DEF-056, DEF-051 · **Upstream:** `github.com/fledgeling-co/fledgeling-plugins`

## Where this can be done, and it is not here

Read this before planning any work. The three defects are in `test-campaign` **0.9.2**, at
`~/.claude/plugins/cache/fledgeling-plugins/test-campaign/0.9.2/skills/test-campaign/scripts/`.
That code is not in this repository at any path. The vendored submodule
`.claude/plugins/fledgeling-plugins` carries test-campaign **0.5.0**, which has no
`vacuity-check.py`, no `capture-lineage.py`, no `effect-witness` rung and no
`blindVocabulary` — four minor versions behind what every gate in this campaign actually
ran (DEF-057).

So this item cannot be closed by an mcp-router runner. Closing it means a change pushed to
`fledgeling-plugins` and then a submodule bump here: a different repository and an
outward-facing action. Route it to that repo, or hold it. What follows is the complete
specification so whoever picks it up does not re-measure.

## What was measured

**DEF-052 — no published artifact lists a defect.** `evidence-page.py`'s
`<section id=defects>` renders `[c for c in cases if state_of(c.get("status")) == "fail"]`
— failing *cases*, not the defect registry — and its nav count at line 305 is
`counts["fail"]`, the same population. `campaign.py`'s ledger writer never reads the
registry either. Measured against the built 124,100-byte `evidence.html`: 8 of the 11 open
defects at the time appear **zero** times, and `ledger.md` prints `0 open` on a campaign
holding 12 open defects. Confirmed directly rather than inferred — adding DEF-055 and
editing two existing defects left `evidence.html` byte-identical at 124,100.

**DEF-056 — the ledger drops 8 of its own 80 cases.** The writer buckets with
`by_surface.setdefault(c.get("surface", "—"), [])`, then emits
`for s in inventory["surface"]: for c in by_surface.get(s["id"], [])`. `"—"` is not a
surface id, so that bucket is never visited. The header says `80 cases`; the table carries
72 rows. The eight absent are CASE-0145–0148 and CASE-0151–0154, all passing. The first
four are the campaign's entire `effect-witness` rung, so a reader of `ledger.md` cannot
learn the campaign has its most expensive evidence.

**DEF-051 — a denominator built from captures rather than from enumeration.**
`witness-worklist.py` reports 17 judgeable pairs; `capture-lineage.py --gate` reports
`JUDGED 16 of 16 judgeable (100%)`. The disagreeing member is exactly one: SURF-009, the
Mac menu-bar popover. It has a rendered design of record, which is the only condition the
worklist tests, and no build capture at all, so it never enters capture-lineage's
population. The direction is the dangerous one — an uncaptured surface **raises** the
percentage.

## What to deliver

1. `evidence-page.py` renders the defect registry from `inventory.json["defect"]` as its own
   section, with the open ones counted in the nav, separately from failing cases. The two
   populations answer different questions and today the page answers only one of them.
2. `campaign.py`'s ledger writer emits every case. Iterating surfaces and dropping the
   residual bucket is the mechanism; iterating cases and grouping by surface, with a final
   group for those that have none, keeps the existing layout and loses nothing.
3. `campaign.py`'s ledger prints the defect registry's open count, so `0 open` cannot mean
   `0 open cases` on a campaign with twelve open defects.
4. `capture-lineage.py --gate` builds its denominator from enumerated judgeable surfaces
   rather than from published captures, and names any surface with a reference and no
   capture rather than omitting it. A surface that cannot be photographed is still a
   surface that was not compared.

Each of the four is independently checkable against this repo's campaign at
`planning/test-campaign/`, which is the corpus all three defects were measured on.

## Scope

Deliver those four, at that scope. These are reporting paths; the gates' verdicts and
ratchets are correct and stay as they are. If a fix would change what a gate *decides*
rather than what it *prints*, say so and stop rather than changing it.
