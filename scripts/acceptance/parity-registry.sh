#!/usr/bin/env bash
#
# P3 — the registry lane.
#
# `GET /registry/search` is the one control route that leaves the machine, and it has never been
# compared. The manifest blocked it on `D-m` with a true reason — "the reference calls live
# registries; two runs a second apart return different bodies" — and that reason hid a second,
# worse one.
#
# MEASURED ON MAIN AT 7babd97, BOTH BINARIES ON SCRATCH HOMES, THE SAME REQUEST AT EACH:
#     swift     → HTTP 502  {"error":"registry search is unavailable: no HTTP client is configured"}
#     reference → HTTP 200  {"results":[…]}
# `RouterServiceDispatch` built the daemon's `ControlDeps` with no `registry:`, and no production
# type conformed to `HTTPFetching` anywhere in app/Sources — every conformance was in a test
# target. The merge, the dedupe, the limit coercion and the ranking were all implemented, unit
# tested, and unreachable in the process that ships. A row blocked for an oracle reason reads as
# "probably fine, unmeasurable", which is why this was worth finding.
#
# THE ORACLE. Both implementations resolve their two indexes from an environment variable
# (`src/registry.ts:18-19`; `RegistryDeps.officialBase`/`.smitheryBase`). This lane points both at
# `scripts/fixtures/registry-fixture-server.mjs`, so both read identical upstream bytes and any
# difference in the response is the port's.
#
# GITHUB IS THE THIRD LIVE DEPENDENCY AND IS PINNED RATHER THAN AVOIDED. `enrichWithStars` calls
# api.github.com for every entry with a github.com repository, and that host is HARD-CODED in the
# reference — there is no env seam for it. Serving no github repositories would make the route
# deterministic and would also switch off `repoKey` dedupe, which is how one server in both indexes
# becomes one `source:"both"` row — the most interesting behaviour here. So instead both scratch
# homes are seeded with an in-TTL `github-cache.json`: both implementations read a day-old cache
# before fetching (src/registry.ts:235; RegistrySearch.swift:225), so the entries are cache hits,
# no request is issued, and the dedupe, the star enrichment and the useCount→stars→updatedAt
# ranking all stay inside the comparison. The seeded star count is asserted in the response, which
# is the egress guard: a router that really called GitHub would carry that project's real numbers.
#
# NOTHING IS NORMALISED, and that is an assertion rather than an omission. The corpus is fixed, the
# stars come from a file, no timestamp is minted by this route and no body carries a port. The
# bodies are compared as raw bytes. A body that needed normalising would be telling us something.
#
# ROWS THIS LANE OWNS. It writes results for this id and no other.
#   control: control-registry-search
#
# Exit codes: 0 every scenario agreed, 1 a mismatch, 2 the environment could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TS_PORT="${REGISTRY_TS_PORT:-8957}"
SWIFT_PORT="${REGISTRY_SWIFT_PORT:-8958}"
FIXTURE_PORT="${REGISTRY_FIXTURE_PORT:-8959}"
# The empty-base scenario restarts both routers, because both read the registry bases once at
# construction. Fresh ports rather than the same two, so a socket still in TIME_WAIT cannot make
# that scenario look like a router that would not start.
TS_PORT2="${REGISTRY_TS_PORT2:-8960}"
SWIFT_PORT2="${REGISTRY_SWIFT_PORT2:-8961}"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
WORK="$(mktemp -d -t parity-registry)"
RESULTS="${PARITY_RESULTS:-}"
TS_PID=""
SWIFT_PID=""
FIXTURE_PID=""

