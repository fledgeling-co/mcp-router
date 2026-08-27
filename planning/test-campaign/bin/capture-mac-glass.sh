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
  # Who is in front at the shutter. The invariant this campaign owes is that MCPRouter is
  # never activated, and that is a fact about MCPRouter rather than about whichever app the
  # window server promoted while a launch and a terminate went past. Sampled here so every
  # capture carries its own answer instead of the run carrying one for all of them.
  local front_at_shutter
  front_at_shutter="$("$AXKIT" front)"
  FRONT_SHUTTER="$front_at_shutter"
  if [ "$front_at_shutter" = "MCPRouter" ]; then
    echo "FAIL $name: MCPRouter was frontmost at the shutter — this campaign never activates it"
    exit 1
  fi
  screencapture -x -l"$WINID" "$dest"
  local title_after
  title_after="$("$AXKIT" title "$PID")"
  if [ "$title" != "$title_after" ]; then
    echo "  UNSETTLED $name: title moved $title -> $title_after during capture"
    title="UNSETTLED:$title->$title_after"
  fi
  SUBJECT="$subject" NAME="$name" DEST="$dest" TITLE="$title" FRAME="$frame" \
  WANT="$want" WINID="$WINID" PID="$PID" APP="$MAC_APP" SHARES="$shares" \
  FRONT="$front_at_shutter" \
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
                   "frontmostAtShutter": os.environ.get("FRONT", ""),
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

# Nine boards, each selected then read back. SURF-001 is the shell — chrome that
# has no board of its own — so it is photographed on the Servers board and says
# so, rather than being filed as "whatever was restored".
#
# **SURF-025 joined this loop on 2026-08-27 and that is the whole of G15.** The
# Harnesses board shipped with M22 and was never enumerated, so it was never
# selected here — and because a surface with no row cannot be reported uncovered,
# every completeness gate stayed clean over a list that had eight boards in it and
# a product that had nine. Adding the pair is the fix; the denominator moving is
# the evidence.
for pair in \
  "SURF-002:Servers" \
  "SURF-003:Activity" \
  "SURF-004:Skills" \
  "SURF-025:Harnesses" \
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
    SUBJECT=SURF-001 NAME=SURF-001.build DEST="$SHOTS/SURF-001.build.png" FRONT="$FRONT_SHUTTER" \
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
                        # The same shutter as SURF-002's, because these are the same pixels.
                        "frontmostAtShutter": os.environ.get("FRONT", ""),
                        "scenario": "populated"},
         "witnessed": f"axkit attached pid={os.environ['PID']} owns CGWindowID {os.environ['WINID']}, bundle {os.environ['APP']}",
         "sharesWith": ["SURF-002"], "shareReason": os.environ["REASON"]}
open(os.environ["MANIFEST_NDJSON"], "a").write(json.dumps(entry) + "\n")
print(f"  captured SURF-001.build (declared share of SURF-002) sha={entry['sha256'][:16]}")
PY
    "$AXKIT" dump "$PID" window > "$AX/SURF-001.window.txt"

    # The shell's OWN pixels: the sidebar, cropped out of the window it was photographed in.
    #
    # The full-window share above is honest and it is also not evidence about the shell alone — it
    # is byte-identical to the Servers board, so a pixel claim on it is a pixel claim on SURF-002
    # wearing a second id, which is exactly what `glass-assert.py` and `campaign.py check` both
    # refuse. This crop is the shell without a board in it. Its geometry is read out of the dump
    # rather than written down, so a resized window crops correctly instead of silently cutting the
    # wrong strip, and the entry records what it was derived from.
    SHOT_DIR="$SHOTS" AX_DUMP="$AX/SURF-001.window.txt" APP="$MAC_APP" PID="$PID" \
    WINID="$WINID" MANIFEST_NDJSON="$SHOTS/.captures.ndjson" python3 - <<'CROP'
import hashlib, json, os, datetime, pathlib
from PIL import Image

shots = pathlib.Path(os.environ["SHOT_DIR"])
src = shots / "SURF-001.build.png"
rows = [r.split("\t") for r in pathlib.Path(os.environ["AX_DUMP"]).read_text().splitlines()]

