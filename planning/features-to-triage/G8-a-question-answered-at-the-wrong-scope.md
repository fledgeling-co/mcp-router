---
status: to-triage
found-by: lukerhodes-2f and the orchestrator, three times in one evening, 2026-08-23
---

# A question answered at the wrong scope returns a clean answer

Filed beside `G7` rather than inside it, on the same test that split `G7` from `G6`: shared
shape, unshared remedy. **`G7`'s fix is carry the frame. This one's is establish the set before
answering about members of it.**

## Why it is harder to catch than a bad citation

`lukerhodes-2f` put it better than the evidence does: **a citation that does not resolve
announces itself when someone follows it. A question answered at the wrong scope returns a clean
answer.** There is no dangling pointer, no missing file, no red — just a correct answer to a
narrower question than the one that mattered, indistinguishable from a correct answer to the
right one.

## Three occurrences, 2026-08-23, and it took all three before either party named it

1. **The `:159` citation.** Both a recovery session and this orchestrator independently ruled out
   revision drift after checking three frames — `43b44a2`, `3e63811`, the worktree — **all on the
   same side of the edit**. Three concordant readings from one side of a change are one reading.
   The base frame `a9603e5`, where `:159` is correct, was never checked. *(`G7` carries this one
   as its measurement; it appears here as the scope failure that produced it.)*
2. **`RouterSheet.Kind`.** A peer verified the cases existed and inferred what their existence
   *meant* — slot to fill, rather than record of a deliberate hole — without reading the tests
   that define it. Existence and meaning are different observations and the second one lived in
   `RouterSheetTests`.
3. **The `VOUCHED_CONTROLS` collision.** A peer asked the two parties it was already talking to
   which of them touched the file, instead of asking **which branches touch the file**. The
   answer was complete about the wrong set: `ai/m19` is the largest party at `+29/−6` and was
   absent from it. The orchestrator only caught it because M19's own report mentioned the table
   in passing — **had it not, an unmeasured union would have been merged on a two-way picture**,
   so the failure to sweep is the orchestrator's as much as the peer's.

A fourth, same evening, same shape, different instrument: a **line-anchored `grep`** used as an
absence sweep over hard-wrapped prose returned `0` for a phrase present **twice**, and the
orchestrator reported the phrase as a paraphrase rather than a quotation — to the party who had
quoted it correctly, who then adopted the wrong version. That one is already `G4`'s tenth
instance; it is listed here because the mechanism is identical. **The instrument answered a
narrower question — *does this string appear within one line* — and the answer was clean.**

## A fifth, and it sharpens the statement

`lukerhodes-2f` reported a fourth instance of its own, while relaying a warning about this exact
failure. M22 wrote to it: *"the conductor died in the crash and is holding re-dispatch until I
report, so I've surfaced it to the user instead and written it into `planning/progress/M22.md`
§Fidelity."* The **"it"** is the sequencing position. The relay compressed two clauses and
reported the file as carrying the died-in-the-crash belief.

An independent wrap-tolerant sweep of that file found `conductor` 0, `died in the crash` 0,
`re-dispatch` 0, `orphan` 0 — on the branch and in the worktree. §Fidelity carries the sequencing
analysis at `:90`, exactly as M22 said. **The belief was real and correcting it was right; it was
never written down, and the relay said it had been.**

That is a different remedy from the scope one, and the item's statement needs both:

- **Scope** — *establish the set before answering about members of it.* The three occurrences
  above.
- **Source** — *establish what the source actually says before reporting what it says.* This one.
  It is `G7`'s territory applied to a **message** rather than a file: a quotation compressed in
  the retelling resolves against nothing, and the reader has no way to follow it back.

Both share the property that makes this item worth filing: **one observation, a second inferred,
and the inference reported as the observation.**

## The remedy, and why it is cheap

Ask what the set is before answering a question about its members, and prefer a sweep to a poll:

- `git log --all -S<phrase>` or a diff over **every** branch, not the branches you are in
  conversation with.
