#!/usr/bin/env bash
#
# P1: approval and authentication routes over the retained TypeScript daemon's socket.
# A scratch home isolates configuration, token, manifest and logs from the installed service.
# Exit 0 means assertions held; 1 means a measured failure; 2 means the lane could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST="${MCP_ROUTER_DIST:-$REPO_ROOT/dist}"
HOME_DIR="$(mktemp -d -t mcprouter-p1)"
PORT="${PORT:-8983}"
# The auth callback port is pinned to a scratch one. Without this the daemon binds the REAL 8880
# the moment a non-stdio `/auth` reaches it — the developer's own router may hold it, and a check
# whose result depends on that is not a check.
AUTH_PORT="${AUTH_PORT:-8982}"
ROUTER_PID=""

pass=0
fail=0
declare -a failures=()

cleanup() {
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null
  wait "$ROUTER_PID" 2>/dev/null
  rm -rf "$HOME_DIR"
}
trap cleanup EXIT INT TERM HUP

for bound_port in "$PORT" "$AUTH_PORT"; do
  if lsof -nP -iTCP:"$bound_port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "environment: scratch port $bound_port is already listening"; exit 2
  fi
done

[ -f "$DIST/index.js" ] || { echo "environment: build the TypeScript router first (npm run build)"; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "environment: curl is not installed"; exit 2; }

# One stdio server, and a manifest entry carrying a pending change so BOTH approve paths are
# reachable — the 409 (no pending) case needs a second server that has none.
cat >"$HOME_DIR/servers.json" <<'JSON'
{
  "mcpServers": {
    "p1-quiet": { "command": "/bin/echo", "args": ["quiet"] },
    "p1-held": { "command": "/bin/echo", "args": ["held"] },
    "p1-http": { "url": "https://example.invalid/mcp", "type": "http", "oauth": true }
  }
}
JSON

cat >"$HOME_DIR/manifest.json" <<'JSON'
{
  "version": 1,
  "servers": {
    "p1-quiet": { "tools": [], "digest": "d0", "builtAt": "2026-01-01T00:00:00.000Z" },
    "p1-held": {
      "tools": [{ "name": "old" }],
      "digest": "d1",
      "builtAt": "2026-01-01T00:00:00.000Z",
      "pending": { "tools": [{ "name": "a" }, { "name": "b" }], "digest": "d2" }
    }
  }
}
JSON

MCP_ROUTER_HOME="$HOME_DIR" MCP_ROUTER_AUTH_PORT="$AUTH_PORT" \
  node "$DIST/index.js" serve --port "$PORT" >"$HOME_DIR/serve.out" 2>&1 &
ROUTER_PID=$!

health=""
for _ in $(seq 1 50); do
  if curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then health=ok; break; fi
  kill -0 "$ROUTER_PID" 2>/dev/null || break
  sleep 0.2
done
if [ "$health" != "ok" ]; then
  echo "environment: the Swift daemon never answered /health on :$PORT — its output:"
  sed -n '1,40p' "$HOME_DIR/serve.out"
  exit 2
fi

TOKEN="$(cat "$HOME_DIR/control.token" 2>/dev/null || echo '')"
[ -n "$TOKEN" ] || { echo "environment: the daemon minted no control token at $HOME_DIR/control.token"; exit 2; }

# One request. Asserts the status AND the body, because a route that returns the right number with
# the wrong bytes is still a divergence — and on these two routes the body carries the whole reason.
# Seconds a single request may take. Raised around the one check that begins a real OAuth flow:
# that route races the provider for 20 seconds before it gives up, by design and in both routers.
TIMEOUT=5

check() { # label method target want-status want-body(or "-") [--no-token]
  local label="$1" method="$2" target="$3" want_status="$4" want_body="$5" no_token="${6:-}"

  if ! kill -0 "$ROUTER_PID" 2>/dev/null; then
    echo "environment: the daemon exited before \"$label\" — its output:"
    sed -n '1,40p' "$HOME_DIR/serve.out"
    exit 2
  fi

  local request_body='{}'
  if [[ "$target" == */approve ]]; then
    local review_digest
    review_digest="$(curl -sS -m "$TIMEOUT" "http://127.0.0.1:$PORT${target%/approve}/changes" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("pendingDigest") or "0"*64)')"
    request_body="{\"expectedDigest\":\"$review_digest\"}"
  fi

  local -a args=(-sS -m "$TIMEOUT" -o "$HOME_DIR/body" -w '%{http_code}' -X "$method"
                 "http://127.0.0.1:$PORT$target" -H 'content-type: application/json'
                 --data-binary "$request_body")
  [ -z "$no_token" ] && args+=(-H "x-mcpr-token: $TOKEN")

  local status; status="$(curl "${args[@]}" 2>/dev/null || echo 000)"
  local body; body="$(cat "$HOME_DIR/body")"

  # 000 is curl failing to reach the daemon. Comparing that against an expectation would let a dead
  # socket satisfy a check whose expectation happened to be empty.
  if [ "$status" = "000" ]; then
    echo "environment: curl could not reach the daemon for \"$label\""
    exit 2
  fi

  if [ "$status" = "$want_status" ] && { [ "$want_body" = "-" ] || [ "$body" = "$want_body" ]; }; then
    printf '  ok   %-52s %s\n' "$label" "$status"
    pass=$((pass + 1))
  else
    printf '  FAIL %-52s got %s (wanted %s)\n' "$label" "$status" "$want_status"
    [ "$want_body" != "-" ] && printf '       body: %s\n       want: %s\n' "$body" "$want_body"
    fail=$((fail + 1)); failures+=("$label")
  fi
}

