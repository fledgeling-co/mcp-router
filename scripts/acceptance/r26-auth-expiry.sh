#!/usr/bin/env bash
#
# R26 — upstream credential expiry, over the daemon's own socket, against records planted on disk.
#
# THREE things the unit suite structurally cannot see.
#
# The first is R28's and R31's lesson repeated: `ControlDeps.authExpiry` is optional exactly as
# `caches`, `extensions`, `health`, `registry` and `authFlow` are, and two of those shipped nil in
# `RouterServiceDispatch` with a green suite — `GET /registry/search` answered 502 in the only
# process that ships, and `POST /servers/:name/auth` answered 405 until P7. Deleting the one
# `authExpiry:` line there leaves every unit test passing and turns this whole lane into 503s.
#
# The second is the THROTTLE, which is state held by the process across requests. A monitor built
# per request has delivered nothing yet, so it would re-issue every notice on every call and every
# unit test that makes one request would still pass.
#
# The third is this item's own and it is the one that matters. The expiry the router reports is
# `authorizedAt + expires_in` read out of a file — NOT the result of asking the upstream. That
# claim has an absence in it (nothing was spawned), and an absence is satisfied trivially by a
# feature that does nothing at all. So it is never asserted alone here: every zero-children reading
# below is PAIRED with a reading that changes when the planted file changes. The lane rewrites a
# credential record between two requests and requires the reported date to move with it.
#
# EVERY PATH IS INSIDE A SCRATCH HOME, on a port the campaign reserves, so the operator's own
# router at 127.0.0.1:8879 is never touched, and the operator's own `~/.claude/mcp-router/auth` is
# never read.
#
# Exit codes follow the house pattern:
#   0  every assertion held
#   1  the daemon answered, and answered something wrong
#   2  the environment could not run the check — the binary is missing, or the daemon never bound.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
HOME_DIR="$(mktemp -d -t mcprouter-r26)"
PORT="${PORT:-8978}"
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

parity_lock_acquire "r26-auth-expiry.sh"

[ -x "$SWIFT_BIN" ] || { echo "environment: no MCPRouterCLI at $SWIFT_BIN (run: make build-cli-debug)"; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "environment: curl is not installed"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "environment: python3 is not installed"; exit 2; }

# ------------------------------------------------------------------ the fixtures
#
# One stdio server whose command is a script of its OWN, so the process-table reading below is a
# fact about this server rather than arithmetic over a command line the others share. NOTHING
# should ever run it: a stdio upstream cannot be OAuth-authorised, so it has no credential to
# expire, and the report must reach that conclusion from its configuration without touching it.
cat >"$HOME_DIR/r26-local.py" <<'PY'
import sys
for line in sys.stdin:
    pass
PY

# `authorizedAt + expires_in`, written the way the router itself writes a record.
plant() { # name expires_in authorized-seconds-ago [refresh]
  local name="$1" expires="$2" ago="$3" refresh="${4:-}"
  python3 - "$HOME_DIR/auth/$name.json" "$expires" "$ago" "$refresh" <<'PY'
import json, sys, time, os
path, expires, ago, refresh = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
tokens = {"access_token": "planted-by-the-lane"}
if expires != "none":
    tokens["expires_in"] = float(expires)
if refresh:
    tokens["refresh_token"] = refresh
rec = {"tokens": tokens}
stamp = time.time() - ago
rec["authorizedAt"] = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(stamp)) + ".000Z"
os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
with open(path, "w") as fh:
    json.dump(rec, fh, indent=2)
os.chmod(path, 0o600)
PY
}

mkdir -p "$HOME_DIR/auth"
chmod 700 "$HOME_DIR/auth"
# An hour's life, two hours ago: expired.
plant r26-expired 3600 7200
# A day's life, twenty-three hours ago: one hour left, inside the default window.
plant r26-expiring 86400 82800
# A token with no declared lifetime. This is the vacuity arm: it must NOT read `valid`.
plant r26-unknown none 60
# A week's life, minted now, with a refresh token: nothing to say about it at all.
plant r26-fine 604800 0 a-refresh-token

# `warnWithinMs` is below the floor on purpose, so the refusal is on the wire in the same reply as
# the states it did not get to influence.
cat >"$HOME_DIR/servers.json" <<JSON
{
  "authExpiry": { "warnWithinMs": 500 },
  "mcpServers": {
    "r26-expired":  { "url": "https://expired.invalid/mcp",  "type": "http", "oauth": true },
    "r26-expiring": { "url": "https://expiring.invalid/mcp", "type": "http", "oauth": true },
    "r26-unknown":  { "url": "https://unknown.invalid/mcp",  "type": "http", "oauth": true },
    "r26-fine":     { "url": "https://fine.invalid/mcp",     "type": "http", "oauth": true },
    "r26-local":    { "command": "/usr/bin/python3", "args": ["$HOME_DIR/r26-local.py"] }
  }
}
JSON

MCP_ROUTER_HOME="$HOME_DIR" "$SWIFT_BIN" serve --port "$PORT" >"$HOME_DIR/serve.out" 2>&1 &
ROUTER_PID=$!

