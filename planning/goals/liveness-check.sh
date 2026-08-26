#!/bin/bash
# Whether the work is done and whether the agents doing it are alive are independent facts.
#
# FOUR revisions. The three failures are recorded because each was a different way of being wrong,
# and a gate's blind spots are worth more written down than rediscovered:
#   v1  flagged a worktree with ZERO commits. Too weak: a verify agent dying on an 8-commit branch
#       passed it happily — the "armed but dead" shape it exists to catch.
#   v2  added "an in-flight workflow whose transcript went quiet". FALSE POSITIVES: `started > results`
#       is not staleness. A run that completed after a harness retry keeps the extra `started`, and a
#       run that died and was already relaunched keeps all of them. It flagged two finished runs.
#   v3  reverted to v1. Then v1 ITSELF false-positived, measured 2026-08-26 21:04: two runners launched
#       two minutes earlier had worktrees and no commits yet, which is what a healthy new runner looks
#       like for its first stretch. A young worktree and a dead one are indistinguishable by commit
#       count alone.
#   v4  a worktree with no commits is only dead if it is also QUIET. Age plus inactivity, not either.
#   v5  skip a MERGED branch: merged-and-uncleaned looks identical to died-before-committing.
#   v7  SIXTH way of being wrong: a worktree whose runner FINISHED is quiet forever, and
#       quiet-because-done cannot be told from quiet-because-dead by any reading of the
#       filesystem. It called `ai/m32` stalled at exactly 35m while M32 sat complete, reported and
#       waiting to be verified. Delivery is now RECORDED in planning/goals/delivered.tsv rather
#       than inferred, because only the orchestrator knows a runner returned — and each row names
#       the tip it was delivered at, so a branch that moves past it is in flight again and the
#       exemption lapses on its own.
#   v6  TWO defects, both found 2026-08-26 while seven runners were live.
#       (a) BLIND TO EVERY COMMITTED BRANCH. `n > 0 && continue` meant a runner that commits and
#           then dies is invisible — which is v1's recorded failure, reintroduced by v3-v5's
#           narrowing. At the moment it was found, all seven live worktrees had commits, so the
#           gate could see none of them and its `0 stalled` was an absence rather than a
#           measurement. Quiet is now applied to committed branches too, at a longer threshold,
#           because the false positives on record were all about COMMIT COUNT alone and none about
#           quiet.
#       (b) SAMPLING BUG. `find ... | head -400` took an arbitrary 400 files and read the newest of
#           those. The newest file in the worktree need not be among them, so a busy runner could
#           read as quiet. It now asks `find -mmin` whether anything wrote inside the window, which
#           is exact and short-circuits.
#       Related, and the reason (b) matters: an ad-hoc check in the same session used
#       `find -newermt '-10 minutes'`, which on this BSD find reported 10 files where `-mmin -10`
#       reported 55 on the same tree in the same minute. Two readers, 5.5x apart, and the run acted
#       on the wrong one twice. Every reader here is now one whose output was compared against a
#       second.
#
# A gate with false positives is worse than a narrow true one: it blocks the run on noise and teaches
# its reader to skip the class. Agent death is also watched by the better-goal Monitor and the
# harness's own task notifications, which see liveness directly rather than inferring it from files.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
QUIET_MIN=${QUIET_MIN:-20}                       # no commits yet: a young runner is quiet briefly
QUIET_COMMITTED_MIN=${QUIET_COMMITTED_MIN:-35}   # committed: gates are long, so be generous
now=$(date +%s)
bad=0; seen=0

# Did anything write under $1 within $2 minutes? Exact, and short-circuits on the first hit.
wrote_within() {
  # Command substitution, NOT `find | head -1 | grep -q .`. Under `set -o pipefail` the early
  # close from head/grep gives find a SIGPIPE, the pipeline reports 141, and a busy worktree reads
  # as silent. Caught 2026-08-26 because this function said "no write in 35m" about a worktree the
  # age reader beside it put at 0m — two readers in one gate, disagreeing in print. Printing both
  # is what made it visible; a gate that printed only its verdict would have shipped flagging live
  # runners as dead.
  local hit
  hit=$(find "$1" -type f -not -path '*/.git/*' -mmin "-$2" 2>/dev/null | head -1)
  [ -n "$hit" ]
}
# Minutes since the newest write under $1, over ALL files (no head -N sample).
quiet_for() {
  local newest
  newest=$(find "$1" -type f -not -path '*/.git/*' -exec stat -f '%m' {} + 2>/dev/null | sort -rn | head -1)
  [ -z "$newest" ] && newest=$(stat -f %m "$1" 2>/dev/null || echo "$now")
  echo $(( (now - newest) / 60 ))
}

