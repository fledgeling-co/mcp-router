#!/usr/bin/env bash
#
# F6 — `GET /extensions/updates`, over the daemon's own socket, against a real store on disk.
#
# TWO things the unit suite structurally cannot see.
#
# The first is R28's and R31's lesson repeated: `ControlDeps.extensions` is optional exactly as
# `registry` and `authFlow` are, and both of those shipped nil in `RouterServiceDispatch` with a
# green suite — `GET /registry/search` answered 502 in the only process that ships, and
# `POST /servers/:name/auth` answered 405 until P7. Deleting the one `extensions:` line leaves every
# unit test passing and turns this whole lane into 503s.
#
# The second is this item's own. The verdict this feature exists to produce — `update-available` —
# fires ZERO times on the author's real machine: measured 2026-08-29 over all 127 installed plugins
# by `planning/evidence/F6/measure-update-surface.py`, 105 are equal, 22 cannot be compared at all,
# and the single difference points backwards (held 2.0.0, offered 1.0.0). So there is no reading of
# a real tree that exercises the state that costs an install, and the fixture below is the only
# place it can be driven. Every entry in it is written with `mkdir` and `printf` — never through the
# API — so what the route reports is a reading of the bytes rather than a record of a call.
#
# THE FIXTURE'S SHAPE IS THE REAL ONE, in the place it matters: a plugin is stored under
# `<plugin>@<marketplace>` while its own `plugin.json` names `<plugin>`. That is what R30's `adopt`
# produces and what `add` refuses, so a lane built through the API would prove the route against a
# shape the product never holds.
#
# EVERY PATH IS INSIDE A SCRATCH HOME. `MCP_ROUTER_HOME` moves the store with the rest of the
# router's state, and the last check proves the operator's own `~/.claude` was never read.
#
# Exit codes follow the house pattern:
#   0  every assertion held
#   1  the daemon answered, and answered something wrong
#   2  the environment could not run the check — the binary is missing, or the daemon never bound.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST="${MCP_ROUTER_DIST:-$REPO_ROOT/dist}"
HOME_DIR="$(mktemp -d -t mcprouter-f6)"
PORT="${PORT:-8991}"
ROUTER_PID=""

pass=0
fail=0
declare -a failures=()

. "$REPO_ROOT/scripts/acceptance/acceptance-lock.sh"

cleanup() {
  parity_lock_release
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null
  wait "$ROUTER_PID" 2>/dev/null
  rm -rf "$HOME_DIR"
}
trap cleanup EXIT INT TERM HUP

parity_lock_acquire "f6-updates.sh"

[ -f "$DIST/index.js" ] || { echo "environment: build TypeScript first (npm run build)"; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "environment: curl is not installed"; exit 2; }

# The operator's own tree, stat'ed before anything runs. Read-only, and the denominator for the
# last check in this file rather than decoration.
REAL_CLAUDE="$HOME/.claude/plugins/marketplaces"
real_before="$(ls -1 "$REAL_CLAUDE" 2>/dev/null | wc -l | tr -d ' ')"

# ------------------------------------------------------------------ the fixture
STORE="$HOME_DIR/extensions"

write() { # kind name relative-descriptor-path body
  mkdir -p "$STORE/$1/$2/$(dirname "$3")"
  printf '%s' "$4" >"$STORE/$1/$2/$3"
}

plugin() { write plugins "$1" .claude-plugin/plugin.json "$2"; }
market() { write marketplaces "$1" .claude-plugin/marketplace.json "$2"; }

market f6-market '{"name":"f6-market","plugins":[
  {"name":"behind","version":"2.0.0"},
  {"name":"level","version":"1.0.0"},
  {"name":"ahead","version":"1.0.0"},
  {"name":"sha","version":"aa11bb22cc33"},
  {"name":"silent"},
  {"name":"unversioned","version":"1.0.0"}
]}'
# The descriptor names the PLUGIN; the directory names `<plugin>@<marketplace>`. That disagreement
# is the real shape, and a reader that used the descriptor's name would find nothing to compare.
plugin 'behind@f6-market'      '{"name":"behind","version":"1.0.0"}'
plugin 'level@f6-market'       '{"name":"level","version":"1.0.0"}'
plugin 'ahead@f6-market'       '{"name":"ahead","version":"2.0.0"}'
plugin 'sha@f6-market'         '{"name":"sha","version":"ed404106fcd8"}'
plugin 'silent@f6-market'      '{"name":"silent","version":"1.0.0"}'
plugin 'unversioned@f6-market' '{"name":"unversioned"}'
plugin 'dropped@f6-market'     '{"name":"dropped","version":"1.0.0"}'
plugin 'orphan@f6-gone'        '{"name":"orphan","version":"1.0.0"}'
write skills f6-skill SKILL.md '---
name: f6-skill
description: a skill with no version
---
'
# A second marketplace that IS a git checkout, so `refreshable` is asserted in both states.
market f6-cloned '{"name":"f6-cloned","plugins":[]}'
mkdir -p "$STORE/marketplaces/f6-cloned/.git"

