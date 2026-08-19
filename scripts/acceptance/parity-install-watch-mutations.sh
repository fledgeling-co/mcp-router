#!/usr/bin/env bash
#
# P8 — can `install-launchd-watch`'s two terms actually go red?
#
# This row has been marked `proven` once already, on a term that agreed sixteen consecutive times
# and measured the wrong thing. So the claim is not made on a series here. It is made on mutations,
# each aimed at ONE term, each run enough times to state a RATE rather than an anecdote — because
# the finding that withdrew the last promotion was a rate: 2 of 6 trials spuriously green, and a
# single trial would have shown either face of it.
#
# It runs `parity-install-watch.sh` — the lane's own observation code, sourced, not re-implemented.
# A harness with its own copy of the term proves that the copy can fail.
#
# THE ARMS. Every mutation is applied to the plist this lane generates or to the program it names;
# none is applied to the router. A test-only branch inside the product is a branch that can ship.
#
#   control   nothing mutated. The term must be able to go GREEN, or every red below is free. This
#             is also the arm that bounds how often the lane reddens a working pair.
#
#   decoy     WatchPaths rewritten to a .json in a fresh `mktemp -d` this lane never touches. A
#             genuine delivery is impossible, so `reran=no` is the only correct answer. This is the
#             exact mutation that withdrew the last promotion (D-p1-e), where it read 4 of 6 red.
#
#   blind     WatchPaths left alone; the agent's HOME moved to a second directory holding its own
#             unchanging `.claude.json`. launchd therefore DOES deliver — the watched file really is
#             being restaged — and the job really does re-run, so the counter really does move. What
#             the run cannot do is observe the staged change, because it reads a different file.
#             This arm is the whole of P8 in one trial: under the `runs`-only term it is green every
#             time and IS SCORED AS SUCH BELOW, and under the attributable term it must be red.
#
#   stamp-only  the decoy plist again, with half 2 of the fix REVERTED — the stimulus pinned back
#             to the agent's own `$HOME/.claude.json` rather than following the plist. This is P5's
#             lane with P8's stamp bolted on and nothing else, and it asks whether the stamp alone
#             would have been enough. Gated on nothing, because the answer is a rate and not a
#             verdict.
#
#             MEASURED 2026-08-20, and it did not answer the question: all six trials read
#             `runs=1->1`, so not one spurious increment occurred, where D-p1-e measured two in six
#             on the same configuration. The mechanism this arm needs in order to say anything did
#             not fire, so what it establishes is only that the spurious-spawn RATE is not stable
#             between sessions — which is itself the reason this row must not rest on "the decoy
#             usually goes red". Half 2's justification stays what the header calls it: structural,
#             not contingent on that rate.
#
#             It also reports `watched=self`, because the override moves the stimulus target and
#             `watched` names the target rather than the plist. Under this arm alone, that field
#             does not show the mutation.
#
#   resident  the Swift program replaced by `sh -c '<bin> watch; sleep 300'` — it writes its state
#             and then stays up. Aimed at `oneshot`, which P5 showed discriminates; re-run here so
#             that a fix to one term cannot be traded for the other without anyone noticing.
#
# BOTH TERMS ARE SCORED ON EVERY TRIAL. The `runs`-only term P8 replaces is derivable from the same
# observation (`runs=N->M` with M>N), so each trial reports what the old term would have said and
# what the new one does say. The delta is measured on the same evidence rather than argued.
#
# ONE SIDE ONLY. Mutations are applied to the Swift agent, as P5's were: the reference is the oracle
# and mutating it measures nothing about the router under test.
#
# COST. Roughly 40 minutes at the default trial counts, because every trial waits out a 10s
# ThrottleInterval, a 60s settling bound and a 90s restaging bound. `WATCH_MUTATION_TRIALS` and
# `WATCH_MUTATION_RESIDENT_TRIALS` set them; nothing below is timing-sensitive to their values.
#
# Exit codes: 0 every arm answered as it must, 1 an arm did not (which is the finding), 2 the
# environment could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
TRIALS="${WATCH_MUTATION_TRIALS:-6}"
RESIDENT_TRIALS="${WATCH_MUTATION_RESIDENT_TRIALS:-3}"

WORK="$(mktemp -d -t parity-watch-mut)"
STAMP="$$"
LABELS=""
CURRENT_SIDE=""
# Both lists are files. Everything that appends to them runs inside a command substitution, so a
# variable would be discarded the moment the observation returned — the trap the lane's own evidence
# line documents, and the reason its `$LABELS` loop has never had anything to boot out.
DECOYS="$WORK/decoys"
: > "$DECOYS"

MAIN_PID=$$
cleanup() {
  [ "$BASHPID" != "$MAIN_PID" ] && return 0
  for label in $LABELS; do launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1; done
  while read -r label; do
    [ -n "$label" ] && launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1
  done < "${WATCH_LABELS:-/dev/null}"
  while read -r decoy; do
    case "$decoy" in */p8-decoy*) rm -rf "$decoy" ;; esac
  done < "$DECOYS"
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM HUP

