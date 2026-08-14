#!/usr/bin/env bash
#
# R3 acceptance: the Swift control handler answers what the RUNNING TypeScript router answers.
#
# Every other check in this item compares the port to something we wrote. The 23 recorded fixtures
# are bytes captured once and committed; the vector corpus is generated from the reference but
# consumed by assertions we authored; the unit suite is our belief about the contract. All three
# agree with the model by construction, which is exactly the property that makes them unable to
# catch the reference moving. This runs `dist/` — the actual reference, now — issues the same
# request to both, and compares the bytes.
#
# Both sides are pointed at ONE state: the same servers.json, the same manifest, the same usage
# files. That is what makes a difference in the output attributable to the code rather than to the
# inputs, and it is why the router is started against a scratch MCPR home rather than the real one.
#
# The request matrix is not a happy path. It carries the acceptance-criteria rows (a described
# server, the servers envelope, the usage summary) and the proactive sweeps the skill calls for:
#   6b fault injection  — malformed JSON body, wrong content-type, absent method-appropriate token
#   6e data-shape stress — an oversized limit, a NaN limit, a negative limit, a huge path segment
#   6f security surface  — an unauthorized mutation, a percent-encoded path traversal, and the
#                          canary sweep that proves no env VALUE is reachable through the API
#
# Only requests whose answer is independent of live pool state are compared, and that is enforced
# rather than assumed: the upstreams are never called, so the pool is empty on both sides. A
# request that depends on a live upstream would be comparing two different worlds.
#
# Exit codes follow the house pattern: 1 is a real mismatch, 2 is an environment that could not run
# the check. Collapsing them reports "node is missing" as "the port is broken".

set -euo pipefail

# `$BASHPID` below needs bash 4; macOS still ships 3.2 at /bin/bash, where it is unset and `set -u`
# turns the guard that protects the router into the thing that kills the script. Checked explicitly
# rather than left to PATH order, because a gate that depends on which bash it happened to get is a
# gate that passes on one machine and not the next.
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  echo "environment: this needs bash 4+ (found ${BASH_VERSION:-unknown}); macOS /bin/bash is 3.2."
  echo "             brew install bash, or run it with a bash 4+ on PATH."
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST="${MCP_ROUTER_DIST:-$REPO_ROOT/dist}"
PORT="${PORT:-8973}"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/ControlDiff}"

HOME_DIR="$(mktemp -d -t mcprouter-differential)"
ROUTER_PID=""

# The EXIT trap is INHERITED by command-substitution subshells, and it fires when each one ends.
# Every `x="$(curl ...)"` below therefore ran this handler, killed the router and deleted the
# scratch home — after which every remaining row failed to connect and compared against a stale
# response body, which reads as 28 divergences in the port rather than one defect in this script.
# `$$` is the top-level shell and does not change in a subshell; `$BASHPID` does.
MAIN_PID=$$
cleanup() {
  [ "$BASHPID" != "$MAIN_PID" ] && return 0
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null || true
  rm -rf "$HOME_DIR"
}
trap cleanup EXIT

command -v node >/dev/null 2>&1 || { echo "environment: node is not installed"; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "environment: curl is not installed"; exit 2; }
[ -f "$DIST/index.js" ] || {
  echo "environment: no built reference at $DIST/index.js — run 'npm run build', or set"
  echo "             MCP_ROUTER_DIST. A skipped differential reports the same success as a"
  echo "             passing one, so this is an error rather than a skip."
  exit 2
}
[ -x "$SWIFT_BIN" ] || {
  echo "environment: $SWIFT_BIN is missing — run 'swift build --product ControlDiff' in app/"
  exit 2
}

# Refuse to run if the port is already taken. Without this the readiness probe happily connects to
# whatever is already listening — including a router left behind by a previous run of this very
# script, with a different home and a different config — and every subsequent row compares the
# Swift handler against a stranger. That produced a confident list of "divergences" that were
# entirely an artefact of the harness.
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "environment: something is already listening on :$PORT. This harness will not share a port,"
  echo "             because a readiness probe cannot tell the reference from a stranger."
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | sed -n '1,3p'
  exit 2
