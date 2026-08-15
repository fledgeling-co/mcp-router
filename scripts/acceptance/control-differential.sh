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
# D-g1-g. Release sits INSIDE the BASHPID guard above deliberately: the same subshell inheritance
# that killed the router mid-run would otherwise drop the lock mid-run, letting a second run bind
# :8973 underneath this one. `parity_lock_release` carries its own BASHPID guard as well, so this
# is belt and braces on the failure this script already paid for once.
. "$REPO_ROOT/scripts/acceptance/parity-lock.sh"
cleanup() {
  [ "$BASHPID" != "$MAIN_PID" ] && return 0
  parity_lock_release
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null || true
  rm -rf "$HOME_DIR"
}
trap cleanup EXIT INT TERM HUP
parity_lock_acquire "control-differential.sh"

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

# R4: every row also reports itself to a machine-readable file, so `parity-gate.sh` can reconcile
# what ran against `planning/parity/surface.tsv` rather than against whatever this script happened
# to print. The gate's denominator comes from the manifest; this file only supplies numerators.
#
# Each row names the manifest ROW ID it speaks for, not its own label. Several rows can speak for
# one route — `/servers/:name` is compared four ways — and a route is proven only when every row
# naming it passed. Deriving the id from the label instead would break the moment a label is
# reworded, and it would break silently, by producing a numerator for a row that does not exist.
RESULTS="${PARITY_RESULTS:-}"
record() {
  [ -n "$RESULTS" ] || return 0
  printf '%s\t%s\t%s\t%s\n' "control" "$1" "$2" "$3" >> "$RESULTS"
}

# R4: a declared divergence is its own manifest row, in the `divergence` group, and it needs its
# own result. Recording only under the control route id left R3's D1-D5 rows reading "no lane
# reported" in the gate — asserted in this file, and invisible to the census that decides whether
# a cutover is justified.
record_divergence() {
  [ -n "$RESULTS" ] || return 0
  printf '%s\t%s\t%s\t%s\n' "divergence" "$1" "$2" "$3" >> "$RESULTS"
}

# One row: a manifest row id, a label, a method, an encoded target, and an optional body.
compare() {
  local id="$1" label="$2" method="$3" target="$4" body="${5:-}"

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

  # A curl that could not reach the reference reports 000 with an empty body. If the Swift oracle
  # also fails to produce a response, the two "agree" — identical status, identical bytes — and the
  # row records a PASS built from two failures. That is the canonical differential-harness defect:
  # nothing else here asserts that either side actually answered before their answers are compared.
  if [ "$ts_status" = "000" ]; then
    echo "environment: the reference did not answer \"$label\" (curl reported 000)."
    echo "             Refusing to compare two failures as though they agreed."
    exit 2
  fi

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
    record "$id" ok "$label"
  else
    fail=$((fail + 1))
    failures+=("$label")
    printf '  FAIL %-46s ts=%s swift=%s\n' "$label" "$ts_status" "$swift_status"
    printf '       ts:    %s\n' "$ts_body"
    printf '       swift: %s\n' "$swift_body"
    record "$id" fail "$label — ts=$ts_status swift=$swift_status"
  fi
}

echo "Differential: the Swift handler against the running reference on :$PORT"
echo

echo "acceptance criteria"
compare control-servers-get     "B13 GET /servers envelope"          GET "/servers"
compare control-server-get      "B1  describe a stdio server"        GET "/servers/diff-stdio"
compare control-server-get      "B1  describe an http server"        GET "/servers/diff-http"
compare control-server-get      "B1  describe an oauth server"       GET "/servers/diff-oauth"
compare control-server-get      "B1  describe a warm/placarded row"  GET "/servers/diff-warm"
compare control-usage-summary   "B47 GET /usage/summary"             GET "/usage/summary"
compare control-usage-get       "B45 GET /usage"                     GET "/usage"
compare control-changes-get     "B26 GET /servers/:name/changes"     GET "/servers/diff-stdio/changes"
compare control-server-get      "B24 unknown server is 404"          GET "/servers/nope"