printf '{"mcpServers":{}}' >"$HOME_DIR/servers.json"

MCP_ROUTER_HOME="$HOME_DIR" node "$DIST/index.js" serve --port "$PORT" >"$HOME_DIR/serve.out" 2>&1 &
ROUTER_PID=$!

health=""
for _ in $(seq 1 50); do
  if curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then health=ok; break; fi
  kill -0 "$ROUTER_PID" 2>/dev/null || break
  sleep 0.2
done
if [ "$health" != "ok" ]; then
  echo "environment: the Swift daemon never answered /health on :$PORT — its output:"
  sed -n '1,40p' "$HOME_DIR/serve.out"
  exit 2
fi

TOKEN="$(cat "$HOME_DIR/control.token" 2>/dev/null || echo '')"
[ -n "$TOKEN" ] || { echo "environment: the daemon minted no control token at $HOME_DIR/control.token"; exit 2; }

TIMEOUT=5

check() { # label method target want-status want-substring(or "-") [--no-token]
  local label="$1" method="$2" target="$3" want_status="$4" want_body="$5" no_token="${6:-}"

  if ! kill -0 "$ROUTER_PID" 2>/dev/null; then
    echo "environment: the daemon exited before \"$label\" — its output:"
    sed -n '1,40p' "$HOME_DIR/serve.out"
    exit 2
  fi

  local -a args=(-sS -m "$TIMEOUT" -o "$HOME_DIR/body" -w '%{http_code}' -X "$method"
                 "http://127.0.0.1:$PORT$target" -H 'content-type: application/json')
  [ -z "$no_token" ] && args+=(-H "x-mcpr-token: $TOKEN")

  local status; status="$(curl "${args[@]}" 2>/dev/null || echo 000)"
  local body; body="$(cat "$HOME_DIR/body")"

  if [ "$status" = "000" ]; then
    echo "environment: curl could not reach the daemon for \"$label\""
    exit 2
  fi

  if [ "$status" = "$want_status" ] && { [ "$want_body" = "-" ] || case "$body" in *"$want_body"*) true ;; *) false ;; esac; }; then
    printf '  ok   %-62s %s\n' "$label" "$status"
    pass=$((pass + 1))
  else
    printf '  FAIL %-62s got %s (wanted %s)\n' "$label" "$status" "$want_status"
    [ "$want_body" != "-" ] && printf '       body: %s\n       want to contain: %s\n' "$body" "$want_body"
    fail=$((fail + 1)); failures+=("$label")
  fi
}

absent() { # label substring — the reply must NOT contain it
  local label="$1" needle="$2"
  local body; body="$(cat "$HOME_DIR/body")"
  case "$body" in
    *"$needle"*) printf '  FAIL %-62s the reply contained %s\n' "$label" "$needle"
                 fail=$((fail + 1)); failures+=("$label") ;;
    *)           printf '  ok   %-62s absent\n' "$label"; pass=$((pass + 1)) ;;
  esac
}

count_store_files() { find "$STORE" -type f | wc -l | tr -d ' '; }

echo "F6 — /extensions/updates on the daemon's own socket, home $HOME_DIR"
echo
echo "the route is wired at all — the missing-dependency class"
check "GET /extensions/updates answers"        GET "/extensions/updates" 200 '"summary"'
check "and it is NOT read as a kind named updates" GET "/extensions/updates" 200 '"checkedAtMs"'
absent "no 'unknown kind' reply reached the caller" 'no extension kind named'
check "an unknown kind is still refused"       GET "/extensions/nonsense" 404 'no extension kind named'
# Ported extension routes require the control token for reads as well as writes.
check "an untokened update read is refused" GET "/extensions/updates" 401 '"error"' --no-token

