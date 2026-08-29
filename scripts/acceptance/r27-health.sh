#!/usr/bin/env bash
#
# R27 — upstream health, over the daemon's own socket, against real child processes.
#
# TWO things the unit suite structurally cannot see.
#
# The first is R28's and R31's lesson repeated: `ControlDeps.health` is optional exactly as
# `caches`, `extensions`, `registry` and `authFlow` are, and two of those shipped nil in
# `RouterServiceDispatch` with a green suite — `GET /registry/search` answered 502 in the only
# process that ships, and `POST /servers/:name/auth` answered 405 until P7. Deleting the one
# `health:` line there leaves every unit test passing and turns this whole lane into 503s.
#
# The second is this item's own, and it is sharper: the suite drives a stubbed transport, so
# **nothing in it spawns**. A probe that reported `healthy` without reaching an upstream would pass
# every assertion in `UpstreamHealthProbeTests`. Here the upstreams are real python processes, and
# the recovery arm below is decided by a file on disk that the router never reads.
#
# The effect itself — that a probe really becomes a child process, attributed to this daemon by two
# records that cannot have coordinated — is `planning/test-campaign/bin/witness-health-probe.sh`.
# This lane is the route contract; that one is the effect.
#
# EVERY PATH IS INSIDE A SCRATCH HOME, on a port the campaign reserves, so the operator's own
# router at 127.0.0.1:8879 is never touched.
#
# Exit codes follow the house pattern:
#   0  every assertion held
#   1  the daemon answered, and answered something wrong
#   2  the environment could not run the check — the binary is missing, or the daemon never bound.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
HOME_DIR="$(mktemp -d -t mcprouter-r27)"
PORT="${PORT:-8979}"
ROUTER_PID=""

pass=0
fail=0
declare -a failures=()

. "$REPO_ROOT/scripts/acceptance/parity-lock.sh"

cleanup() {
  parity_lock_release
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null
  wait "$ROUTER_PID" 2>/dev/null
  rm -rf "$HOME_DIR"
}
trap cleanup EXIT INT TERM HUP

parity_lock_acquire "r27-health.sh"

[ -x "$SWIFT_BIN" ] || { echo "environment: no MCPRouterCLI at $SWIFT_BIN (run: make build-cli-debug)"; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "environment: curl is not installed"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "environment: python3 is not installed"; exit 2; }

