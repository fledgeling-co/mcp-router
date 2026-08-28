#!/usr/bin/env bash
#
# R28 — the `/extensions` family, over the daemon's own socket.
#
# The unit suite drives `ControlHandler.handle` with a `ControlDeps` a test constructed, so it can
# prove the routes and it cannot prove the DAEMON routes them. That gap has bitten this repository
# twice already: `GET /registry/search` had a fully implemented, unit-tested search pipeline and no
# HTTP client in `RouterServiceDispatch`, so the one process that ships answered 502 while every
# check was green (the `control-registry-search` row); and `POST /servers/:name/auth` answered 405
# for the same reason until P7 (`D-p1-a`). `ControlDeps.extensions` is optional for the same reason
# theirs are, so exactly the same defect is available here — one missing line in
# `RouterServiceDispatch.controlDeps()` and every route below answers 503 with the suite passing.
#
# So this asks the one question the suite cannot: does the real `MCPRouterCLI serve`, its
# `LoopbackHTTPServer` and its own `ControlDeps` answer this family?
#
# SCOPE: the extension routes and the gates in front of them, and nothing else. No other route was
# changed by this item and re-running checks over surfaces it did not touch is waste.
#
# Exit codes follow the house pattern:
#   0  every assertion held
#   1  the daemon answered, and answered something wrong
#   2  the environment could not run the check — the binary is missing, or the daemon never bound.
#      Distinct because a daemon that never started must not read as a passing check.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
HOME_DIR="$(mktemp -d -t mcprouter-r28)"
PORT="${PORT:-8986}"
ROUTER_PID=""

pass=0
fail=0
declare -a failures=()

# The machine-wide parity lock: this binds a fixed port, exactly as the parity lanes do, and two
# runs contending for it is the failure that prints a number nobody could have measured.
. "$REPO_ROOT/scripts/acceptance/parity-lock.sh"

cleanup() {
  parity_lock_release
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null
  wait "$ROUTER_PID" 2>/dev/null
  rm -rf "$HOME_DIR"
}
trap cleanup EXIT INT TERM HUP

parity_lock_acquire "r28-extensions.sh"

[ -x "$SWIFT_BIN" ] || { echo "environment: no MCPRouterCLI at $SWIFT_BIN (run: make build-cli-debug)"; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "environment: curl is not installed"; exit 2; }

# Two servers, so the inventory's `servers` count is a number this script chose rather than
# whatever the developer's own config happens to hold.
cat >"$HOME_DIR/servers.json" <<'JSON'
{
  "mcpServers": {
    "r28-a": { "command": "/bin/echo", "args": ["a"] },
    "r28-b": { "command": "/bin/echo", "args": ["b"] }
  }
}
JSON

MCP_ROUTER_HOME="$HOME_DIR" "$SWIFT_BIN" serve --port "$PORT" >"$HOME_DIR/serve.out" 2>&1 &
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

# One request. Status AND a substring of the body, because a route that returns the right number
# with the wrong bytes is still wrong — and on an inventory the body carries the whole answer.
check() { # label method target want-status want-substring(or "-") [--no-token]
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

  # 000 is curl failing to reach the daemon. Comparing that against an expectation would let a dead
  # socket satisfy a check whose expectation happened to be empty.
  if [ "$status" = "000" ]; then
    echo "environment: curl could not reach the daemon for \"$label\""
    exit 2
  fi

  if [ "$status" = "$want_status" ] && { [ "$want_body" = "-" ] || case "$body" in *"$want_body"*) true ;; *) false ;; esac; }; then
    printf '  ok   %-56s %s\n' "$label" "$status"
    pass=$((pass + 1))
  else
    printf '  FAIL %-56s got %s (wanted %s)\n' "$label" "$status" "$want_status"
    [ "$want_body" != "-" ] && printf '       body: %s\n       want to contain: %s\n' "$body" "$want_body"
    fail=$((fail + 1)); failures+=("$label")
  fi
}

on_disk() { # label path present|absent
  local label="$1" path="$2" want="$3"
  if [ -e "$path" ] && [ "$want" = present ]; then
    printf '  ok   %-56s present\n' "$label"; pass=$((pass + 1))
  elif [ ! -e "$path" ] && [ "$want" = absent ]; then
    printf '  ok   %-56s absent\n' "$label"; pass=$((pass + 1))
  else
    printf '  FAIL %-56s wanted %s at %s\n' "$label" "$want" "$path"
    fail=$((fail + 1)); failures+=("$label")
  fi
}

SKILL='{"name":"r28-skill","files":[{"path":"SKILL.md","text":"---\nname: r28-skill\ndescription: added over the wire\n---\n"}]}'
PLUGIN='{"name":"r28-plugin","files":[{"path":".claude-plugin/plugin.json","text":"{\"name\":\"r28-plugin\",\"description\":\"a plugin\"}"}]}'
MARKET='{"name":"r28-market","files":[{"path":".claude-plugin/marketplace.json","text":"{\"name\":\"r28-market\",\"plugins\":[]}"}]}'

echo "R28 — /extensions on the daemon's own socket, home $HOME_DIR"
echo
echo "the family is routed at all — this is the whole of the missing-wiring class"
check "GET /extensions before anything is held" GET "/extensions" 200 \
  '"counts":{"servers":2,"skills":0,"plugins":0,"marketplaces":0}'

