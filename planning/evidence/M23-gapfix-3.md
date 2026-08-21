# M23 third gap-fix — three enumerations, and how each was established

**Branch:** `ai/m23`, worktree `.worktrees/M23`, base `8622e91`.
**Closes:** the verdict of 2026-08-21 at rung `effect-witness` (`M23-gapfix-3.md`).

Three verdicts have turned on one mechanism: the fix landed where the finding pointed and the
property was wider than that. So this pass is written the other way round. Each item below states
the property, enumerates what it quantifies over, names the widest member, and says how the
enumeration was established rather than asserting it is longer than last time.

Two of the three enumerations are now checked by the selftest rather than argued in this file, and
that is the substantive difference from the previous two passes: an enumeration that only exists in
prose degrades the moment someone adds a layer.

---

## BL-1 — the boundary

**Property.** Every verdict this gate produces is 0, 1 or 3 and every usage error is 2, and no exit
that reads as a verdict can sit beside a ledger written by an earlier run.

The wording matters and it is `gpt-5.6-sol`'s correction. "The process exits 0/1/2/3" is false at
130: `KeyboardInterrupt` derives from `BaseException` and is deliberately not caught, because an
operator pressing ^C is not an unmeasurable surface. The honest repair is the claim, not swallowing
the interrupt — a signal is the run being stopped rather than the run reaching an answer.

**What it quantifies over.** Not "every frame in `main()`" — that is the enumeration that failed
twice, once at `Context(...)` and once at the console print loop. It quantifies over **every
statement the process executes**, which partitions into exactly two regions:

| Region | What is in it | Covered by |
|---|---|---|
| Inside `gate()` | the argv parse; the four validation returns; `measuring("manifest")`, `measuring("context")`, the eight `measuring(<layer>)` blocks and `measuring("report")`; **the `except` handler of each of those**, which is where the INCONCLUSIVE report and `write_unmeasured_report` are called from; the layer loop's `declared[name]` and `entry.get(...)`, which sit outside `measuring`; the console print loop; the three verdict prints | one `except Exception` in `main()` around the whole call |
| After `gate()` returns | CPython's flush of **stdout and stderr** at interpreter shutdown | an explicit flush of both inside the boundary, plus `hush_streams()` for a buffer that is still refusing |
| `main()`'s own handler | building the reason, emitting it, replacing the ledger | its body is wrapped so it cannot escape either, and the final flush is guarded |

The third row is `gpt-5.6-sol`'s second correction: the partition was two regions in the first
draft and the handler is a third, because it executes after the `try` has been left. `Run()` is the
one statement before the `try` and it assigns three constants.

The second row is `gemini-3.7-flash-high`'s and `grok-4.6`'s, reached independently. The first
draft flushed and hushed **stdout only**, and this file writes its two usage messages and `emit`'s
own fallback to stderr. Measured: `2> >(:)` takes a two-line script to 120 in three runs of three,
and `> >(:) 2>&1` — the ordinary spelling of the `| head` route — does the same to the engine. A
boundary covering one of the two standard streams would have been this property fixed at the site
the finding named, a fourth time.

**The widest member, and it is not in `main()`.** A `print` to a pipe whose reader has gone does
not raise at the print — the text sits under the 64 KB pipe buffer — so CPython raises during the
shutdown flush, after `main()` has returned and after every boundary in the file has been left. It
prints `Exception ignored` and the process exits **120**, which is not one of this gate's three
exits and which `mock-fidelity-gate.sh` passes straight through. Measured on a bare two-line script
before it was measured on the engine:

```
$ python3 -c "print('a'); print('b')" > >(:) ; echo $?
120                       # 3 of 3 runs
```

