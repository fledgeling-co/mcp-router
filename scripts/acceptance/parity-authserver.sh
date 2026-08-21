#!/usr/bin/env bash
#
# R14 — the router's own authorization server, driven at BOTH routers.
#
# The owner's blocker: an MCP client's "Authenticate" action against
# http://127.0.0.1:8879/mcp reported `Dynamic Client Registration rejected (HTTP 404)` and could
# not succeed. This lane proves it now can, and that every security constraint the three review
# lanes named is actually armed rather than described.
#
# WHAT IS COMPARED BYTE FOR BYTE, and what is not. The two metadata documents and every refusal
# body are deterministic, so they are diffed whole. The sealed values — client_id, codes, tokens —
# are HMACs over two DIFFERENT issuer keys by construction, so comparing those bytes would compare
# two random secrets. They are asserted per router instead: the flow completes, a replayed code is
# refused, a forged refresh token is refused. That split is stated rather than hidden, because a
# lane that normalises away the thing it is meant to check is worse than no lane.
#
# ROWS THIS LANE OWNS. It writes results for these ids and no others; the `record` guard below
# refuses anything else, because the gate matches on (group, id) and binds no script to either —
# authorship has to be closed from the lane's side or it is not closed at all.
#   authserver: authserver-metadata-resource authserver-metadata-as authserver-register
#               authserver-authorize authserver-token authserver-instructions
#               authserver-state-report authserver-host-authority
#
# Exit codes: 0 everything agreed and every constraint held, 1 a failure, 2 the environment could
# not run the lane.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TS_PORT="${R14_TS_PORT:-8961}"
SWIFT_PORT="${R14_SWIFT_PORT:-8962}"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
WORK="$(mktemp -d -t r14-auth)"
TS_PID=""; SWIFT_PID=""

cleanup() {
  [ -n "$TS_PID" ] && kill "$TS_PID" 2>/dev/null
  [ -n "$SWIFT_PID" ] && kill "$SWIFT_PID" 2>/dev/null
  [ -n "$TS_PID" ] && wait "$TS_PID" 2>/dev/null
  [ -n "$SWIFT_PID" ] && wait "$SWIFT_PID" 2>/dev/null
  rm -rf "$WORK"
  return 0
}
trap cleanup EXIT

RESULTS="${PARITY_RESULTS:-}"
OWNED="divergence/div-r14-redirect-host authserver/authserver-metadata-resource authserver/authserver-metadata-as
authserver/authserver-register authserver/authserver-authorize authserver/authserver-token
authserver/authserver-instructions authserver/authserver-state-report
authserver/authserver-host-authority"

record() { # group id ok|fail detail
  [ -n "$RESULTS" ] || return 0
  case " $(echo $OWNED) " in
    *" $1/$2 "*) ;;
    *) echo "  LANE BUG: refusing to record $1/$2, which this lane does not own" >&2; return 1 ;;
  esac
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$RESULTS"
}

pass=0; fail=0
ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
# Every failure is attributed to the row being exercised, so a row is proven only when the checks
# that speak for it all passed. CURRENT_ROW is set before each block below.
CURRENT_ROW="authserver-metadata-resource"
bad()  { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; ROW_FAIL["$CURRENT_ROW"]=$(( ${ROW_FAIL["$CURRENT_ROW"]:-0} + 1 )); }
check(){ if [ "$1" = "$2" ]; then ok "$3 ($2)"; else bad "$3 — expected $2, got $1"; fi; }

# Per-row verdicts. A row is proven only when every check that speaks for it passed, so each row
# tracks its own tally rather than inheriting the lane's.
declare -A ROW_FAIL
row() { ROW_FAIL["$1"]=$(( ${ROW_FAIL["$1"]:-0} + ${2:-0} )); }
verdict_rows() {
  local id
  record divergence div-r14-redirect-host \
    "$([ "${ROW_FAIL[authserver-register]:-0}" = 0 ] && echo ok || echo fail)" \
    "asserted in both directions across fifteen redirect_uri shapes"
  for id in authserver-metadata-resource authserver-metadata-as authserver-register \
            authserver-authorize authserver-token authserver-instructions \
            authserver-state-report authserver-host-authority; do
    if [ "${ROW_FAIL[$id]:-0}" = 0 ]; then
      record authserver "$id" ok "compared at both routers by parity-authserver.sh"
    else
      record authserver "$id" fail "${ROW_FAIL[$id]} check(s) failed"
    fi
  done
}