ready=""
for _ in $(seq 1 50); do
  if curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then ready=ok; break; fi
  kill -0 "$ROUTER_PID" 2>/dev/null || break
  sleep 0.2
done
if [ "$ready" != "ok" ]; then
  echo "environment: the Swift daemon never answered /health on :$PORT — its output:"
  sed -n '1,40p' "$HOME_DIR/serve.out"
  exit 2
fi

TOKEN="$(cat "$HOME_DIR/control.token" 2>/dev/null || echo '')"
[ -n "$TOKEN" ] || { echo "environment: the daemon minted no control token at $HOME_DIR/control.token"; exit 2; }

TIMEOUT=25

check() { # label method target want-status want-substring(or "-") [--no-token|--no-type|--absent]
  local label="$1" method="$2" target="$3" want_status="$4" want_body="$5" mode="${6:-}"

  if ! kill -0 "$ROUTER_PID" 2>/dev/null; then
    echo "environment: the daemon exited before \"$label\" — its output:"
    sed -n '1,40p' "$HOME_DIR/serve.out"
    exit 2
  fi

  local -a args=(-sS -m "$TIMEOUT" -o "$HOME_DIR/body" -w '%{http_code}' -X "$method"
                 "http://127.0.0.1:$PORT$target")
  [ "$mode" != "--no-type" ] && args+=(-H 'content-type: application/json')
  [ "$mode" != "--no-token" ] && args+=(-H "x-mcpr-token: $TOKEN")
  [ "$method" = "POST" ] && args+=(--data-binary '{}')

  local status; status="$(curl "${args[@]}" 2>/dev/null || echo 000)"
  local body; body="$(cat "$HOME_DIR/body")"

  if [ "$status" = "000" ]; then
    echo "environment: curl could not reach the daemon for \"$label\""
    exit 2
  fi

  local held=1
  if [ "$status" != "$want_status" ]; then
    held=0
  elif [ "$want_body" = "-" ]; then
    held=1
  elif [ "$mode" = "--absent" ]; then
    case "$body" in *"$want_body"*) held=0 ;; *) held=1 ;; esac
  else
    case "$body" in *"$want_body"*) held=1 ;; *) held=0 ;; esac
  fi

  if [ "$held" = "1" ]; then
    printf '  ok   %-62s %s\n' "$label" "$status"
    pass=$((pass + 1))
  else
    printf '  FAIL %-62s got %s (wanted %s)\n' "$label" "$status" "$want_status"
    [ "$want_body" != "-" ] && printf '       body: %s\n       %s: %s\n' "$body" \
      "$([ "$mode" = "--absent" ] && echo 'want NOT to contain' || echo 'want to contain')" "$want_body"
    fail=$((fail + 1)); failures+=("$label")
  fi
}

record() { # label ok-if-true message
  local label="$1" ok="$2" detail="$3"
  if [ "$ok" = "1" ]; then
    printf '  ok   %-62s %s\n' "$label" "$detail"
    pass=$((pass + 1))
  else
    printf '  FAIL %-62s %s\n' "$label" "$detail"
    fail=$((fail + 1)); failures+=("$label")
  fi
}

read_field() { # jq-free: pull one server's member out of the report
  curl -sS -m "$TIMEOUT" -H "x-mcpr-token: $TOKEN" \
    "http://127.0.0.1:$PORT/upstreams/auth-expiry" 2>/dev/null \
    | python3 -c "
import json, sys
doc = json.load(sys.stdin)
row = next(r for r in doc['upstreams'] if r['server'] == sys.argv[1])
print(row.get(sys.argv[2], ''))
" "$1" "$2"
}

claim() { # POST once and print the body, so several assertions can read ONE reply
  curl -sS -m "$TIMEOUT" -X POST -H 'content-type: application/json' -H "x-mcpr-token: $TOKEN" \
    --data-binary '{}' "http://127.0.0.1:$PORT/upstreams/auth-expiry/notify" 2>/dev/null
}

contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

echo "r26-auth-expiry — the routes are wired in the process that ships"
check "GET /upstreams/auth-expiry answers"        GET "/upstreams/auth-expiry" 200 '"count":5'
check "a stdio upstream has no credential to expire" GET "/upstreams/auth-expiry" 200 '"state":"not-applicable"'
check "an expired token is reported expired"      GET "/upstreams/auth-expiry" 200 '"state":"expired"'
check "one inside the window is reported expiring" GET "/upstreams/auth-expiry" 200 '"state":"expiring"'
check "and a fresh one is valid"                  GET "/upstreams/auth-expiry" 200 '"state":"valid"'

echo
echo "the router says it does not know, rather than saying it is fine"
check "a token with no declared lifetime is unknown" GET "/upstreams/auth-expiry" 200 '"state":"unknown"'
check "and the report says what it is missing"     GET "/upstreams/auth-expiry" 200 '"unknownReason":"no-lifetime-declared"'
unknown_expiry="$(read_field r26-unknown expiresAt)"
record "no expiry date is invented for it" \
  "$([ -z "$unknown_expiry" ] && echo 1 || echo 0)" "expiresAt=<${unknown_expiry}>"