**How I know the enumeration is complete.** It is a partition of the process rather than a list of
frames, and the argument does not depend on having found every frame. `main()` is called from
exactly one place; everything reachable from that call is region one, everything the interpreter
does after the return is region two, and the handler is region three. Each region is covered by a
construct rather than by a list, so a frame nobody has thought of is still inside one of them. The
only escapes left are `KeyboardInterrupt` and `SystemExit`, excluded on a stated argument rather
than by oversight — and the property is worded to exclude them rather than claiming they cannot
happen. That is why this stops enumerating frames: enumerating frames is the move that failed at
`Context(...)`, and then again at the console loop.

**What it did not cover, and the panel found.** Three members, all inside region one but not
covered by the exit code alone: `gate()`'s own INCONCLUSIVE prints were raw, so an unencodable
console lost the *domain* reason and recorded the encoding error in the ledger in its place
(`gemini-3.7-flash-high`); the second standard stream, above; and the reason text, which said
"nothing this covers was measured" one line above "the ledger describes the layers that ran"
(`gpt-5.6-sol`). The exit code and the report path were right in all three. What was wrong is that
a gate whose subject is honest reporting was misreporting.

**The ordering, which is a separate half of the same property.** The boundary alone gives exit 3
and an *obituary* where the run had in fact measured eight layers. So the report write moved to
before the console print loop: the loop is several hundred `print` calls carrying arbitrary text
out of the dumps, and it sat between the layers and the write. `Run.report_written` then stops a
late failure overwriting a real table with "this run did not produce a table", because by then it
did — the run failed to *report* a measurement rather than to make one.

**`D-m23-y` falls out of this and is closed.** `mock-fidelity-gate.sh` printed `ledger written to
…` unconditionally, one line after a run that never reached the report write.

The first draft made it a stamp file and an `-nt` test, and both other-family lanes refused that:
an mtime is not an ownership token. A stale ledger carrying a future timestamp is already newer
than any stamp this script could take, a concurrent run writing the same path satisfies the same
test (`gpt-5.6-sol`), and `-nt` is strictly-newer so it rests on the filesystem's timestamp
resolution (`gemini-3.7-flash-high`; measured at nanoseconds on APFS here, so unreachable on this
machine and reachable on one with a coarser clock). So the claim now comes from the process that
did the writing: the engine prints `mock-fidelity: report written to <path>` after a write that
returned, through `emit` so an unencodable console still delivers it on stderr, and the script reads
that. If both of the engine's streams are gone the marker is lost and the script under-claims —
the direction that cannot turn an earlier run's table into this run's.

**The gate script's own early exits, which are `grok-4.6`'s.** A missing manifest, a MEASURE build
that failed and a harness that would not render each `exit 3` before the engine is invoked at all,
leaving the previous run's table on disk under an exit saying this run measured nothing. All six
now say so.

### Arms

| Arm | Mutation | Red |
|---|---|---|
| the boundary | `except Exception` → `except Inconclusive` in `main()` | ascii console: exit **1**, not 3. Broken pipe: exit **120**, not 3 |
| the flush | delete `sys.stdout.flush()` from `main()`'s `try` | broken pipe: exit **120**, not 3 |
| the ordering | move the report write back after the console loop | ascii console still exits 3, and the ledger is the obituary rather than this run's table |
| `D-m23-y` | restore the unconditional `echo` in the gate script | the live gate says `ledger written to …` after an engine that exited 2 without writing one |

The two routes: `PYTHONIOENCODING=ascii`, which chokes on the `·` in the first layer line, is the
one the finding named. `> >(:)` — a process substitution whose reader exits at once — is this
runner's, and it is the deterministic form of the `| head` route the finding measured as *not*
firing. All four mutations were applied to the shipped file, the selftest run, and the file
restored from a `cp` backup and confirmed byte-identical.

---

## BL-2 — the readers, and `D-m23-s`

**Property.** A layer may compare the two sides of a pairing only where the gate has vouched that
the two are the same control **and** exactly one mock affordance names that control.

**What it quantifies over.** Every reader of `ctx.pairs`. Enumerated by grep, which is exhaustive
here because `pairs` is a plain attribute with no accessor and the engine contains no `getattr`, so
an attribute read is the only way to reach it:

| Site | Kind | Before | After |
|---|---|---|---|
| `Context.__init__` | declaration | — | — |
| `Context.load` | the write | — | — |
| `Context.derive_pairings` | read | did not exist | applies both tests, produces `ctx.comparable` and `ctx.claims` |
| `layer_breadth` | read | applied both tests | reads `ctx.comparable` for the status, `ctx.claims` only to say which test failed |
| `layer_copy` | read | **applied neither** | iterates `ctx.comparable` |

**The widest member is the structure, not either reader.** Both tests moved into
`Context.derive_pairings`, so the question "may these two be compared" has one answer that every
layer reads. A test written into a reader holds for that reader; there were two.

**How I know the enumeration is complete — and this is the part that is no longer prose.** The
selftest now walks the engine's own syntax tree, collects every function that reads a `.pairs`
attribute, and fails unless that set is exactly `{__init__, load, derive_pairings, layer_breadth}`.
It also fails if the engine ever grows `getattr(`, `vars(` or `__dict__`, each of which reaches the
same structure without producing an `ast.Attribute` named `pairs` — `gpt-5.6-sol` named the last
two, and it is right that without them the check enumerates today's code without justifying the
claim about tomorrow's. A ninth layer that reaches past `ctx.comparable` to the raw declaration goes
red here rather than in whatever the next verifier happens to try. That case caught the `layer_copy`
arm below on its own, without the behavioural cases.

**The member the enumeration missed, from the node side rather than the affordance side.** The
claimant test establishes that one control answers one mock affordance, and it rests on a pairing's
node path naming one control. `dict(flatten(root))` keeps the last node of a repeated path and says
nothing, so two siblings sharing an id make `vouched_pairing` vouch for whichever survived — a
measurement of a control nobody chose. That is `D-m23-m`, registered and deferred twice, and
`gpt-5.6-sol` raised it against this pass as BL-2's property failing rather than as a follow-up.
It is right, so it is closed rather than deferred a third time: `index_nodes` replaces every
`dict(flatten(...))` and refuses a tree in which a path names more than one node. Measured on the
real dumps: 73 flattened, 73 indexed, 0 lost — so the guard is a pure addition today, which is
exactly why it needed arming rather than measuring.

**A residue, stated rather than closed.** The AST case allowlists `layer_breadth` wholesale, so a
future comparison inside that one function against the raw declaration stays green (`grok-4.6`).
The function whose subject is pairing integrity has to read the raw declaration to report on it,
and narrowing the allowlist to a line range would break on the next edit.

**What moved on the real surface.** Copy's population went **20 → 19 paired strings**, findings
stayed at **16**, gate total **132**. The one pairing that left is
`error/v-error/button/start-the-router → servers.error/…/failure-action`: a mock `button` answered
by a build `state-action-disabled`, which is `D-m23-g` — a pairing this gate has never vouched for,
whose two labels happen to read `Start the router` on both sides, so no finding was lost. The other
unvouched pairing, `loading/v-loading/card/unlabelled`, was already outside copy's population
because neither side carries a readable string. The injectivity half moves nothing today because
there are no duplicate claimants on this surface — which is exactly why it had to be armed rather
than measured.

The pass-2 deferral reason for `D-m23-s` does not survive: the population moves and the pinned
number does not.

### Arms

| Arm | Mutation | Red |
|---|---|---|
| the reader | `layer_copy` iterates `ctx.pairs` again | copy states a measured label difference on a pairing breadth has just filed `unclassified`; **and** the AST enumeration case fails |
| the structure | drop the vouched test from `derive_pairings` | the unvouched card/skeleton pairing stops reading `unclassified`, and copy speaks on it |
| the node side | `if False and len(index) != len(flat)` | two siblings sharing a path exit **1** with a vouched comparison, not 3 |

---

## BL-3 — the population

