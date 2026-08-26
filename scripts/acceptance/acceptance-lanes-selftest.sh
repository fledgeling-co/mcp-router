#!/bin/bash
#
# Proves `acceptance-lanes.sh` can go red, and that a red lane cannot hide inside a green total.
#
# The aggregation G10 asks for trades one failure mode for another: halting let one stale lane hide
# five others, and continuing risks a green summary over a red lane. A summary that has never been
# observed reporting a red lane is exactly the instrument-that-cannot-fail this repository keeps a
# register of — so the continuing half is only safe if the redness is demonstrated rather than
# asserted. Every arm below plants a known exit and requires the aggregate to react to it.
#
# It runs against scratch lanes in a temp directory, in about a second, with no build and no GUI.
# That is deliberate: a selftest that needs the real lanes could only run when the real lanes run,
# which is the state this whole item exists to end.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/scripts/acceptance/acceptance-lanes.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0
note_fail() { echo "  SELFTEST FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }
note_pass() { echo "  ok — $*"; }

# Plant a lane that prints a recognisable line and exits with a given code.
plant() { # $1 = name, $2 = exit code
    cat > "$WORK/$1" <<PLANT
#!/bin/bash
echo "ran $1"
exit $2
PLANT
    chmod +x "$WORK/$1"
}

run_lanes() { # $1 = space-separated lane names -> sets OUT and CODE
    OUT="$(ACCEPTANCE_LANES_DIR="$WORK" ACCEPTANCE_LANES="$1" "$RUNNER" 2>&1)"
    CODE=$?
}

# ---------------------------------------------------------------- arm 0: green is reachable
#
# Without this the whole selftest is satisfiable by a runner that always exits 1, which would pass
# every other arm below. A gate that cannot say yes is not a gate.
echo "arm 0 — an all-green set exits 0"
plant a.sh 0; plant b.sh 0; plant c.sh 0
run_lanes "a.sh b.sh c.sh"
[ "$CODE" -eq 0 ] || note_fail "an all-green set exited $CODE, expected 0"
echo "$OUT" | grep -q "ACCEPTANCE PASSED: all 3 lanes exited 0" \
    || note_fail "the all-green summary did not state the pass with its count"
[ "$CODE" -eq 0 ] && note_pass "3 green lanes -> exit 0, and the summary says so"

# ---------------------------------------------------------------- arm 1: a red lane reddens the total
#
# The arm this item is actually about. The failing lane sits FIRST, which is where `shells.sh` sat.
echo "arm 1 — a failing FIRST lane reddens the aggregate and is named"
plant a.sh 1; plant b.sh 0; plant c.sh 0
run_lanes "a.sh b.sh c.sh"
[ "$CODE" -eq 1 ] || note_fail "a set containing a failing lane exited $CODE, expected 1"
echo "$OUT" | grep -qE '^a\.sh +1 +FAIL' \
    || note_fail "the summary table does not carry a.sh with exit 1 and FAIL"
echo "$OUT" | grep -q "ACCEPTANCE FAILED: 1 of 3 lanes failed an assertion" \
    || note_fail "the verdict line does not count the failure"
[ "$CODE" -eq 1 ] && note_pass "a red first lane -> exit 1, named in the table, counted in the verdict"

# ---------------------------------------------------------------- arm 2: the lanes behind it still run
#
# This is the difference between the repair and the reordering the brief forbids. If a red first
# lane still stops the run, nothing has changed except which lane is privileged.
echo "arm 2 — the lanes behind a red one are still reached"
plant a.sh 1; plant b.sh 0; plant c.sh 0
run_lanes "a.sh b.sh c.sh"
for lane in b.sh c.sh; do
    echo "$OUT" | grep -q "ran $lane" || note_fail "$lane did not run behind a failing first lane"
done
echo "$OUT" | grep -q "run: 3" || note_fail "the counts do not show all 3 lanes producing a result"
note_pass "b.sh and c.sh both ran behind a red a.sh, and the counts show 3 of 3"

# ---------------------------------------------------------------- arm 3: a red lane cannot hide in a green majority
#
# The named risk of continuing, stated as an assertion: one red among many green must not round to
# green, and the red one must be findable in the table by name.
echo "arm 3 — one red among six green does not round to green"
plant a.sh 0; plant b.sh 0; plant c.sh 0; plant d.sh 0; plant e.sh 0; plant f.sh 0; plant g.sh 1
run_lanes "a.sh b.sh c.sh d.sh e.sh f.sh g.sh"
[ "$CODE" -eq 1 ] || note_fail "6 green and 1 red exited $CODE, expected 1"
echo "$OUT" | grep -qE '^g\.sh +1 +FAIL' || note_fail "the one red lane is not in the table"
echo "$OUT" | grep -q "pass: 6   fail: 1   blocked: 0" || note_fail "the counts do not separate 6 pass from 1 fail"
echo "$OUT" | grep -q "ACCEPTANCE PASSED" && note_fail "a run with a red lane printed ACCEPTANCE PASSED"
[ "$CODE" -eq 1 ] && note_pass "6 green + 1 red -> exit 1, counted 6/1/0, and no PASSED line"

# ---------------------------------------------------------------- arm 4: blocked is not a pass and not a failure
#
# The distinction the Makefile has always carried: reporting a missing Accessibility grant as a
# failed assertion is how a suite produces confident false failures that all point at the app.
echo "arm 4 — a lane that could not run exits 2, not 0 and not 1"
plant a.sh 0; plant b.sh 2; plant c.sh 0
run_lanes "a.sh b.sh c.sh"
[ "$CODE" -eq 2 ] || note_fail "a set with a blocked lane exited $CODE, expected 2"
echo "$OUT" | grep -qE '^b\.sh +2 +BLOCKED' || note_fail "b.sh is not classed BLOCKED in the table"
echo "$OUT" | grep -q "ACCEPTANCE COULD NOT COMPLETE" || note_fail "the blocked verdict line is missing"
echo "$OUT" | grep -q "ACCEPTANCE PASSED" && note_fail "a run with a blocked lane printed ACCEPTANCE PASSED"
[ "$CODE" -eq 2 ] && note_pass "a blocked lane -> exit 2, classed BLOCKED, no PASSED line"

# ---------------------------------------------------------------- arm 5: a failure outranks a blocked lane
echo "arm 5 — a failure and a blocked lane together exit 1"
plant a.sh 2; plant b.sh 1; plant c.sh 0
run_lanes "a.sh b.sh c.sh"
[ "$CODE" -eq 1 ] || note_fail "a set with both a failure and a blocked lane exited $CODE, expected 1"
echo "$OUT" | grep -q "pass: 1   fail: 1   blocked: 1" || note_fail "the counts do not report 1/1/1"
[ "$CODE" -eq 1 ] && note_pass "fail + blocked -> exit 1, counts 1/1/1, both visible"

# ---------------------------------------------------------------- arm 6: enrolled but not runnable is red
#
# The shape that started this: a lane enrolled into the target while nothing could actually dispatch
# it. Silence here would let an enrolment read as covered work forever.
echo "arm 6 — an enrolled lane that is not executable is red, not skipped"
plant a.sh 0; plant b.sh 0
run_lanes "a.sh b.sh missing.sh"
[ "$CODE" -eq 1 ] || note_fail "an unrunnable enrolled lane exited $CODE, expected 1"
echo "$OUT" | grep -qE '^missing\.sh +127 +FAIL' || note_fail "missing.sh is not in the table at 127"
[ "$CODE" -eq 1 ] && note_pass "an enrolled lane with no executable -> 127 and FAIL, in the table"

# ---------------------------------------------------------------- arm 7: every enrolled lane gets a row
#
# The count check, armed. A verdict computed from rows is only as good as the guarantee that every
# lane produced one.
echo "arm 7 — every enrolled lane appears in the table exactly once"
plant a.sh 0; plant b.sh 1; plant c.sh 2
run_lanes "a.sh b.sh c.sh"
for lane in a.sh b.sh c.sh; do
    n="$(echo "$OUT" | grep -cE "^${lane//./\\.} +[0-9]+ +")"
    [ "$n" -eq 1 ] || note_fail "$lane appears $n times in the table, expected exactly 1"
done
echo "$OUT" | grep -q "enrolled: 3   run: 3" || note_fail "enrolled/run counts are not both 3"
note_pass "3 enrolled, 3 rows, one each"

echo
if [ "$FAILURES" -eq 0 ]; then
    echo "acceptance-lanes selftest: 8 arms, all held."
    exit 0
fi
echo "acceptance-lanes selftest: $FAILURES assertion(s) failed." >&2
exit 1
