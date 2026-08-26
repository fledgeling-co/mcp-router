# Dispatch records — what was already committed, kept where it reads as a record

This directory holds dispatch material that was **already committed into the tree** before `G6`
settled where such material lives. The files are kept byte-identical to what was dispatched; the
explanation is here rather than inside them, so each stays the record it was.

## Why they moved

`git log --all --diff-filter=A` finds a dispatch artifact added in three commits, all three
ancestors of `main`:

| commit | item | note |
|---|---|---|
| `bcc69dd` | M20's work order | *kept as the dispatch record* — the only one that handled it deliberately, isolating the file so the commit could be dropped before merge |
| `9b13a49` | M19 | added inside a feature commit |
| `30f639d` | an earlier item | **predates this fleet**; the hazard was inherited, not introduced |

`bcc69dd`'s copy is the one that survived to `0e5ff49`, and it was at the **repository root**.
That position is the problem `G6` names, and it is worse than the brief measured: a file at the
root of `main` is inherited by every branch cut from `main` — **29 of them at `0e5ff49`** — so
every runner's worktree opened with another item's work order sitting exactly where a runner looks
for its own. Four-of-twelve counted the worktrees that wrote their own; it did not count the one
they all already had.

Moving rather than deleting is the reversible choice, and it keeps `bcc69dd`'s stated intent: the
record of what was dispatched is worth having. What is not worth having is that record occupying
the root of the subject under test. Deleting outright was the alternative and was not taken —
history holds the content either way, but a file nobody can find is not a record.

## Where live dispatch material goes now

`.dispatch/` in the worktree, ignored by `.gitignore`. Inside the repository, so a brief may cite a
repo-relative path and satisfy *a brief cites a repo path or it cites nothing*; outside every
item's diff, so no runner has to reinvent `bcc69dd`'s isolate-and-drop workaround. The rule and its
reasoning are in `planning/practices/EVIDENCE_AND_DISPATCH.md`.
