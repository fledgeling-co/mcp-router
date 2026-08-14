#!/usr/bin/env bash
#
# R4 — the pool lane.
#
# The brief asks for "behaviourally identical spawn and reap decisions". That corpus is the one
# place where the two sides cannot be put on a wire next to each other: the reference's pool is
# driven by MCP traffic arriving on /mcp, and Swift has no MCP endpoint at all (R2-R). So this
# lane does the half that is honestly reachable and says plainly what the other half would need.
#
# The REFERENCE half is measured live here: a real child process, real calls through /mcp, and
# the decision read back off /status, which reports each child's state, its call count and how
# long it has been idle.
#
# The SWIFT half is a real-process test suite — RealProcessTests spawns actual children rather
# than doubles — and each row below names the test that carries it. That makes a row a comparison
# of two measurements taken at different times, which is weaker than the control lane's
# simultaneous byte diff, and the manifest note on every one of these rows says so.
#
# Two decisions are not reachable this way at all and stay blocked: a call outstanding must never
# be reaped, and reap behaviour under sustained live traffic. Both need traffic arriving at a
# Swift endpoint. Neither is approximated here — an approximated parity row is the thing this
# item exists to prevent.
#
# Exit codes: 0 the reference made every decision the Swift suite asserts, 1 it did not, 2 the
# environment could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT="${POOL_PORT:-8966}"
IDLE_MS="${POOL_IDLE_MS:-3000}"
WORK="$(mktemp -d -t parity-pool)"
RESULTS="${PARITY_RESULTS:-}"
ROUTER_PID=""

MAIN_PID=$$
cleanup() {
  [ "$BASHPID" != "$MAIN_PID" ] && return 0
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

record() {
  [ -n "$RESULTS" ] || return 0
  printf '%s\t%s\t%s\t%s\n' "pool" "$1" "$2" "$3" >> "$RESULTS"
}

# D6 is a `divergence` row, not a pool row, and the gate matches results on group AND id. Stamping
# every result `pool` meant this lane was writing a result for a row in another group — authorship
# nothing checked, and after the gate started checking it, a result that would never match.
record_divergence() {
  [ -n "$RESULTS" ] || return 0
  printf '%s\t%s\t%s\t%s\n' "divergence" "$1" "$2" "$3" >> "$RESULTS"
}

command -v node >/dev/null 2>&1 || { echo "environment: node is not installed"; exit 2; }
[ -f "$REPO_ROOT/dist/index.js" ] || {
  echo "environment: no built reference at dist/index.js. Run npm run build."
  echo "             A skipped lane is recorded as blocked, not as a pass."; exit 2; }
[ -d "$REPO_ROOT/node_modules/@modelcontextprotocol" ] || {
  echo "environment: the MCP client SDK is not installed, so no call can be made through /mcp."
  echo "             Run npm install."; exit 2; }
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "environment: something is already listening on :$PORT. This harness never shares a port"
  echo "             and never touches the router on 8975/8976."
  exit 2
fi

echo "toolset" > "$WORK/toolset"
cat > "$WORK/servers.json" <<JSON
{
  "mcpServers": {
    "pool-child": {
      "command": "node",
      "args": ["$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs", "stdio"],
      "env": { "FIXTURE_TOOLSET_FILE": "$WORK/toolset" }
    }
  }
}
JSON

MCP_ROUTER_HOME="$WORK" node "$REPO_ROOT/dist/index.js" serve \
  --port "$PORT" --idle-ms "$IDLE_MS" >"$WORK/router.log" 2>&1 &
ROUTER_PID=$!

TOKEN=""
for _ in $(seq 1 100); do
  if [ -f "$WORK/control.token" ]; then
    TOKEN="$(cat "$WORK/control.token")"
    curl -fsS -m 2 -H "x-mcpr-token: $TOKEN" "http://127.0.0.1:$PORT/servers" >/dev/null 2>&1 && break
  fi
  kill -0 "$ROUTER_PID" 2>/dev/null || { echo "environment: the reference exited during startup"; tail -20 "$WORK/router.log"; exit 2; }
  sleep 0.1
done
[ -n "$TOKEN" ] || { echo "environment: the reference never wrote a control token"; exit 2; }

# The upstream's tools have to be indexed before anything can be called through /mcp. Without
# this the router logs "1 upstream(s) not in the manifest" and serves 0 tools, and every call
# below hangs looking for a tool that was never published — which is a fault in the harness
# reported as a fault in the pool.
curl -fsS -m 30 -X POST -H "x-mcpr-token: $TOKEN" -H 'content-type: application/json' \
  "http://127.0.0.1:$PORT/servers/pool-child/reindex" >"$WORK/reindex.json" 2>&1 || {
  echo "environment: the upstream could not be indexed, so no tool exists to call"
  cat "$WORK/reindex.json"; exit 2; }
grep -q '"tools":[1-9]' "$WORK/reindex.json" || {
  echo "environment: indexing published no tools — $(cat "$WORK/reindex.json" | cut -c1-160)"
  exit 2; }

# Counting the pool's children by matching the upstream's command line AND requiring the router to
# be the parent. `pgrep -P` alone is wrong: the reference spawns a short-lived `lsof` for every
# control request, to attribute the caller, and those are its children too. The first version of
# this lane counted two of them and reported that the pool had eagerly spawned — a harness artefact
# that would have been filed as a parity defect in the reference.
children() {
  # pgrep exits 1 for "matched nothing" and >1 for a real error, and both used to print 0 through
  # `wc -l`. P1 and P3 each assert children == 0, so a pgrep that failed for any reason — a changed
  # argv, a permissions problem — proved two rows from an instrument that was not working.
  local out rc
  out="$(pgrep -P "$ROUTER_PID" -f "mcp-fixture-server.mjs" 2>/dev/null)"; rc=$?
  if [ "$rc" -gt 1 ]; then echo "ERROR"; return 0; fi
  printf '%s' "$out" | grep -c . | tr -d ' '
}
# Every read of the reference asserts the reference is ALIVE first. Without it, a router that died
# after the token check answers nothing, `state_of` reports "unknown", and "state != running" is
# satisfied by the absence of an answer rather than by an observation.
alive() { kill -0 "$ROUTER_PID" 2>/dev/null; }
field_of() { # field
  alive || { echo "REFERENCE-DEAD"; return 0; }
  curl -fsS -m 5 -H "x-mcpr-token: $TOKEN" "http://127.0.0.1:$PORT/servers/pool-child" 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])" 2>/dev/null || echo UNREADABLE
}
state_of() { field_of state; }
calls_of() { field_of callsServed; }
call_tool() { node "$REPO_ROOT/scripts/fixtures/call-through-router.mjs" "http://127.0.0.1:$PORT/mcp" ping; }

