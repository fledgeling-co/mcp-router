# G8: a question answered at the wrong scope returns a clean answer

**Category:** harness · **Brief:** `planning/features-to-triage/G8-a-question-answered-at-the-wrong-scope.md`
**Related:** G7 (a citation that does not resolve where it is read), G4 (assertions that do not read
their own quantity), M16 (the cross-branch role-intersection reduction).

`lukerhodes-2f` stated the item better than the evidence does: **a citation that does not resolve
announces itself when someone follows it; a question answered at the wrong scope returns a clean
answer.** No dangling pointer, no missing file, no red — a correct answer to a narrower question
than the one that mattered, indistinguishable from a correct answer to the right one.

---

## 1 · What had already landed, and what it does not reach

Two of the brief's three scope items are on `main` and this spec does not re-do them.

| Owed by the brief | Where it landed | Frame |
|---|---|---|
| M16's reduction written into `mock_fidelity.py`'s header, with *zero diff means no conflict; it does not mean no exposure* travelling with it | `scripts/acceptance/mock_fidelity.py`, the Cross-Branch Role-Intersection and Scope-Completeness Invariant | `49eae13` |
| the rule made runnable rather than written down | `planning/role-intersection-gate.py`, `make role-intersection` | `49eae13` |
| a presence control on every absence sweep, and a gate that runs them | `planning/sweep-control-gate.py`, in `make lint` | `49eae13` |

**What none of them reaches is the first half of the item's own sentence.** `sweep-control-gate.py`
requires every absence sweep to plant a known instance and confirm the instrument sees it. That
proves an instrument is not **blind**. It says nothing about whether the instrument was pointed at
the right **set**, and the two failures are indistinguishable from outside — measured, in §2.

## 2 · The measurement, taken 2026-08-29 at `49eae13`

`git ls-files` with no `-C` enumerates **the caller's directory downwards**, not the repository:

| run from | `git ls-files \| wc -l` |
|---|---|
| the repository root | 2163 |
| `planning/` | 955 |
| `scripts/` | 109 |

Three tracked instruments read their corpus that way. Each was run from the root and from
`scripts/`, at `49eae13`, before anything was changed:

| instrument | from the root | from `scripts/` |
|---|---|---|
| `planning/claim-sweep.py` | 11 blocking hits, **exit 1** | 0 hits, **exit 0** |
| `planning/py39-annotation-gate.py` | `swept 77 tracked .py files`, `control: HELD` | `swept 9 tracked .py files`, `control: HELD` |
| `planning/m33-branch-sweep.py` | `examined=233 affected=7 covered=0 n/a=226` | `examined=233 affected=0 covered=0 n/a=233` |

Three properties of that table are the whole item:

1. **`claim-sweep.py` is the file whose own docstring is the rule about reading the whole corpus.**
   It returned a clean exit over a corpus it had narrowed by 95%.
2. **`py39-annotation-gate.py` printed `control: HELD` in both columns.** Its presence control
   plants a union and confirms the parser finds it — which it does, in the nine files it was looking
   at. A presence control cannot see a scope failure, because the planted instance is inside the
   narrowed set by construction.
3. **`m33-branch-sweep.py` printed `affected=0` with a denominator of 233 beside it.** Its own
   header says *"the number it must never print is a bare `affected=0` with no denominator beside
   it"*. It satisfied that guard and was wrong anyway: the sweep exists to find the branches whose
   green `swift test` covered nothing under `app/MCPRouter/`, and from a subdirectory it reports
   that there are none.

## 3 · What this item builds

**`planning/scope-invariance-gate.py`**, in `make lint`, with two arms and its own controls.

- **Static.** Over every tracked `.py` file: a `git` invocation whose subcommand enumerates a corpus
  (`ls-files`, `ls-tree`, `grep`) must be anchored — `-C <root>`, or a `cwd=` that is not a literal
  relative path. `cwd="."` is the caller's directory under another name and counts as unanchored.
- **Dynamic.** Each instrument named in `INVARIANT_RUNS` is executed from the repository root and
  from `planning/`, and must return the identical exit code and the identical stdout. This is the
  arm that runs the artifact instead of a model of it; the static rule is a claim about source text,
  and the failure in §2 is a claim about behaviour. When they disagree the report carries the first
  line of output that differs, because an exit code alone reports `0 vs 0` on the py39 instance.
- **Eight controls on every invocation**, five static and three dynamic, so a rule that flagged
  everything and a rule that flagged nothing both fail. A run whose controls did not all hold exits
  4 and prints no verdict.

And the three anchors: `claim-sweep.py`, `py39-annotation-gate.py` and `m33-branch-sweep.py`
enumerate under a root each derives from `__file__`, and read every path back under that same root.

## 4 · Success criteria

1. `python3 planning/scope-invariance-gate.py` exits 0 on the branch, and its eight controls hold.
2. Each of the three instruments in §2 produces **byte-identical stdout and exit code** from the
   repository root and from a subdirectory.
3. Each of the three produces the **same output at the root as it did before the change** — the
   anchor is a scope fix, not a behaviour change.
4. The gate goes red on a planted unanchored enumeration and green on its anchored twin, in a
   scratch tree, on every run.
5. `make lint` is exit 0 whole, with the new gate a member.

## 5 · Scope boundaries, stated rather than implied

- **Shell is declined.** An anchor in shell is a `cd` three lines earlier, and a text scan cannot
  tell that from its absence. The gate measures how much it is declining — it counts and names
  tracked `.sh` files invoking an enumerating git subcommand, one today
  (`scripts/acceptance/carrier-census.sh` at `b25ceb0a1282aa7229074efd1f32a5ce5761aaf7` (historical source), which `cd`s to a root it derives). The day a second
  appears, that line changes and nobody has to remember this paragraph.
- **An argv this reader cannot resolve is named, never assumed clean.** Nine today.
- **Whether the anchored root is the *right* root is out of scope.** A gate rooted at the wrong
  repository is anchored and wrong, and nothing here would see it.
- **`claim-sweep.py` is not in the per-run dynamic set.** It reads all 2163 tracked files whole,
  ~12s CPU per run; its invariance is measured once, by hand, with the command recorded in
  `planning/evidence/G8/scope-invariance.md`. The gate prints that decline on every run.

## 6 · Assumptions

- **A1** — The dynamic arm's second working directory is `planning/`, because it is tracked, always
  present, and holds only a fraction of the corpus. Alternative rejected: a scratch directory
  outside the repository, which would exercise git's not-a-repository path instead of the narrowing
  this item is about.
- **A2** — Anchoring is checked, not root correctness. A gate that verified the derived root would
  have to know which repository each instrument means, which is a second item and not this one.
- **A3** — The static population is Python. It is the population where an anchor is decidable from
  the source text alone; §5 records what that costs and measures it on every run.