- A wrap-tolerant reader for any absence claim over prose — `planning/claim-sweep.py` and
  `planning/verification/G5-gapfix-3-sweep.py` are both committed and both do this.
- **A presence control on every absence check.** Plant a known instance, confirm the instrument
  sees it, then trust the zero. An absence check cannot detect its own blindness.
- When ruling out a change, read **both sides of it**. Three readings from one side are one
  reading.

M16 produced the pattern's positive form on the same evening and it is the model: rather than
asking whether a particular merge conflicts, it **derived the union of all three trees, walked
its own dumps against it, and named the one thing it could not check** — which someone else then
ran. That reduces an open-ended cross-branch question to a mechanical one: *does the other branch
introduce a role I use.* Runnable before any merge, no judgement.

## Scope

- Write M16's reduction into `scripts/acceptance/mock_fidelity.py`'s header, where it retires the
  merge hazard rather than answering it once.
- Decide whether the presence-control rule earns a gate. Every absence-sweeping script in this
  repo already carries controls; nothing checks that a new one does.

## A sixth, in the rule this item is carrying — and the rule invites it

Measured 2026-08-23 after M22 found the gap. Three branches make **three pairs**; one pair was
checked in both directions and the hazard reported closed.

| surface | build roles | frames | intersection with what the merge adds |
|---|---|---|---|
| M16 servers | 39 | 4 | `jack`, `signature` — its own |
| M19 readme | 21 | **1** | 8 roles — its own |
| M22 harnesses | 42 | 4 | **`callout`** — M19's |

M16 is clear of M19's roles and M19 of M16's, as both runs said. **M22 is not clear of M19's**,
and nobody had run it. Harmless in the event — the only node carrying `callout` is
`unreadable-note`, error frame only, and it is already paired, so the quota rule has nothing to
reclassify — but non-empty, and it was reported as empty.

**The full measurement, recorded here because both other authors' sessions have ended and it
otherwise survives only in `planning/fidelity/harnesses.layers.json` and `planning/progress/M22.md`.**
The `m19+m16` union adds **ten** roles to `MOCK_KINDS_FOR_ROLE`: `badge`, `callout`, `codeblock`,
`heading`, `jack`, `list-item`, `sentence`, `signature`, `tab`, `verified-mark`. The single
intersecting node on M22's surface is `harnesses.error.json`, role `callout`, kind `text`, id
**`unreadable-note`** — error frame only, and paired, so the quota rule has nothing to
reclassify. **Harmless for a reason about M22's pairing coverage, not because the merge is
inert.**

M22 was left out because it has **zero diff** on `mock_fidelity.py`, which was taken for having
no stake. **M16's own rule says why that is wrong**: the quota rule keys on the **build node's
role**, not on the edit. A branch that never touches the table can still be reclassified by
another branch's addition.

> **Zero diff means no conflict. It does not mean no exposure.**

That sentence must travel **with** the rule when this item lands it in `mock_fidelity.py`'s
header, because the rule as stated — *does the other branch introduce a role my surface uses* —
reads as addressed to branches that edit the table, and invites exactly this omission. M22's
phrasing is the one to keep: **"came back empty" was M16's surface, not a property of the merge.
The check is per-surface, and must be run once per surface, including surfaces that edited
nothing.**

## What this item owes `planning/claim-sweep.py`

Routed here 2026-08-23 on the same reasoning that kept M16's rule out of the header: it is not
M16's file and `ai/m16` is finished.

M16's sizing note is the requirement, and it is sharper than the count finding above:

> The useful output is the **normaliser's identity AND the sites**, not just the count — because
> a bare count is what let two parties report *verified* over **disjoint subsets**. Two runs that
> both say `2` and disagree about **which 2** is the failure we actually hit, and a count alone
> cannot show it.

The phrase-count record stands at **five sweeps, four answers, one phrase, one file**, and only
the widest normaliser was complete.
