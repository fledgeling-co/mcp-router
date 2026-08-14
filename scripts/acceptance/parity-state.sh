#!/usr/bin/env bash
#
# R2-R — the state lane.
#
# The files a cutover inherits rather than creates. A machine that moves to the Swift router keeps
# `servers.json`, `manifest.json`, `usage.jsonl` and `usage-stats.json` that the TypeScript router
# wrote over months, and nothing had ever observed the Swift side reading a full set of them.
#
# The direction is the whole point and it is one-way by design: **the reference writes, the Swift
# router reads.** Seeding those files from the harness would prove that Swift can read files the
# harness knows how to write, which is a fact about the harness. So the reference is run first, for
# real — indexed, called twice, stopped — and only then is the Swift router pointed at the home it
# left behind.
#
# What is compared: the `tools/list` corpus and the `/usage` body that each router serves **from the
# same on-disk state**, byte for byte. The reference is restarted on its own leftovers to produce
# its half, so both halves are "a router started on a used home", not "a router that has just
# written what it is about to read".
#
# ROWS THIS LANE OWNS:  state: state-ondisk-compat
#
# CAVEAT, printed into the gate's report: this is a two-router comparison over one directory of real
# leftovers, and it is one-directional — it establishes that Swift READS what TypeScript WROTE, and
# says nothing about the reverse.
#
# Exit codes: 0 agreed, 1 a mismatch, 2 the environment could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
PORT="${STATE_PORT:-8996}"
WORK="$(mktemp -d -t parity-state)"
RESULTS="${PARITY_RESULTS:-}"
RUNNING=""

MAIN_PID=$$
cleanup() {
  [ "$BASHPID" != "$MAIN_PID" ] && return 0
  [ -n "$RUNNING" ] && kill "$RUNNING" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

record() {
  [ -n "$RESULTS" ] || return 0
  case "$1/$2" in
    state/state-ondisk-compat) ;;
    *) echo "  LANE BUG: refusing to record $1/$2, which this lane does not own" >&2; return 1 ;;
  esac
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$RESULTS"
}

command -v node >/dev/null 2>&1 || { echo "environment: node is not installed"; exit 2; }
[ -f "$REPO_ROOT/dist/index.js" ] || { echo "environment: no dist/index.js. Run npm run build."; exit 2; }
[ -x "$SWIFT_BIN" ] || { echo "environment: no Swift router at ${SWIFT_BIN#"$REPO_ROOT/"}"; exit 2; }
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "environment: something is already listening on :$PORT"; exit 2
fi

HOME_DIR="$WORK/home"
mkdir -p "$HOME_DIR"
echo "toolset" > "$HOME_DIR/toolset"
cat > "$HOME_DIR/servers.json" <<JSON
{
  "mcpServers": {
    "probe": {
      "command": "node",
      "args": ["$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs", "stdio"],
      "env": { "FIXTURE_TOOLSET_FILE": "$HOME_DIR/toolset" }
    }
  }
}
JSON

start() { # kind
  if [ "$1" = ts ]; then
    MCP_ROUTER_HOME="$HOME_DIR" node "$REPO_ROOT/dist/index.js" serve --port "$PORT" --idle-ms 60000 \
      >"$WORK/$1.stdout" 2>&1 &
  else
    MCP_ROUTER_HOME="$HOME_DIR" "$SWIFT_BIN" serve --port "$PORT" --idle-ms 60000 \
      >"$WORK/$1.stdout" 2>&1 &
  fi
  RUNNING=$!
  for _ in $(seq 1 80); do
    curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && return 0
    kill -0 "$RUNNING" 2>/dev/null || { echo "environment: the $1 router exited during startup"; return 1; }
    sleep 0.25
  done
  echo "environment: the $1 router never answered /health"; return 1
}
stop() {
  [ -n "$RUNNING" ] || return 0
  kill -TERM "$RUNNING" 2>/dev/null
  wait "$RUNNING" 2>/dev/null
  RUNNING=""
  sleep 0.5
}

ACCEPT='accept: application/json, text/event-stream'
capture() { # prefix
  curl -sS -m 15 -X POST "http://127.0.0.1:$PORT/mcp" -H 'content-type: application/json' \
    -H "$ACCEPT" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
    | grep '^data: ' | sed 's/^data: //' > "$WORK/$1.tools"
  curl -sS -m 10 "http://127.0.0.1:$PORT/usage?limit=10" > "$WORK/$1.usage"
}

echo "phase 1 — the reference writes the state, for real"
start ts || { tail -20 "$WORK/ts.stdout"; exit 2; }
TOKEN="$(cat "$HOME_DIR/control.token" 2>/dev/null)"
curl -fsS -m 30 -X POST -H "x-mcpr-token: $TOKEN" -H 'content-type: application/json' \
  "http://127.0.0.1:$PORT/servers/probe/reindex" >/dev/null 2>&1 || {
  echo "environment: the reference could not index the upstream"; exit 2; }
node "$REPO_ROOT/scripts/fixtures/call-through-router.mjs" "http://127.0.0.1:$PORT/mcp" ping >/dev/null 2>&1 || true
node "$REPO_ROOT/scripts/fixtures/call-through-router.mjs" "http://127.0.0.1:$PORT/mcp" echo >/dev/null 2>&1 || true
capture ts
stop

for file in servers.json manifest.json usage.jsonl usage-stats.json; do
  [ -s "$HOME_DIR/$file" ] || {
    echo "environment: the reference left no $file, so there is no inherited state to read"
    exit 2; }
  echo "  the reference left $file ($(wc -c <"$HOME_DIR/$file" | tr -d ' ') bytes)"
done

echo
echo "phase 2 — the Swift router is started on exactly those files, having written none of them"
start swift || { tail -20 "$WORK/swift.stdout"; exit 2; }
capture swift
stop

# `since` is stamped when a store is constructed, so two processes never agree on it; every other
# member of the usage body is inherited state.
strip_since() { python3 -c '
import json,sys
raw=sys.stdin.read().strip()
body=json.loads(raw) if raw else {}
body.pop("since", None)
print(json.dumps(body, sort_keys=False))
'; }

problems=""
diff "$WORK/ts.tools" "$WORK/swift.tools" >"$WORK/d.tools" 2>&1 \
  || problems="$problems tools/list:[$(head -4 "$WORK/d.tools" | tr '\n' ' ' | cut -c1-140)]"
diff <(strip_since <"$WORK/ts.usage") <(strip_since <"$WORK/swift.usage") >"$WORK/d.usage" 2>&1 \
  || problems="$problems /usage:[$(head -4 "$WORK/d.usage" | tr '\n' ' ' | cut -c1-140)]"

echo
if [ -z "$problems" ]; then
  echo "  ok   the Swift router served the same tool corpus and the same call history from the"
  echo "       reference's own files, having written none of them"
  record state state-ondisk-compat ok \
    "Swift served an identical tools/list and /usage from a home the reference wrote"
  echo
  echo "state: one-directional by design — TypeScript writes, Swift reads."
  exit 0
fi
echo "  FAIL the Swift router read the inherited state differently —$problems"
record state state-ondisk-compat fail "$problems"
echo
echo "state: one-directional by design — TypeScript writes, Swift reads."
exit 1
