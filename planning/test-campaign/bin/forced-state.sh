#!/usr/bin/env bash
#
# J5 — put the router into a chosen state and read the boards back.
#
# ## What this is for
#
# `REQ-004`, `REQ-005` and `REQ-007` are the product's three honesty promises about what a board
# may claim: that the Servers board reflects live server states without inventing a figure the
# tracker did not observe; that live counts go ABSENT rather than last-known when the tracker is
# stale or the router is not running; and that no number the router does not observe is displayed.
# All three carried evidence `reported` — the project's own account of itself — and they carried it
# for a structural reason rather than an oversight.
#
# Every board this campaign has ever photographed was drawn by `FixtureControlAPIClient`. A Debug
# build could not reach a live router at all: `ShellClientFactory` had no `.live` branch reachable
# from the environment, so `MCPROUTER_SCENARIO=live` fell through `Scenario(rawValue:)` and rendered
# `.populated` without saying so. A picture of the populated fixture proves the board renders that
# JSON file. It cannot prove the board reflects a router, and it says nothing at all about what the
# board does when a router that WAS answering stops — which is the half that matters, because a
# board showing a stale figure as current looks identical to one that is right.
#
# So this script arranges the world instead of the app. It starts a REAL router, on a port of its
# own, under a scratch `MCP_ROUTER_HOME`, declaring servers with run-unique names that exist nowhere
# else on the machine. It then drives the built Debug app against that router in three arranged
# conditions and records what the Servers board says in each:
#
#   cold     the router was NEVER started. Nothing has ever listened on this port, so nothing has
#            ever loaded. `ServerStateTracker` is `.failed`.
#   running  the router is up and answering. `.loaded`.
#   stale    the SAME app instance, after a successful load, with the router killed underneath it.
#            `.stale` — a poll that failed over servers that are real. This is the condition
#            `REQ-005` is about and the one nobody encounters by launching the app normally.
#
# `stale` must follow `running` on ONE app instance. A relaunch would reach `.failed`, which is a
# different state that renders differently and would prove the wrong thing.
#
# ## The oracle is a second reader, not the app
#
# At every state this script reads the router itself over HTTP, independently of the app, and writes
# what it got beside what the board drew. `forced-state-assert.py` then compares the two. That is
# what makes these observations rather than reports: the figures on the board have a source outside
# the process that drew them, and a fabricated figure has nowhere to come from.
#
# The declared server names carry a per-run nonce for the same reason. If the shell fell back to the
# shipping endpoint — because the endpoint variable was refused, or because another router happens
# to be listening — the names on the board would not be this run's, and the assertion goes red
# rather than passing against the wrong world.
#
# ## Exit codes
#
#   0  every state was arranged and read
#   1  a state could not be arranged, or the app failed to draw — a claim about the product
#   2  BLOCKED: this harness could not run (no node, no build, no axkit, the port is taken)
#
# The split is the house pattern and it is load-bearing here: reporting "node is not installed" as a
# product failure sends somebody looking for a bug that is not there.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CAMPAIGN="$ROOT/planning/test-campaign"
AXKIT="$CAMPAIGN/bin/axkit"
MAC_APP="$ROOT/app/.derived/Build/Products/Debug/MCPRouter.app"
OUT="$CAMPAIGN/evidence/forced-state"
SHOTS="$CAMPAIGN/evidence/shots/forced-state"
AX="$CAMPAIGN/evidence/ax"
LOG="$OUT/forced-state.log"
PORT="${J5_PORT:-8955}"
ENDPOINT="http://127.0.0.1:$PORT"

# shellcheck source-path=SCRIPTDIR/../../../scripts/acceptance
# shellcheck source=scripts/acceptance/mac-app.sh
# shellcheck disable=SC1091
source "$ROOT/scripts/acceptance/mac-app.sh"

mkdir -p "$OUT" "$SHOTS" "$AX"
exec > >(tee "$LOG") 2>&1

blocked() { echo "BLOCKED: $*" >&2; exit 2; }
failed() { echo "FAIL: $*" >&2; exit 1; }

