# spec-P4 — Derive the manifest rows, and fix the directory-dependent normaliser

**Item:** P4 · **Category:** harness · **Deps:** R4 ✓ · **Branch:** `ai/p4` ·
**Worktree:** `.worktrees/P4` · **Plan:** `planning/plans/plan-P4.md`

**Owned this wave:** `scripts/acceptance/parity-*.sh`. No other runner touches them.

Two defects in the parity harness itself. Neither is a defect in either router. Both make the
harness's own number untrustworthy, and one of them makes it untrustworthy *in a way that reads as
a better result*, which is the more dangerous half.

**Revision note.** §§3–4 were rewritten after the grok-4.6 spec review (§10) returned AMEND. The
first draft proposed widening a character class and classifying CLI verbs by spelling; both were
refuted with concrete sequences, and both are replaced below. The review also found a live hole in
the *existing* control check that this spec had asserted was safe (§2.5).

---

## 1. The brief, verbatim

> `D-n` — the `cli` and `mcp` manifest rows are hand-maintained. `src/index.ts`'s ten `case` arms
> and `src/router.ts`'s endpoints are mechanically extractable, and until they are, **42 of 82 rows
> are hand-written and deleting one raises the coverage figure.** That is the gate's own worst
> failure mode.
>
> `D-o` — `parity-fixture.sh:121` normalises `"project":"[A-Za-z0-9]+"`, a character class omitting
> `-` and `_`. A call's project is the directory it came from, so **the gate's verdict depends on
> the name of the directory it is run from**.
>
> **Done means:** the rows derived, the normaliser fixed, and the number identical from both a
> worktree and the repo root.

The denominator moved to 83 when P1 landed, so the brief's `42 of 82` is `43 of 83` today.

---

## 2. What is actually there — measured, not inferred

Both runs below are the **identical tree** (`main` at `317d957`), the same gate, minutes apart.
The worktree needed `npm install && npm run build` first: `dist/` and `node_modules/` are
gitignored, so a fresh worktree has no reference to compare against and all ten lanes exit 2.

Logs: `/tmp/p4-before-root.txt` (gone), `/tmp/p4-before-worktree.txt` (gone).

| | repo root `mcp-router` | worktree `.worktrees/P4` |
|---|---|---|
| exit | 1 | 1 |
| proven | 73 of 83 | 73 of 83 |
| blocked | 9 | 9 |
| DIVERGED | **1 — `fixture usage`** | **1 — `divergence R2 D6`** |
| `fixture` group | 22 proven, 1 blocked, **1 DIVERGED** | 23 proven, 1 blocked |
| `divergence` group | 14 proven | 13 proven, **1 DIVERGED** |

**The two totals agreeing at 73 is a coincidence of this pair of runs.** They diverge on *different
rows*, and only one of the two is P4's defect. This matters for the acceptance criteria: "the same
number from both places" — the brief's own wording, written when the numbers were 71 and 72 — is
**already true today, with D-o fully live**. A criterion phrased that way would be green before any
work started. §4 A9 is phrased against the rows instead.

### 2.1 The root's divergence is D-o, exactly as described

```
fixture  usage  the recording no longer matches the reference —
                .records[0].project: recorded="<project>" live="mcp-router"
```

`projectOf` is `basename(cwd)` (`src/usage.ts:305-306`). The recorded fixtures carry
`"cwd":"…/.worktrees/F3"` with `"project":"F3"` — the worktree F3 was captured in, which no longer
exists. `F3` is alphanumeric, so the recording always normalises. The live side is whatever
directory the gate runs from. `P4` normalises; `mcp-router` does not, because the character class
has no `-`.

**Every runner works in a worktree named alphanumerically, so no runner can hit it.** That is why it
survived R4's three adversarial reviews. The repo root is where a human reads the number, and where
the cutover decision gets taken.

### 2.2 The worktree's divergence is NOT directory-dependent, and is not P4's

`divergence R2 D6 — callsServed=4, neither the declared 1 nor a call count of 5`
(`parity-pool.sh:196`).

