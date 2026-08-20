#!/bin/bash
# One backgrounded launch, unique window-scoped captures per Mac surface.
# Never activates. UI_VERIFICATION.md rule 1.
#
# Every capture writes a manifest entry into evidence/shots/captures.json as the
# shutter opens: the subject it claims, the target the channel was actually
# pointed at, the channel itself, the bytes' sha256 and the conditions. The
# target is READ BACK from the running app (`axkit title`) rather than asserted
# by this script, which is the only reason it can contradict the filename.
#
# It has, twice. The previous version of this script captured SURF-001 as
# "whatever destination is restored" and the restored destination was Activity,
# so the shell's picture was byte-identical to SURF-003's; and it filed a
# photograph of the Inbox board as SURF-010, the pairing sheet. Both were
# invisible because the filename was the only thing binding a picture to a
# surface. `capture-lineage.py --gate` reads the manifest this writes.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CAMPAIGN="$ROOT/planning/test-campaign"
AXKIT="$CAMPAIGN/bin/axkit"
MAC_APP="$ROOT/app/.derived/Build/Products/Debug/MCPRouter.app"
SHOTS="$CAMPAIGN/evidence/shots"
AX="$CAMPAIGN/evidence/ax"
MANIFEST="$SHOTS/captures.json"
LOG="$CAMPAIGN/evidence/runs/mac-glass-capture.log"
# shellcheck source=scripts/acceptance/mac-app.sh
source "$ROOT/scripts/acceptance/mac-app.sh"

mkdir -p "$SHOTS" "$AX" "$(dirname "$LOG")"
exec > >(tee "$LOG") 2>&1

[ -x "$AXKIT" ] || { echo "no axkit"; exit 2; }
[ -d "$MAC_APP" ] || { echo "no debug app"; exit 2; }

: > "$SHOTS/.captures.ndjson"

FRONT_BEFORE="$("$AXKIT" front)"
echo "frontmost before: $FRONT_BEFORE"

mac_app_launch "$MAC_APP" "$AXKIT" "MCPROUTER_SCENARIO=populated"
echo "attached pid=$PID"
WINID="$("$AXKIT" winid "$PID")"
echo "winid=$WINID"
"$AXKIT" frame "$PID"
"$AXKIT" title "$PID"
"$AXKIT" dump "$PID" menu > "$AX/SURF-001.menu.txt"

# capture <name> <subject> <route-suffix-or-READBACK> [sharesWith,…] [shareReason]
capture() {
  local name="$1" subject="$2" want="$3" shares="${4:-}" reason="${5:-}"
  local dest="$SHOTS/${name}.png"
  local title frame
  # Read back what the window is showing BEFORE the shutter, and again after, so
  # a destination that changed mid-capture cannot be recorded as settled.
  title="$("$AXKIT" title "$PID")"
  frame="$("$AXKIT" frame "$PID")"
  screencapture -x -l"$WINID" "$dest"
  local title_after
  title_after="$("$AXKIT" title "$PID")"
  if [ "$title" != "$title_after" ]; then
    echo "  UNSETTLED $name: title moved $title -> $title_after during capture"
    title="UNSETTLED:$title->$title_after"
  fi
  SUBJECT="$subject" NAME="$name" DEST="$dest" TITLE="$title" FRAME="$frame" \
  WANT="$want" WINID="$WINID" PID="$PID" APP="$MAC_APP" SHARES="$shares" \
  REASON="$reason" MANIFEST_NDJSON="$SHOTS/.captures.ndjson" python3 - <<'PY'
import hashlib, json, os, datetime, pathlib
dest = pathlib.Path(os.environ["DEST"])
raw = dest.read_bytes()
if raw[:8] != b"\x89PNG\r\n\x1a\n":
    raise SystemExit(f"{os.environ['NAME']} is not a PNG")
title = os.environ["TITLE"]
want = os.environ["WANT"]
# The target is the board the app SAID it was showing, not the one asked for.
slug = title.strip().lower().replace(" ", "-")
target = f"app://mac/{slug}" if want == "READBACK" else f"app://mac/{want}"
entry = {
    "path": f"evidence/shots/{dest.name}",
    "subject": os.environ["SUBJECT"],
    "target": target,
    "channel": "screencapture -x -l<CGWindowID> (window-scoped, background; macOS)",
    "derivedFrom": None,
    "sha256": hashlib.sha256(raw).hexdigest(),
    "capturedAt": datetime.datetime.now(datetime.timezone.utc)
                  .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "conditions": {"windowTitleReadback": title, "frame": os.environ["FRAME"],
                   "cgWindowID": os.environ["WINID"], "appearance": "system",
                   "scenario": os.environ.get("SCENARIO", "populated")},
    "witnessed": (f"axkit attached pid={os.environ['PID']} owns CGWindowID "
                  f"{os.environ['WINID']}, bundle {os.environ['APP']}"),
}
if os.environ.get("SHARES"):
    entry["sharesWith"] = [s for s in os.environ["SHARES"].split(",") if s]
    entry["shareReason"] = os.environ.get("REASON") or ""
with open(os.environ["MANIFEST_NDJSON"], "a") as fh:
    fh.write(json.dumps(entry) + "\n")
print(f"  captured {os.environ['NAME']} bytes={len(raw)} "
      f"sha={entry['sha256'][:16]} target={target}")
PY
}

