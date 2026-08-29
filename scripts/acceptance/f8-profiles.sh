#!/usr/bin/env bash
#
# F8 — the `/profiles` family, over the daemon's own socket.
#
# The unit suite drives `ControlHandler.handle` with a `ControlDeps` a test constructed, so it can
# prove the routes and it cannot prove the DAEMON routes them. `ControlDeps.profiles` and
# `ControlDeps.skillRoots` are optional for the reason `extensions` is, so exactly the defect this
# repository has already paid for twice is available here: one missing line in
# `RouterServiceDispatch.controlDeps()` and every route below answers 503 with the suite green
# (`D-p1-a`, and the `control-registry-search` row).
#
# So this asks the one question the suite cannot: does the real `MCPRouterCLI serve`, its
# `LoopbackHTTPServer` and its own `ControlDeps` answer this family?
#
# HOME IS A SCRATCH DIRECTORY AND THAT IS LOAD-BEARING. `DiskSkillRoots` reads whatever `$HOME`
# names, so a lane pointed at the developer's own home would put somebody's real `~/.cursor/skills`
# inside a gate run and report a different body on every machine. The skill roots this lane reads
# are built by this lane, under its own scratch home, and torn down with it — which is the same
# discipline `div-m22-harnesses` records for `GET /harnesses`.
#
# SCOPE: the profile routes and the gates in front of them, and nothing else.
#
# Exit codes follow the house pattern:
#   0  every assertion held
#   1  the daemon answered, and answered something wrong
#   2  the environment could not run the check — the binary is missing, or the daemon never bound.
#      Distinct because a daemon that never started must not read as a passing check.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
HOME_DIR="$(mktemp -d -t mcprouter-f8)"
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

parity_lock_acquire "f8-profiles.sh"

[ -x "$SWIFT_BIN" ] || { echo "environment: no MCPRouterCLI at $SWIFT_BIN (run: make build-cli-debug)"; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "environment: curl is not installed"; exit 2; }

# One server, so the profile's `servers` selection is measured against a set this script chose.
cat >"$HOME_DIR/servers.json" <<'JSON'
{
  "mcpServers": {
    "f8-a": { "command": "/bin/echo", "args": ["a"] }
  }
}
JSON

# A scratch Cursor skills root holding one LIVE link and one DANGLING one — the state the item
# exists for, built here rather than hoped for. `alive` resolves; `design-craft` points at a
# directory this script then removes, which is exactly how the 27 real ones came to be.
mkdir -p "$HOME_DIR/.cursor/skills" "$HOME_DIR/targets/alive" "$HOME_DIR/targets/doomed"
ln -s "$HOME_DIR/targets/alive" "$HOME_DIR/.cursor/skills/alive"
ln -s "$HOME_DIR/targets/doomed" "$HOME_DIR/.cursor/skills/design-craft"
rmdir "$HOME_DIR/targets/doomed"

# The router home is a directory of its own INSIDE the scratch home, so `$HOME` can be the scratch
# tree — which is what makes the skill roots this lane reads its own.
ROUTER_HOME="$HOME_DIR/router"
mkdir -p "$ROUTER_HOME"
cp "$HOME_DIR/servers.json" "$ROUTER_HOME/servers.json"

HOME="$HOME_DIR" MCP_ROUTER_HOME="$ROUTER_HOME" "$SWIFT_BIN" serve --port "$PORT" \
  >"$HOME_DIR/serve.out" 2>&1 &
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

TOKEN="$(cat "$ROUTER_HOME/control.token" 2>/dev/null || echo '')"
[ -n "$TOKEN" ] || { echo "environment: the daemon minted no control token"; exit 2; }

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
    printf '  ok   %-58s %s\n' "$label" "$want"; pass=$((pass + 1))
  else
    printf '  FAIL %-58s wanted %s at %s\n' "$label" "$want" "$path"
    fail=$((fail + 1)); failures+=("$label")
  fi
}

SKILL='{"name":"design-craft","files":[{"path":"SKILL.md","text":"---\nname: design-craft\ndescription: a skill this lane added\n---\n"}]}'

echo "F8 — /profiles on the daemon's own socket"
echo "  scratch HOME   $HOME_DIR"
echo "  router home    $ROUTER_HOME"
echo

