#!/bin/bash
# One backgrounded launch, unique window-scoped captures per Mac surface.
# Never activates. UI_VERIFICATION.md rule 1.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CAMPAIGN="$ROOT/planning/test-campaign"
AXKIT="$CAMPAIGN/bin/axkit"
MAC_APP="$ROOT/app/.derived/Build/Products/Debug/MCPRouter.app"
SHOTS="$CAMPAIGN/evidence/shots"
AX="$CAMPAIGN/evidence/ax"
LOG="$CAMPAIGN/evidence/runs/mac-glass-capture.log"
# shellcheck source=scripts/acceptance/mac-app.sh
source "$ROOT/scripts/acceptance/mac-app.sh"

exec > >(tee "$LOG") 2>&1

[ -x "$AXKIT" ] || { echo "no axkit"; exit 2; }
[ -d "$MAC_APP" ] || { echo "no debug app"; exit 2; }

FRONT_BEFORE="$("$AXKIT" front)"
echo "frontmost before: $FRONT_BEFORE"

mac_app_launch "$MAC_APP" "$AXKIT" "MCPROUTER_SCENARIO=populated"
echo "attached pid=$PID"
WINID="$("$AXKIT" winid "$PID")"
echo "winid=$WINID"
"$AXKIT" frame "$PID"
"$AXKIT" title "$PID"
"$AXKIT" dump "$PID" window > "$AX/SURF-001.window.txt"
"$AXKIT" dump "$PID" menu > "$AX/SURF-001.menu.txt"

capture() {
  local name="$1"
  local dest="$SHOTS/${name}.png"
  # window-scoped; photographs this window even when occluded by others
  screencapture -x -l"$WINID" "$dest"
  python3 - <<PY
from pathlib import Path
p=Path("$dest")
raw=p.read_bytes()
print(f"  captured $name bytes={len(raw)} sha={__import__('hashlib').sha256(raw).hexdigest()[:16]}")
if raw[:8] != b"\\x89PNG\\r\\n\\x1a\\n":
    raise SystemExit(f"$name is not a PNG")
PY
}

# shell (whatever destination is restored)
capture SURF-001.build

# eight destinations via sidebar select
for pair in \
  "SURF-003:Activity" \
  "SURF-002:Servers" \
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
  sleep 0.4
  "$AXKIT" title "$PID" | tee "$AX/${sid}.title.txt"
  "$AXKIT" dump "$PID" window > "$AX/${sid}.window.txt"
  capture "${sid}.build"
done

# pairing sheet: try the Inbox "Pair" control
echo "try pairing sheet"
if "$AXKIT" press "$PID" "Pair" >/dev/null 2>&1 || "$AXKIT" press "$PID" "Pairing" >/dev/null 2>&1; then
  sleep 0.5
  "$AXKIT" dump "$PID" window > "$AX/SURF-010.window.txt"
  capture SURF-010.build
  "$AXKIT" key "$PID" 53 || true   # escape
  sleep 0.3
else
  echo "  pairing control not pressable in background — SURF-010 uncaptured"
fi

# popover: try status item
echo "try status item / popover"
if "$AXKIT" press "$PID" "mcp-router" >/dev/null 2>&1 || "$AXKIT" press "$PID" "Conduit" >/dev/null 2>&1; then
  sleep 0.4
  capture SURF-009.build
else
  echo "  status item not pressable in background — SURF-009 uncaptured"
fi

# empty-state relaunch
"$AXKIT" terminate "$PID" || true
mac_app_wait_gone "$MAC_APP"
mac_app_launch "$MAC_APP" "$AXKIT" "MCPROUTER_SCENARIO=empty"
WINID="$("$AXKIT" winid "$PID")"
"$AXKIT" select "$PID" "Servers" || true
sleep 0.4
capture SURF-002.empty
"$AXKIT" dump "$PID" window > "$AX/SURF-002.empty.window.txt"

# offline relaunch
"$AXKIT" terminate "$PID" || true
mac_app_wait_gone "$MAC_APP"
mac_app_launch "$MAC_APP" "$AXKIT" "MCPROUTER_SCENARIO=offline"
WINID="$("$AXKIT" winid "$PID")"
"$AXKIT" select "$PID" "Servers" || true
sleep 0.4
capture SURF-002.offline
"$AXKIT" dump "$PID" window > "$AX/SURF-002.offline.window.txt"

"$AXKIT" terminate "$PID" || true
mac_app_wait_gone "$MAC_APP"

FRONT_AFTER="$("$AXKIT" front)"
echo "frontmost after: $FRONT_AFTER"
if [ "$FRONT_AFTER" != "$FRONT_BEFORE" ]; then
  echo "FAIL: stole focus ($FRONT_BEFORE -> $FRONT_AFTER)"
  exit 1
fi
echo "glass capture done, focus unchanged"