def frame(row):
    return [float(v) for v in row[-5:-1]]

window = next(r for r in rows if len(r) > 5 and r[1] == "AXWindow")
sidebar = next(r for r in rows if len(r) > 5 and r[1] == "AXOutline" and "Sidebar" in r)
wx, wy, ww, wh = frame(window)
sx, sy, sw, sh = frame(sidebar)

image = Image.open(src)
# Two unknowns, two equations: the window's points map to pixels at some scale, inside a shadow
# margin the compositor adds equally on each side.
scale = (image.width - image.height) / (ww - wh)
margin = (image.width - ww * scale) / 2
right = margin + (sx + sw - wx) * scale
if not (0 < right <= image.width) or abs(scale - round(scale)) > 0.01:
    raise SystemExit(f"sidebar crop refused: scale={scale} right={right} of {image.width}")

dest = shots / "SURF-001.shell.png"
image.crop((0, 0, int(round(right)), image.height)).save(dest)
raw = dest.read_bytes()
entry = {
    "path": f"evidence/shots/{dest.name}", "subject": "SURF-001",
    "target": "app://mac/shell",
    "channel": "screencapture -x -l<CGWindowID> (window-scoped, background; macOS), "
               "cropped to the sidebar frame the AX dump reports",
    "derivedFrom": "evidence/shots/SURF-001.build.png",
    "sha256": hashlib.sha256(raw).hexdigest(),
    "capturedAt": datetime.datetime.now(datetime.timezone.utc)
                  .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "conditions": {"windowTitleReadback": window[3], "frame": f"{sx},{sy},{sw},{sh}",
                   "cgWindowID": os.environ["WINID"], "appearance": "system",
                   # No shutter of its own: this is cut from a capture that had one, and that
                   # capture's own entry carries the answer. Said rather than left empty.
                   "frontmostAtShutter": "n/a — derived crop, see SURF-001.build.png",
                   "scenario": "populated",
                   "crop": f"0,0,{int(round(right))},{image.height} of "
                           f"{image.width}x{image.height} at scale {scale:g}, "
                           f"shadow margin {margin:g}px"},
    "witnessed": (f"axkit attached pid={os.environ['PID']} owns CGWindowID "
                  f"{os.environ['WINID']}, bundle {os.environ['APP']}"),
}
open(os.environ["MANIFEST_NDJSON"], "a").write(json.dumps(entry) + "\n")
print(f"  captured SURF-001.shell (sidebar crop of SURF-001.build) "
      f"bytes={len(raw)} sha={entry['sha256'][:16]}")
CROP
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
# The pairing sheet, opened from the board that carries its control.
#
# Reported "no pairing control was pressable in the background" for three runs, and the control was
# pressable the whole time: `axkit press` walks the FRONT window, the block above leaves the app on
# Servers, and the `Pairing…` button lives on Inbox and on Settings. The surface was recorded as
# unreachable for a reason that was this script's own navigation rather than the product's. Select
# the board first, and press the label the dump actually reports — with its ellipsis, since the
# match is a substring of the accessibility description.
echo "try pairing sheet"
PAIR_OPENED=0
for board in Inbox Settings; do
  "$AXKIT" select "$PID" "$board" || continue
  sleep 0.4
  if "$AXKIT" press "$PID" "Pairing" >/dev/null 2>&1; then PAIR_OPENED=1; break; fi
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