SHELL_SHARE_REASON="the shell is window chrome and the sidebar; it has no board of its own, so it is photographed on the Servers board and is the same window and the same pixels"

# Eight boards, each selected then read back. SURF-001 is the shell — chrome that
# has no board of its own — so it is photographed on the Servers board and says
# so, rather than being filed as "whatever was restored".
for pair in \
  "SURF-002:Servers" \
  "SURF-003:Activity" \
  "SURF-004:Skills" \
  "SURF-005:Discover" \
  "SURF-008:Inbox" \
  "SURF-006:Checks" \
  "SURF-007:Cleanup" \
  "SURF-011:Settings"
do
  sid="${pair%%:*}"
  row="${pair##*:}"
  echo "select $row -> $sid"
  "$AXKIT" select "$PID" "$row" || echo "  select failed for $row"
  sleep 0.5
  "$AXKIT" title "$PID" | tee "$AX/${sid}.title.txt"
  "$AXKIT" dump "$PID" window > "$AX/${sid}.window.txt"
  # The Servers capture is also the shell's, so BOTH entries declare the share —
  # the gate requires every subject in a share to name the others, which is what
  # makes the wall say "one picture, two cells" from either side of it.
  if [ "$sid" = "SURF-002" ]; then
    capture "${sid}.build" "$sid" READBACK "SURF-001" "$SHELL_SHARE_REASON"
  else
    capture "${sid}.build" "$sid" READBACK
  fi
  if [ "$sid" = "SURF-002" ]; then
    # The shell is the same window and the same pixels. Declared, not hidden.
    cp "$SHOTS/SURF-002.build.png" "$SHOTS/SURF-001.build.png"
    SUBJECT=SURF-001 NAME=SURF-001.build DEST="$SHOTS/SURF-001.build.png" \
    TITLE="$("$AXKIT" title "$PID")" FRAME="$("$AXKIT" frame "$PID")" \
    WANT=READBACK WINID="$WINID" PID="$PID" APP="$MAC_APP" \
    SHARES="SURF-002" \
    REASON="$SHELL_SHARE_REASON" \
    MANIFEST_NDJSON="$SHOTS/.captures.ndjson" python3 - <<'PY'
import hashlib, json, os, datetime, pathlib
dest = pathlib.Path(os.environ["DEST"]); raw = dest.read_bytes()
title = os.environ["TITLE"]
entry = {"path": f"evidence/shots/{dest.name}", "subject": os.environ["SUBJECT"],
         "target": "app://mac/" + title.strip().lower().replace(" ", "-"),
         "channel": "screencapture -x -l<CGWindowID> (window-scoped, background; macOS)",
         "derivedFrom": "evidence/shots/SURF-002.build.png",
         "sha256": hashlib.sha256(raw).hexdigest(),
         "capturedAt": datetime.datetime.now(datetime.timezone.utc)
                       .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
         "conditions": {"windowTitleReadback": title, "frame": os.environ["FRAME"],
                        "cgWindowID": os.environ["WINID"], "appearance": "system",
                        "scenario": "populated"},
         "witnessed": f"axkit attached pid={os.environ['PID']} owns CGWindowID {os.environ['WINID']}, bundle {os.environ['APP']}",
         "sharesWith": ["SURF-002"], "shareReason": os.environ["REASON"]}
