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
