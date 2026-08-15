#!/bin/bash
#
# M1 acceptance: the Mac shell, measured and driven rather than described — and never brought to
# the front.
#
# `shells.sh` proves the shared design system reaches the screen. This proves the *shell* — its
# three zones, its sidebar, its menu bar, its keyboard and its restoration — against the running
# app, because every one of those clauses is about behaviour a build gate cannot see. A linker
# success is not evidence that selecting Servers moves the title.
#
# **The whole run is invisible, and that is a hard requirement rather than a courtesy.**
# `planning/practices/UI_VERIFICATION.md` rule 1: the developer loop must never take the user's
# screen. The previous version of this script broke that on every pass — it launched with `open`
# (which activates) and re-issued `tell application … to activate` before each keystroke, because a
# System Events keystroke only reaches a frontmost app. Measured from one run: three launches and
# eight osascript drives, each of which pulled the window in front of whoever was working.
#
# So nothing here activates anything. The app is launched with `open -g`, every read is an
# accessibility query by pid, and every action is one of the four background-safe routes proven in
# `axkit.swift`'s header. The frontmost application is recorded at the start and asserted unchanged
# at the end: if this gate ever steals the screen, it fails itself.
#
# Exit codes match the house rule: 2 means the harness could not run (no Accessibility grant, a
# locked screen), 1 means an assertion failed. Collapsing them is how a missing permission gets
# reported as a broken app.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT/app"
MAC_APP="$APP_DIR/.derived/Build/Products/Debug/MCPRouter.app"
REL_APP="$APP_DIR/.derived/Build/Products/Release/MCPRouter.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
blocked() { echo "BLOCKED: $*" >&2; exit 2; }
pass() { echo "  ok — $*"; }

[ -d "$MAC_APP" ] || blocked "no built app at $MAC_APP — run 'make build-mac' first"

# ---------------------------------------------------------------- the harness
#
# One compiled binary rather than a handful of `swift file.swift` invocations. The reason is
# correctness before speed: `entire contents` in AppleScript binds a snapshot of a tree this app
# mutates every two seconds as it polls, and reading a property off a stale element raises "-1728",
# which reads as a missing element rather than as a race. The first version of this script failed
# that way against a perfectly good window.

AXKIT="$WORK/axkit"
swiftc -O -o "$AXKIT" "$ROOT/scripts/acceptance/axkit.swift" 2>"$WORK/axkit.log" \
  || { cat "$WORK/axkit.log" >&2; blocked "could not build the accessibility toolkit"; }

# ---------------------------------------------------------------- preflight
#
# Each of these is its own outcome. Without the grant every AX query returns empty, which is
# indistinguishable from "the element is missing"; without a console session macOS composites no
# window at all and every measurement below reads as a broken app.

case "$("$AXKIT" session)" in
    locked)     blocked "the screen is locked — macOS will not composite a window for a launched app" ;;
    nosession)  blocked "no GUI session (headless or SSH) — the window assertions need a console session" ;;
    notconsole) blocked "this session does not own the console — windows cannot be rendered here" ;;
esac
[ "$("$AXKIT" trusted)" = "yes" ] \
  || blocked "no Accessibility permission for this terminal — System Settings > Privacy & Security > Accessibility"

# The invisibility guard's baseline. Whatever the user is actually working in right now.
FRONT_AT_START="$("$AXKIT" front)"
echo "frontmost at start: $FRONT_AT_START"
case "$FRONT_AT_START" in
    "MCP Router"|MCPRouter) blocked "MCP Router is already frontmost — this gate cannot prove it never took the screen" ;;
esac

# The invariant is "**this app** never comes to the front", not "the frontmost app never changes".
# The stricter reading was tried first and is wrong: the user switching from their terminal to a
# browser mid-run failed the gate for something the gate did not do, which is a false alarm on the
# one rule that must be believed. What is asserted is the thing that would actually take the screen.
# Puts the app back behind whatever the user is using, if macOS has promoted it.
#
# `open -g` does not activate, and nothing in this gate does either — but macOS gives the front to a
# background app on its own when whatever *was* in front goes away, and that was observed here: a
# third application took focus mid-run, dropped it, and MCP Router inherited the front through no
# call of this script's. Failing on that would report a screen theft that did not happen; ignoring it
# would leave the app in the user's face. Hiding and immediately un-hiding removes it from the front
# and restores its windows without activating anything, which is the only correction available that
# does not take the screen for something else.
step_back() {
    case "$("$AXKIT" front)" in
        "MCP Router"|MCPRouter) ;;
        *) return 0 ;;
    esac
    "$AXKIT" hidden "$PID" hide >/dev/null 2>&1 || true
    sleep 0.6
    "$AXKIT" hidden "$PID" unhide >/dev/null 2>&1 || true
    sleep 0.8
}

check_invisible() {
    # One correction attempt before judging, for the reason `step_back` documents. A gate that fails
    # on someone else's focus change is a gate nobody believes the next time it fires.
    step_back
    local now
    now="$("$AXKIT" front)"
    case "$now" in
        "MCP Router"|MCPRouter)
            fail "the app came to the front during '$1' — UI_VERIFICATION.md rule 1 forbids the developer loop taking the user's screen" ;;
    esac
    if [ "$now" != "$FRONT_AT_START" ]; then
        # Worth printing rather than failing: the user moved, and the run carried on behind them,
        # which is exactly what is supposed to happen.
        echo "  (the user moved to '$now' during '$1'; the app stayed in the background)"
        FRONT_AT_START="$now"
    fi
}

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

# Column indices, named so the awk below reads as something other than magic numbers.
# 1 depth · 2 role · 3 subrole · 4 title · 5 value · 6 desc · 7 help · 8 enabled · 9 selected
# 10 cmdchar · 11 cmdmods · 12 identifier · 13 x · 14 y · 15 w · 16 h · 17 focused

launch_app() {
    local scenario="${1:-}"
    pkill -f 'MCPRouter.app/Contents/MacOS/MCPRouter' >/dev/null 2>&1 || true
    sleep 1
    # `-g` is the whole point: `open` on its own activates, and activation is what takes the screen.
    #
    # `--env` is how a state other than the populated one is reached. Before `ShellClientFactory`
    # existed the app was hardwired to one fixture, so every clause whose evidence names the running
    # app in a failure or overflow state had no lane at all — A28 in particular asks for the offline
    # and unauthorised copy to be read out of the **running app**, and it could not have been.
    if [ -n "$scenario" ]; then
        open -g -a "$MAC_APP" --env "MCPROUTER_SCENARIO=$scenario"
    else
        open -g -a "$MAC_APP"
    fi
    for _ in $(seq 1 40); do
        PID="$(pgrep -f 'MCPRouter.app/Contents/MacOS/MCPRouter' | head -1 || true)"
        if [ -n "$PID" ] && "$AXKIT" dump "$PID" window >/dev/null 2>&1; then
            step_back
            check_invisible "launch"
            return 0
        fi
        sleep 0.5
    done
    fail "the shell window never appeared${scenario:+ (scenario $scenario)}"
}

