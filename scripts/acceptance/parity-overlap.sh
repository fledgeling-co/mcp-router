#!/usr/bin/env bash
#
# R19 — the overlap lane.
#
# Every other lane in this harness runs the two binaries **sequentially**, over separate scratch
# homes, one after the other. That is right for comparing what each of them answers, and it is
# structurally blind to a property that only exists while two writers overlap: a manifest row
# written between another path's read and its save. `parity-cli.sh` could grow a fifth `watch`
# scenario and still never see it, because nothing in that lane is ever live at the same time as
# anything else.
#
# So this lane is the one that overlaps. It runs a `watch` fire that stays open for seconds against
# a staged server that fails to index, and drives a SECOND writer into the middle of that window.
# The assertion is on `manifest.json` rather than on a stream: what is under test is which rows
# survive, and the two routers report a refused write in different words for reasons that predate
# this item (see "what is NOT compared" below).
#
# ROWS THIS LANE OWNS — asserted before any write, because the gate binds no script to a group:
#   overlap: overlap-watch-index overlap-lock-shared
#
# WHAT IS NOT COMPARED, and why it is not silence:
#
#   · **The streams.** Under a refused manifest write the reference throws and exits 1, and this
#     router reports `not cached` on stdout and exits 0. That is R10/DEF-049's decision, recorded in
#     `ServicePorts.swift` as deliberately not moved by that item, and it is reached here only when
#     a lock is deliberately held by this script. Comparing the streams would redden this row on a
#     divergence that is older than R19 and owned elsewhere.
#   · **Timing.** The reference's pool notices a child that exits and fails within milliseconds of
#     it; this router waits out `startupTimeoutMs`. The fixture therefore fails by TIMEOUT on both
#     sides — `startupTimeoutMs` is set below and the fixture's own exit is a backstop that a
#     healthy run never reaches — so neither side's window depends on that difference.
#
# NOTHING HERE RESTARTS A ROUTER. The staged server fails, so nothing is ever adopted, so
# `servers.json` is never rewritten and the reference never reaches its hardcoded `launchctl
# kickstart` against the developer's own live router. `parity-cli.sh` avoids the same hazard by
# pre-seeding; this lane avoids it by never producing an adoption at all, and the assertion below
# that `servers.json` is byte-unchanged is what keeps that true rather than assumed.
#
# It binds no port, so it takes no harness lock: the thing `parity-lock.sh` protects is a set of
# TCP ports and this lane has none.
#
# Exit codes: 0 agreed, 1 a mismatch, 2 the environment could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
WORK="$(mktemp -d -t parity-overlap)"
RESULTS="${PARITY_RESULTS:-}"

MAIN_PID=$$
cleanup() {
  [ "$BASHPID" != "$MAIN_PID" ] && return 0
  rm -rf "$WORK"
}
trap cleanup EXIT

OWNED="overlap/overlap-watch-index overlap/overlap-lock-shared"

record() {
  [ -n "$RESULTS" ] || return 0
  case " $(echo $OWNED) " in
    *" $1/$2 "*) ;;
    *) echo "  LANE BUG: refusing to record $1/$2, which this lane does not own" >&2; return 1 ;;
  esac
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$RESULTS"
}

pass=0; fail=0
verdict() { # id ok? message
  if [ "$2" = 1 ]; then
    pass=$((pass + 1)); printf '  ok   %-24s %s\n' "$1" "$3"; record overlap "$1" ok "$3"
  else
    fail=$((fail + 1)); printf '  FAIL %-24s %s\n' "$1" "$3"; record overlap "$1" fail "$3"
  fi
}

command -v node >/dev/null 2>&1 || { echo "environment: node is not installed"; exit 2; }
[ -f "$REPO_ROOT/dist/index.js" ] || { echo "environment: no dist/index.js. Run npm run build."; exit 2; }
[ -x "$SWIFT_BIN" ] || { echo "environment: no Swift router at ${SWIFT_BIN#"$REPO_ROOT/"}"; exit 2; }
command -v perl >/dev/null 2>&1 || { echo "environment: perl is needed to hold a real flock"; exit 2; }
FIXTURE="$REPO_ROOT/scripts/fixtures/slow-failing-server.mjs"
[ -f "$FIXTURE" ] || { echo "environment: no slow-failing fixture at ${FIXTURE#"$REPO_ROOT/"}"; exit 2; }

# How long the staged server holds the index open. Long enough that the second writer lands well
# inside the window on a loaded machine, short enough that the lane costs seconds rather than a
# minute. The fixture's own exit is a backstop at 3x this, so a run where the timeout somehow does
# not fire still ends rather than hanging the gate.
STARTUP_MS=8000
SECOND_WRITER_AT=2

