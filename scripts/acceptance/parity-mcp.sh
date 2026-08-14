#!/usr/bin/env bash
#
# R2-R — the mcp lane.
#
# The corpus R4 could not compare at all: `POST /mcp`, `tools/list`, `tools/call`, `/health` and
# `/status`, plus the two pool decisions that need traffic arriving at a **Swift** endpoint.
#
# Both routers are started, on **copies** of one scratch home, and every comparison below drives the
# same request at each and diffs the answer. Nothing here compares a router against a recording, a
# fixture, or a belief of ours: the two sides are two live processes.
#
# What is normalised, and why each one is a clock or a coordinate rather than a behaviour:
#   · `Date:`      a clock reading.
#   · `port`       two routers cannot share a port, so `/status` differs by construction.
#   · `idleSec`    a clock reading.
#   · absolute paths in a body — the two homes are two directories.
# Nothing else is normalised. Bodies are diffed **byte for byte**, envelope member order included,
# because that order (`result, jsonrpc, id`) is the divergence most likely to occur and sorting keys
# is exactly what would hide it.
#
# Chunk boundaries are deliberately NOT compared. The reference's are chosen by Node's write
# scheduler, not by its code, so a byte diff of the raw chunked stream would be comparing Node's I/O
# scheduling rather than the protocol. The SSE stream is de-framed first and its events compared.
#
# ROWS THIS LANE OWNS. It writes results for these ids and no others; the assertion below refuses
# anything else, because the gate matches on (group, id) and binds no script to either — authorship
# has to be closed from the lane's side or it is not closed at all.
#   mcp:        mcp-endpoint mcp-tools-list mcp-tools-call mcp-health mcp-status
#   pool:       pool-p4 pool-reap-traffic
#   divergence: div-r2r-d8
#
# CAVEAT, printed into the gate's own report because the gate's caveat block names only the three
# older lanes and this item may not edit it:
#   this lane is a simultaneous two-router wire comparison — the strongest kind in this gate — for
#   every row EXCEPT div-r2r-d8, which is an assertion in both directions rather than an agreement.
#
# Exit codes: 0 every comparison agreed, 1 a mismatch, 2 the environment could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TS_PORT="${MCP_TS_PORT:-8992}"
SWIFT_PORT="${MCP_SWIFT_PORT:-8993}"
# A third router, used by BOTH sides as an HTTP upstream. Without it the HTTP client half of this
# port is compiled and never run: every other lane seeds stdio upstreams only, so `open()`, the SSE
# refusal, the 401 challenge, `listTools` and `callTool` on an HTTP session are all unexecuted. A
# reference router IS an MCP server over HTTP, which makes it the honest upstream to point at.
HUB_PORT="${MCP_HUB_PORT:-8998}"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
WORK="$(mktemp -d -t parity-mcp)"
RESULTS="${PARITY_RESULTS:-}"
TS_PID=""
SWIFT_PID=""
HUB_PID=""

MAIN_PID=$$
cleanup() {
  [ "$BASHPID" != "$MAIN_PID" ] && return 0
  [ -n "$TS_PID" ] && kill "$TS_PID" 2>/dev/null
  [ -n "$SWIFT_PID" ] && kill "$SWIFT_PID" 2>/dev/null
  [ -n "$HUB_PID" ] && kill "$HUB_PID" 2>/dev/null
  # WAIT for each one to actually go. `kill` only asks; it returns long before the process has run
  # its shutdown and released the port. Without this the lane can exit while a router still holds
  # its listener, and the NEXT run of this lane refuses to start with "something is already
  # listening" — which the self-test scores as "could not run", inconclusive rather than a pass.
  # Observed: two consecutive mcp checks both exited 2 because the first run's hub outlived it.
  [ -n "$TS_PID" ] && wait "$TS_PID" 2>/dev/null
  [ -n "$SWIFT_PID" ] && wait "$SWIFT_PID" 2>/dev/null
  [ -n "$HUB_PID" ] && wait "$HUB_PID" 2>/dev/null
  rm -rf "$WORK"
  return 0
}
trap cleanup EXIT