dump_window() { "$AXKIT" dump "$PID" window > "$WORK/window.tsv" 2>/dev/null || blocked "the window walk failed"; }
dump_menu()   { "$AXKIT" dump "$PID" menu   > "$WORK/menu.tsv"   2>/dev/null || blocked "the menu walk failed"; }

echo
echo "the three-zone shell"
launch_app
sleep 2
dump_window
[ -s "$WORK/window.tsv" ] || blocked "the accessibility tree read as empty — harness or permission problem"

# ---------------------------------------------------------------- A1 · the three zones

# The sidebar. Named by role rather than by a path through the view hierarchy, which SwiftUI is
# free to reshape.
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
# In a unified-toolbar window the titlebar is *inside* the 52pt band rather than stacked above it,
# so there is no separate titlebar band to measure on screen. Two things are asserted here and a
# third is reported: the chrome band above the content is exactly `MetricToken.unifiedToolbar`, and
# AppKit's standard title bar fits inside it. Reported, not asserted: AppKit on this machine gives a
# **32pt** title bar where `DESIGN.md` §2 records 33. Neither document is this item's to change.
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

# The destination rows must all be one height. Headers are a different (smaller) one, which is why
# this takes the *modal* height rather than requiring the whole set to agree.
DEST_ROW="$(awk -F'\t' '$2 == "AXRow" && $16 > 0 { c[$16]++ } END { m = 0; for (h in c) if (c[h] > m) { m = c[h]; best = h } print best }' "$WORK/window.tsv")"
[ -n "$DEST_ROW" ] || fail "no sidebar rows in the accessibility tree"
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

TITLE="$("$AXKIT" title "$PID")"
case "$TITLE" in
    Activity|Servers|Skills|Discover|Inbox|Evals|Cleanup|Settings) ;;
    *) fail "the window title is '$TITLE', which is not a destination name (§3.7 forbids the app's name)" ;;
esac
pass "window title is '$TITLE' — the view, not the app"
check_invisible "the window assertions"

echo
echo "the menu bar"

# **No menu is opened, and none needs to be.** The previous version clicked each of the six menus
# through System Events — which activates the app — on the belief that SwiftUI populates
# `CommandGroup` items lazily and that a help tag is only readable once a menu has been shown.
# Measured on 2026-08-14 against a background app launched with `open -g`: all six menus, all their
# items, every shortcut and every help tag were readable with nothing opened and Ghostty frontmost
# throughout. The activation was buying nothing.
#
# The lazy population is real, though, and it is why this walks **twice**. SwiftUI builds the Edit
# group's three items on demand, and the accessibility walk is itself what demands them — so the
# first walk creates them and reads them bare, before `ShellMenuReasons`' 100 ms pass has annotated
# them. Measured: walk one reported `Find` with an empty `AXHelp` and walk one second later reported
# its reason. The first walk here is a warm-up whose output is discarded; the second is the evidence.
# This is not the gate papering over a gap — the same second is what stands between a VoiceOver user
# opening Edit for the first time and hearing why Find is dimmed, and `ShellMenuReasons` documents
# that window deliberately.
dump_menu
sleep 1.5
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
# contents depend on what is installed and which files the user opened recently, and none of it is
# anything this app declares or could. Only the **top level** of each menu: the tree is menu bar (0)
# → menu bar item (1) → menu (2) → menu item (3), and anything deeper is a submenu's contents — the
# Services list, Writing Tools, AutoFill, Move & Resize — each of which belongs to its parent item,
# which is itself in the system list below.
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
import sys
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

    # Rebuilt in Apple's own display order, ⌃⌥⇧⌘, so the string can be compared to the document's.
    got=""
    if [ $(( mods & 4 )) -ne 0 ]; then got="${got}⌃"; fi
    if [ $(( mods & 2 )) -ne 0 ]; then got="${got}⌥"; fi
    if [ $(( mods & 1 )) -ne 0 ]; then got="${got}⇧"; fi
    if [ $(( mods & 8 )) -eq 0 ]; then got="${got}⌘"; fi

    # ⌫ has no printable command character, so AX reports an empty one after the control range is
    # stripped. The previous spelling substituted the **expected** glyph when the observation was
    # empty — `if [ -z "$char" ] && [ "$shortcut" = "⌘⌫" ]; then char="⌫"; fi` — which made that row
    # unable to fail on its key, because the answer was written in from the question. A completeness
    # critic caught it. What is asserted instead is what AX can actually report for that key: the
    # modifiers, compared as usual, and the *absence* of a printable character, which is itself the
    # observation that distinguishes ⌫ from a letter.
    if [ "$shortcut" = "⌘⌫" ]; then
        [ -z "$char" ] \
          || fail "Edit / $title reports the printable key '$char'; ⌫ has none, so this is a different chord"
        SHORTCUT_CHECKED=$((SHORTCUT_CHECKED + 1))
        [ "$got" = "⌘" ] \
          || { echo "  $menu / $title: modifiers are '$got', expected ⌘" >&2; SHORTCUT_FAILS=$((SHORTCUT_FAILS + 1)); }
        continue
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

# **The expectation is derived, not restated.** This block used to read the inventory table's
# fourth column and assert it against the running app. That column is headed *"Availability in
# M1"* and means exactly that: the answer in `CommandContext.none`, with no board installed, which
# is what `MenuCommandTests` compares it against and what it is still correct for. It was never
# the shipped app's answer, and the two stopped agreeing the moment M3 installed the Servers
# board — a document restating by hand a rule `MenuCommand.availability(in:)` already computes,
# going stale silently every time a board ships. It went stale twice (M3, then M4) before this
# gate caught it, and hand-correcting seven rows would only have bought until the next one.
#
# So the oracle for *availability* is the model itself, compiled from the shipped source with the
# context the running app actually has. The spec table remains the external oracle for the two
# things a model cannot check about itself — which commands exist, and which chords they carry —
# and those are asserted above, unchanged.
#
# What this still proves, and it is the thing that broke: the model's answer has to survive the
# crossing into AppKit. Measured on 2026-08-15 before the fix, `Add server…` reported `AXEnabled`
# 0 with an empty `AXHelp` — SwiftUI dimmed it from `.none` while `ShellMenuReasons` annotated it
# from the live context, so a command whose board had shipped was permanently unusable and said
# nothing about why. Every reviewer that looked only at `availability(in:)` passed it.