# ------------------------------------------------------------------ the fixtures
#
# `answering` is a minimal stdio MCP server. `flaky` is the same server behind a shell that refuses
# to exec while a sentinel file exists — which is how the RECOVERY arm is driven from outside the
# router: the router never reads that file, so nothing it does can make the arm pass.
cat >"$HOME_DIR/answering.py" <<'PY'
import json, sys
def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n"); sys.stdout.flush()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        msg = json.loads(line)
    except Exception:
        continue
    mid, method = msg.get("id"), msg.get("method")
    if method == "initialize":
        send({"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": "2024-11-05", "capabilities": {"tools": {}},
            "serverInfo": {"name": "r27-fixture", "version": "1.0.0"}}})
    elif method == "tools/list":
        send({"jsonrpc": "2.0", "id": mid, "result": {"tools": [
            {"name": "echo", "description": "Returns its input.",
             "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}}}]}})
    elif mid is not None:
        send({"jsonrpc": "2.0", "id": mid,
              "error": {"code": -32601, "message": "no method %s" % method}})
PY

# `startupTimeoutMs` is 1500 on this one deliberately, and the reason is a MEASURED property of the
# pool rather than impatience: a stdio child that exits immediately is not noticed as gone, so the
# acquisition waits out the whole startup budget — 60 s by default. The probe's own
# `probeTimeoutMs` does not cover acquisition (it bounds the `tools/list` request, so that "the
# child never started" and "the child answered too slowly" stay different answers), which means the
# budget that actually governs this arm is this one. Recorded as `DEF-063`.
cat >"$HOME_DIR/flaky.sh" <<SHIM
#!/bin/bash
# Refuses while the sentinel exists. The router never reads this file; the lane owns it.
[ -e "$HOME_DIR/broken" ] && exit 17
exec /usr/bin/python3 "$HOME_DIR/answering.py"
SHIM
chmod +x "$HOME_DIR/flaky.sh"
: > "$HOME_DIR/broken"
# The disabled server gets its OWN copy of the same script, under a different name. Counting
# `answering.py` children could not speak for it: the enabled servers run the same command line, so
# the count is a fact about them and any statement about the disabled one would be arithmetic on a
# denominator that moves whenever this lane adds a server.
cp "$HOME_DIR/answering.py" "$HOME_DIR/disabled.py"

cat >"$HOME_DIR/servers.json" <<JSON
{
  "mcpServers": {
    "r27-good":   { "command": "/usr/bin/python3", "args": ["$HOME_DIR/answering.py"] },
    "r27-flaky":  { "command": "$HOME_DIR/flaky.sh", "startupTimeoutMs": 1500,
                    "health": { "tripAfter": 2 } },
    "r27-refused": { "command": "/usr/bin/python3", "args": ["$HOME_DIR/answering.py"],
                     "health": { "tripAfter": 1, "probeIntervalMs": 10 } },
    "r27-off":    { "command": "/usr/bin/python3", "args": ["$HOME_DIR/disabled.py"],
                    "disabled": true }
  }
}
JSON

MCP_ROUTER_HOME="$HOME_DIR" "$SWIFT_BIN" serve --port "$PORT" >"$HOME_DIR/serve.out" 2>&1 &
ROUTER_PID=$!

ready=""
for _ in $(seq 1 50); do
  if curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then ready=ok; break; fi
  kill -0 "$ROUTER_PID" 2>/dev/null || break
  sleep 0.2
done
if [ "$ready" != "ok" ]; then
  echo "environment: the Swift daemon never answered /health on :$PORT — its output:"
  sed -n '1,40p' "$HOME_DIR/serve.out"
  exit 2
fi

TOKEN="$(cat "$HOME_DIR/control.token" 2>/dev/null || echo '')"
[ -n "$TOKEN" ] || { echo "environment: the daemon minted no control token at $HOME_DIR/control.token"; exit 2; }

TIMEOUT=25

check() { # label method target want-status want-substring(or "-") [--no-token|--no-type]
  local label="$1" method="$2" target="$3" want_status="$4" want_body="$5" mode="${6:-}"

  if ! kill -0 "$ROUTER_PID" 2>/dev/null; then
    echo "environment: the daemon exited before \"$label\" — its output:"
    sed -n '1,40p' "$HOME_DIR/serve.out"
    exit 2
  fi

  local -a args=(-sS -m "$TIMEOUT" -o "$HOME_DIR/body" -w '%{http_code}' -X "$method"
                 "http://127.0.0.1:$PORT$target")
  [ "$mode" != "--no-type" ] && args+=(-H 'content-type: application/json')
  [ "$mode" != "--no-token" ] && args+=(-H "x-mcpr-token: $TOKEN")
  [ "$method" = "POST" ] && args+=(--data-binary '{}')

  local status; status="$(curl "${args[@]}" 2>/dev/null || echo 000)"
  local body; body="$(cat "$HOME_DIR/body")"

  if [ "$status" = "000" ]; then
    echo "environment: curl could not reach the daemon for \"$label\""
    exit 2
  fi

  if [ "$status" = "$want_status" ] && { [ "$want_body" = "-" ] || case "$body" in *"$want_body"*) true ;; *) false ;; esac; }; then
    printf '  ok   %-62s %s\n' "$label" "$status"
    pass=$((pass + 1))
  else
    printf '  FAIL %-62s got %s (wanted %s)\n' "$label" "$status" "$want_status"
    [ "$want_body" != "-" ] && printf '       body: %s\n       want to contain: %s\n' "$body" "$want_body"
    fail=$((fail + 1)); failures+=("$label")
  fi
}

echo "r27-health — the routes are wired in the process that ships"
check "GET /upstreams/health answers"            GET  "/upstreams/health" 200 '"count":4'
check "nothing is probed until something asks"   GET  "/upstreams/health" 200 '"state":"unprobed"'
check "a probe of a real upstream is healthy"    POST "/servers/r27-good/probe" 200 '"state":"healthy"'
check "the probe counted the tools it was told"  POST "/servers/r27-good/probe" 200 '"tools":1'

echo
echo "the record is the process's, not the request's"
check "the report carries what the probe found"  GET  "/upstreams/health" 200 '"state":"healthy"'
check "and it counted both probes"               GET  "/upstreams/health" 200 '"probesRun":2'

echo
echo "degraded precedes tripped, and one success recovers"
check "the first failure is degraded"            POST "/servers/r27-flaky/probe" 200 '"state":"degraded"'
check "the second reaches this server's own limit" POST "/servers/r27-flaky/probe" 200 '"state":"tripped"'
rm -f "$HOME_DIR/broken"
check "one success recovers a tripped upstream"  POST "/servers/r27-flaky/probe" 200 '"state":"healthy"'

echo
echo "a refused setting is reported rather than clamped in silence"
check "the refusal names the key"                GET  "/upstreams/health" 200 '"key":"tripAfter"'
check "and its scope"                            GET  "/upstreams/health" 200 '"scope":"server"'
check "the policy in force is the global one"    POST "/servers/r27-refused/probe" 200 '"tripAfter":3'

echo
echo "a disabled server is declined rather than spawned"
check "the probe route declines it"              POST "/servers/r27-off/probe" 200 '"declined":"the server is disabled"'
check "and it stays unprobed"                    POST "/servers/r27-off/probe" 200 '"state":"unprobed"'

echo
echo "the refusals"
check "an unknown server is 404"                 POST "/servers/ghost/probe" 404 'no server named'
check "an untokened probe is 401"                POST "/servers/r27-good/probe" 401 - --no-token
check "a probe with no content-type is 415"      POST "/servers/r27-good/probe" 415 - --no-type
check "GET on the probe path is 405"             GET  "/servers/r27-good/probe" 405 -
check "an uppercase sub-path is not a probe"     POST "/servers/r27-good/Probe" 405 -
check "the collection is GET-only"               POST "/upstreams/health" 405 -
check "a prefix collision is not claimed"        GET  "/upstreams/healthx" 404 'MCP endpoint'

echo
echo "the disabled server was never spawned by any of it"
spawned="$(ps -Ao ppid=,command= 2>/dev/null | awk -v p="$ROUTER_PID" '$1==p' | grep -c 'disabled.py')"
# Zero, and it is a reading of the process table rather than of the reply. A route that answered
# `declined` while spawning the child anyway would pass every assertion above.
if [ "$spawned" -eq 0 ]; then
  printf '  ok   %-62s %s\n' "children running the disabled server's own script" "$spawned"
  pass=$((pass + 1))
else
  printf '  FAIL %-62s %s, and there should be none\n' "children running the disabled server's own script" "$spawned"
  fail=$((fail + 1)); failures+=("disabled server spawned")
fi

echo
echo "r27-health: $pass ok, $fail failed"
if [ "$fail" -gt 0 ]; then
  printf '  failed: %s\n' "${failures[@]}"
  exit 1
fi
exit 0
