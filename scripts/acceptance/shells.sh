#!/bin/bash
#
# F1 acceptance: both app shells launch and render a value that came from MCPRouterKit.
#
# This exists because clauses A5 and A15 cannot be met by a build gate. A build proves the linker
# resolved a symbol; it does not prove the shared library reached the screen. The one-off evidence
# for those clauses was a screenshot a human looked at, which is not evidence anyone can re-check —
# so this is that check, made repeatable.
#
# Two oracles, deliberately, because neither is sufficient alone:
#
#   1. The rendered pixel. The window's background is sampled and compared to `ColorToken.ground`.
#      This is the only assertion here that proves something *drew*.
#   2. The accessibility tree, for the text. It proves the semantic tree carries the strings, which
#      is what a screen reader would read.
#
# The second is explicitly NOT a render check. Apple states the accessibility tree is not
# necessarily one-to-one with what a sighted user sees, so a green AX walk over a window that
# painted nothing is possible. That is why the pixel assertion is the one that carries A15, and why
# removing it would leave this script asserting far less than it appears to.
#
# The expected colour is read out of ColorToken.swift rather than written here, so the gate follows
# the token instead of pinning a copy of it that can drift. The unit suite separately holds that
# token equal to DESIGN.md, so this transitively checks the document too.
#
# Exit codes are distinct on purpose: 2 means the harness could not run (no Accessibility grant, an
# unreadable tree), 1 means an assertion failed. Reporting a permission problem as a failed
# assertion is how a suite produces N confident false failures that all point at the app.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT/app"
MAC_APP="$APP_DIR/.derived/Build/Products/Debug/MCPRouter.app"
MAC_BUNDLE_ID="app.fledgeling.mcprouter"
IOS_BUNDLE_ID="app.fledgeling.mcprouter.ios"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
blocked() { echo "BLOCKED: $*" >&2; exit 2; }
pass() { echo "  ok — $*"; }

# ---------------------------------------------------------------- expected value

# Read the token from source. An unreadable token is a harness failure, not a passing test: without
# it there is nothing to compare against, and defaulting to a literal would assert a stale copy.
#
# Scoped to the `hex` property's own switch. `ColorToken` now carries two appearances, so a bare
# grep for `case .ground:` matches the dark value AND the light one and yields a two-line string
# that can never equal a sampled pixel — a harness that fails against every colour it is given.
EXPECTED_HEX="$(sed -n '/var hex: String/,/^    }/p' \
  "$APP_DIR/Sources/MCPRouterKit/Design/ColorToken.swift" \
  | grep -oE 'case \.ground: *"#[0-9A-Fa-f]{6}"' \
  | grep -oE '#[0-9A-Fa-f]{6}' | tr '[:lower:]' '[:upper:]' || true)"
[ -n "$EXPECTED_HEX" ] || blocked "could not read ColorToken.ground from source — nothing to assert against"
[ "$(printf '%s' "$EXPECTED_HEX" | wc -l)" -eq 0 ] \
  || blocked "ColorToken.ground read as more than one value — the extraction is ambiguous"
echo "expecting ColorToken.ground = $EXPECTED_HEX"

# ---------------------------------------------------------------- pixel sampler

# Reads the raw pixel in the image's OWN colour space.
#
# Converting to sRGB first is the trap here, and it is silent: `screencapture` writes a Display
# P3-tagged PNG, and converting a neutral #1E1E1E out of P3 reports #282828 — a mismatch that looks
# exactly like the app painting the wrong colour. The first run of this check "found" that bug, and
# the bug was in the measurement.
cat > "$WORK/sample.swift" <<'SWIFT'
import AppKit
let args = CommandLine.arguments
guard args.count >= 4, let img = NSImage(contentsOfFile: args[1]),
      let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let x = Int(args[2]), let y = Int(args[3]) else {
    FileHandle.standardError.write(Data("sampler: bad arguments or unreadable image\n".utf8))
    exit(2)
}
guard x < rep.pixelsWide, y < rep.pixelsHigh, let c = rep.colorAt(x: x, y: y) else {
    FileHandle.standardError.write(Data("sampler: point outside image\n".utf8))
    exit(2)
}
print(String(format: "#%02X%02X%02X",
             Int((c.redComponent * 255).rounded()),
             Int((c.greenComponent * 255).rounded()),
             Int((c.blueComponent * 255).rounded())))
