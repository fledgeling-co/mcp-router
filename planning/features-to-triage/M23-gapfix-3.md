# M23 gap-fix 3 — the property is wider than the site, three times running

**Parent:** M23 — The mock-to-SwiftUI conversion contract
**Status:** Untriaged · gap-fix, third pass
**Verdict that produced it:** Needs More Work, 2026-08-21, rung `effect-witness`
**Worktree:** `.worktrees/M23`, branch `ai/m23`, base `8622e91`

## Read this part before the findings

Three verdicts have now turned on one mechanism, and the findings below are its third
instance rather than three new problems. Each pass closed the route its finding named, and
each next verifier found the same property failing one frame, one consumer or one population
further out:

| pass | property | closed at | still failing at |
|---|---|---|---|
| 1 | `present` does not agree on nothing | two empty strings | two zero-width spaces |
| 2 | the boundary catches what cannot be measured | one exception class | one frame up |
| 3 | the boundary catches what cannot be measured | every layer and the report write | `main()`'s console loop, which runs *before* the write |

So the instruction for this pass is about method, not targets. **For each property, enumerate
what it quantifies over — every frame that can raise, every consumer that reads the structure,
every population a count could be taken on — and fix at the widest member. Then show the
enumeration and say how you know it is complete.** A fix that lands where the finding points
has been the failure mode three times; the acceptance below reads the enumeration, not the
patch.

The good news is that the blockers are getting cheaper, which is the convergence signal. Pass
2 needed an exception boundary designed. All three below are a moved line, an existing check
applied to a second caller, and a count taken on the right set.

## What is genuinely closed — do not reopen it

**B3's class holds by construction.** The verifier built the route this brief would have asked
for: **zero of 4,174** Default_Ignorable codepoints survive `readable()`, and the only
survivors named "blank" (U+2422, U+2423, U+FFFC, U+1D159) draw real glyphs. Leave it alone.

**The sixteen new checks are not vacuous.** Every one the verifier could reach has a
demonstrated firing input — `matched=garbage` → exit 3; `unrelated=0` → exit 3 quoting
`KeyError('stray')`; an unparseable scan line → exit 3; `--report` with no path → exit 2; and
`run()`'s `UnicodeDecodeError` branch is reachable because `subprocess.run(text=True)` does
raise on invalid UTF-8. "None of the sixteen moves a number on the real surface" is the
correct outcome here, and it has been distinguished from the vacuous one that looks identical.

**The census reproduces exactly.** An independent run of the shipped engine against the real
dumps rebuilds the committed `servers.ledger.md` byte for byte, the arithmetic closes at 149
rows and 132 findings, and `D-m23-l` moved exactly two rows —
`loading/v-loading/card/unlabelled` and `error/v-error/button/start-the-router`, both
`divergent`→`unclassified`, with every other cell unchanged.

## BL-1 — B2's property, through the frame one further out

`main()`'s console print loop (lines 1038–1057) sits outside every `measuring()`, and
`write_report` is at line 1058, **after** it. An exception in that loop gives a traceback,
**exit 1**, no report written, and the stale committed ledger intact — while
`mock-fidelity-gate.sh` prints `ledger written to …` immediately afterwards, which is the
sentence the pass-2 work order quotes as the failure it was closing.

Settled at `effect-witness`: a sentinel file planted at the report path, the engine run as a
separate OS process, and the filesystem read back to establish no write happened.

Two demonstrated instances: a non-UTF-8 stdout (`PYTHONIOENCODING=ascii`, or
`PYTHONCOERCECLOCALE=0 PYTHONUTF8=0 LC_ALL=C`) chokes on the `·` in the **first** layer line
at position 25; and a lone surrogate in a dump string. Two things that do **not** fire it, so
nobody re-derives them: bare `LC_ALL=C` (PEP 538 coercion), and `| head` — `layer.findings[:400]`
caps stdout near 36 KB, under the 64 KB pipe buffer, confirmed by inflating a dump to 1600
extra nodes.

Fix is one line — write the report before the console loop, or wrap the loop. Then enumerate
what else in `main()` runs outside a boundary.

## BL-2 — B4's property, in the other consumer

The pass-2 work order asked for "an injectivity check on `self.pairs[state]`". The check went
into `layer_breadth` only. `layer_copy` reads the same structure with no claimant test.

