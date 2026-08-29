#!/bin/bash
#
# The gate beside this file makes a claim — nothing under the invocation directory reaches the
# network — and a claim is worth what its failure mode is worth. This fleet has now found five
# oracles that could not fail inside one merged item, seventeen arms all watching readers while the
# writer went unwitnessed, and a printer filed as a gate. So the gate is watched failing here before
# any green from it is spent.
#
# Three arms, and the third is the one that catches the failure this file exists for:
#
#   1. On the tree as it stands, the gate exits 0.
#   2. With one refused symbol planted in a scratch copy, it exits 1 AND names the file.
#   3. Pointed at a directory holding no Swift at all, it exits 2 rather than reporting clean.
#
# Arm 3 is not decoration. A gate whose directory is renamed keeps exiting 0 forever, and every
# reader downstream of it reads that as a measurement. `planning/null-run-gate.py` is the mechanism
# for the same class across this repository.
#
# It works in a scratch copy of the tree, never in place: a gate — or a gate's selftest — that
# mutates the working tree as a side effect of checking is a rule this fleet learned the hard way.
#
# Exit 0 when all three arms held. Exit 1 when any did not, naming which.

set -euo pipefail

cd "$(dirname "$0")/../.."

GATE="scripts/lint/no-telemetry-egress.sh"
SUBJECT="app/Sources/RouterCore/Invocations"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

failures=0
note() { echo "no-telemetry-egress-selftest: $1"; }

# --- Arm 1: the tree as it stands is clean -----------------------------------------------------
set +e
"$GATE" > /dev/null 2>&1
arm1=$?
set -e
if [[ $arm1 -ne 0 ]]; then
  note "ARM 1 FAILED — the gate does not pass on the unmutated tree (exit $arm1)"
  failures=$((failures + 1))
else
  note "arm 1 held — exit 0 on the unmutated tree"
fi

# --- Arm 2: a planted symbol reddens it --------------------------------------------------------
mkdir -p "$scratch/planted"
cp "$SUBJECT"/*.swift "$scratch/planted/" 2>/dev/null || true
cat > "$scratch/planted/Planted.swift" <<'PLANT'
import Foundation
enum Planted {
    static func send() {
        _ = URLSession.shared
    }
}
PLANT
set +e
planted_output=$(TELEMETRY_EGRESS_ROOT="$scratch/planted" "$GATE" 2>&1)
arm2=$?
set -e
if [[ $arm2 -ne 1 ]]; then
  note "ARM 2 FAILED — a planted URLSession did not redden the gate (exit $arm2)"
  failures=$((failures + 1))
elif ! grep -q "Planted.swift" <<< "$planted_output"; then
  note "ARM 2 FAILED — the gate reddened without naming the offending file"
  failures=$((failures + 1))
else
  note "arm 2 held — exit 1, and Planted.swift is named"
fi

# --- Arm 3: an empty subject is not a pass -----------------------------------------------------
mkdir -p "$scratch/empty"
set +e
TELEMETRY_EGRESS_ROOT="$scratch/empty" "$GATE" > /dev/null 2>&1
arm3=$?
set -e
if [[ $arm3 -ne 2 ]]; then
  note "ARM 3 FAILED — a directory with no Swift in it did not exit 2 (exit $arm3)"
  failures=$((failures + 1))
else
  note "arm 3 held — exit 2 on a subject holding nothing"
fi

if [[ $failures -ne 0 ]]; then
  note "$failures of 3 arms failed; the gate beside this file cannot be trusted until they hold"
  exit 1
fi
note "3 of 3 arms held"