command -v node >/dev/null 2>&1 || { echo "environment: node is not installed"; exit 2; }
[ -f "$REPO_ROOT/dist/index.js" ] || {
  echo "environment: no built reference at dist/index.js. Run npm run build."; exit 2; }
[ -x "$SWIFT_BIN" ] || {
  echo "environment: no Swift router at ${SWIFT_BIN#"$REPO_ROOT/"}. cd app && swift build"; exit 2; }
for port in "$TS_PORT" "$SWIFT_PORT"; do
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "environment: something is already listening on :$port. This lane never shares a port"
    echo "             and never touches the router on 8879."; exit 2
  fi
done

# Two homes from one declaration. `probe` serves tools; `needsauth` is an http upstream pointed at
# a closed port, so it is an upstream that can be authorised and is serving nothing — the shape the
# state report has to classify.
for side in ts swift; do
  mkdir -p "$WORK/$side"
  cat > "$WORK/$side/servers.json" <<JSON
{ "mcpServers": {
  "probe": { "command": "node", "args": ["$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs", "stdio"] },
  "needsauth": { "type": "http", "url": "http://127.0.0.1:9/mcp" }
} }
JSON
done

MCP_ROUTER_HOME="$WORK/ts" node "$REPO_ROOT/dist/index.js" serve --port "$TS_PORT" \
  >"$WORK/ts.log" 2>&1 & TS_PID=$!
MCP_ROUTER_HOME="$WORK/swift" "$SWIFT_BIN" serve --port "$SWIFT_PORT" \
  >"$WORK/swift.log" 2>&1 & SWIFT_PID=$!

wait_ready() {
  for _ in $(seq 1 120); do
    curl -fsS -m 2 "http://127.0.0.1:$1/health" >/dev/null 2>&1 && return 0
    kill -0 "$2" 2>/dev/null || { echo "environment: the $3 router exited during startup"; return 1; }
    sleep 0.25
  done
  echo "environment: the $3 router never answered /health"; return 1
}
wait_ready "$TS_PORT" "$TS_PID" reference || { tail -20 "$WORK/ts.log"; exit 2; }
wait_ready "$SWIFT_PORT" "$SWIFT_PID" Swift || { tail -20 "$WORK/swift.log"; exit 2; }

TS="http://127.0.0.1:$TS_PORT"
SW="http://127.0.0.1:$SWIFT_PORT"

# The port is a coordinate two routers cannot share; the entry point is `node …/dist/index.js` at
# one and a compiled binary at the other, and it appears inside the commands the page prints.
norm() { sed -e "s/127\.0\.0\.1:$TS_PORT/127.0.0.1:<port>/g" -e "s/127\.0\.0\.1:$SWIFT_PORT/127.0.0.1:<port>/g" \
             -e "s|node [^<\"]*dist/index\.js|<entry>|g" -e "s|[^<\" ]*MCPRouterCLI|<entry>|g" \
             -e 's/"client_id_issued_at":[0-9]*/"client_id_issued_at":<t>/'; }

status() { curl -sS -o /dev/null -w '%{http_code}' -m 10 "$@"; }
bodyof() { curl -sS -m 10 "$@"; }

echo "R14 — the authorization server, at both routers (reference :$TS_PORT, Swift :$SWIFT_PORT)"
echo
echo "byte-for-byte, both routers:"

diffcmp() { # label path [curl args...]
  local label="$1" path="$2"; shift 2
  bodyof "$TS$path" "$@" | norm > "$WORK/a"
  bodyof "$SW$path" "$@" | norm > "$WORK/b"
  if [ ! -s "$WORK/a" ]; then bad "$label — the reference returned nothing"; return; fi
  if diff -q "$WORK/a" "$WORK/b" >/dev/null 2>&1; then ok "$label"
  else bad "$label — $(diff "$WORK/a" "$WORK/b" | head -4 | tr '\n' ' ' | cut -c1-150)"; fi
}

