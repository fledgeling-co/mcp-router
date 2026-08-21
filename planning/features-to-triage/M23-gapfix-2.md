# M23 gap-fix, second pass — assert the property, not the route

**Parent:** M23, the mock-to-SwiftUI conversion contract.
**Branch:** `ai/m23`, worktree `.worktrees/M23`, at `f74ca96`. Resume in place.
**Verdict this closes:** verified 2026-08-21 at `metamorphic`, **Needs More Work** — the second
such verdict on this item.

## Read this before the findings, because it is why there is a second pass

The verifier's own summary: *"this is not 'the fixes did not land', it is 'the properties they
assert do not yet hold, by routes of the same class'."*

All three of the first gap-fix's acceptance criteria reproduce exactly. The ledger counts moved as
claimed (`present 10 → 3`, `unclassified 1 → 6`, `divergent 16 → 18`, `covered-by-pair 17 → 16`),
the selftest runs 26 cases with all three exits observed, and every arm the runner planted fires.
The fixes are real.

And each closed **the route the finding named** rather than the property the finding was about.
`present` stopped agreeing on two empty strings — and still agrees on two zero-width spaces. The
container exemption became a quota on the role the census enumerates — and a surplus child wearing
any *other* role still rides through to exit 0. The tokens layer converts three subprocess failures
to `Inconclusive` — and a `KeyError` one frame up still exits 1 with a stale ledger on disk.

**So the standard for this pass is different: each fix must be argued as a property, and the
acceptance must include a route nobody named.** Three independent instruments — the verifier's own
mutations, `grok-4.6` at xhigh and `gpt-5.6-sol` at high — converged on the set below without
seeing each other's output, which is what a class rather than a list looks like from outside.

This is `G4`'s shape (`G4-assertions-that-do-not-read-their-own-quantity.md`), arriving inside the
item that exists to prove conversions. Worth reading that file before starting.

## B1 — a required layer that measured nothing reads `clean`, and the gate exits 0

`layer_literals` reads the lint's scan count **precisely because**, in its own comment, *"a lint
that scanned nothing and a lint that found nothing print the same exit code"* — and then never
compares it to anything. `floors` covers `tokenRows`, `dumpNodes` and `affordances` only.

Measured: a lint printing `scanning 0 files` and exiting 0 gives
`literals ran · scanning 0 files · clean` and `EXIT 0 — every required layer ran and found nothing`.

This is worse than the G3 defect it sits beside, which at least exited 1. Independently ranked HIGH
by `gpt-5.6-sol`. It is not in the deferred register.

**Fix:** a floor for the literals scan alongside the other three.

## B2 — the exception boundary is one class wide, and the stale-ledger failure returns through it

`Context(manifest, dump_dir)` is constructed **outside** the `try/except Inconclusive` in `main()`,
and the layer loop catches only `Inconclusive`. Measured twice: a surface manifest missing `floors`,
and a dump node missing `role`. Each gives a traceback, **exit 1**, no report written, the stale
committed ledger intact — and `mock-fidelity-gate.sh` printing `ledger written to …` on the line
before.

That is the first work order's own sentence — *"the stale committed `servers.ledger.md` stays on
disk beside an exit code that reads as a measured verdict"* — reproduced through a different door.

Both out-of-family lanes enumerated six further doors each: a non-JSON inventory on a zero exit, a
dump that is `[]`, a non-UTF-8 pairing or manifest, `layer_geometry`'s `dump["size"]`, an unguarded
`write_report`, a trailing bare `--report`. **The manifest route matters most**, because a
hand-written `<surface>.layers.json` is the first artifact M15–M22 each author, so this is the
error a future conversion is most likely to make first.

**Fix, and it is the one that closes a class rather than a list:** catch `Exception` around
`Context(...)`, `ctx.load()` and each layer call, convert to `Inconclusive` quoting the traceback.

## B3 — `present` is still earned vacuously

The new test is `if mock_text and app_text` — truthiness, not readable content.
`" ".join(x.split())` drops `\xa0` but keeps U+200B. Measured: a mock label and a build text each
consisting of one zero-width space, on a vouched `heading` pair, read `present` at exit **0**.
Reproduced independently by `gpt-5.6-sol` and reached independently by `grok-4.6`.