echo "the family is routed at all — this is the whole of the missing-wiring class"
check "GET /profiles is answered, not 404 or 503"   GET /profiles 200 '"count":0'
echo

echo "the round trip"
check "POST a profile"           POST "/profiles/frontend" 200 '"name":"frontend"' \
  '{"title":"Frontend","skills":["design-craft"],"servers":["f8-a"]}'
check "it is listed"             GET  /profiles 200 '"count":1'
check "it reads back"            GET  "/profiles/frontend" 200 '"title":"Frontend"'
on_disk "and it is on the router's own disk" "$ROUTER_HOME/profiles/frontend.json" present
echo

echo "the projection — and the reach split it exists to state"
# The store holds nothing yet, so the skill is `missing-from-store` rather than projected onto a
# harness. That is the ordinary state of a fresh router and it must not read as a failure.
check "a skill the store lacks is missing-from-store" GET "/profiles/frontend/projection" 200 \
  '"action":"missing-from-store"'
check "and the body says it applies nothing"          GET "/profiles/frontend/projection" 200 \
  '"applies":false'
check "the server step reaches the other binary"      GET "/profiles/frontend/projection" 200 \
  '"tell-elsewhere":1'
check "add the skill to the router's store"           POST "/extensions/skills" 201 '"added"' "$SKILL"
# Now it projects onto the scratch Cursor root, where the link is dangling — so the action is a
# REPAIR naming the target, not an install. This is the reading the item was written for, taken on
# the daemon rather than in a unit test.
check "the dangling link is a repair, not an add"     GET "/profiles/frontend/projection" 200 \
  '"action":"repair"'
check "and the repair names what the link claims"     GET "/profiles/frontend/projection" 200 \
  "$HOME_DIR/targets/doomed"
check "the harnesses with no skill root are named"    GET "/profiles/frontend/projection" 200 \
  '"withoutSkillRoot"'
echo

echo "nothing was applied — the whole of the boundary, measured on disk rather than in the reply"
on_disk "the dangling link is still dangling"  "$HOME_DIR/targets/doomed" absent
on_disk "the live link is untouched"           "$HOME_DIR/.cursor/skills/alive" present
if [ -L "$HOME_DIR/.cursor/skills/design-craft" ]; then
  printf '  ok   %-58s still a broken link\n' "the router repaired nothing"; pass=$((pass + 1))
else
  printf '  FAIL %-58s the router changed a harness tree\n' "the router repaired nothing"
  fail=$((fail + 1)); failures+=("the router repaired nothing")
fi
cursor_entries="$(ls -A "$HOME_DIR/.cursor/skills" | wc -l | tr -d ' ')"
if [ "$cursor_entries" = "2" ]; then
  printf '  ok   %-58s 2\n' "the harness root still holds exactly what it held"; pass=$((pass + 1))
else
  printf '  FAIL %-58s %s (wanted 2)\n' "the harness root still holds exactly what it held" "$cursor_entries"
  fail=$((fail + 1)); failures+=("harness root entry count")
fi
echo

echo "the gates in front of the family"
check "an untokened POST is 401, before the store is consulted" POST "/profiles/x" 401 '-' '{}' --no-token
check "PUT is not served — it is outside the token gate's set"  PUT  "/profiles/x" 405 '-' '{}'
check "a name that escapes the store is refused"                POST "/profiles/..%2Fesc" 400 \
  '"reason":"bad-name"' '{}'
check "a member of the wrong shape is refused"                  POST "/profiles/y" 400 \
  'must be an array of strings' '{"skills":"one"}'
check "an unknown profile is 404"                               GET  "/profiles/nope" 404 '-'
echo

echo "the removal is reversible"
check "DELETE reports where the bytes went" DELETE "/profiles/frontend" 200 '"restorePath"'
on_disk "and they are there"                "$ROUTER_HOME/profiles/.removed/frontend" present
on_disk "and the profile is gone"           "$ROUTER_HOME/profiles/frontend.json" absent
echo

if [ "$pass" -eq 0 ]; then
  echo "instrument: no assertion ran, so nothing was compared"
  exit 2
fi
echo "f8-profiles: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  printf '  failed: %s\n' "${failures[@]}"
  exit 1
fi
exit 0
