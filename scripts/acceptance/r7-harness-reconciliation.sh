#!/usr/bin/env bash
#
# R7 — a fixture harness config carrying three duplicates is reported as three, and zero after
# reconciliation. `planning/specs/spec-R7.md` A3 and A8.
#
# It never reads and never writes the developer's own harness configs. HOME points at a scratch
# directory for the whole run, both fixtures are written by this script, and the verb under test
# opens every file read-only. The one thing this lane must not do is the one thing the item itself
# refuses to do — see spec §7.
#
# Three passes, and the third is the one that makes the first two mean anything:
#   green->zero  three duplicates reported as three, then the same file with them removed as zero
#   arming       the router's own upstream set emptied, three duplicates still declared: a detector
#                that answers "3" from the harness file alone reports three here and fails, because
#                a duplicate is a RELATION between two files and cannot be counted from one
#   httpUrl      the same harness wired on Gemini's OWN key rather than `url`. A reader keying on
#                `url` alone reports this file `not-wired` and then offers to wire it — the tool
#                telling the user to create the state it cannot read
#   unreadable   a config that could not be parsed. The human output says so and suppresses the
#                plan; the JSON must be able to say so too, or this lane — which asserts on JSON
#                only — cannot tell a broken file from a clean unwired one
#   which file    BOTH Gemini config files present and disagreeing, which is the state the machine
#                 this was measured on is actually in. `agy` reads `config/mcp_config.json`; the
#                 stale `settings.json` beside it says stdio shim where the live one says HTTP
#   pre-migration only `settings.json`, because a straight path swap breaks that install
#   serverUrl    the key `agy` writes, as opposed to the struct tag pass 1 taught the reader
#   evidence     an entry that merely mentions the router's address — a `curl` at `/health`, an
#                 endpoint key at `/health`, a stdio server carrying a stale url — is not a route
#   two spellings an entry declaring two different endpoints is reported rather than resolved by
#                 precedence, in both directions, while two that agree are one endpoint
#
# Exit codes: 0 pass, 1 a wrong answer, 2 the environment could not run the lane.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d -t r7-harness)"
SWIFT_BIN="${MCPR_ROUTER_BINARY:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
PORT=8879
FAILURES=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

[ -x "$SWIFT_BIN" ] || {
  echo "environment: no router binary at $SWIFT_BIN."
  echo "             Run (cd app && swift build --product MCPRouterCLI)."
  echo "             A skipped lane is recorded as blocked, not as a pass."; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "environment: python3 is not installed"; exit 2; }

SCRATCH_HOME="$WORK/home"
mkdir -p "$SCRATCH_HOME/.gemini/config" "$SCRATCH_HOME/.claude/mcp-router"

# The router's own upstream set. Three stdio servers, one of which the fixture harness will declare
# under a DIFFERENT name — so a name-only comparison cannot reach three and the lane would go red.
write_router_config() {
  local servers="$1"
  cat > "$SCRATCH_HOME/.claude/mcp-router/servers.json" <<JSON
{ "port": $PORT, "host": "127.0.0.1", "idleMs": 300000, "mcpServers": $servers }
JSON
}

FULL_UPSTREAMS='{
    "obscura":       { "command": "/usr/bin/obscura", "args": ["mcp"] },
    "dossier":       { "command": "npx", "args": ["-y", "dossier-research-mcp@latest"] },
    "ref-tools-mcp": { "command": "npx", "args": ["-y", "ref-tools-mcp@3.0.3"] },
    "mobbin":        { "type": "http", "url": "https://api.mobbin.com/mcp" }
  }'

