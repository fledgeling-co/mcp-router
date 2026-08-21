#!/usr/bin/env bash
# Witness: the authorization server accepting real connections on loopback, seen by the
# kernel's socket table rather than by the product. Recorder is lsof(8); the router does
# not author it. Armed by pointing the same recorder at a port nothing was told to bind.
set -u
PORT="${1:?usage: witness-authserver-socket.sh PORT}"
DECOY=$((PORT+7))
listen() { lsof -nP -iTCP:"$1" -sTCP:LISTEN 2>/dev/null | grep -c LISTEN; }
estab()  { lsof -nP -iTCP:"$1" -sTCP:ESTABLISHED 2>/dev/null | grep -c ESTABLISHED; }

echo "before:      LISTEN on $PORT = $(listen $PORT)   decoy $DECOY = $(listen $DECOY)"
# Hold a socket open across the sample, with a real OAuth request written into it.
exec 3<>/dev/tcp/127.0.0.1/$PORT
printf 'GET /.well-known/oauth-authorization-server HTTP/1.1\r\nHost: 127.0.0.1:%s\r\nConnection: keep-alive\r\n\r\n' "$PORT" >&3
sleep 1
E=$(estab $PORT); ED=$(estab $DECOY)
ROUTER=$(lsof -nP -iTCP:"$PORT" -sTCP:ESTABLISHED 2>/dev/null | grep -c node)
head -c 40 <&3 > /tmp/wa-body.txt 2>/dev/null || true
exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
echo "during:      ESTABLISHED on $PORT = $E (router-owned halves = $ROUTER)   decoy = $ED"
echo "first bytes: $(tr -d '\r\n' < /tmp/wa-body.txt | head -c 32)"
echo
echo "examined=2 ports · effect-class=inbound-socket · witnessed=$([ "$ROUTER" -ge 1 ] && echo 1 || echo 0) · decoy=$ED"
[ "$ROUTER" -ge 1 ] && [ "$ED" -eq 0 ]