CURRENT_ROW=authserver-metadata-resource
diffcmp "GET /.well-known/oauth-protected-resource" /.well-known/oauth-protected-resource
diffcmp "GET /.well-known/oauth-protected-resource/mcp (RFC 9728 suffix form)" \
  /.well-known/oauth-protected-resource/mcp
CURRENT_ROW=authserver-metadata-as
diffcmp "GET /.well-known/oauth-authorization-server" /.well-known/oauth-authorization-server
CURRENT_ROW=authserver-register
diffcmp "POST /register with a remote https redirect_uri is refused, identically" /register \
  -X POST -H 'content-type: application/json' -d '{"redirect_uris":["https://attacker.example/cb"]}'
diffcmp "POST /register with a text/plain body is refused on content-type, identically" /register \
  -X POST -H 'content-type: text/plain' -d '{"redirect_uris":["http://127.0.0.1:1/cb"]}'
diffcmp "POST /register with no redirect_uris is refused, identically" /register \
  -X POST -H 'content-type: application/json' -d '{}'
diffcmp "cross-origin POST /register is refused, identically" /register \
  -X POST -H 'content-type: application/json' -H 'Origin: https://attacker.example' \
  -d '{"redirect_uris":["http://127.0.0.1:1/cb"]}'
CURRENT_ROW=authserver-token
diffcmp "cross-origin POST /token is refused, identically" /token \
  -X POST -H 'content-type: application/x-www-form-urlencoded' -H 'Origin: https://attacker.example' \
  -d 'grant_type=refresh_token&refresh_token=x'
# The out-of-family review's one finding: a sandboxed iframe, a data: document and some redirect
# chains all send `Origin: null`, and it used to be waved through as "not a browser origin".
diffcmp "Origin: null is refused on /register, identically" /register \
  -X POST -H 'content-type: application/json' -H 'Origin: null' \
  -d '{"redirect_uris":["http://127.0.0.1:1/cb"]}'
diffcmp "Origin: null is refused on /token, identically" /token \
  -X POST -H 'content-type: application/x-www-form-urlencoded' -H 'Origin: null' \
  -d 'grant_type=refresh_token&refresh_token=x'
diffcmp "a text/plain JSON-CSRF body on /register is refused when it carries an Origin" /register \
  -X POST -H 'content-type: text/plain' -H 'Origin: https://attacker.example' \
  -d '{"redirect_uris":["http://127.0.0.1:1/cb"]}'
diffcmp "a forged refresh token is refused, identically" /token \
  -X POST -H 'content-type: application/x-www-form-urlencoded' \
  -d 'grant_type=refresh_token&refresh_token=forged.notasignature'
diffcmp "an unsupported grant is refused, identically" /token \
  -X POST -H 'content-type: application/x-www-form-urlencoded' -d 'grant_type=password'
diffcmp "GET /token is refused, identically" /token
CURRENT_ROW=authserver-authorize
diffcmp "GET /authorize with an unissued client_id renders the same refusal page" \
  "/authorize?client_id=forged&redirect_uri=http%3A%2F%2F127.0.0.1%3A1%2Fcb&response_type=code"

echo
echo "the whole flow, at each router:"
CURRENT_ROW=authserver-authorize