# The ids this lane is allowed to speak for, as (group, id) pairs. A lane that can write any row
# anywhere is a lane that can satisfy the gate without testing anything.
OWNED="mcp/mcp-endpoint mcp/mcp-tools-list mcp/mcp-tools-call mcp/mcp-health mcp/mcp-status
pool/pool-p4 pool/pool-reap-traffic divergence/div-r2r-d8"

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
for port in "$TS_PORT" "$SWIFT_PORT" "$HUB_PORT"; do
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "environment: something is already listening on :$port. This harness never shares a port"
    echo "             and never touches the router on 8975/8976."; exit 2
  fi
done

# --------------------------------------------------------------------------------------- two homes
# One declaration, copied into two directories. The copies are what make the comparison fair: a
# single shared home would let whichever router indexed first decide what the other served.
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
    },
    "slow": {
      "command": "node",
      "args": ["$REPO_ROOT/scripts/fixtures/slow-mcp-server.mjs"]
    },
    "hub": {
      "type": "http",
      "url": "http://127.0.0.1:$HUB_PORT/mcp"
    }
  }
}
JSON
done

# The hub: a reference router with one stdio upstream, serving MCP over HTTP.
mkdir -p "$WORK/hub"
echo "toolset" > "$WORK/hub/toolset"
cat > "$WORK/hub/servers.json" <<JSON
{
  "mcpServers": {
    "probe": {
      "command": "node",
      "args": ["$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs", "stdio"],
      "env": { "FIXTURE_TOOLSET_FILE": "$WORK/hub/toolset" }
    }
  }
}
JSON
MCP_ROUTER_HOME="$WORK/hub" node "$REPO_ROOT/dist/index.js" serve \
  --port "$HUB_PORT" --idle-ms 120000 >"$WORK/hub.log" 2>&1 &
HUB_PID=$!

MCP_ROUTER_HOME="$WORK/ts" node "$REPO_ROOT/dist/index.js" serve \
  --port "$TS_PORT" --idle-ms 3000 >"$WORK/ts.log" 2>&1 &
TS_PID=$!
MCP_ROUTER_HOME="$WORK/swift" "$SWIFT_BIN" serve \
  --port "$SWIFT_PORT" --idle-ms 3000 >"$WORK/swift.log" 2>&1 &
SWIFT_PID=$!

wait_ready() { # port pid label
  for _ in $(seq 1 120); do
    curl -fsS -m 2 "http://127.0.0.1:$1/health" >/dev/null 2>&1 && return 0
    kill -0 "$2" 2>/dev/null || { echo "environment: the $3 router exited during startup"; return 1; }
    sleep 0.25
  done
  echo "environment: the $3 router never answered /health"; return 1
}
wait_ready "$HUB_PORT" "$HUB_PID" "HTTP upstream hub" || { tail -20 "$WORK/hub.log"; exit 2; }
hub_token="$(cat "$WORK/hub/control.token" 2>/dev/null)"
curl -fsS -m 30 -X POST -H "x-mcpr-token: $hub_token" -H 'content-type: application/json' \
  "http://127.0.0.1:$HUB_PORT/servers/probe/reindex" >/dev/null 2>&1 || {
  echo "environment: the hub could not index its own upstream"; exit 2; }

wait_ready "$TS_PORT" "$TS_PID" reference || { tail -20 "$WORK/ts.log"; exit 2; }
wait_ready "$SWIFT_PORT" "$SWIFT_PID" Swift || { tail -20 "$WORK/swift.log"; exit 2; }

# Both index their own copy, so both serve the same tool surface from their own manifest.
for side in ts:$TS_PORT swift:$SWIFT_PORT; do
  home="$WORK/${side%%:*}"; port="${side##*:}"
  token="$(cat "$home/control.token" 2>/dev/null)"
  for server in probe slow hub; do
    curl -fsS -m 30 -X POST -H "x-mcpr-token: $token" -H 'content-type: application/json' \
      "http://127.0.0.1:$port/servers/$server/reindex" >"$WORK/reindex-${side%%:*}-$server.json" 2>&1 || {
      echo "environment: $server could not be indexed on ${side%%:*}"
      cat "$WORK/reindex-${side%%:*}-$server.json"; exit 2; }
  done
done

# --------------------------------------------------------------------------------------- helpers
ACCEPT='accept: application/json, text/event-stream'

