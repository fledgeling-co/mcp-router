#!/usr/bin/env bash
#
# R33 — the presence control for `planning/carrier-parity-gate.py` and
# `scripts/acceptance/carrier-census.sh`.
#
# The gate asserts an ABSENCE: no one-sided landing in the window lacks a disposition. A check that
# CANNOT fire and a check that correctly does not fire produce the same green run, which is the
# failure `sweep-control-gate.py` exists for. So every finding class is planted here and required to
# appear, and the clean tree is required to stay clean.
#
# EVERY ARM RUNS AGAINST A COPY. `CARRIER_LEDGER` points the gate at a doctored ledger under a
# scratch directory; the tracked one is never written, and the last arm diffs it to prove that.
#
# Exit codes: 0 every arm behaved, 1 an arm did not, 2 the environment could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$REPO_ROOT/planning/carrier-parity-gate.py"
LEDGER="$REPO_ROOT/planning/parity/carriers.tsv"
WORK="$(mktemp -d -t carrier-parity-selftest)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$GATE" ]   || { echo "environment: no gate at $GATE" >&2; exit 2; }
[ -f "$LEDGER" ] || { echo "environment: no ledger at $LEDGER" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "environment: python3 is not installed" >&2; exit 2; }

before="$(shasum "$LEDGER" | awk '{print $1}')"
arms=0
bad=0

# arm <name> <ledger> <expected-exit> <expected-substring>
arm() {
  local name="$1" ledger="$2" want_exit="$3" want_text="$4" out code
  arms=$((arms + 1))
  out="$(CARRIER_LEDGER="$ledger" python3 "$GATE" 2>&1)"
  code=$?
  if [ "$code" != "$want_exit" ]; then
    printf '  FAIL  %-22s exit %s, wanted %s\n' "$name" "$code" "$want_exit"
    bad=$((bad + 1)); return
  fi
  if ! printf '%s' "$out" | grep -q -- "$want_text"; then
    printf '  FAIL  %-22s exit %s as wanted, but said nothing matching %s\n' "$name" "$code" "$want_text"
    bad=$((bad + 1)); return
  fi
  printf '  ok    %-22s exit %s, %s\n' "$name" "$code" "$want_text"
}

victim="$(awk -F'\t' '!/^#/ && NF == 5 { print $1; exit }' "$LEDGER")"
[ -n "$victim" ] || { echo "environment: the ledger holds no parsable row to arm with" >&2; exit 2; }

# 1. The clean case. Without this every other arm is satisfied by a gate that reddens on anything.
cp "$LEDGER" "$WORK/clean.tsv"
arm clean "$WORK/clean.tsv" 0 "0 findings"

# 2. A one-sided landing whose row is gone must be named, not passed over.
grep -v "^$victim" "$LEDGER" > "$WORK/dropped.tsv"
arm dropped-row "$WORK/dropped.tsv" 1 "UNDISPOSITIONED"

# 3. A carrier that disagrees with the diff must be a finding rather than a record.
awk -F'\t' -v v="$victim" 'BEGIN { OFS = "\t" }
  $1 == v { $3 = ($3 == "swift-only") ? "typescript-only" : "swift-only" } { print }' \
  "$LEDGER" > "$WORK/flipped.tsv"
arm flipped-carrier "$WORK/flipped.tsv" 1 "DISAGREES"

# 4. A row with no reason records nothing, and must not pass for a disposition.
awk -F'\t' -v v="$victim" 'BEGIN { OFS = "\t" } $1 == v { $5 = "" } { print }' \
  "$LEDGER" > "$WORK/no-note.tsv"
arm empty-note "$WORK/no-note.tsv" 1 "no note"

# 5. A disposition outside the vocabulary is not a disposition.
awk -F'\t' -v v="$victim" 'BEGIN { OFS = "\t" } $1 == v { $4 = "probably-fine" } { print }' \
  "$LEDGER" > "$WORK/bad-word.tsv"
arm unknown-disposition "$WORK/bad-word.tsv" 1 "is not one of"

# 6. No pin means no window, and every landing would pass for want of an obligation. That is an
#    environment failure and not a clean run.
grep -v "^# since:" "$LEDGER" > "$WORK/no-pin.tsv"
arm no-pin "$WORK/no-pin.tsv" 2 "carries no"

# 7. A row for a landing that touched neither router is stale rather than harmless.
{ cat "$LEDGER"; printf '%s\tphantom\tswift-only\tported\tinvented for the selftest\n' \
  "$(printf '0%.0s' $(seq 1 40))"; } > "$WORK/stale.tsv"
arm stale-row "$WORK/stale.tsv" 1 "STALE"

# 8. A malformed row must be named by line, because a reader selecting on field count would
#    otherwise leave it in the file and out of the count.
{ cat "$LEDGER"; printf 'not\ta\trow\n'; } > "$WORK/malformed.tsv"
arm malformed-row "$WORK/malformed.tsv" 1 "MALFORMED"

after="$(shasum "$LEDGER" | awk '{print $1}')"
if [ "$before" != "$after" ]; then
  echo "  FAIL  the tracked ledger changed during this run. A control that edits its subject proves"
  echo "        nothing about the subject."
  bad=$((bad + 1))
fi

echo
if [ "$bad" -ne 0 ]; then
  echo "carrier-parity-selftest: $bad of $arms arm(s) did not behave. The gate above is not armed."
  exit 1
fi
echo "carrier-parity-selftest: $arms arms, all as declared, and the tracked ledger is byte-identical."
exit 0