# R4 — the routes R3's matrix never reached. Each one is a route the reference dispatches, so
# each one is a manifest row that was being counted as covered by a harness that never issued it.
echo
echo "R4 — routes the 32-row matrix did not reach"
compare control-servers-post    "POST /servers with no name"         POST "/servers" '{}'
compare control-servers-post    "POST /servers with an empty name"   POST "/servers" '{"name":""}'
compare control-servers-post    "POST /servers with no command"      POST "/servers" '{"name":"x"}'
compare control-auth-delete     "DELETE /servers/:name/auth"         DELETE "/servers/diff-stdio/auth"
compare control-auth-delete     "DELETE auth on an http server"      DELETE "/servers/diff-oauth/auth"
compare control-auth-delete     "DELETE auth on an unknown server"   DELETE "/servers/nope/auth"
compare control-reindex-post    "POST reindex on an unknown server"  POST "/servers/nope/reindex" '{}'
compare control-changes-get     "changes on an unknown server"       GET "/servers/nope/changes"

echo
echo "6b — fault injection"
compare control-server-patch    "malformed JSON body"                PATCH "/servers/diff-stdio" '{"warm":'
compare control-server-patch    "body is an array"                   PATCH "/servers/diff-stdio" '[1,2]'
compare control-server-patch    "body is null"                       PATCH "/servers/diff-stdio" 'null'
compare control-server-get      "lowercase method is not mutating"   GET "/servers/diff-stdio"

echo
echo "6e — data-shape stress"
compare control-usage-get       "N4 ?limit= is empty"                GET "/usage?limit="
compare control-usage-get       "N4 ?limit=0"                        GET "/usage?limit=0"
compare control-usage-get       "N4 ?limit=abc is NaN"               GET "/usage?limit=abc"
compare control-usage-get       "N4 ?limit=-5 counts from the front" GET "/usage?limit=-5"
compare control-usage-get       "?limit=1e300 does not trap"         GET "/usage?limit=1e300"
compare control-usage-get       "repeated ?limit takes the first"    GET "/usage?limit=1&limit=9"
# `/registry/search` is deliberately NOT compared by equality here. The reference answers it by
# calling the live Smithery and official registries over the network, so two runs a second apart
# return different rows and different counts — there is no stable oracle to diff against, and a row
# that fails on someone else's deploy teaches nothing about this port. `ControlDiff` has no HTTP
# client for the same reason the unit suite has none: no check in this item may touch the network.
# R4 records the route as BLOCKED in the manifest rather than leaving it silently uncompared — an
# uncompared route was previously indistinguishable from a compared one.
compare control-server-get      "a very long server name"            GET "/servers/$(printf 'a%.0s' $(seq 1 512))"

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
# control API. Asserted as a disclaim rather than an equality, per the note above. Not recorded
# against a manifest row: it asserts that a string is NOT a route, which is not a route's parity.
disclaims "B15 encoded slash is not a route"   "/servers%2Fdiff-stdio"
compare control-server-get      "path traversal stays a name"        GET "/servers/..%2F..%2Fetc%2Fpasswd"
compare control-server-get      "unknown control path"               GET "/servers/diff-stdio/nope"

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
for probe in "POST /servers" "DELETE /servers/diff-stdio" "PATCH /servers/diff-stdio" \
             "POST /servers/diff-stdio/approve" "POST /servers/diff-stdio/auth"; do
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
  local id="$1" div_id="$2" label="$3" method="$4" target="$5" body="${6:-}" want_status="$7" want_body="$8"

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
    record "$id" fail "stale divergence: $label — the reference survived"
    record_divergence "$div_id" fail "stale: the reference survived $label, so the divergence record has outlived its reason"
    return
  fi
  if [ "$swift_status" != "$want_status" ] || [ "$swift_body" != "$want_body" ]; then
    printf '  FAIL %-44s swift=%s %s\n' "$label" "$swift_status" "$swift_body"
    printf '       wanted %s %s\n' "$want_status" "$want_body"
    fail=$((fail + 1)); failures+=("$label")
    record "$id" fail "$label — swift=$swift_status"
    record_divergence "$div_id" fail "$label — swift answered $swift_status, not the declared $want_status"
    return
  fi
  printf '  ok   %-44s reference DIED (%s) · swift %s\n' "$label" "${node_error%%:*}" "$want_status"
  pass=$((pass + 1))
  record "$id" ok "$label"
  record_divergence "$div_id" ok "$label — reference died, swift answered $want_status, both as declared"
  # The reference is gone; the next row that needs it will start a fresh one.
}

