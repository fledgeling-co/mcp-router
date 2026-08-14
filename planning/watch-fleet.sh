#!/bin/bash
# Emit a line when a named fleet runner goes quiet, or when every named run has finished.
#
#   planning/watch-fleet.sh wf_9ba012c9-417 wf_761c23ce-32c
#
# Detects the two failures that look identical from outside: an agent that died, and an agent
# that RETURNED EARLY (journaled as a success, never retried, artifacts left untracked). Both
# present as work that stops while its siblings keep going. I1 sat in that state for 45 minutes
# before a manual check found it.
#
# Run ids are ARGUMENTS, not discovered. An earlier version globbed every wf_* under the session
# and reported 13-hour-old agents from waves that finished this morning. It also tried to skip
# finished runs with `results >= started`, which can never be true for the runs that matter: a
# dead agent never journals a result, so a run that lost one stays permanently "unfinished".
#
# LIVENESS IS PER ITEM, AND THE WORKTREE IS PART OF IT. Two false positives on 2026-08-14, both
# from treating one agent's transcript mtime as the signal:
#
#   - M1 reported quiet at 16m while it was actively building. The harness had RETRIED it under a
#     new agentId; the original's transcript is frozen forever and never journals a result, so an
#     agent-keyed check reports that corpse until the run ends.
#   - F4 reported quiet at 24m while its gate output and .build were seconds old. A transcript is
#     appended when the agent SPEAKS; an agent thirty minutes into a swift build writes thousands
#     of files and not a byte to it.
#
# So an item is quiet only when nothing has moved — no agent of that item has spoken AND its
# worktree is untouched. That covers the retry case for free, because both agents fold into one
# item, and it covers the long-build case because .build is checked directly.
#
# Not a false positive on a blocked agent either: a running codex gate is reported separately and
# only past a length no observed gate reaches.

QUIET=${FLEET_QUIET:-900}               # 15 min of silence with no gate running
GATED_QUIET=${FLEET_GATED_QUIET:-2700}  # 45 min: past 1740s, the longest gate re-run observed
REPO=${FLEET_REPO:-/Users/lukerhodes/Dev/mcp-router}
SESSION=/Users/lukerhodes/.claude/projects/-Users-lukerhodes-Dev/bdb1ad3b-8861-4dfc-8f0d-9e160dc3aa80
RUNS="$SESSION/subagents/workflows"

