#!/bin/bash
#
# Runs EVERY lane enrolled in `make acceptance`, then aggregates.
#
# Why this exists (G10). `make acceptance` used to be eight recipe lines, and make stops a target at
# the first line that fails. `shells.sh` is first, it was red on `main` for long enough that the blob
# was byte-identical across three branches, and so the seven lanes behind it had not been reached at
# all. A lane that has never run is not known to pass — so the red lane did not merely fail, it
# *hid* the other seven, and every later enrolment into this target was inert while still reading in
# its commit message like a way to make a lane run.
#
# The repair is not to reorder the list. Reordering makes one lane run and leaves the ordering as the
# thing that decides what gets measured, which is the same defect with a different lane at the front.
# So: run all of them, keep going past a red one, and aggregate at the end.
#
# The risk of continuing is a green summary over a red lane, which is worse than halting — so that
# is the thing this file is built to make impossible rather than the thing it hopes to avoid:
#
#   * The summary names EVERY lane with its own exit code. There is no total that a lane can be
#     absent from, because the table is printed from the same array the verdict is computed from.
#   * The verdict is computed from the codes, never from a flag any lane could fail to set.
#   * The counts are printed, and `lanes run` must equal `lanes enrolled` or the run is red on that
#     alone — a lane that vanished between enrolment and execution is a result, not a skip.
#
# Exit codes, kept distinct for the reason the Makefile has always given: collapsing them is how "no
# Accessibility permission" gets reported as a broken app.
#
#   0  every lane passed
#   1  at least one lane FAILED an assertion   (any nonzero that is not 2)
#   2  no failures, but at least one lane COULD NOT RUN (a lane exited 2)
#
# A failure outranks a blocked lane, because a run with both has something known to be broken in it.
#
# `set -e` is deliberately absent. The whole point is to survive a red lane; -u and pipefail stay.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# The enrolled set. This array is the single home for the lane list: the Makefile calls this script
# rather than repeating the lanes, so the target and this table cannot drift apart.
LANES=(
    shells.sh
    control-client.sh
    p1-auth-routes.sh
    mac-shell.sh
    r7-harness-reconciliation.sh
    m22-boards.sh
    menu-badge-lane.sh
    menu-badge-lane-selftest.sh
)

# Both overrides exist for the selftest, which must be able to plant lanes with known exits. Neither
# is read in a normal run, and the selftest is what proves the aggregation can actually go red.
LANE_DIR="${ACCEPTANCE_LANES_DIR:-$ROOT/scripts/acceptance}"
if [ -n "${ACCEPTANCE_LANES:-}" ]; then
    read -r -a LANES <<< "$ACCEPTANCE_LANES"
fi

ENROLLED=${#LANES[@]}
names=()
codes=()

for lane in "${LANES[@]}"; do
    echo
    echo "──────────────────────────────────────────────────────────────────────"
    echo "lane: $lane"
    echo "──────────────────────────────────────────────────────────────────────"
    if [ ! -x "$LANE_DIR/$lane" ]; then
        # Enrolled and not runnable is a RESULT. Skipping it here would recreate the whole defect:
        # a lane nothing dispatches, passing by hand forever while reading as covered work.
        echo "ENROLLED BUT NOT EXECUTABLE: $LANE_DIR/$lane" >&2
        code=127
    else
        "$LANE_DIR/$lane"
        code=$?
    fi
    names+=("$lane")
    codes+=("$code")
    echo "lane $lane exited $code"
done

RUN=${#names[@]}

fails=0
blocked=0
passes=0

echo
echo "══════════════════════════════════════════════════════════════════════"
echo "make acceptance — per-lane result"
echo "══════════════════════════════════════════════════════════════════════"
printf '%-36s %6s  %s\n' "LANE" "EXIT" "VERDICT"
for i in "${!names[@]}"; do
    c=${codes[$i]}
    case "$c" in
        0) verdict="PASS";    passes=$((passes + 1)) ;;
        2) verdict="BLOCKED — could not run"; blocked=$((blocked + 1)) ;;
        *) verdict="FAIL";    fails=$((fails + 1)) ;;
    esac
    printf '%-36s %6s  %s\n' "${names[$i]}" "$c" "$verdict"
done

echo "----------------------------------------------------------------------"
echo "enrolled: $ENROLLED   run: $RUN   pass: $passes   fail: $fails   blocked: $blocked"

# The count check. If these disagree, a lane left the run without leaving a row, and no verdict
# computed from the rows can be trusted — so this is red on its own terms.
if [ "$RUN" -ne "$ENROLLED" ]; then
    echo "ACCEPTANCE FAILED: $ENROLLED lanes enrolled but $RUN produced a result — a lane left no row." >&2
    exit 1
fi

if [ "$fails" -gt 0 ]; then
    echo "ACCEPTANCE FAILED: $fails of $ENROLLED lanes failed an assertion." >&2
    exit 1
fi

if [ "$blocked" -gt 0 ]; then
    echo "ACCEPTANCE COULD NOT COMPLETE: $blocked of $ENROLLED lanes could not run (exit 2)." >&2
    echo "This is not a pass. It is not a failed assertion either — see each lane's own message." >&2
    exit 2
fi

echo "ACCEPTANCE PASSED: all $ENROLLED lanes exited 0."
exit 0
