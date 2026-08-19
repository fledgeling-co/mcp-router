#!/usr/bin/env bash
#
# P7 — the OAuth lane: `control-auth-post-http`, the HTTP half of `POST /servers/:name/auth`.
#
# `control-auth-post` proves the STDIO REFUSAL. This proves the other half — the one where the
# reference begins a real OAuth flow and answers 200 with an `authorizationUrl`, and where this
# router answered 405 until an `AuthTransport` existed outside the test target (`D-p1-a`).
#
# WHAT IS COMPARED, and why each piece is here rather than just the response body:
#
#   1. the 200 and its `authorizationUrl`, with the per-run PKCE challenge normalised;
#   2. the SEQUENCE OF REQUESTS each router made to the provider. This is the piece that answers
#      the recorded objection to this row — a fixture that answers every conventional path cannot
#      tell a correct discovery cascade from a client that hardcodes `/authorize`, so the
#      authorization server's own endpoints sit behind FIXTURE_OAUTH_PREFIX at a path nothing can
#      guess and are advertised ONLY in the metadata document;
#   3. the dynamic-registration request body, byte for byte;
#   4. the token request's form parameters, in order, with the per-run code verifier normalised;
#   5. the page the browser lands on after the provider redirects, byte for byte;
#   6. the credential file the flow writes, whose member order and membership are decided by the
#      reference SDK's schema rather than by the provider — the fixture answers in a deliberately
#      different order and carries an unknown member, so a port that wrote the provider's bytes
#      straight through diverges here;
#   7. `GET /servers/:name`'s `auth` sub-object, which is how the app learns any of this happened;
#   8. a SECOND authorization against the now-authorized server, which the reference does not
#      answer with a new URL at all — it refreshes instead. That is a whole branch a first-flow
#      comparison never reaches.
#
# WHAT IS NOT COMPARED, stated rather than implied:
#
#   * the MCP `initialize` body of the probe that provokes the 401. That is the MCP handshake and
#     the `mcp` rows own it; the fixture refuses every request to `/mcp` whatever it says.
#   * everything the routers do AFTER the token exchange. Authorizing triggers a re-index, the
#     fixture refuses that too, and the reference's SDK then retries the refresh grant a
#     nondeterministic number of times. The comparison is therefore of the log PREFIX up to and
#     including the token request, and the truncation is asserted rather than assumed.
#
# Exit codes follow the house pattern:
#   0  the two routers agreed on everything above
#   1  they disagreed
#   2  the environment could not run the check. A skipped comparison is not a passing one.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST="${MCP_ROUTER_DIST:-$REPO_ROOT/dist}"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
FIXTURE="$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs"
RESULTS="${PARITY_RESULTS:-}"

OAUTH_PORT="${OAUTH_PORT:-8967}"
ROUTER_PORT="${ROUTER_PORT:-8968}"
CALLBACK_PORT="${CALLBACK_PORT:-8969}"
# Advertised only through the metadata document. A client that guesses `/authorize` gets the
# fixture's catch-all 401 and produces no flow at all.
PREFIX="${PARITY_OAUTH_PREFIX:-/as-9c41f7}"
SERVER_NAME="fx"

WORK="$(mktemp -d -t parity-oauth)"
FIXTURE_PID=""
ROUTER_PID=""

record() { # id ok|fail detail
  [ -n "$RESULTS" ] || return 0
  printf 'control\t%s\t%s\t%s\n' "$1" "$2" "$3" >> "$RESULTS"
}

. "$REPO_ROOT/scripts/acceptance/parity-lock.sh"

