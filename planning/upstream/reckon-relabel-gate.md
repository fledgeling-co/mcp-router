# reckon: the re-label refusal cannot fire on any ledger reckon writes

**Where this belongs:** `fledgeling-plugins`, plugin `reckon`. Not this repository.
**Versions measured affected:** 1.5.0, 1.7.0, 1.8.0 — every version that carries the field.
**Versions measured unaffected:** none. 1.0.0 through 1.4.0 have no such guard to reach.
**Filed from:** mcp-router, item `G27`, 2026-08-28.
**Reproduction:** `python3 planning/upstream/reckon-relabel-probe.py`, in this repository.

## The guard, and what it is for

`reckon`'s `ratchet` refuses a requirement moved from `unmeasured` to `observed` with no passing
case citing it. The guard's own comment records the measurement it was built from: one campaign
moved eight requirements out of `unmeasured` inside a single session with no case having run in
between, in the same session that carried a brief join from 6% to 100% by writing citations into
81 briefs, and both `check` and `ratchet` exited 0. `SKILL.md` states the rule in the same terms —
*"a move to `observed` with that list empty is refused as a re-label"*.

The guard reads `backed_by`, the ids of the passing cases citing the requirement. That field is
computed from the campaign rather than from the requirement's own word, which is the whole point:
it is the one thing on the row the requirement does not say about itself.

## The defect

Two lines, in the plugin's own `reckon.py`, one at each end of the field's life. Both are under
`skills/reckon/scripts/` in the distributed tree; they are written here without that prefix because a
repo-rooted path token in this repository's records is read as a path into *this* tree, and these are
not.

The writer, in the requirement loop — line 750 in 1.5.0, 811 in 1.7.0, 846 in 1.8.0:

```python
"backed_by": sorted(backing.get(r.get("id"), [])) or None,
```

`sorted([])` is falsy, so `or None` converts *zero backing cases* into `None`.

The reader, in `ratchet` — line 1218 in 1.5.0, 1301 in 1.7.0, 1336 in 1.8.0:

```python
backed = crow.get("backed_by")
if backed is None or backed:
    continue
```

`None` means "this ledger predates the field" here, and is let through. That allowance is right,
and the comment above it argues for it correctly: refusing there would fail every first comparison
against an older ledger, which is a fact about the ledger's age rather than about the project.

But the writer never emits an empty list, so **every zero-backing row takes the allowance**. The
refusal below it is unreachable for any ledger this tool writes. The logic is correct, the message
is the right one, and the value never arrives in the shape that reaches it.

## The two conditions are already distinguishable, and `.get()` is what discards it

A ledger written before 1.5.0 has **no `backed_by` key at all** on a requirement row. A ledger
written by 1.5.0 or later has the key on **every** requirement row, carrying `null` when nothing
backs it. Measured over the twelve ledgers this repository has kept:

| ledgers | requirement rows | key present | value `null` | value `[]` |
|---|---|---|---|---|
| four written before 1.5.0 | 100 | 0 | 0 | 0 |
| eight written by 1.5.0 or later | 210 | 210 | 29 | **0** |
| all twelve | 310 | 210 | 29 | **0** |

Not one empty list, over every ledger the tool has written here. Key presence is a complete
discriminator on data that already exists, which makes the read side the better place to fix it: a read-side fix also restores the
guard over ledgers already written, where a write-side fix leaves the first comparison against any
existing 1.5.0-and-later ledger passing silently.

## The fix, measured on both sides

Both halves, applied to a scratch copy — never to a plugin tree:

```python
_NO_FIELD = object()   # key absent = ledger predates the field; None/[] = zero backing

# writer
"backed_by": sorted(backing.get(r.get("id"), [])),

# reader
backed = crow.get("backed_by", _NO_FIELD)
if backed is _NO_FIELD or backed:
    continue
```

Put to the same transition three ways, differing only in the shape of `backed_by` on the one row:

| arm | 1.7.0 and 1.8.0 | patched | what a working guard owes |
|---|---|---|---|
| `null` — what the writer emits for zero backing | exit 0, allowed | exit 3, refused | refuse |
| `[]` — what the guard's text expects | exit 3, refused | exit 3, refused | refuse |
| key absent — a genuinely pre-field ledger | exit 0, allowed | exit 0, allowed | allow |

End to end with the patched tool — both ledgers built by it rather than edited afterwards — the
real transition is refused at exit 3 with the guard's own message. The plugin's `selftest.py` passes
unchanged against the patch, all cases, exit 0.

## The selftest passes today, and that is the second half of the report

`selftest.py` exits 0 on every affected version. It exercises the guard through `req(..., backed_by=[])`,
a hand-built row, and its pre-field arm through a hand-built row with the key omitted — so both
sides of the branch are covered and **neither shape is one the writer produces**. The fixture is
the only place an empty list has ever existed.

So the arm worth adding upstream is not another branch case. It is one that **builds a ledger
through `build` and asserts on what came out**: a requirement with no passing case citing it must
serialise in a shape the ratchet refuses. That is the arm that would have failed the day the field
landed, and it is the shape of the probe filed with this report.

## What it cost the project that found it

mcp-router's ledger of 2026-08-27T1520 carries five requirements — `REQ-021` through `REQ-025` —
recorded `observed` and classed `verified-done` with `backed_by: null`, while the campaign's own
`check` named all five as requirements no case traced to. Two instruments disagreed about the same
five rows and the one gating the goal harness was the one that was wrong.

The window closed by accident rather than by the gate. The five cases behind those requirements had
been lost in a stash and were restored under this repository's `G26`; from the 1730 ledger onward
all five carry a citing case at `effect-witness`, `metamorphic` and `raster-visual` rungs with the
evidence artifacts present. Nothing needed re-classing — but nothing had refused the interval
either, which is the property the guard was added for.

## Filing note

No change has been pushed to `fledgeling-plugins` and no plugin tree was edited. This repository
vendors instruments rather than forking them: an edit that lands only here is a fork, and a script
behaving one way here and another way everywhere else stops being evidence. The submodule pinned in
this repository predates `reckon` entirely and does not contain it, so there is no local tree to
raise the change in either. What is owed upstream is the two-line change above, the selftest arm
that builds through the writer, and a release; this document and the probe beside it are what a
person carries there.