# ---- presence control, on real directories, run every invocation ----
# It calls the REAL readers against real filesystem state rather than modelling them.
#
# WHAT THIS CONTROL CANNOT DO, stated rather than left to be discovered. The SIGPIPE defect fixed
# on 2026-08-26 is a RACE: it appears only when find is still writing as head closes, so it needs a
# tree big enough and a machine loaded enough. A planted 400-file directory did NOT reproduce it —
# this control printed HELD against a deliberately re-introduced bug while the gate below went on
# to call a live runner stalled. A control that passes over the defect it was written for is the
# thing this repository keeps shipping, so it is not relied on for that class.
# The cross-check inside the loop is what covers it: both readers run on every real worktree and
# must agree. Today's bug produces a contradiction on the first one.
_ctl=$(mktemp -d)
mkdir -p "$_ctl/old" "$_ctl/new"
: > "$_ctl/old/f"; touch -t "$(date -v-90M +%Y%m%d%H%M)" "$_ctl/old/f"
: > "$_ctl/new/f"
ctl_fail=0
wrote_within "$_ctl/old" 35 && { echo "control: a 90m-old tree read as written-within-35m"; ctl_fail=1; }
wrote_within "$_ctl/new" 35 || { echo "control: a fresh tree read as silent"; ctl_fail=1; }
[ "$(quiet_for "$_ctl/old")" -ge 89 ] || { echo "control: age reader did not see a 90m-old file"; ctl_fail=1; }
[ "$(quiet_for "$_ctl/new")" -le 1 ]  || { echo "control: age reader did not see a fresh file"; ctl_fail=1; }
rm -rf "$_ctl"
if [ "$ctl_fail" -ne 0 ]; then
  echo "liveness: CONTROL DID NOT FIRE — the readers cannot tell a live tree from a dead one."
  echo "liveness: INCONCLUSIVE at exit 2, no count printed, because the count would be one this instrument cannot see."
  exit 2
fi
# Third arm: the delivered exemption must be tip-bound. A row naming the WRONG tip must not exempt.
_dfile=planning/goals/delivered.tsv
if [ -f "$_dfile" ]; then
  _rows=$(grep -cv '^#' "$_dfile" 2>/dev/null || echo 0)
  _bad=$(grep -v '^#' "$_dfile" | awk -F'\t' 'NF<2 {c++} END {print c+0}')
  if [ "${_bad:-0}" -ne 0 ]; then
    echo "liveness: $_bad malformed row(s) in $_dfile — a row without a tip would exempt unconditionally."
    echo "liveness: INCONCLUSIVE at exit 2, no count printed."
    exit 2
  fi
  echo "liveness: control HELD (old=silent, fresh=alive, both age readings correct); $_rows delivery row(s), all tip-bound"
else
  echo "liveness: control HELD (old=silent, fresh=alive, both age readings correct); no delivery file"
fi

while read -r path _ br; do
  case "$path" in *".worktrees/"*) ;; *) continue;; esac
  b=${br#[}; b=${b%]}
  seen=$((seen+1))
  if git branch --merged main --list "$b" | grep -q .; then
    echo "liveness: $b merged — worktree is cleanup, not a corpse"; continue
  fi
  # Delivered? Then quiet is the expected state, not evidence of death.
  drow=$(grep -v '^#' planning/goals/delivered.tsv 2>/dev/null | awk -v b="$b" -F'\t' '$1==b {print $2"\t"$3}')
  if [ -n "$drow" ]; then
    dtip=$(printf '%s' "$drow" | cut -f1)
    cur=$(git rev-parse --short "$b" 2>/dev/null)
    if [ "$cur" = "$dtip" ]; then
      echo "liveness: $b — delivered at $dtip, quiet is expected: not a corpse"
      continue
    fi
    echo "liveness: $b — delivered at $dtip but tip is now $cur; exemption lapsed, work is in flight again"
  fi
  n=$(git log --oneline "main..$b" 2>/dev/null | wc -l | tr -d ' ')
  if [ "${n:-0}" -gt 0 ]; then thresh=$QUIET_COMMITTED_MIN; state="$n commit(s)"
  else thresh=$QUIET_MIN; state="no commits"; fi

  # BOTH readers, every worktree, and they must agree. quiet_for is authoritative (exact, no
  # short-circuit); wrote_within is the fast one and is here as a live cross-check. A disagreement
  # means one of them is broken, and a gate whose readers disagree has no verdict to give.
  q=$(quiet_for "$path")
  if wrote_within "$path" "$thresh"; then w=alive; else w=silent; fi
  if [ "$q" -lt "$thresh" ]; then a=alive; else a=silent; fi
  if [ "$w" != "$a" ]; then
    echo "liveness: READERS DISAGREE on $b — fast reader says $w, age reader says $a (${q}m vs ${thresh}m threshold)"
    echo "liveness: INCONCLUSIVE at exit 2, no count printed. One reader is broken and this gate cannot say which."
    exit 2
  fi
  if [ "$a" = alive ]; then
    echo "liveness: $b — $state, wrote ${q}m ago (threshold ${thresh}m): alive"
  else
    echo "liveness: $b — $state, NO write for ${q}m (threshold ${thresh}m): stalled"
    bad=$((bad+1))
  fi
done < <(git worktree list)

# The count carries its denominator: `0 stalled` over 0 examined is an absence, not a measurement.
echo "liveness: $bad stalled of $seen worktree(s) examined — see header for what this does not cover"
[ "$seen" -gt 0 ] || echo "liveness: nothing to examine; this run measured no worktrees"
[ "$bad" -eq 0 ]
