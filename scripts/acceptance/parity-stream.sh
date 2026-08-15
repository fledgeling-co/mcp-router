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
# ---------------------------------------------------------------------------------------------
# P3 CONNECTED THIS LANE TO THE GATE AND WIDENED WHAT IT COMPARES.
#
# The lane above was written, was correct as far as it went, and `parity-gate.sh` never ran it:
# `stream` was absent from its `LANES` list, so the script sat on disk being dispatched by nothing
# while the row stayed blocked under a note about SSE that R2-R had already made untrue. The gate's
# missing-script guard only fires for a lane it was ASKED to run, so a lane nobody names produces
# no result, no environment failure and no complaint.
#
# Four things the row claims and this lane did not compare, each now its own verdict:
#
#   · THE RESPONSE HEAD. Nothing looked at the status line or a single header on this route —
#     `cache-control: no-store` and `connection: keep-alive` were asserted nowhere. The manifest
#     note said framing was "reported"; framing agreement is not body parity, and it was not even
#     framing agreement.
#   · EVERY LINE. Frames were extracted with a grep for three line kinds, which deleted the BLANK
#     LINES that terminate each SSE frame — the very thing the paragraph below claimed was compared
#     byte for byte — and would equally have deleted an `event:`, `id:` or `retry:` line.
#   · A LATE SUBSCRIBER. Every assertion measured a reader that connected before any call. A port
#     that replayed history to a new subscriber would double every record in an app that
#     reconnects and would pass every line of this lane as it stood.
#   · THE CONNECTION STILL BEING OPEN. The lane killed its readers without ever establishing they
#     were alive, so a router that closed the stream after the last record passed.
#
# What is normalised, each a clock or a coordinate rather than a behaviour:
#   · `ts`        an ISO clock reading, per record.
#   · `ms`        a measured duration.
#   · `pid`       the process id of the caller; two curls are two processes.
#   · `cwd`/`project` the two homes are two directories.
#   · the port    two routers cannot share one.
#   · `Date`      in the response head, and nothing else in it. Measured rather than allowlisted:
#                 both routers send the same five headers in the same order.
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
# Exit codes: 0 every dimension agreed, 1 a mismatch, 2 the environment could not run.

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
TS_LATE=""
SWIFT_LATE=""

