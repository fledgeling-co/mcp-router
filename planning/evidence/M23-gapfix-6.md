# M23 gap-fix 6 — the report marker, enumerated

The five previous passes each armed `REPORT_MARKER` on the routes they knew about, and each next
verification found more. This pass replaces the method: enumerate every site the marker can be
emitted from and every route reaching each, argue the enumeration from the code, assert per route,
and leave a check behind so the enumeration cannot quietly go stale.

Engine and `mock-fidelity-gate.sh` are byte-identical to the branch base throughout
(`0ad79d1b…` and `2229940e…`, verified after every mutation arm below). Only the selftest changed.

## The enumeration

`mock-fidelity-gate.sh` decides between `ledger written to <path>` and `NO ledger was written by
this run` on one `grep -qF "mock-fidelity: report written to $LEDGER" "$ENGINE_LOG"`. Anything that
satisfies that grep has to put those bytes on a stream the script captures, so the question closes
by finding every place the engine can print them.

**Completeness, from the code rather than from search effort:**

1. `grep -n "report written to" mock_fidelity.py` returns one line — the module constant
   `REPORT_MARKER` at line 115. There is no second literal, no f-string and no `.format` spelling it.
2. That constant is read at exactly two places, both `emit(REPORT_MARKER + …)`.
3. Nothing in the engine reaches a module global under another name: it contains no `getattr(`,
   no `vars(` and no `__dict__`. The enumeration rests on that, so case 60 re-checks it rather than
   relying on case 46 having checked it for a different reason.

**Two emission sites:**

| | Site | Entered when |
|---|---|---|
| S1 | `gate()`, after `write_report` returned and `run.report_written` was set | `--report` given and the write returned |
| S2 | the tail of `write_unmeasured_report`, after the obituary was written | `path` truthy and `open()` accepted it |

**S2's five callers, which is the other half:**

| | Call site | Reached when |
|---|---|---|
| R1 | `gate()` | the manifest failed to load |
| R2 | `gate().unmeasured()` | one of six manifest-validation returns |
| R3 | `gate()` | `Context` construction or `load` raised |
| R4 | `gate()` | `write_report` raised |
| R5 | `main()` | something escaped `gate()` with the report unwritten |

Six route classes. `unmeasured()` fans out to six validation returns, which are indistinguishable
at the marker — same call, same argument shape — so they are one class rather than six.

## What the suite did before this pass

Measured by tracing the two emission lines across every engine process the suite starts, with a
`sitecustomize.py` on `PYTHONPATH` rather than by editing the engine:

- **145 python3 processes, of which 52 are the engine**, 10 of those with `--report`. Without
  `--report`, `write_unmeasured_report` returns at `if not path` and no marker is possible, which
  is why 42 of the engine's runs are irrelevant to it. *Corrected on the seventh pass* (`D-m23-bc`):
  this line read "145 engine runs", which is every python3 process the suite starts — the fixture
  builder and the affordance tool included. Re-measured on the same 59-case suite with a
  `sitecustomize.py` logging argv: 145 processes, 52 the engine, 10 with `--report`, 0 `python3 -c`.
  Every emission figure below is unaffected; only the population was over-counted, 2.8x.