MAIN_PID=$$
cleanup() {
  [ "$BASHPID" != "$MAIN_PID" ] && return 0
  for pid in "$TS_PID" "$SWIFT_PID" "$FIXTURE_PID"; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

OWNED="control/control-registry-search"

# HOW MANY SCENARIOS MUST RUN BEFORE THIS LANE MAY SPEAK FOR ITS ROW. Keep in step with the
# `compare`/`verdict` calls below; the count is asserted, not decorative.
EXPECTED_SCENARIOS=12

# RESULTS ARE BUFFERED AND FLUSHED ONCE, AT THE END, AND THE REASON IS A HOLE THIS LANE HAD.
#
# The first form of this script appended each scenario's verdict to `$PARITY_RESULTS` as it went.
# `parity-gate.sh` scores a row `proven` when it sees any `ok` and no `fail` (its reconciliation
# loop), so a lane that recorded six `ok`s and then died — a fixture restart that failed, a kill, a
# port grabbed by something else — left the row PROVEN on the strength of the six happy-path
# scenarios, with the 503 and unreachable paths never run. Worse, the gate then printed its
# env-failure banner saying "those rows were counted blocked rather than proven", which by then was
# false: reconciliation had already counted them.
#
# That is precisely the failure this item exists to refuse — a green row whose interesting half was
# not compared — and it was inside the lane written to refuse it.
#
# So: `verdict` writes to a buffer. Only `finish` copies the buffer into `$PARITY_RESULTS`, and
# only after asserting every scenario ran. Every `exit 2` environment path below flushes NOTHING,
# which makes the gate say "(no lane reported)" and count the row blocked — the honest answer for a
# lane that did not finish. The EXIT trap deliberately does not flush; a trap that did would put
# the hole straight back.
PENDING="$WORK/pending.tsv"
: > "$PENDING"

record() { # group id ok|fail detail
  case " $(echo $OWNED) " in
    *" $1/$2 "*) ;;
    *) echo "  LANE BUG: refusing to record $1/$2, which this lane does not own" >&2; return 1 ;;
  esac
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$PENDING"
}

pass=0; fail=0
verdict() { # ok? message
  if [ "$1" = 1 ]; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$2"; record control control-registry-search ok "$2"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n' "$2"; record control control-registry-search fail "$2"
  fi
}

# The only path that may speak for the row. Called on a completed run, whatever its verdicts.
finish() { # exit-code
  local code="${1:-0}" ran=$((pass + fail))
  if [ "$ran" -ne "$EXPECTED_SCENARIOS" ]; then
    echo
    echo "  LANE INCOMPLETE: $ran of $EXPECTED_SCENARIOS scenarios reached a verdict."
    echo "  The row is not proven by the half that ran, so this is recorded as a failure rather"
    echo "  than left as a partial pass."
    printf 'control\tcontrol-registry-search\tfail\t%s\n' \
      "only $ran of $EXPECTED_SCENARIOS scenarios ran; a partial lane does not prove this row" \
      >> "$PENDING"
    code=1
  fi
  [ -n "$RESULTS" ] && cat "$PENDING" >> "$RESULTS"
  exit "$code"
}

# --------------------------------------------------------------------------------------- environment
command -v node >/dev/null 2>&1 || { echo "environment: node is not installed"; exit 2; }
[ -f "$REPO_ROOT/dist/index.js" ] || {
  echo "environment: no built reference at dist/index.js. Run npm run build."; exit 2; }
[ -x "$SWIFT_BIN" ] || {
  echo "environment: no Swift router at ${SWIFT_BIN#"$REPO_ROOT/"}."
  echo "             Build it with: cd app && swift build"; exit 2; }
FIXTURE_SERVER="$REPO_ROOT/scripts/fixtures/registry-fixture-server.mjs"
[ -f "$FIXTURE_SERVER" ] || { echo "environment: no registry fixture at $FIXTURE_SERVER"; exit 2; }
for port in "$TS_PORT" "$SWIFT_PORT" "$FIXTURE_PORT" "$TS_PORT2" "$SWIFT_PORT2"; do
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "environment: something is already listening on :$port. This harness never shares a port"
    echo "             and never touches the router on 8975/8976."; exit 2
  fi
done

start_fixture() { # fail-mode ("" for none)
  FIXTURE_REGISTRY_FAIL="$1" node "$FIXTURE_SERVER" "$FIXTURE_PORT" >>"$WORK/fixture.log" 2>&1 &
  FIXTURE_PID=$!
  for _ in $(seq 1 40); do
    curl -fsS -m 2 "http://127.0.0.1:$FIXTURE_PORT/v0/servers" >/dev/null 2>&1 && return 0
    curl -sS -m 2 "http://127.0.0.1:$FIXTURE_PORT/v0/servers" 2>/dev/null | grep -q . && return 0
    sleep 0.25
  done
  echo "environment: the registry fixture never answered on :$FIXTURE_PORT"; return 1
}
stop_fixture() {
  [ -n "$FIXTURE_PID" ] && kill "$FIXTURE_PID" 2>/dev/null
  FIXTURE_PID=""
  sleep 0.5
}

start_fixture "" || { tail -5 "$WORK/fixture.log"; exit 2; }