# The response head, with the two values that cannot agree normalised and nothing else touched.
# `Date` is a clock reading; the port is a coordinate, and two routers cannot share one.
normalise() { sed -e 's/^Date: .*/Date: <normalised>/' -e "s/127\.0\.0\.1:$TS_PORT/127.0.0.1:<port>/g" \
                  -e "s/127\.0\.0\.1:$SWIFT_PORT/127.0.0.1:<port>/g" \
                  -e "s|$WORK/ts|<home>|g" -e "s|$WORK/swift|<home>|g" ; }

# Issue one request against a port and write head and body to files.
issue() { # port outfile [curl args...]
  local port="$1" out="$2"; shift 2
  curl -sS -i -m 15 "${@//__PORT__/$port}" >"$out" 2>&1 || true
}

compare() { # group id label ts-file swift-file
  if diff <(normalise <"$4") <(normalise <"$5") >"$WORK/diff.txt" 2>&1; then
    verdict "$1" "$2" 1 "$3"
  else
    verdict "$1" "$2" 0 "$3 — $(head -6 "$WORK/diff.txt" | tr '\n' ' ' | cut -c1-160)"
  fi
}

echo "driving both routers: reference on :$TS_PORT, Swift on :$SWIFT_PORT"
echo

# --------------------------------------------------------------------------------------- mcp-health
issue "$TS_PORT"    "$WORK/health.ts"    "http://127.0.0.1:__PORT__/health"
issue "$SWIFT_PORT" "$WORK/health.swift" "http://127.0.0.1:__PORT__/health"
# Two identically-empty answers diff clean, so the answer has to BE something before it can agree.
for side in ts swift; do
  grep -q '"ok":true' "$WORK/health.$side" || {
    echo "environment: the $side router did not answer /health with a body"; exit 2; }
done
compare mcp mcp-health "GET /health — status, headers and body" "$WORK/health.ts" "$WORK/health.swift"

# --------------------------------------------------------------------------------------- mcp-endpoint
# The four framing refusals. Each is a request a hostile page or a broken client actually sends, and
# each has a distinct status the reference chose.
refuse() { # id label curl-args...
  local id="$1" label="$2"; shift 2
  issue "$TS_PORT"    "$WORK/$id.ts"    "$@"
  issue "$SWIFT_PORT" "$WORK/$id.swift" "$@"
  if diff <(normalise <"$WORK/$id.ts") <(normalise <"$WORK/$id.swift") >"$WORK/d.txt" 2>&1; then
    printf '  ok   %s\n' "$label"; return 0
  fi
  printf '  FAIL %s — %s\n' "$label" "$(head -6 "$WORK/d.txt" | tr '\n' ' ' | cut -c1-140)"
  return 1
}

endpoint_ok=1
refuse badhost "POST /mcp with a foreign Host is 403" \
  -X POST "http://127.0.0.1:__PORT__/mcp" -H 'content-type: application/json' -H "$ACCEPT" \
  -H 'Host: evil.example.com' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' || endpoint_ok=0
refuse badaccept "POST /mcp accepting only JSON is 406" \
  -X POST "http://127.0.0.1:__PORT__/mcp" -H 'content-type: application/json' \
  -H 'accept: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' || endpoint_ok=0
refuse notype "POST /mcp with no content-type is 415" \
  -X POST "http://127.0.0.1:__PORT__/mcp" -H "$ACCEPT" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' || endpoint_ok=0
refuse emptybody "POST /mcp with an empty body is 400 parse error" \
  -X POST "http://127.0.0.1:__PORT__/mcp" -H 'content-type: application/json' -H "$ACCEPT" || endpoint_ok=0
refuse notfound "an unknown path is 404 naming the MCP endpoint" \
  "http://127.0.0.1:__PORT__/nope" || endpoint_ok=0
verdict mcp mcp-endpoint "$endpoint_ok" "the framing refusals and the 404 agree on both routers"

# --------------------------------------------------------------------------------------- div-r2r-d8
# Asserted in BOTH directions: the reference must still answer 500/-32603 carrying V8's parser text,
# and Swift must still answer 500/-32603 with its own. Either side moving records `stale`, which is
# what stops a declared divergence quietly becoming an accidental one.
issue "$TS_PORT"    "$WORK/d8.ts"    -X POST "http://127.0.0.1:__PORT__/mcp" \
  -H 'content-type: application/json' -H "$ACCEPT" -d 'not json'