# `<home>` for the directory. Nothing else is normalised, and nothing here diffs a stream.
rows_of() { # manifest-path -> the sorted server names, comma-separated, or "(none)"
  node -e '
    const fs = require("node:fs");
    try {
      const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const names = Object.keys(m.servers ?? {}).sort();
      process.stdout.write(names.length ? names.join(",") : "(none)");
    } catch { process.stdout.write("(unreadable)"); }
  ' "$1"
}

seed() { # side
  local side="$1" home="$WORK/$1/home" rh="$WORK/$1/rh"
  rm -rf "$WORK/$side"; mkdir -p "$home" "$rh"
  echo "toolset" > "$WORK/$side/toolset"
  # `lifeline` is the row the SECOND writer owns: configured, never staged, so the watch fire never
  # touches it and a row of its that goes missing can only have been erased by somebody else's save.
  cat > "$rh/servers.json" <<JSON
{
  "port": 8879,
  "host": "127.0.0.1",
  "idleMs": 300000,
  "startupTimeoutMs": $STARTUP_MS,
  "mcpServers": {
    "lifeline": {
      "command": "node",
      "args": ["$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs", "stdio"],
      "env": { "FIXTURE_TOOLSET_FILE": "$WORK/$side/toolset" }
    }
  }
}
JSON
  # `slowfail` is staged only. It answers nothing and is killed by the startup timeout, so the
  # watcher records a backoff and adopts nothing — which is what keeps `servers.json` untouched.
  # It also LEAVES A MANIFEST ROW carrying its reason, which is R17's decision and is why the
  # expected row set below is two names rather than one. When this lane was written the watcher
  # deleted that row, so the manifest ended holding `lifeline` alone; R17 keeps it, and the merge
  # of the two items is where the two facts met. The row under test is still `lifeline`'s.
  cat > "$home/.claude.json" <<JSON
{
  "numStartups": 41,
  "mcpServers": {
    "slowfail": {
      "command": "node",
      "args": ["$FIXTURE"],
      "env": { "FIXTURE_FAIL_AFTER_MS": "$((STARTUP_MS * 3))" }
    }
  }
}
JSON
  cp "$rh/servers.json" "$WORK/$side/servers.json.before"
}

run_side() { # side verb...
  local side="$1"; shift
  if [ "$side" = ts ]; then
    HOME="$WORK/ts/home" MCP_ROUTER_HOME="$WORK/ts/rh" \
      node "$REPO_ROOT/dist/index.js" "$@"
  else
    HOME="$WORK/swift/home" MCP_ROUTER_HOME="$WORK/swift/rh" \
      MCPR_LAUNCHD_LABEL="gg.rhodes.mcp-router-overlap-$$" \
      "$SWIFT_BIN" "$@"
  fi
}

# ---------------------------------------------------------------------------------------------
# overlap-watch-index — a row written inside a watch fire's window survives it.
#
# The one scenario this whole lane exists for. Pre-R19 the reference loaded the manifest once, spent
# the whole index in that window and saved the snapshot, so `lifeline`'s row — written at t+2s by a
# second process — was gone from the file at the end of it, with no delete statement anywhere in the
# path.
overlap_case() { # side -> prints the rows left in the manifest
  local side="$1"
  seed "$side"
  run_side "$side" watch --verbose > "$WORK/$side/watch.out" 2> "$WORK/$side/watch.err" &
  local watcher=$!
  sleep "$SECOND_WRITER_AT"
  run_side "$side" index --force > "$WORK/$side/index.out" 2> "$WORK/$side/index.err"
  printf '%s' "$?" > "$WORK/$side/index.code"
  wait "$watcher"
  printf '%s' "$?" > "$WORK/$side/watch.code"
  rows_of "$WORK/$side/rh/manifest.json"
}

echo "overlapping a watch fire with a second writer, on both binaries"
echo

ts_rows="$(overlap_case ts)"
sw_rows="$(overlap_case swift)"

# Exact rather than "does it contain lifeline": a watcher that wrote rows nobody asked for would
# pass a containment check, and `rows_of` sorts, so the order is the fixture's and not the clock's.
# `lifeline` is the row this lane exists for — written by the SECOND writer, at t+2s, inside the
# fire's window. `slowfail` is the staged server's own failure record, R17's, and asserting it here
# means a watcher that went back to deleting it reddens this row too.
WANTED_ROWS="lifeline,slowfail"

problems=""
[ "$ts_rows" = "$WANTED_ROWS" ] \
  || problems="$problems reference:[rows=$ts_rows, wanted $WANTED_ROWS]"
[ "$sw_rows" = "$WANTED_ROWS" ] \
  || problems="$problems swift:[rows=$sw_rows, wanted $WANTED_ROWS]"