MAIN_PID=$$
cleanup() {
  [ "$BASHPID" != "$MAIN_PID" ] && return 0
  for reader in "$TS_READER" "$SWIFT_READER" "$TS_LATE" "$SWIFT_LATE"; do
    [ -n "$reader" ] && kill "$reader" 2>/dev/null
  done
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
open_stream() { # port token outfile headerfile
  curl -sS -N --no-buffer -m 180 -D "$4" -H "x-mcpr-token: $2" \
    "http://127.0.0.1:$1/usage/stream" >"$3" 2>&1 &
  echo $!
}
TS_READER="$(open_stream "$TS_PORT" "$TS_TOKEN" "$WORK/ts.sse" "$WORK/ts.head")"
SWIFT_READER="$(open_stream "$SWIFT_PORT" "$SWIFT_TOKEN" "$WORK/swift.sse" "$WORK/swift.head")"

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

# ------------------------------------------------------------------------------------ the response head
# The manifest's note said framing was "reported" and not compared, and that was true: no lane
# looked at the status line or a single header on this route. `content-type: text/event-stream`,
# `cache-control: no-store` and `connection: keep-alive` are the three the handler sets
# (control.ts:456-459), and a stream that arrives without them is one a browser or a proxy will
# buffer or cache — invisible in a body diff and fatal in the app.
#
# `Date` is a clock and is the only substitution. MEASURED before this was written, rather than
# allowlisted defensively: on both routers the head is
#     HTTP/1.1 200 OK · content-type · cache-control · connection · Date · Transfer-Encoding
# in that order, byte-identical apart from the second in `Date`. So this is a full-head comparison,
# not three cherry-picked headers, and the three are ALSO asserted present by name so that a future
# node adding a header fails with a sentence rather than with a diff nobody can read.
head_of() { tr -d '\r' < "$1" | sed -e 's/^Date: .*/Date: <clock>/'; }
head_of "$WORK/ts.head" > "$WORK/ts.head.norm"
head_of "$WORK/swift.head" > "$WORK/swift.head.norm"

head_ok=1
for side in ts swift; do
  for want in '^HTTP/1.1 200 OK$' '^content-type: text/event-stream$' \
              '^cache-control: no-store$' '^connection: keep-alive$'; do
    grep -qE "$want" "$WORK/$side.head.norm" || {
      head_ok=0; echo "  the $side head is missing $want"; }
  done
done
if [ "$head_ok" = 1 ] && diff "$WORK/ts.head.norm" "$WORK/swift.head.norm" > "$WORK/head.diff" 2>&1; then
  verdict control control-usage-stream 1 \
    "the response head — status line and every header — is byte-identical on both routers, Date aside"
else
  echo "  --- reference vs Swift, response head ---"
  sed 's/^/    /' "$WORK/head.diff" 2>/dev/null | head -20
  verdict control control-usage-stream 0 \
    "the SSE response heads differ: $(head -4 "$WORK/head.diff" 2>/dev/null | tr '\n' ' ')"
fi

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
#
# EVERY LINE, and the change is the point. This read
#     … | grep -E '^(: connected|data: |: ping)'
# which dropped any line that was not one of those three kinds — so the BLANK LINES that terminate
# each SSE frame were filtered out before the diff, and so would be an `event:`, `id:` or `retry:`
# line. The header comment above claimed the blank-line terminator was "compared byte for byte"
# and it was being deleted two steps earlier. A frame delimiter is not decoration: without it a
# client reads the whole stream as one unterminated frame, and this lane called that parity.
frames_of() { sed -n '1,/^: ping$/p' "$1" | tr -d '\r' | normalise; }

frames_of "$WORK/ts.sse" > "$WORK/ts.frames"
frames_of "$WORK/swift.sse" > "$WORK/swift.frames"

# An unexpected line KIND is named rather than left to a diff, and it is a failure even when both
# sides produce it: two routers agreeing on a frame shape this lane was never told about is a
# change to the protocol, not a pass.
for side in ts swift; do
  # The alternation carries no EMPTY branch and the blank line is its own pattern. Written as
  # `(…|…|)$` it is an empty sub-expression, which BSD grep REFUSES: it printed
  # "grep: empty (sub)expression" to stderr, matched nothing, and left `unexpected` empty — so the
  # check reported clean on every input it could ever be given. A guard that cannot fail is the
  # thing this whole lane exists to refuse, and it shipped inside the fix for another one.
  unexpected="$(grep -vE '^(: connected|: ping|data: .*)$|^$' "$WORK/$side.frames" | head -3)"
  if [ -n "$unexpected" ]; then
    verdict control control-usage-stream 0 \
      "the $side stream carried a line kind this lane does not recognise: $(printf '%s' "$unexpected" | head -1)"
    echo; echo "compared $((pass + fail)) rows: $pass ok, $fail failed"; exit 1
  fi
done

# Empty is never a pass, asserted after normalisation as well as before it: a sed that ate the body
# would otherwise leave two empty files that diff clean.
ts_lines="$(wc -l < "$WORK/ts.frames" | tr -d ' ')"
swift_lines="$(wc -l < "$WORK/swift.frames" | tr -d ' ')"
if [ "$ts_lines" -lt 9 ] || [ "$swift_lines" -lt 9 ]; then
  verdict control control-usage-stream 0 \
    "normalisation left too few frames to be a comparison: ts=$ts_lines swift=$swift_lines, wanted the opening comment, 3 data frames, a heartbeat and each one's blank terminator"
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

# --------------------------------------------------------------- a subscriber that joins late
# THE DIMENSION NO ASSERTION ABOVE CAN SEE. Every check so far measures a reader that connected
# before any call happened. The reference's stream carries no history — it subscribes and nothing
# more (control.ts:462) — so a port that replayed the log to a new subscriber would double every
# record in an app that reconnects, and would pass every line of this lane as written.
#
# The assertion is ABSOLUTE before it is differential, deliberately: two routers that both replay
# diff clean, so "no backlog" is asserted on each side as a count of zero rather than as an
# agreement. Only then is the one new record compared.
echo
echo "  a second reader, joining after three records already exist"
TS_LATE="$(open_stream "$TS_PORT" "$TS_TOKEN" "$WORK/ts.late" "$WORK/ts.late.head")"
SWIFT_LATE="$(open_stream "$SWIFT_PORT" "$SWIFT_TOKEN" "$WORK/swift.late" "$WORK/swift.late.head")"

late_ok=1
for side in ts swift; do
  await "$WORK/$side.late" '^: connected' 1 15 "late opening frame" || {
    late_ok=0; echo "  the $side router's late reader never got its opening comment"; }
done

if [ "$late_ok" = 1 ]; then
  # Give a replay time to arrive. A snapshot taken the instant the stream opens would read as
  # "no backlog" on a router that replays 50ms later, which is the check passing by being early.
  sleep 2
  for side in ts swift; do
    backlog="$(count_of '^data: ' "$WORK/$side.late")"
    if [ "$backlog" != 0 ]; then
      late_ok=0
      echo "  the $side router replayed $backlog record(s) to a subscriber that joined afterwards"
    fi
  done
fi

# ONE MORE CALL AT EACH ROUTER, DRIVEN UNCONDITIONALLY, and the unconditionality is the point.
#
# This used to sit inside `if [ "$late_ok" = 1 ]`, which coupled two independent verdicts: a router
# that replayed its backlog failed the check above, the fourth record was then never driven, and
# the still-open verdict below went red because no fourth record existed rather than because a
# stream had ended. One defect, two red verdicts, and the second one meaningless — which also means
# a mutation aimed at replay could never show that everything else still held.
#
# It does double duty: the late reader must receive exactly this one record, and the ORIGINAL
# reader must receive it too, which is what proves the first connection is still open and still
# delivering after its heartbeat.
for port in "$TS_PORT" "$SWIFT_PORT"; do
  call "$port" '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"probe__echo","arguments":{"text":"four"}}}'
done

if [ "$late_ok" = 1 ]; then
  for side in ts swift; do
    await "$WORK/$side.late" '^data: ' 1 20 "late data frame" || {
      late_ok=0; echo "  the $side router's late reader never received the record driven after it joined"; }
  done
fi

if [ "$late_ok" = 1 ]; then
  for side in ts swift; do
    delivered="$(count_of '^data: ' "$WORK/$side.late")"
    if [ "$delivered" != 1 ]; then
      late_ok=0
      echo "  the $side router's late reader holds $delivered data frames where exactly 1 was driven"
    fi
  done
fi

if [ "$late_ok" = 1 ]; then
  sed -n '1,$p' "$WORK/ts.late"    | tr -d '\r' | normalise > "$WORK/ts.late.frames"
  sed -n '1,$p' "$WORK/swift.late" | tr -d '\r' | normalise > "$WORK/swift.late.frames"
  # The same line-kind check the original stream gets. Without it the late stream was a raw diff,
  # so two routers that both emitted an `event:` or `id:` line only to late subscribers agreed with
  # each other and neither was named — the check existed on one of the two streams this lane reads.
  for side in ts swift; do
    unexpected="$(grep -vE '^(: connected|: ping|data: .*)$|^$' "$WORK/$side.late.frames" | head -3)"
    if [ -n "$unexpected" ]; then
      late_ok=0
      echo "  the $side late stream carried a line kind this lane does not recognise: $(printf '%s' "$unexpected" | head -1)"
    fi
  done
fi

if [ "$late_ok" = 1 ]; then
  if diff "$WORK/ts.late.frames" "$WORK/swift.late.frames" > "$WORK/late.diff" 2>&1; then
    verdict control control-usage-stream 1 \
      "a late subscriber received no backlog at either router and exactly the one record driven after it joined, byte for byte"
  else
    echo "  --- reference vs Swift, late subscriber ---"
    sed 's/^/    /' "$WORK/late.diff" | head -20
    verdict control control-usage-stream 0 \
      "the late subscribers' frames differ: $(head -4 "$WORK/late.diff" | tr '\n' ' ')"
  fi
else
  verdict control control-usage-stream 0 \
    "a late subscriber did not get the reference's contract — see the lines above"
fi

# ------------------------------------------------------------- the first connection is still open
# `curl` exits when the server closes the connection, so a live pid means the stream did not end
# itself. Checked BEFORE the teardown, because killing a reader that had already exited proves
# nothing and the previous form of this lane did exactly that. The stronger half is above: the
# original reader had to carry the fourth record, which a closed connection cannot do.
still_open=1
for pair in "ts:$TS_READER" "swift:$SWIFT_READER"; do
  pid="${pair##*:}"
  kill -0 "$pid" 2>/dev/null || {
    still_open=0; echo "  the ${pair%%:*} router's stream had already ended before it was torn down"; }
done
for side in ts swift; do
  if [ "$(count_of '^data: ' "$WORK/$side.sse")" -lt 4 ]; then
    still_open=0
    echo "  the $side router's original reader stopped delivering: $(count_of '^data: ' "$WORK/$side.sse") of 4 records"
  fi
done
# THE FOURTH RECORD IS COMPARED, not counted. `frames_of` cuts the byte diff at the first `: ping`,
# so nothing above this line ever looks at what the ORIGINAL readers received after the heartbeat —
# the check was `count >= 4`, which two routers that both stayed open and both emitted some fourth
# `data:` line of any content whatsoever would pass together. The late readers' copy of this record
# is diffed; the original readers' copy was not, and post-heartbeat delivery on a long-lived
# connection is the one thing this verdict exists to speak for.
if [ "$still_open" = 1 ]; then
  for side in ts swift; do
    grep '^data: ' "$WORK/$side.sse" | tail -1 | tr -d '\r' | normalise > "$WORK/$side.fourth"
  done
  if [ ! -s "$WORK/ts.fourth" ] || [ ! -s "$WORK/swift.fourth" ]; then
    still_open=0
    echo "  a router's original reader holds no final data frame to compare"
  elif ! diff "$WORK/ts.fourth" "$WORK/swift.fourth" > "$WORK/fourth.diff" 2>&1; then
    still_open=0
    echo "  --- reference vs Swift, the record delivered after the heartbeat ---"
    sed 's/^/    /' "$WORK/fourth.diff" | head -10
  fi
fi
if [ "$still_open" = 1 ]; then
  verdict control control-usage-stream 1 \
    "both original connections were still open after the heartbeat and delivered the fourth record byte for byte — the stream does not end itself and does not degrade once it is long-lived"
else
  verdict control control-usage-stream 0 \
    "a stream ended on its own, or stopped delivering what the other one delivered, after its heartbeat"
fi

# --------------------------------------------------------------------- the reader going away
# `onTermination` is the only cancellation channel the Swift stream has: it unsubscribes from the
# usage store and cancels the heartbeat task. If it leaked, or if it took the router with it, the
# router would stop answering. Closing the reader and re-probing is what proves it did neither.
kill "$TS_LATE" 2>/dev/null; kill "$SWIFT_LATE" 2>/dev/null
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