ROUTER_PID=""
HOME_DIR=""
cleanup() {
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null || true
  [ -n "${PID:-}" ] && "$AXKIT" terminate "$PID" >/dev/null 2>&1 || true
  [ -n "$HOME_DIR" ] && rm -rf "$HOME_DIR" || true
}
trap cleanup EXIT INT TERM HUP

command -v node >/dev/null 2>&1 || blocked "node is not installed — the reference router cannot run"
command -v swiftc >/dev/null 2>&1 || blocked "swiftc is not installed — axkit cannot be built"
[ -f "$ROOT/dist/index.js" ] || blocked "dist/index.js is missing — run npm run build"
[ -d "$MAC_APP" ] || blocked "no Debug app at $MAC_APP — run make build-mac"

# The port has to be free BEFORE anything is arranged. A router of somebody else's already on this
# port would answer every reading here, and `cold` — the state defined by nothing listening — would
# be arranged by writing a comment rather than by the world.
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  blocked "something is already listening on :$PORT. The 'cold' state is defined by nothing being
there, so it cannot be arranged while it is occupied. Set J5_PORT to a free port."
fi

if [ ! -x "$AXKIT" ]; then
  echo "building the accessibility toolkit…"
  swiftc -O -o "$AXKIT" "$ROOT/scripts/acceptance/axkit.swift" 2>"$OUT/axkit.build.log" \
    || { cat "$OUT/axkit.build.log" >&2; blocked "could not build the accessibility toolkit"; }
fi

HOME_DIR="$(mktemp -d -t mcprouter-j5)"
NONCE="$(date -u +%Y%m%dT%H%M%SZ)-$$"

# What this router declares, and why every figure it produces is a different number.
#
# Three upstreams, each a copy of `bin/witness-fixture/fixture-server.py` — a real stdio MCP peer
# that answers `initialize` and `tools/list` and reaches no network. `mcp-router index` is then run
# against them, so the router's disk cache genuinely holds their tools, and ONE of the three is
# declared `warm`, which `src/pool.ts` pre-opens at startup and the reaper leaves alone.
#
# The result is `3 tools from 3 servers · 1 running`, and the four figures are 3, 3, 1 and 1 rather
# than 0, N, 0 and 0. That matters: a board that computed `running` as `servers.count`, or as zero,
# or that dropped the tools total, agrees with a degenerate reading and is caught by this one. An
# earlier draft declared `/bin/echo` three times and produced `0 tools … · 0 running`, where two of
# the four checks compared 0 against 0 and could not have failed.
#
# Every name carries the run's nonce, so a board drawn from any other router on this machine — the
# user's own on :8879 included — cannot pass the assertion.
ALPHA="j5-alpha-$NONCE"
BETA="j5-beta-$NONCE"
GAMMA="j5-gamma-$NONCE"
cp "$CAMPAIGN/bin/witness-fixture/fixture-server.py" "$HOME_DIR/fixture-server.py"
cat > "$HOME_DIR/servers.json" <<JSON
{
  "mcpServers": {
    "$ALPHA": {
      "type": "stdio", "command": "/usr/bin/python3",
      "args": ["$HOME_DIR/fixture-server.py"],
      "env": { "WITNESS_PIDFILE": "$HOME_DIR/alpha.pid" },
      "warm": true
    },
    "$BETA": {
      "type": "stdio", "command": "/usr/bin/python3",
      "args": ["$HOME_DIR/fixture-server.py"],
      "env": { "WITNESS_PIDFILE": "$HOME_DIR/beta.pid" }
    },
    "$GAMMA": {
      "type": "stdio", "command": "/usr/bin/python3",
      "args": ["$HOME_DIR/fixture-server.py"],
      "env": { "WITNESS_PIDFILE": "$HOME_DIR/gamma.pid" }
    }
  }
}
JSON
MCP_ROUTER_HOME="$HOME_DIR" node "$ROOT/dist/index.js" index > "$OUT/index.log" 2>&1 \
  || { tail -20 "$OUT/index.log" >&2; blocked "the router could not index the fixture upstreams"; }
