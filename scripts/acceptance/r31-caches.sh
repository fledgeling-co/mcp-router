#!/usr/bin/env bash
#
# R31 — the `/caches` family, over the daemon's own socket, against real directories.
#
# TWO things the unit suite structurally cannot see, and they are different in kind.
#
# The first is R28's lesson repeated: `ControlDeps.caches` is optional exactly as `extensions`,
# `registry` and `authFlow` are, and both of the latter shipped nil in `RouterServiceDispatch` with
# a green suite — `GET /registry/search` answered 502 in the only process that ships, and
# `POST /servers/:name/auth` answered 405 until P7. Deleting the one `caches:` line here leaves
# every unit test passing and turns this whole lane into 503s.
#
# The second is this item's own: the suite drives a stub probe, so **nothing in it deletes a
# directory**. A plan that reports a removal it did not perform, and a removal that takes a
# neighbouring tree with it, are both invisible to a stub and both are what an invalidation lane is
# for. Every removal assertion below is on the filesystem rather than on the reply.
#
# EVERY PATH IS INSIDE A SCRATCH HOME. `MCP_ROUTER_CACHE_HOME` moves both cache roots together, and
# the last check in this file proves it did — the operator's own `~/.npm/_npx` was 2.0 GB across 48
# entries when this was written, and a lane that reached it would be spending somebody's disk to
# make a point.
#
# Exit codes follow the house pattern:
#   0  every assertion held
#   1  the daemon answered, and answered something wrong
#   2  the environment could not run the check — the binary is missing, or the daemon never bound.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
HOME_DIR="$(mktemp -d -t mcprouter-r31)"
PORT="${PORT:-8987}"
ROUTER_PID=""

pass=0
fail=0
declare -a failures=()

. "$REPO_ROOT/scripts/acceptance/parity-lock.sh"

cleanup() {
  parity_lock_release
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null
  wait "$ROUTER_PID" 2>/dev/null
  rm -rf "$HOME_DIR"
}
trap cleanup EXIT INT TERM HUP

parity_lock_acquire "r31-caches.sh"

[ -x "$SWIFT_BIN" ] || { echo "environment: no MCPRouterCLI at $SWIFT_BIN (run: make build-cli-debug)"; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "environment: curl is not installed"; exit 2; }

# The real cache, counted before anything runs. Read-only, and it is the denominator for the last
# check in this file rather than decoration.
REAL_NPX="$HOME/.npm/_npx"
real_before="$(ls -1 "$REAL_NPX" 2>/dev/null | wc -l | tr -d ' ')"

# ------------------------------------------------------------------ the fixture
#
# Two npx entries for one package and one for another, plus an entry naming no package at all —
# the shape measured on this machine, where two of the 48 entries hold no readable package.json.
CACHE_HOME="$HOME_DIR/cache-home"
NPX="$CACHE_HOME/.npm/_npx"
PLUGINS="$CACHE_HOME/.claude/plugins/cache"

mkdir -p "$NPX/aaa/node_modules/r31-pkg" "$NPX/bbb/node_modules/r31-pkg" \
         "$NPX/ccc/node_modules/r31-other" "$NPX/ddd/node_modules" \
         "$PLUGINS/r31-market/r31-plug/1.0.0" "$PLUGINS/r31-market/r31-plug/2.0.0" \
         "$PLUGINS/temp_git_r31"
printf '{"dependencies":{"r31-pkg":"^1.0.0"}}' >"$NPX/aaa/package.json"
printf '{"dependencies":{"r31-pkg":"^1.0.0"}}' >"$NPX/bbb/package.json"
printf '{"dependencies":{"r31-other":"^2.0.0"}}' >"$NPX/ccc/package.json"
printf '{"name":"r31-pkg","version":"1.0.0"}'   >"$NPX/aaa/node_modules/r31-pkg/package.json"
printf '{"name":"r31-pkg","version":"1.0.0"}'   >"$NPX/bbb/node_modules/r31-pkg/package.json"
printf '{"name":"r31-other","version":"2.0.0"}' >"$NPX/ccc/node_modules/r31-other/package.json"

cat >"$HOME_DIR/servers.json" <<'JSON'
{
  "mcpServers": {
    "r31-npx": { "command": "npx", "args": ["-y", "r31-pkg@1.0.0"] },
    "r31-local": { "command": "/bin/echo", "args": ["hello"] }
  }
}
JSON

