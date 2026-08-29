# G8 — evidence: an instrument's answer moving with the caller's working directory

Every figure below is a verdict line, transcribed from a run whose command is in the header above
it. No raw gate capture is pasted: a capture quotes `path:line` out of the gates' own findings text,
and committing one turns a green lint red on the act of recording it.

Base frame for every "before" run: `main` at `49eae13`, worktree `.worktrees/L4`, 2026-08-29.
"After" runs are the same tree with the anchors applied.

---

## 1 · The mechanism

```
git ls-files | wc -l          # from the repository root, from planning/, from scripts/
```

| run from | paths returned |
|---|---|
| the repository root | 2163 |
| `planning/` | 955 |
| `scripts/` | 109 |

`git ls-files` with no `-C` takes its pathspec from the process's working directory. An
enumeration written without an anchor answers about a subtree.

## 2 · `planning/claim-sweep.py`

```
python3 planning/claim-sweep.py                     # cwd = repository root
cd scripts && python3 ../planning/claim-sweep.py    # cwd = scripts/
```

| | before, from the root | before, from `scripts/` | after, from the root | after, from `scripts/` |
|---|---|---|---|---|
| `scanned N tracked files` | 1898 | — | 1898 | 1898 |
| `blocking classes A1+A2+A3 total` | 11 | **0** | 11 | 11 |
| exit | 1 | **0** | 1 | 1 |

The after-columns are byte-identical files, checked with `diff -q`, and the after-root output is
byte-identical to the before-root output — the anchor changed where it looked and nothing else.

Unanchored call site: `planning/claim-sweep.py:125` at `49eae13`.

## 3 · `planning/py39-annotation-gate.py`

```
python3 planning/py39-annotation-gate.py                       # cwd = repository root
cd scripts && python3 ../planning/py39-annotation-gate.py      # cwd = scripts/
```

| | before, root | before, `scripts/` | after, root | after, `scripts/` |
|---|---|---|---|---|
| `swept N tracked .py files` | 77 | **9** | 77 | 77 |
| `N file(s) carry a PEP 604 union` | 0 | 0 | 0 | 0 |
| `control:` | HELD | **HELD** | HELD | HELD |
| exit | 0 | 0 | 0 | 0 |

**The control held in the narrowed column.** A presence control plants an instance and confirms the
instrument can see it; the planted instance is inside the narrowed set by construction, so a scope
failure is invisible to it. That is why this gate exists beside `sweep-control-gate.py` rather than
inside it.

Unanchored call site: `planning/py39-annotation-gate.py:55` at `49eae13`.

## 4 · `planning/m33-branch-sweep.py`

```
python3 planning/m33-branch-sweep.py                       # cwd = repository root
cd scripts && python3 ../planning/m33-branch-sweep.py      # cwd = scripts/
```

| | before, root | before, `scripts/` | after, root | after, `scripts/` |
|---|---|---|---|---|
| verdict line | `examined=233 affected=7 covered=0 n/a=226` | `examined=233 affected=0 covered=0 n/a=233` | `examined=233 affected=7 covered=0 n/a=226` | `examined=233 affected=7 covered=0 n/a=226` |

The sweep exists to find the branches whose green `swift test` covered nothing under
`app/MCPRouter/`. From a subdirectory it reports that there are none — with a full denominator
beside the zero, which is the one guard its own header names.

Unanchored call site: `planning/m33-branch-sweep.py:65` at `49eae13`, a wrapper passing `cwd=None`
explicitly.

## 5 · The gate, red then green

```
python3 planning/scope-invariance-gate.py
```

**Before the anchors** — exit 1:

> `FINDINGS scope-invariance: 3 unanchored enumeration(s), 1 instrument(s) whose answer moved with its cwd.`

and the invariant row carried the disagreement itself rather than an exit code:

> `invariant MOVED  planning/py39-annotation-gate.py  root: exit 0 · swept 77 tracked .py files … · planning/: exit 0 · swept 57 tracked .py files …`

(57 rather than 9 because the second directory the gate uses is `planning/`, not `scripts/`.)

**After the anchors** — exit 0:

> `CLEAN scope-invariance: 70 tracked .py files, 0 unanchored enumerations, 1 instrument(s) proved cwd-invariant by running them.`

## 6 · Controls

```
python3 planning/scope-invariance-gate.py --selftest
```

Eight arms, all held, exit 0. Five static — an unanchored `ls-files` reported; `-C <root>` not
reported; `cwd=root` not reported; `cwd="."` reported; `git rev-parse HEAD` not reported. Two
dynamic, in a scratch repository under `mktemp` — a planted cwd-sensitive enumerator caught by the
comparison, its anchored twin passing it. One null — a corpus of zero files is a refusal.

A rule that flagged every git call fails three static arms; a rule that flagged none fails two. A
dynamic comparison that could only agree fails the first dynamic arm.

## 7 · What this run did not measure

- **Shell.** One tracked `.sh` file invokes an enumerating git subcommand
  (`scripts/acceptance/carrier-census.sh`) and it is anchored by a `cd` to a root it derives — the
  form a text scan cannot distinguish from its absence. Counted and named on every gate run.
- **Nine argv sites** built from a registry or a parameter, which this reader resolves one binding
  deep and no further. Counted and named on every gate run.
- **Whether an anchored root is the right root.** Out of scope, recorded in the spec's §5.