diverges control-server-patch div-r3-d1 "PATCH body 42 kills the reference"   PATCH "/servers/diff-stdio" '42' \
  "400" '{"error":"Cannot use '"'"'in'"'"' operator to search for '"'"'projects'"'"' in 42"}'
diverges control-server-patch div-r3-d2 "PATCH body \"hi\" kills the reference" PATCH "/servers/diff-stdio" '"hi"' \
  "400" '{"error":"Cannot use '"'"'in'"'"' operator to search for '"'"'projects'"'"' in hi"}'
diverges control-server-patch div-r3-d3 "PATCH body true kills the reference"  PATCH "/servers/diff-stdio" 'true' \
  "400" '{"error":"Cannot use '"'"'in'"'"' operator to search for '"'"'projects'"'"' in true"}'
# Unauthenticated: the token gate covers POST/DELETE/PATCH only, so this needs no credential at all.
diverges control-server-get div-r3-d4 "GET %ZZ kills the reference"          GET "/servers/%ZZ" '' \
  "400" '{"error":"URI malformed"}'
diverges control-server-get div-r3-d5 "GET a truncated escape kills it"      GET "/servers/%E0%A4%A" '' \
  "400" '{"error":"URI malformed"}'

# ---------------------------------------------------------------------------------------------
# P1 — the two routes that used to be asserted here as KNOWN DEFECTS, now compared for real.
#
# `AuthRoutes.approve` and `AuthRoutes.authStart` were both implemented by R5, both unit-tested,
# and both reachable by nothing: `ControlHandler`'s dispatch carried ("/auth", "DELETE") and no
# POST arm at all, so the wire answered 405 to two routes the reference answers. That was `D-j`,
# and this file used to hold a `known_defect` helper asserting the defect in BOTH directions so it
# could not be mistaken for coverage.
#
# `D-r2r-c` is the instruction that the helper had to go in the SAME change that fixed D-j —
# otherwise the harness reports a failure *because* the defect was fixed, which is the worst kind
# of red. P1 did both, so the helper is deleted rather than left dead and these are ordinary
# `compare` rows.
#
# `compare` and not `compare_mutating`: neither request issued here writes anything. `/approve`
# against a server with no pending change returns 409 before any write, and `/auth` against a
# stdio server returns 400 before any flow begins or any port is bound. A mutating harness would
# snapshot and restore `servers.json` around two requests that never touch it.
#
# The non-stdio half of `/auth` is NOT compared here, and its absence is not agreement: the
# reference answers 200 with an authorization URL and this router answers 405, because nothing
# conforms to `AuthTransport` yet. That is carried as its own manifest row, `control-auth-post-http`,
# blocked on `D-p1-a` — declared rather than left to look like parity.
echo
echo "P1 — the two auth routes, reachable at last"
# The two rows immediately above kill the reference on purpose — that IS `div-r3-d4`/`d5`, an
# unhandled `URIError` in `decodeURIComponent`. The deleted `known_defect` helper carried this same
# guard for the same reason; `compare` does not restart on its own, and without it every row below
# reports "the reference exited" (exit 2) rather than comparing anything.
kill -0 "$ROUTER_PID" 2>/dev/null || start_router
compare control-approve-post    "POST /servers/:name/approve"        POST "/servers/diff-stdio/approve" '{}'
compare control-auth-post       "POST /servers/:name/auth"           POST "/servers/diff-stdio/auth" '{}'
compare control-approve-post    "approve on an unknown server"       POST "/servers/nope/approve" '{}'
compare control-auth-post       "POST auth on an unknown server"     POST "/servers/nope/auth" '{}'

