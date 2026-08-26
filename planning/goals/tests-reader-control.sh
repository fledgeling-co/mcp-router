#!/bin/bash
# Does tests-check.sh's reader stay silent on a GREEN log?
#
# It did not. The reader shipped with `Test .* failed` in its pattern, and this repo names tests
# after the failures they exercise, so a green run gave it 59 matches and it printed them under a
# heading reading FAILING TESTS. This control is those real lines, kept as a fixture: a reader that
# matches any of them is matching test names rather than failures.
#
# Second arm: a real swift-testing issue line MUST match, so the fixture cannot be satisfied by a
# pattern that matches nothing at all.
#
# The fixture names FixtureOnlyTests.swift, which is not a file in this tree, and that is
# deliberate. The first version used a real tracked test file, and `planning/citation-gate.py`
# correctly read the synthetic log line as a citation into the repository — adding a bare-citation
# row to the ratchet for a pointer that was never a claim about anything. Fixture data that looks
# like a citation IS a citation to every reader that cannot ask what it was for.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2
# The pattern is EXTRACTED from tests-check.sh, never copied. A copied pattern passes this control
# for as long as it takes someone to edit the original, and then the control is testing a string
# nothing runs — which is the shape of a gate that cannot fail.
PAT=$(sed -n "s/^if ! grep -hE '\(.*\)' \"\$log\".*/\1/p" planning/goals/tests-check.sh)
if [ -z "$PAT" ]; then
  echo "control: could not extract the reader's pattern from tests-check.sh — its shape changed."
  echo "control: INCONCLUSIVE at exit 2; this control is now testing nothing and says so."
  exit 2
fi
echo "control: pattern extracted from tests-check.sh: $PAT" 

green=$(cat <<'LINES'
􁁛  Test "a failed poll appends no sample and still ages the window" passed after 0.878 seconds.
􁁛  Test "a failed rename leaves the temp file in place and propagates" passed after 2.832 seconds.
􀟈  Test "a failed re-query keeps the last good rows and marks them stale" started.
􁁛  Test "a router that answers with nothing is an empty board, not a failed one" passed after 3.899 seconds.
􁁛  Test "the partial scenario returns servers where exactly some carry a reason they failed" passed after 0.865 seconds.
2026-08-26T12:51:35.150Z error failed to index "dieslisting": [-32603] Internal error: Client disconnected
􁁛  Test run with 1980 tests in 252 suites passed after 10.409 seconds.
LINES
)
red=$(cat <<'LINES'
✘  Test "the one that broke" recorded an issue at FixtureOnlyTests.swift:238: Expectation failed
􀢄  Test run with 1980 tests in 252 suites failed after 10.627 seconds with 1 issue.
FixtureOnly.swift:12:5: error: cannot find 'Bar' in scope
LINES
)

fp=$(printf '%s\n' "$green" | grep -cE "$PAT" || true)
tp=$(printf '%s\n' "$red"   | grep -cE "$PAT" || true)
echo "control: green-log fixture (7 lines, 5 with 'failed' in the TEST NAME) -> $fp match(es), want 0"
echo "control: red-log fixture (3 real failure lines)                        -> $tp match(es), want 3"
rc=0
[ "$fp" -ne 0 ] && { echo "control: FAILED — the reader matches test names, not failures"; rc=1; }
[ "$tp" -ne 3 ] && { echo "control: FAILED — the reader misses a real failure line"; rc=1; }
[ "$rc" -eq 0 ] && echo "control: HELD — silent on green, complete on red"
exit $rc