command -v launchctl >/dev/null 2>&1 || { echo "environment: launchctl is not available"; exit 2; }
[ -x /usr/bin/plutil ] || { echo "environment: /usr/bin/plutil is not available"; exit 2; }
[ -x "$SWIFT_BIN" ] || { echo "environment: no Swift router at ${SWIFT_BIN#"$REPO_ROOT/"}"; exit 2; }

LAUNCHD_PATH="/usr/local/bin:/usr/bin:/bin"

. "$REPO_ROOT/scripts/acceptance/parity-install-watch.sh"

# The unmutated plist writer, kept so each mutation is a REWRITE of what the lane generates rather
# than a second copy of it. A copy would drift, and a drifted copy is free to agree with the wrong
# answer — which is this row's entire history.
eval "watch_plist_unmutated() $(declare -f watch_plist | tail -n +2)"
eval "watched_path_of_unmutated() $(declare -f watched_path_of | tail -n +2)"

apply_mutation() { # arm
  watched_path_of() { watched_path_of_unmutated "$@"; }
  case "$1" in
    control|resident)
      watch_plist() { watch_plist_unmutated "$@"; } ;;
    decoy)
      # A private directory this lane never writes to, created fresh per trial. The decoy file is
      # never created either: the point is a watched path that nothing this lane does can disturb.
      watch_plist() {
        local dir; dir="$(mktemp -d -t p8-decoy)"
        printf '%s\n' "$dir" >> "$DECOYS"
        watch_plist_unmutated "$@" \
          | sed "s|<key>WatchPaths</key><array><string>[^<]*</string>|<key>WatchPaths</key><array><string>$dir/decoy.json</string>|"
      } ;;
    blind)
      # HOME moved to a directory with its own `.claude.json`, seeded once and never restaged. The
      # WatchPaths entry is untouched, so the delivery this agent receives is genuine.
      watch_plist() {
        local blind="$WORK/blind-$STAMP-$RANDOM"
        mkdir -p "$blind"
        printf '{\n  "numStartups": 41,\n  "mcpServers": { "notadoptable-blind": { "note": "no command and no url" } }\n}\n' \
          > "$blind/.claude.json"
        watch_plist_unmutated "$@" \
          | sed "s|<key>HOME</key><string>[^<]*</string>|<key>HOME</key><string>$blind</string>|"
      } ;;
    stamp-only)
      # The decoy plist, with HALF 2 OF THE FIX REVERTED: the stimulus is pinned back to the agent's
      # own `$HOME/.claude.json` instead of following the path the plist declares. This is the lane
      # P5 measured, with P8's stamp bolted on and nothing else — the arm exists to measure whether
      # the stamp ALONE would have been enough, rather than to argue that it would not.
      watch_plist() {
        local dir; dir="$(mktemp -d -t p8-decoy)"
        printf '%s\n' "$dir" >> "$DECOYS"
        watch_plist_unmutated "$@" \
          | sed "s|<key>WatchPaths</key><array><string>[^<]*</string>|<key>WatchPaths</key><array><string>$dir/decoy.json</string>|"
      }
      watched_path_of() { printf '%s' "$WORK/watch-$CURRENT_SIDE-home/.claude.json"; } ;;
    *) echo "  HARNESS BUG: unknown arm $1" >&2; exit 2 ;;
  esac
}

# One trial of one arm. Called DIRECTLY, never through `$( … )`: it has to leave its verdicts in
# globals, and a command substitution would run it in a subshell and discard them — which is the
# same trap the evidence file exists to work around one level down.
trial() { # arm index  -> TRIAL_RAN TRIAL_NEW TRIAL_OLD TRIAL_ONESHOT TRIAL_LINE
  local arm="$1" index="$2"
  # Three `local` statements, not one. Bash expands every word of a `local` line before it assigns
  # any of them, so `local a="$1" b="x-$a"` reads `$a` from the enclosing scope — or, under `set -u`,
  # aborts the run.
  local side="mut-$arm-$index"
  CURRENT_SIDE="$side"
  apply_mutation "$arm"
  : > "$WATCH_EVIDENCE"
  local terms evidence
  if [ "$arm" = resident ]; then
    terms="$(observe_watch "$side" /bin/sh -c "'$SWIFT_BIN' watch; sleep 300")"
  else
    terms="$(observe_watch "$side" "$SWIFT_BIN" watch)"
  fi
  evidence="$(tr -s ' ' <"$WATCH_EVIDENCE")"

  # The new term is what the lane records. The old one is `runs` moving, recovered from the same
  # evidence line so the two are scored on identical trials.
  TRIAL_NEW="$(printf '%s' "$terms" | cut -d, -f2)"
  local before after
  before="$(printf '%s' "$evidence" | sed -n 's/.*runs=\([0-9?]*\)->.*/\1/p')"
  after="$(printf '%s' "$evidence" | sed -n 's/.*runs=[0-9?]*->\([0-9?]*\).*/\1/p')"
  TRIAL_OLD=unreadable
  if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != '?' ] && [ "$after" != '?' ]; then
    TRIAL_OLD=no
    [ "$after" -gt "$before" ] && TRIAL_OLD=yes
  fi
  TRIAL_ONESHOT="$(printf '%s' "$terms" | cut -d, -f3)"
  TRIAL_RAN="$(printf '%s' "$terms" | cut -d, -f1)"
  TRIAL_LINE="$terms | $evidence"
}