[ "$ts_rows" = "$sw_rows" ] || problems="$problems disagree:[ts=$ts_rows swift=$sw_rows]"
# The guard that keeps the no-kickstart claim in this file's header true rather than assumed. An
# adoption would rewrite servers.json, and on the reference the next line is a hardcoded
# `launchctl kickstart` against whatever `gg.rhodes.mcp-router` is loaded on this machine.
for side in ts swift; do
  cmp -s "$WORK/$side/servers.json.before" "$WORK/$side/rh/servers.json" \
    || problems="$problems $side:[servers.json was rewritten — an adoption happened and this lane must not produce one]"
done

if [ -z "$problems" ]; then
  verdict overlap-watch-index 1 \
    "a row written ${SECOND_WRITER_AT}s into a watch fire survives it on both binaries (rows=$ts_rows); neither rewrote servers.json"
else
  verdict overlap-watch-index 0 "the overlapping writer's row did not survive —$problems"
fi

# ---------------------------------------------------------------------------------------------
# overlap-lock-shared — both binaries queue on the SAME lock object.
#
# The scenario above proves each router's own read-modify-write is atomic against itself. It cannot
# prove the two exclude EACH OTHER, and they only do if they agree on where the lock lives and on
# what a lock on it means. The reference reaches `flock(2)` through macOS's `O_EXLOCK` open flag
# because node has no `flock` binding; this router calls `flock` directly. Those are one lock or two
# depending on a detail neither file can assert about the other.
#
# A third process holds `<manifest>.lock` with a plain `flock(LOCK_EX)` — the same call the Swift
# side makes and the one `O_EXLOCK` is defined against — and each binary is then asked to write with
# a short bound. Neither may land a row while it is held; both must land one once it is released.
# A binary that ignored the sidecar would write straight through and be caught by the first half.
held_write() { # side -> prints "held-rows|released-rows"
  local side="$1"
  seed "$side"
  local lock="$WORK/$side/rh/manifest.json.lock"
  mkdir -p "$(dirname "$lock")"
  : > "$lock"
  # `$| = 1` matters: stdout is redirected to a file here, so it is block-buffered and the readiness
  # line would sit in perl's buffer for the whole hold — the wait below would expire and this half
  # would report "holder-never-locked" while the lock was in fact held.
  perl -e '$| = 1; open(my $f, "+<", $ARGV[0]) or die; flock($f, 2) or die; print "ready\n"; sleep 60;' \
    "$lock" > "$WORK/$side/holder.out" 2>&1 &
  local holder=$!
  # Bounded: a holder that never took the lock would otherwise leave this half asserting nothing.
  local ready=0
  for _ in $(seq 1 100); do
    grep -q ready "$WORK/$side/holder.out" 2>/dev/null && { ready=1; break; }
    kill -0 "$holder" 2>/dev/null || break
    sleep 0.1
  done
  if [ "$ready" != 1 ]; then
    kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
    printf 'holder-never-locked|holder-never-locked'
    return
  fi

  MCPR_CONFIG_LOCK_TIMEOUT_MS=400 run_side "$side" index --force \
    > "$WORK/$side/held.out" 2> "$WORK/$side/held.err"
  local during
  during="$(rows_of "$WORK/$side/rh/manifest.json")"

  kill "$holder" 2>/dev/null
  wait "$holder" 2>/dev/null
  run_side "$side" index --force > "$WORK/$side/after.out" 2> "$WORK/$side/after.err"
  printf '%s|%s' "$during" "$(rows_of "$WORK/$side/rh/manifest.json")"
}

echo
echo "holding the sidecar from a third process, on both binaries"
echo

ts_lock="$(held_write ts)"
sw_lock="$(held_write swift)"

lock_problems=""
for pair in "reference:$ts_lock" "swift:$sw_lock"; do
  side="${pair%%:*}"; value="${pair#*:}"
  during="${value%%|*}"; after="${value##*|}"
  case "$during" in
    "(none)"|"(unreadable)") ;;
    *) lock_problems="$lock_problems $side:[wrote $during while the lock was held]" ;;
  esac
  [ "$after" = "lifeline" ] \
    || lock_problems="$lock_problems $side:[after release rows=$after, wanted lifeline]"
done

if [ -z "$lock_problems" ]; then
  verdict overlap-lock-shared 1 \
    "neither binary wrote a row while a third process held manifest.json.lock, and both wrote one after it was released"
else
  verdict overlap-lock-shared 0 "the sidecar is not one lock for both —$lock_problems"
fi

echo
echo "overlap: $pass agreed, $fail did not"
echo "     Both rows are simultaneous, not sequential: the first runs a second writer INSIDE a live"
echo "     watch fire, and the second holds the lock object from a third process while each binary"
echo "     writes. No other lane in this harness has two writers live at once."
echo "     Streams are deliberately not diffed here — under a refused write the two routers report"
echo "     differently for R10/DEF-049's reasons, which predate this item and are owned elsewhere."
[ "$fail" -gt 0 ] && exit 1
exit 0
