#!/usr/bin/env bash
#
# An upstream that refuses our credentials must SAY so, on every surface that reports it.
#
# The failure this exists to refuse was measured on a live router on 2026-08-20. An HTTP
# upstream's access token expired at 11:56:39Z; the re-index at 11:58:54Z came back
# `[-32603] Internal error: Authentication required` in 373ms. From then on the router
# served 91 tools and none of them were that server's. `mcpr status` printed `idle` for
# it — the same word as the eleven upstreams that were working. The log's last
# `needs authorization` line was five days old. `pendingAuth` was null. And `/servers`
# carried, three lines apart in one object, `indexError: "...Authentication required"`
# and `auth.authorized: true`.
#
# Nothing was broken in a way anything could see. The user spent a day intending to use
# that server, was never offered its tools, and had no surface that would have told them.
#
# The fixture reproduces the shape exactly: the transport connects, the MCP handshake
# succeeds, and the first real call comes back as a JSON-RPC error inside a 200. That is
# what a rejected REFRESH looks like, and it is not what the `oauth` fixture produces —
# that one 401s at the transport, which the router already handled.
#
#   bash scripts/acceptance/auth-rejection-visible.sh [--binary <cmd...>]
#
# Exit 0 all checks passed · 1 a check failed · 2 the environment could not be set up.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs"
SERVER_NAME="staleserver"
STALE_PORT="${STALE_PORT:-8974}"
ROUTER_PORT="${ROUTER_PORT:-8975}"

pass=0; fail=0
WORK="$(mktemp -d -t auth-rejection)"
FIXTURE_PID=""; ROUTER_PID=""
cleanup() {
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null
  [ -n "$FIXTURE_PID" ] && kill "$FIXTURE_PID" 2>/dev/null
  wait 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

environment_failure() {
  printf '\nenvironment: %s\n' "$1"
  printf 'This is not a finding about the router. Nothing was measured.\n'
  exit 2
}

check() { # label  expected  actual
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1)); printf '  ok   %-52s %s\n' "$1" "$3"
  else
    fail=$((fail + 1)); printf '  FAIL %-52s expected %s, got %s\n' "$1" "$2" "$3"
  fi
}
check_contains() { # label  needle  haystack
  if printf '%s' "$3" | grep -qF -- "$2"; then
    pass=$((pass + 1)); printf '  ok   %-52s contains %s\n' "$1" "$2"
  else
    fail=$((fail + 1)); printf '  FAIL %-52s expected to contain %s, got: %s\n' "$1" "$2" "${3:0:120}"
  fi
}

BINARY=(node "$REPO_ROOT/dist/index.js")
if [ "${1:-}" = "--binary" ]; then shift; BINARY=("$@"); fi

printf 'auth-rejection-visible — an upstream that refuses our credentials says so\n'
printf '  binary: %s\n\n' "${BINARY[*]}"

[ -f "$FIXTURE" ] || environment_failure "the fixture server is not at $FIXTURE"
command -v node >/dev/null 2>&1 || environment_failure "node is not on PATH"

# ---------------------------------------------------------------- the fixture --
FIXTURE_STALE_PORT="$STALE_PORT" node "$FIXTURE" staletoken > "$WORK/fixture.out" 2>&1 &
FIXTURE_PID=$!
ready=""
for _ in $(seq 1 60); do
  curl -sS -m 2 -o /dev/null -X POST -H 'content-type: application/json' \
    --data-binary '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    "http://127.0.0.1:$STALE_PORT/mcp" >/dev/null 2>&1 && { ready=ok; break; }
  kill -0 "$FIXTURE_PID" 2>/dev/null || break
  sleep 0.2
done
[ "$ready" = ok ] || environment_failure "the stale-token fixture never answered on :$STALE_PORT
             ($(tail -3 "$WORK/fixture.out" | tr '\n' ' '))"

# ------------------------------------------------------------------- the home --
# A SEEDED credential is the whole point of the setup. `hasTokens` reads this file, and it
# is what made the old `authorized` report true: a token on disk that the server has stopped
# honouring is indistinguishable from a working one until somebody asks the server.
HOME_DIR="$WORK/home"
mkdir -p "$HOME_DIR/auth"
cat > "$HOME_DIR/servers.json" <<JSON
{ "mcpServers": { "$SERVER_NAME": { "url": "http://127.0.0.1:$STALE_PORT/mcp", "type": "http" } } }
JSON
cat > "$HOME_DIR/auth/$SERVER_NAME.json" <<JSON
{
  "clientInformation": { "client_id": "fixture-client" },
  "tokens": { "access_token": "expired-at-1156", "token_type": "bearer", "expires_in": 3600 },
  "authorizedAt": "2026-08-20T10:56:39.710Z"
}
JSON
chmod 600 "$HOME_DIR/auth/$SERVER_NAME.json"

MCP_ROUTER_HOME="$HOME_DIR" "${BINARY[@]}" serve --port "$ROUTER_PORT" \
  > "$WORK/serve.out" 2>&1 &
ROUTER_PID=$!
ready=""
for _ in $(seq 1 100); do
  curl -fsS -m 2 "http://127.0.0.1:$ROUTER_PORT/health" >/dev/null 2>&1 && { ready=ok; break; }
  kill -0 "$ROUTER_PID" 2>/dev/null || break
  sleep 0.2
