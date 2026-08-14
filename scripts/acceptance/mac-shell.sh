#!/bin/bash
#
# M1 acceptance: the Mac shell, measured and driven rather than described.
#
# `shells.sh` proves the shared design system reaches the screen. This proves the *shell* — its
# three zones, its sidebar, its menu bar, its keyboard and its restoration — against the running
# app, because every one of those clauses is about behaviour a build gate cannot see. A linker
# success is not evidence that ⌘2 selects Servers.
#
# The measurement is a Swift walk of the accessibility API rather than AppleScript. That is not a
# style choice: `entire contents` binds a snapshot of a tree that this app mutates every two
# seconds as it polls the router, and reading a property off a stale element raises "-1728" — which
# reads as a missing element rather than as a race. The first version of this script failed that
# way against a perfectly good window.
#
# Exit codes match the house rule: 2 means the harness could not run (no Accessibility grant, a
# locked screen), 1 means an assertion failed. Collapsing them is how a missing permission gets
# reported as a broken app.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT/app"
MAC_APP="$APP_DIR/.derived/Build/Products/Debug/MCPRouter.app"
REL_APP="$APP_DIR/.derived/Build/Products/Release/MCPRouter.app"
BUNDLE_ID="app.fledgeling.mcprouter"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
blocked() { echo "BLOCKED: $*" >&2; exit 2; }
pass() { echo "  ok — $*"; }

[ -d "$MAC_APP" ] || blocked "no built app at $MAC_APP — run 'make build-mac' first"

# ---------------------------------------------------------------- the values under test
#
# Every expected number is read from the source of truth rather than written here. A literal in a
# gate is a second copy of a design value, free to drift from the one the parity suite checks — and
# a gate that drifts agrees with the wrong answer.

metric() {
    sed -n '/var leadingScalar: Double/,/^    }/p' \
      "$APP_DIR/Sources/MCPRouterKit/Design/MetricToken.swift" \
      | grep -oE "case \.$1: *[0-9.]+" | grep -oE '[0-9.]+$' || true
}

SIDEBAR_W="$(metric sidebar)"
TOOLBAR_H="$(metric unifiedToolbar)"
TITLEBAR_H="$(metric titlebar)"
TABLE_ROW="$(metric tableRows)"
for v in SIDEBAR_W TOOLBAR_H TITLEBAR_H TABLE_ROW; do
    [ -n "${!v}" ] || blocked "could not read $v out of MetricToken.swift — nothing to assert against"
done
echo "tokens: sidebar=$SIDEBAR_W toolbar=$TOOLBAR_H titlebar=$TITLEBAR_H tableRow=$TABLE_ROW"

# `DESIGN.md` §2's documented sidebar row sizes, parsed out of the document. A4 asserts the rendered
# row is one of these rather than a number this item chose — the rendered 32 is AppKit's own inset
# around a 24pt content frame, and both values live in that one cell.
DOC_ROWS="$(grep -oE '\| Sidebar \| [0-9]+pt; rows [0-9/]+' "$ROOT/DESIGN.md" \
  | grep -oE 'rows [0-9/]+' | grep -oE '[0-9/]+' | tr '/' ' ' || true)"
[ -n "$DOC_ROWS" ] || blocked "could not read the documented sidebar row sizes out of DESIGN.md"
echo "DESIGN.md §2 sidebar rows: $DOC_ROWS"

# ---------------------------------------------------------------- preflight
#
# Both of these are their own outcome. Without the grant every AX query returns empty, which is
# indistinguishable from "the element is missing"; without a console session macOS composites no
# window at all and every measurement below reads as a broken app.

cat > "$WORK/session.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let d = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
let locked = (d["CGSSessionScreenIsLocked"] as? Int) ?? 0
let onConsole = (d["kCGSSessionOnConsoleKey"] as? Int) ?? 0
if d.isEmpty { print("nosession") } else if locked == 1 { print("locked") }
else if onConsole != 1 { print("notconsole") } else { print("ok") }
SWIFT
case "$(swift "$WORK/session.swift" 2>/dev/null || echo unknown)" in
    locked)     blocked "the screen is locked — macOS will not composite a window for a launched app" ;;
    nosession)  blocked "no GUI session (headless or SSH) — the window assertions need a console session" ;;
    notconsole) blocked "this session does not own the console — windows cannot be rendered here" ;;
esac

osascript -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1 \
  || blocked "no Accessibility permission for this terminal — System Settings > Privacy & Security > Accessibility"

# ---------------------------------------------------------------- the AX walker

cat > "$WORK/axdump.swift" <<'SWIFT'
import AppKit
import ApplicationServices

// Walks a process's accessibility tree and prints one tab-separated row per element. A snapshot
// taken in one pass, so nothing here reads a property off an element the app has since replaced.
//
// Usage: axdump <pid> window|menu

let args = CommandLine.arguments
guard args.count >= 3, let pid = Int32(args[1]) else {
    FileHandle.standardError.write(Data("axdump: expected <pid> <window|menu>\n".utf8))
    exit(2)
}
guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("axdump: not trusted for accessibility\n".utf8))
    exit(2)
}

let app = AXUIElementCreateApplication(pid)

func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func string(_ element: AXUIElement, _ name: String) -> String {
    guard let value = attr(element, name) else { return "" }
    if let s = value as? String { return s }
    if let n = value as? NSNumber { return n.stringValue }
    return ""
}

func bool(_ element: AXUIElement, _ name: String) -> String {
    guard let value = attr(element, name), let n = value as? NSNumber else { return "" }
    return n.boolValue ? "1" : "0"
}

func point(_ element: AXUIElement, _ name: String) -> (Double, Double)? {
    guard let value = attr(element, name) else { return nil }
    // AXValue wraps CGPoint / CGSize; there is no bridged cast for it.
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = value as! AXValue
    if AXValueGetType(axValue) == .cgPoint {
        var p = CGPoint.zero
        if AXValueGetValue(axValue, .cgPoint, &p) { return (Double(p.x), Double(p.y)) }
    }
    if AXValueGetType(axValue) == .cgSize {
        var s = CGSize.zero
        if AXValueGetValue(axValue, .cgSize, &s) { return (Double(s.width), Double(s.height)) }
    }
    return nil
}

func clean(_ s: String) -> String {
    s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
}

