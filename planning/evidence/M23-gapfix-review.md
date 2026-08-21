# M23 gap-fix — out-of-family review, two lanes

> **Superseded, and the reason matters.** The snapshot both lanes reviewed here is not what
> shipped: it carried a planted `timeout=1` on `run()`, which HEAD does not contain — `grep -n
> timeout scripts/acceptance/mock_fidelity.py` returns only the `= 900` default and its two uses.
> So every finding below was made against a file this repository has never held, and one of grok's
> six was spent on the plant. The second pass's review is `M23-gapfix-2-review.md`, against the
> shipped diff, and when the verifier showed both lanes the real code they immediately returned
> blocking findings this round did not.
>
> A second correction, on this file's own reasoning rather than its inputs: it offered grok ranking
> the planted `timeout=1` first as evidence the lane had read the artifact. It does not establish
> that. There was no matched trial without the plant, and "a hard-coded one-second timeout looks
> like a debug leftover" is a stock finding a pattern-matcher produces on request. It rules out a
> canned response and nothing further. Showing a lane read a diff needs a control it must *not*
> flag — which is how the second pass is graded.


Both lanes reviewed the gap-fix diff to `scripts/acceptance/mock_fidelity.py`, briefed with the
three findings of `planning/features-to-triage/M23-gapfix.md` and asked whether each was actually
closed and whether the new code could be bypassed. The diff was passed **inline in the prompt**
rather than as a path — asking `codex` to explore this tree burned 900s twice on the previous pass
and produced nothing.

| Lane | Command | Outcome |
|---|---|---|
| `grok-4.6` | `grok -m grok-4.6 --effort xhigh` | **landed**, 2456 bytes, 6 ranked findings |
| `gpt-5.6-sol` | `codex exec -m gpt-5.6-sol -c model_reasoning_effort=high -s read-only -o` | **landed**, 6395 bytes, 7 findings |

Two earlier attempts failed, and how each was told apart from a review that found nothing:

- **`codex`, first attempt: refused.** Launched with the working directory `/tmp`, it wrote
  `Not inside a trusted directory and --skip-git-repo-check was not specified` to its log and left
  no `-o` file at all. `codex exec` exits 0 on a usage limit as well, so the absent `-o` file is the
  only honest tell either way. Relaunched from the worktree; it landed.
- **`grok`, first attempt: answered without reading.** It returned 117 bytes —
  *"The full prompt was offloaded; I'll read that first so the review is of the complete diff, not
  the truncated slice"* — and stopped. The prompt was 26KB. `grok` exits 0 when session init
  fails, so the assertion is on content rather than status; this was caught by reading the file.
  Relaunched with the engine diff alone at 16KB; it landed.

**Both lanes reviewed the same snapshot, and it carried a mutation.** The diff was captured while
the planted `timeout=1` acceptance mutation was live on disk, so both lanes were shown
`run(..., timeout=1)` in `layer_tokens`. `grok` ranked it its highest finding — *"looks like a
selftest leftover that shipped in the production function"* — and it was reading the artifact
correctly; the shipped engine has the 900s default and no override, which is what
`grep -n timeout scripts/acceptance/mock_fidelity.py` shows. Recorded rather than dismissed,
because a reviewer that catches a planted mutation is a reviewer that was reading.

## What was changed because of the review

Both lanes independently reached the same two holes, by different routes.

1. **The same-word rule was a hole, and it was removed.** The first draft let a build role that
   spelled the mock kind vouch for itself, skipping the structural kind entirely. `grok`: *"a name
   collision, not a measured pairing … a build that renames `skeleton` → `card` earns `vouched`
   with no table edit."* `gpt-5.6-sol` reached it from the other end: *"if role equality is
   genuinely authoritative, the tuple's kind checks are unnecessary; if kind matters, the shortcut
   is a hole."* `VOUCHED_CONTROLS` now lists `column-header` and `skeleton-row` explicitly and the
   shortcut is gone, so every vouched pairing is one table entry somebody wrote down.

2. **The G2 quota counted pairing success while claiming to count the mock.** `grok`: *"the finding
   text says `the mock accounts for {declared}` but that number is pairing success, not the mock
   census length,"* and *"`declared == 0` → blanket `covered-by-pair`"* leaves the original hole
   reachable whenever none of the same-role children were paired. `gpt-5.6-sol` named the nested
   variant: putting the extra row inside an already-paired row moves `nearest_pair` and the quota
   stops binding. The quota now asks the **mock's inventory** — how many affordances of a kind this
   build role may answer the census names for this state — so both routes are closed. The residue
   is a role the table does not map at all, which is `D-m23-i`.

3. **`run()` now converts `UnicodeDecodeError` too** (`gpt-5.6-sol` 7, `grok` 6): it is a
   `ValueError`, so the `OSError` arm never caught it, and an undecodable subprocess stream was a
   third route to exit 1 with nothing measured.

4. **The token markers are parsed strictly** (`gpt-5.6-sol` 6): `matched` is read as an integer
   rather than passed through as a string, and the zero-literals marker must carry a field *named*
   `stray` — `MOCK-FIDELITY-MOCK-LITERALS: unrelated=0` was being accepted as a clean measurement
   of a property nothing had measured.

## What was accepted and deferred rather than fixed

- **Glyph identity is still unread** (both lanes). The harness records no glyph, so an icon pair has
  nothing to compare. It lands `unclassified` rather than `present`, which is the honest outcome
  and not the audited one. The code comment now says so. `D-m23-j`.
- **`VOUCHED_CONTROLS` entries are global** (both lanes): one tuple authorises the equivalence for
  every state, surface and path, so a central edit has a wide blast radius. `gpt-5.6-sol` also
  notes it is still strictly tighter than the mechanism it replaced, where every same-label pair
  passed with no allowlist at all. `D-m23-h`.
- **The census arithmetic is unchecked** — nothing asserts `matched + pending == rows`
  (`gpt-5.6-sol` 6). The parse strictness is in; the arithmetic is a new assertion beyond the work
  order's "wrap the marker parse". `D-m23-k`.
- **A role the table does not map is still exempt inside a pair** (both lanes). `D-m23-i`.
- **`extra-cited` appends a finding** (`grok` 5, conditional on `extra_allowed` being a permit). It
  is not one: `planning/fidelity/servers.pairing.tsv`'s own header says a citation *"records WHO
  OWNS the difference, and never suppresses it"*, and the pre-existing code appended a finding for
  a cited extra too. No change.
- **`node["kind"]` is an unguarded `KeyError` on a malformed dump** (`gpt-5.6-sol` 7). `flatten`
  already assumes `node["id"]`; dump-schema validation is `D-m23-b`'s territory.
- **`str | None` needing Python 3.10** (`gpt-5.6-sol` 7) — not a defect: `from __future__ import
  annotations` is the first import in the file, and the dataclass already carried `str | None`
  before this change.