MCP_ROUTER_HOME="$HOME_DIR" MCP_ROUTER_CACHE_HOME="$CACHE_HOME" \
  "$SWIFT_BIN" serve --port "$PORT" >"$HOME_DIR/serve.out" 2>&1 &
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

TIMEOUT=5

check() { # label method target want-status want-substring(or "-") [data] [--no-token]
  local label="$1" method="$2" target="$3" want_status="$4" want_body="$5" data="${6:-}" no_token="${7:-}"

  if ! kill -0 "$ROUTER_PID" 2>/dev/null; then
    echo "environment: the daemon exited before \"$label\" — its output:"
    sed -n '1,40p' "$HOME_DIR/serve.out"
    exit 2
  fi

  local -a args=(-sS -m "$TIMEOUT" -o "$HOME_DIR/body" -w '%{http_code}' -X "$method"
                 "http://127.0.0.1:$PORT$target" -H 'content-type: application/json')
  [ -n "$data" ] && args+=(--data-binary "$data")
  [ -z "$no_token" ] && args+=(-H "x-mcpr-token: $TOKEN")

  local status; status="$(curl "${args[@]}" 2>/dev/null || echo 000)"
  local body; body="$(cat "$HOME_DIR/body")"

  if [ "$status" = "000" ]; then
    echo "environment: curl could not reach the daemon for \"$label\""
    exit 2
  fi

  if [ "$status" = "$want_status" ] && { [ "$want_body" = "-" ] || case "$body" in *"$want_body"*) true ;; *) false ;; esac; }; then
    printf '  ok   %-58s %s\n' "$label" "$status"
    pass=$((pass + 1))
  else
    printf '  FAIL %-58s got %s (wanted %s)\n' "$label" "$status" "$want_status"
    [ "$want_body" != "-" ] && printf '       body: %s\n       want to contain: %s\n' "$body" "$want_body"
    fail=$((fail + 1)); failures+=("$label")
  fi
}

on_disk() { # label path present|absent
  local label="$1" path="$2" want="$3"
  if { [ -e "$path" ] && [ "$want" = present ]; } || { [ ! -e "$path" ] && [ "$want" = absent ]; }; then
    printf '  ok   %-58s %s\n' "$label" "$want"
    pass=$((pass + 1))
  else
    printf '  FAIL %-58s wanted %s at %s\n' "$label" "$want" "$path"
    fail=$((fail + 1)); failures+=("$label")
  fi
}

echo "R31 — /caches on the daemon's own socket, home $HOME_DIR"
echo
echo "the family is routed at all — the missing-wiring class"
check "GET /caches answers"            GET "/caches" 200 '"cache":"npx"'
check "it covers the manifest cache"   GET "/caches" 200 '"cache":"manifest"'
check "and the plugin cache"           GET "/caches" 200 '"cache":"plugins"'
check "every row names what re-fetches it" GET "/caches" 200 '"refetch":"npx -y r31-pkg@^1.0.0"'
check "a plugin version names its marketplace" GET "/caches" 200 \
  '"refetch":"claude plugin install r31-plug@1.0.0 --marketplace r31-market"'
# Two: the npx entry with no package.json, and the clone leftover with no plugin layout.
check "the rows nothing can re-fetch are counted" GET "/caches" 200 '"irreplaceable":1'

echo
echo "planning is the default, and a plan changes nothing"
check "a server plan lists the tree and the re-index" POST "/caches/invalidate" 200 \
  '"effect":"reindex-server"' '{"server":"r31-npx"}'
check "and says it was not applied"    POST "/caches/invalidate" 200 '"applied":false' '{"server":"r31-npx"}'
on_disk "the tree is still there after a plan" "$NPX/aaa" present
on_disk "and so is the other package's"       "$NPX/ccc" present

echo
echo "applying removes exactly what was named — asserted on the filesystem, not on the reply"
check "apply the server target" POST "/caches/invalidate" 200 '"applied":true' \
  '{"server":"r31-npx","apply":true}'
on_disk "both entries for the named package are gone" "$NPX/aaa" absent
on_disk "the second one too"                          "$NPX/bbb" absent
on_disk "the OTHER package's entry is untouched"      "$NPX/ccc" present
on_disk "the entry naming no package is untouched"    "$NPX/ddd" present
on_disk "and no plugin version was taken with it"     "$PLUGINS/r31-market/r31-plug/1.0.0" present