issue "$SWIFT_PORT" "$WORK/d8.swift" -X POST "http://127.0.0.1:__PORT__/mcp" \
  -H 'content-type: application/json' -H "$ACCEPT" -d 'not json'
ts_d8="$(grep -c '"code":-32603' "$WORK/d8.ts" || true)"
sw_d8="$(grep -c '"code":-32603' "$WORK/d8.swift" || true)"
ts_500="$(head -1 "$WORK/d8.ts" | grep -c ' 500 ' || true)"
sw_500="$(head -1 "$WORK/d8.swift" | grep -c ' 500 ' || true)"
ts_v8="$(grep -c 'Unexpected token' "$WORK/d8.ts" || true)"
# The Swift half is MEASURED rather than asserted: its message must carry the same
# `invalid JSON body: ` prefix the reference's does, and the two suffixes must actually DIFFER. A
# check that only looked at the status and the code would call the divergence intact on a Swift
# router that had silently stopped saying anything at all, and one that never compared the suffixes
# could not notice the divergence being fixed from either end.
ts_prefix="$(grep -c 'invalid JSON body: ' "$WORK/d8.ts" || true)"
sw_prefix="$(grep -c 'invalid JSON body: ' "$WORK/d8.swift" || true)"
ts_msg="$(sed -n 's/.*invalid JSON body: \(.*\)"}.*/\1/p' "$WORK/d8.ts" | head -1)"
sw_msg="$(sed -n 's/.*invalid JSON body: \(.*\)"}.*/\1/p' "$WORK/d8.swift" | head -1)"
if [ "$ts_d8" = 1 ] && [ "$sw_d8" = 1 ] && [ "$ts_500" = 1 ] && [ "$sw_500" = 1 ] \
   && [ "$ts_v8" = 1 ] && [ "$ts_prefix" = 1 ] && [ "$sw_prefix" = 1 ] \
   && [ -n "$sw_msg" ] && [ "$ts_msg" != "$sw_msg" ]; then
  verdict divergence div-r2r-d8 1 \
    "both answer 500/-32603 with the \"invalid JSON body: \" prefix; the parser text differs, as declared (ts=\"$(printf '%s' "$ts_msg" | cut -c1-40)\" swift=\"$(printf '%s' "$sw_msg" | cut -c1-40)\")"
else
  verdict divergence div-r2r-d8 0 \
    "stale: ts(500=$ts_500,-32603=$ts_d8,v8=$ts_v8,prefix=$ts_prefix) swift(500=$sw_500,-32603=$sw_d8,prefix=$sw_prefix) msg-differ=$([ "$ts_msg" != "$sw_msg" ] && echo yes || echo no) — the declared divergence no longer describes either side"
fi

# --------------------------------------------------------------------------------------- tools/list
# De-framed: the `data:` payload is what both routers author, and it is compared whole.
sse_body() { # file
  grep '^data: ' "$1" | sed 's/^data: //'
}
issue "$TS_PORT"    "$WORK/list.ts"    -X POST "http://127.0.0.1:__PORT__/mcp" \
  -H 'content-type: application/json' -H "$ACCEPT" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
issue "$SWIFT_PORT" "$WORK/list.swift" -X POST "http://127.0.0.1:__PORT__/mcp" \
  -H 'content-type: application/json' -H "$ACCEPT" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
# The HEAD as well as the payload. `sse_body` drops the status line, every header and the
# `event: message` line, so comparing only its output would leave the SSE framing uncompared on the
# two rows that carry the largest corpora.
sse_head() { sed -n '1,/^$/p' "$1"; }
sse_head "$WORK/list.ts"    | normalise > "$WORK/list.ts.head"
sse_head "$WORK/list.swift" | normalise > "$WORK/list.swift.head"
sse_body "$WORK/list.ts"    | normalise > "$WORK/list.ts.body"
sse_body "$WORK/list.swift" | normalise > "$WORK/list.swift.body"
[ -s "$WORK/list.ts.body" ] || { echo "environment: the reference returned no tools/list frame"; exit 2; }
[ -s "$WORK/list.swift.body" ] || {
  echo "the Swift router returned no tools/list frame at all"
  verdict mcp mcp-tools-list 0 "the Swift router returned no tools/list frame"
  }
