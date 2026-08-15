#!/usr/bin/env bash
#
# R4 — the parity gate.
#
# One entry point. It runs every lane, reconciles what they reported against the enumerated
# surface in planning/parity/surface.tsv, and prints coverage as a fraction of that surface.
#
# The fraction is the point. "The differential passed" is a sentence this repo can no longer
# print, because it was true of a 32-row subset of a 74-row surface and would have been read as
# "the routers are equivalent". A gate that reports what it happens to cover converts an unknown
# into a false certainty, and a cutover then gets justified by it.
#
# Three traps, each guarded, because each one turns a broken run into a green one:
#
#   1. A lane that fails to start must not shrink the denominator. Reconciliation is against the
#      MANIFEST, never against the set of rows the lanes happened to report. A manifest row with
#      no result is blocked — never absent, never quietly dropped.
#   2. `set -euo pipefail` with a lane in a pipeline reports the status of the last command in the
#      pipe. Lanes run unpiped, with their status captured explicitly on the next line.
#   3. A lane that exits 0 having printed nothing did not run. A lane that produces no result rows
#      is recorded as an environment failure, not as a lane with nothing to say.
#
# Exit codes:
#   0  every row proven. Not reachable today, and the report says why.
#   1  a row is blocked, or a lane reported a mismatch.
#   2  the environment could not run a lane. Distinct because a skipped lane is not a pass.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="${PARITY_MANIFEST:-$REPO_ROOT/planning/parity/surface.tsv}"
# A lane that is not NAMED here is not run, and nothing says so. The missing-script guard below
# only fires for a lane the gate was asked about, so a lane script that exists and is never
# listed produces no results, no environment failure and no complaint — its rows simply stay
# blocked under whatever note they carry. `stream` sat on disk in exactly that state from R2-R
# until P3: written, executable, passing when run by hand, and dispatched by nothing.
LANES="${PARITY_LANES:-control fixture divergence pool suite mcp cli install state log stream registry}"
WORK="$(mktemp -d -t parity-gate)"
RESULTS="$WORK/results.tsv"
: > "$RESULTS"

env_failed=0
declare -a env_reasons=()

# D-g1-g. Sourced before the trap is installed, so `cleanup` can never name a function that does
# not exist yet, and acquired before the manifest check and before any lane binds anything — so a
# refused run prints its refusal and nothing that could be read as a result.
# `parity_lock_acquire` exits 2 itself when the harness is busy; it never returns having failed.
. "$REPO_ROOT/scripts/acceptance/parity-lock.sh"

cleanup() { parity_lock_release; rm -rf "$WORK"; }
trap cleanup EXIT INT TERM HUP

parity_lock_acquire "parity-gate.sh"

# ---------------------------------------------------------------------------------------------
# The manifest is checked FIRST. Every number below it is computed from this file, so a manifest
# that has drifted from the source invalidates the coverage fraction rather than merely being
# untidy — and a drifted manifest reports a HIGHER pass rate, never a lower one.
echo "parity gate — $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo
bash "$REPO_ROOT/scripts/acceptance/parity-manifest-check.sh"
manifest_status=$?
if [ "$manifest_status" = 2 ]; then
  echo
  echo "the manifest could not be checked — the reason is printed above. There is no surface to"
  echo "report against, so no coverage is computed."
  exit 2
fi
if [ "$manifest_status" != 0 ]; then
  echo
  echo "the manifest disagrees with the source. Coverage is not computed from a stale census."
  exit 1
fi
echo