SWIFT

sample_pixel() { swift "$WORK/sample.swift" "$1" "$2" "$3"; }

# ---------------------------------------------------------------- static: the gallery is Debug-only

# These two run BEFORE anything that needs a screen, deliberately. They are the only assertions here
# that a locked or headless machine can still make, and they carry acceptance criterion 9 on their
# own — so a session that cannot render still produces real evidence instead of nothing.
#
# Checked against the built binaries rather than the source: `#if DEBUG` around the wrong brace
# still compiles, and grepping the source would agree with itself.

echo
echo "the gallery is compiled into Debug only"

GALLERY_ID="mcprouter-design-gallery"
REL_APP="$APP_DIR/.derived/Build/Products/Release/MCPRouter.app"

# Search every Mach-O in the bundle, not just `Contents/MacOS/<name>`.
#
# An Xcode 16 Debug build puts the app's actual code in `MCPRouter.debug.dylib` and leaves a ~40KB
# launcher stub at the executable path. Checking only that stub reports "the gallery is not
# compiled in" for a build that contains it — a false failure that points at the feature instead of
# at the measurement. Release has no such split, so the same sweep covers both.
bundle_contains() {
    local bundle="$1" needle="$2" f
    while IFS= read -r f; do
        if strings -a "$f" 2>/dev/null | grep -qF "$needle"; then return 0; fi
    done < <(find "$bundle" -type f -perm +111)
    return 1
}

[ -d "$MAC_APP" ] || blocked "no built app at $MAC_APP — run 'make build-mac' first"
bundle_contains "$MAC_APP" "$GALLERY_ID" \
  || fail "no binary in the Debug bundle contains '$GALLERY_ID' — the gallery is not compiled in"
pass "Debug bundle contains the gallery"

[ -d "$REL_APP" ] || blocked "no Release build at $REL_APP — run 'make build-mac-release' first"
if bundle_contains "$REL_APP" "$GALLERY_ID"; then
    fail "the Release bundle contains '$GALLERY_ID' — the Debug-only gallery is shipping"
fi
pass "Release bundle does not contain the gallery"

# ---------------------------------------------------------------- macOS

echo
echo "macOS shell"

[ -d "$MAC_APP" ] || blocked "no built app at $MAC_APP — run 'make build-mac' first"

# Kill any stale instance BEFORE anything else. A previous run's copy still holding the bundle id
# means `open` activates the zombie rather than launching this build, so every assertion below
# would describe an app nobody just built.
osascript -e "tell application id \"$MAC_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
pkill -f 'MCPRouter.app/Contents/MacOS/MCPRouter' >/dev/null 2>&1 || true
sleep 1

# Preflight the screen lock. macOS does not composite windows for an app launched into a locked
# session, so every window assertion below fails — and fails as "the window never appeared", which
# reads as a broken app rather than a machine nobody is logged into. This script already refuses to
# report a missing permission as a failed assertion; a locked screen is the same class of problem
# and gets the same treatment.
cat > "$WORK/session.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let d = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
let locked = (d["CGSSessionScreenIsLocked"] as? Int) ?? 0
let onConsole = (d["kCGSSessionOnConsoleKey"] as? Int) ?? 0
if d.isEmpty { print("nosession") } else if locked == 1 { print("locked") }
else if onConsole != 1 { print("notconsole") } else { print("ok") }
SWIFT
SESSION_STATE="$(swift "$WORK/session.swift" 2>/dev/null || echo unknown)"
case "$SESSION_STATE" in
    locked)     blocked "the screen is locked — macOS will not composite a window for a launched app. Unlock and re-run." ;;
    nosession)  blocked "no GUI session (headless or SSH) — the window assertions need a logged-in console session" ;;
    notconsole) blocked "this session does not own the console — windows cannot be rendered here" ;;
esac