grep -q "tools cached" "$OUT/index.log" \
  || { cat "$OUT/index.log" >&2; blocked "the index run cached nothing, so every tools figure below
would be a zero this harness produced rather than a reading of the product"; }
echo "scratch home: $HOME_DIR"
echo "declared: $ALPHA $BETA $GAMMA"

: > "$OUT/.states.ndjson"

# Read the router INDEPENDENTLY of the app, and record what came back.
#
# This is the oracle. It runs in this process, over the same loopback endpoint, at the moment the
# board is photographed — so "what the board says" and "what the router says" are two readings of
# one world rather than one reading told twice.
read_router() {
  local state="$1"
  local dest="$OUT/router.$state.json"
  # The narration goes to stderr and the VERDICT to stdout, because every caller reads this
  # through `$(...)`. Written the obvious way the two share one channel and the captured value
  # becomes "  router reading (cold): did not answer…unreachable", which then matches neither arm
  # of the caller's test — a harness that arranged the state correctly and mis-read its own answer.
  if curl -fsS --max-time 5 "$ENDPOINT/servers" -o "$dest" 2>/dev/null; then
    echo "  router reading ($state): answered, $(wc -c <"$dest" | tr -d ' ') bytes" >&2
    printf '%s' "reachable"
  else
    rm -f "$dest"
    echo "  router reading ($state): did not answer on $ENDPOINT" >&2
    printf '%s' "unreachable"
  fi
}

# Wait until the Servers board's subtitle says something other than "Reading the router…".
#
# Bounded, and the bound is reported rather than retried away: the app polls every five seconds, so
# a first answer that has not arrived inside the window is a fact about the run and not a reason to
# keep asking. `settled` is the OBSERVED condition, so a state that never settles is recorded as
# unsettled rather than photographed as though it had.
wait_for_reading() {
  local want="$1" tick dump
  for ((tick = 0; tick < 60; tick++)); do
    dump="$("$AXKIT" dump "$PID" window 2>/dev/null || true)"
    case "$want" in
      # Each state waits for ITS OWN answer and for no other. An `any answer will do` wait accepts
      # the wrong board: `The router isn't running` is a settled reading for the cold state and a
      # failed first poll for the running one, and a wait that took either would photograph the
      # second as though it were the first.
      not-running) case "$dump" in *"router isn't running"*) return 0 ;; esac ;;
      current) case "$dump" in *" running"*) case "$dump" in *"tools from"*) return 0 ;; esac ;; esac ;;
      not-current) case "$dump" in *"last reading, not current"*) return 0 ;; esac ;;
      *) echo "wait_for_reading: no such target $want" >&2; return 1 ;;
    esac
    sleep 0.5
  done
  return 1
}