flow() { # label base
  local label="$1" B="$2" reg cid v ch loc code tok at rt
  reg="$(bodyof "$B/register" -X POST -H 'content-type: application/json' \
    -d '{"redirect_uris":["http://127.0.0.1:33418/callback"],"client_name":"lane"}')"
  cid="$(printf '%s' "$reg" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("client_id",""))' 2>/dev/null)"
  [ -n "$cid" ] || { bad "$label registration returned no client_id"; return; }
  ok "$label registration returns a client_id"

  # Idempotent: the same redirect URIs must produce the same identifier, or a restart-free
  # re-registration leaks a new client every time and refresh grants start failing.
  local again
  again="$(bodyof "$B/register" -X POST -H 'content-type: application/json' \
    -d '{"redirect_uris":["http://127.0.0.1:33418/callback"],"client_name":"lane"}' \
    | python3 -c 'import json,sys;print(json.load(sys.stdin).get("client_id",""))' 2>/dev/null)"
  [ "$cid" = "$again" ] && ok "$label re-registering the same URIs is idempotent" \
                        || bad "$label re-registration minted a different client_id"

  v="$(python3 -c 'import base64,os;print(base64.urlsafe_b64encode(os.urandom(32)).rstrip(b"=").decode())')"
  ch="$(python3 -c "import base64,hashlib;print(base64.urlsafe_b64encode(hashlib.sha256('$v'.encode()).digest()).rstrip(b'=').decode())")"

  bodyof -G "$B/authorize" --data-urlencode "client_id=$cid" \
    --data-urlencode 'redirect_uri=http://127.0.0.1:33418/callback' \
    --data-urlencode 'response_type=code' --data-urlencode "code_challenge=$ch" \
    --data-urlencode 'code_challenge_method=S256' > "$WORK/consent.html"
  [ -s "$WORK/consent.html" ] && ok "$label GET /authorize renders the consent page" \
                              || bad "$label GET /authorize rendered nothing"
  # The ticket the page issues, read back the way a browser reads it: out of the form.
  local consent
  consent="$(sed -n 's/.*name="consent" value="\([^"]*\)".*/\1/p' "$WORK/consent.html" | head -1)"
  [ -n "$consent" ] && ok "$label the consent page carries a signed consent ticket" \
                    || bad "$label no consent ticket on the consent page"

  # A POST that never went through the page is refused, so the interstitial is not decorative.
  local noticket
  noticket="$(curl -sS -i -m 10 -X POST "$B/authorize" -H 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode "client_id=$cid" --data-urlencode 'redirect_uri=http://127.0.0.1:33418/callback' \
    --data-urlencode "code_challenge=$ch" 2>/dev/null)"
  if printf '%s' "$noticket" | head -1 | grep -q ' 400 ' \
     && ! printf '%s' "$noticket" | grep -qi '^location:'; then
    ok "$label POST /authorize without a consent ticket is refused and mints no code"
  else
    bad "$label POST /authorize minted a code without the consent page having been rendered"
  fi

  # The consent ticket must not be redeemable AS a code. Both blobs carry client, redirect,
  # challenge and expiry; only the type tag and the nonce tell them apart, and the review lane
  # redeemed a ticket at /token for a working token before the tag existed.
  check "$(status -X POST "$B/token" -H 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=authorization_code' --data-urlencode "code=$consent" \
    --data-urlencode "code_verifier=$v")" 400 \
    "$label a consent ticket is NOT redeemable as an authorization code"

  # /register must declare JSON: a text/plain form body parses as JSON and needs no preflight.
  check "$(status -X POST "$B/register" -H 'content-type: text/plain' \
    -d '{"redirect_uris":["http://127.0.0.1:1/cb"]}')" 415 \
    "$label POST /register without a JSON content-type is refused"

  # PKCE is required, not merely offered.
  loc="$(curl -sS -i -m 10 -G "$B/authorize" --data-urlencode "client_id=$cid" \
    --data-urlencode 'redirect_uri=http://127.0.0.1:33418/callback' \
    --data-urlencode 'response_type=code' --data-urlencode "code_challenge=$ch" \
    --data-urlencode 'code_challenge_method=plain' | grep -i '^location:' | tr -d '\r')"
  case "$loc" in *error=invalid_request*) ok "$label code_challenge_method=plain is refused" ;;
                 *) bad "$label plain PKCE was not refused: $loc" ;; esac

  # A remote redirect_uri must render a page, never a redirect to it.
  local remote_head
  remote_head="$(curl -sS -i -m 10 -G "$B/authorize" --data-urlencode "client_id=$cid" \
    --data-urlencode 'redirect_uri=https://attacker.example/cb' --data-urlencode 'response_type=code' \
    --data-urlencode "code_challenge=$ch" --data-urlencode 'code_challenge_method=S256')"
  if printf '%s' "$remote_head" | head -1 | grep -q ' 400 ' \
     && ! printf '%s' "$remote_head" | grep -qi '^location:'; then
    ok "$label a remote redirect_uri gets a 400 page and NO Location header"
  else
    bad "$label a remote redirect_uri was not refused cleanly"
  fi

  # The consent page carries the headers that stop it being framed.
  local head
  head="$(curl -sS -i -m 10 -o /dev/null -D - -G "$B/authorize" --data-urlencode "client_id=$cid" \
    --data-urlencode 'redirect_uri=http://127.0.0.1:33418/callback' --data-urlencode 'response_type=code' \
    --data-urlencode "code_challenge=$ch" --data-urlencode 'code_challenge_method=S256')"
  printf '%s' "$head" | grep -qi 'x-frame-options: DENY' \
    && printf '%s' "$head" | grep -qi "frame-ancestors 'none'" \
    && ! printf '%s' "$head" | grep -qi 'access-control-allow-origin' \
    && ! printf '%s' "$head" | grep -qi 'access-control-allow-private-network' \
    && ok "$label the consent page denies framing and sets no CORS header" \
    || bad "$label the consent page headers are wrong"

  # The WHOLE response, not just the header — and curl's exit code is checked.
  #
  # A 302 whose body is neither content-length'd nor chunked never completes: the `location`
  # header is readable immediately, so a grep for it passes while the client hangs until its
  # timeout. That is exactly what the Swift router did, and what this check exists to catch. curl
  # exit 28 here means the redirect a browser follows would stall.
  curl -sS -i -m 10 -X POST "$B/authorize" -H 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode "client_id=$cid" --data-urlencode 'redirect_uri=http://127.0.0.1:33418/callback' \
    --data-urlencode "code_challenge=$ch" --data-urlencode 'state=xyz' \
    --data-urlencode "consent=$consent" >"$WORK/redirect" 2>/dev/null
  local curl_status=$?
  if [ "$curl_status" = 0 ]; then
    ok "$label the 302 response completes rather than hanging on unframed body"
  else
    bad "$label the 302 never completed (curl exit $curl_status) — no content-length and no chunking"
  fi
  loc="$(grep -i '^location:' "$WORK/redirect" | tr -d '\r')"
  code="$(printf '%s' "$loc" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')"
  [ -n "$code" ] || { bad "$label POST /authorize returned no code"; return; }
  case "$loc" in *state=xyz*) ok "$label POST /authorize redirects with a code and echoes state" ;;
                 *) bad "$label state was not echoed" ;; esac

  # A wrong verifier must not redeem a genuine code.
  check "$(status -X POST "$B/token" -H 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=authorization_code' --data-urlencode "code=$code" \
    --data-urlencode 'code_verifier=wrong-verifier-entirely')" 400 "$label a wrong PKCE verifier is refused"

  tok="$(bodyof "$B/token" -X POST -H 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=authorization_code' --data-urlencode "code=$code" \
    --data-urlencode "code_verifier=$v" --data-urlencode "client_id=$cid" \
    --data-urlencode 'redirect_uri=http://127.0.0.1:33418/callback')"
  at="$(printf '%s' "$tok" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)"
  rt="$(printf '%s' "$tok" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("refresh_token",""))' 2>/dev/null)"
  [ -n "$at" ] && [ -n "$rt" ] && ok "$label the code is exchanged for an access and a refresh token" \
                              || { bad "$label token exchange failed: $(printf '%s' "$tok" | cut -c1-120)"; return; }

  check "$(status -X POST "$B/token" -H 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=authorization_code' --data-urlencode "code=$code" \
    --data-urlencode "code_verifier=$v")" 400 "$label replaying the code is refused"

  check "$(status -X POST "$B/token" -H 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=refresh_token' --data-urlencode "refresh_token=$rt")" 200 \
    "$label the refresh token is accepted"

  # /mcp never returns 401 — the invariant that keeps a token lost to a restart from breaking
  # connectivity. Bare, valid-bearer and garbage-bearer must be indistinguishable.
  local bare valid junk
  bare="$(status -X POST "$B/mcp" -H 'content-type: application/json' \
    -H 'accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')"
  valid="$(status -X POST "$B/mcp" -H 'content-type: application/json' \
    -H 'accept: application/json, text/event-stream' -H "authorization: Bearer $at" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')"
  junk="$(status -X POST "$B/mcp" -H 'content-type: application/json' \
    -H 'accept: application/json, text/event-stream' -H 'authorization: Bearer garbage' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')"
  if [ "$bare" = 200 ] && [ "$valid" = 200 ] && [ "$junk" = 200 ]; then
    ok "$label /mcp answers 200 bare, with a valid bearer and with a garbage one — never 401"
  else
    bad "$label /mcp differed by Authorization: bare=$bare valid=$valid junk=$junk"
  fi

  # Every new route inherits R15's authority check, proven by the same arm that proves it for /mcp.
  local hostfail=0
  for p in /.well-known/oauth-protected-resource /.well-known/oauth-authorization-server \
           /register /authorize /token; do
    [ "$(status "$B$p" -H 'Host: evil.example')" = 403 ] || hostfail=1
  done
  [ "$hostfail" = 0 ] && ok "$label a foreign Host is refused on all five new routes" \
                      || bad "$label a foreign Host reached a new route"

  printf '%s' "$rt" > "$WORK/rt.$(basename "$B")"
}

