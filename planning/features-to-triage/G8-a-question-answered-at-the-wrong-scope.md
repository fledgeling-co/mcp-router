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
