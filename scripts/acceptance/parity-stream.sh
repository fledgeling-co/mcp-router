#!/usr/bin/env bash
#
# R2-R — the stream lane.
#
# `GET /usage/stream` is the one control route no lane has ever driven over a socket.
# `control-differential.sh` drives `ControlDiff`, an in-process oracle that cannot hold a
# connection open, so it prints the route informationally at :623-625 and records nothing. The
# manifest blocked the row on `D-l` for a stated reason: "the response body is an open stream, so
# there is no byte oracle to diff".
#
# That reason is true of the body as a WHOLE and false of the body's FRAMES. An SSE stream is a
# sequence of frames, each one complete when it arrives, and a frame is as diffable as any other
# body. This lane opens the stream at both routers, drives an identical call sequence at each, and
# diffs the frames that come back: the opening comment, one `data:` frame per usage record, and the
# heartbeat. What stays uncompared is the stream's END, because a stream that ends has failed.
#
# The reason this lane exists at all is not the row. `RouterService.usageStream` — the subscribe,
# the heartbeat `Task`, the `UnsubscribeBox`, `continuation.onTermination`, and `HTTPWire`'s
# `.chunks` body over a real socket for an UNBOUNDED response — was written by this item, compiled,
# linked, and never once executed against a client that holds a connection open. The MCP endpoint
# exercises `.chunks` for a stream that completes; nothing exercised one that does not. That is the
# same hole §9.1 of the evidence file found in the HTTP upstream clients, in the same item, and
# leaving it a second time having named it once would be indefensible.
#
# What is normalised, each a clock or a coordinate rather than a behaviour:
#   · `ts`        an ISO clock reading, per record.
#   · `ms`        a measured duration.
#   · `pid`       the process id of the caller; two curls are two processes.
#   · `cwd`/`project` the two homes are two directories.
#   · the port    two routers cannot share one.
# Nothing else is touched. Member order, field PRESENCE (an omitted optional is a real difference),
# the `ok` flag, `cold`, `err` text, the frame's `data: ` prefix and its blank-line terminator are
# all compared byte for byte.
#
# Empty is never a pass. Both sides must carry the opening comment and the expected number of
# `data:` frames before any diff is believed — two silent streams diff clean, and that is exactly
# how this row would come back a lie.
#
# ROWS THIS LANE OWNS. It writes results for this id and no other.
#   control: control-usage-stream
#
# Exit codes: 0 the frames agreed, 1 a mismatch, 2 the environment could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TS_PORT="${STREAM_TS_PORT:-8988}"
SWIFT_PORT="${STREAM_SWIFT_PORT:-8989}"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
WORK="$(mktemp -d -t parity-stream)"
RESULTS="${PARITY_RESULTS:-}"
TS_PID=""
SWIFT_PID=""
TS_READER=""
SWIFT_READER=""

MAIN_PID=$$
cleanup() {
  [ "$BASHPID" != "$MAIN_PID" ] && return 0
  [ -n "$TS_READER" ] && kill "$TS_READER" 2>/dev/null
  [ -n "$SWIFT_READER" ] && kill "$SWIFT_READER" 2>/dev/null
  [ -n "$TS_PID" ] && kill "$TS_PID" 2>/dev/null
  [ -n "$SWIFT_PID" ] && kill "$SWIFT_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

OWNED="control/control-usage-stream"

record() { # group id ok|fail detail
  [ -n "$RESULTS" ] || return 0
  case " $(echo $OWNED) " in
    *" $1/$2 "*) ;;
    *) echo "  LANE BUG: refusing to record $1/$2, which this lane does not own" >&2; return 1 ;;
  esac
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$RESULTS"
}

pass=0; fail=0
verdict() { # group id ok? message
  if [ "$3" = 1 ]; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$4"; record "$1" "$2" ok "$4"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n' "$4"; record "$1" "$2" fail "$4"
  fi
}

# --------------------------------------------------------------------------------------- environment
command -v node >/dev/null 2>&1 || { echo "environment: node is not installed"; exit 2; }
[ -f "$REPO_ROOT/dist/index.js" ] || {
  echo "environment: no built reference at dist/index.js. Run npm run build."; exit 2; }
[ -x "$SWIFT_BIN" ] || {
  echo "environment: no Swift router at ${SWIFT_BIN#"$REPO_ROOT/"}."
  echo "             Build it with: cd app && swift build"; exit 2; }
for port in "$TS_PORT" "$SWIFT_PORT"; do
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "environment: something is already listening on :$port. This harness never shares a port"
    echo "             and never touches the router on 8975/8976."; exit 2
  fi
done

# --------------------------------------------------------------------------------------- two homes
for side in ts swift; do
  mkdir -p "$WORK/$side"
  echo "toolset" > "$WORK/$side/toolset"
  cat > "$WORK/$side/servers.json" <<JSON
{
  "mcpServers": {
    "probe": {
      "command": "node",
      "args": ["$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs", "stdio"],
      "env": { "FIXTURE_TOOLSET_FILE": "$WORK/$side/toolset" }
    }
  }
}
JSON
done

