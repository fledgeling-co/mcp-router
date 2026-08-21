#!/usr/bin/env bash
# R14/R15 evidence producer. Runs against a sandboxed router; prints a denominator
# for every group, because `failures=0` is a claim and `examined=N failures=0` is a result.
set -u
B="${1:?usage: r14-authserver-probe.sh http://127.0.0.1:PORT}"
pass=0; fail=0; examined=0
ck() { # ck <name> <expected> <actual>
  examined=$((examined+1))
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "  ok   $1 ($3)"
  else fail=$((fail+1)); echo "  FAIL $1: expected $2, got $3"; fi
}
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$@"; }

echo "REQ-021 — the Authenticate flow completes"
ck "protected-resource metadata"  200 "$(code $B/.well-known/oauth-protected-resource)"
ck "authorization-server metadata" 200 "$(code $B/.well-known/oauth-authorization-server)"
REG=$(curl -s --max-time 8 -X POST $B/register -H 'Content-Type: application/json' \
  -d '{"client_name":"probe","redirect_uris":["http://127.0.0.1:57100/cb"],"grant_types":["authorization_code"],"response_types":["code"]}')
CID=$(printf '%s' "$REG" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("client_id",""))' 2>/dev/null)
ck "registration returns a client_id" "yes" "$([ -n "$CID" ] && echo yes || echo no)"

echo "REQ-022 — /mcp never returns 401"
BODY='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"p","version":"0"}}}'
H1=(-H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream')
ck "no Authorization header"    200 "$(code -X POST "${H1[@]}" -d "$BODY" $B/mcp)"
ck "garbage bearer"             200 "$(code -X POST "${H1[@]}" -H 'Authorization: Bearer garbage' -d "$BODY" $B/mcp)"
ck "empty Authorization header" 200 "$(code -X POST "${H1[@]}" -H 'Authorization:' -d "$BODY" $B/mcp)"

echo "REQ-024 — every route refuses a foreign Host"
for p in /health /status /servers /usage /mcp /authorize /token /register \
         /.well-known/oauth-protected-resource /.well-known/oauth-authorization-server; do
  ck "foreign Host on $p" 403 "$(code -H 'Host: evil.example' $B$p)"
done

echo "REQ-025 — the refusals"
ck "cross-origin POST /register" 403 "$(code -X POST -H 'Origin: https://evil.example' -H 'Content-Type: application/json' -d '{}' $B/register)"
ck "Origin: null POST /register" 403 "$(code -X POST -H 'Origin: null' -H 'Content-Type: application/json' -d '{}' $B/register)"
ck "/register without JSON type"  415 "$(code -X POST -H 'Content-Type: text/plain' -d '{}' $B/register)"
ck "external redirect_uri"        400 "$(code "$B/authorize?response_type=code&client_id=x&redirect_uri=https%3A%2F%2Fevil.example%2Fcb")"

echo
echo "examined=$examined pass=$pass failures=$fail"
[ "$fail" -eq 0 ]