flow "reference:" "$TS"
flow "Swift:    " "$SW"

# The framing of the redirect, compared across routers with the sealed code normalised away.
# Header NAMES and order are the comparison: that is where the missing chunking lived.
redirect_frame() { # base -> header names, in order
  local B="$1" reg cid
  reg="$(bodyof "$B/register" -X POST -H 'content-type: application/json' \
    -d '{"redirect_uris":["http://127.0.0.1:33418/callback"]}')"
  cid="$(printf '%s' "$reg" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("client_id",""))')"
  local consent
  consent="$(bodyof -G "$B/authorize" --data-urlencode "client_id=$cid" \
    --data-urlencode 'redirect_uri=http://127.0.0.1:33418/callback' \
    --data-urlencode 'response_type=code' --data-urlencode 'code_challenge=abc' \
    --data-urlencode 'code_challenge_method=S256' \
    | sed -n 's/.*name="consent" value="\([^"]*\)".*/\1/p' | head -1)"
  curl -sS -i -m 10 -X POST "$B/authorize" -H 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode "client_id=$cid" --data-urlencode 'redirect_uri=http://127.0.0.1:33418/callback' \
    --data-urlencode 'code_challenge=abc' --data-urlencode "consent=$consent" 2>/dev/null \
    | sed -n '1,/^\r$/p' | tr -d '\r' | sed -e 's/:.*//' -e '/^$/d'
}
redirect_frame "$TS" > "$WORK/frame.ts"
redirect_frame "$SW" > "$WORK/frame.sw"
if [ -s "$WORK/frame.ts" ] && diff -q "$WORK/frame.ts" "$WORK/frame.sw" >/dev/null 2>&1; then
  ok "the 302 head carries the same headers, in the same order, at both routers"
else
  bad "the 302 framing differs — $(diff "$WORK/frame.ts" "$WORK/frame.sw" | tr '\n' ' ' | cut -c1-140)"
fi

echo
echo "the state report, at both routers:"
CURRENT_ROW=authserver-state-report
# The page must name the upstream that is serving nothing, and must NOT tell the owner to
# authorise one that is already authorised. `needsauth` has no credential record here, so it is
# the never-authorised row; `probe` is stdio and can never be an authorisation story.
for pair in "reference:$TS" "Swift:$SW"; do
  side="${pair%%:*}"; B="${pair#*:}"
  reg="$(bodyof "$B/register" -X POST -H 'content-type: application/json' \
    -d '{"redirect_uris":["http://127.0.0.1:33418/callback"]}')"
  cid="$(printf '%s' "$reg" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("client_id",""))')"
  v="$(python3 -c 'import base64,os;print(base64.urlsafe_b64encode(os.urandom(32)).rstrip(b"=").decode())')"
  ch="$(python3 -c "import base64,hashlib;print(base64.urlsafe_b64encode(hashlib.sha256('$v'.encode()).digest()).rstrip(b'=').decode())")"
  page="$(bodyof -G "$B/authorize" --data-urlencode "client_id=$cid" \
    --data-urlencode 'redirect_uri=http://127.0.0.1:33418/callback' --data-urlencode 'response_type=code' \
    --data-urlencode "code_challenge=$ch" --data-urlencode 'code_challenge_method=S256')"
  printf '%s' "$page" | grep -q 'needsauth' \
    && ok "$side the page names the upstream serving no tools" \
    || bad "$side the page does not name needsauth"
  printf '%s' "$page" | grep -q 'never authorised' \
    && ok "$side it is reported as never authorised, not as a generic failure" \
    || bad "$side needsauth is not in the never-authorised state"
  printf '%s' "$page" | grep -q 'auth needsauth' \
    && ok "$side it carries the command that fixes it" \
    || bad "$side no command is offered for needsauth"
  printf '%s' "$page" | grep -q 'Authorising will not help' \
    && ok "$side the stdio upstream is told authorising will not help it" \
    || bad "$side the stdio upstream was mis-reported as an auth problem"
  CURRENT_ROW=authserver-instructions
  instr="$(bodyof "$B/mcp" -X POST -H 'content-type: application/json' \
    -H 'accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"lane","version":"1"}}}' \
    | sed -n 's/^data: //p' \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"].get("instructions",""))')"
  printf '%s' "$instr" | grep -q 'needsauth' \
    && ok "$side initialize carries instructions naming the same set" \
    || bad "$side initialize instructions do not name needsauth"
  CURRENT_ROW=authserver-state-report