MCP_ROUTER_HOME="$WORK/ts" node "$REPO_ROOT/dist/index.js" serve \
  --port "$TS_PORT" --idle-ms 120000 >"$WORK/ts.log" 2>&1 &
TS_PID=$!
MCP_ROUTER_HOME="$WORK/swift" "$SWIFT_BIN" serve \
  --port "$SWIFT_PORT" --idle-ms 120000 >"$WORK/swift.log" 2>&1 &
SWIFT_PID=$!

wait_ready() { # port pid label
  for _ in $(seq 1 120); do
    curl -fsS -m 2 "http://127.0.0.1:$1/health" >/dev/null 2>&1 && return 0
    kill -0 "$2" 2>/dev/null || { echo "environment: the $3 router exited during startup"; return 1; }
    sleep 0.25
  done
  echo "environment: the $3 router never answered /health"; return 1
}
wait_ready "$TS_PORT" "$TS_PID" reference || { tail -20 "$WORK/ts.log"; exit 2; }
wait_ready "$SWIFT_PORT" "$SWIFT_PID" Swift || { tail -20 "$WORK/swift.log"; exit 2; }

TS_TOKEN="$(cat "$WORK/ts/control.token" 2>/dev/null)"
SWIFT_TOKEN="$(cat "$WORK/swift/control.token" 2>/dev/null)"
[ -n "$TS_TOKEN" ] && [ -n "$SWIFT_TOKEN" ] || {
  echo "environment: a router did not write a control token"; exit 2; }

for side in ts:$TS_PORT:$TS_TOKEN swift:$SWIFT_PORT:$SWIFT_TOKEN; do
  name="${side%%:*}"; rest="${side#*:}"; port="${rest%%:*}"; token="${rest##*:}"
  curl -fsS -m 30 -X POST -H "x-mcpr-token: $token" -H 'content-type: application/json' \
    "http://127.0.0.1:$port/servers/probe/reindex" >"$WORK/reindex-$name.json" 2>&1 || {
    echo "environment: probe could not be indexed on $name"; cat "$WORK/reindex-$name.json"; exit 2; }
done

echo
echo "R2-R — GET /usage/stream, driven over a socket at both routers"

# ------------------------------------------------------------------------------------- the readers
# `curl -N` disables buffering, so a frame reaches the file when it reaches the socket. The reader
# is what makes this a stream test rather than a request test: it holds the connection open across
# every call below, exactly as the Mac app's ControlEventStream does.
open_stream() { # port token outfile
  curl -sS -N --no-buffer -m 120 -H "x-mcpr-token: $2" \
    "http://127.0.0.1:$1/usage/stream" >"$3" 2>&1 &
  echo $!
}
TS_READER="$(open_stream "$TS_PORT" "$TS_TOKEN" "$WORK/ts.sse")"
SWIFT_READER="$(open_stream "$SWIFT_PORT" "$SWIFT_TOKEN" "$WORK/swift.sse")"

# The opening comment must ARRIVE. A stream whose first frame is buffered until the body ends is a
# stream the app cannot use, and it is indistinguishable from a working one in a diff taken later.
# `grep -c` prints its count AND exits 1 when the count is zero, so a `|| echo 0` fallback appends a
# second number and every arithmetic test downstream fails with "integer expected". The count is
# read on its own and the exit status discarded.
count_of() { # pattern file
  local n; n="$(grep -c -- "$1" "$2" 2>/dev/null)"; printf '%s' "${n:-0}"
}
await() { # file pattern count seconds label
  local waited=0
  while [ "$waited" -lt "$(( $4 * 4 ))" ]; do
    if [ "$(count_of "$2" "$1")" -ge "$3" ]; then return 0; fi
    sleep 0.25; waited=$((waited + 1))
  done
  return 1
}

opened=1
for side in ts swift; do
  if ! await "$WORK/$side.sse" '^: connected' 1 15 "opening frame"; then
    opened=0
    echo "  the $side router never delivered its opening comment within 15s"
    echo "  --- what did arrive ---"; cat "$WORK/$side.sse" | head -5
  fi
done
if [ "$opened" != 1 ]; then
  verdict control control-usage-stream 0 \
    "a router never delivered the SSE opening comment, so no frames could be compared"
  echo; echo "compared 0 rows: 0 ok, 1 failed"; exit 1
fi
echo "  both routers delivered the opening comment while the connection stayed open"

# -------------------------------------------------------------------------------- identical traffic
# Three calls, chosen so the record shape varies: a plain success, a second success that is NOT a
# cold start (so `cold` must flip), and a failure that must carry `ok:false` and an `err`.
ACCEPT='accept: application/json, text/event-stream'
call() { # port body
  curl -sS -m 30 -X POST -H "$ACCEPT" -H 'content-type: application/json' \
    -d "$2" "http://127.0.0.1:$1/mcp" >/dev/null 2>&1 || true
}
for port in "$TS_PORT" "$SWIFT_PORT"; do
  call "$port" '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"probe__echo","arguments":{"text":"one"}}}'
  call "$port" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"probe__echo","arguments":{"text":"two"}}}'
  call "$port" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"probe__nosuchtool","arguments":{}}}'