Contrived to arrange, and it is the literal form of "agreement between two absences" the fix was
written to end.

**Fix:** require readable content rather than truthiness.

## B4 — pairing is not one-to-one, so one control can earn `present` N times

`self.pairs[state]` is a dict keyed by affordance, so any number of affordances may name the same
node and nothing checks injectivity. Measured: two mock headings pointed at one build control gives
`present 4` at exit **0**.

It does not fire on today's ledger — the verifier searched all four states and found no absent
affordance whose label matches a vouched node's text. But 80 of 173 rows are `absent` findings, and
matches appear precisely as M16 converts the board: **the defect activates exactly when someone is
working toward exit 0.** Same class as the original G1 — a `present` that was not earned by
measuring that control.

**Fix:** an injectivity check on `self.pairs[state]`.

## A correction to the first work order, which was mine

It described the current behaviour as *"an unvouched pair reading `unclassified`"*. The code reads
`divergent` (`if not vouched: status = "divergent"`). That matters beyond the wording, and it is
registered as `D-m23-l`: the layer's own doctrine says a comparison the instrument could not make
is `unclassified`, and *"this gate has never vouched for this pairing"* is that, not a measured
difference. Two of today's 18 divergent rows are this shape and both happen to be real control
differences, so nothing is currently mis-stated — but the nine unmapped mock kinds `D-m23-h` lists
will each land here, and **a correct build will read `divergent`.**

Fixing `D-m23-l` is in scope for this pass, because it is the same confusion as B1 and B2 —
reporting a measurement that did not happen — and it is three lines.

## Acceptance

Each fix proved by a mutation that goes red and returns on restore, **plus one route the findings
above do not name.** A fix that closes only its named route is what produced this second pass.

1. A lint scanning zero files makes the gate exit 3, not 0. Removing the floor turns the selftest red.
2. A manifest missing a required key, a dump node missing `role`, **and one further malformed input
   of your own choosing**, each exit 3 with the tokens layer's reason quoted and a ledger written.
   Narrowing the `except` back to `Inconclusive` turns the selftest red.
3. Two zero-width spaces read `unclassified`, not `present`. So does any other whitespace-class
   codepoint you can find that `str.split()` does not drop.
4. Two affordances pointed at one node produce a finding. Restoring the non-injective dict turns
   the selftest red.
5. An unvouched pairing reads `unclassified`, and the ledger's `divergent` count falls by exactly
   the two rows the verifier identified.
6. Everything that reproduced still reproduces, exit codes quoted: gate exit 1 at 132 findings
   (116 breadth + 16 copy), gate B exit 3 with a ledger written, selftest exit 0 with all three
   exits observed, `make lint` 0, `make test` twice at 1580/198, `ledger-reconcile.py` 0.

## Two things the verifier established that change how you work

**Your previous out-of-family review was performed against a snapshot that is not what shipped.**
The runner disclosed that both lanes were shown a file carrying a planted `timeout=1`; `grep -n
timeout` on the shipped engine returns only the `= 900` default and its two uses. So every finding
in `M23-gapfix-review.md` was made against a file HEAD does not contain, and one of grok's six
findings was spent on the plant. **Review the shipped diff.** When the verifier showed both lanes
the real code, both immediately returned blocking findings the earlier pass did not.

**The `timeout=1` inference does not hold** and should not be repeated as evidence. It was offered
as proof the lane read the artifact rather than pattern-matching. There was no control — no matched
trial without the plant — and "hard-coded 1-second timeout looks like a debug leftover" is a stock
review finding a pattern-matcher also produces. It rules out a canned response and nothing more.
If you want to establish a lane read your diff, **run it against something it must not flag** and
confirm it doesn't.

## Scope

Deliver B1–B4 and `D-m23-l`, with the acceptance above. `D-m23-a` … `D-m23-k` plus the new
`D-m23-m` (no node-id uniqueness check — duplicate ids collapse in `dict(flatten(...))`, so every
per-node layer under-counts and the `dumpNodes` floor is computed from the collapsed set) and
`D-m23-n` (`floors` lives in the manifest the gate reads, unlike `ALLOWED_OPTIONAL` and
`VOUCHED_CONTROLS`, so a surface author sets their own denominator) stay deferred.

Record anything else as deferred-register rows rather than fixing it.