# ---------------------------------------------------------------------------------------------
# One notice for one environment fact, said before the lanes rather than twenty-two times during
# and after them.
#
# In a fresh worktree the reference is unbuilt, and the gate DOES run: it walks the whole manifest,
# classifies every affected row blocked, exits 2 and names the remedy. That behaviour is correct
# and is not changed here. What it also did was print "run npm run build" TWENTY-TWO times — once
# per lane as it failed and once per lane again in the summary — so the one thing the reader needs
# to do arrived buried in its own repetition, and only after the whole walk.
#
# This is a notice and nothing else. No lane is skipped, no verdict is altered, and nothing that
# computes coverage is touched: the lanes keep their own messages, their own exit 2 and their own
# blocked rows.
if [ ! -f "${MCP_ROUTER_DIST:-$REPO_ROOT/dist/index.js}" ]; then
  echo "notice: the TypeScript reference is not built, so every lane that compares against it will"
  echo "        report an environment failure below and its rows will stay blocked."
  echo "        Run 'npm install && npm run build' first. The gate still runs, and still exits 2."
  echo
fi

# ---------------------------------------------------------------------------------------------
# Lanes. Each writes `group<TAB>id<TAB>ok|fail<TAB>detail` rows to $RESULTS via PARITY_RESULTS.
# A lane's own exit status is captured on the line after it runs — never through a pipe.
lane_count="$(printf '%s\n' $LANES | wc -w | tr -d ' ')"
lane_index=0
for lane in $LANES; do
  lane_index=$((lane_index + 1))
  script="$REPO_ROOT/scripts/acceptance/parity-$lane.sh"
  echo "running $lane ($lane_index of $lane_count lanes)"

  if [ ! -f "$script" ]; then
    env_failed=1
    env_reasons+=("$lane — no lane script at ${script#"$REPO_ROOT/"}")
    echo "  the lane script is missing. Its rows stay blocked."
    continue
  fi

  before="$(wc -l < "$RESULTS" | tr -d ' ')"
  PARITY_RESULTS="$RESULTS" bash "$script" > "$WORK/$lane.log" 2>&1
  status=$?
  after="$(wc -l < "$RESULTS" | tr -d ' ')"
  produced=$((after - before))

  case "$status" in
    0) echo "  $lane: $produced result rows" ;;
    2) env_failed=1
       env_reasons+=("$lane — $(tail -3 "$WORK/$lane.log" | tr '\n' ' ')")
       echo "  $lane could not run. Its rows stay blocked, which is not a pass." ;;
    *) echo "  $lane reported mismatches — $produced result rows" ;;
  esac

  # A lane that exits 0 having recorded nothing has not run, whatever its status says.
  if [ "$status" = 0 ] && [ "$produced" = 0 ]; then
    env_failed=1
    env_reasons+=("$lane — exited 0 and produced no result rows, so it did not run")
    echo "  $lane exited 0 without recording a single row. Treated as not run."
  fi

  cat "$WORK/$lane.log" | sed 's/^/    /'
done
echo

# ---------------------------------------------------------------------------------------------
# Reconciliation. Driven by the manifest, one row at a time. A manifest row that no lane spoke
# for is blocked with a reason that names the silence — the alternative is a row that disappears
# from both the numerator and the denominator, which is the failure this gate exists to prevent.
proven=0; blocked=0; mismatched=0; total=0
: > "$WORK/blocked.txt"
: > "$WORK/mismatch.txt"
: > "$WORK/bygroup.txt"