# ------------------------------------------------------------------------------------- the two homes
# `Cinder` is SEEDED into servers.json rather than added over the control API, so `installed` is
# read from the upstream map both routers loaded at startup. Adding it with `POST /servers` would
# make this row depend on a control-API write reaching the live process, which is a separate open
# question (`D-v1a`) and not this row's subject.
SEED_NOW="$(node -e 'process.stdout.write(String(Date.now()))')"
for side in ts swift; do
  mkdir -p "$WORK/$side"
  cat > "$WORK/$side/servers.json" <<'JSON'
{ "mcpServers": { "Cinder": { "command": "/bin/echo", "args": ["seeded"] } } }
JSON
  # In-TTL, so both readers take the cache-hit branch and neither issues a GitHub request. The
  # star counts are deliberately not the real project's.
  cat > "$WORK/$side/github-cache.json" <<JSON
{"acme/atlas":{"stars":1520,"forks":88,"pushedAt":"2026-04-02T10:00:00Z","archived":false,"at":$SEED_NOW},
 "acme/beacon":{"stars":128,"forks":9,"pushedAt":"2026-02-12T10:00:00Z","archived":false,"at":$SEED_NOW}}
JSON
done

export MCP_ROUTER_REGISTRY="http://127.0.0.1:$FIXTURE_PORT"
export MCP_ROUTER_SMITHERY="http://127.0.0.1:$FIXTURE_PORT"
# Unset deliberately: with a token present the rate-limit warning changes text, and a developer's
# own token in the environment would make this lane's verdict depend on whose machine it ran on.
unset GITHUB_TOKEN GH_TOKEN

MCP_ROUTER_HOME="$WORK/ts" node "$REPO_ROOT/dist/index.js" serve \
  --port "$TS_PORT" --idle-ms 120000 >"$WORK/ts.log" 2>&1 &
TS_PID=$!
MCP_ROUTER_HOME="$WORK/swift" "$SWIFT_BIN" serve \
  --port "$SWIFT_PORT" --idle-ms 120000 >"$WORK/swift.log" 2>&1 &
SWIFT_PID=$!

wait_ready() { # port pid label
  for _ in $(seq 1 120); do
    curl -fsS -m 2 "http://127.0.0.1:$1/health" >/dev/null 2>&1 && return 0
    kill -0 "$2" 2>/dev/null || { echo "environment: the $3 router exited during startup"; return 1; }
    sleep 0.25
  done
  echo "environment: the $3 router never answered /health"; return 1
}
wait_ready "$TS_PORT" "$TS_PID" reference || { tail -20 "$WORK/ts.log"; exit 2; }
wait_ready "$SWIFT_PORT" "$SWIFT_PID" Swift || { tail -20 "$WORK/swift.log"; exit 2; }

echo
echo "P3 — GET /registry/search, both routers against one pinned registry on :$FIXTURE_PORT"

# ---------------------------------------------------------------------------------------- scenarios
# `require_results` distinguishes the populated scenarios from the ones whose whole subject is an
# empty or partial result. Two silent routers diff clean, and that is exactly how this row would
# come back a lie.
compare() { # label query require_results must_contain
  local label="$1" query="$2" require="$3" needle="${4:-}"
  # The STATUS is compared, not just the body. A row in the `control` group means both routers on
  # the wire, status included; comparing bodies alone would let one answer 200 and the other 502
  # with the same bytes — which is not hypothetical here, since the 502 is what this route did.
  local ts_status swift_status
  ts_status="$(curl -sS -m 30 -o "$WORK/ts.body" -w '%{http_code}' \
    "http://127.0.0.1:$TS_PORT/registry/search?$query" 2>/dev/null)"
  swift_status="$(curl -sS -m 30 -o "$WORK/swift.body" -w '%{http_code}' \
    "http://127.0.0.1:$SWIFT_PORT/registry/search?$query" 2>/dev/null)"
  if [ "$ts_status" != "$swift_status" ]; then
    verdict 0 "$label — status differs: reference $ts_status, Swift $swift_status"
    return
  fi

  for side in ts swift; do
    if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$WORK/$side.body" 2>/dev/null; then
      verdict 0 "$label — the $side body is not JSON: $(head -c 120 "$WORK/$side.body")"
      return
    fi
  done
  if [ "$require" = 1 ]; then
    for side in ts swift; do
      local count
      count="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d.get("results") or []))' "$WORK/$side.body")"
      if [ "$count" -lt 1 ]; then
        verdict 0 "$label — the $side router returned no results, so an agreement here proves nothing"
        return
      fi
    done
  fi
  if [ -n "$needle" ]; then
    # Newline-separated: a scenario whose whole subject is two warnings has to assert both.
    local one
    while IFS= read -r one; do
      [ -n "$one" ] || continue
      for side in ts swift; do
        if ! grep -q -- "$one" "$WORK/$side.body"; then
          verdict 0 "$label — the $side body does not carry $one"
          return
        fi
      done
    done <<< "$needle"
  fi

  if diff -q "$WORK/ts.body" "$WORK/swift.body" >/dev/null 2>&1; then
    verdict 1 "$label — HTTP $ts_status, $(wc -c < "$WORK/ts.body" | tr -d ' ') bytes, byte for byte, no normalisation"
  else
    echo "  --- reference vs Swift ---"
    diff <(python3 -m json.tool "$WORK/ts.body" 2>/dev/null) \
         <(python3 -m json.tool "$WORK/swift.body" 2>/dev/null) | head -20 | sed 's/^/    /'
    verdict 0 "$label — the bodies differ"
  fi
}

