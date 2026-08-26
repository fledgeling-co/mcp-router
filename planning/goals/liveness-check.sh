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
#
# A gate with false positives is worse than a narrow true one: it blocks the run on noise and teaches
# its reader to skip the class. Agent death is also watched by the better-goal Monitor and the
# harness's own task notifications, which see liveness directly rather than inferring it from files.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
QUIET_MIN=${QUIET_MIN:-20}
now=$(date +%s)
bad=0
while read -r path _ br; do
  case "$path" in *".worktrees/"*) ;; *) continue;; esac
  b=${br#[}; b=${b%]}
  n=$(git log --oneline "main..$b" 2>/dev/null | wc -l | tr -d ' ')
  [ "${n:-0}" -gt 0 ] && continue                    # it has committed; not this check's business
  # No commits yet. Dead only if nothing has written under it for QUIET_MIN minutes.
  newest=0
  while IFS= read -r f; do
    m=$(stat -f %m "$f" 2>/dev/null || echo 0)
    [ "$m" -gt "$newest" ] && newest=$m
  done < <(find "$path" -type f -not -path '*/.git/*' 2>/dev/null | head -400)
  [ "$newest" -eq 0 ] && newest=$(stat -f %m "$path" 2>/dev/null || echo "$now")
  quiet=$(( (now - newest) / 60 ))
  if [ "$quiet" -ge "$QUIET_MIN" ]; then
    echo "liveness: $b has a worktree, no commits, and no write for ${quiet}m — died before committing"
    bad=$((bad+1))
  else
    echo "liveness: $b has no commits yet but wrote ${quiet}m ago — young, not dead"
  fi
done < <(git worktree list)
echo "liveness: $bad stalled worktree(s) — see header for what this does not cover"
[ "$bad" -eq 0 ]