# Photograph and dump one arranged state.
#
#   observe <state> <arrangement-prose> <settled:0|1> <router-reachability>
#
# The window title is read back before and after the shutter, exactly as `capture-mac-glass.sh`
# does, so a board that changed mid-capture is recorded as unsettled rather than filed as settled.
observe() {
  local state="$1" arrangement="$2" settled="$3" reach="$4"
  local dump="$AX/SURF-002.live-$state.window.txt"
  local shot="$SHOTS/SURF-002.live-$state.png"
  local title title_after frame front

  # Force the window server to re-composite before the shutter, then PROVE the frame painted.
  #
  # Measured on this lane's first two runs: `screencapture -l<CGWindowID>` against this window
  # returns an UNPAINTED surface — window chrome, a title, and not even the sidebar — and it does so
  # silently. The cold and stale frames came back byte-identical to each other (sha 84a469099e7c,
  # 267622 bytes) while their accessibility trees differed by 26 rows, so the pictures agreed about
  # a state the app was not in and nothing in the capture said so.
  #
  # The cause is measured rather than guessed. A fixture launch photographs correctly, because
  # `FixtureControlAPIClient` has its data at the first render and the first paint therefore carries
  # the board. A live launch does not: the window is created, the app is behind everything, and by
  # the time the first poll answers the window server has stopped compositing it. Hide-then-unhide,
  # an Activity-and-back reselect and a resize were each tried and each left the surface unchanged.
  #
  # So the shutter is not trusted. `paint-check.py` crops the sidebar out of the frame, using the
  # geometry the accessibility tree reports, and counts the colours in it. Every state draws that
  # sidebar; a frame that does not contain it is a photograph of a window that never painted, and
  # filing one under a state's name is the same defect as photographing a select that did not take.
  # An unpainted frame is DELETED and the state records why it has no picture.
  "$AXKIT" hidden "$PID" hide >/dev/null 2>&1 || true
  sleep 0.5
  "$AXKIT" hidden "$PID" unhide >/dev/null 2>&1 || true
  sleep 1.2

  title="$("$AXKIT" title "$PID")"
  frame="$("$AXKIT" frame "$PID")"
  front="$("$AXKIT" front)"
  if [ "$front" = "MCPRouter" ]; then
    failed "MCPRouter was frontmost at the shutter — this campaign never activates it"
  fi
  "$AXKIT" dump "$PID" window > "$dump"
  screencapture -x -l"$WINID" "$shot"
  title_after="$("$AXKIT" title "$PID")"
  [ "$title" = "$title_after" ] || title="UNSETTLED:$title->$title_after"

  local painted="" reason=""
  # 2>&1 because the refusal is on stderr and it is the whole of what a reader needs when a frame
  # is withheld. Written the obvious way the reason arrives empty and the record says a picture was
  # refused without saying why, which is a withheld measurement with no measurement in it.
  if painted="$(python3 -W ignore "$CAMPAIGN/bin/paint-check.py" "$shot" "$dump" 2>&1)"; then
    echo "  painted $state: $painted"
    painted=1
  else
    reason="$painted"
    painted=0
    rm -f "$shot"
    echo "  NOT PHOTOGRAPHED $state: $reason"
  fi

  STATE="$state" ARRANGEMENT="$arrangement" SETTLED="$settled" REACH="$reach" \
  DUMP="$dump" SHOT="$shot" TITLE="$title" FRAME="$frame" FRONT="$front" \
  PAINTED="$painted" UNPAINTED_REASON="$reason" \
  WINID="$WINID" PID="$PID" APP="$MAC_APP" ENDPOINT="$ENDPOINT" \
  ROUTER_JSON="$OUT/router.$state.json" CAMPAIGN="$CAMPAIGN" \
  NDJSON="$OUT/.states.ndjson" python3 - <<'PY'
import datetime
import hashlib
import json
import os
import pathlib

campaign = pathlib.Path(os.environ["CAMPAIGN"])
shot = pathlib.Path(os.environ["SHOT"])
painted = os.environ["PAINTED"] == "1"
if painted:
    raw = shot.read_bytes()
    if raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{shot} is not a PNG")
    digest = hashlib.sha256(raw).hexdigest()
else:
    digest = None
router = pathlib.Path(os.environ["ROUTER_JSON"])
entry = {
    "state": os.environ["STATE"],
    "arrangement": os.environ["ARRANGEMENT"],
    "settled": os.environ["SETTLED"] == "1",
    "endpoint": os.environ["ENDPOINT"],
    "routerReachable": os.environ["REACH"] == "reachable",
    "routerReading": str(router.relative_to(campaign)) if router.exists() else None,
    "ax": str(pathlib.Path(os.environ["DUMP"]).relative_to(campaign)),
    "shot": str(shot.relative_to(campaign)) if painted else None,
    "unphotographedReason": None if painted else os.environ["UNPAINTED_REASON"],
    "sha256": digest,
    "windowTitleReadback": os.environ["TITLE"],
    "frame": os.environ["FRAME"],
    "cgWindowID": os.environ["WINID"],
    "frontmostAtShutter": os.environ["FRONT"],
    "capturedAt": datetime.datetime.now(datetime.timezone.utc)
                  .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "witnessed": (f"axkit attached pid={os.environ['PID']} owns CGWindowID "
                  f"{os.environ['WINID']}, bundle {os.environ['APP']}"),
}
with open(os.environ["NDJSON"], "a") as fh:
    fh.write(json.dumps(entry) + "\n")
print(f"  observed {entry['state']}: settled={entry['settled']} "
      f"routerReachable={entry['routerReachable']} "
      f"sha={entry['sha256'][:16] if entry['sha256'] else 'NOT PHOTOGRAPHED'} "
      f"title={entry['windowTitleReadback']}")
PY
}