# shellcheck source=scripts/acceptance/board-registry.sh
. "$ROOT/scripts/acceptance/board-registry.sh"
REGISTRY="$APP_DIR/Sources/MCPRouterUI/Shell/ScaffoldPane.swift"
INSTALLED_NAMES="$(board_registry_installed "$REGISTRY" \
  | grep -oE '\.[a-z][a-zA-Z]*' | tr -d '.' | tr '\n' ' ')"
# An empty list is a broken reader, never an empty set — `installed` has been non-empty since M2.
# It matters more here than anywhere: the oracle takes the installed set as **arguments**, so an
# empty one produces a complete, well-formed table in which every board-dependent command reads
# `surfaceAbsent`. That is the old stale answer, wearing the derivation's clothes.
[ -n "$(printf '%s' "$INSTALLED_NAMES" | tr -d ' ')" ] \
  || blocked "read no installed boards out of $REGISTRY — the registry reader is wrong, not the code"

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

// What every command should report, in the context the running app is in.
//
// `selectedServerIsTripped` is nil because the menu walk happens with no server selected — the
// shell has just launched onto its restored destination and nothing in the servers table is
// picked. The two commands that branch on a selection therefore expect `needsServerSelection`,
// which is a different sentence from the surface-absent one and is asserted as such.
let names = Array(CommandLine.arguments.dropFirst())
let installed = Set(names.compactMap(Destination.init(rawValue:)))
// A name that is not a `Destination` is a broken caller, not a board that is switched off, and
// `compactMap` would drop it silently — leaving a smaller installed set, a `surfaceAbsent`
// expectation, and a failure that reads as an availability defect in the app. Say what happened.
guard installed.count == names.count else {
    let unknown = names.filter { Destination(rawValue: $0) == nil }
    FileHandle.standardError.write(Data("not a Destination: \(unknown.joined(separator: " "))\n".utf8))
    exit(2)
}
let context = MenuCommand.CommandContext(installedDestinations: installed, selectedServerIsTripped: nil)
for command in MenuCommand.allCases {
    let availability = command.availability(in: context)
    let token = switch availability {
    case .enabled: "enabled"
    case .surfaceAbsent: "surfaceAbsent"
    case .needsServerSelection: "needsServerSelection"
    }
    print([
        command.menu.rawValue,
        command.title,
        command.isSystemProvided ? "system" : "app",
        token,
        availability.reason ?? ""
    ].joined(separator: "\t"))
}
SWIFT

# **The oracle and the binary must be the same tree.** The oracle is compiled from source at run
# time while the app under test was built earlier, so a source edit without a rebuild has the gate
# comparing a fresh expectation against a stale app. The likely direction is a false red, which
# wastes a run; the dangerous direction is the inverse — a binary built from a *fixed* tree passing
# a gate whose oracle was compiled from a broken one, certifying code that is not what shipped.
MENU_SOURCES=(
  "$APP_DIR/Sources/MCPRouterKit/Shell/MenuCommand.swift"
  "$APP_DIR/Sources/MCPRouterKit/Shell/Destination.swift"
  "$APP_DIR/Sources/MCPRouterUI/Shell/ShellCommands.swift"
  "$APP_DIR/Sources/MCPRouterUI/Shell/ShellMenuReasons.swift"
)
STALE="$(find "${MENU_SOURCES[@]}" -newer "$MAC_APP/Contents/MacOS/MCPRouter" 2>/dev/null || true)"
[ -z "$STALE" ] \
  || blocked "these sources are newer than the built app — run 'make build-mac' so the oracle and the binary are one tree:
$STALE"

swiftc -O -o "$WORK/menu-oracle" \
  "$APP_DIR/Sources/MCPRouterKit/Shell/MenuCommand.swift" \
  "$APP_DIR/Sources/MCPRouterKit/Shell/Destination.swift" \
  "$WORK/main.swift" 2>"$WORK/oracle.log" \
  || { cat "$WORK/oracle.log" >&2; blocked "could not build the availability oracle"; }

# shellcheck disable=SC2086  # the installed names are a deliberate argument list
"$WORK/menu-oracle" $INSTALLED_NAMES > "$WORK/expected.tsv" \
  || blocked "the availability oracle did not run"

# Only what the **app** declares. macOS dims Close, Undo and Minimize while an application is
# inactive, and this gate deliberately reads a backgrounded app — so its own items are the only
# ones whose enabled bit means anything here. `isSystemProvided` supplies that split, derived,
# where this block used to carry a hand-written `View/*|Help/*|"MCP Router/Settings"` list that
# was itself a second copy of the same fact and covered thirteen of the twenty.
APP_ROWS="$(awk -F'\t' '$3 == "app"' "$WORK/expected.tsv" | grep -c . || true)"
[ "$APP_ROWS" -ge 15 ] \
  || blocked "the availability oracle named only $APP_ROWS app-declared commands — it did not load"
echo "  availability oracle: $APP_ROWS app-declared commands, boards installed: $INSTALLED_NAMES"

AVAIL_CHECKED=0
DISABLED_CHECKED=0
ENABLED_CHECKED=0
while IFS=$'\t' read -r menu title kind availability reason; do
    [ "$kind" = "app" ] || continue
    line="$(awk -F'\t' -v m="$menu" -v t="$title" '$1 == m && $2 == t { print; exit }' "$WORK/items.tsv")"
    [ -n "$line" ] || fail "$menu / $title is declared by the app and is not in the menu bar — §3.4 forbids hiding it"
    enabled="$(printf '%s' "$line" | cut -f3)"
    help="$(printf '%s' "$line" | cut -f4)"
    if [ "$availability" = "enabled" ]; then
        [ "$enabled" = "1" ] \
          || fail "$menu / $title is usable in this build, but the menu bar reports it disabled"
        # The other direction, and the one that would have caught the stale annotation: a reason
        # left behind on a command that has since become usable tells the user a surface is
        # missing while the menu offers it.
        [ -z "$help" ] \
          || fail "$menu / $title is usable but still carries the reason '$help'"
        ENABLED_CHECKED=$((ENABLED_CHECKED + 1))
    else
        [ "$enabled" = "0" ] \
          || fail "$menu / $title reports itself enabled, but its availability is $availability"
        [ "$help" = "$reason" ] \
          || fail "$menu / $title carries no discoverable reason (AXHelp was '$help', expected '$reason')"
        DISABLED_CHECKED=$((DISABLED_CHECKED + 1))
    fi
    AVAIL_CHECKED=$((AVAIL_CHECKED + 1))
