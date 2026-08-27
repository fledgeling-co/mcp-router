#!/usr/bin/env bash
# Witness: `GET /servers/:name/document` crossing a real kernel socket, seen by the socket
# table rather than by the router.
#
# The wire cases in `wire-document.py` read status codes and bodies back through
# urllib, which proves the route answered but takes the router's own word for how the
# bytes travelled. This takes a different party's: lsof(8) reads the kernel's socket
# table, which no part of the product authors, and it is sampled while a client holds a
# real document request open so the ESTABLISHED pair is still there to be seen.
#
# The half that matters is the ROUTER-OWNED half. A client-owned ESTABLISHED row only
# says this script opened a socket; the accepted half says the router process took the
# connection rather than merely reserving the port. CASE-0147 learned that the hard way,
# sampling after curl had already closed and recording zero.
#
# Armed by pointing the same recorder at a decoy port nothing was told to bind: it must
# report 0 in the same run that the real port reports 1, or the recorder is answering a
# question about whether the router is alive rather than about this port.
#
# The server it asks for is CONSTRUCTED. None of the 21 upstreams installed on this
# machine declares a package directory, so on every one of them this route 404s
# `noPackageDirectory` and never reaches a body worth witnessing.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
PORT="${1:-8983}"
DECOY=$((PORT + 7))
SCRATCH=/tmp/g19-witness-scratch
CLI="$REPO/app/.build/debug/MCPRouterCLI"
OUT="$REPO/planning/test-campaign/evidence/wire-document"
mkdir -p "$OUT"

[ -x "$CLI" ] || { echo "no router binary at $CLI"; exit 2; }

listen() { lsof -nP -iTCP:"$1" -sTCP:LISTEN       2>/dev/null | grep -c LISTEN;      }
estab()  { lsof -nP -iTCP:"$1" -sTCP:ESTABLISHED  2>/dev/null | grep -c ESTABLISHED; }

/usr/bin/python3 -c "
import sys; sys.path.insert(0, '$HERE/wire-document-fixture')
import seed; seed.seed('$SCRATCH')
" >/dev/null || { echo "fixture seeding failed"; exit 2; }

MCP_ROUTER_HOME="$SCRATCH/home" "$CLI" serve --port "$PORT" >"$OUT/witness.log" 2>&1 &
SPID=$!
for _ in $(seq 1 100); do estab_ok=$(listen "$PORT"); [ "$estab_ok" -ge 1 ] && break; sleep 0.2; done

L=$(listen "$PORT"); LD=$(listen "$DECOY")
LPID=$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | awk 'NR==2{print $2}')
echo "before:      LISTEN on $PORT = $L (owner pid $LPID, serve pid $SPID)   decoy $DECOY = $LD"

# Hold the socket open across the sample with a real document request written into it.
exec 3<>/dev/tcp/127.0.0.1/$PORT
printf 'GET /servers/constructed-served/document HTTP/1.1\r\nHost: 127.0.0.1:%s\r\nConnection: keep-alive\r\n\r\n' "$PORT" >&3
sleep 1
E=$(estab "$PORT"); ED=$(estab "$DECOY")
ROUTER=$(lsof -nP -iTCP:"$PORT" -sTCP:ESTABLISHED -a -p "$SPID" 2>/dev/null | grep -c ESTABLISHED)
# Time-bounded and byte-wise. Two earlier spellings each lost the body:
#   head -c 1400   blocked forever — the connection is keep-alive, so the server sends
#                  its ~590 bytes and holds the socket open, and head waits for the rest.
#   print while <> read by LINE, and the JSON body carries no trailing newline, so the
#                  last read blocked and SIGALRM discarded the buffered line. The headers
#                  arrived and the body did not, which reads exactly like a route that
#                  answered 200 with nothing in it.
# sysread of one byte with autoflush loses at most the byte in flight when the alarm fires.
perl -e '$|=1; alarm 4; while (sysread(STDIN, $b, 1)) { print $b }' <&3 \
  > /tmp/g19-witness-body.txt 2>/dev/null || true
exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null

FIRST=$(head -c 15 /tmp/g19-witness-body.txt | tr -d '\r\n')
SENT=$(grep -c '9f4c1e-served-readme' /tmp/g19-witness-body.txt || true)
echo "during:      ESTABLISHED on $PORT = $E (router-owned halves = $ROUTER)   decoy = $ED"
echo "first bytes: $FIRST"
echo "sentinel in the bytes read back off the socket: $SENT"

kill "$SPID" 2>/dev/null
wait "$SPID" 2>/dev/null
A=$(listen "$PORT")
echo "after:       LISTEN on $PORT = $A"
echo
echo "examined=2 ports · effect-class=inbound-socket · witnessed=$([ "$ROUTER" -ge 1 ] && echo 1 || echo 0) · decoy=$ED"
[ "$L" -ge 1 ] && [ "$LD" -eq 0 ] && [ "$ROUTER" -ge 1 ] && [ "$ED" -eq 0 ] && [ "$A" -eq 0 ] \
  && [ "${FIRST#HTTP/1.1 200}" != "$FIRST" ]