# Preflight the Accessibility grant. Without it every AX query returns empty, which is
# indistinguishable from "the element is missing" — so it must be its own outcome.
if ! osascript -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1; then
    blocked "no Accessibility permission for this terminal — System Settings > Privacy & Security > Accessibility"
fi

open "$MAC_APP"

# Poll for a real standard window. A non-activating panel can enumerate before the main window
# exists, so "a window exists" can be true too early.
WINDOW_READY=""
for _ in $(seq 1 30); do
    if osascript -e "tell application \"System Events\" to tell process \"MCPRouter\" to get subrole of window 1" 2>/dev/null | grep -q 'AXStandardWindow'; then
        WINDOW_READY=1; break
    fi
    sleep 0.5
done
[ -n "$WINDOW_READY" ] || fail "the macOS window never appeared"
sleep 1  # settle: let SwiftUI finish its first paint before sampling
pass "window appeared (AXStandardWindow)"

# Walk the tree. `entire contents` is bound to a variable first: iterating it inline yields zero
# elements where the bound form yields the full set, and both spellings look correct.
AX_TEXT="$(osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events" to tell process "MCPRouter"
    set out to ""
    set c to entire contents of window 1
    repeat with e in c
        try
            set v to value of e as text
            if v is not "" then set out to out & v & linefeed
        end try
    end repeat
    return out
end tell
APPLESCRIPT
)"

# Zero-count guard: fail ONCE as an unreadable tree rather than once per expected string. N false
# failures read as a broken app; one reads as a broken harness, which is what it would be.
[ -n "$(printf '%s' "$AX_TEXT" | tr -d '[:space:]')" ] || blocked "the accessibility tree read as empty — harness or permission problem, not an assertion failure"

for needle in "MCP Router" "Version"; do
    printf '%s' "$AX_TEXT" | grep -qF "$needle" \
      || fail "the macOS window's accessibility tree does not carry '$needle'"
    pass "accessibility tree carries '$needle'"
done

# The render assertion. Sample well inside the window, below the text block.
BOUNDS="$(osascript -e 'tell application "System Events" to tell process "MCPRouter" to get {position, size} of window 1')"
WX="$(echo "$BOUNDS" | cut -d, -f1 | tr -d ' ')"
WY="$(echo "$BOUNDS" | cut -d, -f2 | tr -d ' ')"
WW="$(echo "$BOUNDS" | cut -d, -f3 | tr -d ' ')"
WH="$(echo "$BOUNDS" | cut -d, -f4 | tr -d ' ')"
screencapture -o -x -R "$WX,$WY,$WW,$WH" "$WORK/mac.png"

# Sampled in image pixels; the capture is 2x on a Retina display, so this is the lower-middle of
# the window either way — clear of the title and the copy.
GOT="$(sample_pixel "$WORK/mac.png" 200 "$((WH * 3 / 2))")"
[ "$GOT" = "$EXPECTED_HEX" ] \
  || fail "macOS background rendered $GOT, expected ColorToken.ground $EXPECTED_HEX"
pass "rendered background = $GOT = ColorToken.ground"

osascript -e "tell application id \"$MAC_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true

# ---------------------------------------------------------------- the design gallery

# The rendered half of the gallery's evidence. The Debug-only claim was already settled above,
# without needing a screen; what is left is the part only a running window can show — that the
# gallery opens, and that its LIGHT appearance actually renders the light ground.
#
# That last assertion is the only one in the repository proving the authored light appearance
# reaches a screen. The parity suite proves the values exist and match the document; it cannot
# prove anything drew them.

echo
echo "design gallery"

# Read the light ground out of the token, for the same reason the dark one is read: a literal here
# would be a second copy of a design value, free to drift from the one the suite checks.
EXPECTED_LIGHT="$(sed -n '/var lightHex: String/,/^    }/p' \
  "$APP_DIR/Sources/MCPRouterKit/Design/ColorToken.swift" \
  | grep -oE 'case \.ground: *"#[0-9A-Fa-f]{6}"' \
  | grep -oE '#[0-9A-Fa-f]{6}' | tr '[:lower:]' '[:upper:]' || true)"