var rows = 0
func emit(_ element: AXUIElement, depth: Int) {
    let pos = point(element, kAXPositionAttribute as String) ?? (-1, -1)
    let size = point(element, kAXSizeAttribute as String) ?? (-1, -1)
    let fields = [
        "\(depth)",
        string(element, kAXRoleAttribute as String),
        string(element, kAXSubroleAttribute as String),
        clean(string(element, kAXTitleAttribute as String)),
        clean(string(element, kAXValueAttribute as String)),
        clean(string(element, kAXDescriptionAttribute as String)),
        clean(string(element, kAXHelpAttribute as String)),
        bool(element, kAXEnabledAttribute as String),
        bool(element, kAXSelectedAttribute as String),
        clean(string(element, "AXMenuItemCmdChar")),
        clean(string(element, "AXMenuItemCmdModifiers")),
        clean(string(element, kAXIdentifierAttribute as String)),
        String(format: "%.1f", pos.0), String(format: "%.1f", pos.1),
        String(format: "%.1f", size.0), String(format: "%.1f", size.1),
        // Appended deliberately at the end: the columns above are read positionally by awk, and
        // inserting a field anywhere earlier would silently re-point every one of those reads.
        bool(element, kAXFocusedAttribute as String)
    ]
    print(fields.joined(separator: "\t"))
    rows += 1
    guard depth < 24 else { return }
    if let children = attr(element, kAXChildrenAttribute as String) as? [AXUIElement] {
        for child in children { emit(child, depth: depth + 1) }
    }
}

switch args[2] {
case "window":
    guard let windows = attr(app, kAXWindowsAttribute as String) as? [AXUIElement], !windows.isEmpty else {
        FileHandle.standardError.write(Data("axdump: no windows\n".utf8))
        exit(2)
    }
    // The main window, by title: a Debug build also carries the design gallery.
    let wanted = args.count > 3 ? args[3] : ""
    let target = windows.first { w in
        wanted.isEmpty ? string(w, kAXSubroleAttribute as String) == "AXStandardWindow"
                       : string(w, kAXTitleAttribute as String) == wanted
    } ?? windows[0]
    emit(target, depth: 0)
case "menu":
    guard let bar = attr(app, "AXMenuBar") else {
        FileHandle.standardError.write(Data("axdump: no menu bar\n".utf8))
        exit(2)
    }
    emit(bar as! AXUIElement, depth: 0)
default:
    FileHandle.standardError.write(Data("axdump: unknown mode\n".utf8))
    exit(2)
}

// A walk that produced nothing is a harness failure, never a clean tree.
if rows == 0 {
    FileHandle.standardError.write(Data("axdump: walked zero elements\n".utf8))
    exit(2)
}
SWIFT

swiftc -O -o "$WORK/axdump" "$WORK/axdump.swift" 2>"$WORK/axdump.log" \
  || { cat "$WORK/axdump.log" >&2; blocked "could not build the accessibility walker"; }

# Column indices, named so the awk below reads as something other than magic numbers.
# 1 depth · 2 role · 3 subrole · 4 title · 5 value · 6 desc · 7 help · 8 enabled · 9 selected
# 10 cmdchar · 11 cmdmods · 12 identifier · 13 x · 14 y · 15 w · 16 h

launch_app() {
    pkill -f 'MCPRouter.app/Contents/MacOS/MCPRouter' >/dev/null 2>&1 || true
    sleep 1
    open "$MAC_APP"
    for _ in $(seq 1 40); do
        PID="$(pgrep -f 'MCPRouter.app/Contents/MacOS/MCPRouter' | head -1 || true)"
        if [ -n "$PID" ] && "$WORK/axdump" "$PID" window >/dev/null 2>&1; then return 0; fi
        sleep 0.5
    done
    fail "the shell window never appeared"
}

dump_window() { "$WORK/axdump" "$PID" window > "$WORK/window.tsv" 2>/dev/null || blocked "the window walk failed"; }
dump_menu()   { "$WORK/axdump" "$PID" menu   > "$WORK/menu.tsv"   2>/dev/null || blocked "the menu walk failed"; }

# The app must be frontmost before a keystroke is sent. `open` activates it, but the terminal
# running this script takes focus back, and a ⌘-digit delivered to the terminal changes nothing in
# the app — which reads exactly like a shortcut that is not wired up.
#
# **Waiting for frontmost rather than sleeping on it.** `activate` is asynchronous and a fixed sleep
# is a guess about how long it takes; measured here, the guess was wrong often enough that ⌘1 and ⌘6
# were delivered while the terminal still had focus, and the run reported them as unbound while
# every digit that actually arrived worked. Worse, those keystrokes went *somewhere* — into the
# terminal, whose own ⌘-digit bindings switch tabs. So this polls the real frontmost process and
# only returns once it is the app, and treats never getting there as an environment failure rather
# than sending the key anyway.
activate_app() {
    local deadline=$((SECONDS + 20)) front=""
    while [ "$SECONDS" -lt "$deadline" ]; do
        # Re-issued on every pass rather than once. A single `activate` loses to any app that takes
        # focus back afterwards — a terminal printing output is enough — and one request followed by
        # a long wait is a slower way to lose the same race.
        osascript -e "tell application id \"$BUNDLE_ID\" to activate" >/dev/null 2>&1 || true
        sleep 0.3
        front="$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || true)"
        if [ "$front" = "MCPRouter" ]; then
            # Frontmost is necessary but not sufficient: it is reported as the activation begins, and
            # a ⌘-key delivered during it can land before the window is taking key events. Measured —
            # returning the instant frontmost flipped made ⌘2 intermittently do nothing. The settle
            # costs half a second per activation and removes the flake.
            sleep 0.5
            return 0
        fi
    done
    blocked "MCPRouter never became frontmost (it is '$front') — a keystroke sent now would go to
         another app. Nothing else may hold focus while this runs: close other foreground work on
         this display and run it again."
}

echo
echo "the three-zone shell"
launch_app
sleep 2
dump_window
[ -s "$WORK/window.tsv" ] || blocked "the accessibility tree read as empty — harness or permission problem"

# ---------------------------------------------------------------- A1 · the three zones

# The sidebar. Named "Sidebar" by AppKit, so it is found by role+title rather than by a path
# through the view hierarchy, which SwiftUI is free to reshape.
GOT_SIDEBAR="$(awk -F'\t' '$2 == "AXOutline" { print $15; exit }' "$WORK/window.tsv")"
[ -n "$GOT_SIDEBAR" ] || fail "no sidebar outline in the accessibility tree"
awk -v got="$GOT_SIDEBAR" -v want="$SIDEBAR_W" 'BEGIN { exit !(got + 0 == want + 0) }' \
  || fail "the sidebar rendered ${GOT_SIDEBAR}pt wide, expected MetricToken.sidebar = $SIDEBAR_W"