list_ok=1
diff "$WORK/list.ts.head" "$WORK/list.swift.head" >/dev/null 2>&1 || {
  printf '  FAIL tools/list SSE head differs\n'; list_ok=0; }
diff "$WORK/list.ts.body" "$WORK/list.swift.body" >"$WORK/d.list" 2>&1 || {
  printf '  FAIL tools/list body — %s\n' "$(head -4 "$WORK/d.list" | tr '\n' ' ' | cut -c1-140)"
  list_ok=0; }
verdict mcp mcp-tools-list "$list_ok" \
  "tools/list — SSE head and the whole envelope, byte for byte"

# --------------------------------------------------------------------------------------- tools/call
call_ok=1
call_case() { # name payload
  issue "$TS_PORT"    "$WORK/call-$1.ts"    -X POST "http://127.0.0.1:__PORT__/mcp" \
    -H 'content-type: application/json' -H "$ACCEPT" -d "$2"
  issue "$SWIFT_PORT" "$WORK/call-$1.swift" -X POST "http://127.0.0.1:__PORT__/mcp" \
    -H 'content-type: application/json' -H "$ACCEPT" -d "$2"
  if diff <(sse_body "$WORK/call-$1.ts" | normalise) \
          <(sse_body "$WORK/call-$1.swift" | normalise) >"$WORK/d.txt" 2>&1; then
    printf '  ok   tools/call %s\n' "$1"; return 0
  fi
  printf '  FAIL tools/call %s — %s\n' "$1" "$(head -4 "$WORK/d.txt" | tr '\n' ' ' | cut -c1-140)"
  return 1
}
call_case ok '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"probe__ping","arguments":{}}}' || call_ok=0
call_case unnamespaced '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"bare","arguments":{}}}' || call_ok=0
call_case unknownserver '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"ghost__x","arguments":{}}}' || call_ok=0
call_case unknownmethod '{"jsonrpc":"2.0","id":9,"method":"nope/nope"}' || call_ok=0
call_case initialize '{"jsonrpc":"2.0","id":10,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"parity","version":"1"}}}' || call_ok=0
call_case ping '{"jsonrpc":"2.0","id":11,"method":"ping"}' || call_ok=0
# The seventh shape, and the only one that travels over an HTTP upstream rather than a stdio child:
# `hub` is a third router, so this call goes router -> HTTP -> router -> stdio. It is what exercises
# HTTPUpstreamTransport, HTTPUpstreamSession, and `listTools`/`callTool` on an HTTP session — none of
# which any other lane or test reaches, because every other upstream in this harness is stdio.
call_case httpupstream '{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"hub__probe__ping","arguments":{}}}' || call_ok=0
# And the tool must actually have answered, rather than both sides agreeing on an error.
if ! grep -q 'fixture:ping' "$WORK/call-httpupstream.swift"; then
  printf '  FAIL the HTTP upstream call did not reach the tool on the Swift side\n'
  call_ok=0
fi
verdict mcp mcp-tools-call "$call_ok" \
  "tools/call agrees across seven shapes, one of them routed through an HTTP upstream"

