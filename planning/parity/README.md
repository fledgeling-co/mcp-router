# planning/parity — the cutover surface

`surface.tsv` is the census this repo reports parity against. It exists because of one sentence in
R4's brief: *"This item may not be marked done on a partial pass."*

A differential that compares thirty rows and prints "parity" is worse than no differential, because
it converts an unknown into a certainty that a cutover then gets justified by. R3's
`control-differential.sh` compared 32 rows and passed. The enumerated surface is **74 rows**. Both
statements were true at the same time, and only one of them was being reported.

## What a row is

One capability the cutover requires the Swift router to answer for. Six tab-separated fields:

| Field | Meaning |
|---|---|
| `group` | `control`, `fixture`, `divergence`, `mcp`, `cli`, `pool`, `log` |
| `id` | stable row id. A lane reports its result against this, so it must be unique |
| `subject` | for `control`, the exact route string `src/control.ts` answers; for `fixture`, the fixture basename. Both are checked mechanically against the source |
| `verdict` | `proven`, `proven-by-suite` or `blocked` |
| `owner` | the item that would unblock a blocked row; `-` otherwise |
| `note` | why. A blocked row's note says what is missing, not merely that something is |

## The three verdicts are not the same claim

- **`proven`** — a lane compared both sides on this subject and they agreed.
- **`proven-by-suite`** — nothing is observable from outside the process, and a named test carries
  it instead. Weaker, printed as such, and the cited test is resolved against `app/Tests` by
  `parity-manifest-check.sh` on every run.
- **`blocked`** — not compared. Never counted toward coverage.

And `proven` itself does not mean the same thing in every group, which is why the gate prints
coverage **per group** rather than one blended number:

- `control` compares the two routers on the wire, byte for byte, status included.
- `fixture` compares the live reference against its own recording. That is *reference currency* —
  it proves the contract the Swift decode suite is written against is still the one the reference
  sends. It is not two-router parity.
- `pool` compares a live reference measurement against a Swift real-process test. Both halves are
  real, but they are taken at different times, which is weaker than a simultaneous diff.

Collapsing those three into "50 proven" is the exact conflation this directory exists to prevent.

## Why the manifest is guarded rather than trusted

A hand-maintained census drifts, and it drifts in the dangerous direction: a route added to
`control.ts` with no row here does not turn the gate red — it shrinks the denominator, and the
coverage percentage goes **up**.

`scripts/acceptance/parity-manifest-check.sh` therefore derives the control rows from
`src/control.ts` and the fixture rows from the fixture directory, and fails when this file and the
source disagree **in either direction**. It also resolves every cited test and script, because
three of this manifest's first six citations named tests that did not exist — written from the
divergence prose rather than read out of the suite, and indistinguishable from real ones until
something checked.

## Running it

```bash
scripts/acceptance/parity-gate.sh          # every lane, then reconciliation
PARITY_LANES="control" scripts/acceptance/parity-gate.sh   # one lane
scripts/acceptance/parity-manifest-check.sh                # the census alone
```

Exit `0` only when every row is proven. `1` when a row is blocked or a lane found a mismatch.
`2` when the environment could not run a lane, kept distinct because a skipped lane is not a pass.

The gate starts its own reference on ports in the 896x range and refuses a port it does not own.
It never touches the router on 8975/8976, the user's `MCP_ROUTER_HOME`, or `~/.claude.json`.

## `fixture-status.tsv`

The HTTP status of every recorded fixture, which the recorded set has never carried — deferred
child **D-a**. A port could answer every fixture's bytes under the wrong status and the whole
decode suite would still pass. Captured by re-running the recorder with `STATUS_DIR` set; the
fixture files themselves are never written to.