D6 asserts five concurrent callers share one lease, so `callsServed` reads 1. A reading of 4 means
four of the five acquired separately. Measured rather than assumed: **the pool lane run in
isolation, four times from the repo root and four times from the worktree — 8 of 8 read
`callsServed=1`, exit 0, from both directories** (`/tmp/p4-pool-root-{1..4}.log` (gone),
`/tmp/p4-pool-wt-{1..4}.log` (gone)). The `4` was read inside a full gate run, with nine other lanes and a
second runner's worktree live on the machine.

So it is contention-sensitive, not directory-sensitive, and it is **not filed as flaky** — that
label invites re-running until green over a real acquisition race (the `D-p` mistake, and the
reason `D-p1-e` was worded as it was). Registered as `D-p4-a`; not fixed here, because the tolerance
that would fix it is the tolerance that would stop D6 being diffed at all.

### 2.3 What is hand-written, counted

`parity-manifest-check.sh` mechanically reconciles `control` (16 rows, against `src/control.ts`) and
`fixture` (24 rows, against the fixture directory). The remaining **43 are hand-written**: `cli` 10,
`mcp` 5, `divergence` 15, `install` 5, `pool` 6, `state` 1, `log` 1.

Deleting a *blocked* hand-written row raises the reported fraction: it leaves the numerator alone
and shrinks the denominator. `cli-auth` is blocked today — deleting it takes 73/83 to 73/82.
Nothing in the gate notices, and the headline number improves.

P4 closes 15 of the 43 — the two groups the brief names, which are the two genuinely extractable
from a source file. The residue is argued in §5.

### 2.4 What is extractable, confirmed against source

`src/index.ts:342` is a `switch (cmd)` with **twelve** `case` labels: ten verbs
(`import index refresh serve status tools auth usage watch help`) and two flag spellings (`--help`,
`-h`) that fall through with `help`. The manifest's ten `cli` rows are exactly the ten verbs.

`src/router.ts` compares `url.pathname` against `/health` (:239) and `/status` (:242), and against
`MCP_PATH = '/mcp'` (:16) at :266; it registers two JSON-RPC handlers, `ListToolsRequestSchema`
(:75) and `CallToolRequestSchema` (:80). The method strings are **not** hand-mapped: the SDK schema
carries them, and asking it returns `tools/list` and `tools/call`. The manifest's five `mcp` rows
are exactly those five subjects.

**Both groups agree with source today**, so the derivation confirms the existing rows rather than
editing them, and the denominator does not move. That is the wanted outcome: a rising numerator
over a shrinking denominator is the failure mode this item exists to prevent, so this item must
not itself move the denominator.

### 2.5 The rows that ARE mechanical are not a safe set either — found by the review

`parity-manifest-check.sh:103` reconciles control rows by `sort -u` on the **subject**.
`control-auth-post` (proven) and `control-auth-post-http` (blocked, `D-p1-a`) deliberately share the
subject `POST /servers/:name/auth` — P1 wrote the second row's note explaining exactly why the
subject string had to be identical. So:

1. Delete `control-auth-post-http`.
2. The subject is still carried by `control-auth-post`; both directions of the source reconciliation
   stay satisfied; `manifest-check` exits 0.
3. Coverage goes 73/83 → 73/82.

**A blocked row inside the "mechanically checked" group can be deleted to raise the figure.** That
is D-n's headline failure, in the group this spec's first draft cited as proof it could not happen.

The two rows' notes each name the other's id, and `div-r1-d3`'s note names `div-r1-d3-control` — 3
cross-citations across the 83 rows. `manifest-check` already resolves *cited tests* and *cited
scripts* on the principle that "a citation has to keep being true, not merely have been true once".
Extending that to **cited row ids** closes this, mechanically, with no hand-written list (§4 A12).

---

## 3. The normaliser: what the fix is, and what it is not

### 3.1 A wider character class is the wrong fix

The obvious repair — `"project":"[^"]+"` — was refuted in review and is **rejected**. Substitutions
run in order: the repo-path rules (:114-115) rewrite any checkout path to `<repo>` *before* the
project rule (:121) runs. So if the reference ever regressed to putting the whole cwd in `project`
instead of its basename:

