#!/usr/bin/env bash
#
# R33 — the green streak, measured.
#
# `R4-C2` (retiring `src/*.ts`) is held because the repository is "not on a green streak", and
# `R4-C1` asks for "a number of consecutive whole gates including the cold port-reuse path".
# `planning/parity/green-streak.md` defines what a whole-gate pass is, what the cold port-reuse
# path is, and why the bound is the owner's. This script reads the ledger and counts.
#
# Two modes, and they are separate on purpose:
#
#   green-streak.sh                 READS. Counts the current streak and reports it. Writes nothing.
#   green-streak.sh --record <log>  APPENDS one row, parsed out of a captured parity-gate.sh run.
#
# A gate that records as a side effect of checking is a gate that can make its own subject true, so
# the reading mode never touches the ledger. That is this repo's own rule and the reason it exists.
#
# Exit codes:
#   0  the streak was measured and reported
#   1  the ledger contradicts itself — a row that cannot be parsed, or a pass verdict that its own
#      figures refuse
#   2  nothing to measure. No ledger, or no run recorded in it. A count over an empty sequence is
#      not a streak of zero that anybody should act on, it is an unrun instrument
#
# THE BOUND IS NOT ENFORCED HERE AND THAT IS DELIBERATE. While `# bound:` reads `unset`, this
# reports the streak and says `R4-C2` stays held. It never reads a long streak as a met condition:
# `R4-C1` requires the number to be stated BEFORE the runs it is judged on, and a script that
# picked one afterwards would be choosing the formulation under which the answer comes out green.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LEDGER="${GREEN_STREAK_LEDGER:-$REPO_ROOT/planning/parity/green-streak.tsv}"
GATE="$REPO_ROOT/scripts/acceptance/parity-gate.sh"

[ -f "$LEDGER" ] || { echo "environment: no ledger at $LEDGER" >&2; exit 2; }

# The target is a DECISION and lives in one place. Read it; never restate it.
target="$(sed -n 's/^PARITY_CUTOVER_TARGET=\([0-9]*\).*/\1/p' "$GATE" | head -1)"
if [ -z "$target" ]; then
  echo "environment: PARITY_CUTOVER_TARGET could not be extracted from ${GATE#"$REPO_ROOT/"}." >&2
  echo "             Every pass verdict below is arithmetic on it, so none is computed. This is a" >&2
  echo "             stale anchor, not an absent target." >&2
  exit 2
fi

bound="$(sed -n 's/^#[[:space:]]*bound:[[:space:]]*\(.*\)$/\1/p' "$LEDGER" | head -1)"
[ -z "$bound" ] && bound=unset

# ---------------------------------------------------------------------------------------------
# --record. Parses the four figures out of a captured run rather than taking them on report.
if [ "${1:-}" = "--record" ]; then
  log="${2:-}"
  [ -n "$log" ] && [ -f "$log" ] || { echo "usage: green-streak.sh --record <captured-log> [kind]" >&2; exit 2; }
  kind="${3:-whole-gate}"
  case "$kind" in whole-gate|cold-port-reuse) ;; *) echo "kind is whole-gate or cold-port-reuse" >&2; exit 2 ;; esac
  code="${GREEN_STREAK_EXIT:-}"
  [ -n "$code" ] || { echo "set GREEN_STREAK_EXIT to the exit code the run actually took" >&2; exit 2; }

  # The gate prints `parity: N of M rows proven`, and the blocked/excluded/diverged lines each have
  # their own sentence. A figure this reader cannot find is recorded as `?` rather than as 0: a
  # missing number and a zero are opposite facts, and a run that printed neither is a run whose
  # verdict nobody should compute.
  proven="$(sed -n 's/^parity: \([0-9]*\) of [0-9]* rows proven.*/\1/p' "$log" | head -1)"
  total="$(sed -n 's/^parity: [0-9]* of \([0-9]*\) rows proven.*/\1/p' "$log" | head -1)"
  blocked_total="$(sed -n 's/^parity: [0-9]* of [0-9]* rows proven.*, \([0-9][0-9]*\) blocked\..*/\1/p' "$log" | head -1)"
  # The exclusions block prints only when `excluded > 0`, so its ABSENCE is the observation that
  # there were none. That is derivable and is recorded as 0. `blocked` and `proven` are not: the
  # gate withholds them on a run it could not measure, and a withheld figure recorded as 0 is a
  # run that reported nothing being read as a run that reported a clean nothing.
  excluded="$(sed -n 's/^ *\([0-9][0-9]*\) of the [0-9][0-9]* blocked rows.*/\1/p' "$log" | head -1)"
  grep -q 'STANDING EXCLUSION' "$log" || excluded=0
  diverged="$(sed -n 's/^parity: \([0-9]*\) of [0-9]* rows DIVERGED.*/\1/p' "$log" | head -1)"
  [ -z "$proven" ] && proven='?'
  [ -z "$total" ] && total='?'
  [ -z "$blocked_total" ] && blocked_total='?'
  [ -z "$excluded" ] && excluded='?'
  [ -z "$diverged" ] && diverged=0

  started="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  tree="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  rel="${log#"$REPO_ROOT/"}"
  [ "$rel" = "$log" ] && rel='-'
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$started" "$tree" "$kind" "$code" "$proven" "$total" "$blocked_total" "$excluded" "$diverged" "$rel" \
    >> "$LEDGER"
  echo "recorded: $started $kind exit=$code proven=$proven/$total blocked=$blocked_total excluded=$excluded diverged=$diverged"
  exit 0