pass "sidebar rendered ${GOT_SIDEBAR}pt = MetricToken.sidebar"

GOT_TOOLBAR="$(awk -F'\t' '$2 == "AXToolbar" { print $16; exit }' "$WORK/window.tsv")"
[ -n "$GOT_TOOLBAR" ] || fail "no toolbar in the accessibility tree"
awk -v got="$GOT_TOOLBAR" -v want="$TOOLBAR_H" 'BEGIN { exit !(got + 0 == want + 0) }' \
  || fail "the toolbar rendered ${GOT_TOOLBAR}pt tall, expected MetricToken.unifiedToolbar = $TOOLBAR_H"
pass "unified toolbar rendered ${GOT_TOOLBAR}pt = MetricToken.unifiedToolbar"

# The titlebar, and the one number in §2 this item could not reproduce.
#
# In a unified-toolbar window the titlebar is *inside* the 52pt band rather than stacked above it —
# which is why the toolbar and the window share a y origin, and why there is no separate titlebar
# band to measure on screen. So two things are asserted here, and a third is reported.
#
# Asserted: the chrome band above the content is exactly `MetricToken.unifiedToolbar`, measured from
# the window's own origin to the top of the sidebar; and AppKit's standard title bar fits inside it.
#
# Reported, not asserted: AppKit on this machine reports a **32pt** title bar for a standard titled
# window, where `DESIGN.md` §2 records 33. Neither `DESIGN.md` nor `MetricToken` is this item's to
# change — both are shared surfaces — so the discrepancy is printed here and carried in the item's
# report rather than papered over with a tolerance or quietly corrected.
CONTENT_TOP="$(awk -F'\t' '$2 == "AXOutline" { print $14; exit }' "$WORK/window.tsv")"
WIN_TOP="$(awk -F'\t' '$1 == 0 { print $14; exit }' "$WORK/window.tsv")"
[ -n "$CONTENT_TOP" ] && [ -n "$WIN_TOP" ] || fail "could not measure the chrome band above the content"
CHROME_BAND="$(awk -v a="$CONTENT_TOP" -v b="$WIN_TOP" 'BEGIN { printf "%.1f", a - b }')"
awk -v got="$CHROME_BAND" -v want="$TOOLBAR_H" 'BEGIN { exit !(got + 0 == want + 0) }' \
  || fail "the chrome above the content measures ${CHROME_BAND}pt, expected MetricToken.unifiedToolbar = $TOOLBAR_H"
pass "chrome band above content = ${CHROME_BAND}pt = MetricToken.unifiedToolbar"

cat > "$WORK/titlebar.swift" <<'SWIFT'
import AppKit
let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
let content = NSRect(x: 0, y: 0, width: 400, height: 400)
let frame = NSWindow.frameRect(forContentRect: content, styleMask: style)
print(Int((frame.height - content.height).rounded()))
SWIFT
GOT_TITLEBAR="$(swift "$WORK/titlebar.swift" 2>/dev/null || true)"
[ -n "$GOT_TITLEBAR" ] || blocked "could not ask AppKit for the title bar height"
awk -v t="$GOT_TITLEBAR" -v band="$TOOLBAR_H" 'BEGIN { exit !(t + 0 > 0 && t + 0 < band + 0) }' \
  || fail "AppKit's ${GOT_TITLEBAR}pt title bar does not fit inside the ${TOOLBAR_H}pt unified band"
pass "AppKit's title bar (${GOT_TITLEBAR}pt) sits inside the unified band, as a unified toolbar means"

if ! awk -v got="$GOT_TITLEBAR" -v want="$TITLEBAR_H" 'BEGIN { exit !(got + 0 == want + 0) }'; then
    echo "  NOTE — DESIGN.md §2 records a ${TITLEBAR_H}pt titlebar; AppKit here reports ${GOT_TITLEBAR}pt."
    echo "  NOTE   Reported as a shared-surface finding rather than changed: DESIGN.md and MetricToken"
    echo "  NOTE   belong to the design system, not to this item."
fi

# ---------------------------------------------------------------- A4 · one row height, documented

# Destination rows are the outline rows that carry a button; the two group headers are rows too and
# are excluded by having a heading rather than a button.
awk -F'\t' '$2 == "AXRow" { print $16 }' "$WORK/window.tsv" | sort -u > "$WORK/rowheights.txt"
ROW_HEIGHTS="$(grep -vE '^(0\.0|-1\.0)$' "$WORK/rowheights.txt" | tr '\n' ' ')"
[ -n "$ROW_HEIGHTS" ] || fail "no sidebar rows in the accessibility tree"

# The destination rows must all be one height. Headers are a different (smaller) one, which is why
# this takes the *modal* height rather than requiring the whole set to agree.
DEST_ROW="$(awk -F'\t' '$2 == "AXRow" && $16 > 0 { c[$16]++ } END { m = 0; for (h in c) if (c[h] > m) { m = c[h]; best = h } print best }' "$WORK/window.tsv")"
DEST_ROW_COUNT="$(awk -F'\t' -v h="$DEST_ROW" '$2 == "AXRow" && $16 == h { n++ } END { print n + 0 }' "$WORK/window.tsv")"
[ "$DEST_ROW_COUNT" -ge 8 ] || fail "only $DEST_ROW_COUNT rows share the modal height — the sidebar is not one row size"

IN_DOC=0
for size in $DOC_ROWS; do
    awk -v a="$DEST_ROW" -v b="$size" 'BEGIN { exit !(a + 0 == b + 0) }' && IN_DOC=1
done
[ "$IN_DOC" -eq 1 ] \
  || fail "rows rendered ${DEST_ROW}pt, which is not one of DESIGN.md §2's documented sidebar rows ($DOC_ROWS)"
pass "$DEST_ROW_COUNT destination rows share one height, ${DEST_ROW}pt, which §2 documents"

# ---------------------------------------------------------------- A35 · what a screen reader reads

WINDOW_TEXT="$(cut -f4,5,6 "$WORK/window.tsv" | tr '\t' '\n' | grep -v '^$' || true)"

