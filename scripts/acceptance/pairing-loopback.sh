#!/bin/bash
#
# B6: does a phone's pairing exchange, run against a real router over loopback, leave a record only
# where the wire contract allows one? (planning/plans/plan-pairing-handshake.md §2.4 and §7.)
#
# ## What it runs
#
# A scratch TypeScript router, with its own temporary MCP_ROUTER_HOME, its own control port and its own
# pairing port, both ephemeral and both on 127.0.0.1. The live router on 8879 is never addressed. The
# pairing listener is bound to loopback through the scratch config, which is the test setting §7
# describes; production never sets it.
#
# The checks are in pairing-loopback.mjs. They assert that the router records a phone only after the
# phone's pair.ack, and that a wrong code, a burned code, an already-used code, a wrong fingerprint and a
# drop before the ack each leave no record.
#
# ## What it does not prove
#
# The phone is a stand-in written from the wire contract, not LivePairingService. The production TLS
# transport is B5 and is not merged, so the Swift service has no socket to reach. Every check on the router
# is a check on the real router over real TLS. Every check on the phone side is a check on the stand-in.
# The LAN, Bonjour, the iOS binary and the firewall prompt are outside this lane (§7, §8).
#
# ## Mutation
#
# PAIRING_LOOPBACK_MUTANT=skip-ack makes the happy-path phone drop instead of acking. The lane must go red:
# the Mac holds no record, and the checks that need one fail. That is the proof the lane can fail on the
# missing ack, and it is run by hand rather than in the enrolled set.
#
# ## Exit codes, as the acceptance runner reads them
#
#   0  every check held
#   1  a check about the router failed, or the scratch router never started its pairing listener
#   2  the lane could not run: a missing tool, a failed build, a router that would not answer, or a driver
#      that did not finish

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DRIVER="$ROOT/scripts/acceptance/pairing-loopback.mjs"
WORK="$(mktemp -d -t pairing-loopback)"
ROUTER_HOME="$WORK/router-home"
PHONE_HOME="$WORK/phone-home"
ROUTER_PID=""

# Returns the status it was entered with. The EXIT trap must not be able to rewrite the lane's verdict.
lane__cleanup() {
    local status=$?
    [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null
    [ -n "$ROUTER_PID" ] && wait "$ROUTER_PID" 2>/dev/null
    rm -rf "$WORK"
    return $status
}
trap lane__cleanup EXIT

blocked() { echo "BLOCKED: $*" >&2; exit 2; }
failed() { echo "FAIL: $*" >&2; exit 1; }

for tool in node python3 openssl curl perl; do
    command -v "$tool" >/dev/null 2>&1 || blocked "$tool is not installed"
done

# The router under test is the compiled one. Building it here means the lane never judges a stale dist.
(cd "$ROOT" && npx tsc -p tsconfig.json) > "$WORK/build.log" 2>&1 \
    || { tail -20 "$WORK/build.log" >&2; blocked "the router did not build (npx tsc -p tsconfig.json)"; }

# An ephemeral port, asked of the kernel rather than chosen, so a port in use cannot be mistaken for ours.
free_port() {
    python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}
CONTROL_PORT="$(free_port)"
PAIRING_PORT="$(free_port)"
[ -n "$CONTROL_PORT" ] && [ -n "$PAIRING_PORT" ] || blocked "could not ask the kernel for two free ports"

mkdir -m 700 "$ROUTER_HOME" "$PHONE_HOME"
cat > "$ROUTER_HOME/servers.json" <<JSON
{
  "mcpServers": {},
  "pairing": { "enabled": true, "host": "127.0.0.1", "port": $PAIRING_PORT }
}
JSON

MCP_ROUTER_HOME="$ROUTER_HOME" node "$ROOT/dist/index.js" serve --port "$CONTROL_PORT" \
    > "$WORK/router.log" 2>&1 &
ROUTER_PID=$!

for _ in $(seq 1 60); do
    curl -fsS --max-time 2 "http://127.0.0.1:$CONTROL_PORT/servers" >/dev/null 2>&1 && break
    sleep 0.25
done
curl -fsS --max-time 2 "http://127.0.0.1:$CONTROL_PORT/servers" >/dev/null 2>&1 \
    || { sed -n '1,40p' "$WORK/router.log" >&2; blocked "the scratch router never answered on 127.0.0.1:$CONTROL_PORT"; }

# pairing.enabled is set, so the listener has to have started. Waiting for its log line means a missing
# listener is reported as the router's failure, not as a connection error from the driver.
listening=""
for _ in $(seq 1 40); do
    if grep -q "pairing listening on" "$WORK/router.log" "$ROUTER_HOME/router.log" 2>/dev/null; then
        listening=1
        break
    fi
    sleep 0.25
done
[ -n "$listening" ] || { sed -n '1,40p' "$WORK/router.log" >&2; failed "pairing.enabled is set but the listener never logged that it was listening"; }

perl -e 'alarm shift @ARGV; exec @ARGV' 240 node "$DRIVER" \
    --router-home "$ROUTER_HOME" \
    --control-port "$CONTROL_PORT" \
    --pairing-port "$PAIRING_PORT" \
    --phone-home "$PHONE_HOME" \
    --mutant "${PAIRING_LOOPBACK_MUTANT:-}"
status=$?

case "$status" in
    0) exit 0 ;;
    1) exit 1 ;;
    *) blocked "the driver did not finish (exit $status)" ;;
esac
