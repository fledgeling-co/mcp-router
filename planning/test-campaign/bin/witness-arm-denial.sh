#!/bin/bash
# Second arming pass: DENIAL controls, appended to arming.log.
#
# witness-arm.sh points each recorder at a world where the effect does not happen, which
# proves the recorder answers about the thing it watches rather than about whether the
# router ran. That is a pointing control. Part 4 of the causal witness in
# references/effect-boundary.md asks for something stronger: deny the effect itself and
# watch the scenario fail. The subprocess recorder already had one -- a config declaring
# no servers takes the count to 0 -- and these two give the other recorders theirs.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
CLI="$REPO/app/.build/debug/MCPRouterCLI"
OUT="$REPO/planning/test-campaign/evidence/witness"
LOG="$OUT/arming.log"
say() { printf '%s\n' "$*" | tee -a "$LOG"; }
bad=0

say ""
say "== second arming pass: denial controls =="
say "recorded at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say ""

# --- REQ-013 filesystem-write: deny the write, not the pointer ------------------------
say "-- deny REQ-013: a router home the process is not permitted to write --"
DEN=/tmp/mcp-witness-denyfs; rm -rf "$DEN"; mkdir -p "$DEN"
cp /tmp/mcp-witness-home/fixture-server.py "$DEN/" 2>/dev/null
sed 's#/tmp/mcp-witness-home#/tmp/mcp-witness-denyfs#' /tmp/mcp-witness-home/servers.json > "$DEN/servers.json"
chmod 500 "$DEN"
MCP_ROUTER_HOME="$DEN" "$CLI" index --force >>"$LOG" 2>&1
RC=$?
PRESENT=$([ -e "$DEN/manifest.json" ] && echo yes || echo no)
say "   home mode: $(stat -f '%Sp' "$DEN")  (the process may read and traverse, not create)"
say "   index --force exit code: $RC"
say "   manifest.json present after the run: $PRESENT"
if [ "$PRESENT" = "no" ]; then
  say "   count=0 with the effect denied. The stat recorder is reading the write, not the run."
else
  say "   RED FLAG: a manifest appeared in a directory the process cannot write."
  bad=1
fi
chmod 700 "$DEN"; rm -rf "$DEN"
say ""

# --- REQ-012 inbound-socket: deny the bind ---------------------------------------------
say "-- deny REQ-012: hold the port first, so the router's bind cannot succeed --"
PORT=8973
python3 - "$PORT" >/tmp/mcp-witness-squat.log 2>&1 &
SQUAT=$!
sleep 0.6
python3 -c "
import socket,sys,time
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(('127.0.0.1',$PORT)); s.listen(1); time.sleep(25)
" &
SQUAT=$!
for _ in $(seq 1 20); do lsof -nP -iTCP@127.0.0.1:$PORT 2>/dev/null | grep -q LISTEN && break; sleep 0.3; done
SQ_ROWS=$(lsof -nP -iTCP@127.0.0.1:$PORT 2>/dev/null | awk -v p="$SQUAT" '$2==p' | grep -c LISTEN)
say "   squatter pid $SQUAT holds the port: LISTEN rows owned by it = $SQ_ROWS"
MCP_ROUTER_HOME=/tmp/mcp-witness-home "$CLI" serve --port $PORT >>"$LOG" 2>&1 &
SPID=$!
sleep 3
ROUTER_ROWS=$(lsof -nP -iTCP@127.0.0.1:$PORT 2>/dev/null | awk -v p="$SPID" '$2==p' | grep -c LISTEN)
say "   router pid $SPID, LISTEN rows owned by the router = $ROUTER_ROWS"
if [ "$SQ_ROWS" -ge 1 ] && [ "$ROUTER_ROWS" -eq 0 ]; then
  say "   count=0 with the bind denied, against count=1 in the witness run on the same port."
  say "   The lsof recorder attributes the listener to a pid rather than to the port."
else
  say "   RED FLAG: squatter=$SQ_ROWS router=$ROUTER_ROWS -- the denial did not take, or"
  say "   the recorder credited the router with a socket it does not own."
  bad=1
fi
kill "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null
kill "$SQUAT" 2>/dev/null; wait "$SQUAT" 2>/dev/null
say ""

say "-- the kernel bar is out of reach on this host, and that is the lane's ceiling --"
say "   csrutil: $(csrutil status 2>&1 | tr -d '\n')"
say "   uid: $(id -u)   dtrace: $(dtrace -n 'BEGIN{exit(0)}' 2>&1 | tail -1)"
say "   So no execve/connect/open syscall trace backs part 2 of the causal witness."
say "   What these recorders carry is the portable floor from references/effect-boundary.md:"
say "   a real listener the kernel reports, a real child that reports its own parent, and a"
say "   real file whose inode and mtime the filesystem records. Completion is witnessed by"
say "   something other than the product; the ATTEMPT is not separately traced."
say ""
if [ "$bad" -eq 0 ]; then
  say "DENIAL-ARMED: every recorder went to 0 when the effect itself was denied."
else
  say "NOT DENIAL-ARMED: detail above."
fi
exit $bad