# ------------------------------------------------------------------------------- the shape guard
# An agreement over a body that lost its interesting parts is the failure this lane is most exposed
# to: two parsers that both returned nothing diff clean. So before any scenario is believed, the
# populated body must be shown to contain the paths the route is here to exercise — the deduped
# `source:"both"` row, both install recipes the official branch can produce, the Smithery-only row,
# and an `installed:true` that came from the seeded upstream map.
shape_guard() {
  local side port ok=1
  for side in ts swift; do
    port="$TS_PORT"; [ "$side" = swift ] && port="$SWIFT_PORT"
    curl -sS -m 30 "http://127.0.0.1:$port/registry/search?q=github&limit=10" \
      > "$WORK/$side.shape.json" 2>&1
    python3 - "$WORK/$side.shape.json" "$side" <<'PY' || ok=0
import json, sys
path, side = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(path))
except Exception as e:
    print(f"  the {side} body is not JSON ({e})"); sys.exit(1)
rows = d.get("results") or []
want = {
    'a deduped source:"both" row':        any(r.get("source") == "both" for r in rows),
    'a Smithery-only row':                any(r.get("source") == "smithery" for r in rows),
    'an official-only row':               any(r.get("source") == "official" for r in rows),
    'a stdio install (npx)':              any((r.get("install") or {}).get("command") == "npx" for r in rows),
    'a stdio install (uvx)':              any((r.get("install") or {}).get("command") == "uvx" for r in rows),
    'an sse install':                     any((r.get("install") or {}).get("type") == "sse" for r in rows),
    'an http install':                    any((r.get("install") or {}).get("type") == "http" for r in rows),
    'a requires[] entry':                 any((r.get("install") or {}).get("requires") for r in rows),
    'a row marked installed:true':        any(r.get("installed") is True for r in rows),
    'a row marked installed:false':       any(r.get("installed") is False for r in rows),
    'stars applied from the seeded cache': any(r.get("stars") == 1520 for r in rows),
    'a non-empty sources census':         (d.get("sources") or {}).get("merged", 0) > 0,
    # The owner-less repository URL. `repoKey` must find no owner/repo in
    # "https://github.com/", so the row identifies by displayName and is NEVER star-enriched.
    # A port that returned a bogus key would either collide this row with another or attach
    # stars to it, and both are visible right here.
    'the owner-less github.com row, unenriched': any(
        r.get("name") == "io.acme/ownerless" and r.get("stars") is None for r in rows),
}
bad = [k for k, present in want.items() if not present]
if bad:
    print(f"  the {side} body is missing: " + "; ".join(bad)); sys.exit(1)

# RANKING IS ASSERTED PER ROUTER, not left to the cross-port diff.
#
# Both routers could skip `useCount → stars → updatedAt` entirely, emit their merge order, and
# diff clean against each other — the ordering would never have been compared. The corpus is
# built so the ranked order is NOT the merge order: merging official-then-smithery would put
# beacon second, and only the ranking key puts smithery's cinder there.
expected = ["io.acme/atlas", "zed/cinder", "io.acme/beacon", "io.acme/relay",
            "io.acme/vault", "io.acme/ownerless", "io.probe/echoed-query",
            "probe/echoed-query-smithery"]
got = [r.get("name") for r in rows]
if got != expected:
    print(f"  the {side} router did not rank by useCount → stars → updatedAt")
    print(f"    wanted: {expected}")
    print(f"    got:    {got}")
    sys.exit(1)