fi

# Servers chosen so every describe() branch is reachable without ever calling an upstream:
# a stdio server carrying env keys (whose VALUES must never appear), an HTTP server, and an
# HTTP server that declares oauth so the auth sub-object is exercised.
cat > "$HOME_DIR/servers.json" <<JSON
{
  "mcpServers": {
    "diff-stdio": {
      "command": "/bin/echo",
      "args": ["hello", "world"],
      "env": { "DIFF_SECRET": "sk-must-never-appear", "ZED": "1", "alpha": "2" },
      "projects": ["/tmp/one", "/tmp/two"]
    },
    "diff-http": { "url": "https://example.invalid/mcp", "type": "http", "oauth": false },
    "diff-oauth": { "url": "https://example.invalid/auth", "type": "http", "oauth": true },
    "diff-warm": { "command": "/bin/echo", "warm": true, "placard": "a placard" }
  }
}
JSON

# MCP_ROUTER_HOME is the ONLY variable that moves the router's whole state, and `serve --port` is
# how the port is set — an earlier version of this script guessed `MCPR_HOME` and `MCP_ROUTER_PORT`,
# both of which are silently ignored, so the router came up against the developer's REAL home and
# REAL servers.json and wrote into `~/.claude/mcp-router`. A test harness that falls back to
# production on a typo is worse than one that fails, so the guard below refuses to continue unless
# the scratch home is actually in effect.
#
# Extracted into a function because the divergence rows at the bottom KILL the reference outright,
# and each one needs a fresh process to run the next against.
TOKEN=""
start_router() {
  MCP_ROUTER_HOME="$HOME_DIR" node "$DIST/index.js" serve --port "$PORT" \
    >"$HOME_DIR/router.log" 2>&1 &
  ROUTER_PID=$!

  sleep 0.5
  if grep -q "$HOME/.claude/mcp-router" "$HOME_DIR/router.log" 2>/dev/null; then
    echo "environment: the router is using the REAL home despite MCP_ROUTER_HOME — refusing to"
    echo "             continue, because this harness would then mutate live state."
    sed -n '1,10p' "$HOME_DIR/router.log"
    exit 2
  fi

  # Wait for the control API rather than sleeping a fixed interval — a fixed sleep is either slow or
  # flaky, and on a loaded machine it is both.
  TOKEN=""
  for _ in $(seq 1 100); do
    if [ -f "$HOME_DIR/control.token" ]; then
      TOKEN="$(cat "$HOME_DIR/control.token")"
      if curl -fsS -m 2 -H "x-mcpr-token: $TOKEN" "http://127.0.0.1:$PORT/servers" >/dev/null 2>&1; then
        break
      fi
    fi
    kill -0 "$ROUTER_PID" 2>/dev/null || { echo "environment: the router exited during startup"; tail -20 "$HOME_DIR/router.log"; exit 2; }
    sleep 0.1
  done
  [ -n "$TOKEN" ] || { echo "environment: the router never wrote a control token"; tail -20 "$HOME_DIR/router.log"; exit 2; }
}
start_router

export MCPR_CONFIG="$HOME_DIR/servers.json"
export MCPR_MANIFEST="$HOME_DIR/manifest.json"
export MCPR_USAGE="$HOME_DIR/usage.jsonl"
export MCPR_STATS="$HOME_DIR/usage-stats.json"
export MCPR_TOKEN="$TOKEN"
export MCPR_PORT="$PORT"

pass=0; fail=0
declare -a failures=()