done

echo
echo "a token minted before a restart still validates after it:"
CURRENT_ROW=authserver-token
kill "$TS_PID" 2>/dev/null; wait "$TS_PID" 2>/dev/null
kill "$SWIFT_PID" 2>/dev/null; wait "$SWIFT_PID" 2>/dev/null
MCP_ROUTER_HOME="$WORK/ts" node "$REPO_ROOT/dist/index.js" serve --port "$TS_PORT" \
  >>"$WORK/ts.log" 2>&1 & TS_PID=$!
MCP_ROUTER_HOME="$WORK/swift" "$SWIFT_BIN" serve --port "$SWIFT_PORT" \
  >>"$WORK/swift.log" 2>&1 & SWIFT_PID=$!
wait_ready "$TS_PORT" "$TS_PID" reference || exit 2
wait_ready "$SWIFT_PORT" "$SWIFT_PID" Swift || exit 2
for pair in "reference:$TS" "Swift:$SW"; do
  side="${pair%%:*}"; B="${pair#*:}"
  rt="$(cat "$WORK/rt.$(basename "$B")" 2>/dev/null)"
  check "$(status -X POST "$B/token" -H 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=refresh_token' --data-urlencode "refresh_token=$rt")" 200 \
    "$side a pre-restart refresh token is still valid"