while IFS=$'\t' read -r group id subject verdict owner note; do
  case "$group" in ''|'#'*) continue ;; esac
  # `read` assigns every named variable even on a short line, so testing whether `note` is SET
  # never fails. A five-field row would have been counted with an empty verdict and fallen through
  # to the results lookup. The verdict is what has to be present, and it has to be one this gate
  # knows — an unrecognised verdict is a row nobody can score, not a row to wave through.
  case "$verdict" in
    proven|proven-by-suite|blocked) ;;
    *) echo "manifest row \"$id\" has verdict \"$verdict\", which this gate cannot score." >&2
       total=$((total + 1)); blocked=$((blocked + 1))
       printf '%s\t%s\n' "$group" "blocked" >> "$WORK/bygroup.txt"
       printf '%s\t%s\t%s\t%s\n' "(unscoreable)" "$group" "$subject" \
         "verdict \"$verdict\" is not one this gate recognises" >> "$WORK/blocked.txt"
       continue ;;
  esac
  total=$((total + 1))

  if [ "$verdict" = "blocked" ]; then
    blocked=$((blocked + 1))
    printf '%s\t%s\n' "$group" "blocked" >> "$WORK/bygroup.txt"
    printf '%s\t%s\t%s\t%s\n' "$owner" "$group" "$subject" "$note" >> "$WORK/blocked.txt"

    # A blocked row still gets its results read, for one reason: a row blocked because of a KNOWN
    # DEFECT carries an assertion that the defect is still exactly what was recorded. If that
    # assertion goes stale — the defect was fixed, or either side moved — the record has outlived
    # its reason and must not sit quietly in the blocked list forever. Skipping the lookup here
    # was a real hole: a blocked row is blocked whether or not its reason is still true.
    stale="$(awk -F'\t' -v id="$id" '$2 == id && $4 ~ /^stale/ { print $4 }' "$RESULTS" | head -1)"
    if [ -n "$stale" ]; then
      mismatched=$((mismatched + 1))
      printf '%s\t%s\t%s\n' "$group" "$subject" "$stale" >> "$WORK/mismatch.txt"
    fi
    continue
  fi

  # proven-by-suite carries no WIRE result, but it does carry a citation, and the suite lane runs
  # it. It used to be counted here unconditionally on the strength of the manifest check having
  # found a function of that name somewhere in app/Tests — so a cited test that failed, or that
  # asserted something else, still proved its row. It now reconciles like any other row; only the
  # label under which it is counted differs.
  suite_marker="proven"
  [ "$verdict" = "proven-by-suite" ] && suite_marker="by-suite"

  # Matched on GROUP and id, not id alone. Without the group, any lane can write a result for any
  # row anywhere in the manifest and nothing notices — authorship goes unchecked, and a lane can
  # satisfy the did-it-run guard with rows for ids it never tested.
  results="$(awk -F'\t' -v g="$group" -v id="$id" '$1 == g && $2 == id { print $3 }' "$RESULTS")"
  if [ -z "$results" ]; then
    blocked=$((blocked + 1))
    printf '%s\t%s\n' "$group" "blocked" >> "$WORK/bygroup.txt"
    printf '%s\t%s\t%s\t%s\n' "(no lane reported)" "$group" "$subject" \
      "the manifest claims this is proven and no lane spoke for it" >> "$WORK/blocked.txt"
    continue
  fi
  # The token set is CLOSED. Only `ok` proves a row. Anything else — `fail`, `blocked` from a lane
  # that could only make a weaker claim, a typo — leaves the row unproven. Testing for `fail` alone
  # and treating every other token as success is how a lane's own weaker claim gets destroyed in
  # transit: `not_provable` records `blocked`, and the gate read it as proven.
  if printf '%s\n' "$results" | grep -qx fail; then
    mismatched=$((mismatched + 1))
    printf '%s\t%s\n' "$group" "mismatch" >> "$WORK/bygroup.txt"
    detail="$(awk -F'\t' -v id="$id" '$2 == id && $3 == "fail" { print $4 }' "$RESULTS" | head -3)"
    printf '%s\t%s\t%s\n' "$group" "$subject" "$detail" >> "$WORK/mismatch.txt"
    continue
  fi
  if ! printf '%s\n' "$results" | grep -qx ok; then
    blocked=$((blocked + 1))
    printf '%s\t%s\n' "$group" "blocked" >> "$WORK/bygroup.txt"
    printf '%s\t%s\t%s\t%s\n' "(lane claimed less)" "$group" "$subject" \
      "the lane reported \"$(printf '%s' "$results" | tr '\n' ' ')\", which is not a pass" \
      >> "$WORK/blocked.txt"
    continue
  fi
  proven=$((proven + 1))
  printf '%s\t%s\n' "$group" "$suite_marker" >> "$WORK/bygroup.txt"
done < "$MANIFEST"

