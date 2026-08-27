#!/usr/bin/env bash
#
# Runs EVERY selftest enrolled in `make parity-selftest`, then aggregates.
#
# Why this exists (P10). `make parity-selftest` used to be five recipe lines, and make stops a
# target at the first line that fails. `parity-manifest-selftest.sh` is first, it was red on `main`
# from `b1160ef` onward — because `planning/parity/surface.tsv` pinned `# rows: 95` against a file
# holding 97 — and the four selftests behind it therefore never ran at all. `grep -c
# parity-regen-selftest` over a full run log returns 0. One of the four it silenced was P9's own
# new selftest, merged the same evening into a target that could not reach it.
#
# This is G10's finding, one target over: `make acceptance` had the same shape, `shells.sh` was red
# on `main` long enough that the blob was byte-identical across three branches, and the seven lanes
# behind it had not been reached. The repair there is the repair here, for the reason given there —
# reordering makes one selftest run and leaves the ordering as the thing deciding what gets
# measured. So: run all of them, keep going past a red one, and aggregate at the end.
#
# The risk of continuing is a green summary over a red selftest, so that is what this file is built
# to make impossible rather than what it hopes to avoid:
#
#   * The summary names EVERY selftest with its own exit code, printed from the same array the
#     verdict is computed from. There is no total a selftest can be absent from.
#   * `selftests run` must equal `selftests enrolled`, or the run is red on that alone.
#   * The verdict is computed from the codes, never from a flag any selftest could fail to set.
#
# `parity-lane-selftest.sh` needs `dist/index.js` — the TypeScript reference — and takes about four
# and a half minutes. Without it, it is reported SKIPPED rather than run, loudly, and that is not a
# pass: the Makefile has always said so and the summary says so too. It does not fail the run,
# because this target has to stay runnable in a fresh worktree that has not built the reference yet.
#
# Exit codes, kept distinct for the reason the Makefile has always given about `acceptance`:
# collapsing them is how "the environment could not run this" gets reported as a broken tree.
#
#   0  every enrolled selftest passed (or was loudly skipped for a missing reference)
#   1  at least one selftest FAILED (any nonzero that is not 2)
#   2  no failures, but at least one selftest COULD NOT RUN (exit 2)
#
# `set -e` is deliberately absent. The whole point is to survive a red selftest; -u and pipefail stay.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# The enrolled set. This array is the single home for the list: the Makefile calls this script
# rather than repeating the selftests, so the target and this table cannot drift apart.
SELFTESTS=(
    parity-manifest-selftest.sh
    parity-lock-selftest.sh
    parity-normalise-selftest.sh
    parity-regen-selftest.sh
    parity-lane-selftest.sh
)

# Both overrides exist for watching this aggregation go red, which needs selftests with known exits.
# Neither is read in a normal run.
SELFTEST_DIR="${PARITY_SELFTEST_DIR:-$ROOT/scripts/acceptance}"
if [ -n "${PARITY_SELFTESTS:-}" ]; then
    read -r -a SELFTESTS <<< "$PARITY_SELFTESTS"
fi

ENROLLED=${#SELFTESTS[@]}
names=()
codes=()

for selftest in "${SELFTESTS[@]}"; do
    echo
    echo "──────────────────────────────────────────────────────────────────────"
    echo "selftest: $selftest"
    echo "──────────────────────────────────────────────────────────────────────"
    if [ "$selftest" = "parity-lane-selftest.sh" ] && [ ! -f "$ROOT/dist/index.js" ]; then
        echo "parity-lane-selftest: SKIPPED — no dist/index.js. This is a skip, not a pass:"
        echo "  run 'npm install && npm run build' and re-run 'make parity-lane-selftest' to prove"
        echo "  the lanes can still go red."
        code=126
    elif [ ! -x "$SELFTEST_DIR/$selftest" ]; then
        # Enrolled and not runnable is a RESULT. Skipping it here would recreate the whole defect:
        # a selftest nothing dispatches, passing by hand forever while reading as covered work.
        echo "ENROLLED BUT NOT EXECUTABLE: $SELFTEST_DIR/$selftest" >&2
        code=127
    else
        "$SELFTEST_DIR/$selftest"
        code=$?
    fi
    names+=("$selftest")
    codes+=("$code")
    echo "selftest $selftest exited $code"
done

RUN=${#names[@]}
fails=0; blocked=0; passes=0; skipped=0

echo
echo "══════════════════════════════════════════════════════════════════════"
echo "make parity-selftest — per-selftest result"
echo "══════════════════════════════════════════════════════════════════════"
printf '%-32s %6s  %s\n' "SELFTEST" "EXIT" "VERDICT"
for i in "${!names[@]}"; do
    c=${codes[$i]}
    case "$c" in
        0)   verdict="PASS";                                  passes=$((passes + 1)) ;;
        2)   verdict="BLOCKED — could not run";               blocked=$((blocked + 1)) ;;
        126) verdict="SKIPPED — no reference build (not a pass)"; skipped=$((skipped + 1)) ;;
        *)   verdict="FAIL";                                  fails=$((fails + 1)) ;;
    esac
    printf '%-32s %6s  %s\n' "${names[$i]}" "$c" "$verdict"
done
echo "----------------------------------------------------------------------"
echo "enrolled: $ENROLLED   run: $RUN   pass: $passes   fail: $fails   blocked: $blocked   skipped: $skipped"

# If these disagree, a selftest left the run without leaving a row, and no verdict computed from
# the rows can be trusted — so this is red on its own terms.
if [ "$RUN" -ne "$ENROLLED" ]; then
    echo "PARITY SELFTESTS FAILED: $ENROLLED enrolled but $RUN produced a result — one left no row." >&2
    exit 1
fi

if [ "$fails" -gt 0 ]; then
    echo "PARITY SELFTESTS FAILED: $fails of $ENROLLED selftests failed." >&2
    exit 1
fi

if [ "$blocked" -gt 0 ]; then
    echo "PARITY SELFTESTS COULD NOT COMPLETE: $blocked of $ENROLLED could not run (exit 2)." >&2
    echo "This is not a pass, and it is not a failure either — see each selftest's own message." >&2
    exit 2
fi

if [ "$skipped" -gt 0 ]; then
    echo "PARITY SELFTESTS PASSED, WITH $skipped SKIPPED: the skipped one needs dist/index.js."
    exit 0
fi

echo "PARITY SELFTESTS PASSED: all $ENROLLED ran and exited 0."
exit 0
