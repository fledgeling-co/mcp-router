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

QUIET=${FLEET_QUIET:-900}               # 15 min of silence with no gate running
GATED_QUIET=${FLEET_GATED_QUIET:-2700}  # 45 min: past 1740s, the longest gate re-run observed
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

        # Which ITEMS in this run are finished. Keyed by item, not agentId, because the harness
        # retries transparently under a NEW agentId: R3's first agent was interrupted and never
        # journaled a result, while a retry with a different id returned for the same item. An
        # agentId-only check can never clear that first agent, so its corpse reports forever.
        # Item-name keying is safe *within* a run — a run's retries of one item are that item —
        # and would be wrong across runs, where a relaunched I1 and the original are both "I1".
        done_items=$(python3 - "$dir" <<'PY'
import json, os, re, sys
run = sys.argv[1]
finished = set()
results = set()
for line in open(os.path.join(run, "journal.jsonl")):
    d = json.loads(line)
    if d.get("type") == "result" and d.get("agentId"):
        results.add(d["agentId"])
for name in os.listdir(run):
    m = re.fullmatch(r"agent-(\w+)\.jsonl", name)
    if not m or m.group(1) not in results:
        continue
    with open(os.path.join(run, name), errors="ignore") as fh:
        hit = re.search(r"FEATURE: ([A-Z0-9]+)", fh.read())
    if hit:
        finished.add(hit.group(1))
print(" ".join(sorted(finished)))
PY
)
        for f in "$dir"/agent-*.jsonl; do
            [ -f "$f" ] || continue
            agent=$(basename "$f" .jsonl); agent=${agent#agent-}
            key="$id/$agent"

            silent=$(( now - $(stat -f '%m' "$f") ))
            item=$(grep -o 'FEATURE: [A-Z0-9]*' "$f" | head -1 | cut -d' ' -f2)

            # This item already returned in this run, by this agent or by a retry of it.
            case " $done_items " in *" ${item:-__none__} "*) continue ;; esac

            if [ "$silent" -lt "$QUIET" ]; then
                live=$(( live + 1 ))
                unset "reported[$key]"
                continue
            fi
            [ -n "${reported[$key]:-}" ] && continue

            # A running codex gate explains the silence, so it is not an event. The threshold
            # cannot simply sit above the gates: they are nominally bounded at 600s, but a
            # runner whose gate dies on its alarm legitimately re-runs it longer — 1740s was
            # observed on M1 — so a gated agent trips any fixed bound and trains the reader to
            # ignore the watcher. Report a gated agent only past a length no observed gate
            # reaches, and say that is what happened.
            if pgrep -f "gate-${item}-" >/dev/null 2>&1; then
                [ "$silent" -lt "$GATED_QUIET" ] && continue
                reported[$key]=1
                echo "STUCK ${item:-?} in $id — quiet $(( silent / 60 ))m with a codex gate still running, past any observed gate length. Check whether the gate is hung."
                continue
            fi
            reported[$key]=1
            echo "QUIET ${item:-?} in $id — no transcript write for $(( silent / 60 ))m and NO codex gate for it. Check died-vs-returned-early before relaunching."
        done
    done
    [ "$live" -eq 0 ] && { echo "ALL QUIET — every agent in $* has stopped writing; the wave is over or wholly stalled"; exit 0; }
    sleep 120
done