stop_router() {
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null
  [ -n "$ROUTER_PID" ] && wait "$ROUTER_PID" 2>/dev/null
  ROUTER_PID=""
}
stop_fixture() {
  [ -n "$FIXTURE_PID" ] && kill "$FIXTURE_PID" 2>/dev/null
  [ -n "$FIXTURE_PID" ] && wait "$FIXTURE_PID" 2>/dev/null
  FIXTURE_PID=""
}
# Between the two sides the ports have to be BINDABLE, which is a stronger condition than "not
# listening" and is the one that actually decides whether the next side starts.
#
# Measured rather than guessed: after the reference side, `lsof -sTCP:LISTEN` reports :8969 free and
# the Swift callback listener still fails with EADDRINUSE. The reference's callback server closes
# the browser connection last, so the port sits in TIME_WAIT on the server side — node's listener
# sets SO_REUSEADDR and binds straight over it, while `LoopbackCallbackListener` sets
# `allowLocalEndpointReuse = false` on purpose (R5, B84: a second router process must FAIL to bind
# rather than silently take half the callbacks). So the harness waits for the kernel, and a bind
# attempt is the only probe that answers the question being asked.
port_bindable() {
  python3 -c '
import socket, sys
probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    probe.bind(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    probe.close()
' "$1"
}

wait_for_ports_bindable() {
  local port waited
  for port in "$@"; do
    waited=0
    until port_bindable "$port"; do
      sleep 0.5
      waited=$((waited + 1))
      if [ "$waited" -gt 120 ]; then
        echo "environment: :$port was still unbindable 60s after the previous side was stopped"
        exit 2
      fi
    done
    [ "$waited" -gt 0 ] && echo "  (waited $((waited / 2))s for :$port to become bindable again)"
  done
  return 0
}

cleanup() { parity_lock_release; stop_router; stop_fixture; rm -rf "$WORK"; }
trap cleanup EXIT INT TERM HUP

parity_lock_acquire "parity-oauth.sh"

environment_failure() {
  echo "environment: $1"
  echo "             This row stays blocked. A comparison that could not run is not a pass."
  exit 2
}

command -v node >/dev/null 2>&1 || environment_failure "node is not installed"
command -v curl >/dev/null 2>&1 || environment_failure "curl is not installed"
command -v python3 >/dev/null 2>&1 || environment_failure "python3 is not installed"
[ -f "$DIST/index.js" ] || environment_failure \
  "no built reference at $DIST/index.js — run 'npm install && npm run build', or set MCP_ROUTER_DIST"
[ -x "$SWIFT_BIN" ] || environment_failure \
  "no MCPRouterCLI at $SWIFT_BIN (run: make build, or swift build --package-path app)"
[ -f "$FIXTURE" ] || environment_failure "no fixture upstream at $FIXTURE"

for port in "$OAUTH_PORT" "$ROUTER_PORT" "$CALLBACK_PORT"; do
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    environment_failure "something is already listening on :$port, so a readiness probe here
             cannot tell this run's process from a stranger's"
  fi
done

# ---------------------------------------------------------------------------------------------
# One side: a fresh provider, a fresh scratch home, a fresh router, one whole authorization.
run_side() { # label  command...
  local label="$1"; shift
  local home="$WORK/$label-home"
  local log="$WORK/$label.rawlog"
  mkdir -p "$home"
  : > "$log"

  FIXTURE_OAUTH_PORT="$OAUTH_PORT" FIXTURE_OAUTH_PREFIX="$PREFIX" FIXTURE_OAUTH_LOG="$log" \
    node "$FIXTURE" oauth > "$WORK/$label-fixture.out" 2>&1 &
  FIXTURE_PID=$!
  local ready=""
  for _ in $(seq 1 60); do
    curl -sS -m 2 -o /dev/null "http://127.0.0.1:$OAUTH_PORT/.well-known/oauth-protected-resource" \
      >/dev/null 2>&1 && { ready=ok; break; }
    kill -0 "$FIXTURE_PID" 2>/dev/null || break
    sleep 0.2
  done
  [ "$ready" = ok ] || environment_failure "the fixture provider never answered on :$OAUTH_PORT
             ($(tail -3 "$WORK/$label-fixture.out" | tr '\n' ' '))"

  cat > "$home/servers.json" <<JSON
{ "mcpServers": { "$SERVER_NAME": { "url": "http://127.0.0.1:$OAUTH_PORT/mcp", "type": "http", "oauth": true } } }
JSON

  MCP_ROUTER_HOME="$home" MCP_ROUTER_AUTH_PORT="$CALLBACK_PORT" \
    "$@" serve --port "$ROUTER_PORT" > "$WORK/$label-serve.out" 2>&1 &
  ROUTER_PID=$!
  ready=""
  for _ in $(seq 1 100); do
    curl -fsS -m 2 "http://127.0.0.1:$ROUTER_PORT/health" >/dev/null 2>&1 && { ready=ok; break; }
    kill -0 "$ROUTER_PID" 2>/dev/null || break
    sleep 0.2
  done
  [ "$ready" = ok ] || environment_failure "the $label router never answered /health on :$ROUTER_PORT
             ($(tail -5 "$WORK/$label-serve.out" | tr '\n' ' '))"

  local token; token="$(cat "$home/control.token" 2>/dev/null || echo '')"
  [ -n "$token" ] || environment_failure "the $label router minted no control token"

  # 1 — the route itself.
  local status hop
  status="$(curl -sS -m 30 -o "$WORK/$label.auth" -w '%{http_code}' -X POST \
    -H "x-mcpr-token: $token" -H 'content-type: application/json' --data-binary '{}' \
    "http://127.0.0.1:$ROUTER_PORT/servers/$SERVER_NAME/auth" 2>/dev/null)"
  # `-w` always prints a code, and prints `000` when curl never connected. An `|| echo 000`
  # fallback here appended a second token and reported `000000`, which compares unequal to every
  # real status including another failure — a difference that is the harness, not the routers.
  printf 'status=%s\n' "${status:-000}" > "$WORK/$label.authstatus"

  local url
  url="$(python3 -c "import json,sys
try: print(json.load(open('$WORK/$label.auth')).get('authorizationUrl',''))
except Exception: print('')")"

  # 2 — the browser hop, followed to the router's own callback listener.
  if [ -n "$url" ]; then
    hop="$(curl -sSL -m 30 -o "$WORK/$label.page" -w '%{http_code}' "$url" 2>/dev/null)"
    printf 'final=%s\n' "${hop:-000}" > "$WORK/$label.pagestatus"
  else
    : > "$WORK/$label.page"
    printf 'final=no-url\n' > "$WORK/$label.pagestatus"
  fi

  # The record is written inside the callback's own request, so it exists by the time the page
  # comes back — but the re-index that follows is not awaited, so give the file a bounded wait
  # rather than a sleep whose length is a guess.
  for _ in $(seq 1 50); do
    [ -s "$home/auth/$SERVER_NAME.json" ] && break
    sleep 0.1
  done
  cp "$home/auth/$SERVER_NAME.json" "$WORK/$label.record" 2>/dev/null || : > "$WORK/$label.record"

  # 3 — how the app sees it.
  curl -sS -m 10 -H "x-mcpr-token: $token" \
    "http://127.0.0.1:$ROUTER_PORT/servers/$SERVER_NAME" > "$WORK/$label.describe.raw" 2>/dev/null
  python3 -c "import json
try:
    d = json.load(open('$WORK/$label.describe.raw'))
    print(json.dumps(d.get('auth'), sort_keys=False, separators=(',', ':')))
except Exception:
    print('')" > "$WORK/$label.describe"

  # 4 — the second authorization, against a server that now holds tokens. The reference refreshes
  # rather than opening a browser, so this branch never appears in a first-flow comparison.
  status="$(curl -sS -m 60 -o "$WORK/$label.reauth" -w '%{http_code}' -X POST \
    -H "x-mcpr-token: $token" -H 'content-type: application/json' --data-binary '{}' \
    "http://127.0.0.1:$ROUTER_PORT/servers/$SERVER_NAME/auth" 2>/dev/null)"
  printf 'status=%s\n' "${status:-000}" > "$WORK/$label.reauthstatus"

  stop_router
  stop_fixture
  wait_for_ports_bindable "$ROUTER_PORT" "$OAUTH_PORT" "$CALLBACK_PORT"
  cp "$log" "$WORK/$label.log.full"
}

# ---------------------------------------------------------------------------------------------
# Normalisation. Every pattern is ANCHORED and LENGTH-EXACT, so a value of the wrong shape is left
# alone and shows up as a difference rather than being quietly absorbed — which is the failure mode
# `D-o` cost this harness once already.
normalise() { # file
  python3 - "$1" <<'PY'
import re, sys

text = open(sys.argv[1]).read()
# A PKCE S256 challenge is exactly 43 base64url characters.
text = re.sub(r'(?<=code_challenge=)[A-Za-z0-9_-]{43}(?![A-Za-z0-9_-])', '<challenge>', text)
# A verifier is exactly 43 characters of pkce-challenge's own mask, percent-encoded on the wire
# (`~` becomes %7E) and raw in the credential file.
text = re.sub(r'(?<=code_verifier=)(?:[A-Za-z0-9._~-]|%7E){43,60}(?![A-Za-z0-9._~%-])',
              '<verifier>', text)
text = re.sub(r'"codeVerifier": "[A-Za-z0-9._~-]{43}"', '"codeVerifier": "<verifier>"', text)
text = re.sub(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z', '<timestamp>', text)
sys.stdout.write(text)
PY
}

# The comparison is over the log PREFIX ending at the token request. Everything after it is the
# post-authorization re-index, which this row does not own and whose retry count is not stable.
truncate_log() { # file
  python3 - "$1" "$PREFIX" <<'PY'
import json, sys

path, prefix = sys.argv[1], sys.argv[2]
out = []
for line in open(path):
    line = line.strip()
    if not line:
        continue
    entry = json.loads(line)
    out.append(json.dumps(entry, separators=(',', ':'), sort_keys=True))
    if entry['method'] == 'POST' and entry['path'] == f'{prefix}/token':
        break
else:
    sys.stderr.write('no token request in the log\n')
    sys.exit(3)
sys.stdout.write('\n'.join(out) + '\n')
PY
}

echo "P7 — control-auth-post-http: the OAuth half of POST /servers/:name/auth, both routers"
echo "     provider on :$OAUTH_PORT with its endpoints at $PREFIX, callback on :$CALLBACK_PORT"
echo

run_side reference node "$DIST/index.js"
run_side swift "$SWIFT_BIN"

# A side that never reached the token endpoint completed no authorization, and WHICH side it was
# decides what that means. The distinction is not pedantry — it was bought by the mutation gate,
# which broke the Swift client on purpose and watched the lane report `environment: could not run`.
# That is the wrong answer twice over: it says the harness is broken when the router is, and it
# reports a lane that DID measure something as a lane that measured nothing.
#
#   * the REFERENCE side is the oracle. If it cannot complete a flow, the fixture or `dist/` is
#     broken and there is nothing to compare against — exit 2, and the row stays blocked.
#   * the SWIFT side is the subject. If it cannot complete a flow the reference completed, that is
#     the finding — exit 1, with the row recorded `fail`.
incomplete() { # label
  echo "the $label side made no token request, so no authorization completed."
  echo "  POST /auth:  $(cat "$WORK/$1.authstatus") $(cat "$WORK/$1.auth")"
  echo "  browser hop: $(cat "$WORK/$1.pagestatus")"
  echo "  router log:  $(tail -5 "$WORK/$1-serve.out" | tr '\n' ' ')"
  echo "  the provider saw:"
  sed -n '1,20p' "$WORK/$1.log.full" | sed 's/^/    /'
}

for label in reference swift; do
  truncate_log "$WORK/$label.log.full" > "$WORK/$label.log" 2> "$WORK/$label.logerr" || {
    if [ "$label" = reference ]; then
      echo "environment: the ORACLE could not complete an authorization, so there is nothing to"
      echo "             compare against. This row stays blocked; it is not a pass and not a"
      echo "             failure of the router under test."
      incomplete "$label"
      record control-auth-post-http blocked "the reference side never reached the token endpoint"
      exit 2
    fi
    echo "FAIL — the reference completed an authorization and this router did not."
    incomplete "$label"
    record control-auth-post-http fail "the Swift router never reached the token endpoint"
    exit 1
  }
done

# ---------------------------------------------------------------------------------------------
# Guards that make the comparison mean something. Each one exists because its absence lets two
# empty, absent or unrecognised values compare equal — which is a green row over nothing.
pass=0
fail=0
declare -a failures=()

guard() { # label test-result explanation
  if [ "$2" = ok ]; then
    printf '  ok   %-46s %s\n' "$1" "${3:-}"
    pass=$((pass + 1))
  else
    printf '  FAIL %-46s %s\n' "$1" "${3:-}"
    fail=$((fail + 1)); failures+=("$1")
  fi
}

echo "guards — the comparison has something to compare"
for label in reference swift; do
  normalise "$WORK/$label.auth" > "$WORK/$label.auth.n"
  normalise "$WORK/$label.log" > "$WORK/$label.log.n"
  normalise "$WORK/$label.record" > "$WORK/$label.record.n"
  normalise "$WORK/$label.describe" > "$WORK/$label.describe.n"

  [ "$(cat "$WORK/$label.authstatus")" = "status=200" ] \
    && guard "$label answered 200 to POST /auth" ok \
    || guard "$label answered 200 to POST /auth" fail "$(cat "$WORK/$label.authstatus")"
  grep -q '<challenge>' "$WORK/$label.auth.n" \
    && guard "$label produced a 43-char S256 challenge" ok \
    || guard "$label produced a 43-char S256 challenge" fail "$(cat "$WORK/$label.auth")"
  grep -q '<verifier>' "$WORK/$label.record.n" \
    && guard "$label saved a well-formed code verifier" ok \
    || guard "$label saved a well-formed code verifier" fail
  grep -q '"access_token"' "$WORK/$label.record.n" \
    && guard "$label's credential file holds a token" ok \
    || guard "$label's credential file holds a token" fail "$(cat "$WORK/$label.record")"
  [ "$(cat "$WORK/$label.pagestatus")" = "final=200" ] \
    && guard "$label's callback answered the browser 200" ok \
    || guard "$label's callback answered the browser 200" fail "$(cat "$WORK/$label.pagestatus")"
  lines="$(wc -l < "$WORK/$label.log" | tr -d ' ')"
  [ "$lines" -ge 6 ] \
    && guard "$label's provider saw the whole cascade" ok "$lines requests" \
    || guard "$label's provider saw the whole cascade" fail "$lines requests, expected 6 or more"
done

echo
echo "the comparison — $(wc -l < "$WORK/reference.log" | tr -d ' ') provider requests per side"
compare() { # label file
  if diff -u "$WORK/reference.$2" "$WORK/swift.$2" > "$WORK/$2.diff"; then
    printf '  ok   %-46s identical\n' "$1"
    pass=$((pass + 1))
  else
    printf '  FAIL %-46s\n' "$1"
    sed -n '1,24p' "$WORK/$2.diff" | sed 's/^/       /'
    fail=$((fail + 1)); failures+=("$1")
  fi
}

compare "the 200 and its authorizationUrl" auth.n
compare "every request the provider was sent" log.n
compare "the credential file on disk" record.n
compare "the page the browser lands on" page
compare "GET /servers/:name's auth sub-object" describe.n
compare "a second authorization on an authorized server" reauth
if [ "$(cat "$WORK/reference.reauthstatus")" = "$(cat "$WORK/swift.reauthstatus")" ]; then
  printf '  ok   %-46s %s\n' "the second authorization's status" \
    "$(cat "$WORK/reference.reauthstatus")"
  pass=$((pass + 1))
else
  printf '  FAIL %-46s reference %s, swift %s\n' "the second authorization's status" \
    "$(cat "$WORK/reference.reauthstatus")" "$(cat "$WORK/swift.reauthstatus")"
  fail=$((fail + 1)); failures+=("the second authorization's status")
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "$pass checks passed, 0 failed — examined=$pass failures=0"
  echo "the routers agree on the discovery cascade, the registration bytes, the PKCE parameters,"
  echo "the token exchange, the callback page, the credential file and the re-authorization branch."
  record control-auth-post-http ok \
    "compared on the wire against the running reference: $pass checks, 0 failures"
  exit 0
fi

echo "$pass passed, $fail failed:"
for item in "${failures[@]}"; do echo "  - $item"; done
record control-auth-post-http fail "$fail of $((pass + fail)) checks disagreed: ${failures[*]}"
exit 1
