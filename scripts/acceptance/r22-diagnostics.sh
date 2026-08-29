#!/usr/bin/env bash
#
# R22 — the diagnostics bundle, over the daemon's own socket, with a real secret planted on disk.
#
# THIS LANE IS THE WITNESS, and the reason it exists is that the unit suite cannot be one.
#
# `ControlDiagnosticsTests` drives `ControlHandler.handle` and reads the value it returns. That is
# the right place to prove the redaction logic and it is one process boundary short of the claim.
# The claim is about **bytes that left this machine's router over a socket**, and between the
# handler's return and those bytes sit the response writer, the HTTP framing and the daemon's own
# wiring — the last of which has shipped nil twice in this repository with a green suite
# (`GET /registry/search` answered 502 in the only process that ships; `POST /servers/:name/auth`
# answered 405 until P7). A bundle route that was never dispatched would pass every unit test and
# leak nothing, and would also export nothing.
#
# So this lane plants a real credential in a real `servers.json`, starts the real daemon on it,
# asks the real route over the real socket, and greps the bytes.
#
# THREE THINGS MAKE THE ABSENCE MEAN SOMETHING, and without all three "no secret in the output" is
# satisfied by an empty file:
#
#   1. THE INPUT IS PROVEN TO CONTAIN IT. The lane greps `servers.json` for the planted secret and
#      requires a hit. A secret that was never written cannot be leaked, and a run that silently
#      failed to write one would otherwise report a clean bundle.
#   2. THE OUTPUT IS PROVEN TO BE THE BUNDLE. The public canary planted in the log line must be
#      PRESENT, and so must the key names, so a 404, a 503 or an empty document fails here.
#   3. THE SCRUBBER IS PROVEN TO HAVE WORKED. `occurrencesRemoved` must be non-zero, because the
#      secret is also planted in a log line — which is the only channel layer 1 does not cover.
#
# EVERY PATH IS INSIDE A SCRATCH HOME on a port the campaign reserves, so the operator's own router
# at 127.0.0.1:8879 is never touched, read or restarted — and the planted secret is a literal
# invented for this file, never a real credential.
#
# Exit codes follow the house pattern:
#   0  every assertion held
#   1  the daemon answered, and answered something wrong
#   2  the environment could not run the check — the binary is missing, or the daemon never bound.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
HOME_DIR="$(mktemp -d -t mcprouter-r22)"
PORT="${PORT:-8981}"
ROUTER_PID=""

# Invented for this file. It is not a credential, and it is long enough and odd enough that no
# substring of it occurs anywhere in a bundle by accident.
SECRET="sk-r22-lane-QZ7vN4pLxK9mT2wB8yH3cJ6dF5gS1aE0"
CANARY="R22-LANE-CANARY-LOG-LINE-REACHED"
SHORT="dev"

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

parity_lock_acquire "r22-diagnostics.sh"

[ -x "$SWIFT_BIN" ] || { echo "environment: no MCPRouterCLI at $SWIFT_BIN (run: make build-cli-debug)"; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "environment: curl is not installed"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "environment: python3 is not installed"; exit 2; }

# ------------------------------------------------------------------ the fixture
cat >"$HOME_DIR/answering.py" <<'PY'
import json, sys
def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n"); sys.stdout.flush()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        msg = json.loads(line)
    except Exception:
        continue
    mid, method = msg.get("id"), msg.get("method")
    if method == "initialize":
        send({"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": "2024-11-05", "capabilities": {"tools": {}},
            "serverInfo": {"name": "r22-fixture", "version": "1.0.0"}}})
    elif method == "tools/list":
        send({"jsonrpc": "2.0", "id": mid, "result": {"tools": []}})
    elif mid is not None:
        send({"jsonrpc": "2.0", "id": mid,
              "error": {"code": -32601, "message": "no method %s" % method}})
PY

