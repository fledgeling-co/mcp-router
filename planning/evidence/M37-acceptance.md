# M37 — acceptance evidence

`Upstream server disable and pause action` · branch `ai/l5` · worktree `.worktrees/L5` ·
cut at `49eae13`
Spec `planning/specs/spec-M37.md` · plan `planning/plans/plan-M37.md` ·
brief `planning/features-to-triage/server-disable-toggle-action.md`

Append to this file, never rewrite it. Read it **before** testing anything: if a row exists and
`git diff <that SHA>..HEAD` does not touch the files behind it, that row *is* the evidence, and
the right thing to do is skip the check and say so.

---

## What changed, under which screen

One surface: the **Servers board's inspector pane** (SURF-002). Three files under it —
`ServerInspectorCopy.swift` (new), `ServerInspectorSections.swift`, `ServerInspector.swift`.
No board, no row, no sheet, no menu and no router source changed.

**Not re-verified, and why.** The Servers *table* row, its state cell, its withheld tools cell and
its `Enable` action are M29's and this branch does not touch the files behind them. The held-change
sheet is M29's and is byte-unchanged. `RouterCore` is unchanged in full — the only RouterCore
addition is a test and a vector, so every serving consequence of `disabled` is proved by the
evidence M29 and K5 already carry. Re-running those against unchanged code has one possible
outcome.

## The rungs this branch actually reached, and the one it did not

| Oracle | Rung | Instrument |
|---|---|---|
| 1, 2, 5 (the control is offered in all five conditions, dimmed only for the two right reasons) | outcome | `ServersPauseAffordanceTests`, in-process |
| 3, 4, 14 (bound to the wire field; both directions; the pinned bytes) | effect-witness | the board model driven against a recording client, compared against `Vectors/pause-action.json` |
| 6, 7 (drawn from the named copy, and the word is never *pause*) | source-binding | `ShellTestSupport.declarationBody` over the two view files |
| 8, 9, 10 (the three claims the control makes ordinary) | outcome | the copy functions over the cross product of disabled × scoped |
| 11, 12, 13 (a paused upstream is provably not served) | effect-witness, **cross-channel** | `ControlPauseVectorTests` — the real `ControlHandler` against a real `servers.json`, read back off the filesystem through `ServerParser` and `ToolUnion.isServed`, with an untouched sibling as the control |

**Not reached: any rendered rung.** No screenshot, no on-glass walk, no `mock-fidelity` run. Stated
rather than implied, because a pass and a could-not-run look identical from outside:

- The `swiftui` lane here is `in-process`, which is what the five campaign cases record.
- `make mock-fidelity SURFACE=servers` is recorded by spec-M29 as exiting **3 — inconclusive** on a
  break inherited from `main`, and this branch did not re-measure that claim.
- The on-glass lane was not run. This branch stops before verify by its dispatch, and the machine
  carried load averages of 670 across 16 cores throughout, with a sibling worktree's `make lint`
  live for most of it.

So oracle lines 1, 2 and 5 are proved as *values a host would render*, not as pixels. That is a
weaker rung than a capture and is labelled as one.

## Gate runs

Verdict lines only, with the command that produced each. Raw gate output is deliberately not
committed: it quotes `path:line` out of the gates' own findings text, and committing that turns a
green `citation-gate` red on the act of recording it.

Both run on the committed tree at `2e1ae0b`, with nothing else of this fleet's building on the
machine, and the working tree clean afterwards.

| Command | Verdict |
|---|---|
| `make test` | **exit 0** · `Test run with 2120 tests in 271 suites passed` · 0 issues recorded · baseline on `main` was 2107 in 269, so this branch adds 13 tests in 2 suites |
| `make lint` | **exit 0** · `Done linting! Found 0 violations, 0 serious in 714 files` · `citation-gate` `exit: control 0 · blocking 0 · ratchet 0` · `CLEAN sweep-control: 105 discovered sweep(s), all disposed; 31 declared control(s) run and passing` · `registry-drop-gate` `no id dropped — registry holds 254` · `pin-class-gate` `every vector declares a pin class; 0 carried, 28 compliant` |
| `zsh app/Scripts/pool-mutation-gate-selftest.sh` | **exit 0** · `cases: 14 passed, 0 failed, of 14` · run alone, tree clean afterwards |
| `swift test --filter` per mutation arm | ten arms, each red by assertion against a green baseline; see the mutation lane below |

