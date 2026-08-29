#!/usr/bin/env bash
#
# R33 — the presence control for `scripts/acceptance/green-streak.sh`.
#
# The streak reader's whole job is to refuse a pass, so every clause of the pass predicate in
# `planning/parity/green-streak.md` is planted here and required to end a streak. Without that, a
# reader that called everything a pass and a reader that read the clauses correctly would both
# report the same number on the ledger as it stands today, which holds no runs at all.
#
# Two of the arms are the recorder rather than the reader, and they matter for a different reason:
# the recorder's regexes are aimed at `parity-gate.sh`'s own output, and a regex that has drifted
# off that format records `?` for every figure while exiting 0. So one arm feeds it the gate's real
# summary shape and requires the four figures back, and one feeds it a run that WITHHELD coverage
# and requires `?` rather than a helpful zero — a withheld figure recorded as 0 is a run that
# measured nothing read as a run that measured a clean nothing.
#
# EVERY ARM RUNS AGAINST A COPY, through `GREEN_STREAK_LEDGER`. The tracked ledger is never written
# and the last check diffs it to prove that.
#
# Exit codes: 0 every arm behaved, 1 an arm did not, 2 the environment could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
READER="$REPO_ROOT/scripts/acceptance/green-streak.sh"
LEDGER="$REPO_ROOT/planning/parity/green-streak.tsv"
WORK="$(mktemp -d -t green-streak-selftest)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$READER" ] || { echo "environment: no reader at $READER" >&2; exit 2; }
[ -f "$LEDGER" ] || { echo "environment: no ledger at $LEDGER" >&2; exit 2; }

# The target is read from the gate by the reader under test, so the fixtures are built around
# whatever it says rather than around 82. A fixture pinned to a number the gate no longer holds
# would arm the wrong predicate.
target="$(sed -n 's/^PARITY_CUTOVER_TARGET=\([0-9]*\).*/\1/p' "$REPO_ROOT/scripts/acceptance/parity-gate.sh" | head -1)"
[ -n "$target" ] || { echo "environment: PARITY_CUTOVER_TARGET is not extractable" >&2; exit 2; }
short=$((target - 1))

before="$(shasum "$LEDGER" | awk '{print $1}')"
tree="$(git -C "$REPO_ROOT" rev-parse HEAD)"
arms=0
bad=0

row() { # started kind exit proven total blocked excluded diverged
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t-\n' \
    "$1" "$tree" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
}
PASS_A="$(row 2026-01-01T01:00:00Z whole-gate 1 "$target" 105 1 1 0)"
PASS_B="$(row 2026-01-01T02:00:00Z cold-port-reuse 1 "$target" 105 1 1 0)"

ledger() { # name, then rows on stdin
  { echo '# bound: unset'; cat; } > "$WORK/$1.tsv"
  printf '%s' "$WORK/$1.tsv"
}

arm() { # name ledger expected-exit expected-substring
  local name="$1" file="$2" want_exit="$3" want_text="$4" out code
  arms=$((arms + 1))
  out="$(GREEN_STREAK_LEDGER="$file" bash "$READER" 2>&1)"
  code=$?
  if [ "$code" != "$want_exit" ]; then
    printf '  FAIL  %-22s exit %s, wanted %s\n' "$name" "$code" "$want_exit"; bad=$((bad + 1)); return
  fi
  if ! printf '%s' "$out" | grep -q -- "$want_text"; then
    printf '  FAIL  %-22s exit %s as wanted, but said nothing matching: %s\n' "$name" "$code" "$want_text"
    printf '%s\n' "$out" | sed 's/^/          /'
    bad=$((bad + 1)); return
  fi
  printf '  ok    %-22s exit %s, %s\n' "$name" "$code" "$want_text"
}

# 1. An empty ledger is unmeasured, not a streak of zero, and it must not read as a pass.
arm empty "$(printf '' | ledger empty)" 2 "streak is not zero"

# 2. Two passes are two, and the cold port-reuse one is counted as such rather than blended in.
arm two-passes "$(printf '%s\n%s\n' "$PASS_A" "$PASS_B" | ledger pass)" 0 \
  "current streak: 2 consecutive whole-gate pass(es), 1 of them cold port-reuse"

