# Citations — anchor, tree and line

A citation must resolve where it is **read**, not merely where it was written. Write every
pointer into a file with three coordinates:

```
"the phrase relied on", `path/to/file.md:159` at `a9603e5`
```

`planning/citation-gate.py` reads them, and `make lint` runs it.

## Why three

Each coordinate covers a failure the other two do not.

| Coordinate | Survives | Does not survive |
| --- | --- | --- |
| Anchor — the phrase relied on | a line shift | a re-wrap |
| Line — the number | a re-wrap | a shift |
| Tree — a commit SHA | — | it is what makes either of the others checkable |

Settled by `M16` on 2026-08-23. Any two coordinates leave a hole the third closes.

## Renumbering is the defect, not the fix

A number chased forward to the current revision is correct until the next edit and carries no way
for a reader to tell. One line carries two different sentences at two trees:
"`installed_plugins.json` records", `planning/progress/G5.md:159` at `a9603e5`, against
"M28 docket and the X7 brief all name", `planning/progress/G5.md:159` at `0e5ff49`. The second is
unrelated prose, and the sentence the citation was written for is not in the file any more, so
renumbering could not have repaired it even in principle. Carry the frame instead and the pointer stays checkable from either side of the
edit.

The gate is built so renumbering earns nothing: a citation with no tree and no anchor stays
unfalsifiable however recently its number was chased.

## The one that gets believed

A citation into nothing announces itself — a blank line, a number past the end of the file, and
the reader goes looking. A citation onto a line that reads plausibly is believed. `M16` found two
of its own three in that state; `G5`'s gap-fix 4 measured five of six broken citations landing on
prose that reads perfectly well against one landing on a blank line.

That is why the gate reports what the cited line actually says, and marks it `DANGEROUS` when the
frame fails and the line still reads like prose.

## The spellings the gate parses

The frame is read by adjacency, so it sits against the citation with only a connective between:

```
"the phrase relied on", `path/file.md:159` at `a9603e5`
anchor `enum HarnessState`, `HarnessState.swift:52` at `f190de0`
`RUN-2026-08-20.md:589` at `cef3729` records "58 of 76 (76%)"
```

An anchor two clauses away from its citation reads as no anchor. That is the right way round: a
frame a parser cannot follow is a frame a reader has to reconstruct, and reconstructing it is the
work the form exists to remove.

Delimit the anchor with double quotes when it contains backticks of its own, since a backticked
anchor ends at its first inner backtick.

## What blocks and what is counted

`DRIFTED` (the anchor is in the file at that tree, at a different line) and `ABSENT` (the anchor is
not there at all) exit 1. A stated frame that does not hold is a false claim.

A bare citation cannot block, because there is nothing to compare it against. Bare citations are
held against a baseline in `planning/citation-ratchet.json`, **per citing file**, and each file's
count may only fall. A scalar total would let a deletion in one file buy headroom for a new bare
citation in another. The gate prints the ten files holding the most, so the number is lowerable
rather than merely held; lower it with `python3 planning/citation-gate.py --write-ratchet`, in the
same change that repoints them.

A citation whose frame the grammar cannot follow is counted `BARE` rather than reported as
unparsed, so it drops past the blocking check silently. Every run prints how many `BARE` citations
sit within reach of a SHA-shaped token — 82 at the time of writing — which is the visible size of
that hole. Writing a frame in one of the three spellings above is what keeps a citation out of it.

## Citing a section rather than a line

Quote the phrase the citation relies on. A bare `§6` is unfalsifiable; `§6's "the reconciler exits
1"` is a claim a grep can break. Recorded as G4's eighteenth item, after `planning/progress/G4.md`
cited a section that was later corrected truthfully and broke the sentence pointing at it.

## An anchor that quotes a table row cannot live inside a table

Measured 2026-08-26, and it blocked an item for a full iteration.

`LEDGER.md`'s rows put a status and its narrative in one cell, so a citation written there sits
inside a markdown table row. When the cited line is *itself* a table row, its pipes re-split the
citing row: the ledger renders wrong and every reader splitting on the pipe reads it wrong, which
`ledger-reconcile`'s check J catches by cell count.

Escaping them fixes the table and breaks the citation. The anchor then reads `\| ... \|` while the
cited line reads `| ... |`, so it can never match, and `citation-gate.py` correctly classes it
`ABSENT` — which is the **dangerous** class, a pointer a reader believes. Two gates, each right,
each undoing the other's fix.