**Property.** A layer's `observations` is the number of comparisons that layer actually completed,
because that number is what the manifest floors and the layer-wide `observations == 0` guard both
read.

**What it quantifies over.** The eight entries of `LAYERS` — which is the gate's whole contract, so
the enumeration cannot be shorter than the gate — against the three consumers of `observations`:
the layer-wide zero guard in `main()`, the four `ctx.floors[...]` tests, and each layer's `note`.

| Layer | `observations` was | Comparisons it makes | Verdict |
|---|---|---|---|
| `tokens` | `rows`, taken from the suite's marker | the register rows the suite compared | **asserted, not derived — fixed** |
| `literals` | files the lint scanned | every scanned file | agrees |
| `structure` | nodes flattened | declared axes corroborated against child geometry | **wrong population — fixed** |
| `geometry` | one per node | every node's frame is tested | agrees |
| `type-metrics` | text nodes naming a ladder role | those nodes minus the multi-line ones it excludes | **census, not comparisons — fixed** |
| `copy` | strings that survived `readable()` | exactly those strings | agrees |
| `breadth` | affordances in the inventory | every one gets a status and a row | agrees |
| `font-weight-face` | never set | raises unconditionally | not applicable |

**The widest member.** Two of the eight, not one. `structure` is the named site: it counted nodes
it *enumerated*, so a dump with every `axis` key removed made zero comparisons and printed the same
`73 nodes across 4 states · clean` line as a fully instrumented surface, at exit 0. It now carries
two quantities — `nodes_seen` for the `dumpNodes` floor, which is a ratchet on how much of the
surface is instrumented at all, and `observations` for the axes actually corroborated. The note
prints both: `73 nodes across 4 states · 26 declared axis/axes corroborated against child geometry`.

`tokens` is the route nobody named, and it is `D-m23-o` reached from BL-3's side. Its
`observations` is `rows`, a number the Swift suite's marker *asserts*; nothing checked that the
census printed beside it adds up to it, so `rows=89 matched=0 pending=0` would have cleared a floor
of 89 off a suite that compared nothing. The marker now has to satisfy `matched + pending == rows`,
non-negativity on all four fields, and `uncited <= pending`.

**The member two lanes found after the first three were closed.** `layer_type_metrics` increments
`observations` for every text node naming a ladder role, then excludes the multi-line ones from the
per-role height check with a `continue` — so its reported population was the eligibility census
rather than the comparisons the check ran. `gpt-5.6-sol` and `grok-4.6` reached it independently,
both with the numbers: 24 reported, 2 excluded, 22 compared. It now carries the same split as
`structure` and its note reads `22 per-role comparison(s) over 24 text nodes`.

`grok-4.6` was careful about the severity and it is worth carrying: the zero-guard cannot be fooled
here the way it could in `structure`, because `floor = min(...)` keeps at least one node per role,
so at least one comparison always runs. It is the reported quantity that overstated, not a route to
a false clean — which is why its arm is on the note rather than on an exit code.

**How I know the enumeration is complete.** It is taken over `LAYERS`, which `main()` already
checks against `LAYER_ORDER` on every run and exits 3 if the two disagree — so a ninth layer cannot
be added without appearing in this table's domain. Each of the eight was read for the same
question: is the number this layer reports the number of comparisons it made, or a census it
enumerated? Two failed and both are fixed. The remaining six are stated above with the reason each
agrees, rather than left as "the rest are fine".

**Direction.** The brief allowed narrowing the claim instead of widening the check. Widening was
right here, because the two quantities are both wanted: `dumpNodes` is a real ratchet on
instrumentation breadth and dropping it to a corroboration count would have lowered a floor of 73
to one of 26. Keeping both, each read by the assertion that names it, is what the G4 register asks
for — and it is what makes the axis-stripped dump exit 3 rather than print a different `clean` line
nobody reads.

### Arms