launch_live() {
  mac_app_launch "$MAC_APP" "$AXKIT" \
    "MCPROUTER_SCENARIO=live" \
    "MCP_ROUTER_URL=$ENDPOINT" \
    "MCP_ROUTER_HOME=$HOME_DIR"
  WINID="$("$AXKIT" winid "$PID")"
  "$AXKIT" select "$PID" "Servers" || failed "the Servers row could not be selected"
  sleep 0.5
}

# ---------------------------------------------------------------- state 1: cold
#
# Nothing has ever listened. This is arranged by not starting the router, and the pre-guard above is
# what makes that an arrangement rather than an assumption.
echo "== state: cold (the router was never started) =="
REACH_COLD="$(read_router cold)"
[ "$REACH_COLD" = "unreachable" ] || blocked "something answered on $ENDPOINT before the router was
started — the cold state was not arranged"
launch_live
SETTLED_COLD=1
wait_for_reading not-running || SETTLED_COLD=0
observe cold "the router was never started; nothing has ever listened on $ENDPOINT, so no poll has \
ever succeeded" "$SETTLED_COLD" "$REACH_COLD"
"$AXKIT" terminate "$PID" || true
mac_app_wait_gone "$MAC_APP"

# ------------------------------------------------------------- state 2: running
echo "== state: running (a real router, declaring three servers this run named) =="
MCP_ROUTER_HOME="$HOME_DIR" node "$ROOT/dist/index.js" serve --port "$PORT" \
  >"$OUT/router.log" 2>&1 &
ROUTER_PID=$!
for _ in $(seq 1 60); do
  curl -fsS --max-time 2 "$ENDPOINT/servers" >/dev/null 2>&1 && break
  sleep 0.25
done
curl -fsS --max-time 2 "$ENDPOINT/servers" >/dev/null 2>&1 || {
  sed -n '1,40p' "$OUT/router.log"
  blocked "the router never answered on :$PORT"
}
launch_live
SETTLED_RUNNING=1
wait_for_reading current || SETTLED_RUNNING=0
REACH_RUNNING="$(read_router running)"
observe running "a reference router is up on $ENDPOINT under a scratch MCP_ROUTER_HOME, declaring \
three servers whose names carry this run's nonce" "$SETTLED_RUNNING" "$REACH_RUNNING"

# --------------------------------------------------------------- state 3: stale
#
# The SAME app instance. It has loaded; the router is now killed underneath it. Relaunching would
# reach `.failed`, which is the cold state again and renders differently — so the app is deliberately
# left running across this boundary.
echo "== state: stale (the same app, with the router killed underneath it) =="
kill "$ROUTER_PID" 2>/dev/null || true
wait "$ROUTER_PID" 2>/dev/null || true
ROUTER_PID=""
for _ in $(seq 1 40); do
  curl -fsS --max-time 1 "$ENDPOINT/servers" >/dev/null 2>&1 || break
  sleep 0.25
done
REACH_STALE="$(read_router stale)"
[ "$REACH_STALE" = "unreachable" ] || blocked "the router was still answering after it was killed —
the stale state was not arranged"
SETTLED_STALE=1
wait_for_reading not-current || SETTLED_STALE=0
observe stale "the router that had been answering was killed while this same app instance kept \
running, so a poll that used to succeed now fails over servers that are real" \
"$SETTLED_STALE" "$REACH_STALE"