pass=0; fail=0
verdict() { # id  ok?  message  swift-test
  if [ "$2" = 1 ]; then
    pass=$((pass + 1)); printf '  ok   %-52s %s\n' "$3" ""
    record "$1" ok "reference: $3 | swift: $4"
  else
    fail=$((fail + 1)); printf '  FAIL %-52s\n' "$3"
    record "$1" fail "reference did not make the decision the Swift suite asserts — $3"
  fi
}

# ---------------------------------------------------------------------------------------------
echo "driving the reference's pool on :$PORT with a ${IDLE_MS}ms idle window"
echo

# P1 — nothing spawns before the first lease. The router has been up and answering the control API
# for several seconds at this point, which is exactly the window in which an eager pool would have
# started something.
before_state="$(state_of)"; before_children="$(children)"
# `idle` specifically, not "anything that is not running" — REFERENCE-DEAD and UNREADABLE are both
# "not running" and neither is an observation of a pool that declined to spawn.
if [ "$before_state" = "idle" ] && [ "$before_children" = 0 ]; then ok=1; else ok=0; fi
verdict pool-p1 "$ok" "nothing spawned before the first call (state=$before_state, children=$before_children)" \
  "RouterCoreTests/RealProcessTests.poolSpawnsAndReapsARealChild"