fi

# ---------------------------------------------------------------------------------------------
# The reading mode.
rows="$(awk -F'\t' '!/^#/ && NF == 10' "$LEDGER")"
malformed="$(awk -F'\t' '!/^#/ && NF != 10 && NF > 0' "$LEDGER" | wc -l | tr -d ' ')"

if [ "$malformed" -ne 0 ]; then
  echo "the ledger holds $malformed row(s) that are not ten fields. Every reader here selects on"
  echo "NF == 10, so such a row is invisible to the count while sitting in the file — which is the"
  echo "one thing a streak ledger must never do. Exit 1."
  exit 1
fi

count="$(printf '%s\n' "$rows" | grep -c . || true)"
echo "green streak — R4-C2's hold, measured rather than asserted"
echo
echo "  ledger        ${LEDGER#"$REPO_ROOT/"}"
echo "  bound         $bound"
echo "  target        $target (PARITY_CUTOVER_TARGET, a decision — see green-streak.md)"
echo "  runs recorded $count"
echo

if [ "$count" -eq 0 ]; then
  echo "  No whole-gate run has been recorded, so there is no sequence to count over and the"
  echo "  streak is not zero — it is unmeasured. Those are different claims and only one of them"
  echo "  is true today."
  echo
  echo "  To record one:"
  echo "    bash scripts/acceptance/parity-gate.sh > /tmp/parity.log 2>&1; ec=\$?"
  echo "    GREEN_STREAK_EXIT=\$ec bash scripts/acceptance/green-streak.sh --record /tmp/parity.log"
  echo
  echo "  R4-C2 stays held. Nothing here moves it. Exit 2."
  exit 2
fi

# Count back from the newest. The first non-pass ends it.
streak=0
cold=0
verdicts=""
ended=0
while IFS=$'\t' read -r started tree kind code proven total blocked excluded diverged log; do
  [ -z "${started:-}" ] && continue
  verdict=pass
  why=""
  case "$proven$total$blocked$excluded" in *'?'*) verdict=UNVERDICTABLE; why="a figure the recorder could not find" ;; esac
  if [ "$verdict" = pass ]; then
    [ "$code" = 2 ] && { verdict=fail; why="exit 2 — a lane could not run, and a skipped lane is not a pass"; }
  fi
  if [ "$verdict" = pass ] && [ "$diverged" != 0 ]; then
    verdict=fail; why="$diverged row(s) DIVERGED"
  fi
  if [ "$verdict" = pass ] && [ "$blocked" != "$excluded" ]; then
    verdict=fail; why="$blocked blocked, of which $excluded standing — the rest is not a pass"
  fi
  if [ "$verdict" = pass ] && [ "$proven" -lt "$target" ] 2>/dev/null; then
    verdict=fail; why="$proven proven is short of the target $target"
  fi
  verdicts="$verdicts$(printf '%s\t%s\t%s\t%s\t%s\n' "$started" "$kind" "$code" "$verdict" "$why")
"
  if [ "$ended" -eq 0 ]; then
    if [ "$verdict" = pass ]; then
      streak=$((streak + 1))
      [ "$kind" = cold-port-reuse ] && cold=$((cold + 1))
    else
      ended=1
    fi
  fi
done < <(printf '%s\n' "$rows" | sort -r)

echo "  runs, newest first:"
printf '%s' "$verdicts" | while IFS=$'\t' read -r started kind code verdict why; do
  [ -z "${started:-}" ] && continue
  printf '    %-21s %-16s exit=%-2s %-14s %s\n' "$started" "$kind" "$code" "$verdict" "$why"
done
echo
echo "  current streak: $streak consecutive whole-gate pass(es), $cold of them cold port-reuse."
echo

if [ "$bound" = unset ]; then
  echo "  NO BOUND HAS BEEN DECIDED, so this is a measurement and not a verdict. R4-C1 requires the"
  echo "  number to be stated before the runs it is judged on, so a script choosing one now would"
  echo "  be picking the formulation that makes the answer green. R4-C2 stays held."
  exit 0
fi

echo "  bound is $bound. This script still reports rather than decides: flipping the installer and"
echo "  deleting src/*.ts is REQ-020, and REQ-020 makes it the owner's."
exit 0