open(os.environ["MANIFEST_NDJSON"], "a").write(json.dumps(entry) + "\n")
print(f"  captured SURF-001.build (declared share of SURF-002) sha={entry['sha256'][:16]}")
PY
    "$AXKIT" dump "$PID" window > "$AX/SURF-001.window.txt"
  fi
done

# The add-server sheet. It is a state of the Servers board, not a surface of its
# own — the registry's SURF-013 is "iOS Triage, Queue, Library", and an earlier
# version of this script filed this Mac sheet under that id because it was
# written against a stale draft of the surface list whose ids shift from
# SURF-012 on. The capture is kept under a name that claims no surface.
echo "try add-server sheet"
if "$AXKIT" select "$PID" "Servers" && sleep 0.4 && \
   "$AXKIT" press "$PID" "Add server" >/dev/null 2>&1; then
  sleep 0.6
  "$AXKIT" dump "$PID" window > "$AX/SURF-002.addserver.window.txt"
  capture SURF-002.addserver SURF-002 READBACK
  "$AXKIT" key "$PID" 53 || true
  sleep 0.3
else
  echo "  add-server control not pressable in background — sheet uncaptured"
fi

# Pairing sheet. The previous run filed a photograph of the Inbox board here.
echo "try pairing sheet"
PAIR_OPENED=0
for label in "Pair a phone" "Pair" "Pairing"; do
  if "$AXKIT" press "$PID" "$label" >/dev/null 2>&1; then PAIR_OPENED=1; break; fi
done
if [ "$PAIR_OPENED" = "1" ]; then
  sleep 0.6
  "$AXKIT" dump "$PID" window > "$AX/SURF-010.window.txt"
  capture SURF-010.build SURF-010 "pairing"
  "$AXKIT" key "$PID" 53 || true
  sleep 0.3
else
  echo "  no pairing control was pressable in the background — SURF-010 uncaptured,"
  echo "  and no picture is filed under it. The previous run filed the Inbox board here."
fi

# Status item / popover — recorded as unreachable rather than substituted.
echo "try status item / popover"
if "$AXKIT" press "$PID" "mcp-router" >/dev/null 2>&1; then
  sleep 0.4
  capture SURF-009.build SURF-009 READBACK
else
  echo "  status item not pressable in background — SURF-009 uncaptured"
fi

relaunch_and_capture() {
  local scenario="$1" name="$2" subject="$3"
  "$AXKIT" terminate "$PID" || true
  mac_app_wait_gone "$MAC_APP"
  mac_app_launch "$MAC_APP" "$AXKIT" "MCPROUTER_SCENARIO=$scenario"
  WINID="$("$AXKIT" winid "$PID")"
  "$AXKIT" select "$PID" "Servers" || true
  sleep 0.5
  "$AXKIT" dump "$PID" window > "$AX/${name}.window.txt"
  SCENARIO="$scenario" capture "$name" "$subject" READBACK
}
relaunch_and_capture empty   SURF-002.empty   SURF-002
relaunch_and_capture offline SURF-002.offline SURF-002

"$AXKIT" terminate "$PID" || true
mac_app_wait_gone "$MAC_APP"

python3 - <<PY
import json, pathlib
src = pathlib.Path("$SHOTS/.captures.ndjson")
rows = [json.loads(l) for l in src.read_text().splitlines() if l.strip()]
pathlib.Path("$MANIFEST").write_text(json.dumps(rows, indent=2) + "\n")
print(f"manifest: {len(rows)} capture(s) -> $MANIFEST")
src.unlink()
PY

FRONT_AFTER="$("$AXKIT" front)"
echo "frontmost after: $FRONT_AFTER"
if [ "$FRONT_AFTER" != "$FRONT_BEFORE" ]; then
  echo "FAIL: stole focus ($FRONT_BEFORE -> $FRONT_AFTER)"
  exit 1
fi
echo "glass capture done, focus unchanged"