echo
echo "a refused setting is reported rather than clamped in silence"
check "the refusal names the key"                 GET "/upstreams/auth-expiry" 200 '"key":"warnWithinMs"'
check "and its scope"                             GET "/upstreams/auth-expiry" 200 '"scope":"global"'
check "and the value as written"                  GET "/upstreams/auth-expiry" 200 '"value":500'
check "the policy in force is the default"        GET "/upstreams/auth-expiry" 200 '"warnWithinMs":86400000'

echo
echo "the report is derived from the file, and follows it when it changes"
before="$(read_field r26-expiring expiresAt)"
plant r26-expiring 172800 82800     # two days' life instead of one, same origin
after="$(read_field r26-expiring expiresAt)"
record "the reported expiry moved with the planted record" \
  "$([ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ] && echo 1 || echo 0)" \
  "$before -> $after"
record "and the state moved with it"  \
  "$([ "$(read_field r26-expiring state)" = "valid" ] && echo 1 || echo 0)" \
  "state=$(read_field r26-expiring state)"
plant r26-expiring 86400 82800      # put it back

echo
echo "the notices, and the throttle over them"
# ONE claim, then several readings of the SAME reply. Claiming per assertion would spend the
# notices on the first one and every later assertion would be reading an empty reply — which is
# how an absence assertion becomes unfailable.
claimed="$(claim)"
record "the notify route hands over what is due" \
  "$(contains "$claimed" '"count":2' && echo 1 || echo 0)" "$(echo "$claimed" | head -c 120)"
record "the expired credential is one of them" \
  "$(contains "$claimed" '"server":"r26-expired"' && contains "$claimed" '"kind":"expired"' && echo 1 || echo 0)" \
  "expired present"
record "the one inside the window is the other" \
  "$(contains "$claimed" '"server":"r26-expiring"' && contains "$claimed" '"kind":"expiring"' && echo 1 || echo 0)" \
  "expiring present"
# The two absences below are read off a reply that carries two other servers, so "the reply was
# empty" cannot satisfy them.
record "a fresh credential is not among them" \
  "$(contains "$claimed" 'r26-fine' && echo 0 || echo 1)" "r26-fine absent"
record "an unknown expiry is not among them" \
  "$(contains "$claimed" 'r26-unknown' && echo 0 || echo 1)" "r26-unknown absent"
repeat="$(claim)"
record "and the repeat is withheld" \
  "$(contains "$repeat" '"count":0' && echo 1 || echo 0)" "$(echo "$repeat" | head -c 120)"

echo
echo "resolving the authorisation clears the warning rather than ageing it out"
plant r26-expired 604800 0     # re-authorised, from outside; the router never wrote this
plant r26-unknown 3600 7200    # newly broken, so the next reply is not merely empty
recovered="$(claim)"
record "the re-authorised credential is gone from the notices" \
  "$(contains "$recovered" '"server":"r26-expired"' && echo 0 || echo 1)" "r26-expired absent"
record "and the reply is not merely empty" \
  "$(contains "$recovered" '"server":"r26-unknown"' && echo 1 || echo 0)" "r26-unknown present"
# The default `renotifyAfterMs` is six hours and this lane has been running for seconds, so a
# throttle that merely aged out could not produce the next line. It arrives because the recovery
# DROPPED the delivery record.
plant r26-expired 3600 7200
reported="$(claim)"
record "and the next failure is reported at once" \
  "$(contains "$reported" '"server":"r26-expired"' && echo 1 || echo 0)" "reported inside the window"

echo
echo "the refusals"
check "an untokened claim is 401"                 POST "/upstreams/auth-expiry/notify" 401 - --no-token
check "a claim with no content-type is 415"       POST "/upstreams/auth-expiry/notify" 415 - --no-type
check "POST on the collection is 405"             POST "/upstreams/auth-expiry" 405 -
check "GET on the notify path is 405"             GET  "/upstreams/auth-expiry/notify" 405 -
check "a prefix collision is not claimed"         GET  "/upstreams/auth-expiryx" 404 'MCP endpoint'

echo
echo "and none of it spawned anything"
# The PAIRED half of every assertion above. Zero alone is what a feature that does nothing reports;
# zero beside a report that moved when the planted file moved is the claim this lane exists to make.
spawned="$(ps -Ao ppid=,command= 2>/dev/null | awk -v p="$ROUTER_PID" '$1==p' | grep -c 'r26-local.py')"
record "children running the stdio server's own script" \
  "$([ "$spawned" -eq 0 ] && echo 1 || echo 0)" "$spawned, and there should be none"
children="$(ps -Ao ppid= 2>/dev/null | awk -v p="$ROUTER_PID" '$1==p' | wc -l | tr -d ' ')"
record "child processes of the daemon, at rest, after all of it" \
  "$([ "$children" -eq 0 ] && echo 1 || echo 0)" "$children"

echo
echo "r26-auth-expiry: $pass ok, $fail failed"
if [ "$fail" -gt 0 ]; then
  printf '  failed: %s\n' "${failures[@]}"
  exit 1
fi
exit 0