[ -n "$EXPECTED_LIGHT" ] || blocked "could not read ColorToken.ground's light value from source"
echo "expecting light ColorToken.ground = $EXPECTED_LIGHT"

# Launch Debug with the gallery forced into its light appearance, then open the window.
open -n "$MAC_APP" --args --gallery-appearance light
sleep 2

if ! osascript -e 'tell application "System Events" to tell process "MCPRouter" to click menu item "Design system" of menu "Window" of menu bar 1' >/dev/null 2>&1; then
    blocked "could not reach the Design system item in the Window menu"
fi

GALLERY_READY=""
for _ in $(seq 1 30); do
    if osascript -e 'tell application "System Events" to tell process "MCPRouter" to get name of windows' 2>/dev/null | grep -q 'Design system'; then
        GALLERY_READY=1; break
    fi
    sleep 0.5
done
[ -n "$GALLERY_READY" ] || fail "the design gallery window never appeared"
sleep 2
pass "gallery window opened from the menu bar"

GB="$(osascript -e 'tell application "System Events" to tell process "MCPRouter" to get {position, size} of (first window whose name is "Design system")')"
GX="$(echo "$GB" | cut -d, -f1 | tr -d ' ')"
GY="$(echo "$GB" | cut -d, -f2 | tr -d ' ')"
GW="$(echo "$GB" | cut -d, -f3 | tr -d ' ')"
GH="$(echo "$GB" | cut -d, -f4 | tr -d ' ')"
screencapture -o -x -R "$GX,$GY,$GW,$GH" "$WORK/gallery.png"

# Sampled low in the detail pane: clear of the swatch rows and right of the sidebar. The capture is
# 2x on a Retina display, so these are image pixels rather than points.
GOT_LIGHT="$(sample_pixel "$WORK/gallery.png" "$((GW * 2 - 40))" "$((GH * 2 - 40))")"
[ "$GOT_LIGHT" = "$EXPECTED_LIGHT" ] \
  || fail "the gallery's light appearance rendered $GOT_LIGHT, expected $EXPECTED_LIGHT"
pass "light appearance rendered $GOT_LIGHT = ColorToken.ground (light)"

osascript -e "tell application id \"$MAC_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true

# ---------------------------------------------------------------- iOS

echo
echo "iOS shell"

SIM_ID="$(xcrun simctl list devices available | grep -E 'iPhone' | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)"
[ -n "$SIM_ID" ] || blocked "no iPhone simulator available"

IOS_APP="$(find "$APP_DIR/.derived/Build/Products" -name 'MCPRouterIOS.app' -path '*iphonesimulator*' 2>/dev/null | head -1)"
[ -n "$IOS_APP" ] || blocked "no built iOS app — run 'make build-ios' with a simulator destination first"

xcrun simctl boot "$SIM_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIM_ID" -b >/dev/null 2>&1 || true
xcrun simctl install "$SIM_ID" "$IOS_APP" >/dev/null
xcrun simctl terminate "$SIM_ID" "$IOS_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$SIM_ID" "$IOS_BUNDLE_ID" >/dev/null
sleep 4
xcrun simctl io "$SIM_ID" screenshot "$WORK/ios.png" >/dev/null 2>&1
[ -s "$WORK/ios.png" ] || blocked "the simulator produced no screenshot"
pass "app launched and produced a screenshot"

# Mid-screen, below the copy block and above the home indicator.
GOT_IOS="$(sample_pixel "$WORK/ios.png" 300 1400)"
[ "$GOT_IOS" = "$EXPECTED_HEX" ] \
  || fail "iOS background rendered $GOT_IOS, expected ColorToken.ground $EXPECTED_HEX"
pass "rendered background = $GOT_IOS = ColorToken.ground"

xcrun simctl terminate "$SIM_ID" "$IOS_BUNDLE_ID" >/dev/null 2>&1 || true

echo
echo "acceptance: both shells render ColorToken.ground ($EXPECTED_HEX) — A5, A15 hold"
echo "acceptance: the gallery is Debug-only and its light appearance renders $EXPECTED_LIGHT"
