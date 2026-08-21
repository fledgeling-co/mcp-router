#!/bin/bash
#
# M23's mock-to-SwiftUI conversion gate.
#
#   ./scripts/acceptance/mock-fidelity-gate.sh [surface]        # default: servers
#
# Three exit states, and the third one is the reason this exists:
#
#   0  clean and complete — every required layer ran and found nothing
#   1  findings — at least one difference
#   3  inconclusive — a layer the verdict depended on could not run
#
# A two-state gate reports a layer it could not perform as agreement, because a property the
# instrument cannot compute reads the same on both sides and the differ emits nothing. So every
# stage here fails to 3 rather than to 0: a missing manifest, a build that did not produce the
# harness, a dump the recorder wrote no nodes into, a census smaller than its floor.
#
# What it drives, in order:
#
#   1. builds MeasureDump with MCP_ROUTER_MEASURE=1, which is what defines MEASURE and compiles the
#      in-view harness in at all. Without the flag the tool exits 3 by construction rather than
#      writing a dump of a surface it never instrumented.
#   2. renders each declared state of the surface headless and writes one JSON tree per state.
#   3. hands the manifest and the dumps to scripts/acceptance/mock_fidelity.py, which runs the eight
#      layers — including `literals`, which EXECUTES scripts/lint/no-raw-design-values.sh rather than
#      re-spelling its rule here, and quotes what it said.
#
# It is not in `make all`: it needs the MEASURE build, which is a second compilation of the UI
# target, for the same reason `mutation` and `acceptance` are out. `make mock-fidelity-selftest` is
# the part that runs unattended, and it proves all three exits are reachable.
set -uo pipefail

cd "$(dirname "$0")/../.."
ROOT=$(pwd)

SURFACE=${1:-servers}
MANIFEST="planning/fidelity/${SURFACE}.layers.json"
DUMPS="planning/fidelity/dumps"
LEDGER="planning/fidelity/${SURFACE}.ledger.md"
SETTLE=${MOCK_FIDELITY_SETTLE:-1.5}

# Every stage below can exit 3 before the engine is ever invoked — a missing manifest, a MEASURE
# build that failed, a harness that would not render. Each of those leaves the previous run's table
# sitting at $LEDGER under an exit that says this run measured nothing, which is the stale ledger
# with the gate script rather than the engine in front of it (`grok-4.6`). So they say so.
stale_ledger_note() {
  if [ -f "$LEDGER" ]; then
    echo "              The table at $LEDGER is an earlier run's and does not describe this one."
  fi
}

if [ ! -f "$MANIFEST" ]; then
  echo "INCONCLUSIVE mock-fidelity: no layer manifest at $MANIFEST, so which layers this surface's"
  echo "              verdict depends on is unknown. That is not a clean surface."
  stale_ledger_note
  exit 3
fi

STATES=$(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["states"]))' "$MANIFEST") || {
  echo "INCONCLUSIVE mock-fidelity: $MANIFEST did not parse"
  stale_ledger_note
  exit 3
}

echo "mock-fidelity-gate: building the measurement harness (MCP_ROUTER_MEASURE=1)"
BUILD_LOG=$(mktemp)
if ! (cd app && MCP_ROUTER_MEASURE=1 swift build --product MeasureDump) > "$BUILD_LOG" 2>&1; then
  echo "INCONCLUSIVE mock-fidelity: the MEASURE build failed, so no surface was measured. swift said:"
  sed 's/^/              /' "$BUILD_LOG" | tail -30
  rm -f "$BUILD_LOG"
  stale_ledger_note
  exit 3
fi
rm -f "$BUILD_LOG"

TOOL="$ROOT/app/.build/debug/MeasureDump"
if [ ! -x "$TOOL" ]; then
  echo "INCONCLUSIVE mock-fidelity: $TOOL is missing after a build that reported success"
  stale_ledger_note
  exit 3
fi

mkdir -p "$DUMPS"

# The instrument's own preflight, before it is trusted to measure anything.
#
# `MeasureDump` used to default an unreadable `--state` back to `ideal`, so a typo wrote the ideal
# frame into `servers.<typo>.json` and exited 0 — a measurement of a surface nobody asked for,
# reported as a success. It now refuses. Asserted here on every run rather than recorded once,
# because a tool that quietly resumed defaulting would make every dump below suspect and nothing
# would say so. Costs one process launch against a build that has already happened.
PREFLIGHT_OUT=$(mktemp)
"$TOOL" --state definitely-not-a-state --out "$DUMPS/.preflight.json" > "$PREFLIGHT_OUT" 2>&1
preflight=$?
if [ $preflight != 3 ] || [ -f "$DUMPS/.preflight.json" ]; then
  echo "INCONCLUSIVE mock-fidelity: MeasureDump was handed an unreadable --state and exited"
  echo "              $preflight rather than 3. It is defaulting instead of refusing, so a dump"
  echo "              named for one state may hold another and nothing downstream can tell. It said:"
  sed 's/^/              /' "$PREFLIGHT_OUT"
  rm -f "$PREFLIGHT_OUT" "$DUMPS/.preflight.json"
  stale_ledger_note
  exit 3
fi
rm -f "$PREFLIGHT_OUT"

for state in $STATES; do
  out="$DUMPS/${SURFACE}.${state}.json"
  rm -f "$out"
  # macOS has no timeout(1). A harness that hangs must not read as one that measured nothing.
  if ! perl -e 'alarm shift @ARGV; exec @ARGV' 180 \
       "$TOOL" --surface "$SURFACE" --state "$state" --settle "$SETTLE" --out "$out"; then
    echo "INCONCLUSIVE mock-fidelity: MeasureDump could not render '$SURFACE.$state'"
    stale_ledger_note
    exit 3
  fi
done

# "ledger written to …" used to be printed unconditionally, one line after a run that had exited 1
# without ever reaching `write_report` — so the sentence naming the artifact was the thing that made
# a stale table look like this run's.
#
# It is now the engine's own claim rather than this script's inference. An mtime is not an ownership
# token: a stale ledger carrying a future timestamp is already newer than any stamp taken here, and
# a concurrent run writing the same path satisfies the same test (`gpt-5.6-sol`). So the engine
# prints REPORT_MARKER after a write that returned, through its `emit`, and this reads that. If both
# of the engine's streams are gone the marker is lost and this under-claims, which is the direction
# that cannot turn an earlier run's table into this one's.
ENGINE_LOG=$(mktemp)
python3 scripts/acceptance/mock_fidelity.py "$MANIFEST" "$DUMPS" --report "$LEDGER" 2>&1 | tee "$ENGINE_LOG"
status=${PIPESTATUS[0]}
if grep -qF "mock-fidelity: report written to $LEDGER" "$ENGINE_LOG"; then
  echo "mock-fidelity-gate: ledger written to $LEDGER"
elif [ -f "$LEDGER" ]; then
  echo "mock-fidelity-gate: NO ledger was written by this run (exit $status). The table at $LEDGER"
  echo "                    is an earlier run's and does not describe this one."
else
  echo "mock-fidelity-gate: no ledger was written by this run (exit $status), and there is no"
  echo "                    file at $LEDGER."
fi
rm -f "$ENGINE_LOG"
exit $status