# --------------------------------------------------------------------------------------- mcp-status
# Driven identically first, so `callsServed` and `inFlight` are comparable rather than incidental.
sleep 4   # past the 3s idle window, so both have reaped and both report `idle`
issue "$TS_PORT"    "$WORK/status.ts"    "http://127.0.0.1:__PORT__/status"
issue "$SWIFT_PORT" "$WORK/status.swift" "http://127.0.0.1:__PORT__/status"
status_body() { sed -n '/^{/p' "$1" | python3 -c '
import json,sys
raw = sys.stdin.read().strip()
body = json.loads(raw) if raw else {}
# `port` differs by construction — two routers cannot share one — and `idleSec` is a clock reading.
body.pop("port", None)
for child in body.get("children", []):
    child.pop("idleSec", None)
print(json.dumps(body, sort_keys=False))
'; }
status_body "$WORK/status.ts"    > "$WORK/status.ts.body"
status_body "$WORK/status.swift" > "$WORK/status.swift.body"
compare mcp mcp-status "GET /status after an identical call sequence" \
  "$WORK/status.ts.body" "$WORK/status.swift.body"

# --------------------------------------------------------------------------------------- pool-p4
# A call outstanding is never reaped. The idle window is 3s and the tool sleeps 6s, so a reaper that
# ignores in-flight work closes the child underneath the call and the call fails.
outstanding() { # port
  node - "$1" <<'NODE'
const { Client } = await import('@modelcontextprotocol/sdk/client/index.js');
const { StreamableHTTPClientTransport } = await import('@modelcontextprotocol/sdk/client/streamableHttp.js');
const port = process.argv[2];
const client = new Client({ name: 'parity-p4', version: '1.0.0' }, { capabilities: {} });
await client.connect(new StreamableHTTPClientTransport(new URL(`http://127.0.0.1:${port}/mcp`)));
const result = await client.callTool({ name: 'slow__sleep', arguments: { ms: 6000 } });
process.stdout.write(result.isError ? 'ERROR' : 'OK');
await client.close();
NODE
}
ts_p4="$(outstanding "$TS_PORT" 2>/dev/null)"
sw_p4="$(outstanding "$SWIFT_PORT" 2>/dev/null)"
if [ "$ts_p4" = OK ] && [ "$sw_p4" = OK ]; then
  verdict pool pool-p4 1 "a 6s call survived a 3s idle window on both routers"
else
  verdict pool pool-p4 0 "a call outstanding was reaped — reference=$ts_p4 swift=$sw_p4"
fi

# --------------------------------------------------------------------------------------- reap under traffic
# burst, idle past the window, burst again — and the spawn/reap sequence read off /status compared as
# a sequence rather than as a final state, because a router that never reaps and one that reaps and
# reopens end in the same place.
# `unknown` is a FAILED READ, not an observed state, so it is retried rather than recorded. Under
# load — several fleet runners on one machine — the curl or the python3 spawn can miss its 5s
# budget, and a single miss turned `running,idle,running` into `running,unknown,unknown` and failed
# the row. Measured: this row passed, failed, then passed again across three runs with no code
# change between them. Retrying a failed read cannot mask a divergence, because a real divergence
# reports a definite state that differs; only an absent answer is retried, and an answer that never
# arrives still ends as `unknown` and still fails.
state_of() { # port -> state, or unknown after 5 tries
  local port="$1" s=""
  for _ in 1 2 3 4 5; do
    s="$(curl -fsS -m 5 "http://127.0.0.1:$port/servers/probe" 2>/dev/null \
         | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])' 2>/dev/null)"
    [ -n "$s" ] && { printf '%s' "$s"; return 0; }
    sleep 0.5
  done
  printf 'unknown'
}
sequence() { # port
  local out=""
  for _ in 1 2 3; do
    node "$REPO_ROOT/scripts/fixtures/call-through-router.mjs" \
      "http://127.0.0.1:$1/mcp" ping >/dev/null 2>&1 || true
  done
  out="$out$(state_of "$1")"
  sleep 5
  out="$out,$(state_of "$1")"
  node "$REPO_ROOT/scripts/fixtures/call-through-router.mjs" \
    "http://127.0.0.1:$1/mcp" ping >/dev/null 2>&1 || true
  out="$out,$(state_of "$1")"
  printf '%s' "$out"
}
ts_seq="$(sequence "$TS_PORT")"
sw_seq="$(sequence "$SWIFT_PORT")"
# A sequence containing ANY unknown is an unread state, not an agreement. Two sides that both failed
# to answer would otherwise diff clean and record a pass.
case "$ts_seq$sw_seq" in
  *unknown*) verdict pool pool-reap-traffic 0 \
      "a state read never answered after 5 tries: reference $ts_seq, Swift $sw_seq" ;;
  *) if [ "$ts_seq" = "$sw_seq" ]; then
       verdict pool pool-reap-traffic 1 "spawn/reap under live traffic: both reported $ts_seq"
     else
       verdict pool pool-reap-traffic 0 "reference reported $ts_seq, Swift reported $sw_seq"
     fi ;;
esac

echo
echo "mcp: $pass comparisons agreed, $fail did not"
echo "     Every row above except div-r2r-d8 is a SIMULTANEOUS two-router wire comparison — both"
echo "     routers live, the same request at each, bodies diffed byte for byte. div-r2r-d8 is an"
echo "     assertion in both directions rather than an agreement, and is labelled as such."
[ "$fail" -gt 0 ] && exit 1
exit 0