echo "P1 — POST /servers/:name/approve and POST /servers/:name/auth, on the daemon's own socket"
echo

echo "the routes answer at all — this is the whole of D-j"
check "approve, no pending change" POST "/servers/p1-quiet/approve" \
  409 '{"error":"no pending change for \"p1-quiet\""}'
check "auth on a stdio server" POST "/servers/p1-quiet/auth" \
  400 '{"error":"stdio servers do not authorize; their credentials are env vars"}'

echo
echo "the gates that run in front of them"
check "approve on an unknown server is 404" POST "/servers/ghost/approve" \
  404 '{"error":"no server named \"ghost\""}'
check "auth on an unknown server is 404" POST "/servers/ghost/auth" \
  404 '{"error":"no server named \"ghost\""}'
check "untokened approve is 401" POST "/servers/p1-quiet/approve" 401 - --no-token
check "untokened auth is 401" POST "/servers/p1-quiet/auth" 401 - --no-token

echo
echo "the write path: approve promotes, and the manifest on disk says so"
check "approve with a pending change" POST "/servers/p1-held/approve" \
  200 '{"server":"p1-held","approved":2}'

# The bytes, not the reply. A route that answers 200 and writes nothing is the worse of the two
# failures, and it is the one a status-only assertion cannot see. Matched with `tr -d` so the
# assertion is about what was written rather than about the writer's whitespace.
flat="$(tr -d ' \n' <"$HOME_DIR/manifest.json")"
if printf '%s' "$flat" | grep -q '"pending"'; then
  printf '  FAIL %-52s pending survived the approve\n' "the pending block is gone from disk"
  fail=$((fail + 1)); failures+=("pending survived")
else
  printf '  ok   %-52s removed\n' "the pending block is gone from disk"
  pass=$((pass + 1))
fi
if printf '%s' "$flat" | grep -q '{"name":"a"},{"name":"b"}'; then
  printf '  ok   %-52s promoted\n' "the pending tools are now the served tools"
  pass=$((pass + 1))
else
  printf '  FAIL %-52s not promoted; manifest reads: %s\n' "the pending tools are now the served tools" "$flat"
  fail=$((fail + 1)); failures+=("tools not promoted")
fi

check "approving twice is 409 the second time" POST "/servers/p1-held/approve" \
  409 '{"error":"no pending change for \"p1-held\""}'

# B94, and it is asserted HERE rather than in the unit suite for a reason: a test can inject a log
# into `ControlDeps`, but until this change `RouterServiceDispatch.controlResponse` built its deps
# without one, so the daemon — the only process that ships — passed nil and the line was
# unemittable. Every unit test still passed. This is the assertion that catches that class.
if grep -q 'approved "p1-held"'"'"'s new tool surface (2 tools)' "$HOME_DIR/router.log"; then
  printf '  ok   %-52s logged\n' "B94: the approval is on the record"
  pass=$((pass + 1))
else
  printf '  FAIL %-52s the daemon logged no approval line\n' "B94: the approval is on the record"
  printf '       serve.out tail: %s\n' "$(tail -3 "$HOME_DIR/serve.out" | tr '\n' ' ')"
  fail=$((fail + 1)); failures+=("B94 approval line missing")
fi

echo
echo "the half this router did NOT serve until P7 — asserted on the daemon, not just in the suite"
# D-p1-a, closed. `OAuthFlowStarter` is now wired into `RouterServiceDispatch`, so a non-stdio
# `/auth` begins a real flow instead of falling through to the 405 this route used to answer.
#
# The upstream is `https://example.invalid/mcp`, a name RFC 2606 guarantees will never resolve, so
# the flow binds its callback port, fails to reach the provider, and loses the 20-second race for an
# authorization URL — which is exactly what the reference does with the same config, byte for byte.
# `scripts/acceptance/parity-oauth.sh` is what proves the SUCCESS path against the running
# reference; this asserts the route is dispatched at all in the daemon, which is what D-r2r-b is
# about and what a unit suite injecting its own `ControlDeps` cannot see.
TIMEOUT=40
check "http auth begins a flow and races the provider" POST "/servers/p1-http/auth" \
  502 '{"error":"the server never produced an authorization URL"}'
TIMEOUT=5
check "and approve on that same http server still works" POST "/servers/p1-http/approve" \
  409 '{"error":"no pending change for \"p1-http\""}'

echo
if [ "$fail" -eq 0 ]; then
  echo "$pass passed, 0 failed — both routes are reachable on the wire, not only through ControlDiff."
  exit 0
fi
echo "$pass passed, $fail failed:"
for item in "${failures[@]}"; do echo "  - $item"; done
exit 1