# Destinations are matched as a **prefix**, not exactly, because a row that carries a badge
# announces it as part of one sentence — "Servers, 1 need attention" rather than "Servers" and a
# loose number. That is the point of the label, so the assertion has to allow for it.
for needle in Activity Servers Skills Discover Inbox Evals Cleanup Settings; do
    printf '%s\n' "$WINDOW_TEXT" | grep -qE "^$needle(,|$)" \
      || fail "the accessibility tree does not carry a row for '$needle'"
done
pass "all eight destinations are in the accessibility tree"

for needle in Running Library; do
    printf '%s\n' "$WINDOW_TEXT" | grep -qxF "$needle" \
      || fail "the accessibility tree does not carry the '$needle' group header"
done
pass "both group headers are in the accessibility tree, sentence case"

# A13, rendered: the two badges say what they count, and the two destinations the router serves no
# source for carry none. A number alone would be the thing §6 forbids — a figure with no stated
# provenance — and Skills or Inbox growing one is exactly the drift this catches.
printf '%s\n' "$WINDOW_TEXT" | grep -qE '^Servers, [0-9]+ need attention$' \
  || fail "the Servers badge does not say what it counts"
printf '%s\n' "$WINDOW_TEXT" | grep -qE '^Cleanup, [0-9]+ never used$' \
  || fail "the Cleanup badge does not say what it counts"
pass "both badges announce what they count"

for bare in Skills Inbox; do
    if printf '%s\n' "$WINDOW_TEXT" | grep -qE "^$bare, "; then
        fail "$bare grew a badge, but the router serves no count for it (§6, A13)"
    fi
done
pass "Skills and Inbox carry no badge — the router serves no count for either"

# The readout. Its label is generated from two observed counts, so this matches the shape rather
# than a fixed string — a fixed one would pin the fixture rather than the derivation.
printf '%s\n' "$WINDOW_TEXT" | grep -qE '^[0-9]+ of [0-9]+ declared servers running$' \
  || fail "the readout's accessibility label is not in the tree"
pass "the readout announces its counts as a sentence"

# ---------------------------------------------------------------- A9 · the title names the view

TITLE="$(awk -F'\t' '$1 == 0 { print $4; exit }' "$WORK/window.tsv")"
case "$TITLE" in
    Activity|Servers|Skills|Discover|Inbox|Evals|Cleanup|Settings) ;;
    *) fail "the window title is '$TITLE', which is not a destination name (§3.7 forbids the app's name)" ;;
esac
pass "window title is '$TITLE' — the view, not the app"

echo
echo "the menu bar"

# Open each menu once before walking it.
#
# The app is brought frontmost first, because a menu bar belongs to the *active* application: walked
# while something else is frontmost, this process reports zero menus, which reads as an app that
# declares none rather than as a walk of the wrong thing.
#
# Two more reasons to open them, and the second is the load-bearing one. SwiftUI inserts the items it
# contributes through `CommandGroup` **lazily** — measured here: at launch the File menu's items
# existed and the Edit menu's three did not, so a walk without this step reported a missing reason
# for a command that has one. And a tool tip is only ever reachable by opening the menu anyway, so
# this is also the state a person is actually in when they need to discover why a command is dimmed.
activate_app
for menu in "MCP Router" File Edit View Window Help; do
    osascript -e "tell application \"System Events\" to tell process \"MCPRouter\" to click menu bar item \"$menu\" of menu bar 1" >/dev/null 2>&1 || true
    sleep 0.4
    osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true
    sleep 0.2
done
sleep 0.5

dump_menu

# ---------------------------------------------------------------- A19 · the six menus

# The Apple menu is macOS's and is excluded by name, the same way the Window menu's list of open
# windows is. Six is the count of menus the app is responsible for.
MENUS="$(awk -F'\t' '$1 == 1 && $2 == "AXMenuBarItem" { print $4 }' "$WORK/menu.tsv" | grep -v '^Apple$' || true)"
MENU_COUNT="$(printf '%s\n' "$MENUS" | grep -c . || true)"
[ "$MENU_COUNT" -eq 6 ] || fail "the menu bar carries $MENU_COUNT app menus, expected 6: $(printf '%s ' $MENUS)"
for want in "MCP Router" File Edit View Window Help; do
    printf '%s\n' "$MENUS" | grep -qxF "$want" || fail "the menu bar has no '$want' menu"
done
pass "exactly six app menus: $(printf '%s' "$MENUS" | paste -sd'|' -)"

# Every menu item title, with its menu, its enabled state and its help tag.
#
# The Apple menu is skipped entirely rather than filtered afterwards. It belongs to macOS, its
# contents depend on what is installed and which files the user opened recently — this machine's
# copy listed thirty-odd Recent Items — and none of it is anything this app declares or could.
# Only the **top level** of each menu. The tree is menu bar (0) → menu bar item (1) → menu (2) →
# menu item (3), and anything deeper is a submenu's contents: the Services list, Writing Tools,
# AutoFill, Move & Resize. Forty-four of those turned up on this machine, and none of them is a
# command this app declares — each belongs to its parent item, which is itself in the system list
# below. An inventory of top-level commands compared against every descendant would fail forever
# for a reason that has nothing to do with the app.
awk -F'\t' '
  $2 == "AXMenuBarItem" { menu = $4; skip = (menu == "Apple"); next }
  skip { next }
  $1 == 3 && $2 == "AXMenuItem" && $4 != "" { print menu "\t" $4 "\t" $8 "\t" $7 "\t" $10 "\t" $11 }
' "$WORK/menu.tsv" > "$WORK/items.tsv"
[ -s "$WORK/items.tsv" ] || blocked "the menu walk found no items"

# ---------------------------------------------------------------- A19 · completeness, both ways

# The inventory, parsed out of the spec — the same external oracle the unit suite uses, so the
# running app and the unit test are held to one list rather than to each other.
python3 - "$ROOT/planning/specs/spec-M1.md" > "$WORK/inventory.tsv" <<'PY'
import sys, re
text = open(sys.argv[1]).read()
start = text.index("## The command inventory")
end = text.index("\n## ", start + 10)
for line in text[start:end].splitlines():
    line = line.strip()
    if not line.startswith("|"):
        continue
    cells = [c.strip() for c in line.split("|")[1:-1]]
    if len(cells) != 4 or cells[0] in ("Menu", "---") or set(cells[0]) <= set("-"):
        continue
    menu, title, shortcut, availability = cells
    print("\t".join([menu, title, "-" if shortcut == "—" else shortcut, availability]))
