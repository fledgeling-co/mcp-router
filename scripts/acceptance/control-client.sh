#!/bin/bash
#
# F3 acceptance: the typed client reaches a REAL router and decodes what it answers.
#
# Clause A1 asks for an exercised request against a running router, and it is the one clause the
# unit suite cannot cover however many tests it has. Every one of those talks to a stub built from
# our own beliefs about the wire, so they all agree with each other by construction and would keep
# agreeing on the day the router's response shape changed. This starts the actual TypeScript router
# and makes the actual client talk to it.
#
# It also checks the two failure states the design turns on, because "it worked once" is not the
# claim being made: a dead port must read as "the router is not running", and a wrong token must
# read as "not authorised" — two different values, from a real socket rather than a stub.
#
# Exit codes follow the house pattern used by shells.sh: 2 means the harness could not run the
# check (no node, nothing built), 1 means it ran and an assertion failed. Collapsing them reports a
# missing toolchain as a broken client.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT/app"
PORT="${PORT:-8973}"
HOME_DIR="$(mktemp -d -t mcprouter-acceptance)"
ROUTER_PID=""

# D-g1-g. Binds :8973, which parity-control.sh reaches through control-differential.sh, so this
# script contends with a full gate run even though it is not one of its lanes.
. "$ROOT/scripts/acceptance/parity-lock.sh"

cleanup() {
  parity_lock_release
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null || true
  rm -rf "$HOME_DIR"
}
trap cleanup EXIT INT TERM HUP

parity_lock_acquire "control-client.sh"

fail()    { echo "FAIL: $*" >&2; exit 1; }
skip()    { echo "SKIP: $*" >&2; exit 2; }

command -v node >/dev/null 2>&1 || skip "node is not installed — cannot run the router"
command -v swift >/dev/null 2>&1 || skip "swift is not installed"
[ -f "$ROOT/dist/index.js" ] || skip "dist/index.js is missing — run npm run build"

echo "building the probe…"
( cd "$APP_DIR" && swift build --product ControlProbe ) >/dev/null || skip "the probe did not build"
PROBE="$(cd "$APP_DIR" && swift build --show-bin-path)/ControlProbe"
[ -x "$PROBE" ] || skip "the probe binary is missing at $PROBE"

# ---------------------------------------------------------------- 1. no router
# Before starting anything: a refused loopback connection has to be its own state. This runs first
# precisely because nothing is listening yet, which is the honest way to produce the condition.
set +e
MCP_ROUTER_HOME="$HOME_DIR" MCP_ROUTER_URL="http://127.0.0.1:$PORT" "$PROBE" >"$HOME_DIR/offline.out" 2>&1
OFFLINE_CODE=$?
set -e
[ "$OFFLINE_CODE" -eq 2 ] || fail "a dead port should report an environment problem (2), got $OFFLINE_CODE"
grep -q "no router is listening" "$HOME_DIR/offline.out" \
  || fail "a dead port was not reported as 'the router is not running': $(cat "$HOME_DIR/offline.out")"
echo "PASS  a refused connection reads as 'the router is not running'"

# ------------------------------------------------------------- 2. a real router
cat > "$HOME_DIR/servers.json" <<JSON
{
  "mcpServers": {
    "acceptance-stdio": { "command": "/bin/echo", "args": ["hello"] }
  }
}
JSON

MCP_ROUTER_HOME="$HOME_DIR" node "$ROOT/dist/index.js" serve --port "$PORT" >"$HOME_DIR/router.log" 2>&1 &
ROUTER_PID=$!

for _ in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:$PORT/servers" >/dev/null 2>&1 && break
  sleep 0.2
done
curl -fsS "http://127.0.0.1:$PORT/servers" >/dev/null 2>&1 || {
  sed -n '1,40p' "$HOME_DIR/router.log"; skip "the router never answered on :$PORT"; }

set +e
MCP_ROUTER_HOME="$HOME_DIR" MCP_ROUTER_URL="http://127.0.0.1:$PORT" "$PROBE" >"$HOME_DIR/live.out" 2>&1
LIVE_CODE=$?
set -e
[ "$LIVE_CODE" -eq 0 ] || { cat "$HOME_DIR/live.out"; fail "the probe could not talk to a running router (exit $LIVE_CODE)"; }

grep -q "^OK$" "$HOME_DIR/live.out" || { cat "$HOME_DIR/live.out"; fail "the probe did not report success"; }
grep -q "server name=acceptance-stdio transport=stdio" "$HOME_DIR/live.out" \
  || { cat "$HOME_DIR/live.out"; fail "the declared server was not decoded off the real response"; }
echo "PASS  the live client decoded a real router's server list"
sed -n '1,12p' "$HOME_DIR/live.out" | sed 's/^/      /'

# ------------------------------------------------------- 3. a rejected credential
# The other half of the pair. A wrong token must be a *different* value from a dead port, or the
# app offers "start the router" to someone whose router is running perfectly well.
#
# It takes a mutating call to find out: reads on this router are unauthenticated, so a GET with a
# wrong token succeeds and would prove nothing. `--check-auth` is what makes the probe attempt one.
echo "not-the-real-token" > "$HOME_DIR/control.token"
set +e
MCP_ROUTER_HOME="$HOME_DIR" MCP_ROUTER_URL="http://127.0.0.1:$PORT" "$PROBE" --check-auth >"$HOME_DIR/unauth.out" 2>&1
UNAUTH_CODE=$?
set -e
[ "$UNAUTH_CODE" -eq 2 ] || { cat "$HOME_DIR/unauth.out"; fail "a wrong token should report an environment problem (2), got $UNAUTH_CODE"; }
grep -q "the control token was rejected" "$HOME_DIR/unauth.out" \
  || { cat "$HOME_DIR/unauth.out"; fail "a wrong token was not reported as 'not authorised'"; }
grep -q "usageReset" "$HOME_DIR/unauth.out" \
  && fail "the mutating call went through despite the wrong token"
echo "PASS  a wrong token reads as 'not authorised', distinctly from 'not running'"

echo
echo "F3 acceptance: 3/3 checks passed against a real router"