# The secret in all four positions this item is responsible for: an env value, a header value, a
# URL's userinfo and a URL's query. Plus a value below the needle floor, so the lane can check that
# it is named rather than used.
cat >"$HOME_DIR/servers.json" <<JSON
{
  "mcpServers": {
    "r22-stdio": {
      "command": "/usr/bin/python3",
      "args": ["$HOME_DIR/answering.py"],
      "env": { "GITHUB_TOKEN": "$SECRET", "MODE": "$SHORT" }
    },
    "r22-http": {
      "url": "https://alice:$SECRET@example.invalid/mcp?api_key=$SECRET",
      "type": "http",
      "headers": { "Authorization": "Bearer $SECRET" }
    }
  }
}
JSON

# The encoded forms, computed the way the PRODUCT computes them.
#
# The first draft of this lane derived the percent form with `urllib.parse.quote(s, safe="")` and
# planted nothing encoded at all. Both were wrong and both were invisible: `quote` never encodes an
# RFC 3986 unreserved character whatever `safe` is set to, so for a secret of alphanumerics and
# hyphens it returns the input unchanged — the "percent-encoded form" assertion was a second copy of
# the literal one — and with neither encoded form ever written to disk, both absences held over a
# router that did no encoding-aware scrubbing whatever. Two assertions that could not fail.
# `SecretNeedles.variants` percent-encodes everything outside `CharacterSet.alphanumerics`, so that
# is what is computed here, and both forms are PLANTED so the absences have something to bite on.
PCT="$(python3 -c 'import sys; sys.stdout.write("".join(c if c.isalnum() else "%%%02X" % ord(c) for c in sys.argv[1]))' "$SECRET")"
B64="$(printf '%s' "$SECRET" | base64)"
if [ "$PCT" = "$SECRET" ] || [ "$B64" = "$SECRET" ]; then
  echo "environment: an encoded form equals the literal, so its assertion below would be a duplicate"
  exit 2
fi

# The log line is the channel layer 1 cannot reach: the secret quoted back inside free text, beside
# a canary that must survive. Written to the path the daemon's own config resolves as `logPath`.
mkdir -p "$HOME_DIR"
cat >"$HOME_DIR/router.log" <<LOG
2026-08-29T00:00:00.000Z error upstream refused: bad token $SECRET $CANARY
2026-08-29T00:00:01.000Z warn  redirect carried ?t=$PCT
2026-08-29T00:00:02.000Z warn  authorization basic $B64
2026-08-29T00:00:03.000Z info  started $SHORT-server on port 3000
LOG

# ------------------------------------------------------------------ (1) the input really holds it
echo "r22-diagnostics — the plant is real before anything is asked of the router"
planted=0
grep -q -F -- "$SECRET" "$HOME_DIR/servers.json" && planted=$((planted + 1))
grep -q -F -- "$SECRET" "$HOME_DIR/router.log"   && planted=$((planted + 1))
grep -q -F -- "$PCT"    "$HOME_DIR/router.log"   && planted=$((planted + 1))
grep -q -F -- "$B64"    "$HOME_DIR/router.log"   && planted=$((planted + 1))
if [ "$planted" -eq 4 ]; then
  printf '  ok   %-62s %s\n' "the secret is on disk in 4 places, in 3 forms" "planted"
  pass=$((pass + 1))
else
  printf '  FAIL %-62s %s of 4\n' "the plant did not land — every absence below would be vacuous" "$planted"
  fail=$((fail + 1)); failures+=("the plant did not land")
  exit 1
fi

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

fetch() { # method target [--no-token] -> writes $HOME_DIR/body, echoes the status
  local method="$1" target="$2" mode="${3:-}"
  if ! kill -0 "$ROUTER_PID" 2>/dev/null; then
    echo "environment: the daemon exited before $method $target — its output:" >&2
    sed -n '1,40p' "$HOME_DIR/serve.out" >&2
    exit 2
  fi
  local -a args=(-sS -m "$TIMEOUT" -o "$HOME_DIR/body" -w '%{http_code}' -X "$method"
                 "http://127.0.0.1:$PORT$target" -H 'content-type: application/json')
  [ "$mode" != "--no-token" ] && args+=(-H "x-mcpr-token: $TOKEN")
  [ "$method" = "POST" ] && args+=(--data-binary '{}')
  curl "${args[@]}" 2>/dev/null || echo 000
}