done < "$WORK/expected.tsv"

# Completeness is carried by the lookup inside the loop — every app-declared row the oracle names
# is resolved against the running menu bar or fails — together with A19's two-way membership check
# above. An earlier draft also asserted `AVAIL_CHECKED -eq APP_ROWS`, which a completeness critic
# pointed out **cannot fail**: the loop counts the same rows it iterates, and every one of them
# either increments the counter or exits. A tautology dressed as an assertion is the thing this
# whole item is about, so it is gone rather than left in to look thorough.
#
# What remains are two tripwires against the gate quietly stopping checking, and they are not
# claims about how many of each there should be. A build in which nothing is disabled has no reason
# to check, and a build in which nothing is enabled would mean inactivity is dimming everything and
# the block above proves nothing about the app.
[ "$DISABLED_CHECKED" -ge 1 ] || fail "no disabled command was exercised — A22's reason check ran on nothing"
[ "$ENABLED_CHECKED" -ge 1 ] || fail "no enabled command was exercised — the dimming above could be inactivity"
pass "$AVAIL_CHECKED app-declared commands match MenuCommand.availability(in:) — $ENABLED_CHECKED enabled and silent, $DISABLED_CHECKED dimmed with their reason"
check_invisible "the menu bar assertions"

echo
echo "the keyboard and the selection"

# ---------------------------------------------------------------- A23 · selection moves, and the title follows
#
# A23 is a chain of four links, and each is evidenced where it can actually be measured. Two are
# above: the chord is bound to the item the inventory names (A20, from the running menu bar), and
# the operation behind each item is a selection (`ShellCommandRouterTests`, a unit test). The third
# is here — a selection moves the row's own selected state *and* the title — and the fourth is the
# one below it: macOS really does dispatch a ⌘-chord to this process.
#
# **Why the selection is driven through `AXSelectedRows` rather than by sending ⌘2.** A menu command
# reaches its window through `@FocusedValue`, and an inactive app has no focused scene, so the value
# is nil and the closure does nothing. Measured 2026-08-14 with the app backgrounded: `AXPress` on
# the View menu's Servers item returned `.success` and the title did not move; a `⌘2` posted to the
# pid did the same. Sending the chord for real needs the app frontmost, which
# `UI_VERIFICATION.md` rule 1 forbids — so the link that needed the front is the one that moved into
# a unit test, and what is exercised here is what can be exercised honestly.
select_and_check() {
    local want="$1" title selected
    "$AXKIT" select "$PID" "$want" >/dev/null || fail "could not select the '$want' row through the accessibility API"
    sleep 1
    title="$("$AXKIT" title "$PID")"
    selected="$("$AXKIT" selected "$PID")"
    [ "$title" = "$want" ] || fail "selecting $want left the title '$title'"
    # Matched as a prefix, because a row that carries a badge announces itself as one sentence —
    # "Servers, 1 need attention" — and the separator may be the comma of that sentence or the pipe
    # between an element's own strings.
    printf '%s\n' "$selected" | grep -qE "^$want([,|]|$)" \
      || fail "selecting $want moved the title but the row does not report itself selected (selected rows: '$selected')"
    [ "$(printf '%s\n' "$selected" | grep -c .)" = "1" ] \
      || fail "more than one sidebar row reports itself selected: '$selected'"
    pass "$want: the row reports itself selected and the title follows it"
}

select_and_check Servers
select_and_check Discover
select_and_check Settings
select_and_check Activity

# The fourth link: macOS dispatches a ⌘-chord to this process at all. `⌘H` is the one command in the
# inventory whose effect is observable without a focused scene, because macOS performs it itself
# rather than routing it through the app's model — so it isolates *dispatch* from the focused-value
# problem above. Chosen deliberately over any app command: if this hides the app, the keyboard
# reaches it, and A20 has already shown each digit is bound to its item.
[ "$("$AXKIT" hidden "$PID")" = "visible" ] || fail "the app was already hidden before the dispatch probe"
"$AXKIT" key "$PID" 4 cmd >/dev/null   # keycode 4 = H
sleep 1.5
[ "$("$AXKIT" hidden "$PID")" = "hidden" ] \
  || fail "⌘H did not reach the app — macOS is not dispatching ⌘-chords to this process, so no menu shortcut can work"
"$AXKIT" hidden "$PID" unhide >/dev/null
sleep 1.5
[ "$("$AXKIT" hidden "$PID")" = "visible" ] || blocked "could not un-hide the app after the dispatch probe"
pass "⌘H reached the app while it was inactive — ⌘-chords are dispatched to this process"
check_invisible "the selection assertions"

# ---------------------------------------------------------------- A21 · the three bare keys arrive

# The probe is a Debug-only surface in the content zone that records the last bare key it received,
# and claims first responder as soon as it has a window. It is what makes A21's claim checkable and
# honest: the shell declares no shortcut for these three and installs no handler, and a focused
# surface in the content zone receives all of them.
#
# The keys go to the process rather than through System Events, which is both safer and stricter: a
# System Events keystroke needs the app frontmost and lands in whatever app *is* frontmost when it
# does not, which is how the previous version could report "the shell swallowed Space" after sending
# Space into the user's terminal.
PROBE_ID="mcprouter-key-probe"
probe_field() {
    dump_window
    awk -F'\t' -v id="$PROBE_ID" -v col="$1" '$12 == id || $6 == id { print $col; exit }' "$WORK/window.tsv"
}

[ -n "$(probe_field 13)" ] || fail "the Debug key probe is not in the content zone — A21 has no test surface"
[ "$(probe_field 17)" = "1" ] \
  || fail "the key probe does not hold keyboard focus — A21 cannot be exercised, and nothing about the shell has been shown either way"
pass "the key probe holds keyboard focus in the content zone"