Neither escaping nor unescaping is the answer, and neither is teaching the gate to unescape `\|`
(that reclassifies every table-row citation in the corpus at once). **Cut the anchor from a
pipe-free fragment of the cited line instead.** A cited table row always has one — the text between
two pipes — and it is usually the most distinctive part anyway:

```
  bad   "\| `planning/citation-gate.py` \| 1 \| **inherited** —", `path/to/file.md:214` at `b5f2227`
  good  "ratchet only, 3 files above baseline and all three are M29's", `path/to/file.md:214` at `b5f2227`
```

The same applies to any anchor carrying a character the *citing* file gives structural meaning to.
The anchor's job is to be findable in the cited file; it is never required to be the whole line.

## The other half: does the target exist at all

Everything above is about whether a **frame** holds. A citation can carry a perfect frame, sit in a
committed file, and still point at nothing — because the file moved, the file was deleted, or the id
was renumbered. `planning/target-resolution-gate.py` reads that half, and `make lint` runs it.

Measured over 411 hand-written records, 2026-08-27: **1639 repo-rooted path citations and 1050
campaign-id citations.** 1591 paths resolve at the index and 957 ids name a row. Of the rest:

| | count | what it is |
| --- | --- | --- |
| `FRAMED` | 9 | gone from the tree, and the citation names a tree where it is. **Not a defect.** |
| `WITHDRAWN` | 8 | gone, and the record says so in a delimited marker |
| `PLANNED` | 8 | a plan naming a file under `Create` / `Delete` — intent, not a claim of presence |
| `DELETED` | 9 | gone from the tree, no frame, no marker. **Blocks.** |
| `PHANTOM` | 13 | in no commit reachable from any ref. **Blocks, and no frame can repair it.** |
| `ID_ABSENT` | 1 | an id with no row in any registry and no declared retirement. **Blocks.** |

`PHANTOM` is the one worth knowing about. There is no tree at which that citation was ever true, so
it is not a pointer that rotted — it is a claim that was never checkable. Three of the thirteen name
an artifact a record calls evidence and no commit holds, which is `G24`'s defect outside the campaign
directory.

### Carry a tree and a rename costs you nothing

A path citation naming a commit reads `FRAMED` forever, whatever happens to the path afterwards.
That is the same third coordinate as above doing a second job, and it is why the answer to a
renamed file is never to chase the new path:

```
  bad   `app/Sources/MCPRouterUI/Breaker.swift` — the drawing
  good  `app/Sources/MCPRouterUI/Breaker.swift` at `d0b19c3` — the drawing
```

The gate prints whether the named tree is an ancestor of `HEAD`. A frame on a side branch is
checkable in this clone and would stop being checkable if that branch were pruned, which is a weaker
guarantee than the same frame on mainline and is not reported as the same fact.

### Where a record must keep a dead pointer

Say so, in `foreign-path-gate`'s marker vocabulary — the same spelling, so a writer satisfies one
rule rather than two. A parenthesised clause opening with the marker word, a lone table cell, or a
bold run opening with it:

```
`planning/PLANT-sweep.py` (deleted after; the plant was reverted and it is in no commit)
| `scripts/acceptance/no-raw-design-values.sh` (does not exist, at any commit) | the script is … |
```

An adjacent denial clause counts too — *"which **does not exist**"*, *"which is nowhere in the
repo"* — but only adjacent. A paragraph that happens to contain the words withdraws nothing, and
the control plants exactly that case to keep it that way.

### Ids, and how a renumber survives

This repository renumbers routinely: `G16` was refiled as `DEF-059`, `G19` as `SURF-027` and `G17`
as `CASE-0184..0194` in one day. None of them reddens the gate, and the reason is structural rather
than a waiver list — **the registries are read as a union**, so a refiling that keeps the old row
leaves both ids resolving. `DEF-059` and `SURF-027` are in `inventory.json` and in neither
`defects.in.json` nor `surfaces.in.json`; a gate reading the seed registries alone would have
blocked 55 cited ids on the day the refiling landed.

What is left is a renumber that deletes the old id from everywhere and names no successor. That is
`registry-drop-gate`'s undeclared drop one layer along, and it is declared in the same file —
`planning/registry-retirements.json`, as `{"id": "…", "reason": "…"}`. One declaration satisfies both
gates.

### The floor

The blocking count is held per **citing file** in `planning/target-resolution-ratchet.json` and may
only fall, for the reason the bare-citation ratchet gives. Lower it with
`python3 planning/target-resolution-gate.py --set-floor`, in the same change that repoints the
citations — never to absorb a new one.
