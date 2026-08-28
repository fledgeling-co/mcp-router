---
status: to-triage
found-by: reckon 1.7.0, 2026-08-29
---

# A brief that names nothing the registry holds can never leave the remaining set

- origin: reckon 1.7.0 over `planning/features-to-triage` and `planning/test-campaign` · 2026-08-29
- audience: whoever reads "134 pieces of work remain" and needs that number to fall when work is done
- platforms: n/a
- proposed-by-ai: true

## What and why

Only **29 of 167 briefs (17.4%)** could be tied to the registry at all. reckon withholds retirement
claims below half, so **75 briefs sit `unjoined`** — 75 of the 134 remaining work items, and the bulk
of the 79 counted as decision work. That is not a backlog of features. It is a backlog of not knowing.

The mechanism is worth stating precisely, because it is narrower than "the join is weak". Every one of
the 99 join edges is a **citation** — a registry id somebody typed into the brief. Not one of the 75
unjoined briefs cites any id the registry holds, and the strongest textual resemblance anywhere in that
set scores 0.154, nowhere near a threshold. So this is not an inference doing badly. It is a channel
that 138 briefs never wrote to at all.

The consequence is that the remaining-work total cannot fall. A brief that cannot be joined cannot be
retired, however much is done about it, and a reader cannot distinguish "nobody has looked at this"
from "this shipped and nothing recorded it".

The same channel fails a second way, and it is one finding rather than two. **Nothing checks that a
citation resolves.** One brief cites `DEF-253` and the registry holds no such id — the sole `unbuilt`
row in the whole reckoning. Because a citation is a link somebody wrote on purpose, reckon reads an
absent target as evidence of absence rather than as a join that missed, which is right; it also means a
mistyped id is indistinguishable from a real finding about the product.

## Acceptance sketch

- A brief states what in the registry would settle it, and a brief written without that is caught when
  it is written rather than at the next reckoning.
- The briefs that currently name nothing either gain their targets, or carry a recorded statement that
  no evidence exists for them yet — which is a different fact, and readable as one.
- A citation naming an id the registry does not hold is reported as a broken link, separately from a
  brief whose subject is genuinely absent from the product.
- The join rate rises above the half floor, so retirement claims stop being withheld across the board.
- Shipping something moves the total, and a run in which nothing moved says why.

## Assumptions made writing this

- Assuming the remedy is to make briefs carry their targets rather than to loosen the join into
  accepting textual overlap — an overlap edge is a guess, reckon already refuses to retire on one, and a
  looser join would raise the percentage without raising what anybody knows.
- Assuming the existing set is worth backfilling rather than applying the rule only to new briefs, since
  the whole of the 75 sits in the existing set.
- Assuming this is the lever `the-reckoning-cannot-see-a-merge` named and deferred — that brief proposed
  a terminal status as the stopgap and called the join rate the real fix. This is that half, not a
  re-filing of it.