# ---------------------------------------------------------------------------------------------
# The reconciliation above walks the MANIFEST, so it can only ever notice a row that is present.
# A row DELETED from the manifest is not blocked, not mismatched and not proven — it is simply not
# considered, and since the denominator is the manifest, deleting one raises the coverage fraction.
# Deleting a BLOCKED row raises it outright: the numerator does not move.
#
# `parity-manifest-check.sh` closes that for every group it can derive from a source file. It
# cannot derive `divergence`, `install`, `pool`, `state` or `log`, because those name declarations
# and scenarios rather than a surface some file exposes.
#
# This closes it for every row a LANE speaks for, with no list to maintain: the lanes already say
# which ids they tested, so a result whose id the manifest does not carry means the row was
# deleted while the work that proves it went on running. It is the same reconciliation, read in
# the other direction.
#
# It does not reach a blocked row, because no lane speaks for one. Four such rows are outside
# every check here — three `install` and one `divergence` — and that residue is recorded in
# planning/specs/spec-P4.md rather than implied.
orphans=0
: > "$WORK/orphans.txt"
while IFS=$'\t' read -r group id status detail; do
  [ -z "${id:-}" ] && continue
  awk -F'\t' -v g="$group" -v i="$id" \
    '$1 == g && $2 == i { found = 1 } END { exit !found }' "$MANIFEST" && continue
  orphans=$((orphans + 1))
  printf '%s\t%s\n' "$group" "$id" >> "$WORK/orphans.txt"
done < "$RESULTS"

if [ "$orphans" -gt 0 ]; then
  echo "───────────────────────────────────────────────────────────────────────"
  echo "a lane reported a result for a row this manifest does not carry:"
  sort -u "$WORK/orphans.txt" | while IFS=$'\t' read -r group id; do
    printf '  %-11s %s\n' "$group" "$id"
  done
  echo
  echo "The lane tested it, so the row existed when the lane was written. A row that leaves the"
  echo "manifest leaves the denominator, and the coverage fraction goes up. Exit 1."
  echo
fi

# ---------------------------------------------------------------------------------------------
# The report. DESIGN.md §5 states, with real copy on the unhappy paths — this output IS this
# item's user-facing surface, and a gate whose failure output is worse than its success output is
# a gate people learn to skim. §6 governs the words: no number that is not observed.
echo "───────────────────────────────────────────────────────────────────────"
if [ -s "$WORK/bygroup.txt" ]; then
  echo "coverage by group — these are not all the same claim:"
  awk -F'\t' '
    { seen[$1]++; state[$1"/"$2]++ }
    END {
      order = "control fixture divergence pool mcp cli install state log"
      n = split(order, groups, " ")
      for (i = 1; i <= n; i++) {
        g = groups[i]
        if (!(g in seen)) continue
        printf "  %-11s %2d of %2d proven", g, state[g"/proven"] + state[g"/by-suite"], seen[g]
        if (state[g"/by-suite"]) printf " (%d by suite only)", state[g"/by-suite"]
        if (state[g"/blocked"])  printf ", %d blocked", state[g"/blocked"]
        if (state[g"/mismatch"]) printf ", %d DIVERGED", state[g"/mismatch"]
        printf "\n"
      }
    }' "$WORK/bygroup.txt"
  echo
  echo "  control compares both routers on the wire. fixture compares the live reference against"
  echo "  its own recording — reference currency, not two-router parity. pool compares a live"
  echo "  reference measurement against a Swift real-process test, taken at different times."
  echo
fi

if [ "$total" = 0 ]; then
  echo "parity: the manifest enumerates no rows. An unrun gate is not a passing one."
  exit 2
fi

if [ "$mismatched" -gt 0 ]; then
  echo "parity: $mismatched of $total rows DIVERGED from the reference."
  echo
  while IFS=$'\t' read -r group subject detail; do
    printf '  %-11s %-42s %s\n' "$group" "$subject" "$detail"
  done < "$WORK/mismatch.txt"
  echo
