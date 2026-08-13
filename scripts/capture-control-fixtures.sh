#!/bin/bash
#
# Capture the control API's real responses as test fixtures.
#
# Why capture rather than write them: a hand-authored fixture records what we *believe* the router
# sends. It agrees with the model by construction, so it can never catch the case that matters —
# the wire changing under a client that still compiles. These come off the real thing.
#
# It captures VARIANTS, not one happy path per endpoint. A single success sample per route leaves
# every conditional branch of a body untested: the 422 that carries a hint, the re-index failure
# that is structured rather than a bare status, a stdio server against an HTTP one, a server with
# a held change against one without. Those branches are where a decode breaks in front of a user.
#
# Exit codes follow the house pattern: 1 is a failed capture, 2 is an environment that could not
# run one. Collapsing them would report "node is missing" as "the router is broken".

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$REPO_ROOT/app/Sources/MCPRouterKit/Control/Fixtures}"
PORT="${PORT:-8971}"
OAUTH_PORT="${OAUTH_PORT:-8972}"
HOME_DIR="$(mktemp -d -t mcprouter-fixtures)"
ROUTER_PID=""
OAUTH_PID=""

cleanup() {
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null || true
  [ -n "$OAUTH_PID" ] && kill "$OAUTH_PID" 2>/dev/null || true
  rm -rf "$HOME_DIR"
}
trap cleanup EXIT

command -v node >/dev/null 2>&1 || { echo "error: node is not installed — cannot run the router"; exit 2; }
[ -f "$REPO_ROOT/dist/index.js" ] || { echo "error: dist/index.js is missing — run npm run build"; exit 2; }

mkdir -p "$OUT"

TOOLSET_FILE="$HOME_DIR/toolset"
echo a > "$TOOLSET_FILE"

# The upstream that demands OAuth. Started before the router so the first connection to it lands on
# a server that is already refusing in the way that begins a flow.
node "$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs" oauth >"$HOME_DIR/oauth.log" 2>&1 &
OAUTH_PID=$!

# Four servers, because the variants live in the differences between them:
#   fixture-stdio  a stdio server (a command, args and env keys)
#   fixture-http   an HTTP server that cannot be reached (the structured re-index failure)
#   fixture-tools  a real MCP server whose tool surface we can change under the router
#   fixture-oauth  an HTTP server that demands authorization (the in-flight auth)
cat > "$HOME_DIR/servers.json" <<JSON
{
  "mcpServers": {
    "fixture-stdio": { "command": "/bin/echo", "args": ["hello"], "env": { "FIXTURE_KEY": "x" } },
    "fixture-http": { "url": "https://example.invalid/mcp", "type": "http", "oauth": false },
    "fixture-tools": {
      "command": "node",
      "args": ["$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs", "stdio"],
      "env": { "FIXTURE_TOOLSET_FILE": "$TOOLSET_FILE" }
    },
    "fixture-oauth": { "url": "http://127.0.0.1:$OAUTH_PORT/mcp", "type": "http", "oauth": true }
  }
}
JSON

echo "starting the router on :$PORT with MCP_ROUTER_HOME=$HOME_DIR"
MCP_ROUTER_HOME="$HOME_DIR" node "$REPO_ROOT/dist/index.js" serve --port "$PORT" >"$HOME_DIR/router.log" 2>&1 &
ROUTER_PID=$!

for _ in $(seq 1 50); do
  if curl -fsS "http://127.0.0.1:$PORT/servers" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
curl -fsS "http://127.0.0.1:$PORT/servers" >/dev/null 2>&1 || {
  echo "error: the router did not answer on :$PORT"; sed -n '1,40p' "$HOME_DIR/router.log"; exit 2; }

TOKEN="$(cat "$HOME_DIR/control.token")"
auth=(-H "Authorization: Bearer $TOKEN" -H "content-type: application/json")

# `-f` is deliberately absent on the calls whose NON-2xx body is the thing being captured.
grab()    { curl -sS "$@" ; }
save()    { local f="$1"; shift; "$@" > "$OUT/$f"; echo "  wrote $f"; }

echo "capturing…"

# The router serves no tools until a server is in the manifest, and says so in its log rather than
# failing. Indexing here is what establishes fixture-tools' *approved* surface — the one the held
# change further down is a diff against.
grab -X POST "${auth[@]}" "http://127.0.0.1:$PORT/servers/fixture-tools/reindex" >/dev/null

save servers.json                grab "http://127.0.0.1:$PORT/servers"
save server-stdio.json           grab "http://127.0.0.1:$PORT/servers/fixture-stdio"
save server-http.json            grab "http://127.0.0.1:$PORT/servers/fixture-http"
save changes-none.json           grab "http://127.0.0.1:$PORT/servers/fixture-stdio/changes"
save registry-search.json        grab "http://127.0.0.1:$PORT/registry/search?q=github&limit=3"
save unauthorized.json           grab -X POST -H 'content-type: application/json' "http://127.0.0.1:$PORT/usage/reset"