done

echo
echo "the issuer key is 0600 in a 0700 directory, at both routers:"
CURRENT_ROW=authserver-token
for side in ts swift; do
  mode="$(stat -f '%Lp' "$WORK/$side/auth/issuer.key" 2>/dev/null)"
  dmode="$(stat -f '%Lp' "$WORK/$side/auth" 2>/dev/null)"
  [ "$mode" = 600 ] && [ "$dmode" = 700 ] && ok "$side issuer.key $mode in auth/ $dmode" \
                                          || bad "$side issuer.key mode $mode, dir $dmode"
done

echo
echo "redirect_uri parsing, at both routers (the two URL parsers normalise differently):"
CURRENT_ROW=authserver-register
# Measured across 21 shapes on 2026-08-21. Every userinfo trick resolves to the attacker's host at
# BOTH parsers, because both read the PARSED host rather than the raw string. The two shapes Node
# accepts and Foundation refuses are declared in div-r14-redirect-host and are asserted here as a
# divergence in BOTH directions, so it cannot be quietly fixed from either end without this saying so.
reg_status() { # base uri
  status "$1/register" -X POST -H 'content-type: application/json' \
    -d "{\"redirect_uris\":[\"$2\"]}"
}
for uri in 'http://[::1]:1/cb' 'http://127.0.0.1:1/cb' 'http://localhost:1/cb' \
           'http://LOCALHOST:1/cb' 'http://[0:0:0:0:0:0:0:1]:1/cb'; do
  a="$(reg_status "$TS" "$uri")"; b="$(reg_status "$SW" "$uri")"
  if [ "$a" = 201 ] && [ "$b" = 201 ]; then ok "accepted at both: $uri"
  else bad "$uri -> $a / $b, expected 201 / 201"; fi