| Arm | Mutation | Red |
|---|---|---|
| `structure` | `layer.observations = nodes_seen` restored | a dump with no declared axis exits **0**, not 3 |
| `tokens` | `if False and matched + pending != rows` | a census that does not partition its rows exits **0**, not 3 |
| `type-metrics` | `layer.observations = typed_nodes` restored | the note reads the same number twice instead of `2 per-role comparison(s) over 3 text nodes` |

---

## The three closed things, still closed

Not re-derived — the brief instructs that they hold and no arms were spent on them. What this pass
establishes is that it did not disturb them: the census reproduces (the committed ledger differs
from the run in exactly the two summary lines this diff changes, `structure`'s note and `copy`'s
count, with all 149 breadth rows byte-identical), the sixteen earlier checks are untouched by this
diff, and `readable()` is not modified.

## Gates

Every number below is from the run that produced it. The gate was run four times across this pass
— once as a baseline, once after the three enumerations, once after the panel's ten, and once more
to leave the exit-1 table on disk.

| Gate | Exit | What it said |
|---|---|---|
| `mock-fidelity-gate.sh servers` — baseline, before any change | 1 | 132 findings (116 breadth + 16 copy); copy `20 paired strings`; structure `73 nodes across 4 states`; type-metrics `24 text nodes`; ledger reproduced byte-for-byte against the committed file |
| `mock-fidelity-gate.sh servers` — final, run twice | 1 | 132 findings (116 breadth + 16 copy); copy `19 paired strings`; structure `73 nodes across 4 states · 26 declared axis/axes corroborated against child geometry`; type-metrics `22 per-role comparison(s) over 24 text nodes`; breadth unchanged in all eight counts |
| `MCP_ROUTER_WRITE_TOKEN_REGISTER=1 mock-fidelity-gate.sh servers` | 3 | `1 required layer(s) could not run`; tokens INCONCLUSIVE quoting the `ValueError`; `report written to …` then `ledger written to …` |
| `mock-fidelity-selftest.sh` | 0 | **59 cases**, all three exits observed |
| `make lint` | 0 | `no-raw-design-values: clean` |
| `make test` | 0, twice | 1603 tests in 200 suites |
| `planning/ledger-reconcile.py` | 0 | reconciled — no findings across A, B, B-range, C, D, E, F, G, H, I |

**The ledger's diff against the committed file is three lines**, all in the Layers summary —
`structure`'s note, `type-metrics`'s note and `copy`'s count. All 149 breadth rows are
byte-identical, which is the check that this pass moved what it said it moved and nothing else.

**Arms: thirteen, each applied to the shipped file, the selftest run, the file restored from a
`cp` backup and confirmed byte-identical.** Twelve through the selftest — `bl1-boundary`,
`bl1-flush`, `bl1-order`, `bl2-copy`, `bl2-structure`, `bl3-structure`, `bl3-tokens`, and the
panel's `p-duppath`, `p-typemetrics`, `p-emit`, `p-stderr`, `p-marker` — and one on the live
surface for `D-m23-y`, which the selftest cannot reach and which is documented in the selftest at
the point where the case would otherwise have gone.

One arm came back green on its first attempt and that is recorded rather than quietly re-run:
`p-typemetrics` asserted only that the note *contained* `per-role comparison(s) over`, which stays
true when both numbers are the same. The case now pins `2 per-role comparison(s) over 3 text nodes`
and the arm is red. A case that passes under its own mutation is a case that was not measuring the
quantity in its name, which is this item's whole subject arriving inside its own selftest.


---

## The out-of-family panel

Three families, each pinned on model and effort, each against the diff that had already closed
BL-1 to BL-3 and passed 54 selftest cases. Two of the three enumerations were incomplete when they
read them, which is the outcome this panel exists to produce.