# A state that needs its own launch, because the scenario is read once at start-up.
#
# The destination is a parameter rather than always Servers. It was always Servers when the only
# extra states were the Servers board's own empty and offline ones, and hard-coding it meant a
# state belonging to another board had nowhere to be photographed — which is why the Cleanup
# board's skill rows had no picture until this argument existed. The board is selected, then read
# back off the running app by `capture ... READBACK`, so a select that silently failed files the
# picture under the destination the app was actually showing rather than the one asked for.
relaunch_and_capture() {
  local scenario="$1" name="$2" subject="$3" destination="${4:-Servers}"
  "$AXKIT" terminate "$PID" || true
  mac_app_wait_gone "$MAC_APP"
  mac_app_launch "$MAC_APP" "$AXKIT" "MCPROUTER_SCENARIO=$scenario"
  WINID="$("$AXKIT" winid "$PID")"
  "$AXKIT" select "$PID" "$destination" || true
  sleep 0.5
  "$AXKIT" dump "$PID" window > "$AX/${name}.window.txt"
  SCENARIO="$scenario" capture "$name" "$subject" READBACK
}
relaunch_and_capture empty   SURF-002.empty   SURF-002
relaunch_and_capture offline SURF-002.offline SURF-002
# The Cleanup board with skills in the proposal. `populated` installs every skill somewhere and a
# skill is only proposed when no readable client has it, so that scenario draws three servers and
# no skills at all: the `Read first…` substitution and the disabled skill-kind `Remove…` had no
# rendered path in any build, only in tests that construct a reading directly.
relaunch_and_capture cleanupSkills SURF-007.cleanup-skills SURF-007 Cleanup

# The Harnesses board's other two states.
#
# The populated capture above is one of the three answers this board has, and it is the one that
# needs no explaining. `empty` is a real answer of NONE — nothing on this Mac looks like an agent
# CLI — which the fixture serves as a successful read of an empty list rather than as a failure,
# so the board draws its own empty state and not an error. `offline` is the read failing, which
# the board answers with the load's error rather than with rows.
#
# Both need their own launch because the scenario is read once at start-up, and both are
# photographed rather than asserted only in the tree: a state that renders in the AX plane and
# draws nothing on screen is exactly the failure this campaign was rebuilt to catch.
relaunch_and_capture empty   SURF-025.empty   SURF-025 Harnesses
relaunch_and_capture offline SURF-025.failure SURF-025 Harnesses

# The sheet that `Read first…` opens, from the row that draws it.
#
# Reachable only from the state above — the button exists on a flagged skill row and no scenario
# but `cleanupSkills` puts one on the board. Pressed rather than assumed: `axkit press` is
# background-safe on a SwiftUI Button because AXPress runs the action on the element and needs no
# focused scene, and a press that does not take exits non-zero, so the sheet is either photographed
# or reported uncaptured. Escape closes it again so the app is left where the board was.
echo "try provenance sheet"
if "$AXKIT" press "$PID" "Read first" >/dev/null 2>&1; then
  sleep 0.6
  "$AXKIT" dump "$PID" window > "$AX/SURF-007.provenance-sheet.window.txt"
  SCENARIO=cleanupSkills capture SURF-007.provenance-sheet SURF-007 READBACK
  "$AXKIT" key "$PID" 53 || true
  sleep 0.3
else
  echo "  Read first… was not pressable in the background — provenance sheet uncaptured,"
  echo "  and no picture is filed under it."
fi

"$AXKIT" terminate "$PID" || true
mac_app_wait_gone "$MAC_APP"

# Merge by path rather than replace.
#
# Two lanes write this one file: this script, and `name-glass-attachments.py`, which merges the
# iOS lane's rows up from `evidence/shots/ios/captures.json` because the lineage gate reads only
# the parent. This block used to write `json.dumps(rows)` — its own eight Mac rows, whole file —
# so whichever lane captured last deleted the other's provenance, silently. Measured on
# 2026-08-20: the parent held 16 Mac rows and none of the nine iOS ones, and
# `capture-lineage.py --gate` reported six iOS captures UNSOURCED, which is the correct verdict on
# a manifest that had been overwritten. That is DEF-039.
#
# Replacing by path keeps this run's rows authoritative for the pictures this run took, and leaves
# every other lane's alone. A row for a capture no longer taken stays rather than vanishing: the
# gate's unsourced pass is where a stale row should surface, not here.
python3 - <<PY
import json, pathlib
src = pathlib.Path("$SHOTS/.captures.ndjson")
rows = [json.loads(l) for l in src.read_text().splitlines() if l.strip()]
dest = pathlib.Path("$MANIFEST")
prior = json.loads(dest.read_text()) if dest.exists() else []
if isinstance(prior, dict):
    prior = prior.get("captures", [])