done
for uri in 'https://127.0.0.1/cb' 'http://[::1]@evil.example/cb' 'http://127.0.0.1@evil.example/cb' \
           'http://localhost@evil.example/cb' 'http://[::ffff:127.0.0.1]/cb' \
           'http://127.0.0.1.evil.example/cb' 'http://localhost.evil.example/cb' \
           'http://evil.example/cb#127.0.0.1'; do
  a="$(reg_status "$TS" "$uri")"; b="$(reg_status "$SW" "$uri")"
  if [ "$a" = 400 ] && [ "$b" = 400 ]; then ok "refused at both: $uri"
  else bad "$uri -> $a / $b, expected 400 / 400"; fi
done
for uri in 'http://127.1/cb' 'http://2130706433/cb'; do
  a="$(reg_status "$TS" "$uri")"; b="$(reg_status "$SW" "$uri")"
  if [ "$a" = 201 ] && [ "$b" = 400 ]; then
    ok "declared divergence holds — the reference accepts IPv4 shorthand and Swift refuses: $uri"
  else
    bad "div-r14-redirect-host is stale: $uri -> $a / $b, declared 201 / 400"
  fi
done

echo
echo "R15 — the authority check sits ahead of the whole ladder:"
CURRENT_ROW=authserver-host-authority
# Every route, old and new. The point of the row is that a route added later inherits the refusal,
# so the pre-existing routes are checked here alongside the ones R14 added: before R15 these four
# answered 200 to a foreign Host while /mcp answered 403.
for path in /health /status /servers /usage /registry/search /nope \
            /.well-known/oauth-protected-resource /.well-known/oauth-authorization-server \
            /register /authorize /token; do
  a="$(status "$TS$path" -H 'Host: evil.example')"
  b="$(status "$SW$path" -H 'Host: evil.example')"
  if [ "$a" = 403 ] && [ "$b" = 403 ]; then ok "a foreign Host is refused on $path at both routers"
  else bad "$path answered $a / $b to a foreign Host, not 403 / 403"; fi
done
# And /mcp's refusal body is still the transport's own, byte for byte, at both routers.
bodyof "$TS/mcp" -X POST -H 'content-type: application/json' \
  -H 'accept: application/json, text/event-stream' -H 'Host: evil.example' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' > "$WORK/mcp403.ts"
bodyof "$SW/mcp" -X POST -H 'content-type: application/json' \
  -H 'accept: application/json, text/event-stream' -H 'Host: evil.example' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' > "$WORK/mcp403.sw"
expected='{"jsonrpc":"2.0","error":{"code":-32000,"message":"Invalid Host header: evil.example"},"id":null}'
if [ "$(cat "$WORK/mcp403.ts")" = "$expected" ] && [ "$(cat "$WORK/mcp403.sw")" = "$expected" ]; then
  ok "/mcp's 403 body is unchanged and identical at both routers"
else
  bad "/mcp's 403 body moved — the parity row's pinned wording no longer holds"
fi
# The other routes get an ordinary 403, not the JSON-RPC envelope.
if bodyof "$TS/health" -H 'Host: evil.example' | grep -q '^{"error":"Invalid Host header' \
   && bodyof "$SW/health" -H 'Host: evil.example' | grep -q '^{"error":"Invalid Host header'; then
  ok "a non-/mcp route gets the ordinary error envelope, not the JSON-RPC one"
else
  bad "a non-/mcp route's refusal body is not the ordinary envelope"
fi

verdict_rows

echo
echo "parity-authserver: $pass checks passed, $fail failed"
[ "$fail" -gt 0 ] && exit 1
exit 0