print(f"  shape guard ({side}): {len(rows)} rows, every compared path present, ranked order exact")
PY
  done
  [ "$ok" = 1 ]
}

if ! shape_guard; then
  verdict 0 "a router did not produce a body carrying the paths and the ranked order this lane compares, so every agreement below would be vacuous"
  echo; echo "compared $((pass + fail)) scenarios: $pass ok, $fail failed"; finish 1
fi

# 1. The whole envelope. `"stars": 1520` is the egress guard: it is the seeded cache's number and
#    not the real project's, so a router that actually reached api.github.com fails here.
compare "?q=github&limit=3 — envelope, merge, ranking, seeded stars" \
  "q=github&limit=3" 1 '"stars":1520'

# 2. `Math.min(Number(x ?? 30) || 30, 60)` at its edges. `||` is ToBoolean so 0 and NaN both become
#    30; 60 is the cap; and a negative survives to `slice`, where it counts from the end and DROPS
#    rows. The echoed query proves what each router actually sent — JavaScript renders a limit of
#    -1 as "-1", and a port stringifying a Double would send "-1.0".
compare "?limit=0 — zero is falsy and becomes 30"    "q=github&limit=0"   1 'official received: search=github&limit=30'
compare "?limit=abc — NaN is falsy and becomes 30"   "q=github&limit=abc" 1 'official received: search=github&limit=30'
compare "?limit=-1 — a negative reaches slice"       "q=github&limit=-1"  0 'official received: search=github&limit=-1'
compare "?limit=99 — capped at 60"                   "q=github&limit=99"  1 'official received: search=github&limit=60'

# 2b. THE SLICE ITSELF, not just the forwarded limit.
#     The four scenarios above assert what each router SENT, via the fixture's echo. That leaves a
#     port free to forward the right limit and then slice locally to something else — the echo
#     matches, the corpus is small enough that the row counts often coincide, and the difference is
#     invisible. `slice(0, -1)` drops the LAST row, so a negative limit must produce a body with
#     strictly fewer results than `limit=30` does, ON EACH ROUTER, as an absolute count rather than
#     as an agreement between two routers that both ignored it.
slice_len() { # port query
  curl -sS -m 30 "http://127.0.0.1:$1/registry/search?$2" 2>/dev/null \
    | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("results") or []))' 2>/dev/null
}
slice_ok=1; slice_detail=""
for pair in "ts:$TS_PORT" "swift:$SWIFT_PORT"; do
  side="${pair%%:*}"; port="${pair##*:}"
  neg="$(slice_len "$port" 'q=github&limit=-1')"
  base="$(slice_len "$port" 'q=github&limit=30')"
  if [ -z "$neg" ] || [ -z "$base" ]; then
    slice_ok=0; slice_detail="the $side router did not return a countable results array"
  elif [ "$neg" -ge "$base" ]; then
    slice_ok=0
    slice_detail="the $side router returned $neg results for limit=-1 and $base for limit=30; a negative limit must reach slice and drop the last row"
  fi
done
if [ "$slice_ok" = 1 ]; then
  verdict 1 "a negative limit reaches slice on both routers — fewer results than limit=30, measured per router, not inferred from agreement"
else
  verdict 0 "$slice_detail"
fi

# 3. No `q` at all: `?? ''` is falsy, so neither index is given a search term.
# `limit=30` and not a small number: the echo row carries no useCount and no stars, so it ranks
# last and a tight slice drops it — which is what the first draft of this line did, and the lane
# correctly failed on a needle that had been sliced out of the body it was searching.
compare "no q — an empty query sets no search parameter" "limit=30" 1 'official received: limit=30'

# 4. One index down, BOTH WAYS. The two are different bodies and not symmetric: official-down
#    leaves the Smithery half plus `sources.official: 0`, smithery-down leaves the official half.
#    Only the smithery direction was compared at first, so a port that mishandled a 503 from the
#    official index specifically would have stayed green — the fixture could already produce it and
#    nothing asked it to.
stop_fixture
start_fixture smithery || { tail -5 "$WORK/fixture.log"; exit 2; }
compare "smithery answering 503 — the warning and the partial result" \
  "q=github&limit=5" 1 'Smithery unreachable: HTTP 503'

stop_fixture
start_fixture official || { tail -5 "$WORK/fixture.log"; exit 2; }
compare "the official index answering 503 — the other half of the same failure" \
  "q=github&limit=5" 1 'official registry unreachable: HTTP 503'