fresh = {r["path"]: r for r in rows}
merged = [fresh.pop(r["path"], r) for r in prior]
merged.extend(fresh.values())
dest.write_text(json.dumps(merged, indent=2) + "\n")
print(f"manifest: {len(rows)} capture(s) from this run, {len(merged)} total -> $MANIFEST")
src.unlink()
PY

# Does any board lay out wider than the window it is in?
#
# Every dump above carries an AXWindow row and, one level down, the AXSplitGroup that holds the
# whole shell. Those two widths are the same on a board that fits. Where the split group is wider,
# `NavigationSplitView` has laid out past the window and SwiftUI has PLACED the oversized child
# centred, so the sidebar's section headers fall off the left and the header's trailing controls
# fall off the right — equally, by half the excess each — and the picture is silent about what it
# cut. That is DEF-015, which was recorded as a shutter-timing artefact until these two numbers
# were read side by side: 988 on Checks, 1044 on Skills and 1119 on Discover, inside a 980pt
# window, each origin moved left by exactly half its excess.
#
# **This fails the capture rather than reporting a number, and it is allowed to because a build
# exists that passes it.** `ContentZone` on `ai/x4` carries `.frame(minWidth: 0, maxWidth:
# .infinity, alignment: .leading)`, which stops the boards' fixed columns reporting a minimum up
# the chain; measured against that build on 20 Aug 2026, all eight boards read 980 of 980. Against
# a build without it the gate is red, and that is the point rather than a problem — a gate wired in
# while nothing can pass it either blocks unrelated work or gets its assertion softened.
#
# **What it does NOT see, stated because `overflowing=0` reads like "nothing is clipped" and is
# not that claim.** It compares the split group against the window, so it catches content escaping
# the window. Content that overflows the detail PANE and is cut at the trailing edge stays inside
# the window and is invisible here — and that is still happening on the same three boards, because
# the leading alignment chooses the trailing chrome over the sidebar rather than making anything
# fit. Closing that needs the three boards' columns to flex.
python3 - <<'OVERFLOW' "$AX"
import pathlib, sys
ax = pathlib.Path(sys.argv[1])
examined = over = 0
for dump in sorted(ax.glob("*.window.txt")):
    rows = [line.split("\t") for line in dump.read_text().splitlines() if line.strip()]
    window = next((r for r in rows if len(r) > 12 and r[1] == "AXWindow"), None)
    split = next((r for r in rows if len(r) > 12 and r[1] == "AXSplitGroup"), None)
    if not window or not split:
        continue
    examined += 1
    window_width, split_width = float(window[-3]), float(split[-3])
    if split_width > window_width + 0.5:
        over += 1
        print(f"  OVERFLOW {dump.stem}: split group {split_width:.0f}pt inside a "
              f"{window_width:.0f}pt window — {split_width - window_width:.0f}pt clipped, "
              f"half off each edge")
print(f"board width: examined={examined} overflowing={over} (DEF-015)")
if examined == 0:
    print("FAIL: no window dump carried both an AXWindow and an AXSplitGroup row — this check "
          "did not run, and a check that did not run is never a pass")
    sys.exit(1)
sys.exit(1 if over else 0)
OVERFLOW

FRONT_AFTER="$("$AXKIT" front)"
echo "frontmost after: $FRONT_AFTER"
# The per-shutter check above is the gate, because it names MCPRouter. This one compares the
# session's frontmost app before and after, which is a different question: it went red twice on
# runs where an unrelated application took focus during the minute this takes, and it cannot tell
# that from this script stealing it. Reported with the app named, so a reader can see which it was,
# and not treated as a verdict about MCPRouter.
if [ "$FRONT_AFTER" != "$FRONT_BEFORE" ]; then
  echo "note: another application took focus during the run ($FRONT_BEFORE -> $FRONT_AFTER)."
  echo "      MCPRouter was not frontmost at any shutter — checked per capture, and recorded on"
  echo "      each entry in captures.json as conditions.frontmostAtShutter."
fi
echo "glass capture done, MCPRouter never frontmost"