- **Eight marker emissions**: five at S1 (cases 43, 44 twice, 51's first and fourth invocations),
  three at S2 — through R2 once (case 32) and R3 twice (cases 23 and 49).
- **R1 was executed by nothing at all.**
- R4 was executed once, by case 51's third invocation, where the write fails and the WARNING branch
  runs instead of the marker.
- R5 was executed once, by case 50, with `path` None because no `expect()` case passes `--report`.

That corrects `D-m23-at`, which says three of the five call sites "are executed by no case". Only
R1 is. Its conclusion — three of five never reach the marker — holds.

## Per-route assertions now

| Route | Assertion | Case |
|---|---|---|
| S1 | present on a write that returned; spelled as the CALLER spelled the path; survives a console that cannot encode the report; reaches stderr when stdout is dead | 51 (1st, 4th), 43, 44 |
| R1 | present, with the obituary replacing a planted stale table | 61 (new) |
| R2 | present | 32 |
| R3 | present | 49 |
| R4 | **absent**, with `could not be replaced` — this is the route whose write failed | 51 (3rd) |
| R5 | unreachable with a report path; wiring pinned structurally | 60 (new) |
| consumer | all three branches of the gate script's decision, both emission sites, both non-zero verdicts | 62–67 (new) |

**Why R5 cannot reach the marker with `--report` set.** `gate()` either returns 3 from R1–R4
without raising, or it reaches the report block — and if it reaches the report block,
`run.report_written` is true before anything downstream can raise, so `main()`'s handler takes its
other branch. Everything between the argument parse and the report block is either inside a
`measuring()` boundary, a validation that returns rather than raises, or a statement that cannot
raise. The claim is checkable rather than prose: the ordering that makes R5 reachable with a path is
the report write moved back after the console loop, and case 43 goes red under it on three clauses.

## The eleven arms

Each applied to a `cp` backup's copy, run, then restored; engine and gate script sha256-verified
after every restore. Baseline: exit 0, 67 cases, 67 ok.

| # | Mutation | Before this pass | Now |
|---|---|---|---|
| 1 | `os.path.normpath(report_path)` on S1 | **invisible** — 59 ok, 0 FAIL | 1 at 66 ok — **case 51 alone** |
| 2 | S2's `emit` moved into R3's call site | **invisible** — 59 ok, 0 FAIL | 1 at 64 ok — cases 32, 60, 61 |
| 3 | S1's `emit` → a bare `print` | **invisible** — 59 ok, 0 FAIL | 1 at 65 ok — cases 44, 60 |
| 4 | gate: affirmation guarded on `[ $status -ne 3 ]` | **invisible** — 59 ok, 0 FAIL | 1 at 65 ok — cases 66, 67 |
| 5 | gate: marker grep → `[ -s "$ENGINE_LOG" ]` | **invisible** — 59 ok, 0 FAIL | 1 at 64 ok — cases 60, 64, 65 |
| 6 | S2's `emit` deleted | visible — 1 FAIL, case 49 | 1 at 62 ok — cases 32, 49, 60, 61, 67 |
| 7 | report write moved after the console loop | visible — 2 FAIL | 1 at 65 ok — cases 43, 44 |
| 8 | a sixth caller of `write_unmeasured_report` | **invisible** — 59 ok, 0 FAIL | 1 at 66 ok — **case 60 alone** |
| 9 | `run.report_path` dropped for the local | **invisible** — 59 ok, 0 FAIL | 1 at 66 ok — **case 60 alone** |
| 10 | gate: `set -uo pipefail` → `set -euo pipefail` | **invisible** — 59 ok, 0 FAIL | 1 at 61 ok — all six gate cases |
| 11 | gate: marker grep → `[ -f "$LEDGER" ]` | **invisible** — 59 ok, 0 FAIL | 1 at 65 ok — cases 60, 64 |

**Nine of the eleven were invisible to the shipped suite** — arms 1-5 and 8-11 each ran 59 ok with
0 FAIL, and only 6 and 7 were visible. *Corrected on the seventh pass* (`D-m23-bb`): this pass
reported five, everywhere except this table. The column carried one fact under two wordings, "all
59 green" and "invisible", and the summary counted one of them. The error **understates** the pass,
and the table it contradicted was sitting directly beneath it.

Arm 7 is the one that shows R5 becoming reachable: under that ordering the marker is still
emitted, from S2 through R5, and what goes red is the table and the diagnostic naming it.

## The harness, adopted

The selftest declared the gate script's console decision uncoverable, and gave a reason —
"the MEASURE build and four rendered dumps, three minutes and not hermetic" — that was measurably
false. It needs a symlinked gate script (bash does not resolve a symlink in `$0`, the same fact the
lint probe already relies on), the `swift` stub `build()` already writes, and a twelve-line
`MeasureDump` that refuses an unreadable `--state` and otherwise copies the dump the fixture
already generated. Reached in about a second; the whole suite's wall time did not move.

Six cases drive it: the affirmation on a clean run and on a findings run (which also pins
`${PIPESTATUS[0]}` — the engine's exit rather than `tee`'s), the denial with a stale table at the
path, the third sentence with no file there at all, exit 3 with a real table, and exit 3 with an
obituary. Both emission sites reach the consumer, and the four ways the block can be broken —
deleting the grep, inverting it, collapsing the denial branches, and guarding the affirmation on
the exit code — are four different edits, only the last of which a clean fixture cannot see.

## `D-m23-aw`: keeping the declared bounds true

The file had exactly one prose reachability declaration and it was the false one. It is gone. What
replaces it is case 60, which re-derives the enumeration from the engine's syntax tree on every
run: the marker's single spelling, the two emission sites and their owning functions, that every
read goes out through `emit`, that `emit` still names stderr, the five callers and their owners,
the `Run` wiring that R5 depends on, and that the consumer still greps the marker at the path it
asked for. A third emission site or a sixth caller makes the route table above incomplete, and the
suite says so rather than a seventh verification finding it.

## Lanes

Read-only, from `/tmp`, against a copy — the standing rule. The worktree carried no mutation at any
point outside the eleven arms above, each restored and sha256-verified. Codex is down until 27
August; grok was not run.

- **`gemini-3.7-flash-high`** — 6,031 B. First attempt returned 0 B: headless mode auto-denied a
  tool permission, so the second run put the whole packet inline and needed no tools. Two live
  findings, both taken: the `run.report_path` cleanup (arm 9, `D-m23-ax`) and the `[ $status -ne 3 ]`
  guard on the gate's affirmation (arm 4). Three refutations, each naming the case that kills it,
  all three correct. Independently reached the same disproof of the prose declaration.
- **`claude-fable-5`** at high — 8,348 B. Two live findings, both taken: `set -euo pipefail`
  (arm 10, `D-m23-ay`) and the marker grep replaced by `[ -f "$LEDGER" ]` (arm 11). Seven
  refutations with the killing case named, including one it declined to file — dropping `2>&1` from
  the gate's pipeline — because it could not construct an observable delta. It named the structural
  fact both findings rest on: before this pass the selftest executed the gate script exactly once,
  down a path that returns at line 57, so **every line of the marker block had zero coverage** and
  any edit confined to it was green by construction.

Both lanes were asked to break rather than review, which is now the phrasing that has produced the
blocking finding on four consecutive passes of this item.