# 5. The registry gone entirely. This is the transport-failure path, and it is here because P3
#    wrote the client that produces it: URLSession's own error description is a paragraph carrying
#    the failing URL, where node's fetch says exactly "fetch failed". That string is user-visible —
#    the Discover board renders it — so it is reproduced rather than approximated.
stop_fixture
compare "the registry unreachable — both report node's own \"fetch failed\"" \
  "q=github&limit=5" 0 'official registry unreachable: fetch failed'

# ------------------------------------------------------------------------------------ egress
# TWO observables, because neither alone is sufficient and saying so is the point.
#
# The strong one is above and is in the compared body: `"stars":1520` is the seeded cache's number
# and not the real acme/atlas's, so a router that actually reached api.github.com either carries
# different numbers or (on a failure) carries none, and the shape guard fails. A cache that missed
# on both sides produces the same absence, which is why the corpus is built so the seeded stars
# also decide the ORDER of two rows.
#
# The weak one is here: no established connection off the loopback interface. It is a point-in-time
# sample and would miss a request that has already closed, which is exactly why it is the second
# check and not the first.
offlan=0
for pid in "$TS_PID" "$SWIFT_PID"; do
  # `-a` is load-bearing: lsof combines selection options with OR, so `-p PID -iTCP` without it
  # lists every TCP connection on the machine as well as everything that pid holds. The first
  # draft of this check reported the SAME three off-loopback connections for both routers, which
  # is what an OR looks like when you meant an AND.
  remote="$(lsof -nP -a -p "$pid" -iTCP -sTCP:ESTABLISHED 2>/dev/null \
            | awk 'NR>1 { print $9 }' | grep -v '127\.0\.0\.1' | head -3)"
  if [ -n "$remote" ]; then
    offlan=1
    echo "  a router holds a connection off loopback: $remote"
  fi
done
if [ "$offlan" = 1 ]; then
  verdict 0 "a router reached a host outside loopback; this lane's determinism depends on it not doing that"
else
  verdict 1 "neither router holds a connection off loopback, and the seeded star count survived into the compared body — the GitHub cache was read rather than the network"
fi

# ------------------------------------------------------------------- an EMPTY base, deliberately
# `RouterServiceDispatch` reads both bases with `??` and nothing else, and its comment calls that
# load-bearing: `process.env.X ?? default` is NULLISH, so a variable that is SET AND EMPTY survives
# to `new URL('/v0/servers', '')`, which throws, and the search reports `Invalid URL`. Filtering the
# empty string out in Swift — the natural-looking `.flatMap { $0.isEmpty ? nil : $0 }` — would
# silently fall back to the real registry instead, and would then leave the machine (B59).
#
# Nothing compared it. The comment asserted a divergence risk that no scenario could see, which is
# a claim resting on a reading of two languages' operators rather than on a measurement. Both
# routers are restarted here with both bases empty, on their own ports, because the environment is
# captured once at construction.
kill "$TS_PID" 2>/dev/null; kill "$SWIFT_PID" 2>/dev/null
wait "$TS_PID" 2>/dev/null; wait "$SWIFT_PID" 2>/dev/null
export MCP_ROUTER_REGISTRY="" MCP_ROUTER_SMITHERY=""
MCP_ROUTER_HOME="$WORK/ts" node "$REPO_ROOT/dist/index.js" serve \
  --port "$TS_PORT2" --idle-ms 120000 >"$WORK/ts2.log" 2>&1 &
TS_PID=$!
MCP_ROUTER_HOME="$WORK/swift" "$SWIFT_BIN" serve \
  --port "$SWIFT_PORT2" --idle-ms 120000 >"$WORK/swift2.log" 2>&1 &
SWIFT_PID=$!
if wait_ready "$TS_PORT2" "$TS_PID" reference && wait_ready "$SWIFT_PORT2" "$SWIFT_PID" Swift; then
  TS_PORT="$TS_PORT2"; SWIFT_PORT="$SWIFT_PORT2"
  compare "both bases set and EMPTY — a nullish default keeps the empty string and new URL throws" \
    "q=github&limit=5" 0 \
    "$(printf 'official registry unreachable: Invalid URL\nSmithery unreachable: Invalid URL')"
else
  verdict 0 "a router would not start with an empty registry base, so the nullish-default claim in RouterServiceDispatch stayed unmeasured"
fi

echo
echo "compared $((pass + fail)) scenarios: $pass ok, $fail failed"
[ "$fail" -gt 0 ] && finish 1
finish 0