# P2 — concurrent leases spawn ONE child. Five callers at once; a pool that spawns per caller
# gives five children, and a pool that serialises gives one.
#
# The pids are collected and waited on individually. A bare `wait` waits for every background job
# the shell owns, and this shell owns the reference router — so it blocked until the alarm killed
# the lane, which looks exactly like a pool that never answers.
call_pids=()
for _ in 1 2 3 4 5; do call_tool >>"$WORK/calls.log" 2>&1 & call_pids+=("$!"); done
for pid in "${call_pids[@]}"; do wait "$pid" || true; done
during_children="$(children)"; served="$(calls_of)"
if [ "$during_children" = 1 ]; then ok=1; else ok=0; fi
alive || { echo "environment: the reference died during the concurrent calls"; exit 2; }
verdict pool-p2 "$ok" "five concurrent calls served by $during_children child (callsServed=$served)" \
  "RouterCoreTests/RealProcessTests.concurrentLeasesSpawnOneRealChild"

# D6 — `callsServed` counts ACQUISITIONS, not served calls. R2 declared this and chose to
# reproduce it exactly rather than correct it, precisely because this gate diffs the number.
#
# The five concurrent callers above shared one lease, so a counter of acquisitions reads 1 and a
# counter of calls reads 5. That makes this the one place the divergence is directly observable,
# and it is asserted here rather than left as an interesting number in the P2 line. If the
# reference is ever fixed to count calls, this row goes red as stale — which is the only way a
# reproduced bug stays a decision instead of becoming folklore.
if [ "$served" = 1 ]; then
  pass=$((pass + 1))
  printf '  ok   %-52s\n' "callsServed counted 1 acquisition for 5 concurrent calls (D6)"
  record_divergence div-r2-d6 ok "five concurrent calls, callsServed=1 — acquisitions, not calls, exactly as declared"
elif [ "$served" = 5 ]; then
  fail=$((fail + 1))
  printf '  FAIL %-52s\n' "callsServed counted 5 — the reference now counts calls, not acquisitions"
  record_divergence div-r2-d6 fail "stale: callsServed=5, so the reference counts calls now and D6 no longer describes it"
else
  fail=$((fail + 1))
  printf '  FAIL %-52s\n' "callsServed=$served, which is neither 1 acquisition nor 5 calls"
  record_divergence div-r2-d6 fail "callsServed=$served — neither the declared 1 nor a call count of 5"
fi

# P3 — an idle child is reaped after the window. Waited past it, not up to it: a reaper that fires
# early and one that fires late are both wrong, and only the second is a bug people notice.
sleep "$(python3 -c "print($IDLE_MS/1000 + 2)")"
after_state="$(state_of)"; after_children="$(children)"
if [ "$after_state" = "idle" ] && [ "$after_children" = 0 ]; then ok=1; else ok=0; fi
verdict pool-p3 "$ok" "the idle child was reaped after ${IDLE_MS}ms (state=$after_state, children=$after_children)" \
  "RouterCoreTests/RealProcessTests.poolSpawnsAndReapsARealChild"

# P8 — a child that exits is evicted and reopened. The child is killed underneath the router; the
# next call has to notice the corpse rather than write into a closed pipe.
call_tool >>"$WORK/calls.log" 2>&1 || true
victim="$(pgrep -P "$ROUTER_PID" -f "mcp-fixture-server.mjs" 2>/dev/null | head -1)"
if [ -n "$victim" ]; then
  kill -9 "$victim" 2>/dev/null || true
  sleep 0.5
  if call_tool >>"$WORK/calls.log" 2>&1; then
    reborn="$(pgrep -P "$ROUTER_PID" -f "mcp-fixture-server.mjs" 2>/dev/null | head -1)"
    [ -n "$reborn" ] && [ "$reborn" != "$victim" ] && ok=1 || ok=0
    verdict pool-p8 "$ok" "child $victim was killed; the next call reopened as $reborn" \
      "RouterCoreTests/RealProcessTests.realChildThatExitsIsEvicted"
  else
    verdict pool-p8 0 "the call after the child was killed did not succeed" \
      "RouterCoreTests/RealProcessTests.realChildThatExitsIsEvicted"
  fi
else
  echo "environment: no child was running to kill, so P8 was not exercised"
  exit 2
fi

echo
echo "pool: $pass decisions match the Swift suite, $fail do not"
echo "      pool-p4 and pool-reap-traffic stay blocked on R2-R — both need traffic arriving at a"
echo "      Swift MCP endpoint, and approximating them would be the failure this gate prevents."
[ "$fail" -gt 0 ] && exit 1
exit 0