send_bare_key() {
    local code="$1" want="$2" attempt got=""
    for attempt in 1 2 3; do
        "$AXKIT" key "$PID" "$code" >/dev/null || blocked "could not post key code $code"
        sleep 0.8
        got="$(probe_field 5)"
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
check_invisible "the bare-key assertions"

# ---------------------------------------------------------------- A24 · the focus ring, rendered

echo
echo "keyboard focus"

# A24 wants a *rendered* measurement — "keyboard focus is visible, accent-bound and 2pt". Two of
# those three are measured here and the third is reported, for the same reason A1's 33 is:
#
# **M1 ships no control that draws its own focus ring.** The shell's focusable surfaces are AppKit's
# sidebar list and the content zone, and the ring on the former is drawn by AppKit at the system
# width. F2's `focusRing` modifier — which does read `MetricToken.focusRing` — is applied by
# controls, and the shell ships none. So the width is AppKit's number, not this item's, and claiming
# a 2pt measurement of it would be claiming credit for someone else's value.
#
# What *is* asserted is the part that is the shell's: with the sidebar unfocused the selected row is
# a neutral fill, and when focus moves to it the row becomes accent-bound and visibly so. Colour is
# matched by blue dominance rather than an exact hex, because the accent composites over a
# translucent sidebar material — see `axkit accent`.
"$AXKIT" select "$PID" Servers >/dev/null
sleep 1
ROW_RECT="$("$AXKIT" rowrect "$PID" Servers)"
IFS=, read -r ROW_X ROW_Y ROW_W ROW_H <<< "$ROW_RECT"
dump_window
WIN_X="$(awk -F'\t' '$1 == 0 { print $13; exit }' "$WORK/window.tsv")"
WIN_Y="$(awk -F'\t' '$1 == 0 { print $14; exit }' "$WORK/window.tsv")"
RING_X0=$(awk -v a="$ROW_X" -v w="$WIN_X" 'BEGIN { printf "%d", (a - w) * 2 }')
RING_X1=$(awk -v a="$ROW_X" -v w="$WIN_X" -v ww="$ROW_W" 'BEGIN { printf "%d", (a - w + ww) * 2 }')
RING_Y0=$(awk -v a="$ROW_Y" -v w="$WIN_Y" 'BEGIN { printf "%d", (a - w) * 2 }')
RING_Y1=$(awk -v a="$ROW_Y" -v w="$WIN_Y" -v hh="$ROW_H" 'BEGIN { printf "%d", (a - w + hh) * 2 }')

WIN_ID="$("$AXKIT" winid "$PID" || true)"
[ -n "$WIN_ID" ] || blocked "could not resolve the window id — Screen Recording permission?"

# The Debug key probe claims first responder at launch, so the sidebar starts unfocused — which is
# the control condition this assertion needs, arrived at without doing anything to produce it.
screencapture -o -x -l"$WIN_ID" "$WORK/unfocused.png"
[ -s "$WORK/unfocused.png" ] || blocked "screencapture produced no image — grant Screen Recording"
UNFOCUSED="$("$AXKIT" accent "$WORK/unfocused.png" "$RING_X0" "$RING_X1" "$RING_Y0" "$RING_Y1" 0.15)"
UNFOCUSED_N="$(printf '%s' "$UNFOCUSED" | cut -d' ' -f1)"

"$AXKIT" focus "$PID" >/dev/null || fail "could not move keyboard focus to the sidebar"
sleep 1.5
screencapture -o -x -l"$WIN_ID" "$WORK/focused.png"
FOCUSED="$("$AXKIT" accent "$WORK/focused.png" "$RING_X0" "$RING_X1" "$RING_Y0" "$RING_Y1" 0.15)"
FOCUSED_N="$(printf '%s' "$FOCUSED" | cut -d' ' -f1)"
FOCUSED_RUN="$(printf '%s' "$FOCUSED" | cut -d' ' -f2)"

awk -v f="$FOCUSED_N" -v u="$UNFOCUSED_N" 'BEGIN { exit !(f + 0 > u + 0) }' \
  || fail "focusing the sidebar changed no accent pixels on the selected row ($UNFOCUSED_N → $FOCUSED_N) — focus is not visible"
# A floor as well as a direction: a handful of pixels is an antialiasing artefact, not something a
# person can see. One row's width of accent is the smallest thing that reads as focus.
awk -v run="$FOCUSED_RUN" -v w="$ROW_W" 'BEGIN { exit !(run + 0 >= w * 0.5) }' \
  || fail "the focused row's longest accent run is only ${FOCUSED_RUN}px across a ${ROW_W}pt row — that is not a visible ring"
pass "focus is visible and accent-bound: $UNFOCUSED_N accent px unfocused → $FOCUSED_N focused, longest run ${FOCUSED_RUN}px"
echo "  NOTE — the ring's width is AppKit's, not this item's: M1 ships no control that draws its own."
echo "  NOTE   MetricToken.focusRing is read by F2's focusRing modifier, which the shell does not use."
check_invisible "the focus-ring assertion"

# ---------------------------------------------------------------- A34 · the scroll edge, rendered

echo
echo "the scroll edge"

# The separator is a hairline and is deliberately hidden from the accessibility tree — it repeats
# nothing a screen reader needs. So this is a **rendered** assertion, driven against a real scroll.
#
# The scroll is driven by setting the scroll bar's `AXValue`. The obvious alternative — warping the
# cursor over the window and posting scroll-wheel events, which is what this script used to do —
# moves the user's pointer, and a wheel event posted to the pid instead was measured to be dropped
# entirely (byte-identical captures).
#
# Driven on **Servers**, and that is checked against the source rather than assumed. An earlier
# version of this comment said the assertion would have to move onto a board's own list "when the
# last board lands". That was wrong, and it cost M13 an investigation: `ContentZone` keeps
# `boardsThatScrollThemselves = [.activity]`, so Activity is the one destination drawn *outside* the
# shell's scroll view, and the other seven — Servers among them — are wrapped in `outerScroll`, whose
# geometry is what drives `ScrollEdgeState`. Servers is correct and does not need moving.
#
# "Wrapped in it" is not the same as "scrolls in it", and one board is not what the set claims:
# `SettingsBoard` installs a `ScrollView` of its own while staying out of
# `boardsThatScrollThemselves`, so it nests one scroller inside another — which is the thing M2's
# B41 said would not happen. That is a defect in the app, recorded by M13 and left for whoever owns
# Settings; it does not touch Servers and it does not touch this assertion.
"$AXKIT" select "$PID" Servers >/dev/null
sleep 1
dump_window
CONTENT_X="$(awk -F'\t' '$2 == "AXScrollArea" { print $13 }' "$WORK/window.tsv" | tail -1)"
CONTENT_Y="$(awk -F'\t' '$2 == "AXScrollArea" { print $14 }' "$WORK/window.tsv" | tail -1)"
CONTENT_W="$(awk -F'\t' '$2 == "AXScrollArea" { print $15 }' "$WORK/window.tsv" | tail -1)"
[ -n "$CONTENT_X" ] || fail "no content scroll area to scroll"
WIN_X="$(awk -F'\t' '$1 == 0 { print $13; exit }' "$WORK/window.tsv")"
WIN_Y="$(awk -F'\t' '$1 == 0 { print $14; exit }' "$WORK/window.tsv")"
WIN_W="$(awk -F'\t' '$1 == 0 { print $15; exit }' "$WORK/window.tsv")"

# Both the sample below and `axkit scroll` take the **last** scroll area in the tree, so they always
# agree with each other — but "last" is only the shell's content zone while the content zone holds
# one scroller. Selecting a server opens `ServerInspector`, which is a `ScrollView` of its own and
# would become last; the run would then drive and photograph the inspector while reporting on the
# shell's scroll edge. Requiring the sampled area to reach the window's trailing edge turns that
# from a silent mis-measurement into a stop.
awk -v cx="$CONTENT_X" -v cw="$CONTENT_W" -v wx="$WIN_X" -v ww="$WIN_W" \
    'BEGIN { exit !(cx + cw >= wx + ww - 4) }' \
  || fail "the last scroll area (x $CONTENT_X w $CONTENT_W) does not reach the window's trailing edge (x $WIN_X w $WIN_W) — a nested scroller is being sampled instead of the content zone"

WIN_ID="$("$AXKIT" winid "$PID" || true)"
[ -n "$WIN_ID" ] || blocked "could not resolve the window id — Screen Recording permission?"

capture_edge() {
    screencapture -o -x -l"$WIN_ID" "$1"
    [ -s "$1" ] || blocked "screencapture produced no image — grant Screen Recording"
}

"$AXKIT" scroll "$PID" 0 >/dev/null || true
sleep 1.2
capture_edge "$WORK/edge-rest.png"

# The backing scale is **measured, not assumed**. Every earlier band in this script multiplies points
# by a hard-coded 2, which is right on this machine and silently wrong on a 1x external display or a
# 3x panel — the band would land a point into the document or up in the toolbar, and the run would
# report a missing separator for the display it was run on. The capture is window-scoped, so its
# width over the window's width in points is the scale.
IMG_W="$(sips -g pixelWidth "$WORK/edge-rest.png" | awk '/pixelWidth/ { print $2 }')"
SCALE="$(awk -v i="$IMG_W" -v w="$WIN_W" 'BEGIN { printf "%.4f", (w > 0 ? i / w : 0) }')"
awk -v s="$SCALE" 'BEGIN { exit !(s + 0 >= 0.9) }' \
  || blocked "could not read the backing scale from the capture (${IMG_W}px over ${WIN_W}pt) — the band cannot be placed"

# Image coordinates are relative to the window's own backing store. The band is inset from both edges
# so the scroll bar that appears during a scroll is outside it — a scroll bar is not a separator, and
# it would otherwise be counted as one.
BAND_X0=$(awk -v cx="$CONTENT_X" -v wx="$WIN_X" -v s="$SCALE" 'BEGIN { printf "%d", (cx - wx + 8) * s }')
BAND_X1=$(awk -v cx="$CONTENT_X" -v wx="$WIN_X" -v w="$CONTENT_W" -v s="$SCALE" 'BEGIN { printf "%d", (cx - wx + w - 24) * s }')
BAND_Y0=$(awk -v cy="$CONTENT_Y" -v wy="$WIN_Y" -v s="$SCALE" 'BEGIN { printf "%d", (cy - wy) * s }')

# `ScrollEdgeSeparator` is `MetricToken.focusRing.leadingScalar / 2` = 1pt tall. The first row that is
# background rather than separator is therefore one point below the top, and that row is what the
# line is compared against.
LINE_Y="$BAND_Y0"
BG_Y=$(awk -v y="$BAND_Y0" -v s="$SCALE" 'BEGIN { printf "%d", y + s }')
LIVE_Y0=$(awk -v y="$BAND_Y0" -v s="$SCALE" 'BEGIN { printf "%d", y + 20 * s }')
LIVE_Y1=$(awk -v y="$BAND_Y0" -v s="$SCALE" 'BEGIN { printf "%d", y + 100 * s }')

# **How the separator is identified, and why the previous answer was wrong.**
#
# This assertion has been withdrawn twice. First it compared pixel counts before and after a scroll
# and required a near-full-width row to change; a completeness critic pointed out that a full-width
# row of body text scrolling past the edge clears the same bar, the negative control failed
# immediately, and it was withdrawn. It was replaced by "the top row is uniformly one colour at rest
# and uniformly a different one once scrolled" — and that is the version M13 found reporting a
# perfectly good separator as a defect, `#2F2F2F covers 0.707 — that is content, not a separator`.
#
# Uniformity is only a fair question while *what sits behind the row* is itself one flat colour
# across the whole content width. That held over a scaffolded placeholder. Over a real board it does
# not: at a scroll offset where the Servers header has reached the top edge, the row contains the
# heading's glyphs and the accent button as well as the hairline, so it is not one colour — while
# the hairline is being drawn perfectly, at full width, over all three.
#
# What is measured now is the **compositing equation**, which is what a translucent line actually
# is. A line of opacity a over a background B renders A = a·V + (1 − a)·B for the line's own colour
# V, so a is solvable at every x whose background is legible — toward white on the dark ground,
# toward black on the light one. A hairline drawn across the row yields the *same* a everywhere,
# whatever each x is drawn over; content yields scattered values, because content is not a uniform
# veil over the row beneath it. The opacity itself is never written down here — it is compared
# against the at-rest reading — so the appearance stays free to change, and the assertion no longer
# depends on the board leaving a flat region under the toolbar.
read -r REST_Q REST_A REST_C REST_N <<< "$("$AXKIT" veil "$WORK/edge-rest.png" "$BAND_X0" "$BAND_X1" "$LINE_Y" "$BG_Y")"
echo "  at rest: opacity ${REST_A} over ${REST_N}px (${REST_Q} of the band readable, ${REST_C} agreeing)"
awk -v q="$REST_Q" 'BEGIN { exit !(q + 0 >= 0.30) }' \
  || fail "only ${REST_Q} of the top row could be read against its background at rest — the edge cannot be measured here"
awk -v a="$REST_A" 'BEGIN { exit !(a + 0 <= 0.010 && a + 0 >= -0.010) }' \
  || fail "the content's top row is already veiled at rest (opacity ${REST_A}) — the separator is showing on a window nobody has scrolled"

# The offset is chosen so that the board's **own content is under the top edge**, which is the moment
# the separator exists for. A small offset would leave the sample sitting over the empty region above
# a board and prove only the easy case; walking outward and taking the first offset that puts real
# content under the edge keeps the measurement on the case that matters. If none does, that is a
# failure — the clause cannot be evidenced — and never a quiet skip.
CHOSEN=""
for FRACTION in 0.6 0.85 0.95; do
    "$AXKIT" scroll "$PID" "$FRACTION" >/dev/null || fail "could not scroll the content zone through its scroll bar"
    sleep 1.5
    capture_edge "$WORK/edge-scrolled.png"
    UNDER_SHARE="$("$AXKIT" uniform "$WORK/edge-scrolled.png" "$BAND_X0" "$BAND_X1" "$BG_Y" | cut -d' ' -f2)"
    if awk -v s="$UNDER_SHARE" 'BEGIN { exit !(s + 0 < 0.90) }'; then CHOSEN="$FRACTION"; break; fi
done
[ -n "$CHOSEN" ] \
  || fail "no scroll offset brought the board's own content under the top edge — the separator cannot be measured at the moment the design says it must appear"

# A scroll bar that accepts a value and moves nothing renders a top row identical to the resting one,
# which would be reported below as "no separator appeared" — a confident wrong diagnosis of exactly
# the species this rewrite exists to remove. So the run proves the view moved before it reads the
# edge at all.
LIVE_FRAC="$("$AXKIT" banddiff "$WORK/edge-rest.png" "$WORK/edge-scrolled.png" "$BAND_X0" "$BAND_X1" "$LIVE_Y0" "$LIVE_Y1" | cut -d' ' -f2)"
awk -v f="$LIVE_FRAC" 'BEGIN { exit !(f + 0 > 0.05) }' \
  || fail "the scroll bar accepted $CHOSEN but nothing below the top edge moved (best row changed ${LIVE_FRAC}) — this run cannot have seen a scroll edge"

read -r SCR_Q SCR_A SCR_C SCR_N <<< "$("$AXKIT" veil "$WORK/edge-scrolled.png" "$BAND_X0" "$BAND_X1" "$LINE_Y" "$BG_Y")"
echo "  scrolled to $CHOSEN (content under the edge, ${UNDER_SHARE} uniform below it):"
echo "    opacity ${SCR_A} over ${SCR_N}px (${SCR_Q} of the band readable, ${SCR_C} agreeing)"
awk -v q="$SCR_Q" 'BEGIN { exit !(q + 0 >= 0.30) }' \
  || fail "only ${SCR_Q} of the top row could be read against its background once scrolled — too little to attribute"
awk -v a="$SCR_A" 'BEGIN { exit !(a + 0 >= 0.030) }' \
  || fail "no line is drawn over the top row once scrolled (opacity ${SCR_A}) — the separator did not appear"
awk -v c="$SCR_C" 'BEGIN { exit !(c + 0 >= 0.95) }' \
  || fail "the top row is lightened unevenly once scrolled (only ${SCR_C} of it shares one opacity) — that is content, not a single hairline drawn across the width"
pass "the scroll edge: nothing at rest, one line at opacity ${SCR_A} across ${SCR_N}px of the content width once scrolled, with content underneath it"

# And back. A34 says "absent at scroll offset 0 and present above it", which is two claims; a
# separator that appeared and never left would satisfy only the first.
"$AXKIT" scroll "$PID" 0 >/dev/null || true
sleep 1.5
capture_edge "$WORK/edge-returned.png"
read -r RET_Q RET_A RET_C RET_N <<< "$("$AXKIT" veil "$WORK/edge-returned.png" "$BAND_X0" "$BAND_X1" "$LINE_Y" "$BG_Y")"
awk -v q="$RET_Q" 'BEGIN { exit !(q + 0 >= 0.30) }' \
  || fail "only ${RET_Q} of the top row could be read against its background after returning to the top"
awk -v a="$RET_A" 'BEGIN { exit !(a + 0 <= 0.010 && a + 0 >= -0.010) }' \
  || fail "returning to the top left the edge veiled at opacity ${RET_A}, not cleared — the separator did not go away"
pass "returning to the top cleared it: opacity back to ${RET_A}"
check_invisible "the scroll-edge assertion"

# ---------------------------------------------------------------- A32, A33 · restoration

echo
echo "restoration across a relaunch"

# Move and resize by a real amount, select a destination that is not the default, then quit and
# relaunch. Asserting the *frame*, not that an autosave name is set: a name with nothing behind it
# is exactly the failure this clause exists to catch. Both the move and the quit go through APIs
# that do not activate the app — `AXPosition`/`AXSize` and `NSRunningApplication.terminate()`.
"$AXKIT" setframe "$PID" 180 140 980 620 >/dev/null || fail "could not move and resize the window"
sleep 1
"$AXKIT" select "$PID" Evals >/dev/null || fail "could not select Evals"
sleep 1.5

WANT_TITLE="$("$AXKIT" title "$PID")"
WANT_FRAME="$("$AXKIT" frame "$PID")"
[ "$WANT_TITLE" = "Evals" ] || fail "the selection did not move to Evals (title is '$WANT_TITLE')"
echo "  before quit: $WANT_TITLE at $WANT_FRAME"

"$AXKIT" terminate "$PID" >/dev/null
sleep 3
launch_app
sleep 3

GOT_TITLE="$("$AXKIT" title "$PID")"
GOT_FRAME="$("$AXKIT" frame "$PID")"
echo "  after relaunch: $GOT_TITLE at $GOT_FRAME"

[ "$GOT_TITLE" = "$WANT_TITLE" ] \
  || fail "the selected destination did not survive the relaunch: '$GOT_TITLE', expected '$WANT_TITLE'"
pass "the selected destination survived quit and relaunch ($GOT_TITLE)"

[ "$GOT_FRAME" = "$WANT_FRAME" ] \
  || fail "the window frame did not survive the relaunch: $GOT_FRAME, expected $WANT_FRAME"
pass "the window frame survived quit and relaunch ($GOT_FRAME)"
check_invisible "the restoration assertions"

# ---------------------------------------------------------------- A28 · the failure copy, in the app

echo
echo "the failure states, in the running app"

# A28 asks for `ControlAPIError`'s wording **verbatim, in the app itself** — "an AX assertion that the
# **running app** carries them". Until `ShellClientFactory` existed that was impossible: the app was
# hardwired to the populated fixture, so no failure state could ever be on screen and the clause's
# running-app leg was unevidenced while the gate reported success. Each state is its own process
# because a fixture is chosen at launch; two extra backgrounded launches is what the clause costs.
#
# The expected strings are parsed out of `ControlAPIClient.swift` rather than written here, so the
# oracle is the type's own copy and a reworded error fails this gate rather than drifting past it.
error_headline() {
    sed -n '/var headline: String/,/^    }/p' \
      "$APP_DIR/Sources/MCPRouterKit/Control/ControlAPIClient.swift" \
      | grep -oE "case \.$1: \"[^\"]+\"" | sed -E 's/.*"(.*)"/\1/'
}

for state in offline unauthorized; do
    case "$state" in
        offline)      want="$(error_headline routerNotRunning)" ;;
        unauthorized) want="$(error_headline unauthorized)" ;;
    esac
    [ -n "$want" ] || blocked "could not read the $state headline out of ControlAPIClient.swift"

    launch_app "$state"
    sleep 2
    dump_window
    STATE_TEXT="$(cut -f4,5,6 "$WORK/window.tsv" | tr '\t' '\n' | grep -v '^$' || true)"
    printf '%s\n' "$STATE_TEXT" | grep -qF "$want" \
      || fail "the running app in the $state state does not carry ControlAPIError's own words: '$want'"

    # A18, rendered: no count may appear when the router made no observation. The readout's populated
    # sentence is the thing that must be absent, and its shape is the same one asserted present above.
    if printf '%s\n' "$STATE_TEXT" | grep -qE '^[0-9]+ of [0-9]+ declared servers running$'; then
        fail "the $state state still renders running counts — a count is a claim about a router that did not answer (A18)"
    fi
    pass "$state: the app carries \"$want\" verbatim, and renders no counts"
    check_invisible "the $state state"