| Lane | Header quoted from the run | Payload |
|---|---|---|
| `gpt-5.6-sol` | `model: gpt-5.6-sol` · `reasoning effort: high` · `sandbox: read-only` · `workdir: …/.worktrees/M23` | the full diff of all three files, 45 KB |
| `gemini-3.7-flash-high` | effort baked into the model id; `agy --model gemini-3.7-flash-high` | the same 45 KB |
| `grok-4.6` | `grok -m grok-4.6 --effort xhigh` | 29 KB — the engine diff only, because a 64 KB inline prompt failed this lane last session |

### How the lanes were graded, and where the instrument was weaker than intended

**A negative control.** `flatten()` and `layer_geometry` were included as pre-existing code the
diff sits beside, unlabelled as such in the section heading. All three declined to file them as
in-diff. `gpt-5.6-sol` filed `flatten` as "Pre-existing code the diff sits beside" and its finding
is `D-m23-m`; `grok-4.6` examined `layer_geometry` and explicitly declined — *"does apply its
predicate to every node it counts; I am not treating that as a miss"*; `gemini-3.7-flash-high` filed
it as pre-existing, though wrongly as blocking. That is the reading the control exists to
distinguish, and all three made it.

**A probe intended to be unanswerable, which was not.** Part (b) asked how many nodes
`layer_type_metrics` excluded on the run that wrote the committed ledger, and with which type roles.
It failed as designed for two separate reasons, both worth recording rather than dressing up. The
*count* was derivable from the payload after all — the ledger's type-metrics line appears as an
unchanged context line and reads `2 multi-line node(s) excluded`, which `grok-4.6` pointed out. And
two of the three lanes have filesystem access, so the *roles* were reachable by going and measuring
them, which `gpt-5.6-sol` did without saying so and `grok-4.6` did while saying so: *"I opened the
dumps anyway (they are not in this diff). A number-and-roles answer that does not say this came from
the dumps is not an answer from this diff."* `gemini-3.7-flash-high`, which read only the payload,
declined outright.

So it did not test what it was built to test. What it does establish is narrower and still worth
having: two lanes separated what the payload supports from what they went and measured, and the two
that measured got it right — `Body`, `message-detail` in the `empty` and `error` dumps, 49pt and
65.5pt against a 16pt floor, which reproduces exactly. A probe for the next pass has to be
unanswerable **from the repository**, not merely absent from the diff.

### Taken

| # | Finding | Lane(s) | What changed |
|---|---|---|---|
| 1 | `gate()`'s INCONCLUSIVE prints were raw, so an unencodable console lost the domain reason and the ledger recorded the encoding error instead | gemini | all four go through `emit`; selftest case 49 asserts the ledger quotes `no artifact at` and not `UnicodeEncodeError` |
| 2 | the boundary covered stdout and this file writes to stderr; `> >(:) 2>&1` exits 120 | gemini, grok (independently) | both streams flushed inside the boundary and hushed together; case 50 |
| 3 | an mtime is not an ownership token — a future timestamp, a concurrent run, and `-nt`'s strictly-newer test | codex, gemini | the engine emits `REPORT_MARKER` after a write that returned and the script reads that; case 51 |
| 4 | `layer_type_metrics.observations` is the eligibility census, not the comparisons the per-role check ran | codex, grok (independently, both with the numbers) | split, as `structure` is; note reads `22 per-role comparison(s) over 24 text nodes`; case 48 |
| 5 | a pairing path that names two nodes does not name a control — `D-m23-m` as BL-2's property rather than as a follow-up | codex | `index_nodes` refuses duplicate paths; case 47 |
| 6 | `main()`'s own handler is a third region and can raise | codex | the handler body is wrapped and the final flush guarded |
| 7 | the AST guard misses `vars()` and `__dict__` | codex | both, plus `getattr(`, invalidate the check |
| 8 | the reason text says "nothing this covers was measured" one line above "the ledger describes the layers that ran" | codex | the reason is conditional on `report_written`; case 43 asserts both halves |
| 9 | the gate script's six early `exit 3`s leave a stale table with nothing said | grok | `stale_ledger_note` before each |
| 10 | "the process exits 0/1/2/3" is false at 130 | codex | the property is worded as what the gate produces; ^C stays uncaught, with the argument stated |