# The harness. It is wired through an mcp-remote stdio shim, exactly as the measured one is, and it
# declares four servers besides: three the router already fronts (one of them RENAMED, so the
# identity basis has to find it) and one it does not.
write_harness() {
  local duplicates="$1"
  cat > "$SCRATCH_HOME/.gemini/settings.json" <<JSON
{
  "mcpServers": {
    "router":  { "command": "npx", "args": ["-y", "mcp-remote", "http://127.0.0.1:$PORT/mcp"] },
    "github":  { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"] }$duplicates
  }
}
JSON
}

# The same harness, wired on Gemini's own key. `agy` 1.1.17's MCP-server config struct carries
# `json:"httpUrl"` — spec §1.2 — so this is the shape a Gemini config that is wired DIRECTLY takes,
# and it is the shape the reader could not see.
write_harness_http_url() {
  local duplicates="$1"
  cat > "$SCRATCH_HOME/.gemini/settings.json" <<JSON
{
  "mcpServers": {
    "router":  { "httpUrl": "http://127.0.0.1:$PORT/mcp" },
    "github":  { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"] }$duplicates
  }
}
JSON
}

# The file `agy` 1.1.17 actually reads. Its MCP configuration moved out of `settings.json` and
# into `config/mcp_config.json`, and the key it writes there is `serverUrl` — its help text names
# "serverUrl (string, required)" and its error string is `MCP server %q must have either command or
# serverUrl`. On the machine this item was measured on both files exist and disagree.
write_migrated() {
  local duplicates="$1" router="$2"
  cat > "$SCRATCH_HOME/.gemini/config/mcp_config.json" <<JSON
{
  "mcpServers": {
    "router":  $router,
    "github":  { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"] }$duplicates
  }
}
JSON
}

remove_migrated() { rm -f "$SCRATCH_HOME/.gemini/config/mcp_config.json"; }

# One arbitrary Gemini entry, whatever the file. Used where a pass is about the READING rule rather
# than about the comparison, so the fixture is as small as the question.
write_gemini_entries() {
  cat > "$SCRATCH_HOME/.gemini/config/mcp_config.json" <<JSON
{ "mcpServers": $1 }
JSON
}

THREE_DUPLICATES=',
    "obscura": { "command": "/usr/bin/obscura", "args": ["mcp"] },
    "dossier": { "command": "npx", "args": ["-y", "dossier-research-mcp@latest"] },
    "Ref":     { "command": "npx", "args": ["-y", "ref-tools-mcp@3.0.3"] }'

# Pass 4 adds a fourth, and it is the one that proves the widening reaches the COMPARISON and not
# only the route: `Mobbin` declares its endpoint under Gemini's key, under a name the router does
# not use, so only a canonicalised identity digest can match it to the router's `mobbin`.
FOUR_DUPLICATES="$THREE_DUPLICATES,
    \"Mobbin\":  { \"httpUrl\": \"https://api.mobbin.com/mcp\" }"

# Read one field out of the verb's own JSON. The lane asserts on the shipped output rather than on
# a re-implementation of the comparison, which is the difference between measuring the product and
# measuring a copy of it.
probe() {
  HOME="$SCRATCH_HOME" MCP_ROUTER_HOME="$SCRATCH_HOME/.claude/mcp-router" \
    "$SWIFT_BIN" harnesses --json --port "$PORT" 2>"$WORK/stderr.txt"
}

# The same run without --json. Two of the checks below are about what a PERSON is told, and the
# `+ add` line is the one the httpUrl defect produced: a harness that is already wired, offered a
# plan to wire it.
text_probe() {
  HOME="$SCRATCH_HOME" MCP_ROUTER_HOME="$SCRATCH_HOME/.claude/mcp-router" \
    "$SWIFT_BIN" harnesses --port "$PORT" 2>"$WORK/stderr.txt"
}

# One harness's plan block: its header, then the indented lines under it. Bounded by the next
# unindented line rather than by the block's own footer — a block whose footer went missing would
# otherwise swallow every harness after it, and the check that reads this would pass by counting
# something from somewhere else.
gemini_plan() {
  awk '/^Gemini CLI — /{f=1; print; next} f && /^[^[:space:]]/{f=0} f{print}'
}

# Every harness fixture this lane wrote, digested. The verb opens configs read-only, and the way to
# assert that is to compare the bytes rather than to grep for a token that a rewrite could preserve.
fixture_digest() {
  find "$SCRATCH_HOME" -type f -name '*.json' -o -type f -name '*.toml' \
    | sort | xargs shasum -a 256 2>/dev/null | shasum -a 256
}

field() {
  python3 -c '
import json, sys
doc = json.load(sys.stdin)
row = next(h for h in doc["harnesses"] if h["harness"] == "geminiCLI")
key = sys.argv[1]
if key not in row:
    # A missing key is the F2 defect returning, not an absent value. Said out loud so that
    # dropping the member from the encoder fails loudly rather than reading as null.
    print("MISSING")
elif row[key] is None:
    print("null")
elif key == "duplicates":
    print(",".join(d["harnessName"] for d in row[key]))
elif key == "unparsed":
    print(";".join(row[key]))
else:
    print(row[key])
' "$1"
}

# The `basis` recorded against one duplicate, by harness name.
basis_of() {
  python3 -c '
import json, sys
doc = json.load(sys.stdin)
row = next(h for h in doc["harnesses"] if h["harness"] == "geminiCLI")
match = [d for d in row["duplicates"] if d["harnessName"] == sys.argv[1]]
print(match[0]["basis"] if match else "ABSENT")
' "$1"
}

check() {
  local what="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ok    $what = $actual"
  else
    echo "  FAIL  $what: expected $expected, got $actual"
    FAILURES=$((FAILURES + 1))
  fi
}

# ---------------------------------------------------------------- pass 1: three
echo "r7: a fixture harness carrying three duplicates"
write_router_config "$FULL_UPSTREAMS"
write_harness "$THREE_DUPLICATES"
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "duplicateCount"    3                       "$(printf '%s' "$OUT" | field duplicateCount)"
check "the names"         "obscura,dossier,Ref"   "$(printf '%s' "$OUT" | field duplicates)"
check "state"             wired-with-duplicates   "$(printf '%s' "$OUT" | field state)"
check "route"             stdio-shim              "$(printf '%s' "$OUT" | field route)"

# ---------------------------------------------------------------- pass 2: zero
echo "r7: the same harness after reconciliation"
write_harness ""
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "duplicateCount"    0                       "$(printf '%s' "$OUT" | field duplicateCount)"
check "the names"         ""                      "$(printf '%s' "$OUT" | field duplicates)"
check "state"             wired-shim              "$(printf '%s' "$OUT" | field state)"
check "route unchanged"   stdio-shim              "$(printf '%s' "$OUT" | field route)"

# ---------------------------------------------------------------- pass 3: arming
# Same three harness entries, an empty router. A duplicate is a relation between two files, so the
# only correct answer is zero. A detector that counts the harness's own entries answers three and
# this pass turns red — which is what stops the two passes above from being a pair of numbers that
# happen to agree with the fixture that produced them.
echo "r7: arming — the same three entries against a router that fronts nothing"
write_router_config '{}'
write_harness "$THREE_DUPLICATES"
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "duplicateCount"    0                       "$(printf '%s' "$OUT" | field duplicateCount)"
check "state"             wired-shim              "$(printf '%s' "$OUT" | field state)"

# ---------------------------------------------------------------- the boundary
# A digest of every fixture, not a grep for one entry name. `D-r7-j`: the old check looked for the
# literal `"Ref"`, so any rewrite that happened to preserve that one token passed — which is the
# same class of vacuity this lane's arming pass exists to refuse, in the lane's own assertion.
echo "r7: the harness fixtures were not modified by the run"
write_harness "$THREE_DUPLICATES"
BOUNDARY_BEFORE="$(fixture_digest)"
probe > /dev/null 2>&1
text_probe > /dev/null 2>&1
check "byte-identical after a json probe and a text probe" \
      "$BOUNDARY_BEFORE" "$(fixture_digest)"

# ---------------------------------------------------------------- pass 4: Gemini's own key
# `HarnessRoute.detect` read `url` and nothing else, so `.directHTTP` was unreachable for the one
# harness this item exists for. The measured symptom was worse than a missed state: the block named
# `json:"httpUrl"` as its evidence and three lines later failed to read an httpUrl entry, reported
# `not wired`, and printed a plan offering to add a router entry to an already-routed harness.
echo "r7: the same harness wired on Gemini's own httpUrl key"
write_router_config "$FULL_UPSTREAMS"
write_harness_http_url "$FOUR_DUPLICATES"
BEFORE="$(fixture_digest)"
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "route"             http                    "$(printf '%s' "$OUT" | field route)"
check "state"             wired-with-duplicates   "$(printf '%s' "$OUT" | field state)"
check "duplicateCount"    4                       "$(printf '%s' "$OUT" | field duplicateCount)"
check "the names"  "obscura,dossier,Ref,Mobbin"   "$(printf '%s' "$OUT" | field duplicates)"
check "the httpUrl duplicate was matched on identity, not on name" \
      identity "$(printf '%s' "$OUT" | basis_of Mobbin)"

TEXT="$(text_probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
PLAN="$(printf '%s' "$TEXT" | gemini_plan)"
check "the plan is printed at all" 1 "$(printf '%s' "$PLAN" | grep -c 'nothing applies this plan')"
check "no + add line for a harness that is already wired" \
      0 "$(printf '%s' "$PLAN" | grep -c '+ add')"
check "the duplicates are still offered for removal" \
      4 "$(printf '%s' "$PLAN" | grep -c -- '- remove')"
check "the headline" 1 \
      "$(printf '%s' "$TEXT" | grep -c 'wired via HTTP, and carrying 4 duplicate direct upstream(s)')"
check "every harness fixture is byte-identical after two probes" "$BEFORE" "$(fixture_digest)"

# ---------------------------------------------------------------- pass 5: could not be read
# An unreadable config arrives at the encoder as an empty report, so `state` reads `not-wired` and
# `duplicateCount` reads 0 — byte-identical to a clean unwired harness. The human output draws the
# distinction; the wire could not, and this lane asserts on the wire, so neither could the lane.
# That is the distinction R7 itself says cost a wrong answer against `~/.grok/config.toml`.
echo "r7: a config that could not be read says so on the wire, not only on the screen"
write_harness_http_url "$THREE_DUPLICATES"
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "a readable config carries no reason" null "$(printf '%s' "$OUT" | field unreadable)"

printf '%s\n' '{ "mcpServers": { "router": { "httpUrl": ' > "$SCRATCH_HOME/.gemini/settings.json"
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
UNREADABLE="$(printf '%s' "$OUT" | field unreadable)"
if [ "$UNREADABLE" = "null" ] || [ "$UNREADABLE" = "MISSING" ] || [ -z "$UNREADABLE" ]; then
  echo "  FAIL  unreadable: the JSON cannot say the file could not be read (got \"$UNREADABLE\")"
  FAILURES=$((FAILURES + 1))
else
  echo "  ok    unreadable = $UNREADABLE"
fi
check "exists"            True                    "$(printf '%s' "$OUT" | field exists)"

# The rest of the row is the empty report, and this is what makes the field load-bearing rather
# than decorative: a consumer switching on `state` alone reads a clean unwired harness here.
check "state is the empty report"      not-wired  "$(printf '%s' "$OUT" | field state)"
check "duplicateCount is the empty report"     0  "$(printf '%s' "$OUT" | field duplicateCount)"
check "entries is the empty report"            0  "$(printf '%s' "$OUT" | field entries)"

TEXT="$(text_probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
# Binding the wire to the screen, rather than guessing what a real reason looks like: the same
# sentence has to appear in both, so a field hard-coded to any plausible string fails here.
check "the screen carries the same reason the wire does" \
      1 "$(printf '%s' "$TEXT" | grep -cF "could not be read: $UNREADABLE")"
check "and the harness is offered no plan at all" \
      0 "$(printf '%s' "$TEXT" | gemini_plan | grep -c .)"

# ---------------------------------------------------------------- pass 6: the file agy reads
# **The route neither pass had an assertion for, and it is this machine's live state**: both Gemini
# config files present, disagreeing about the transport, the entry count and two of the servers.
# The first gap-fix added `httpUrl` to the key list — a route — while R7 went on reading a file the
# harness had stopped reading, which is the property. Reported here: the migrated file wins, and
# with it the transport, the count, and the plan.
echo "r7: both Gemini config files present and disagreeing — the one agy reads wins"
write_router_config "$FULL_UPSTREAMS"
write_harness "$THREE_DUPLICATES"
write_migrated "$THREE_DUPLICATES" '{ "serverUrl": "http://127.0.0.1:'"$PORT"'/mcp" }'
BEFORE="$(fixture_digest)"
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "the path read"     "$SCRATCH_HOME/.gemini/config/mcp_config.json" \
                          "$(printf '%s' "$OUT" | field path)"
check "route"             http                    "$(printf '%s' "$OUT" | field route)"
check "state"             wired-with-duplicates   "$(printf '%s' "$OUT" | field state)"
check "duplicateCount"    3                       "$(printf '%s' "$OUT" | field duplicateCount)"

TEXT="$(text_probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
PLAN="$(printf '%s' "$TEXT" | gemini_plan)"
check "no shim replacement is proposed for a migration already performed" \
      0 "$(printf '%s' "$PLAN" | grep -c -- '~ replace')"
check "and no + add line either" 0 "$(printf '%s' "$PLAN" | grep -c -- '+ add')"
check "the stale file is not the one named in the plan" \
      0 "$(printf '%s' "$PLAN" | grep -c 'settings.json')"
check "every harness fixture is byte-identical after two probes" "$BEFORE" "$(fixture_digest)"

# ---------------------------------------------------------------- pass 7: a pre-migration install
# A straight path swap answers this machine and breaks the install one release behind it, which is
# the same wrong answer with a different date on it.
echo "r7: only settings.json present — a pre-migration install is still read"
remove_migrated
write_harness "$THREE_DUPLICATES"
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "the path read"     "$SCRATCH_HOME/.gemini/settings.json" \
                          "$(printf '%s' "$OUT" | field path)"
check "route"             stdio-shim              "$(printf '%s' "$OUT" | field route)"
check "duplicateCount"    3                       "$(printf '%s' "$OUT" | field duplicateCount)"

# ---------------------------------------------------------------- pass 8: Gemini's written key
# `serverUrl` is the spelling in `~/.gemini/config/mcp_config.json` on this machine, six times over,
# and the router's own entry is one of them. `httpUrl` — pass 1's widening — is a struct tag that
# appears in that file zero times.
echo "r7: the harness wired on serverUrl, the key agy writes"
write_migrated "$FOUR_DUPLICATES" '{ "serverUrl": "http://127.0.0.1:'"$PORT"'/mcp" }'
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "route"             http                    "$(printf '%s' "$OUT" | field route)"
check "state"             wired-with-duplicates   "$(printf '%s' "$OUT" | field state)"
check "duplicateCount"    4                       "$(printf '%s' "$OUT" | field duplicateCount)"
check "the names"  "obscura,dossier,Ref,Mobbin"   "$(printf '%s' "$OUT" | field duplicates)"
TEXT="$(text_probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "the headline" 1 \
      "$(printf '%s' "$TEXT" | grep -c 'wired via HTTP, and carrying 4 duplicate direct upstream(s)')"

# ---------------------------------------------------------------- pass 9: what counts as a route
# A harness that is not routed must not read routed. Two shapes, and the second is the one nobody
# named: B3 was filed on the shim axis, where a `curl` at `/health` made the whole harness read
# `wired via a stdio shim`; the identical evidence rule was wrong one axis along, where a plain
# endpoint key at `/health` read `wired via HTTP`. Both come from comparing host and port and never
# asking what the URL pointed at.
echo "r7: an entry that merely mentions the router's address is not a route"
write_router_config "$FULL_UPSTREAMS"
write_gemini_entries '{ "health": { "command": "curl", "args": ["-s", "http://127.0.0.1:'"$PORT"'/health"] } }'
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "a health-check curl leaves the harness not wired" \
      not-wired "$(printf '%s' "$OUT" | field state)"
check "and the entry stays in the count"  1  "$(printf '%s' "$OUT" | field entries)"

write_gemini_entries '{ "probe": { "url": "http://127.0.0.1:'"$PORT"'/health" } }'
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "an endpoint key at a non-MCP path is not a route either" \
      none "$(printf '%s' "$OUT" | field route)"

write_gemini_entries '{ "fs": { "command": "npx", "args": ["-y", "fs-mcp"], "url": "http://127.0.0.1:'"$PORT"'/mcp" } }'
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "a stdio server carrying a stale url is not wired over HTTP" \
      none "$(printf '%s' "$OUT" | field route)"

# The other direction, in the same pass, because a path rule that refused the real endpoint would
# be a worse defect than the one it replaced.
write_gemini_entries '{ "router": { "serverUrl": "http://127.0.0.1:'"$PORT"'/mcp" } }'
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "the MCP endpoint itself is still a route" http "$(printf '%s' "$OUT" | field route)"

# ---------------------------------------------------------------- pass 10: two spellings, one entry
# A decoy `url` beside a real endpoint returned before canonicalising, so the entry was neither
# counted as a duplicate nor reported unreadable — the silent zero spec §4 forbids in those words.
echo "r7: an entry whose two spellings disagree is reported, never silently zero"
write_gemini_entries '{
    "router": { "serverUrl": "http://127.0.0.1:'"$PORT"'/mcp" },
    "Mobbin": { "serverUrl": "https://api.mobbin.com/mcp" }
  }'
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "the control: one spelling, and it is a duplicate" 1 "$(printf '%s' "$OUT" | field duplicateCount)"

write_gemini_entries '{
    "router": { "serverUrl": "http://127.0.0.1:'"$PORT"'/mcp" },
    "Mobbin": { "serverUrl": "https://api.mobbin.com/mcp", "url": "https://decoy.example/mcp" }
  }'
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "the decoy does not erase it silently" 0 "$(printf '%s' "$OUT" | field duplicateCount)"
UNPARSED="$(printf '%s' "$OUT" | field unparsed)"
if [ -z "$UNPARSED" ] || [ "$UNPARSED" = "MISSING" ] || [ "$UNPARSED" = "[]" ]; then
  echo "  FAIL  unparsed: a decoy erased a duplicate and nothing was reported (got \"$UNPARSED\")"
  FAILURES=$((FAILURES + 1))
else
  echo "  ok    unparsed = $UNPARSED"
fi

# Neither direction is resolved by precedence, and agreement is not a disagreement.
write_gemini_entries '{
    "router": { "serverUrl": "http://127.0.0.1:'"$PORT"'/mcp" },
    "Mobbin": { "url": "https://api.mobbin.com/mcp", "httpUrl": "https://decoy.example/mcp" }
  }'
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "the decoy in the other direction is refused too" 0 "$(printf '%s' "$OUT" | field duplicateCount)"

write_gemini_entries '{
    "router": { "serverUrl": "http://127.0.0.1:'"$PORT"'/mcp" },
    "Mobbin": { "url": "https://api.mobbin.com/mcp", "serverUrl": "https://api.mobbin.com/mcp" }
  }'
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "two spellings that agree are one endpoint" 1 "$(printf '%s' "$OUT" | field duplicateCount)"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "r7-harness-reconciliation: pass"
  exit 0
fi
echo "r7-harness-reconciliation: $FAILURES failing check(s)"
exit 1