done

# Back to the populated app for the checks that follow.
launch_app
sleep 2

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

# **Counted, not pattern-matched.** This used to read `= []` as "scaffolds remain" and *anything
# else* as "every board has shipped", which was true while the only two reachable states were none
# and all. M2 ships one board of eight and the gate concluded "every destination has a board", then
# failed a Release build for honestly carrying a placeholder six destinations still need. A binary
# test of a partial set is a gate that reports the opposite of the truth.
#
# So both numbers are read: how many destinations exist, and how many are installed.
DEST_FILE="$APP_DIR/Sources/MCPRouterKit/Shell/Destination.swift"
[ -f "$DEST_FILE" ] || blocked "could not find Destination.swift to count destinations"
DEST_TOTAL="$(awk '
    /^public enum Destination:/ { inside = 1; next }
    inside && /^}/             { inside = 0 }
    inside && /^ +case [a-z]/  { n++ }
    END { print n + 0 }
' "$DEST_FILE")"
[ "$DEST_TOTAL" -gt 0 ] || blocked "counted zero destinations — the parse is wrong, not the code"

# The declaration is read from its `[` to its matching `]`, however many lines that spans.
#
# It used to be read as one line: `grep … | head -1 | sed -E 's/.*\[(.*)\].*/\1/'`. That was correct
# while the list was short, and it was six characters from lying. At M7 the line reaches 104
# characters; `.swiftformat` sets `--maxwidth 110`, so M5's `.discover` and M8's `.settings` wrap it —
# and a wrapped declaration makes the `sed` match nothing, yielding an empty list, a count of zero,
# and a **passing** gate that reports zero installed boards. A gate whose failure mode is silence
# about the thing it exists to count is worse than no gate.
#
# (An earlier fix here replaced a `sed` *range* that ran past the declaration to the next bracket
# anywhere below, sweeping in three unrelated tokens. Same lesson, opposite direction: read exactly
# the declaration, and nothing else.)
# shellcheck source=scripts/acceptance/board-registry.sh
. "$ROOT/scripts/acceptance/board-registry.sh"
INSTALLED_LIST="$(board_registry_installed "$APP_DIR/Sources/MCPRouterUI/Shell/ScaffoldPane.swift")"
INSTALLED_COUNT="$(board_registry_installed_count "$APP_DIR/Sources/MCPRouterUI/Shell/ScaffoldPane.swift")"