echo
echo "all eight verdicts, driven against the fixture the real machine cannot produce"
check "an offered newer version is an update"  GET "/extensions/updates" 200 '"name":"behind@f6-market","catalogue":"f6-market","state":"update-available"'
check "equal versions are current"             GET "/extensions/updates" 200 '"name":"level@f6-market","catalogue":"f6-market","state":"current"'
check "an OLDER offer is the catalogue behind" GET "/extensions/updates" 200 '"name":"ahead@f6-market","catalogue":"f6-market","state":"catalogue-behind"'
check "two SHAs are unorderable"               GET "/extensions/updates" 200 '"name":"sha@f6-market","catalogue":"f6-market","state":"unorderable"'
check "a versionless offer is not current"     GET "/extensions/updates" 200 '"name":"silent@f6-market","catalogue":"f6-market","state":"catalogue-declares-no-version"'
check "a versionless install is not compared"  GET "/extensions/updates" 200 '"name":"unversioned@f6-market","catalogue":"f6-market","state":"installed-declares-no-version"'
check "a dropped plugin says so"               GET "/extensions/updates" 200 '"name":"dropped@f6-market","catalogue":"f6-market","state":"not-offered"'
check "a missing marketplace says so"          GET "/extensions/updates" 200 '"name":"orphan@f6-gone","catalogue":"f6-gone","state":"no-catalogue"'

echo
echo "the counts distinguish a reading from a silence"
check "exactly one update over the fixture"    GET "/extensions/updates" 200 '"updatesAvailable":1'
check "four rows were actually compared"       GET "/extensions/updates" 200 '"compared":4'
check "and the other seven could not be"       GET "/extensions/updates" 200 '"uncomparable":7'
check "and the two sum to the total"           GET "/extensions/updates" 200 '"total":11'
check "the catalogue reports its versionless offers" GET "/extensions/updates" 200 '"declaredNoVersion":1'

echo
echo "the evidence carries its own age and provenance"
check "a git checkout is refreshable"          GET "/extensions/updates" 200 '"name":"f6-cloned"'
check "a plain directory is not"               GET "/extensions/updates" 200 '"refreshable":false'
check "a catalogue that is not there has a NULL age" GET "/extensions/updates" 200 '"name":"f6-gone","path":'
absent "and never a zero one"                  '"ageMs":0,'
check "the default window is one day"          GET "/extensions/updates" 200 '"staleAfterMs":86400000'
check "an unreadable window is refused, not defaulted" GET "/extensions/updates?staleAfterMs=1h" 400 'staleAfterMs'

echo
echo "read-only by construction — there is no other verb"
before="$(count_store_files)"
check "POST is 405"    POST   "/extensions/updates" 405 '-'
check "PUT is 405"     PUT    "/extensions/updates" 405 '-'
check "PATCH is 405"   PATCH  "/extensions/updates" 405 '-'
check "DELETE is 405"  DELETE "/extensions/updates" 405 '-'
after="$(count_store_files)"
if [ "$before" = "$after" ]; then
  printf '  ok   %-62s %s files\n' "the store is byte-for-byte the same size after all four" "$after"
  pass=$((pass + 1))
else
  printf '  FAIL %-62s %s -> %s\n' "the store changed under a read-only route" "$before" "$after"
  fail=$((fail + 1)); failures+=("store changed")
fi

echo
echo "the reading is of the disk, not of a cache"
printf '%s' '{"name":"f6-market","plugins":[{"name":"level","version":"9.9.9"}]}' \
  >"$STORE/marketplaces/f6-market/.claude-plugin/marketplace.json"
check "an edit made behind the router changes the next reply" GET "/extensions/updates" 200 \
  '"name":"level@f6-market","catalogue":"f6-market","state":"update-available"'
check "and the rows it dropped become not-offered" GET "/extensions/updates" 200 \
  '"name":"behind@f6-market","catalogue":"f6-market","state":"not-offered"'

echo
echo "nothing outside the scratch home was read or written"
real_after="$(ls -1 "$REAL_CLAUDE" 2>/dev/null | wc -l | tr -d ' ')"
if [ "$real_before" = "$real_after" ]; then
  printf '  ok   %-62s %s entries\n' "the operator's own ~/.claude marketplaces are unchanged" "$real_after"
  pass=$((pass + 1))
else
  printf '  FAIL %-62s %s -> %s\n' "the real ~/.claude was touched" "$real_before" "$real_after"
  fail=$((fail + 1)); failures+=("real tree touched")
fi
# A control on the control: a lane that reached the real tree and found it identical would print
# the same line. This proves the fixture, not the real tree, is what the route read.
case "$(cat "$HOME_DIR/body")" in
  *"$HOME_DIR"*) printf '  ok   %-62s scratch\n' "every catalogue path in the reply is under the scratch home"
                 pass=$((pass + 1)) ;;
  *)             printf '  FAIL %-62s no scratch path in the reply\n' "the route read something other than the fixture"
                 fail=$((fail + 1)); failures+=("read outside the fixture") ;;
esac

echo
echo "F6: $pass ok, $fail failed"
if [ "$fail" -ne 0 ]; then
  printf '  - %s\n' "${failures[@]}"
  exit 1
fi
exit 0