fi

by_suite="$(awk -F'\t' '$2 == "by-suite"' "$WORK/bygroup.txt" | wc -l | tr -d ' ')"
suite_note=""
[ "$by_suite" -gt 0 ] && suite_note=" ($by_suite of them by suite only, not by wire comparison)"

# D-g1-g. A run that could not run a lane does not get to print a coverage fraction.
#
# The arithmetic below is unchanged and nothing here can raise a number: this branch only ever
# WITHHOLDS one. The reason it has to is that a fraction is the single thing a reader copies into a
# ledger, and `parity: 69 of 83` from a run whose lanes never started is indistinguishable, at a
# glance, from a real regression against a truth of 78. Both of those numbers are in this fleet's
# history and neither was a measurement. The lane failures are printed instead, because "this run
# did not happen" is the finding, and a smaller number is not a weaker version of it.
if [ "$env_failed" = 1 ]; then
  echo "parity: COVERAGE IS NOT REPORTED for this run."
  echo
  echo "A lane could not run, so the enumerated surface was not measured. A fraction computed now"
  echo "would count what happened to report and would read as a low score rather than as a run that"
  echo "did not take place. The lane that failed, and why, is at the bottom of this report."
  if [ "$blocked" -gt 0 ]; then
    echo
    echo "rows with no result, grouped by the item that would unblock them:"
    sort "$WORK/blocked.txt" | awk -F'\t' '
      $1 != last { printf "\n  %s\n", $1; last = $1 }
      { printf "    %-11s %-46s %s\n", $2, substr($3,1,46), substr($4,1,74) }'
  fi
  echo
elif [ "$blocked" -gt 0 ]; then
  echo "parity: $proven of $total rows proven$suite_note, $blocked blocked. This is NOT a pass."
  echo
  echo "blocked, grouped by the item that would unblock them:"
  sort "$WORK/blocked.txt" | awk -F'\t' '
    $1 != last { printf "\n  %s\n", $1; last = $1 }
    { printf "    %-11s %-46s %s\n", $2, substr($3,1,46), substr($4,1,74) }'
  echo
else
  echo "parity: $proven of $total rows proven$suite_note, 0 blocked."
fi

if [ "$env_failed" = 1 ]; then
  echo "───────────────────────────────────────────────────────────────────────"
  echo "a lane could not run. A skipped lane is recorded as blocked, never as a pass:"
  for reason in "${env_reasons[@]}"; do echo "  $reason"; done
  echo
  echo "those rows were not measured this run, and they are counted blocked rather than proven."
fi

# Precedence, stated rather than left to whichever check runs first: an undeclared DIVERGENCE is
# the louder finding and wins. A run that both lost a lane and found a real mismatch previously
# exited 2 and printed a reassuring line about coverage, burying the one result someone must act
# on. Both are non-zero; which non-zero it is decides what gets read first.
if [ "$mismatched" -gt 0 ]; then
  echo "A mismatch is a divergence from the reference that nothing declared. Exit 1."
  exit 1
fi

# Ranked directly below a divergence and above a lost lane. A row that has left the manifest is a
# claim quietly withdrawn, and unlike a lost lane it makes the number LOOK BETTER, so it must not
# be reported behind a line about an incomplete run.
if [ "$orphans" -gt 0 ]; then
  echo "$orphans row(s) were tested by a lane and are not in the manifest. Exit 1."
  exit 1
fi

if [ "$env_failed" = 1 ]; then
  echo "No divergence was found, but the run is incomplete. Exit 2, distinctly, because a"
  echo "skipped lane is not a pass."
  exit 2
fi

if [ "$blocked" -gt 0 ]; then
  echo "The cutover requires $total of $total. It has $proven."
  echo "Flipping the installer on this evidence is the one outcome this gate exists to prevent."
  exit 1
fi

echo "Every enumerated row is proven. The Swift router answers what the reference answers."
exit 0
