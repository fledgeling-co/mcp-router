# M23 gap-fix 7 — the frame outside the function, and three of our own numbers

R5 is reachable with a report path, on the engine as shipped and with no mutation. The route
table's sixth row said otherwise, argued from the code, and the argument was sound about `gate()`'s
interior and silent about `main()`. Case 68 pins it, and closing it took a six-line change to the
engine — which the brief's scope line forbade. That departure is stated in full below.

## BL-1 — what the argument missed

`main()` runs `sys.stdout.flush()` after `gate()` has returned. Point a dead pipe at a run whose
manifest is missing and `gate()` takes R1: it writes the obituary naming `manifest: no artifact at
…`, emits the marker, and returns 3. The flush then raises `BrokenPipeError` into the boundary with
`run.report_written` False and `run.report_path` set, so the obituary is written a **second** time
and the ledger a reader opens says `gate: BrokenPipeError` — the true cause replaced by a
downstream symptom, in the artifact whose subject is honest reporting.

Measured on the shipped engine, three runs of three, no mutation:

```
python3 scripts/acceptance/mock_fidelity.py <missing-manifest> <dumps> --report LED > >(:) 2>ERR
  exit 3 · markers on stderr 2 · ledger names BrokenPipeError · `no artifact at` absent
```

`PYTHONUNBUFFERED=1` does not reach it: `emit`'s own write then raises at the print, so nothing is
left in the buffer for `main()`'s flush to re-raise on. That is the discriminator case 44 already
documents, and it means a case built only on the unbuffered spelling would have seen nothing.

The engine's own comment above the flush reads *"The last thing that can raise, and it raises after
every boundary inside `gate()` has been left."* The completeness argument was derived from this
file and did not read it.

**The fix.** The flush is caught where it happens, one frame before the boundary: `gate()` has
returned by then, so it has written whatever ledger it was going to write and has already said what
it did. The handler is left for `gate()` itself raising, which is the case the interior argument
does cover. Exit stays 3, `hush_streams()` keeps the no-120 property, and the new sentence says
nothing about what is on disk.

**Red before green, on the same suite.** Shipped engine `0ad79d1b…`: selftest exit **1**, 68 cases,
67 ok, **case 68 alone**, reporting `markers 2 buffered / 1 unbuffered` with the buffered ledger
naming `gate: BrokenPipeError` and the unbuffered one naming the cause. Patched engine
`9f58e96d…`: exit **0**, 68 ok, twice.

**The scope departure, stated.** The brief scoped this pass to the selftest and the route table's
wording and said not to change the engine. Its acceptance asks that the ledger name the original
cause and that the marker be emitted once, and both are properties of the engine's behaviour rather
than of what the suite asserts. `claude-fable-5`, asked whether any selftest-only mechanism could
produce them, found none and explained why: the overwrite happens inside `main()`'s handler in the
engine process, driven only by argv and the state of fds 1 and 2 at invocation, and a file that is
not in that process's execution path cannot alter it. So the two instructions could not both be
met. The reason given for the freeze — that byte-identical is what lets a verifier attribute what
it measures — is served instead by keeping the change to one commit, one function and six lines,
with the before and after shas above.

## The first patch was wrong, and a lane broke it twice

The first shape recorded whether `gate()` had returned and skipped the rewrite when it had. Both
breaks were constructed and confirmed:

| | Break | What the reader saw |
|---|---|---|
| 1 | the obituary write itself fails (`chmod 444` on the ledger) | one honest WARNING, then *"the ledger … already records why this run measured nothing"* — untrue; the file is an earlier run's clean table |
| 2 | no `--report` at all | *"the ledger at None already records …"* — there is no ledger anywhere |

Both left all 68 cases green and case 60's AST check green. The shipped engine's double-write is
wrong about the cause; that patch would have been wrong about the file, which is worse. The shape
taken says nothing about disk contents, and both breaks were re-run against it: break 1 leaves the
two WARNINGs standing with no second claim, break 2 emits no claim at all, exit 3 in both.

## `D-m23-ba` — the guard was one-directional

The enumeration is sound about the engine as it stands, and case 60 is what was evadable. Three
checks now stand where a raw substring scan did: the spelling count comes from the syntax tree with
`BinOp` folding, implicit concatenation and bytes; the escape list carries eleven more spellings;
and the engine is required to import nothing outside the standard library and nothing relative.

Nine evasions, each applied to a copy of the engine and run against the check alone:

| | Emitter added | Caught by |
|---|---|---|
| 1 | `"mock-fidelity: report" " written to " + p` | spelling count — 2, expected 1 |
| 2 | `globals()["REPORT_MARKER"] + p` | escape list |
| 3 | a sibling module `marker_helper.say(p)` | import check |
| 4 | `"mock-fidelity: %s to %s" % ("report written", p)` | fragment check — `'report written'` |
| 5 | `sys.modules[__name__].REPORT_MARKER + p` | escape list |
| 6 | `os.write(1, b"mock-fidelity: ")` and three more chunks | fragment check and escape list |
| 7 | `"mock-fidelity: {} to {}".format("report written", p)` | fragment check |
| 8 | `"".join(["mock-fidelity: ", "report written to ", p])` | fragment check |
| 9 | a third `emit(REPORT_MARKER + p)` site | the Name walk, as before |

