#!/usr/bin/env bash
#
# R4 — the control lane.
#
# R3's control-differential.sh is the control lane. It is not rewritten here, and not copied:
# it already starts its own reference, refuses the developer's real home, compares 49 rows
# across every reachable route, asserts R3's five declared divergences in both directions and
# asserts the two D-j defects. A second copy of that logic is a second idea of what "green"
# means, and the two would drift.
#
# This wrapper exists so the gate has a uniform `parity-<lane>.sh` entry point, and so the
# lane's exit codes mean the same thing every other lane's do. PARITY_RESULTS passes straight
# through, which is how the differential's `record` rows reach reconciliation.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

bash "$REPO_ROOT/scripts/acceptance/control-differential.sh"
status=$?

# 1 from the differential means it compared everything and found mismatches — today that is the
# two known D-j defects, which the manifest already carries as blocked with an owner. The gate
# decides what that means during reconciliation; the lane's job is to report, not to judge.
exit $status