PY
INVENTORY_ROWS="$(grep -c . "$WORK/inventory.tsv" || true)"
[ "$INVENTORY_ROWS" -ge 30 ] || blocked "parsed only $INVENTORY_ROWS inventory rows — the oracle did not load"
echo "  inventory: $INVENTORY_ROWS commands"

MISSING=0
while IFS=$'\t' read -r menu title shortcut availability; do
    [ -n "$title" ] || continue
    if ! awk -F'\t' -v m="$menu" -v t="$title" '$1 == m && $2 == t { found = 1 } END { exit !found }' "$WORK/items.tsv"; then
        echo "  missing: $menu / $title" >&2
        MISSING=$((MISSING + 1))
    fi
done < "$WORK/inventory.tsv"
[ "$MISSING" -eq 0 ] || fail "$MISSING inventoried command(s) are not in the running menu bar"
pass "every one of the $INVENTORY_ROWS inventoried commands is in the menu bar"

# The other direction, over the commands the **app declares**. macOS contributes a great many items
# the inventory does not list; each is excluded by name here rather than by a tolerance, so adding
# one to the app is a failure and adding one to macOS is a one-line, visible edit.
cat > "$WORK/system-items.txt" <<'EOF'
Services
Quit and Keep Windows
Close All
Delete
Writing Tools
AutoFill
Start Dictation
Emoji & Symbols
Show Tab Bar
Show All Tabs
Enter Full Screen
Minimize All
Zoom All
Fill
Center
Move & Resize
Full Screen Tile
Remove Window from Set
Arrange in Front
Show Previous Tab
Show Next Tab
Move Tab to New Window
Merge All Windows
Design system
EOF

EXTRAS=0
while IFS=$'\t' read -r menu title enabled help cmdchar cmdmods; do
    [ -n "$title" ] || continue
    grep -qxF "$title" "$WORK/system-items.txt" && continue
    # macOS's display-move commands name the machine's own monitors — "Move to Built-in Retina
    # Display", "Move to DELL U2720Q" — so they cannot be listed literally without pinning the gate
    # to one Mac. A pattern, kept deliberately narrow, is the only portable way to name them.
    case "$title" in
        "Move to "*) continue ;;
    esac
    awk -F'\t' -v m="$menu" -v t="$title" '$1 == m && $2 == t { found = 1 } END { exit !found }' "$WORK/inventory.tsv" && continue
    # The Window menu additionally lists every open window under its own title, which is macOS
    # naming a window rather than the app declaring a command.
    if [ "$menu" = "Window" ] && printf '%s\n' "$WINDOW_TEXT" | grep -qxF "$title"; then continue; fi
    if [ "$menu" = "Window" ] && [ "$title" = "$TITLE" ]; then continue; fi
    echo "  unlisted: $menu / $title" >&2
    EXTRAS=$((EXTRAS + 1))
done < "$WORK/items.tsv"
[ "$EXTRAS" -eq 0 ] || fail "$EXTRAS menu item(s) are in the menu bar and in neither the inventory nor the named system list"
pass "no command in the menu bar is unaccounted for"

# ---------------------------------------------------------------- A20 · the shortcuts actually bind

# AXMenuItemCmdModifiers is a bitmask: 1 shift, 2 option, 4 control, 8 "no command key".
# Decoding it is what turns "the item exists" into "the item carries the chord the document states".
SHORTCUT_FAILS=0
SHORTCUT_CHECKED=0
while IFS=$'\t' read -r menu title shortcut availability; do
    [ "$shortcut" = "-" ] && continue
    line="$(awk -F'\t' -v m="$menu" -v t="$title" '$1 == m && $2 == t { print; exit }' "$WORK/items.tsv")"
    if [ -z "$line" ]; then
        echo "  $menu / $title: not in the menu bar at all" >&2
        SHORTCUT_FAILS=$((SHORTCUT_FAILS + 1))
        continue
    fi
    char="$(printf '%s' "$line" | cut -f5)"
    mods="$(printf '%s' "$line" | cut -f6)"
    [ -n "$mods" ] || mods=0

    # A key with no printable glyph reports a **control character** rather than nothing: ⌫ comes
    # back as U+0008. That is non-empty, so an `-z` test on it silently reads as "some key I cannot
    # name" and the comparison fails against a chord that is in fact correctly bound. Stripping the
    # control range first is what turns it back into the absence it means.
    char="$(printf '%s' "$char" | tr -d '[:cntrl:]')"

    # AXMenuItemCmdModifiers is a bitmask: 1 shift, 2 option, 4 control, 8 "no command key".
    # Rebuilt in Apple's own display order, ⌃⌥⇧⌘, so the string can be compared to the document's.
    got=""
    if [ $(( mods & 4 )) -ne 0 ]; then got="${got}⌃"; fi
    if [ $(( mods & 2 )) -ne 0 ]; then got="${got}⌥"; fi
    if [ $(( mods & 1 )) -ne 0 ]; then got="${got}⇧"; fi
    if [ $(( mods & 8 )) -eq 0 ]; then got="${got}⌘"; fi

    # ⌫ has no printable command character, so AX reports an empty one. The key is still bound —
    # the modifiers came back — and the glyph the document writes is the one macOS draws.
    if [ -z "$char" ] && [ "$shortcut" = "⌘⌫" ]; then
        char="⌫"
    fi
    got="${got}${char}"

    SHORTCUT_CHECKED=$((SHORTCUT_CHECKED + 1))
    if [ "$got" != "$shortcut" ]; then
        echo "  $menu / $title: menu bar says '$got', the inventory says '$shortcut'" >&2
        SHORTCUT_FAILS=$((SHORTCUT_FAILS + 1))
    fi
done < "$WORK/inventory.tsv"
[ "$SHORTCUT_FAILS" -eq 0 ] || fail "$SHORTCUT_FAILS shortcut(s) are not bound as the inventory states"
[ "$SHORTCUT_CHECKED" -ge 20 ] || fail "only $SHORTCUT_CHECKED shortcuts were checked — the oracle looks wrong"
pass "all $SHORTCUT_CHECKED inventoried shortcuts are bound with the key and modifiers stated"

# ---------------------------------------------------------------- A22 · disabled, and saying why

REASON="$(grep -oE '"This part of the app isn.t built yet\."' \
  "$APP_DIR/Sources/MCPRouterKit/Shell/MenuCommand.swift" | head -1 | tr -d '"')"
[ -n "$REASON" ] || blocked "could not read the surfaceAbsent reason out of MenuCommand.swift"