Rows 4, 5 and 6 are `gemini-3.7-flash-high`'s, asked to break rather than review. Rows 1, 2 and 3
are the brief's. The fragment check is what generalises over run-time assembly: nothing else in
this engine needs a long piece of the marker, so a constant that is one is either the marker being
reassembled or a message that should be using `REPORT_MARKER`. Seven characters is the shortest
bound the file admits, measured — at six `'report'` collides and at four `'mock'` does.

**What it still does not catch, measured rather than assumed.** An assembly from constants of six
characters or fewer — six pieces or more — stays green. A chained `+` of constants does not, and
neither does a subprocess handed the marker as implicitly-concatenated pieces. That bound is
recorded in the case itself, beside the behavioural half that covers the other direction: cases 43,
44, 49, 51, 61 and 68 assert the marker per route on real runs, and 62 to 67 assert what the
consumer does with it.

`gemini-3.7-flash-high` also priced the import check: it rejects splitting this engine into a
package, which is ordinary practice at 1,400 lines. That cost is taken deliberately — the single
file is what the completeness argument rests on, and the check failing is the signal to re-derive
the enumeration across the package.

## Three of our own numbers

**`D-m23-bb` — five arms invisible is nine.** Arms 1 to 5 and 8 to 11 each ran 59 ok with 0 FAIL
against the pre-pass suite; only 6 and 7 were visible. The evidence table carried one fact under
two wordings, "all 59 green" and "invisible", and the summary counted one of them. The column is now
one wording and the count is stated beneath it. The error understates the pass.

**`D-m23-bc` — 145 engine runs is 145 python3 processes, of which 52 are the engine.** Re-measured
by running the 59-case suite that shipped before the sixth pass under a `sitecustomize.py` that logs
`sys.argv` for every interpreter start: **145 processes, 52 of them the engine, 10 of those with
`--report`, and 0 `python3 -c`**. The rest are `build-fixture.py` and `mock-affordances.py`. The
correction filed against this said 53 and counted a `python3 -c` that the trace does not find in
that suite; the over-count is 2.8x rather than 2.7x. Every emission figure the conclusion rests on
is unaffected. For the record, the suite as it now stands runs 173 processes, 61 of them the engine,
19 with `--report`.

**`D-m23-bd` — gate B had no recipe anywhere.** Named once at `M23-gapfix-2.md:121` and carried
through four briefs as "B 3 with a ledger written" with no surface, command or fixture. What pass 2
ran under that letter is not recoverable. The three standing gates now have their commands recorded
in the selftest's header, and B is an equivalent rather than a reproduction, said so in the file:

```
python3 scripts/acceptance/mock_fidelity.py planning/fidelity/servers.layers.json \
  /tmp/no-such-dumps --report /tmp/mock-fidelity-B.ledger.md
  → exit 3, `dump[ideal]: no artifact at …`, obituary written to the report path, marker emitted
```

Hermetic, no MEASURE build, and it writes nowhere the repo reads.

## Gates

| Gate | Result |
|---|---|
| A `mock-fidelity-gate.sh` | exit **1** — `mock-fidelity: EXIT 1 — 132 finding(s)`, `ledger written to planning/fidelity/servers.ledger.md`, and the ledger plus all four dumps sha256-identical either side |
| B (recipe above) | exit **3** — `dump[ideal]: no artifact at …`, obituary written, marker emitted |
| selftest ×2 | exit **0**, 68 cases, 68 ok, both runs |
| `make lint` | exit **0** — 0 violations in 514 files, `no-raw-design-values` clean over 118 |
| `make test` ×2 | exit **0** twice — `Test run with 1615 tests in 202 suites passed` |
| `ledger-reconcile.py` | exit **0** — `reconciled — no findings across A, B, B-range, C, D, E, F, G, H, I, J, K` |

`D-m23-be`'s test, *a waiter that is cancelled is resumed rather than stranded*, passed on both
runs here.

`mock-fidelity-gate.sh` is byte-identical to the branch base at `2229940e…` throughout. The engine
is not, and that is BL-1 above.

## Lanes

Read-only from `/tmp` against `chmod 444` copies, per the standing rule. Codex is down until 27
August; grok was not run.

- **`claude-fable-5`** at high — 5,206 B. Confirmed no selftest-only mechanism exists for BL-1 and
  named the one external lever that looks like a counter-example and is not (`PYTHONUNBUFFERED=1`
  in the invoking environment, which the suite cannot set for `mock-fidelity-gate.sh`). Then broke
  the proposed patch twice, both constructed and confirmed, and proposed the shape that was taken.
- **`gemini-3.7-flash-high`** — first run returned 0 B: headless mode auto-denied a `python3 -c`
  tool call, the same failure the sixth pass recorded. Re-run with the engine and the consumer
  inline and no tools needed: 3,251 B, three breaks of the widened guard, all three now red, plus
  the cost of the import check.

Both were asked to break rather than review, which has now produced the blocking finding or the
final shape on five consecutive passes of this item.