Measured on the real surface: pointing two column-header affordances at one node gives breadth
`unclassified × 2` with *"whichever of them it does answer, the rest were never measured"* —
and three lines below, in the same log, copy emits `v-ideal/column-header/transport reads
"Transport" in the mock and "server" in the build`. That is a stated measured difference
against the control breadth has just declared unmeasured, with both counted into copy's
`paired strings` population.

Enumerate every reader of `self.pairs` before fixing, and fix at the structure rather than in
each reader if that is where the property lives.

## BL-3 — B1's property, on the wrong population

`layer_structure` sets `observations` to the nodes it **enumerated**, not the axis
declarations it **corroborated**. With 14 comparable nodes it prints `73 nodes across 4
states · clean`; with every `axis` key removed — zero comparisons — it prints the identical
line. So the layer-wide `observations == 0` guard cannot fire, and the `dumpNodes` floor is a
floor on the wrong quantity.

Reachable, not hypothetical: `axis` is `nil` wherever the kind does not stack, so a future
surface annotating leaves and texts while skipping containers produces the
"surface-with-nothing-instrumented diffs clean" case the floor's own message claims to
prevent.

The verifier ranks this the weakest of the three and says why: "nodes examined" is a
defensible census, and `across == down` already declares no-evidence honestly. It is blocking
only because B1's own code comment claims the property layer-wide. **If you conclude the
comment should change rather than the code, that is an acceptable resolution — argue it, and
make the comment state the quantity actually read.** This is the one place in this brief where
the right answer may be to narrow the claim instead of widening the check. G4 is the register
for that shape, and either direction closes it.

## D-m23-s: the deferral reason does not survive measurement

Pass 2 deferred `D-m23-s` on the ground that "filtering copy's population moves the finding
count acceptance 6 pins at 16." Measured: filtering copy to vouched pairings only gives **19
paired strings · 16 findings**, gate total still **132** — the population moves, the pinned
number does not. Filtering copy for injectivity alone, which is BL-2's remedy, moves
**neither**: 20 paired strings, 16 findings, unchanged, because there are no duplicate
pairings on today's surface.

The stated obstacle to touching copy does not exist, so `D-m23-s` comes out of the deferred
register and into this pass. It is also the same fix as BL-2 approached from the other side —
`D-m23-l` one layer over — so treat them as one property with two symptoms.

## Acceptance

Each item states the property, the enumeration it quantifies over, and how the enumeration was
established as complete.

1. **BL-1**: an exception anywhere in `main()` outside a layer produces exit 3 and a written
   report, not exit 1 and a stale ledger. Arm it with the non-UTF-8 stdout route and with one
   route of your own from the enumeration. `mock-fidelity-gate.sh` must not state a ledger was
   written when none was.
2. **BL-2 + `D-m23-s`**: every reader of `self.pairs` applies the claimant test, and the
   contradiction between breadth's `unclassified` and copy's stated difference cannot occur.
   Name the readers and how you enumerated them. Finding count stays 16, gate total 132 — the
   verifier has already measured that it does.
3. **BL-3**: either `observations` counts corroborated comparisons, or the comment and the
   floor message state the quantity actually read. Whichever, removing every `axis` key must
   not print the same line as a fully-instrumented surface.
4. The three closed things stay closed: 4,174 Default_Ignorable codepoints still all fail
   `readable()`; every new check still has a demonstrated firing input; the ledger still
   rebuilds byte-for-byte.
5. A route nobody has named, for each of the three. Pass 2 claimed this and the verifier found
   three more — so state, for each, why you believe the enumeration is now exhaustive rather
   than merely longer.

## Corrections to carry

`M23-gapfix-2-review.md` says `paired_nodes` is read at five sites; it is **four** — lines 718
and 722 (the two prefix tests), 739 (surface check), 759 (sibling census); 602 is the write
and 562 the init. The refutation of the dead-code finding stands; only the count is wrong.

## Scope

The fidelity engine, `mock-fidelity-gate.sh`, the selftest, and this item's briefs and
register rows. `D-m23-s` is in scope. `D-m23-x` … `D-m23-ab` are registered and deferred —
except that `D-m23-y` is the console sentence BL-1's acceptance already covers, so fixing it
falls out of BL-1 and should.