DISABLED_CHECKED=0
while IFS=$'\t' read -r menu title shortcut availability; do
    [ "$availability" = "surfaceAbsent" ] || continue
    [ -n "$title" ] || continue
    line="$(awk -F'\t' -v m="$menu" -v t="$title" '$1 == m && $2 == t { print; exit }' "$WORK/items.tsv")"
    [ -n "$line" ] || fail "$menu / $title is disabled in the spec and absent from the menu bar — §3.4 forbids hiding it"
    enabled="$(printf '%s' "$line" | cut -f3)"
    help="$(printf '%s' "$line" | cut -f4)"
    [ "$enabled" = "0" ] || fail "$menu / $title reports itself enabled, but its surface does not exist"
    [ "$help" = "$REASON" ] || fail "$menu / $title carries no discoverable reason (AXHelp was '$help')"
    DISABLED_CHECKED=$((DISABLED_CHECKED + 1))
done < "$WORK/inventory.tsv"
[ "$DISABLED_CHECKED" -ge 7 ] || fail "only $DISABLED_CHECKED disabled commands were checked — the oracle looks wrong"
pass "$DISABLED_CHECKED disabled commands are present, report themselves disabled, and carry their reason"

# ---------------------------------------------------------------- A23 · ⌘-digit moves the selection

echo
echo "the keyboard"


# Sends ⌘<key> and asserts both halves of A23: the row reports itself selected, and the title
# follows it.
#
# Retried up to three times, and the reason is contention rather than flakiness in the app. Another
# process can take focus back in the gap between `activate_app` confirming frontmost and the
# keystroke being delivered — a terminal printing output is enough — and the key then lands
# somewhere else entirely. Re-activating and sending again costs a second; accepting the first
# miss would report a correctly-bound shortcut as unbound. A shortcut that is genuinely not wired
# up fails all three attempts, so nothing is being papered over.
#
# The third argument is a physical key code, used on the final attempt only. `keystroke ","` is the
# layout-independent way to ask for a character and it is what should work — but measured on this
# machine 2026-08-14, ⌘, delivered that way reached the app **intermittently** while the very same
# menu item, invoked through the accessibility API, selected Settings every time and reported
# `AXMenuItemCmdChar` of "," with Command. So the binding is right and the *send* is what is
# unreliable, for punctuation specifically; the digits never missed. Falling back to the key code
# on the last attempt distinguishes an unbound shortcut from an undelivered keystroke, which is the
# distinction this gate exists to make. A genuinely unbound shortcut still fails all three.
select_and_check() {
    local key="$1" want="$2" code="${3:-}" attempt title selected
    for attempt in 1 2 3; do
        activate_app
        if [ "$attempt" = 3 ] && [ -n "$code" ]; then
            osascript -e "tell application \"System Events\" to tell process \"MCPRouter\" to key code $code using command down" >/dev/null 2>&1 \
              || blocked "could not send key code $code"
        else
            osascript -e "tell application \"System Events\" to tell process \"MCPRouter\" to keystroke \"$key\" using command down" >/dev/null 2>&1 \
              || blocked "could not send ⌘$key"
        fi
        sleep 1.5
        dump_window
        title="$(awk -F'\t' '$1 == 0 { print $4; exit }' "$WORK/window.tsv")"
        # The selected row, from the tree's own selected flag rather than from the title — A23 is
        # explicit that the row must report itself selected and the title must follow, not either
        # alone.
        selected="$(awk -F'\t' '$2 == "AXRow" && $9 == "1" { print NR; exit }' "$WORK/window.tsv")"
        if [ "$title" = "$want" ]; then
            [ -n "$selected" ] || fail "⌘$key changed the title but no sidebar row reports itself selected"
            pass "⌘$key selected $want — the row reports itself selected and the title follows"
            return 0
        fi
    done
    fail "⌘$key left the title '$title', expected '$want' — after 3 attempts with the app frontmost"
}

select_and_check 2 Servers
select_and_check 4 Discover
# ⌘, is Settings, which is a destination in this build rather than a sheet — so it goes through the
# same helper as the digits and is held to the same two-part assertion. It previously had a weaker
# block of its own that checked only the window title, which would have passed on a shell that
# moved the title without moving the selection. 43 is the comma's key code.
select_and_check "," Settings 43

select_and_check 1 Activity

# ---------------------------------------------------------------- A21 · the three bare keys arrive

# The probe is a Debug-only surface in the content zone that records the last bare key it received.
# It is what makes A21's claim checkable and honest: the shell declares no shortcut for these three
# and installs no handler, and a focused surface in the content zone receives all of them.
PROBE_ID="mcprouter-key-probe"
probe_value() {
    dump_window
    awk -F'\t' -v id="$PROBE_ID" '$12 == id || $6 == id { print $5; exit }' "$WORK/window.tsv"
}
PROBE_POS="$(awk -F'\t' -v id="$PROBE_ID" '$12 == id || $6 == id { print $13 " " $14 " " $15 " " $16; exit }' "$WORK/window.tsv")"
[ -n "$PROBE_POS" ] || fail "the Debug key probe is not in the content zone — A21 has no test surface"

# Click it so it takes focus, then send each key and read back what arrived.
#
# The app is brought frontmost first: `click at` is a *screen* coordinate, so anything overlapping
# the window would receive the click instead, and the bare keys that follow are unmodified — they
# would land silently in whatever app did have focus.
#
# The position is re-read here rather than reused from the walk above, because the ⌘-shortcut
# assertions changed the destination and the content zone was rebuilt underneath it.
activate_app
dump_window
PROBE_POS="$(awk -F'\t' -v id="$PROBE_ID" '$12 == id || $6 == id { print $13 " " $14 " " $15 " " $16; exit }' "$WORK/window.tsv")"
[ -n "$PROBE_POS" ] || fail "the Debug key probe left the content zone after the keyboard assertions"
set -- $PROBE_POS
CLICK_X=$(awk -v x="$1" -v w="$3" 'BEGIN { printf "%d", x + w / 2 }')
CLICK_Y=$(awk -v y="$2" -v h="$4" 'BEGIN { printf "%d", y + h / 2 }')
osascript -e "tell application \"System Events\" to click at {$CLICK_X, $CLICK_Y}" >/dev/null 2>&1 || true
sleep 1