1. live `"project":"/Users/…/mcp-router"` → path rule → `"project":"<repo>"`
2. `[^"]+` → `"project":"<project>"`
3. recorded is already `"<project>"` → **the bodies match, and a real contract change is invisible.**

Today that regression is caught, only because `<repo>` contains characters the narrow class rejects.
Widening the class fixes under-matching by introducing over-matching, and over-matching is the worse
failure for a parity harness: it makes a router difference disappear. The same applies to
`"project":"/"`, `"."` and `".."`.

### 3.2 The fix is structural, anchored on the contract

The contract is one line of the reference: **`projectOf = cwd ? basename(cwd) : undefined`.** Every
`project` in the corpus has a sibling `cwd` in the same object — in `usage.json` records, and in
`usage-summary.json`'s `projectNames` entries, which are objects `{cwd, project, calls}`.

So: parse the body, walk it, and normalise `project` to `<project>` **only where it equals
`basename(cwd)` of its own object and is non-empty**. Any other value is left alone and mismatches
loudly. This accepts every legal directory name, including every character the old class dropped,
and accepts nothing else. Empty stays rejected — the `+` lesson the `hash` entry records.

### 3.3 The `projectNames` regex destroys real signal and goes

```python
(r'"projectNames":\[([^\]]*)\]',
 lambda m: '"projectNames":[' + ','.join('"<project>"' for x in m.group(1).split(',') …
```

Its comment claims it preserves array length. It was written for an array of **strings**; the
corpus holds an array of **objects**, so it splits `{"cwd":…,"project":"F3","calls":1}` on its
internal commas and emits three markers for one entry — **replacing the `calls` count with
`"<project>"`.** A per-project call count of 1 and of 900 normalise identically. It is symmetric, so
it has never failed; it is also blind.

With §3.2's structural rule it is unnecessary: each entry's `project` normalises against its own
`cwd`, the `cwd` normalises through the path rules, and the array length and every `calls` value
then compare honestly. **Deleting it strictly increases what the lane can detect.**

### 3.4 Two more members of the same table

| line | now | to | why |
|---|---|---|---|
| 114 | `…/\.worktrees/[A-Za-z0-9]+` | `…/\.worktrees/[^"/]+` | Identical class defect. A worktree named `my-tree` normalises `.worktrees/my` and leaves `-tree`, giving `<repo>-tree` against a recorded `<repo>`: a router divergence caused by a directory name. **One path segment**, not `[^"]+`, which would greedily swallow the rest of the path and collapse real structure |
| 127 | `"cwd":"[^"]*"` | `"cwd":"[^"]+"` | The `*` weakness the `hash` entry documents. No fixture has an empty `cwd`, so no current verdict changes |

---

## 4. Acceptance criteria