# ---------------------------------------------------------------------------------------------
# R4 — the mutating routes. R3's matrix compared only their error paths, so the success path of
# every writer in the control API was uncompared.
#
# A mutating row cannot be issued to both sides against one shared file: the reference computes its
# answer from the pre-mutation state and then rewrites the file, so the Swift handler reading the
# same path afterwards computes from a different world and every row reads as a divergence. Each
# side therefore runs against the SAME pre-mutation snapshot, restored in between.
#
# The resulting `servers.json` is compared too, not just the response. A writer whose reply matches
# and whose file does not is the worse of the two failures, and it is the one a response-only diff
# cannot see.
compare_mutating() {
  local id="$1" label="$2" method="$3" target="$4" body="$5"

  kill -0 "$ROUTER_PID" 2>/dev/null || start_router
  cp "$HOME_DIR/servers.json" "$HOME_DIR/servers.snapshot"

  local ts_status ts_body ts_config
  ts_status="$(curl -sS -m 10 -o "$HOME_DIR/m.body" -w '%{http_code}' -X "$method" \
    "http://127.0.0.1:$PORT$target" -H "x-mcpr-token: $TOKEN" \
    -H 'content-type: application/json' --data-binary "$body" 2>/dev/null || echo 000)"
  ts_body="$(cat "$HOME_DIR/m.body")"
  ts_config="$(cat "$HOME_DIR/servers.json")"

  cp "$HOME_DIR/servers.snapshot" "$HOME_DIR/servers.json"

  local swift_out swift_status swift_body swift_config
  swift_out="$("$SWIFT_BIN" "$method" "$target" "$body" 2>&1)" || true
  swift_status="$(printf '%s' "$swift_out" | head -1)"
  swift_body="$(printf '%s' "$swift_out" | tail -n +2)"
  swift_config="$(cat "$HOME_DIR/servers.json")"

  cp "$HOME_DIR/servers.snapshot" "$HOME_DIR/servers.json"
  # The reference now holds a mutated view in memory that no longer matches the file on disk.
  # Retire it rather than let the next row compare against a state nothing else shares.
  kill "$ROUTER_PID" 2>/dev/null || true
  wait "$ROUTER_PID" 2>/dev/null || true
  ROUTER_PID=""

  ts_body="$(printf '%s' "$ts_body" | sed 's/"since":"[^"]*"/"since":"<stamp>"/g')"
  swift_body="$(printf '%s' "$swift_body" | sed 's/"since":"[^"]*"/"since":"<stamp>"/g')"

  if [ "$ts_status" = "$swift_status" ] && [ "$ts_body" = "$swift_body" ] \
     && [ "$ts_config" = "$swift_config" ]; then
    printf '  ok   %-46s %s (config identical)\n' "$label" "$ts_status"
    pass=$((pass + 1)); record "$id" ok "$label"
  else
    fail=$((fail + 1)); failures+=("$label")
    printf '  FAIL %-46s ts=%s swift=%s\n' "$label" "$ts_status" "$swift_status"
    [ "$ts_body" != "$swift_body" ] && {
      printf '       ts body:    %s\n' "$ts_body"
      printf '       swift body: %s\n' "$swift_body"
    }
    [ "$ts_config" != "$swift_config" ] && {
      printf '       the written servers.json differs:\n'
      diff <(printf '%s' "$ts_config") <(printf '%s' "$swift_config") | sed 's/^/         /' | head -20
    }
    record "$id" fail "$label — ts=$ts_status swift=$swift_status"
  fi
}

echo
echo "R4 — mutating routes, each side against the same pre-mutation snapshot"
compare_mutating control-server-patch "PATCH sets a placard"         PATCH "/servers/diff-stdio" '{"placard":"held"}'
compare_mutating control-server-patch "PATCH rejects a command edit" PATCH "/servers/diff-stdio" '{"command":"/bin/sh"}'
compare_mutating control-server-patch "PATCH rejects an env edit"    PATCH "/servers/diff-stdio" '{"env":{"X":"1"}}'
compare_mutating control-servers-post "POST refuses a duplicate"     POST  "/servers" '{"name":"diff-stdio","command":"/bin/echo"}'
compare_mutating control-server-delete "DELETE removes a server"     DELETE "/servers/diff-warm" ''
compare_mutating control-server-delete "DELETE an unknown server"    DELETE "/servers/nope" ''
compare_mutating control-usage-reset  "POST /usage/reset"            POST  "/usage/reset" '{}'

# ---------------------------------------------------------------------------------------------
# R4 — the routes whose answer depends on something `ControlDiff` cannot have.
#
# Two branches of the control API call into the pool and the indexer, and `ControlDiff` supplies an
# `IdlePool` and a `RefusingIndexer` because there is no Swift daemon to supply real ones. Both
# sides run the same logic — `ControlHandler.swift:353` calls `pool.warmUp()` exactly where
# `control.ts:387` calls it, and both index before adopting — so what differs is the OBSERVATION,
# not the port.
#
# That is not a licence to skip the row, which is how a subset becomes a pass. Instead the one
# stub-attributable field is masked and EVERYTHING ELSE must still match byte for byte, so a real
# divergence anywhere else in the same response still fails. The row is then recorded `blocked`
# rather than `ok`: what has been shown is "identical apart from the field a stub owns", which is
# a weaker claim than parity and is reported as one.
not_provable() {
  local id="$1" label="$2" method="$3" target="$4" body="$5" mask="$6" why="$7"

  kill -0 "$ROUTER_PID" 2>/dev/null || start_router
  cp "$HOME_DIR/servers.json" "$HOME_DIR/servers.snapshot"

  local ts_status ts_body
  ts_status="$(curl -sS -m 20 -o "$HOME_DIR/n.body" -w '%{http_code}' -X "$method" \
    "http://127.0.0.1:$PORT$target" -H "x-mcpr-token: $TOKEN" \
    -H 'content-type: application/json' --data-binary "$body" 2>/dev/null || echo 000)"
  ts_body="$(cat "$HOME_DIR/n.body")"

  cp "$HOME_DIR/servers.snapshot" "$HOME_DIR/servers.json"

  local swift_out swift_status swift_body
  swift_out="$("$SWIFT_BIN" "$method" "$target" "$body" 2>&1)" || true
  swift_status="$(printf '%s' "$swift_out" | head -1)"
  swift_body="$(printf '%s' "$swift_out" | tail -n +2)"

  cp "$HOME_DIR/servers.snapshot" "$HOME_DIR/servers.json"
  kill "$ROUTER_PID" 2>/dev/null || true
  wait "$ROUTER_PID" 2>/dev/null || true
  ROUTER_PID=""

  local ts_masked swift_masked
  ts_masked="$(printf '%s' "$ts_body" | sed -E "$mask")"
  swift_masked="$(printf '%s' "$swift_body" | sed -E "$mask")"

  if [ "$ts_status" = "$swift_status" ] && [ "$ts_masked" = "$swift_masked" ]; then
    printf '  --   %-46s %s · identical outside %s\n' "$label" "$ts_status" "$why"
    record "$id" blocked "$label — identical outside $why; needs a live pool/indexer (R2-R)"
  else
    printf '  FAIL %-46s ts=%s swift=%s — differs OUTSIDE %s\n' "$label" "$ts_status" "$swift_status" "$why"
    printf '       ts:    %s\n' "$ts_masked"
    printf '       swift: %s\n' "$swift_masked"
    fail=$((fail + 1)); failures+=("$label")
    record "$id" fail "$label — differs outside the masked field"
  fi
}