done
[ "$ready" = ok ] || environment_failure "the router never answered /health on :$ROUTER_PORT
             ($(tail -5 "$WORK/serve.out" | tr '\n' ' '))"

TOKEN="$(cat "$HOME_DIR/control.token" 2>/dev/null || echo '')"
[ -n "$TOKEN" ] || environment_failure "the router minted no control token"

# Force the index that discovers the rejection. Without this the check would depend on
# whatever the router happens to do at startup, which differs between the two binaries and
# would make a real difference look like a timing one.
REINDEX_STATUS="$(curl -sS -m 60 -o "$WORK/reindex.json" -w '%{http_code}' -X POST \
  -H "x-mcpr-token: $TOKEN" -H 'content-type: application/json' --data-binary '{}' \
  "http://127.0.0.1:$ROUTER_PORT/servers/$SERVER_NAME/reindex" 2>/dev/null)"
# A setup step that fails quietly is how a gate comes to measure the wrong thing and report a
# clean row. If the index never ran there is no rejection to observe, and every check below
# would be reading the state of a router that was never asked the question.
# 422 is the RIGHT answer here and 200 would be the wrong one: the route reports the index
# it just ran, and the index failed, which is the state under test. The first version of this
# gate demanded 200 and refused its own successful setup.
case "$REINDEX_STATUS" in
  200 | 422) : ;;
  *) environment_failure \
    "POST /servers/$SERVER_NAME/reindex answered ${REINDEX_STATUS:-000}; expected 200 or 422
             body: $(head -c 300 "$WORK/reindex.json" 2>/dev/null)
             serve: $(tail -3 "$WORK/serve.out" | tr '\n' ' ')" ;;
esac
grep -qF 'Authentication required' "$WORK/reindex.json" 2>/dev/null || environment_failure \
  "the re-index did not reach the rejection the fixture serves; there is nothing to observe
             body: $(head -c 300 "$WORK/reindex.json" 2>/dev/null)"

curl -fsS -m 10 -H "x-mcpr-token: $TOKEN" "http://127.0.0.1:$ROUTER_PORT/servers" \
  -o "$WORK/servers.json" 2>/dev/null \
  || environment_failure "GET /servers did not answer"

# `pendingAuth` is a different thing on each route and both names are right. On /servers it is
# `currentFlow()` -- a browser authorization happening right now. On /status it is
# `pool.pending()` -- every upstream the router believes needs authorizing, which is what
# `mcp-router status` prints its `!` line from. The rejection has to reach the second one.
curl -fsS -m 10 "http://127.0.0.1:$ROUTER_PORT/status" -o "$WORK/status.json" 2>/dev/null \
  || environment_failure "GET /status did not answer"

read_field() { # jq-ish path via python, so the gate needs no jq
  python3 - "$WORK/servers.json" "$SERVER_NAME" "$1" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
name, field = sys.argv[2], sys.argv[3]
row = next((s for s in doc.get("servers", []) if s.get("name") == name), None)
if row is None:
    print("<no such server>"); raise SystemExit
if field.startswith("auth."):
    print(json.dumps((row.get("auth") or {}).get(field[5:])).strip('"'))
else:
    print(json.dumps(row.get(field)).strip('"'))
PY
}

printf 'what /servers reports about a refused credential\n'
check          'the upstream contributes no tools'        '0'      "$(read_field tools)"
check_contains 'indexError names the refusal'             'Authentication required' "$(read_field indexError)"
check          'auth.authorized is false'                 'false'  "$(read_field auth.authorized)"
check_contains 'auth.rejected carries the reason'         'Authentication required' "$(read_field auth.rejected)"
pending_present() {
  python3 - "$WORK/status.json" "$SERVER_NAME" <<'PENDING_PY'
import json, sys
doc = json.load(open(sys.argv[1]))
print(str(any(p.get("server") == sys.argv[2] for p in (doc.get("pendingAuth") or []))).lower())
PENDING_PY
}
check          '/status pendingAuth carries the server'   'true'   "$(pending_present)"

printf '\nwhat the operator surfaces report\n'
LOG="$(cat "$HOME_DIR/router.log" 2>/dev/null || cat "$WORK/serve.out")"
check_contains 'the log says the credentials were refused' 'refused our credentials' "$LOG"

STATUS_OUT="$(MCP_ROUTER_HOME="$HOME_DIR" "${BINARY[@]}" status --port "$ROUTER_PORT" 2>&1 || true)"
check_contains 'status names the server as needing auth'  "needs authorizing: " "$STATUS_OUT"
check_contains 'status names WHICH server'                "$SERVER_NAME"        "$STATUS_OUT"

printf '\n%d checks — examined=%d failures=%d\n' "$((pass + fail))" "$((pass + fail))" "$fail"
if [ "$fail" -eq 0 ]; then
  printf 'a refused credential is visible on /servers, in the log, and in `status`.\n'
else
  printf 'a refused credential is still invisible somewhere. Those are the surfaces a user has.\n'
fi
[ "$fail" -eq 0 ]
