---
status: to-triage
found-by: tailings 0.1.0 over this session's transcript, 2026-08-29
registry-target: none
no-target-reason: its subject is gate invocations whose stdout went nowhere inside one session's transcript. DEF-361 is the nearest row and is about twelve wave-slot landings merged with no verify verdict recorded - a different mechanism, at merge rather than at invocation. Read and rejected rather than cited on the shared idea of a lost verdict. Read against the registry 2026-09-03, we4.
---
# Gates ran with their verdict thrown away and were never run again where anyone could read it

- origin: tailings audit of this session's own transcript · 2026-08-29
- audience: whoever leans on a gate having run, without being able to see what it said
- platforms: n/a
- proposed-by-ai: true

## What and why

Across this session a run of gates was invoked with their output sent to nowhere or swallowed
into a shell string, and none of them was invoked again in a way that showed what they said.
`scan_workflows.py` accounts for twelve of these on its own; the rest name
`registry-drop-gate.py`, `sweep.py`, `berths.py`, `foreign-path-gate.py`,
`runnable-path-gate.py`, `pool-mutation-gate.sh`, `target-resolution-gate.py`,
`reader-accounting.py` and `parity-manifest-check.sh`, among others.

A gate whose output nobody read is indistinguishable from a gate that did not run, and worse
than one that did not run, because the session afterwards carries the memory of having checked.
This project has already paid for that twice in a different form — a check that is permanently
red stops telling anyone anything, and a check whose verdict is discarded never told them
anything to begin with.

The work is not "stop suppressing output". Suppression is often correct: a gate called for a
single field inside a larger command has no business printing forty lines. The work is that
where a decision rested on a gate, the record can show what that gate returned.

## Acceptance sketch

- Any gate a decision rested on has at least one run in the record where its verdict — output
  or exit status — is visible to a reader.
- `scan_workflows.py`, the heaviest instance, has such a run.
- Where output is deliberately discarded, the record names what stood in for it: the exit code
  read, the field extracted, or the later visible run.
- A later audit of a session that follows this practice reports no suppressed-and-never-re-run
  gates for the gates that session leaned on.

## Assumptions made writing this

- Assuming the row count is an upper bound on the real class: some rows quote a gate's name
  appearing inside an edit to a build file rather than an actual invocation, so triage should
  expect fewer true instances than rows. The class itself is not in doubt — the twelve
  `scan_workflows.py` rows are captured invocations whose status went unread.
- Assuming this is a practice item rather than a change to the gates, which behave correctly.
- Assuming "visible in the record" means the session transcript or a written progress file,
  whichever the reader would reach for, rather than a new artifact per run.