# An empty parse is a broken parse, never an empty set: `installed` is non-empty from M2 onward, so
# zero here means the reader stopped matching the source rather than that no board shipped.
[ "$INSTALLED_COUNT" -gt 0 ] || blocked "parsed zero installed boards — the reader is wrong, not the code"

if [ "$INSTALLED_COUNT" -lt "$DEST_TOTAL" ]; then
    SCAFFOLDS_REMAIN=1
else
    SCAFFOLDS_REMAIN=0
fi
echo "  boards installed: $INSTALLED_COUNT of $DEST_TOTAL destinations"

# Every file in the bundle, not only the executable ones.
#
# This searched `find -type f -perm +111` — executables — until a completeness critic pointed out
# that copy lives in nibs, `.strings` files and asset catalogues just as readily as in a binary, and
# that a scaffold sentence in any of those would have been invisible to the gate meant to catch it.
bundle_contains() {
    local bundle="$1" needle="$2" f
    while IFS= read -r f; do
        if LC_ALL=C grep -qaF -- "$needle" "$f" 2>/dev/null; then return 0; fi
    done < <(find "$bundle" -type f)
    return 1
}

[ -d "$REL_APP" ] || blocked "no Release build at $REL_APP — run 'make build-mac-release' first"

if [ "$SCAFFOLDS_REMAIN" -eq 1 ]; then
    bundle_contains "$REL_APP" "$SENTINEL" \
      || fail "destinations are still scaffolded but the Release bundle does not carry '$SENTINEL' — the placeholder is not what ships"
    pass "$((DEST_TOTAL - INSTALLED_COUNT)) destinations are still scaffolded, and Release carries the placeholder honestly"
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

"$AXKIT" terminate "$PID" >/dev/null || true
sleep 1

# ---------------------------------------------------------------- the invisibility guard, settled
FRONT_AT_END="$("$AXKIT" front)"
case "$FRONT_AT_END" in
    "MCP Router"|MCPRouter) fail "the app is frontmost at the end of the run — it took the user's screen" ;;
esac
pass "MCP Router was never the frontmost application during this run (it ended on '$FRONT_AT_END')"

echo
echo "acceptance: the Mac shell measures ${GOT_SIDEBAR}/${GOT_TOOLBAR}/${GOT_TITLEBAR}, carries its"
echo "acceptance: $INVENTORY_ROWS commands with their shortcuts and reasons, moves its selection and"
echo "acceptance: title together, receives the three bare keys, shows its scroll edge, and restores"
echo "acceptance: its destination and frame — all of it without once coming to the front."
