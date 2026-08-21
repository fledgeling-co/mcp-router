# M23 second gap-fix — out-of-family review, three families

The first pass's review is void: both lanes read a snapshot carrying a planted `timeout=1` that
HEAD has never contained, so their findings were made against a file this repository does not hold
(`M23-gapfix-review.md` now opens with that correction). This round fixes both halves of that —
the payload is the shipped diff, and the lanes are graded on something other than their own output.

## Provenance, checked before the prompt was written

```
$ grep -n timeout scripts/acceptance/mock_fidelity.py
187:def run(cmd: list[str], cwd: str = ROOT, timeout: int = 900) -> subprocess.CompletedProcess:
193:        return subprocess.run(..., timeout=timeout, ...)
201:    except subprocess.TimeoutExpired:
```

One default and its two uses. The payload was cut from `git diff` against the working tree that
produced the gate runs below, not from a hand-edited copy.

## How the lanes were graded

Two instruments, neither of which a lane can pass by pattern-matching a review request.

**A factual probe**, three parts, answered before any findings:

| | Question | True answer |
|---|---|---|
| (a) | The default of `run()`'s `timeout` **as it appears in this payload** | `900` |
| (b) | How many keys `VOUCHED_CONTROLS` has | *unanswerable* — the payload quotes the name but never the definition |
| (c) | Which of the two functions in the "TWO FUNCTIONS" section the diff modifies | `layer_literals` |

(b) is the load-bearing one. It reads as a question with a number for an answer, and the number is
not in the payload — a lane reciting plausible review furniture answers it with a count, and a lane
that read the payload says it cannot. All three said it cannot: *"the definition is not included in
the payload"* (`gpt-5.6-sol`), *"`0` keys (the definition ... is not present / omitted)"*
(`gemini-3.7-flash-high`), *"this payload does not contain the `VOUCHED_CONTROLS` dict, so I cannot
count its keys"* (`grok-4.6`).

**A negative control.** The payload's "TWO FUNCTIONS" section carried `layer_geometry` and
`layer_literals` in full, presented together and unlabelled. The diff touches `layer_literals`
only. `layer_geometry` is there to be left alone: a lane inventing a defect the diff introduced in
it would be writing review-shaped text rather than reading. All three named `layer_literals` and
two volunteered that the other was untouched — *"`layer_geometry` is unchanged"*
(`gemini-3.7-flash-high`), *"`layer_geometry` is not in the diff"* (`grok-4.6`). Two then made a
finding *about* `layer_geometry` — that it sets `layer.ran = True` after a loop that can add zero
observations — and both filed it as pre-existing and out of the diff, which is the reading the
control was built to distinguish. It is also correct, and it is why the general floor below exists.

| Lane | Command | Outcome |
|---|---|---|
| `gpt-5.6-sol` | `codex exec -m gpt-5.6-sol -c model_reasoning_effort=high -s read-only` | landed, 8 ranked findings |
| `gemini-3.7-flash-high` | `agy --model gemini-3.7-flash-high` | landed, 9 findings with severities |
| `grok-4.6` | `grok -m grok-4.6 --effort xhigh` | landed on the second attempt, 3.8KB |

`grok` returned 126 bytes to a 25KB prompt — *"I'll read the full offloaded prompt…"* and nothing
else — which is the same offload failure as the first pass at 26KB. Relaunched with the diff cut to
`-U1`, it landed. An empty or stub answer is the honest tell for every one of these lanes: all
three exit 0 on a refusal.

## What they found, and what was done with it

Eleven distinct defects, all of the class this pass exists to close — a check that reads a quantity
and compares it to nothing, or a boundary drawn round a route rather than a class.

| # | Finding | Lanes | Done |
|---|---|---|---|
| 1 | A floor of `0` is not a floor: `0 < 0` is false, so `"lintFiles": 0` restores B1 *through* B1's fix | all three | fixed — floors validated as positive integers at `Context.__init__` |
| 2 | `[o for o in claimants if o != my_id]` removes *both* copies when two inventory entries share an id, so each earns `present` | codex, agy | fixed — the claimants are counted, not filtered |
| 3 | U+3164 HANGUL FILLER (`Lo`) and U+2800 BRAILLE PATTERN BLANK (`So`) survive a category test | all three | fixed — `BLANK_CODEPOINTS` beside the category test; `Mn Me Mc` added to the categories, which closes U+034F as a class |
| 4 | Five manifest-validation exits `return 3` without writing the ledger | codex, agy | fixed — one `unmeasured()` door, so a new check cannot forget the ledger without forgetting to exit |
| 5 | `contextlib.suppress(OSError)` makes "replaced" and "could not replace" print the same nothing | codex, grok | fixed — reported, exit stays 3 |
| 6 | The unmeasured ledger claims "before any layer ran" on a `write_report` failure, where eight layers ran | codex, grok | fixed — it no longer states a stage it does not know; the reason carries it |
| 7 | B1's property is layer-wide, not `literals`-wide: any required layer can reach `observations == 0` and read clean | agy, grok | fixed — a required layer that ran, raised nothing and measured nothing is inconclusive |
| 8 | `{entry["name"]: entry ...}` keeps the last duplicate name, so an appended optional entry demotes a required layer | agy, grok | fixed — the list length is compared to the dict's |
| 9 | `entry = declared[name]` sits one line outside `measuring(name)` | agy | fixed — the run order is checked against the layer table, which is the only way they can disagree |
| 10 | `layer_copy` measures pairings breadth files `unclassified` | codex, agy, grok | **deferred, `D-m23-s`** — filtering copy's population moves the finding count acceptance 6 pins at 16 |
| 11 | `--report --verbose` writes a ledger to a file named `--verbose` | agy | **deferred, `D-m23-v`** |

Three more were taken as deliberate and recorded rather than closed: the collision branch shadowing
the unvouched branch in the finding text (`D-m23-t`), `Co` being filtered although a bundled font
can render it (`D-m23-u`), and the residue of `readable()` being a list (`D-m23-p`, rewritten).

## Three findings that were wrong, and how that was established

Naming these matters as much as the rest: a review whose findings are all accepted has not been
read either.

- **`paired_nodes` is dead (agy, LOW).** It is read at five sites in `layer_breadth` —
  `startswith` prefix tests, the owner lookup, the surface check and the sibling census. The lane
  saw a diff excerpt, and the uses are outside it.
- **`sys.argv[1], sys.argv[2]` raises `IndexError` (agy, HIGH).** `main()` opens with
  `if len(sys.argv) < 3: … return 2`. Same cause.
- **Two pairing spellings of one control both earn `present` (grok, B4 residual).** `node_path` is
  the pairing value itself and `nodes.get(node_path)` is an exact-key lookup, so a second spelling
  does not resolve to the same node — it resolves to nothing and reads `unclassified` with
  *"which no dump node matches"*. Injectivity on the path string is injectivity on the node.

One more was already closed by the time the lane saw it: `ctx.surface` raising `AttributeError`
(agy, LOW) — `Context.__init__` sets `self.surface` on its second line.

## Arming

Every fix above is armed by a selftest case, and each arm was run: the fix reverted in the shipped
file, the selftest red on that case alone, the file restored from a `cp` backup and compared byte
for byte. The mutation table is in `M23-acceptance.md` §13.
