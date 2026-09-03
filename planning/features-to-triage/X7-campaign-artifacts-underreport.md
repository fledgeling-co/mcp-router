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
72 rows. The eight absent are CASE-0145–0148 and CASE-0151–0154 as they were numbered
when this was measured on 2026-08-21, all passing. The first four are the campaign's entire
`effect-witness` rung, so a reader of `ledger.md` cannot learn the campaign has its most
expensive evidence.

THE SECOND FOUR HAVE MOVED, and the old numbers are kept above rather than overwritten
because they are what the measurement was of. `3189d028` renumbered `CASE-0151..0161 ->
CASE-0184..0194` when four runners allocated registry ids in parallel off the same `main`
and the earliest claimant kept the number. So CASE-0151–0154 are **CASE-0184–0187** today,
and a reader resolving this paragraph against the current `cases.json` should look there.
Rewriting the sentence to the new ids would have made the citation resolve while quietly
claiming the audit had read rows that did not exist under those names on the day it ran.

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


---

## WE3 ADJUDICATION, 2026-09-03 — the three defects are (A). **The paragraph above saying where the work can be done is now WRONG, and correcting it is the point of this note.**

### What changed under the section headed "Where this can be done, and it is not here"

That section says the code *"is not in this repository at any path"* and that the vendored
submodule carries 0.5.0 with none of the relevant scripts. **Both were true when written and
neither is true now.** G5 landed `vendor/test-campaign/` at **0.9.2** on 2026-08-22, one day
after this brief was written, and it carries `evidence-page.py`, `campaign.py`,
`capture-lineage.py`, `vacuity-check.py` and the rest.

The blocker did not lift. It **changed shape**, and the difference matters to whoever picks this
up:

* **Then:** the code was at no path in this repository, so the work was impossible here and had
  to be routed upstream.
* **Now:** the code is here, readable, runnable, and **pinned by tree checksum** in
  `vendor/README.md` precisely so the gates re-run from a clone. Editing it is possible and is
  refused: a `campaign.py` that behaves one way in this repository and another way everywhere
  else stops being evidence of anything, which is the reason `vendor/README.md` gives and the
  reason G5 gives in its own closing section.

So the route is unchanged — upstream, then a re-pin — but "no runner can do it" has become "no
runner may", and a reader who takes the old sentence at face value will look for the code, fail
to find it where the sentence says it is not, and conclude the situation is worse than it is.

### The three defects, each re-read in BOTH copies rather than carried forward

Each was checked against the pinned 0.9.2 **and** the machine's 0.17.0, because an (A) verdict
that holds only in one of them is a verdict about a file nothing here executes.

* **DEF-052 — (A), live in both.** `evidence-page.py:305` at `5934c38f` and `:521` still render failing cases
  under the heading "Defects"; `grep -c defect` over the file returns 3, and all three are those
  two lines and their comment. `campaign.py`'s ledger writer still never reads
  `inventory['defect']`. Exact remedy in DEF-052's `resolution`.
* **DEF-056 — (A), live in both.** `campaign.py:1219` at `5934c38f` buckets into the residual `'—'` key and `:1235`
  iterates surfaces, so the residual bucket is never visited. The input-side fix — give the eight
  cases a surface — **exists and is refused**: four of them are this campaign's entire
  `effect-witness` rung and none has a UI surface, so filing them under one would make the
  ledger's two numbers agree by writing something false. Recorded in DEF-056's `resolution`
  rather than left silent.
* **DEF-051 — not adjudicated here.** It is another runner's member in this wave.

### One correction to this brief's own measurement, since it is quoted downstream

The paragraph on DEF-052 says adding DEF-055 and editing two defects left `evidence.html`
byte-identical. That still holds and is the cleanest proof of the mechanism. Nothing in this
session's re-read contradicts it.

Status word not changed: the three defects stay open and `shipped-brief-gate` R6 is right to
refuse one.
