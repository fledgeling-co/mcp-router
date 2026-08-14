#!/bin/bash
# Emit a line when a named fleet runner goes quiet, or when every named run has finished.
#
#   planning/watch-fleet.sh wf_9ba012c9-417 wf_761c23ce-32c
#
# Detects the two failures that look identical from outside: an agent that died, and an agent
# that RETURNED EARLY (journaled as a success, never retried, artifacts left untracked). Both
# present as a transcript that stops writing while its siblings keep going. I1 sat in that state
# for 45 minutes before a manual check found it.
#
# Run ids are ARGUMENTS, not discovered. An earlier version globbed every wf_* under the session
# and reported 13-hour-old agents from waves that finished this morning. It also tried to skip
# finished runs with `results >= started`, which can never be true for the runs that matter: a
# dead agent never journals a result, so a run that lost one stays permanently "unfinished".
#
# Not a false positive on a blocked agent: the codex review gates are bounded at 600s, so the
# threshold sits above them, and a gate holding THIS run's worktree is reported alongside.

QUIET=${FLEET_QUIET:-900}          # 15 min: above the 600s codex gate ceiling
SESSION=/Users/lukerhodes/.claude/projects/-Users-lukerhodes-Dev/bdb1ad3b-8861-4dfc-8f0d-9e160dc3aa80
RUNS="$SESSION/subagents/workflows"

[ $# -eq 0 ] && { echo "FATAL: no run ids given — watching nothing is not watching"; exit 2; }
for id in "$@"; do
    [ -d "$RUNS/$id" ] || { echo "FATAL: no such run dir: $id"; exit 2; }
done

declare -A reported

while true; do
    now=$(date +%s)
    live=0
    for id in "$@"; do
        dir="$RUNS/$id"
        for f in "$dir"/agent-*.jsonl; do
            [ -f "$f" ] || continue
            key="$id/$(basename "$f" .jsonl)"
            silent=$(( now - $(stat -f '%m' "$f") ))
            item=$(grep -o 'FEATURE: [A-Z0-9]*' "$f" | head -1 | cut -d' ' -f2)

            if [ "$silent" -lt "$QUIET" ]; then
                live=$(( live + 1 ))
                unset "reported[$key]"
                continue
            fi
            [ -n "${reported[$key]:-}" ] && continue
            reported[$key]=1
            if pgrep -f "gate-${item}-" >/dev/null 2>&1; then
                gate="a codex gate for ${item} is running, so this is explained"
            else
                gate="NO codex gate for ${item} — not explained by a review gate"
            fi
            echo "QUIET ${item:-?} in $id — no transcript write for $(( silent / 60 ))m. $gate. Check died-vs-returned-early before relaunching."
        done
    done
    [ "$live" -eq 0 ] && { echo "ALL QUIET — every agent in $* has stopped writing; the wave is over or wholly stalled"; exit 0; }
    sleep 120
done
