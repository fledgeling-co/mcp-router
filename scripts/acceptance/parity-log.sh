#!/usr/bin/env bash
#
# R2-R — the log lane.
#
# The brief's fifth corpus. The reference writes `router.log` while serving; until this item there
# was no Swift process to write one, so `log-bytes` was blocked for want of a producer rather than
# for want of a comparison.
#
# One scripted session is driven at each router — start, index, call, call again, SIGTERM — and the
# two logs are diffed **line by line**, in order. What is normalised is a clock or a coordinate:
#   · the leading ISO timestamp;
#   · a measured duration (`ready in 103ms`, `0s alive`);
#   · absolute paths, because the two homes are two directories;
#   · the port.
# Everything else is compared as written: the level and its padding, the message text, the quoting,
# the `call(s)` plural, and the ORDER. A log whose lines are individually right and collectively out
# of order is a log nobody can diff, and the order caught a real defect on the first run — the Swift
# pool never emitted `upstream "x" ready in Nms` at all, because R2 declared the event and no process
# ever fired it.
#
# ROWS THIS LANE OWNS:  log: log-bytes
#
# CAVEAT, printed into the gate's report: a simultaneous two-router comparison of a real serving
# session, normalised only for clocks and paths.
#
# Exit codes: 0 agreed, 1 a mismatch, 2 the environment could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
PORT="${LOG_PORT:-8995}"
WORK="$(mktemp -d -t parity-log)"
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
    log/log-bytes) ;;
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

session() { # dir kind -> writes $dir/router.log
  local home="$1" kind="$2"
  mkdir -p "$home"
  echo "toolset" > "$home/toolset"
  cat > "$home/servers.json" <<JSON
{
  "mcpServers": {
    "probe": {
      "command": "node",
      "args": ["$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs", "stdio"],
      "env": { "FIXTURE_TOOLSET_FILE": "$home/toolset" }
    }
  }
}
JSON
  if [ "$kind" = ts ]; then
    MCP_ROUTER_HOME="$home" node "$REPO_ROOT/dist/index.js" serve --port "$PORT" --idle-ms 2000 \
      >"$home/stdout" 2>&1 &
  else
    MCP_ROUTER_HOME="$home" "$SWIFT_BIN" serve --port "$PORT" --idle-ms 2000 \
      >"$home/stdout" 2>&1 &
  fi
  RUNNING=$!
  for _ in $(seq 1 80); do
    curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
    kill -0 "$RUNNING" 2>/dev/null || { echo "environment: the $kind router exited during startup"; return 1; }
    sleep 0.25
  done
  local token; token="$(cat "$home/control.token" 2>/dev/null)"
  curl -fsS -m 30 -X POST -H "x-mcpr-token: $token" -H 'content-type: application/json' \
    "http://127.0.0.1:$PORT/servers/probe/reindex" >/dev/null 2>&1
  # Waited past the idle window BEFORE the call as well as after it. Without the first wait the
  # sequence depends on how long `call-through-router.mjs` takes to boot — under the window the
  # child is reused and the log reads "after 2 call(s)", over it the child is reaped and respawned
  # and the log carries a second spawn/ready pair. Both are correct behaviour; only one is
  # deterministic, and a lane that flakes between two correct answers is worse than no lane.
  sleep 4
  node "$REPO_ROOT/scripts/fixtures/call-through-router.mjs" \
    "http://127.0.0.1:$PORT/mcp" ping >/dev/null 2>&1 || true
  sleep 4   # past the 2s idle window again, so the reaper's line is in the corpus too
  kill -TERM "$RUNNING" 2>/dev/null
  wait "$RUNNING" 2>/dev/null
  RUNNING=""
  sleep 0.5
  return 0
}

# Clocks and coordinates only.
normalise() {
  sed -e 's/^[0-9][0-9]*-[0-9][0-9]-[0-9][0-9]T[0-9:.]*Z/<ts>/' \
      -e 's/ready in [0-9][0-9]*ms/ready in <ms>ms/' \
      -e 's/[0-9][0-9]*s alive/<s>s alive/' \
      -e "s|$WORK/ts|<home>|g" -e "s|$WORK/swift|<home>|g" \
      -e "s|$REPO_ROOT|<repo>|g" \
      -e "s/127\.0\.0\.1:$PORT/127.0.0.1:<port>/g"
}

echo "driving one scripted session at each router on :$PORT"
session "$WORK/ts" ts || exit 2
session "$WORK/swift" swift || exit 2

[ -s "$WORK/ts/router.log" ] || { echo "environment: the reference wrote no router.log"; exit 2; }
[ -s "$WORK/swift/router.log" ] || {
  echo "the Swift router wrote no router.log at all"
  record log log-bytes fail "the Swift router wrote no router.log"
  exit 1
}

normalise <"$WORK/ts/router.log"    >"$WORK/ts.norm"
normalise <"$WORK/swift/router.log" >"$WORK/swift.norm"

echo
if diff "$WORK/ts.norm" "$WORK/swift.norm" >"$WORK/diff.txt" 2>&1; then
  lines="$(wc -l <"$WORK/ts.norm" | tr -d ' ')"
  echo "  ok   $lines log lines agree, in order"
  sed 's/^/       /' "$WORK/ts.norm"
  record log log-bytes ok "$lines lines agree in order, normalised only for timestamps, durations and paths"
  echo
  echo "log: a simultaneous two-router comparison of one scripted serving session."
  exit 0
fi
echo "  FAIL the two logs differ"
sed 's/^/       /' "$WORK/diff.txt"
record log log-bytes fail "$(head -8 "$WORK/diff.txt" | tr '\n' ' ' | cut -c1-200)"
echo
echo "log: a simultaneous two-router comparison of one scripted serving session."
exit 1