done

frames=1
for side in ts swift; do
  if ! await "$WORK/$side.sse" '^data: ' 3 20 "data frames"; then
    frames=0
    echo "  the $side router delivered $(count_of '^data: ' "$WORK/$side.sse") of 3 data frames in 20s"
  fi
done
if [ "$frames" != 1 ]; then
  verdict control control-usage-stream 0 \
    "a router did not stream one frame per call: ts=$(count_of '^data: ' "$WORK/ts.sse") swift=$(count_of '^data: ' "$WORK/swift.sse") of 3"
  echo; echo "compared 0 rows: 0 ok, 1 failed"; exit 1
fi
echo "  both routers streamed one frame per call, as the calls happened"

# ------------------------------------------------------------------------------------- the heartbeat
# 25s on both sides. Waited for rather than asserted by construction: a heartbeat that is coded and
# never fires is the failure this frame exists to prevent, and it is invisible to a reader of source.
beat=1
for side in ts swift; do
  await "$WORK/$side.sse" '^: ping' 1 35 "heartbeat" || {
    beat=0; echo "  the $side router sent no heartbeat within 35s of a 25s interval"; }
done
if [ "$beat" = 1 ]; then
  echo "  both routers sent the 25s heartbeat on the open connection"
else
  verdict control control-usage-stream 0 \
    "a router's 25s heartbeat never fired on an open stream"
  echo; echo "compared 0 rows: 0 ok, 1 failed"; exit 1
fi

# ------------------------------------------------------------------------------------------ the diff
normalise() {
  sed -e 's/"ts":"[^"]*"/"ts":"<clock>"/g' \
      -e 's/"ms":[0-9.]*/"ms":<measured>/g' \
      -e 's/"pid":[0-9]*/"pid":<pid>/g' \
      -e "s|$WORK/ts|<home>|g" -e "s|$WORK/swift|<home>|g" \
      -e "s/127\.0\.0\.1:$TS_PORT/127.0.0.1:<port>/g" \
      -e "s/127\.0\.0\.1:$SWIFT_PORT/127.0.0.1:<port>/g"
}

# Only the frames, in order, and only up to the heartbeat — beyond it the two streams are being
# compared on when a 25s timer landed relative to a `kill`, which is scheduling, not protocol.
frames_of() { sed -n '1,/^: ping$/p' "$1" | grep -E '^(: connected|data: |: ping)' | normalise; }

frames_of "$WORK/ts.sse" > "$WORK/ts.frames"
frames_of "$WORK/swift.sse" > "$WORK/swift.frames"

# Empty is never a pass, asserted after normalisation as well as before it: a sed that ate the body
# would otherwise leave two empty files that diff clean.
ts_lines="$(wc -l < "$WORK/ts.frames" | tr -d ' ')"
swift_lines="$(wc -l < "$WORK/swift.frames" | tr -d ' ')"
if [ "$ts_lines" -lt 5 ] || [ "$swift_lines" -lt 5 ]; then
  verdict control control-usage-stream 0 \
    "normalisation left too few frames to be a comparison: ts=$ts_lines swift=$swift_lines, wanted the opening comment, 3 data frames and a heartbeat"
  echo; echo "compared 0 rows: 0 ok, 1 failed"; exit 1
fi

if diff "$WORK/ts.frames" "$WORK/swift.frames" > "$WORK/diff.txt" 2>&1; then
  verdict control control-usage-stream 1 \
    "GET /usage/stream — $ts_lines frames diffed byte for byte on an open connection (opening comment, 3 records, heartbeat)"
else
  echo "  --- reference vs Swift, frame by frame ---"
  sed 's/^/    /' "$WORK/diff.txt" | head -30
  verdict control control-usage-stream 0 \
    "the streamed frames differ: $(head -4 "$WORK/diff.txt" | tr '\n' ' ')"
fi

# --------------------------------------------------------------------- the reader going away
# `onTermination` is the only cancellation channel the Swift stream has: it unsubscribes from the
# usage store and cancels the heartbeat task. If it leaked, or if it took the router with it, the
# router would stop answering. Closing the reader and re-probing is what proves it did neither.
kill "$TS_READER" 2>/dev/null; kill "$SWIFT_READER" 2>/dev/null
TS_READER=""; SWIFT_READER=""
sleep 1
alive=1
for side in ts:$TS_PORT swift:$SWIFT_PORT; do
  port="${side##*:}"
  curl -fsS -m 5 "http://127.0.0.1:$port/health" >/dev/null 2>&1 || {
    alive=0; echo "  the ${side%%:*} router stopped answering after its stream reader disconnected"; }
done
if [ "$alive" = 1 ]; then
  echo "  both routers still served /health after the reader disconnected — the subscription and"
  echo "  the heartbeat were released without taking the process with them"
else
  echo "  NOTE: a router died when its reader went away. Reported here; the row's verdict above"
  echo "        stands on the frame comparison."
fi

echo
echo "compared $((pass + fail)) rows: $pass ok, $fail failed"
[ "$fail" -gt 0 ] && exit 1
exit 0