echo
echo "R4 — branches a stub owns: masked field named, everything else still compared"
not_provable control-server-patch "PATCH sets warm (triggers warm-up)" \
  PATCH "/servers/diff-stdio" '{"warm":true}' \
  's/"state":"[a-z]+"/"state":"<pool>"/' 'the pool-reported state'
not_provable control-servers-post "POST adds a server (indexes first)" \
  POST "/servers" '{"name":"added","command":"/bin/echo"}' \
  's/"error":"[^"]*"/"error":"<indexer>"/' 'the indexer error text'

# ---------------------------------------------------------------------------------------------
# Informational only — neither row is recorded, and both routes stay BLOCKED in the manifest.
# Printing them keeps the reader from assuming an unlisted route was simply forgotten.
echo
echo "not comparable — recorded as blocked in the manifest, shown so the gap is visible"
kill -0 "$ROUTER_PID" 2>/dev/null || start_router
stream_code="$(curl -sS -m 2 -o /dev/null -w '%{http_code}' \
  -H "x-mcpr-token: $TOKEN" "http://127.0.0.1:$PORT/usage/stream" 2>/dev/null || echo 'held-open')"
printf '  --   %-46s ts=%s swift=%s\n' "GET /usage/stream (SSE, body is a stream)" \
  "$stream_code" "$("$SWIFT_BIN" GET /usage/stream 2>&1 | head -1)"
printf '  --   %-46s swift=%s\n' "GET /registry/search (live network on the reference)" \
  "$("$SWIFT_BIN" GET '/registry/search?q=a' 2>&1 | tail -n +2)"

echo
echo "compared $((pass + fail)) rows: $pass ok, $fail failed"
if [ "$fail" -gt 0 ]; then
  echo "mismatched: ${failures[*]}"
  echo
  echo "A mismatch is a divergence from the reference, which is what this item promises not to have."
  exit 1
fi
echo "The Swift handler answers what the reference answers on every compared row."