| # | Criterion | How it is proven |
|---|---|---|
| **A1** | Every `case` label in `src/index.ts`'s `switch (cmd)` is either a `cli` manifest row subject or a **declared alias**, and every `cli` row is such a label. Nothing is classified by spelling | red-green: delete a row; add a bogus row; rename a verb in source; **add `case '--serve':` falling through with `serve`** |
| **A2** | A declared alias must appear as a case label and its fall-through group must contain a verb that has a row. A stale alias declaration, and a group of aliases with no row-backed verb, are both errors | red-green: an alias-only group; an alias declared but absent from source |
| **A3** | Every verb named in `usage()`'s help text is a dispatched case label. One direction only: an advertised verb that is not dispatched is a lie; a dispatched verb that is undocumented is a choice | red-green: remove a dispatched verb the help text still advertises |
| **A4** | Every path `src/router.ts` itself compares against `url.pathname`, and every JSON-RPC method it registers, has an `mcp` row; every `mcp` row is one of those. The `isControlPath` delegation is **out of scope by construction** — those paths carry `control` rows — and the check asserts the delegation still exists so it cannot vanish unnoticed | red-green: delete a row; add a bogus row; remove a handler; remove the delegation |
| **A5** | JSON-RPC method names come from the SDK schema, not a hand table | red-green: **change the method literal in the installed SDK** and watch the extractor follow it to the new name |
| **A6** | Each extractor is paired with an independent count, in the shape `parity-manifest-check.sh:84-101` already uses for control: a verb or path dispatched in a form the extractor cannot read is an error, not a silent absence. Extracting nothing is an environment failure (exit 2) | red-green: `if (cmd === 'doctor')` added **above** an intact switch; a `url.pathname` comparison the extractor cannot read |
| **A7** | `project` normalises exactly where it equals `basename(cwd)` of its own object and is non-empty | red-green: a body whose `project` is the **whole cwd** must stay RED; an empty `project` must stay RED; `mcp-router`, `my_project` and `my-tree` must all go green |
| **A8** | The worktree-path rule accepts any single-segment worktree name | red-green against a hyphenated name |
| **A9** | On the identical tree, **the per-row verdict set of the `fixture` group is identical from the repo root and from a worktree**, and `fixture-usage` reads proven from the repo root specifically. Coverage-number equality is explicitly **not** the criterion — §2 shows it is already true while D-o is live | the full gate from both places, rows diffed, before and after |
| **A10** | The derivation **reports** a row it would need; it never adds one. The denominator observed from both after-runs is recorded | the diff, plus both after-runs |
| **A11** | Every row id named in another row's note exists in the manifest | red-green: delete `control-auth-post-http` and watch `control-auth-post`'s citation break (§2.5) |
| **A12** | `usage-summary.json`'s per-project `calls` counts and `projectNames` array length are compared rather than normalised away | red-green: alter a `calls` count in a captured body |

---

## 5. Out of scope, and why

- **`divergence` (15 rows).** A declared divergence is a statement of intent. There is no source to
  derive it from; that is what declaring one means.
- **`pool`, `state`, `log` (8 rows).** These name scenarios a lane drives, not a surface a file
  exposes.
- **`install` (5 rows).** The first draft claimed deriving these "would mean inventing a source of
  truth"; review pointed out `install.sh` **is** one, and `surface.tsv` itself records that these
  rows were missing from the first census and that their absence raised coverage. The accurate
  statement is narrower: the rows name *scenarios* (`putting a cut-over machine back on TypeScript`)
  rather than tokens a grep can enumerate, so deriving them is a design problem, not a regex.
  Registered as `D-p4-c` rather than argued away.
- **`D-p4-a`** (the D6 acquisition race), §2.2.
- **Any change to either router.** P4 touches the harness only.
- **The cutover.** R4-C's, and the user's.

Note that A11 covers part of the residue from a different direction: it protects any row, in any
group, that another row's note names.

---

## 6. `D-v1g`, measured rather than assumed

> `D-v1g` says B23 and B44 are wrong as written and two real divergences are missing from R4's
> D-table. A divergence absent from that table reads as agreement. Confirm before changing anything;
> it came from a review, not a measurement.

Confirmed against the census the gate actually reads. `surface.tsv` carries five `div-r3` rows:

```
div-r3-d1  R3 D1 PATCH body 42 terminates the reference
div-r3-d2  R3 D2 PATCH body "hi" terminates the reference
div-r3-d3  R3 D3 PATCH body true terminates the reference
div-r3-d4  R3 D4 a bare %ZZ escape terminates the reference
div-r3-d5  R3 D5 a truncated escape terminates the reference
```

D1–D3 are exactly B44's subject (a primitive PATCH body) and D4–D5 are exactly B23's (a malformed
escape). **They are enumerated, and the `divergence` group reads 14 of 15 proven.** So the half of
`D-v1g` that says a divergence "reads as agreement" in the gate is **stale**: it was true of
`spec-R4.md`'s prose D-table, which lists D1–D7 only (R1's and R2's), and is not true of the file
the gate reconciles against.