echo
echo "add each kind, and list it"
check "POST a skill"        POST "/extensions/skills" 201 '"added":"r28-skill"' "$SKILL"
check "POST a plugin"       POST "/extensions/plugins" 201 '"added":"r28-plugin"' "$PLUGIN"
check "POST a marketplace"  POST "/extensions/marketplaces" 201 '"added":"r28-market"' "$MARKET"
check "the skill is listed"       GET "/extensions/skills" 200 '"title":"r28-skill"'
check "the plugin is listed"      GET "/extensions/plugins" 200 '"title":"r28-plugin"'
check "the marketplace is listed" GET "/extensions/marketplaces" 200 '"title":"r28-market"'
check "one request counts all four kinds" GET "/extensions" 200 \
  '"counts":{"servers":2,"skills":1,"plugins":1,"marketplaces":1}'

# The bytes, not the reply. A route that answers 201 and writes nothing is the worse of the two
# failures and the one a status assertion cannot see.
on_disk "the skill's own file is under the router's home" \
  "$HOME_DIR/extensions/skills/r28-skill/SKILL.md" present
on_disk "the plugin's descriptor is too" \
  "$HOME_DIR/extensions/plugins/r28-plugin/.claude-plugin/plugin.json" present

echo
echo "the reading is of the disk, not of a registry"
mkdir -p "$HOME_DIR/extensions/skills/hand-written"
printf -- '---\nname: hand-written\ndescription: nothing wrote this through the API\n---\n' \
  >"$HOME_DIR/extensions/skills/hand-written/SKILL.md"
check "a skill written behind the router's back is listed" GET "/extensions/skills" 200 \
  '"name":"hand-written"'
rm -rf "$HOME_DIR/extensions/skills/hand-written"
check "and gone again once it is deleted" GET "/extensions/skills" 200 '"count":1'

echo
echo "a malformed one is refused rather than half-registered"
check "no frontmatter"     POST "/extensions/skills" 400 '"reason":"malformedDescriptor"' \
  '{"name":"r28-bad","files":[{"path":"SKILL.md","text":"nope"}]}'
check "a path that escapes" POST "/extensions/skills" 400 '"reason":"invalidFilePath"' \
  '{"name":"r28-bad","files":[{"path":"../out.md","text":"x"}]}'
check "a name that escapes" POST "/extensions/skills" 400 '"reason":"invalidName"' \
  '{"name":"../r28-bad","files":[{"path":"SKILL.md","text":"---\nname: x\n---\n"}]}'
check "a descriptor naming something else" POST "/extensions/skills" 400 '"reason":"nameMismatch"' \
  '{"name":"r28-bad","files":[{"path":"SKILL.md","text":"---\nname: other\n---\n"}]}'
check "adding one that exists"  POST "/extensions/skills" 409 '"reason":"nameTaken"' "$SKILL"
on_disk "nothing was left half-written" "$HOME_DIR/extensions/skills/r28-bad" absent
# The staging directory itself is the store's workspace and outlives an add; what must never
# survive is an ENTRY inside it. The first form of this check asserted the directory was absent,
# went red on a successful add, and was wrong rather than the code being wrong — an assertion
# aimed one level too high. Kept as a count so it still fails on wreckage.
staged="$(ls -A "$HOME_DIR/extensions/.staging" 2>/dev/null | wc -l | tr -d ' ')"
if [ "$staged" = "0" ]; then
  printf '  ok   %-56s empty\n' "nothing was left staged"; pass=$((pass + 1))
else
  printf '  FAIL %-56s %s entries under .staging\n' "nothing was left staged" "$staged"
  fail=$((fail + 1)); failures+=("staged wreckage")
fi
check "the collection still holds one"  GET "/extensions/skills" 200 '"count":1'

echo
echo "the gates in front of it"
check "an untokened POST is 401" POST "/extensions/skills" 401 - "$SKILL" --no-token
check "an unknown kind is 404"   GET "/extensions/widgets" 404 'no extension kind named'
check "an unknown entry is 404"  GET "/extensions/skills/ghost" 404 'no skill named'
check "a method it does not serve is 405" PATCH "/extensions/skills" 405 - '{}'

echo
echo "remove each kind, reversibly"
check "DELETE the skill"       DELETE "/extensions/skills/r28-skill" 200 '"removed":"r28-skill"'
check "DELETE the plugin"      DELETE "/extensions/plugins/r28-plugin" 200 '"removed":"r28-plugin"'
check "DELETE the marketplace" DELETE "/extensions/marketplaces/r28-market" 200 '"removed":"r28-market"'
check "the inventory is back to zero" GET "/extensions" 200 \
  '"counts":{"servers":2,"skills":0,"plugins":0,"marketplaces":0}'
on_disk "the entry is gone from the kind directory" \
  "$HOME_DIR/extensions/skills/r28-skill" absent
# Reversible: removal moves rather than deletes, and the reply named where. Found by glob because
# the destination is stamped with the millisecond it happened at.
removed_skill="$(find "$HOME_DIR/extensions/.removed/skills/r28-skill" -name SKILL.md 2>/dev/null | head -1)"
on_disk "and its bytes are still under .removed" "${removed_skill:-/nonexistent}" present

echo
echo "nothing under \$HOME/.claude was touched — this item holds, it does not migrate"
if grep -q "\.claude/skills\|\.claude/plugins" "$HOME_DIR/serve.out"; then
  printf '  FAIL %-56s the daemon logged a path under ~/.claude\n' "Claude's own directories"
  fail=$((fail + 1)); failures+=("claude paths")
else
  printf '  ok   %-56s no ~/.claude path in the daemon log\n' "Claude's own directories"
  pass=$((pass + 1))
fi

echo
echo "r28-extensions: $pass ok, $fail failed"
if [ "$fail" -gt 0 ]; then
  printf '  failed: %s\n' "${failures[@]}"
  exit 1
fi
exit 0