# 3-6. Each clause of the predicate, planted as the NEWEST run, must end the streak at 0.
arm diverged "$(printf '%s\n%s\n%s\n' "$PASS_A" "$PASS_B" \
  "$(row 2026-01-01T03:00:00Z whole-gate 1 "$target" 105 1 1 1)" | ledger diverged)" 0 \
  "current streak: 0"
arm exit-2 "$(printf '%s\n%s\n%s\n' "$PASS_A" "$PASS_B" \
  "$(row 2026-01-01T03:00:00Z whole-gate 2 '?' '?' '?' '?' 0)" | ledger exit2)" 0 \
  "current streak: 0"
arm extra-blocked "$(printf '%s\n%s\n%s\n' "$PASS_A" "$PASS_B" \
  "$(row 2026-01-01T03:00:00Z whole-gate 1 "$target" 105 4 1 0)" | ledger blocked)" 0 \
  "the rest is not a pass"
arm short-of-target "$(printf '%s\n%s\n%s\n' "$PASS_A" "$PASS_B" \
  "$(row 2026-01-01T03:00:00Z whole-gate 1 "$short" 105 1 1 0)" | ledger short)" 0 \
  "short of the target $target"

# 7. A failure BELOW the newest pass must not end the streak — "consecutive" counts back from the
#    newest, and a reader that scanned the whole file for any red would report 0 here.
arm older-failure "$(printf '%s\n%s\n%s\n' \
  "$(row 2026-01-01T00:30:00Z whole-gate 1 "$short" 105 1 1 0)" "$PASS_A" "$PASS_B" | ledger older)" 0 \
  "current streak: 2"

# 8. A row that is not ten fields is invisible to every reader here, which is the one thing a
#    streak ledger must never allow.
arm malformed "$(printf 'a\tb\tc\n' | ledger malformed)" 1 "not ten fields"

# ---------------------------------------------------------------------------------------------
# The recorder, against parity-gate.sh's own summary shape.
cat > "$WORK/measured.log" <<'LOG'
parity gate — 2026-01-01T00:00:00Z

  1 of the 1 blocked rows is a STANDING EXCLUSION, not work — nobody is
  assigned to it and nobody is waiting on it:
    fixture     fixture-registry-search  blocked

parity: 104 of 105 rows proven (12 of them by suite only, not by wire comparison), 1 blocked. This is NOT a pass.
LOG
printf 'parity gate — 2026-01-01T00:00:00Z\n\nparity: COVERAGE IS NOT REPORTED for this run.\n' > "$WORK/withheld.log"

record_arm() { # name log exit expected-substring
  local name="$1" log="$2" code="$3" want="$4" out
  arms=$((arms + 1))
  printf '# bound: unset\n' > "$WORK/rec-$name.tsv"
  out="$(GREEN_STREAK_EXIT="$code" GREEN_STREAK_LEDGER="$WORK/rec-$name.tsv" \
         bash "$READER" --record "$log" 2>&1)"
  if printf '%s' "$out" | grep -q -- "$want"; then
    printf '  ok    %-22s %s\n' "$name" "$want"
  else
    printf '  FAIL  %-22s wanted %s, got: %s\n' "$name" "$want" "$out"; bad=$((bad + 1))
  fi
}
record_arm record-measured "$WORK/measured.log" 1 "proven=104/105 blocked=1 excluded=1 diverged=0"
record_arm record-withheld "$WORK/withheld.log" 2 "proven=?/? blocked=? excluded=0 diverged=0"

after="$(shasum "$LEDGER" | awk '{print $1}')"
if [ "$before" != "$after" ]; then
  echo "  FAIL  the tracked ledger changed during this run. Recording is a mode, not a side effect."
  bad=$((bad + 1))
fi

echo
if [ "$bad" -ne 0 ]; then
  echo "green-streak-selftest: $bad of $arms arm(s) did not behave. The reader above is not armed."
  exit 1
fi
echo "green-streak-selftest: $arms arms, all as declared, and the tracked ledger is byte-identical."
exit 0