[ $# -eq 0 ] && { echo "FATAL: no run ids given — watching nothing is not watching"; exit 2; }
for id in "$@"; do
    [ -d "$RUNS/$id" ] || { echo "FATAL: no such run dir: $id"; exit 2; }
done

# Newest write anywhere in a runner's worktree. `.build` is excluded from the walk because it
# holds tens of thousands of files, then its build database is stat'd directly — that single file
# is touched throughout a compile, which is exactly the window this has to see through.
wt_mtime() {
    local wt="$REPO/.worktrees/$1" newest
    [ -d "$wt" ] || { echo 0; return; }
    newest=$( { find "$wt" -type f -not -path '*/.build/*' -not -path '*/.git/*' \
                     -exec stat -f '%m' {} + 2>/dev/null
                [ -f "$wt/app/.build/build.db" ] && stat -f '%m' "$wt/app/.build/build.db"
              } | sort -rn | head -1 )
    echo "${newest:-0}"
}

# The set of already-reported "run/item" keys, as a space-delimited string rather than an
# associative array. macOS ships bash 3.2, which has no `declare -A`: it fails with
# "declare: -A: invalid option", then every `${reported[$key]}` treats the key as an ARITHMETIC
# subscript and dies with "division by 0 (error token is 2)". Both messages go to stderr, which
# Monitor does not surface as events, so the watcher exited 1 on every arm this session while
# reporting itself armed. A watcher that is not watching is worse than no watcher, because it is
# silence that reads as "nothing has gone wrong".
reported=" "
was_reported() { case "$reported" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
mark_reported() { was_reported "$1" || reported="$reported$1 "; }
clear_reported() { reported=" $(printf '%s' "$reported" | tr ' ' '\n' | grep -v -x -F "$1" | tr '\n' ' ') "; }

while true; do
    now=$(date +%s)
    live=0

    # Every process cwd on the machine, captured once per pass. This is the last and
    # strongest liveness test: a worktree with a live builder in it is not abandoned,
    # whatever its files say. I1 forced this — its `xcodebuild` writes DerivedData OUTSIDE
    # the worktree, so 18 minutes of real compiling looked like 18 minutes of nothing to a
    # file-mtime check. One lsof for all items beats one per item.
    CWDS=$(/usr/sbin/lsof -w -d cwd -Fn 2>/dev/null | grep '^n' | cut -c2-)
    for id in "$@"; do
        dir="$RUNS/$id"

        # One line per ITEM: name, newest transcript write across ALL its agents, done flag.
        # Keyed by item because the harness retries transparently under a new agentId, and
        # because two agents for one item are one piece of work. Item keying is safe *within* a
        # run; across runs it would conflate a relaunched I1 with the original, which is why the
        # report key below carries the run id too.
        items=$(python3 - "$dir" <<'PY'
import json, os, re, sys
run = sys.argv[1]
results = set()
for line in open(os.path.join(run, "journal.jsonl")):
    d = json.loads(line)
    if d.get("type") == "result" and d.get("agentId"):
        results.add(d["agentId"])
newest, done = {}, set()
for name in os.listdir(run):
    m = re.fullmatch(r"agent-(\w+)\.jsonl", name)
    if not m:
        continue
    path = os.path.join(run, name)
    with open(path, errors="ignore") as fh:
        hit = re.search(r"FEATURE: ([A-Z0-9]+)", fh.read())
    if not hit:
        continue
    item = hit.group(1)
    newest[item] = max(newest.get(item, 0), os.stat(path).st_mtime)
    if m.group(1) in results:
        done.add(item)
for item, mtime in sorted(newest.items()):
    print(f"{item} {int(mtime)} {1 if item in done else 0}")
PY
)
        while read -r item mtime finished; do
            [ -n "$item" ] || continue

            # Merged and cleaned up: the orchestrator deletes `ai/<id>` once an item is merged, so
            # a missing branch means this item is finished and its report already collected. Stop
            # watching it. Without this, R4 reported STOPPED twice after it had been merged: a
            # transient sourcekit process in its worktree counted as liveness and cleared its
            # reported flag, and removing the worktree let it fire again.
            git -C "$REPO" show-ref --verify --quiet "refs/heads/ai/$(printf '%s' "$item" | tr 'A-Z' 'a-z')" || continue

            # A journalled result does NOT retire an item from the watch. R5 proved why: a
            # message from the orchestrator resumes a stopped runner, that resumed turn
            # journals a result, and the runner then carries on building for another half
            # hour — during which an item-is-done skip would have watched nothing at all.
            # So liveness alone decides whether to fire, and the result only changes what
            # the event MEANS: with a result it has stopped and owes a report; without one
            # it probably died. A finished, idle item therefore fires exactly once, which
            # is the reminder to go and collect it.

            wt=$(wt_mtime "$item")
            [ "$wt" -gt "$mtime" ] && mtime=$wt
            silent=$(( now - mtime ))
            key="$id/$item"

            if [ "$silent" -lt "$QUIET" ]; then
                live=$(( live + 1 ))
                clear_reported "$key"
                continue
            fi
            was_reported "$key" && continue

            # Last check before firing: is anything actually working in there?
            if printf '%s\n' "$CWDS" | grep -q "^$REPO/.worktrees/$item"; then
                live=$(( live + 1 ))
                clear_reported "$key"
                continue
            fi

            # A running codex gate explains the silence, so it is not an event. The threshold
            # cannot simply sit above the gates: they are nominally bounded at 600s, but a
            # runner whose gate dies on its alarm legitimately re-runs it longer — 1740s was
            # observed on M1 — so a gated agent trips any fixed bound and trains the reader to
            # ignore the watcher. Report a gated agent only past a length no observed gate
            # reaches, and say that is what happened.
            if pgrep -f "gate-${item}-" >/dev/null 2>&1; then
                [ "$silent" -lt "$GATED_QUIET" ] && continue
                mark_reported "$key"
                echo "STUCK $item in $id — quiet $(( silent / 60 ))m with a codex gate still running, past any observed gate length. Check whether the gate is hung."
                continue
            fi
            mark_reported "$key"
            if [ "$finished" = "1" ]; then
                echo "STOPPED $item in $id — quiet $(( silent / 60 ))m and it HAS journalled a result, so it finished a turn rather than dying. Collect its report, or relaunch it if the item is not actually done."
            else
                echo "QUIET $item in $id — no agent write, no worktree write and no process in its worktree for $(( silent / 60 ))m, no codex gate. Check died-vs-returned-early before relaunching."
            fi

        done <<< "$items"
    done
    [ "$live" -eq 0 ] && { echo "ALL QUIET — every item in $* has stopped writing; the wave is over or wholly stalled"; exit 0; }
    sleep 120
done
