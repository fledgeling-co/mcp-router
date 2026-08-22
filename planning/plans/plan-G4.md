# plan-G4 — Readers that cannot account for their own input

Branch `ai/g4` · worktree `.worktrees/G4` · base `72958de`
Spec: `planning/specs/spec-G4.md`

**Baselines measured on this tree before any change**, so a moved number is attributable:

| Gate | Before |
|---|---|
| `make test` | 0, **1684 tests in 209 suites**, measured twice |
| `python3 planning/ledger-reconcile.py` | 0 across A–L · H 85/skipped 21 · I 85 · J 470 · K 213 · L 1761 |
| `make lint` | needs `node_modules` and `dist/` — a fresh worktree has neither, so `npm install && npm run build` ran first |

The brief states main's baseline as 1686 tests in 210 suites. This tree measures 1684/209 twice,
and `git diff HEAD main` is four markdown files with nothing under `app/`, so the difference cannot
come from this branch. Recorded as a finding rather than absorbed.

---

## 1 · Order of work, and why this order

**Measure first.** The census is the denominator and stating it is most of the item's value, so the
detector is built and run before anything is declared or fixed. Building the declarations first
would make the census a description of the work rather than a measurement of the repository.

1. **Detector** (`reader-accounting.py`) — AST pass: find every iteration that decomposes raw input
   and discards an item; classify each reader by whether the discard is recorded and escapes.
2. **Census** — run it, read the population, and only then decide per reader between recording the
   drop and declaring it.
3. **Primitive** (`input_accounting.py`) — `Tally`, so recording is the short path.
4. **Adoption** — convert the readers where the drop is information the output should carry, and
   prove the reconciler's every pre-existing number is unchanged.
5. **Declarations** (`reader-accounting.tsv`) — one written reason per remaining reader; a drop
   nothing else covers is recorded as a `gap` rather than dressed as a design choice.
6. **Null-run gate** (`null-run-gate.py`) — arms against the hermetic instruments.
7. **Wire into `make lint`**, arm both, write the progress note.

## 2 · The two detector decisions that decide whether this is a gate or noise

### 2.1 The drop record must name the item

A rule that accepts "some escaping name was touched before the `continue`" accepts a bare
`examined += 1` at the top of a loop — a number that moves whether or not the drop happened. The
first cut of the detector did exactly that and then reported itself as the one accounting reader in
the repository, on the strength of a counter two lines above a `continue`. The contract's `dropped`
is a set of items, not a count, so the recorded value must mention a name bound inside the loop.

### 2.2 The subject is resolved syntactically, one binding deep, and the failures are printed

A general taint pass propagates through every container the program builds and ends up calling
`for state in self.states` a raw-input reader. So the iteration's subject must itself be a
*decomposition* of raw input — `.splitlines()`, `re.finditer`, `open`, a directory listing — with a
tainted base, followed through at most one unambiguous binding. A name assigned twice resolves to
nothing rather than to a guess.

That under-claims, and the count of what it could not resolve is printed on every run for exactly
the reason the gate demands a skip list of everything else. `ast.walk` versus `os.walk` is the
worked example: the first cut did not distinguish them, classified its own tree traversal as a
filesystem read, and that is the ambiguous binding the Google lane refused for name → quantity, one
layer down.

## 3 · Where the gates live

Inside `make lint`, beside the four script gates already there. Not a lane of their own: a lane of
its own is a lane somebody runs separately from `all`. Both are hermetic, need no simulator, node
build or router binary, and finish in under ten seconds together.

The brief's placement rule is that a known-red lane wired into `all` either blocks unrelated work or
gets its assertions softened. So the accounting gate lands **green over what it can already account
for**, with every current silent drop either recorded, declared, or listed as a `gap` that prints on
every run. It fails on a *new* silent drop, a stale declaration, a moved pin and a malformed row.

## 4 · Risk, and what it is bounded by

The only product-adjacent change is to `ledger-reconcile.py`, the fleet's memory-of-record
instrument. It is bounded by: nothing parses its stdout (grepped — it has no caller in the Makefile,
CI or any script), the three converted readers are pure functions, and every pre-existing printed
number is compared before and after. Four denominator lines are added; none is changed.

`no-wire-codable.sh` and `no-raw-design-values.sh` are read and run by the null-run gate in scratch
trees, never modified.

## 5 · Out of scope, and named

* Instances 2, 3, 7 and the `egress` one — they read a real quantity that is the wrong one and
  survive both mechanisms. §2 of the spec carries the table.
* Shell readers (66 files) — the accounting contract is Python only.
* Fixing `no-wire-codable.sh`'s zero-exemption defect, found by the null-run gate's first run. It is
  another item's gate; it is asserted as a known red in `WIRE-zero-exemptions` and filed in the
  progress note, on the same principle as P10 in `no-harness-config-writes-selftest.sh`.