What may still stand is the other half — that `spec-R3.md`'s B23 and B44 clause *prose* is wrong as
written. That is a documentation defect in another item's spec, it moves no parity row, and P4 does
not touch another item's spec. **No row added, denominator unmoved.** Reported to the orchestrator
with the correction that the finding should be re-pointed at `spec-R4.md`/`spec-R3.md` prose rather
than at the census.

---

## 7. Deferred children

| # | Child | Absorbed by | Why deferred |
|---|---|---|---|
| `D-p4-a` | `parity-pool.sh`'s D6 assertion is contention-sensitive | D1 / R4-C | §2.2. 8 of 8 isolated runs read 1; a full-gate run under load read 4. The lane reports a hard `fail`, which the gate renders as an undeclared DIVERGENCE — its loudest verdict — for a machine that was busy |
| `D-p4-b` | A fresh worktree cannot run the parity gate without `npm install && npm run build` | G1 | All ten lanes exit 2 with "no built reference", which reads as a broken harness rather than an unbuilt worktree. Each message is accurate; the *sequence* is undiscoverable |
| `D-p4-c` | Derive the 5 `install` rows from `install.sh` | D1 | §5. They name scenarios, not tokens; it needs a design, not a regex |
| `D-p4-d` | `spec-R4.md`'s prose D-table lists only D1–D7 | R4-C | §6. The census is complete and the doc is not; a reader who trusts the doc under-counts the declared divergences |

---

## 8. Not fixed, deliberately

- The 28 remaining hand-written rows (§5), less whatever A11 protects.
- A directory name containing an escaped `"` still defeats the path rules. It fails **closed** — a
  mismatch, never a false pass — and is not worth machinery.

---

## 9. Status

`Ready to merge` is claimed only in §11, from measurements, after the gates in `plan-P4.md`.

---

## 10. Review — grok-4.6, adversarial, AMEND

Lane: `grok --model grok-4.6 -p` (out-of-family; codex is account-limited to 2026-08-20 and was not
probed). Smoke-tested before use, because grok exits 0 when session init fails — the probe returned
real content, not an error payload. Prompt `/tmp/p4-spec-review-prompt.txt` (gone), response
`/tmp/p4-spec-review.txt` (gone). Verdict **AMEND**, 6 findings.

| # | Finding | Disposition |
|---|---|---|
| 1 | A9 ("same coverage from both places") is **already true** and does not detect D-o; the two totals coincide at 73 while diverging on different rows | **Accepted, verified.** A9 rewritten as a row-level identity on the `fixture` group; §2 now states the coincidence explicitly |
| 2 | `"project":"[^"]+"` **over-normalises**: a regression putting the whole cwd in `project` is rewritten to `<repo>` by an earlier rule and then to `<project>`, hiding it | **Accepted, verified** against `usage.ts:305-306` and the substitution order. Character-class widening abandoned for §3.2's structural rule |
| 3 | The extractor is not mechanical — "a label beginning with `-` is a flag" is an invented taxonomy; `case '--serve':` grows the CLI surface with no row and no error. And `if (cmd === 'doctor')` above an intact switch defeats it entirely | **Accepted.** The heuristic is gone: every label is a row or a *declared* alias, and an undeclared label is an error (A1/A2). Independent-count guard added (A6) |
| 4 | A10/A11 true by construction or restatements | **Accepted.** A10 restated as a reporting obligation; the old A11 folded into A1/A4; A11 is now the cited-row-id check |
| 5 | §5's `install` argument is an excuse — `install.sh` is a source of truth | **Accepted in part.** Argument narrowed and honest; registered as `D-p4-c` rather than dismissed |
| 6 | Six unsupported claims: 13 vs **12** case labels; a dangling §9 reference; D-v1g possibly stale; **the "40 mechanical rows" are not a safe set (`control-auth-post` / `control-auth-post-http`)**; the 8-of-8 D6 runs cited no logs | **All accepted, all verified.** Count corrected; §6 now carries the measurement; §2.5 added and A11 written to close the hole; log paths cited |

Finding 6's auth-pair hole was reproduced against `surface.tsv` and is the strongest thing the
review produced: it is D-n's exact failure mode inside the group the first draft used as its
counter-example. Nothing was rejected.
