
---

# Delivered — gap-fix 3

## The three shapes, each with its red and its green

Every one was found by a reader constructing source, and every one is pinned by a **one-token**
control: change the single token and the scan changes its answer. Both directions are in the tree.

| shape | before | control (one token changed) | after |
|---|---|---|---|
| `check: if awaitEvent(x) {` around a bare call | `3:BOUND` — a **miss** | label deleted → `3:UNBOUND` | `3:UNBOUND` |
| `await p.awaitReap(name: "own")` | `[]` — **no call site at all** | literal → identifier → `2:UNBOUND` | `2:UNBOUND` |
| `try await awaitEvent("reap at \(Task.currentPriority)") { … }` | `3:UNBOUND` — a **false fire** | `Task` → `Clock` → `3:BOUND` | `3:BOUND` |

**What each was.** `firstWord(of:)` returned `check`, so the `bodyKeywords` guard — added in round two
*because a lane broke exactly this* — never fired and a control-flow body read as the wrapper's
trailing closure. It now steps past a prefix that introduces a statement without being one, which
closed a `case`/`default` clause with it: `case .a: if awaitEvent(x) {` was the same miss through a
door nobody had opened, measured on the pre-fix scanner.

The second is one level up from where it showed. The delexer blanked comments and literals to the
same byte, and `awaitReap(name: "own")` therefore delexed to `awaitReap(name:    )` — the shape of
an unapplied method reference, which `callEnd` discards. **A comment is nothing and a literal is a
value**, and whitespace where a value stood is indistinguishable from absence. Literal bytes now
become `ScanByte.elided`, and so do non-ASCII code bytes, which was the same miss's other door:
`p.awaitReap(name: 名前)` was invisible for the same reason and is now a control.

The third ran the `escapes` test over the opener statement instead of over the callee receiving the
closure. An interpolation is code, so the word really was there. It now reads the owner of the brace.

## The directional claim, corrected

`G3-gapfix-2.md` said the remaining approximation's consequences "each fail toward a red on correct
source rather than toward a miss". That was **true of the three unreachable shapes it named and
false as a statement about the layer**, and the paragraph read as the second. A claim about which
way a residue fails decides whether the residue is tolerable, so the wording is corrected where it
was made, in the suite's doc comment, and in the register.

The corrected claim: **the layer fails both ways, and the direction is not predictable from it.**
The evidence is a count rather than an argument — of the twelve shapes measured against the
delivered scanner this pass, **eight fail toward a miss and four toward a red**:

- Blocking three: 2 misses, 1 false fire.
- The nine the lanes broke it with and this pass did not take (`D-g3-ah`): 6 misses, 3 reds.

A shape found in this layer is a defect until it is measured, not an inconvenience.

## Family C is stated, not closed

The count was one number over three populations of different kinds, and stating the split honestly
is the answer taken. `AwaitBoundControl`'s doc comment now reads:

- **Family A**, the lexical grammar — 19 controls, **closed**: a citable production list, one control
  per production.
- **Family B**, block structure — 12 controls, **closed**: brace nesting, which is what Swift uses.
- **Family C**, Swift's statement and trailing-closure grammar — 38 controls, **open**. `verdict`,
  `statement`, `firstWord`, `continuesStatement` and five keyword lists implement no grammar. Each
  control is a shape somebody wrote down, and the set of shapes somebody might write is exactly the
  open population the other two families escape. The count is a floor on coverage, not a bound on
  the space.

The mutation matrix is stated separately for the same reason: **69 controls, each seen to fail under
at least one of twelve single-mechanism mutations** proves that no mechanism in the code as written
is decorative. That is mutation adequacy of the implementation, and it is a different claim from
covering the grammar the implementation *should* have. Family C is where the two come apart, and
every defect of this round was in Family C.

`AwaitBoundScan` is now three files, split at that seam — the scan, the statement layer, and the
delexer — because the scan file passed SwiftLint's 400-line `file_length` default.

## `D-g3-q`: the derivation is withdrawn

Gap-fix 2 saw `PoolTests.swift:144` green 4 of 4 at 0% idle and derived a load-dependence from it.
The verifier ran the same mutation at 15.5% idle falling to 0.6% under 1-minute load 127 — *heavier*
contention than gap-fix 2 had — and got **both sites red 4 of 4**. Heavier load producing the site
that load was said to suppress refutes the explanation on its own terms. The register reverts to the
previous verifier's reading, and the deferral rests on **scope alone**, which was available the whole
time and needs no contested number: the remedy is `D-g3-g`, which is deferred, and the probe showing
`PROBE-EARLY-RETURN` 3 of 3 stands.