# Focus is asserted before any key is sent, so that "the shell swallowed it" is only ever reported
# when the key really was delivered to a focused surface. Without this, a click that missed and a
# shell that ate the key produce the same message and point at the wrong one.
probe_focused() {
    dump_window
    awk -F'\t' -v id="$PROBE_ID" '$12 == id || $6 == id { print $17; exit }' "$WORK/window.tsv"
}
[ "$(probe_focused)" = "1" ] \
  || fail "the key probe did not take focus when clicked — A21 cannot be exercised, and nothing about the shell has been shown either way"
pass "the key probe holds keyboard focus in the content zone"

# Each key is sent with the app re-activated and the probe's focus re-checked first, and retried up
# to three times, for the same contention reason as the ⌘-digit assertions: another process taking
# focus back mid-sequence sends the key somewhere else, and the probe simply keeps reporting the
# previous one. A key the shell genuinely swallows fails all three attempts.
send_bare_key() {
    local code="$1" want="$2" attempt got=""
    for attempt in 1 2 3; do
        activate_app
        if [ "$(probe_focused)" != "1" ]; then
            osascript -e "tell application \"System Events\" to click at {$CLICK_X, $CLICK_Y}" >/dev/null 2>&1 || true
            sleep 0.5
        fi
        osascript -e "tell application \"System Events\" to key code $code" >/dev/null 2>&1 \
          || blocked "could not send key code $code"
        sleep 1
        got="$(probe_value)"
        if [ "$got" = "$want" ]; then
            pass "$want reached a focused surface in the content zone"
            return 0
        fi
    done
    fail "the content zone did not receive $want (the probe reads '$got') — the shell swallowed it"
}

send_bare_key 49 Space
send_bare_key 36 Return
send_bare_key 53 Esc

# ---------------------------------------------------------------- A34 · the scroll edge, rendered

echo
echo "the scroll edge"

window_id() {
    cat > "$WORK/winid.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
for w in (info as? [[String: Any]]) ?? [] {
    let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
    guard owner == "MCP Router" || owner == "MCPRouter",
          (w[kCGWindowLayer as String] as? Int) == 0,
          let bounds = w[kCGWindowBounds as String] as? [String: Any],
          let height = bounds["Height"] as? Double, height > 100,
          let id = w[kCGWindowNumber as String] as? Int else { continue }
    let name = (w[kCGWindowName as String] as? String) ?? ""
    if CommandLine.arguments.count > 1, !CommandLine.arguments[1].isEmpty {
        guard name == CommandLine.arguments[1] else { continue }
    }
    print(id); exit(0)
}
exit(1)
SWIFT
    swift "$WORK/winid.swift" "${1:-}" 2>/dev/null
}

cat > "$WORK/sample.swift" <<'SWIFT'
import AppKit
let args = CommandLine.arguments
guard args.count >= 4, let img = NSImage(contentsOfFile: args[1]),
      let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let x = Int(args[2]), let y = Int(args[3]) else { exit(2) }
guard x < rep.pixelsWide, y < rep.pixelsHigh, let c = rep.colorAt(x: x, y: y) else { exit(2) }
print(String(format: "#%02X%02X%02X",
             Int((c.redComponent * 255).rounded()),
             Int((c.greenComponent * 255).rounded()),
             Int((c.blueComponent * 255).rounded())))
SWIFT

# The separator is a hairline and is deliberately hidden from the accessibility tree — it repeats
# nothing a screen reader needs. So this is a **rendered** assertion rather than a derived one: the
# strip of pixels directly under the toolbar is sampled before and after a real scroll, and the two
# must differ. Comparing before with after rather than against a fixed colour is what keeps it from
# pinning an alpha blend that the appearance is free to change.
dump_window
CONTENT_X="$(awk -F'\t' '$2 == "AXScrollArea" { print $13 }' "$WORK/window.tsv" | tail -1)"
CONTENT_Y="$(awk -F'\t' '$2 == "AXScrollArea" { print $14 }' "$WORK/window.tsv" | tail -1)"
[ -n "$CONTENT_X" ] || fail "no content scroll area to scroll"

WIN_ID="$(window_id "" || true)"
[ -n "$WIN_ID" ] || blocked "could not resolve the window id — Screen Recording permission?"
WIN_X="$(awk -F'\t' '$1 == 0 { print $13; exit }' "$WORK/window.tsv")"
WIN_Y="$(awk -F'\t' '$1 == 0 { print $14; exit }' "$WORK/window.tsv")"

# Image coordinates are 2x on a Retina display and relative to the window's own backing store.
EDGE_X=$(awk -v cx="$CONTENT_X" -v wx="$WIN_X" 'BEGIN { printf "%d", (cx - wx + 120) * 2 }')
EDGE_Y=$(awk -v cy="$CONTENT_Y" -v wy="$WIN_Y" 'BEGIN { printf "%d", (cy - wy) * 2 + 1 }')

screencapture -o -x -l "$WIN_ID" "$WORK/before.png"
[ -s "$WORK/before.png" ] || blocked "screencapture produced no image — grant Screen Recording"
BEFORE="$(swift "$WORK/sample.swift" "$WORK/before.png" "$EDGE_X" "$EDGE_Y" 2>/dev/null || true)"
[ -n "$BEFORE" ] || blocked "could not sample the scroll edge before scrolling"

CONTENT_W="$(awk -F'\t' '$2 == "AXScrollArea" { print $15 }' "$WORK/window.tsv" | tail -1)"
CONTENT_H="$(awk -F'\t' '$2 == "AXScrollArea" { print $16 }' "$WORK/window.tsv" | tail -1)"

# A real scroll-wheel event, because neither of the obvious spellings works here.
#
# `System Events`' own `scroll` verb does not exist in this version — it raises -1708, "Can't
# continue scroll" — and the keyboard fallback is worse than it looks: Page Down is delivered to
# whatever holds keyboard focus, which after the A21 assertions is the key probe, so the scroll view
# never moved. Both failures are silent and both render as "the separator never appeared", which
# blames the app for a scroll that was never delivered.
#
# So the event is posted directly: warp the cursor over the content and post scroll-wheel units at
# it, which is what a trackpad does and what the scroll view is actually listening for.
cat > "$WORK/scroll.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let a = CommandLine.arguments
guard a.count >= 4, let x = Double(a[1]), let y = Double(a[2]), let lines = Int(a[3]) else { exit(2) }
CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
usleep(250_000)
guard let source = CGEventSource(stateID: .hidSystemState) else { exit(2) }
// Negative wheel1 scrolls the content downward, which is the direction that moves a view off its
// resting offset. Posted a few units at a time so the scroll view sees motion rather than a jump.
for _ in 0 ..< 6 {
    guard let event = CGEvent(
        scrollWheelEvent2Source: source, units: .line, wheelCount: 1,
        wheel1: Int32(lines), wheel2: 0, wheel3: 0
    ) else { exit(2) }
    event.post(tap: .cghidEventTap)
    usleep(40_000)
}
SWIFT