"$AXKIT" terminate "$PID" || true
mac_app_wait_gone "$MAC_APP"
PID=""

# ------------------------------------------------------------------- the record
NONCE="$NONCE" ENDPOINT="$ENDPOINT" HOME_DIR="$HOME_DIR" OUT="$OUT" CAMPAIGN="$CAMPAIGN" \
SHOTS="$SHOTS" NAMES="$ALPHA,$BETA,$GAMMA" APP="$MAC_APP" python3 - <<'PY'
import datetime
import json
import os
import pathlib

campaign = pathlib.Path(os.environ["CAMPAIGN"])
out = pathlib.Path(os.environ["OUT"])
states = [json.loads(line) for line in (out / ".states.ndjson").read_text().splitlines() if line.strip()]
names = os.environ["NAMES"].split(",")
record = {
    "tool": "planning/test-campaign/bin/forced-state.sh",
    "capturedAt": datetime.datetime.now(datetime.timezone.utc)
                  .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "endpoint": os.environ["ENDPOINT"],
    "bundle": os.environ["APP"],
    "declared": {"names": names, "count": len(names)},
    "nonce": os.environ["NONCE"],
    "oracle": ("`curl $ENDPOINT/servers`, taken by this script at each state, independently of the "
               "app. Every figure asserted about a board is compared against this reading rather "
               "than against the app's own account of what it drew."),
    "states": states,
}
(out / "observations.json").write_text(json.dumps(record, indent=1) + "\n")
print(f"wrote {(out / 'observations.json').relative_to(campaign)} — {len(states)} state(s)")

# The lane's own capture-time manifest, in the shape `bin/capture-manifest.py` derives the
# top-level `evidence/shots/captures.json` from. Written HERE, by the process that opened the
# shutter, for the reason that file's docstring gives: a hand-copied provenance row goes stale on
# the next run of the lane it copies, with no signal until the lineage gate reports it.
shots = pathlib.Path(os.environ["SHOTS"])
manifest = [{
    "path": str(pathlib.Path(s["shot"])),
    "subject": "SURF-002",
    "target": "app://mac/" + s["windowTitleReadback"].strip().lower().replace(" ", "-"),
    "channel": "screencapture -x -l<CGWindowID> (window-scoped, background; macOS)",
    "derivedFrom": None,
    "sha256": s["sha256"],
    "capturedAt": s["capturedAt"],
    "conditions": {
        "windowTitleReadback": s["windowTitleReadback"],
        "frame": s["frame"],
        "cgWindowID": s["cgWindowID"],
        "appearance": "system",
        "frontmostAtShutter": s["frontmostAtShutter"],
        "scenario": "live",
        "forcedState": s["state"],
        "arrangement": s["arrangement"],
        "routerReachable": s["routerReachable"],
    },
    "witnessed": s["witnessed"],
} for s in states if s["shot"]]
(shots / "captures.json").write_text(json.dumps(manifest, indent=1) + "\n")
print(f"wrote {(shots / 'captures.json').relative_to(campaign)} — {len(manifest)} capture(s)")
PY

rm -f "$OUT/.states.ndjson"
# Stamp what this run photographed with the build it came from, in the run that took the pictures.
# capture-mac-glass.sh does this for its own shots; this lane photographed SURF-002's live states
# and wrote no stamp, so a re-capture here left glass-build-gate reading the August build for it.
FS_STAMPED=()
while IFS= read -r f; do FS_STAMPED+=("evidence/shots/forced-state/${f}"); done < <(cd "$SHOTS" && ls *.png 2>/dev/null || true)
if [ "${#FS_STAMPED[@]}" -gt 0 ]; then
  python3 "$CAMPAIGN/bin/glass-build-gate.py" --emit "$MAC_APP" "${FS_STAMPED[@]}" || {
    echo "FAIL: this run's pictures could not be stamped with the build they came from."
    exit 1
  }
fi

echo "forced-state: three states arranged and read; MCPRouter never frontmost"
