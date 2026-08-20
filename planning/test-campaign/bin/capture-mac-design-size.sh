#!/bin/bash
#
# Photograph the Mac boards at the window size the design of record draws, so the
# rendered-quality gate has a comparable pair to judge.
#
# ## Why this is a second script rather than a flag on capture-mac-glass.sh
#
# The 980x620 captures that script produces are the evidence under 24 on-glass cases,
# and glass-assert.py reads pixel bands at coordinates derived from that frame -- 224
# checks on 2026-08-20. Re-photographing in place at a different size would invalidate
# every one of them to answer a different question. So these land in their own
# directory, under their own manifest, and nothing here overwrites an existing shot.
#
# ## Why the window is resized at all
#
# be-my-witness's prescan refused all 16 build/design pairs on framing: the design's
# Mac window is 1156x680 (aspect 1.700, from `.mac{width:1156px}` and `.win{height:680px}`)
# and the app opens at 980x620 (aspect 1.581). No crop reconciles two different window
# shapes. The resize is a legitimate configuration rather than a contrivance -- ShellWindow
# sets `.frame(minWidth: 0, maxWidth: .infinity)` and leaves `windowResizability` automatic,
# so this is a size a user can drag the window to, and the boards are built to fill it.
#
# The frame is READ BACK after being set. AXUIElementSetAttributeValue returning .success
# means the message was accepted, not that the window took the size: a window with a
# minimum or a fixed aspect clamps, and the capture would then be filed as "the design
# size" while being some other size entirely.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAMPAIGN="$(dirname "$HERE")"
ROOT="$(cd "$CAMPAIGN/../.." && pwd)"
AXKIT="$CAMPAIGN/bin/axkit"
MAC_APP="$ROOT/app/.derived/Build/Products/Debug/MCPRouter.app"
SHOTS="$CAMPAIGN/evidence/shots/design-size"
AX="$CAMPAIGN/evidence/ax/design-size"
LOG="$CAMPAIGN/evidence/runs/mac-design-size-capture.log"
source "$ROOT/scripts/acceptance/mac-app.sh"

WANT_W=1156
WANT_H=680

mkdir -p "$SHOTS" "$AX" "$(dirname "$LOG")"
exec > >(tee "$LOG") 2>&1

[ -x "$AXKIT" ] || { echo "no axkit"; exit 2; }
[ -d "$MAC_APP" ] || { echo "no debug app"; exit 2; }
: > "$SHOTS/.captures.ndjson"

FRONT_BEFORE="$("$AXKIT" front)"
echo "frontmost before: $FRONT_BEFORE"
echo "design window size: ${WANT_W}x${WANT_H}"

mac_app_launch "$MAC_APP" "$AXKIT" "MCPROUTER_SCENARIO=populated"
echo "attached pid=$PID"
WINID="$("$AXKIT" winid "$PID")"
echo "winid=$WINID"
echo "frame as launched: $("$AXKIT" frame "$PID")"

# Set the frame, then read it back. A clamped resize is the failure this guards.
"$AXKIT" setframe "$PID" 120 120 "$WANT_W" "$WANT_H"
sleep 0.8
GOT="$("$AXKIT" frame "$PID")"
echo "frame after setframe: $GOT"
GOT_W="$(echo "$GOT" | tr ',' ' ' | awk '{print int($3)}')"
GOT_H="$(echo "$GOT" | tr ',' ' ' | awk '{print int($4)}')"
if [ "$GOT_W" != "$WANT_W" ] || [ "$GOT_H" != "$WANT_H" ]; then
  echo "BLOCKED: the window clamped to ${GOT_W}x${GOT_H} instead of ${WANT_W}x${WANT_H};"
  echo "         a capture filed as the design size would be a different size."
  "$AXKIT" terminate "$PID" || true
  exit 2
fi