assert_absent() { # label needle file
  if grep -q -F -- "$2" "$3"; then
    printf '  FAIL %-62s the needle is in the output\n' "$1"
    fail=$((fail + 1)); failures+=("$1")
  else
    printf '  ok   %-62s absent\n' "$1"
    pass=$((pass + 1))
  fi
}

assert_present() { # label needle file
  if grep -q -F -- "$2" "$3"; then
    printf '  ok   %-62s present\n' "$1"
    pass=$((pass + 1))
  else
    printf '  FAIL %-62s missing from the output\n' "$1"
    fail=$((fail + 1)); failures+=("$1")
  fi
}

assert_status() { # label got want
  if [ "$2" = "$3" ]; then
    printf '  ok   %-62s %s\n' "$1" "$2"
    pass=$((pass + 1))
  else
    printf '  FAIL %-62s got %s (wanted %s)\n' "$1" "$2" "$3"
    fail=$((fail + 1)); failures+=("$1")
  fi
}

echo
echo "the route is dispatched in the process that ships"
status="$(fetch POST /diagnostics/bundle)"
assert_status "POST /diagnostics/bundle answers" "$status" 200
cp "$HOME_DIR/body" "$HOME_DIR/bundle.json"

echo
echo "(2) the bytes on the wire are the bundle, not an empty document"
assert_present "the log line was gathered — the canary survived"  "$CANARY"        "$HOME_DIR/bundle.json"
assert_present "the env pair was reached"                         "GITHUB_TOKEN"   "$HOME_DIR/bundle.json"
assert_present "the header pair was reached"                      "Authorization"  "$HOME_DIR/bundle.json"
assert_present "the endpoint is still legible"                    "example.invalid" "$HOME_DIR/bundle.json"

echo
echo "(3) and the secret is not in them, in any form"
assert_absent  "the literal secret"                               "$SECRET"        "$HOME_DIR/bundle.json"
assert_absent  "its percent-encoded form"                         "$PCT"           "$HOME_DIR/bundle.json"
assert_absent  "its base64 form"                                  "$B64"           "$HOME_DIR/bundle.json"
assert_absent  "the URL userinfo it was embedded in"              "alice:"         "$HOME_DIR/bundle.json"

echo
echo "the scrubber had something to do, rather than merely having run"
assert_present "layer 2 named the key it removed"  "<redacted:r22-stdio.env.GITHUB_TOKEN>" "$HOME_DIR/bundle.json"
assert_absent  "and did not report zero removals"  '"occurrencesRemoved":0'                "$HOME_DIR/bundle.json"

echo
echo "the needle floor is reported rather than applied"
assert_present "the short value is named"          "r22-stdio.env.MODE"      "$HOME_DIR/bundle.json"
assert_present "with the reason"                   "shorter than 8"          "$HOME_DIR/bundle.json"
assert_present "and the log line it occurs in is intact" "$SHORT-server on port 3000" "$HOME_DIR/bundle.json"

echo
echo "the gate is the verb"
status="$(fetch POST /diagnostics/bundle --no-token)"
assert_status "an untokened POST is refused"       "$status" 401
assert_absent "and carries no log content"         "$CANARY" "$HOME_DIR/body"
status="$(fetch GET /diagnostics/bundle)"
assert_status "a GET on the bundle path is 405"    "$status" 405
assert_absent "and carries no log content"         "$CANARY" "$HOME_DIR/body"

echo
echo "the ungated preview carries counts and no content"
status="$(fetch GET /diagnostics --no-token)"
assert_status "GET /diagnostics answers untokened" "$status" 200
assert_present "with the categories"               '"category":"routerLog"' "$HOME_DIR/body"
assert_absent  "and no log line"                   "$CANARY"                "$HOME_DIR/body"
assert_absent  "and no secret"                     "$SECRET"                "$HOME_DIR/body"

echo
echo "r22-diagnostics: $pass ok, $fail failed"
if [ "$fail" -gt 0 ]; then
  printf '  failed: %s\n' "${failures[@]}"
  exit 1
fi
exit 0