# --- a real call, so the call log has something in it -------------------------------------------
# An empty `records` array agrees with any record model ever written, so it is the one fixture that
# has to be earned. This makes an actual tool call through the router and captures what it logged.
echo "making a real call through the router…"
if node "$REPO_ROOT/scripts/fixtures/call-through-router.mjs" "http://127.0.0.1:$PORT/mcp" ping; then
  :
else
  echo "error: could not call a tool through the router — the call log would be empty"; exit 1
fi

save usage.json                  grab "http://127.0.0.1:$PORT/usage"
save usage-summary.json          grab "http://127.0.0.1:$PORT/usage/summary"
save server-tools.json           grab "http://127.0.0.1:$PORT/servers/fixture-tools"

# --- a held tool-surface change ----------------------------------------------------------------
# The quarantine surface's whole subject. Surface B renames a tool, drops one, and rewrites a
# description to carry a zero-width space — so the captured diff exercises added, removed, changed
# and the `invisible` codepoint list in one response.
echo b > "$TOOLSET_FILE"
save reindex-held.json           grab -X POST "${auth[@]}" "http://127.0.0.1:$PORT/servers/fixture-tools/reindex"
save changes-pending.json        grab "http://127.0.0.1:$PORT/servers/fixture-tools/changes"
save server-pending-change.json  grab "http://127.0.0.1:$PORT/servers/fixture-tools"

# Approving is captured from the one state where it succeeds, which only exists for as long as the
# change above is held — so it runs here, and the "nothing to approve" conflict runs on a server
# that never had one.
save approve.json                grab -X POST "${auth[@]}" "http://127.0.0.1:$PORT/servers/fixture-tools/approve"
save approve-conflict.json       grab -X POST "${auth[@]}" "http://127.0.0.1:$PORT/servers/fixture-stdio/approve"

# --- an authorization the router is part-way through -------------------------------------------
# Opening the OAuth upstream makes the router record a flow rather than open a browser: it runs
# headless, so it writes the URL down and reports it on /servers as `pendingAuth`.
save auth-start.json             grab -X POST "${auth[@]}" "http://127.0.0.1:$PORT/servers/fixture-oauth/auth"
for _ in $(seq 1 25); do
  if grab "http://127.0.0.1:$PORT/servers" | grep -q '"pendingAuth"'; then break; fi
  sleep 0.2
done
save servers-pending-auth.json   grab "http://127.0.0.1:$PORT/servers"
grep -q '"pendingAuth"' "$OUT/servers-pending-auth.json" || {
  echo "error: no in-flight authorization was captured — the pendingAuth variant would be missing"
  sed -n '1,40p' "$HOME_DIR/oauth.log"; exit 1; }

# --- a server declared inoperative --------------------------------------------------------------
# `DESIGN.md` §5's Disabled state, as *data*. The router's placard says a server is inoperative and
# why, and optionally what to use instead — which is exactly "dims in place with a discoverable
# reason". A scenario that merely calls itself disabled asserts nothing; a reason the router really
# serves is the thing a surface can render.
save server-placarded.json       grab -X PATCH "${auth[@]}" \
  -d '{"placard":{"reason":"under review while the upstream is rebuilt","substitute":"fixture-tools"}}' \
  "http://127.0.0.1:$PORT/servers/fixture-http"
grep -q '"placard"' "$OUT/server-placarded.json" || {
  echo "error: no placard was captured — the disabled state would have no recording"; exit 1; }

# --- the remaining writes ----------------------------------------------------------------------
save patch-response.json         grab -X PATCH "${auth[@]}" -d '{"warm":false}' "http://127.0.0.1:$PORT/servers/fixture-stdio"
save reindex-failure.json        grab -X POST "${auth[@]}" "http://127.0.0.1:$PORT/servers/fixture-http/reindex"
save signout.json                grab -X DELETE "${auth[@]}" "http://127.0.0.1:$PORT/servers/fixture-http/auth"
save usage-reset.json            grab -X POST "${auth[@]}" "http://127.0.0.1:$PORT/usage/reset"

# The 422-with-hint: adding a server whose command cannot start. This is the branch that carries
# the router's advice, and the only place the client learns to offer "add it anyway".
save add-refused.json            grab -X POST "${auth[@]}" \
  -d '{"name":"fixture-broken","command":"/nonexistent/binary-that-cannot-start"}' \
  "http://127.0.0.1:$PORT/servers"

save added.json                  grab -X POST "${auth[@]}" \
  -d '{"name":"fixture-added","command":"/bin/echo","args":["hi"]}' \
  "http://127.0.0.1:$PORT/servers?force=1"

save removed.json                grab -X DELETE "${auth[@]}" "http://127.0.0.1:$PORT/servers/fixture-added"

for f in "$OUT"/*.json; do
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" \
    || { echo "error: $f is not valid JSON"; exit 1; }
done

echo "captured $(ls -1 "$OUT"/*.json | wc -l | tr -d ' ') fixtures into $OUT"