echo
echo "one plugin version, not the plugin"
check "apply one version" POST "/caches/invalidate" 200 '"applied":true' \
  '{"plugin":"r31-market/r31-plug/1.0.0","apply":true}'
on_disk "that version is gone"            "$PLUGINS/r31-market/r31-plug/1.0.0" absent
on_disk "the other version is still here" "$PLUGINS/r31-market/r31-plug/2.0.0" present

echo
echo "the wholesale clear says so and asks, rather than clearing quietly"
check "it is refused without its cost" POST "/caches/invalidate" 409 '"reason":"cost-not-acknowledged"' \
  '{"everyNpxEntry":true,"apply":true}'
on_disk "and nothing went"  "$NPX/ccc" present
check "a wrong figure is refused too"  POST "/caches/invalidate" 409 '"reason":"cost-not-acknowledged"' \
  '{"everyNpxEntry":true,"apply":true,"acknowledgeBytes":1}'
on_disk "still nothing went" "$NPX/ccc" present
# The figure the router just measured, read back out of its own refusal.
COST="$(curl -sS -m "$TIMEOUT" -X POST "http://127.0.0.1:$PORT/caches/invalidate" \
  -H 'content-type: application/json' -H "x-mcpr-token: $TOKEN" \
  --data-binary '{"everyNpxEntry":true}' 2>/dev/null \
  | sed -n 's/.*"fallbackBytes":\([0-9]*\).*/\1/p')"
if [ -n "$COST" ] && [ "$COST" -gt 0 ] 2>/dev/null; then
  printf '  ok   %-58s %s bytes\n' "the refusal names the cost of taking it anyway" "$COST"
  pass=$((pass + 1))
else
  printf '  FAIL %-58s no fallbackBytes in the refusal\n' "the refusal names the cost"
  fail=$((fail + 1)); failures+=("cost figure")
fi
check "named, it is taken" POST "/caches/invalidate" 200 '"applied":true' \
  "{\"everyNpxEntry\":true,\"apply\":true,\"acknowledgeBytes\":$COST}"
on_disk "the re-fetchable entry went"                 "$NPX/ccc" absent
on_disk "the one naming no package STILL did not"     "$NPX/ddd" present

echo
echo "the gates in front of it"
check "an untokened POST is 401"  POST "/caches/invalidate" 401 - '{"server":"r31-npx"}' --no-token
check "no target is 400"          POST "/caches/invalidate" 400 '"reason":"no-target"' '{}'
check "two targets is 400"        POST "/caches/invalidate" 400 '"reason":"no-target"' \
  '{"server":"r31-npx","npxPackage":"r31-other"}'
check "an unknown server is 404"  POST "/caches/invalidate" 404 '"reason":"no-such-server"' \
  '{"server":"ghost"}'
check "an unknown package is 404" POST "/caches/invalidate" 404 '"reason":"no-such-entry"' \
  '{"npxPackage":"never-fetched"}'
check "a method it does not serve is 405" PATCH "/caches" 405 - '{}'
check "a deeper path is not claimed"      GET "/caches/anything" 404 -

echo
echo "the scoping held — the operator's own npx cache was never reached"
real_after="$(ls -1 "$REAL_NPX" 2>/dev/null | wc -l | tr -d ' ')"
if [ "$real_before" = "$real_after" ]; then
  printf '  ok   %-58s %s entries, unchanged\n' "$REAL_NPX" "$real_after"
  pass=$((pass + 1))
else
  printf '  FAIL %-58s %s -> %s\n' "$REAL_NPX" "$real_before" "$real_after"
  fail=$((fail + 1)); failures+=("real npx cache changed")
fi
if grep -q "$REAL_NPX" "$HOME_DIR/serve.out" 2>/dev/null; then
  printf '  FAIL %-58s the daemon logged the real cache path\n' "no real path in the log"
  fail=$((fail + 1)); failures+=("real path logged")
else
  printf '  ok   %-58s none\n' "real cache paths in the daemon log"
  pass=$((pass + 1))
fi

echo
echo "r31-caches: $pass ok, $fail failed"
if [ "$fail" -gt 0 ]; then
  printf '  failed: %s\n' "${failures[@]}"
  exit 1
fi
exit 0