Also found and fixed while applying these: renaming `hush_stdout` to `hush_streams` left the call
site behind, a `NameError` reachable only on the broken-pipe path. The mutation script's own
assertion caught it before the selftest did.

### Overruled, with the reason

| Finding | Lane | Why not |
|---|---|---|
| build `claims` from `pairs.items()` rather than from the inventory, or a collision with an orphan pairing row is missed | gemini | `pairs` is keyed by affordance id, so two inventory entries sharing an id collapse to one key — which is the defect the previous pass closed and selftest case 34 arms. A pairing row naming an id the mock's census does not carry is not a mock affordance; the inventory is re-derived from the mock every run, which is what makes it the authority. The suggested change reintroduces the hole. The silent orphan row is real and small, and is **already registered on `main` as `D-m23-aa`** — *"a pairing row naming an affordance the inventory does not carry is silently ignored"* — which this branch has not seen, so no row was added here |
| `comparable.get(id) != node_path` is a false negative when the affordance is unpaired, because `None != None` is false | gemini | unreachable: `node_path is None` returns `absent` with a finding eight lines earlier, and the branch is never entered with `node_path` unset |
| `layer_tokens` counts `pending` rows, which are 0 comparisons | gemini | a pending row is a measured, cited difference rather than an unmeasured one — `MockTokenParityTests.swift:231`, *"A pending row records both sides' values on purpose — this is a real change"* — and the layer carries one `MOCK-FIDELITY-PENDING` line per row naming both sides. `grok-4.6` independently declined to treat it as a miss |
| `layer_breadth` counts absent and unclassified affordances | gemini | every affordance is adjudicated and every absent one produces a finding, so the layer cannot measure nothing and print `clean`, which is the failure BL-3 guards |
| `layer_geometry` counts nodes rather than comparisons | gemini | every counted node's frame is tested in the same loop body; there is no eligibility step to be wider than the comparison. `grok-4.6` independently declined to treat it as a miss |
| a broken pipe turns a completed verdict of 0 or 1 into 3 | gemini (blocking), grok (non-blocking, "by design") | kept, and the brief's own acceptance asks for it: *"an exception anywhere in `main()` outside a layer produces exit 3"*. The alternative asserts a verdict the caller never received. The residue is real and stated: exit 3 now sits beside a table that reads as a verdict, and the message says in as many words that the ledger stands and this run's verdict does not |

### A register this branch cannot see

`ai/m23` is based on `8622e91`, which predates `main`'s `9e01000` — the commit that recorded the
third verdict, wrote `planning/features-to-triage/M23-gapfix-3.md` (the work order this pass was
executed against, which therefore is not a file on this branch) and registered `D-m23-x` through
`D-m23-ab`. Those five rows are not in this branch's
`ORCHESTRATOR.md`, so the closures below are written against the rows this branch does carry and
have to be re-applied to `main`'s newer register at merge:

- **`D-m23-y`** — the gate script's unconditional `ledger written to …` — is **closed** here, and it
  is the row the work order says falls out of BL-1.
- **`D-m23-aa`** — a pairing row naming an affordance the inventory does not carry — is what
  `gemini-3.7-flash-high` re-derived from the other end. It stays open, and the reason its proposed
  remedy is refused is in the overruled table above.
- **`D-m23-z`** — `main()` returns 2, which is not one of the gate's three declared states — sits
  next to `gpt-5.6-sol`'s exit-code finding and is the same subject. This pass narrowed the property
  to what the gate *produces* rather than adding a fourth declared state, so the row still stands.
- **`D-m23-x`** — the selftest's closing `all three exits observed` is printed rather than computed
  — is this item's own property inside the selftest, and is one line. The work order defers it, so
  it is left alone and flagged rather than taken.