## A finding about the gates, not about this branch

`sweep-control-gate.py` runs `app/Scripts/pool-mutation-gate-selftest.sh` as a declared control
with a **120-second cap**, and `make lint` also runs that script directly as its own member. Under
load the capped run is killed **mid-mutation**, and the plants it had made are left in the working
tree. Measured on this branch, 2026-08-29:

- `sweep-control-gate.py` printed `FAIL  app/Scripts/pool-mutation-gate-selftest.sh control did not
  finish in 120s`, alongside three other controls it timed out the same way.
- Two files were left modified that this branch never touched — a `// MUTATED:` line in place of a
  `SIGKILL` escalation in `StdioUpstreamSession.swift`, and a shortened selector in
  `design/mcp-router-console.html`.
- The later direct run of the same script then failed **4 of 14** cases, all four of them the
  stale-mutation arms, and `make lint` exited 1 on it.
- Restoring the two files and running the script alone: **14 of 14 passed, exit 0**, tree clean.

So the red is the timeout's leftovers being read as a stale mutation by the next run, not a defect
in the guard. It is this repository's own rule — *a gate must not mutate the working tree as a side
effect of checking* — arriving as a load-dependent interaction between two members of one target.
Recorded here rather than fixed: the fix is a restore-on-kill in one of the two gates, it belongs
to whoever owns them, and inventing it inside a feature branch would be the scope creep this
pipeline forbids.

---

## The mutation lane

Ten arms, declared in `planning/plans/plan-M37.md` before they were run, each planted against a
green baseline with the tree restored from `HEAD` afterwards. All ten red **by assertion** — the
table in the plan says which, because a mutation that merely fails to compile exits 1 without
measuring anything and reads identically from the outside.

Two of them changed the work rather than confirming it:

- **PAU-4 found an unguarded oracle.** Re-aimed after its first form turned out not to compile, it
  passed against a switch that dimmed itself once the server was disabled — because the assertion
  searched the whole Behaviour section and the `Keep warm` toggle's identical `disabledReason`
  satisfied it two declarations below. The assertion now slices the switch's own declaration first.
  Without the arm, D5 would have shipped with nothing watching it.
- **PAU-8c/d measured a divergence this item does not own.** Driving `{"disabled":"yes"}` through
  the port and reading the result back: the server is **still served**.

## A second finding about the router, not about this branch

Measured 2026-08-29 on this branch, by parsing one config and asking the two readers:

    "disabled": "yes"   typed `UpstreamConfig.disabled` = nil
                        `ToolUnion.isServed` = true      (the tools are served)
                        raw truthiness       = true      (`Describe.row` reports disabled: true)

`ServerParser` reads the field through `asBool`, which returns `nil` for anything that is not a
JSON boolean, while `Describe` reads the same field off `raw` and reports its JS truthiness — that
second reading is deliberate and its comment says so. The TypeScript reference copies the raw value
and tests `!u.disabled`, so `"yes"` is **not served** there.

So on the Swift router a config carrying a non-boolean truthy `disabled` draws *disabled by you*
on the board over a server whose tools are still in every session's list. It is reachable: the
control API's PATCH writes the supplied value through, and `scripts/acceptance/control-differential.sh` at `bc51e996386494ed9fdc0175eb5d7f259a1daa40` (historical source)
already drives exactly `{"disabled":"yes"}` — but that lane diffs the status, the response body and
`servers.json`, none of which disagree, which is K5's point about an equivalence lane restated by a
second example.

**Not fixed here, deliberately.** It is RouterCore behaviour, it is a parity semantics question
rather than a bug with one obvious answer — match the reference's JS truthiness, or refuse a
non-boolean at the PATCH — and M37 changes no router code at all. Filed as a finding for whoever
owns R4's parity surface.