# An arm's verdict, printed with its denominator on every line. "reran=no on 6" is a result;
# "reran went red" is a claim.
run_arm() { # arm trials want-reran want-oneshot
  local arm="$1" trials="$2" want_reran="$3" want_oneshot="$4"
  local i new_agree=0 old_agree=0 oneshot_agree=0
  echo "arm $arm — $trials trials, want reran=$want_reran oneshot=$want_oneshot"
  for ((i = 1; i <= trials; i++)); do
    trial "$arm" "$i"
    [ "$TRIAL_NEW" = "$want_reran" ] && new_agree=$((new_agree + 1))
    [ "$TRIAL_OLD" = "$want_reran" ] && old_agree=$((old_agree + 1))
    [ "$TRIAL_ONESHOT" = "$want_oneshot" ] && oneshot_agree=$((oneshot_agree + 1))
    printf '  %d/%d  ran=%s reran=%s(want %s) oneshot=%s(want %s) runs-only-would-say=%s\n' \
      "$i" "$trials" "$TRIAL_RAN" "$TRIAL_NEW" "$want_reran" \
      "$TRIAL_ONESHOT" "$want_oneshot" "$TRIAL_OLD"
    printf '        %s\n' "$TRIAL_LINE"
  done
  printf '  RESULT %s: attributable reran correct %d of %d; oneshot correct %d of %d; ' \
    "$arm" "$new_agree" "$trials" "$oneshot_agree" "$trials"
  printf 'the runs-only term it replaces would have been correct %d of %d\n\n' "$old_agree" "$trials"
  ARM_NEW="$new_agree"; ARM_OLD="$old_agree"; ARM_ONESHOT="$oneshot_agree"; ARM_TRIALS="$trials"
}

echo "P8 — mutation trials for install-launchd-watch, against the lane's own observation code"
echo "     swift binary: ${SWIFT_BIN#"$REPO_ROOT/"}"
echo

failures=0
summary=""

run_arm control "$TRIALS" yes yes
[ "$ARM_NEW" = "$ARM_TRIALS" ] || failures=$((failures + 1))
[ "$ARM_ONESHOT" = "$ARM_TRIALS" ] || failures=$((failures + 1))
summary="$summary
  control   reran green $ARM_NEW/$ARM_TRIALS, oneshot green $ARM_ONESHOT/$ARM_TRIALS (both must be all)"

run_arm decoy "$TRIALS" no yes
[ "$ARM_NEW" = "$ARM_TRIALS" ] || failures=$((failures + 1))
summary="$summary
  decoy     reran red $ARM_NEW/$ARM_TRIALS (must be all) — runs-only would have been red $ARM_OLD/$ARM_TRIALS"

run_arm blind "$TRIALS" no yes
[ "$ARM_NEW" = "$ARM_TRIALS" ] || failures=$((failures + 1))
summary="$summary
  blind     reran red $ARM_NEW/$ARM_TRIALS (must be all) — runs-only would have been red $ARM_OLD/$ARM_TRIALS"

# NOT GATED, and deliberately. This arm reverts half 2 of the fix and counts how often the stamp
# alone still reads green under P5's exact decoy. The number is the finding; the pass/fail is not,
# because a red here can mean either "the stamp was enough" or "no spurious spawn happened to occur"
# — and on 2026-08-20 it meant the second, with `runs=1->1` in all six.
run_arm stamp-only "$TRIALS" no yes
summary="$summary
  stamp-only  half 2 reverted: reran red $ARM_NEW/$ARM_TRIALS, NOT GATED. Read it with the runs
              column: a red here with the counter unmoved means no spurious spawn occurred to test
              the stamp with, not that the stamp alone would do"

run_arm resident "$RESIDENT_TRIALS" no no
[ "$ARM_ONESHOT" = "$ARM_TRIALS" ] || failures=$((failures + 1))
summary="$summary
  resident  oneshot red $ARM_ONESHOT/$ARM_TRIALS (must be all)"

echo "roll-up$summary"
echo
if [ "$failures" -gt 0 ]; then
  echo "FAIL: $failures arm-level expectations were not met. A term that cannot go red under its own"
  echo "      mutation measures nothing, and a term that cannot go green measures nothing either."
  exit 1
fi
echo "every arm answered as it must. What this does NOT establish, stated because the row's history"
echo "is a claim that outran its evidence: it bounds the rate at which these mutations are caught on"
echo "THIS machine, and it says nothing about a defect nobody thought to mutate."
exit 0