capture() {
  local name="$1" subject="$2" want="$3"
  local title frame
  if [ "$want" != "READBACK" ]; then
    "$AXKIT" select "$PID" "$want" || { echo "  select '$want' failed — $name uncaptured"; return 1; }
    sleep 0.6
  fi
  # The dump belongs HERE, after the select, not before the call. The first version of this script
  # dumped in the caller's loop and then called this function, so every dump described the board
  # that was up BEFORE the one being photographed -- nine files each labelled with the next board's
  # name. The pictures were unaffected (they are taken below, after the same select, and carry a
  # title readback), and the mislabelling was invisible until a term found in one dump could not be
  # attributed to the board named on it.
  "$AXKIT" dump "$PID" window > "$AX/${name}.window.txt" 2>/dev/null || true
  title="$("$AXKIT" title "$PID")"
  frame="$("$AXKIT" frame "$PID")"
  local dest="$SHOTS/${name}.png"
  local front_shutter; front_shutter="$("$AXKIT" front)"
  screencapture -x -l"$WINID" "$dest"
  [ -f "$dest" ] || { echo "  screencapture produced nothing for $name"; return 1; }
  SUBJECT="$subject" NAME="$name" DEST="$dest" TITLE="$title" FRAME="$frame" \
  PID="$PID" WINID="$WINID" APP="$MAC_APP" FRONT="$front_shutter" \
  WANT="${WANT_W}x${WANT_H}" python3 - <<'PY' >> "$SHOTS/.captures.ndjson"
import hashlib, json, os, subprocess
p = os.environ["DEST"]
raw = open(p, "rb").read()
dim = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", p],
                     capture_output=True, text=True).stdout
px = dict(l.split(":")[0].strip().split()[-1:] + [l.split(":")[1].strip()]
          for l in dim.splitlines() if ":" in l and "pixel" in l)
entry = {
    "name": os.environ["NAME"], "subject": os.environ["SUBJECT"],
    "path": f"evidence/shots/design-size/{os.path.basename(p)}",
    "sha256": hashlib.sha256(raw).hexdigest(),
    "pixels": px,
    "channel": "screencapture -x -l<CGWindowID> (window-scoped, background; macOS)",
    "frameStatus": "unavailable — screencapture exposes no per-frame status; "
                   "ScreenCaptureKit's SCFrameStatus has no equivalent here",
    "conditions": {"windowTitleReadback": os.environ["TITLE"],
                   "frame": os.environ["FRAME"],
                   "requestedSize": os.environ["WANT"],
                   "frontmostAtShutter": os.environ["FRONT"],
                   "scenario": "populated"},
    "witnessed": (f"axkit attached pid={os.environ['PID']} owns CGWindowID "
                  f"{os.environ['WINID']}, bundle {os.environ['APP']}"),
}
print(json.dumps(entry))
print(f"  captured {entry['name']} {px} sha={entry['sha256'][:16]} title={entry['conditions']['windowTitleReadback']!r}",
      file=__import__("sys").stderr)
PY
}

for pair in \
  "SURF-002:Servers" "SURF-003:Activity" "SURF-004:Skills" "SURF-005:Discover" \
  "SURF-008:Inbox" "SURF-006:Checks" "SURF-007:Cleanup" "SURF-011:Settings"
do
  sid="${pair%%:*}"; dest="${pair#*:}"
  echo "-- $sid ($dest)"
  capture "$sid" "$sid" "$dest" || true
done

# SURF-001 is the shell -- the chrome every destination is drawn inside. It is not a
# ninth board, so it is not selected; it is the sidebar region of whatever board is up,
# cropped from that board's own picture downstream, exactly as the 980pt run does it.
echo "-- SURF-001 (shell, declared share of the last board captured)"
"$AXKIT" dump "$PID" window > "$AX/SURF-001.window.txt" 2>/dev/null || true

FRONT_AFTER="$("$AXKIT" front)"
echo "frontmost after: $FRONT_AFTER"
"$AXKIT" terminate "$PID" || true

python3 - <<'PY'
import json, pathlib
d = pathlib.Path("evidence/shots/design-size")
rows = [json.loads(l) for l in (d / ".captures.ndjson").read_text().splitlines() if l.strip()]
(d / "captures.json").write_text(json.dumps({"captures": rows}, indent=2) + "\n")
print(f"wrote {d}/captures.json — {len(rows)} captures")
PY