# One row: a label, a method, an encoded target, and an optional body.
compare() {
  local label="$1" method="$2" target="$3" body="${4:-}"

  # A dead reference is an ENVIRONMENT failure, not a divergence. Without this the harness
  # reports "28 mismatches" for one crashed router and points the reader at the port.
  if ! kill -0 "$ROUTER_PID" 2>/dev/null; then
    echo "environment: the reference exited before \"$label\" — its log:"
    sed -n '1,40p' "$HOME_DIR/router.log"
    exit 2
  fi

  local ts_status ts_body
  local -a curl_args=(-sS -m 10 -o "$HOME_DIR/ts.body" -w '%{http_code}'
                      -X "$method" "http://127.0.0.1:$PORT$target")
  [ -n "$TOKEN" ] && curl_args+=(-H "x-mcpr-token: $TOKEN")
  if [ -n "$body" ]; then
    curl_args+=(-H 'content-type: application/json' --data-binary "$body")
  fi
  ts_status="$(curl "${curl_args[@]}" || echo 000)"
  ts_body="$(cat "$HOME_DIR/ts.body")"

  local swift_out swift_status swift_body
  if [ -n "$body" ]; then
    swift_out="$("$SWIFT_BIN" "$method" "$target" "$body" 2>&1)" || true
  else
    swift_out="$("$SWIFT_BIN" "$method" "$target" 2>&1)" || true
  fi
  swift_status="$(printf '%s' "$swift_out" | head -1)"
  swift_body="$(printf '%s' "$swift_out" | tail -n +2)"

  # `since` is the moment each PROCESS started its usage store; two processes cannot agree on it,
  # and it is the only member here that is a fact about the run rather than about the config. It is
  # rewritten to a constant on both sides rather than deleted, so a MISSING `since` is still a
  # mismatch — dropping the member would let the port stop sending it and stay green.
  ts_body="$(printf '%s' "$ts_body" | sed 's/"since":"[^"]*"/"since":"<stamp>"/g')"
  swift_body="$(printf '%s' "$swift_body" | sed 's/"since":"[^"]*"/"since":"<stamp>"/g')"

  if [ "$ts_status" = "$swift_status" ] && [ "$ts_body" = "$swift_body" ]; then
    pass=$((pass + 1))
    printf '  ok   %-46s %s\n' "$label" "$ts_status"
  else
    fail=$((fail + 1))
    failures+=("$label")
    printf '  FAIL %-46s ts=%s swift=%s\n' "$label" "$ts_status" "$swift_status"
    printf '       ts:    %s\n' "$ts_body"
    printf '       swift: %s\n' "$swift_body"
  fi
}

echo "Differential: the Swift handler against the running reference on :$PORT"
echo

echo "acceptance criteria"
compare "B13 GET /servers envelope"          GET "/servers"
compare "B1  describe a stdio server"        GET "/servers/diff-stdio"
compare "B1  describe an http server"        GET "/servers/diff-http"
compare "B1  describe an oauth server"       GET "/servers/diff-oauth"
compare "B1  describe a warm/placarded row"  GET "/servers/diff-warm"
compare "B47 GET /usage/summary"             GET "/usage/summary"
compare "B45 GET /usage"                     GET "/usage"
compare "B26 GET /servers/:name/changes"      GET "/servers/diff-stdio/changes"
compare "B24 unknown server is 404"          GET "/servers/nope"

echo
echo "6b — fault injection"
compare "malformed JSON body"                PATCH "/servers/diff-stdio" '{"warm":'
compare "body is an array"                   PATCH "/servers/diff-stdio" '[1,2]'
compare "body is null"                       PATCH "/servers/diff-stdio" 'null'
compare "lowercase method is not mutating"   GET "/servers/diff-stdio"

echo
echo "6e — data-shape stress"
compare "N4 ?limit= is empty"                GET "/usage?limit="
compare "N4 ?limit=0"                        GET "/usage?limit=0"
compare "N4 ?limit=abc is NaN"               GET "/usage?limit=abc"
compare "N4 ?limit=-5 counts from the front" GET "/usage?limit=-5"
compare "?limit=1e300 does not trap"         GET "/usage?limit=1e300"
compare "repeated ?limit takes the first"    GET "/usage?limit=1&limit=9"
# `/registry/search` is deliberately NOT compared here. The reference answers it by calling the
# live Smithery and official registries over the network, so two runs a second apart return
# different rows and different counts — there is no stable oracle to diff against, and a row that
# fails on someone else's deploy teaches nothing about this port. `ControlDiff` has no HTTP client
# for the same reason the unit suite has none: no check in this item may touch the network.
# The `limit` coercion the row was reaching for is covered deterministically instead, by the
# `registry-limit` vector file and by RegistryTests.
compare "a very long server name"            GET "/servers/$(printf 'a%.0s' $(seq 1 512))"

# A path the control API DISCLAIMS. The expected answers are not equal and must not be compared as
# if they were: the Swift handler reports "not handled", and the reference's 404 is emitted by
# `router.ts`, not by `control.ts` — a boundary this item does not own. Comparing them read as a
# port defect when what it actually showed was the handoff working.
disclaims() {
  local label="$1" target="$2"
  local ts_body; ts_body="$(curl -sS -m 10 -H "x-mcpr-token: $TOKEN" "http://127.0.0.1:$PORT$target" || echo '')"
  local swift_out; swift_out="$("$SWIFT_BIN" GET "$target" 2>&1)" || true
  if [ "$swift_out" = "NOT-A-CONTROL-PATH" ] && [[ "$ts_body" == *"MCP endpoint is"* ]]; then
    printf '  ok   %-46s both disclaim it\n' "$label"
    pass=$((pass + 1))
  else
    printf '  FAIL %-46s swift=%s ts=%s\n' "$label" "$swift_out" "$ts_body"
    fail=$((fail + 1)); failures+=("$label")
  fi
}

echo
echo "6f — security surface"
# `%2F` stays literal, so this is neither `/servers` nor `/servers/…` and belongs to neither side's
# control API. Asserted as a disclaim rather than an equality, per the note above.
disclaims "B15 encoded slash is not a route"   "/servers%2Fdiff-stdio"
compare "path traversal stays a name"        GET "/servers/..%2F..%2Fetc%2Fpasswd"
compare "unknown control path"               GET "/servers/diff-stdio/nope"

# The canary: an env VALUE must not be reachable through any GET the API answers (B10, S8). This
# is asserted over the RESPONSES rather than by reading the source, because the claim is about
# what leaves the process.
echo
echo "6f — env-value canary"
canary_hits=0
for target in "/servers" "/servers/diff-stdio" "/usage/summary" "/changes"; do
  if curl -sS -m 10 -H "x-mcpr-token: $TOKEN" "http://127.0.0.1:$PORT$target" \
       | grep -q 'sk-must-never-appear'; then
    echo "  FAIL an env value reached the wire from $target"
    canary_hits=$((canary_hits + 1))
  fi
  if "$SWIFT_BIN" GET "$target" 2>/dev/null | grep -q 'sk-must-never-appear'; then
    echo "  FAIL an env value reached the Swift handler's output from $target"
    canary_hits=$((canary_hits + 1))
  fi
done
if [ "$canary_hits" -eq 0 ]; then
  echo "  ok   no env value appears in any compared response"
  pass=$((pass + 1))
else
  fail=$((fail + canary_hits))
  failures+=("env-value canary")
fi

# The token gate, checked against the live router only — the Swift side takes its token by
# parameter, so an unauthorized case there proves nothing about the wire.
echo
echo "6f — the token gate on the live router"
for probe in "POST /servers" "DELETE /servers/diff-stdio" "PATCH /servers/diff-stdio"; do
  set -- $probe
  code="$(curl -sS -m 10 -o /dev/null -w '%{http_code}' -X "$1" \
          -H 'content-type: application/json' --data-binary '{}' \
          "http://127.0.0.1:$PORT$2" || echo 000)"
  if [ "$code" = "401" ]; then
    printf '  ok   %-46s 401\n' "untokened $probe"
    pass=$((pass + 1))
  else
    printf '  FAIL %-46s expected 401, got %s\n' "untokened $probe" "$code"
    fail=$((fail + 1)); failures+=("untokened $probe")
  fi
done

# The rows where this port DELIBERATELY does not match, each asserted rather than excused.
#
# Five measured inputs make the reference throw out of an async request handler that nothing wraps,
# which terminates the router process. Reproducing that would port a remote kill into the
# replacement, so this port answers 400 — the same judgement D1 makes when it refuses the
# config-destroying write the reference performs.
#
# These are checked in BOTH directions. A row passes only when the reference really does die AND
# the Swift handler really does answer the expected 400: if the reference is ever fixed, this
# section fails and says the divergence is stale, so the list cannot outlive its reason. That is
# also why the reference's own error text is used — an unattributed 400 would be indistinguishable
# from an unrelated failure.
echo
echo "expected divergences — the reference dies here, and this port does not"
diverges() {
  local label="$1" method="$2" target="$3" body="${4:-}" want_status="$5" want_body="$6"

  kill -0 "$ROUTER_PID" 2>/dev/null || start_router

  local args=(-sS -m 5 -o "$HOME_DIR/d.body" -w '%{http_code}' -X "$method"
              "http://127.0.0.1:$PORT$target" -H "x-mcpr-token: $TOKEN")
  [ -n "$body" ] && args+=(-H 'content-type: application/json' --data-binary "$body")
  local ts_code; ts_code="$(curl "${args[@]}" 2>/dev/null || echo 000)"
  sleep 0.4

  local ts_state="survived"
  kill -0 "$ROUTER_PID" 2>/dev/null || ts_state="DIED"
  local node_error; node_error="$(grep -m1 -E '^(TypeError|URIError)' "$HOME_DIR/router.log" 2>/dev/null || echo '')"

  local swift_out swift_status swift_body
  if [ -n "$body" ]; then
    swift_out="$("$SWIFT_BIN" "$method" "$target" "$body" 2>&1)" || true
  else
    swift_out="$("$SWIFT_BIN" "$method" "$target" 2>&1)" || true
  fi
  swift_status="$(printf '%s' "$swift_out" | head -1)"
  swift_body="$(printf '%s' "$swift_out" | tail -n +2)"

  if [ "$ts_state" != "DIED" ]; then
    printf '  FAIL %-44s the reference SURVIVED (http=%s) — this divergence is stale\n' "$label" "$ts_code"
    fail=$((fail + 1)); failures+=("stale divergence: $label")
    return
  fi
  if [ "$swift_status" != "$want_status" ] || [ "$swift_body" != "$want_body" ]; then
    printf '  FAIL %-44s swift=%s %s\n' "$label" "$swift_status" "$swift_body"
    printf '       wanted %s %s\n' "$want_status" "$want_body"
    fail=$((fail + 1)); failures+=("$label")
    return
  fi
  printf '  ok   %-44s reference DIED (%s) · swift %s\n' "$label" "${node_error%%:*}" "$want_status"
  pass=$((pass + 1))
  # The reference is gone; the next row that needs it will start a fresh one.
}

diverges "PATCH body 42 kills the reference"   PATCH "/servers/diff-stdio" '42' \
  "400" '{"error":"Cannot use '"'"'in'"'"' operator to search for '"'"'projects'"'"' in 42"}'
diverges "PATCH body \"hi\" kills the reference" PATCH "/servers/diff-stdio" '"hi"' \
  "400" '{"error":"Cannot use '"'"'in'"'"' operator to search for '"'"'projects'"'"' in hi"}'
diverges "PATCH body true kills the reference"  PATCH "/servers/diff-stdio" 'true' \
  "400" '{"error":"Cannot use '"'"'in'"'"' operator to search for '"'"'projects'"'"' in true"}'
# Unauthenticated: the token gate covers POST/DELETE/PATCH only, so this needs no credential at all.
diverges "GET %ZZ kills the reference"          GET "/servers/%ZZ" '' \
  "400" '{"error":"URI malformed"}'
diverges "GET a truncated escape kills it"      GET "/servers/%E0%A4%A" '' \
  "400" '{"error":"URI malformed"}'

echo
echo "compared $((pass + fail)) rows: $pass ok, $fail failed"
if [ "$fail" -gt 0 ]; then
  echo "mismatched: ${failures[*]}"
  echo
  echo "A mismatch is a divergence from the reference, which is what this item promises not to have."
  exit 1
fi
echo "The Swift handler answers what the reference answers on every compared row."