SCROLL_X=$(awk -v x="$CONTENT_X" -v w="$CONTENT_W" 'BEGIN { printf "%d", x + w / 2 }')
SCROLL_Y=$(awk -v y="$CONTENT_Y" -v h="$CONTENT_H" 'BEGIN { printf "%d", y + h / 2 }')
activate_app
swift "$WORK/scroll.swift" "$SCROLL_X" "$SCROLL_Y" -3 2>/dev/null \
  || blocked "could not post a scroll-wheel event — Accessibility or Input Monitoring may be denied"
sleep 1.5

screencapture -o -x -l "$WIN_ID" "$WORK/after.png"
AFTER="$(swift "$WORK/sample.swift" "$WORK/after.png" "$EDGE_X" "$EDGE_Y" 2>/dev/null || true)"
[ -n "$AFTER" ] || blocked "could not sample the scroll edge after scrolling"

if [ "$BEFORE" = "$AFTER" ]; then
    fail "the strip under the toolbar rendered $BEFORE both before and after a scroll — no separator appeared"
fi
pass "the scroll edge rendered $BEFORE at rest and $AFTER once scrolled"

# ---------------------------------------------------------------- A32, A33 · restoration

echo
echo "restoration across a relaunch"

# Move and resize by a real amount, select a destination that is not the default, then quit and
# relaunch. Asserting the *frame*, not that an autosave name is set: a name with nothing behind it
# is exactly the failure this clause exists to catch.
osascript -e 'tell application "System Events" to tell process "MCPRouter" to set position of window 1 to {180, 140}' >/dev/null 2>&1 || true
osascript -e 'tell application "System Events" to tell process "MCPRouter" to set size of window 1 to {980, 620}' >/dev/null 2>&1 || true
sleep 1
activate_app
osascript -e 'tell application "System Events" to tell process "MCPRouter" to keystroke "6" using command down' >/dev/null 2>&1 || true
sleep 2

dump_window
WANT_TITLE="$(awk -F'\t' '$1 == 0 { print $4; exit }' "$WORK/window.tsv")"
WANT_FRAME="$(awk -F'\t' '$1 == 0 { print $13 "," $14 "," $15 "," $16; exit }' "$WORK/window.tsv")"
[ "$WANT_TITLE" = "Evals" ] || fail "⌘6 did not select Evals (title is '$WANT_TITLE')"
echo "  before quit: $WANT_TITLE at $WANT_FRAME"

osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
sleep 3
launch_app
sleep 3
dump_window

GOT_TITLE="$(awk -F'\t' '$1 == 0 { print $4; exit }' "$WORK/window.tsv")"
GOT_FRAME="$(awk -F'\t' '$1 == 0 { print $13 "," $14 "," $15 "," $16; exit }' "$WORK/window.tsv")"
echo "  after relaunch: $GOT_TITLE at $GOT_FRAME"

[ "$GOT_TITLE" = "$WANT_TITLE" ] \
  || fail "the selected destination did not survive the relaunch: '$GOT_TITLE', expected '$WANT_TITLE'"
pass "the selected destination survived quit and relaunch ($GOT_TITLE)"

[ "$GOT_FRAME" = "$WANT_FRAME" ] \
  || fail "the window frame did not survive the relaunch: $GOT_FRAME, expected $WANT_FRAME"
pass "the window frame survived quit and relaunch ($GOT_FRAME)"

# ---------------------------------------------------------------- the scaffold cannot ship silently

echo
echo "the scaffold is bounded by what has shipped"

# The orchestrator's condition, enforced at the binary rather than promised in a comment: the
# placeholder sentence may be in a Release build only while a destination still has no board. When
# the last board lands, `BoardRegistry.installed` covers every destination and this flips — a
# Release build still carrying the sentence fails here.
SENTINEL="$(grep -oE 'sentinel = "[^"]+"' \
  "$APP_DIR/Sources/MCPRouterUI/Shell/ScaffoldPane.swift" | sed -E 's/.*"(.*)"/\1/')"
[ -n "$SENTINEL" ] || blocked "could not read the scaffold sentinel out of ScaffoldPane.swift"

INSTALLED="$(sed -n '/installed: Set<Destination>/p' \
  "$APP_DIR/Sources/MCPRouterUI/Shell/ScaffoldPane.swift")"
case "$INSTALLED" in
    *"= []"*) SCAFFOLDS_REMAIN=1 ;;
    *)        SCAFFOLDS_REMAIN=0 ;;
esac

bundle_contains() {
    local bundle="$1" needle="$2" f
    while IFS= read -r f; do
        if LC_ALL=C grep -qaF -- "$needle" "$f" 2>/dev/null; then return 0; fi
    done < <(find "$bundle" -type f -perm +111)
    return 1
}

[ -d "$REL_APP" ] || blocked "no Release build at $REL_APP — run 'make build-mac-release' first"

if [ "$SCAFFOLDS_REMAIN" -eq 1 ]; then
    bundle_contains "$REL_APP" "$SENTINEL" \
      || fail "destinations are still scaffolded but the Release bundle does not carry '$SENTINEL' — the placeholder is not what ships"
    pass "boards remain unbuilt, and Release carries the placeholder honestly"
else
    if bundle_contains "$REL_APP" "$SENTINEL"; then
        fail "every destination has a board, but the Release bundle still contains '$SENTINEL' — the scaffold outlived the surface it stood in for"
    fi
    pass "every board has shipped and the placeholder is gone from Release"
fi

# The Debug-only key probe must not ship, for the same reason the design gallery must not.
if bundle_contains "$REL_APP" "$PROBE_ID"; then
    fail "the Release bundle contains '$PROBE_ID' — a Debug test surface is shipping"
fi
pass "the Debug key probe is absent from Release"

osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true

echo
echo "acceptance: the Mac shell measures ${GOT_SIDEBAR}/${GOT_TOOLBAR}/${GOT_TITLEBAR}, carries its"
echo "acceptance: $INVENTORY_ROWS commands with their shortcuts and reasons, routes ⌘-digits and the"
echo "acceptance: three bare keys, shows its scroll edge, and restores its destination and frame."
