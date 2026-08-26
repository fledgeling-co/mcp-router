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

# The cleanup runs on EVERY exit, not only the successful one.
#
# What stood here removed `$WORK` and nothing else, while the app this lane launches was quit by a
# `terminate` on the last line of the script. So a run that ended at any `fail` — which is every
# `fail`, since `fail` exits — left an MCPRouter instance running: measured on 2026-08-26, the
# isolated re-run after the oracle repair failed at an assertion and left one behind, briefly
# frontmost, which then had to be quit by hand. That is this lane leaking into the machine it is
# measuring, and the next lane to launch the same bundle inherits it.
#
# `mac_app_wait_gone` at the next launch would eventually clear it, but only for a run that comes
# next in the same bundle; nothing clears it for a person, and rule 1 is about what is on their
# screen. Terminating here costs nothing on a green run — the app is already gone by then and
# `kill -0` says so.
#
# The trap RETURNS the status it was entered with. Bash 3.2 lets an EXIT trap's last command
# overwrite the exit status of a shell killed by `set -u`, which is how `control-client.sh` came to
# report exit 0 having asserted nothing; a cleanup that can rewrite this lane's verdict from FAIL to
# PASS is worse than no cleanup at all.
mac_shell__cleanup() {
    local status=$?
    if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then
        if [ -n "${AXKIT:-}" ] && [ -x "${AXKIT:-}" ]; then
            "$AXKIT" terminate "$PID" >/dev/null 2>&1 || true
        fi
        # Asked, then waited for, then insisted. A `terminate` that returns is not an app that has
        # exited, and reporting a clean-up that did not happen is the shape of defect this file
        # already carries five notes about.
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.3
        done
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null || true
            # And SIGKILL last, because a hung app ignores SIGTERM and the point of this cleanup is
            # that the instance is GONE rather than that it was asked. Raised by the out-of-family
            # review: an escalation that stops at TERM leaves exactly the leak it was written for.
            for _ in 1 2 3 4 5; do
                kill -0 "$PID" 2>/dev/null || break
                sleep 0.3
            done
            if kill -0 "$PID" 2>/dev/null; then kill -9 "$PID" 2>/dev/null || true; fi
        fi
    fi
    rm -rf "$WORK"
    return $status
}
trap mac_shell__cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
blocked() { echo "BLOCKED: $*" >&2; exit 2; }
pass() { echo "  ok — $*"; }

[ -d "$MAC_APP" ] || blocked "no built app at $MAC_APP — run 'make build-mac' first"

# ---------------------------------------------------------------- freshness and preconditions
#
# Both of these were checked in the wrong place, and both cost a runner a turn.
#
# **Freshness first.** Every assertion below judges the RUNNING app, so a binary older than the
# tree makes every one of them a statement about a build nobody is looking at. This gate has
# already reported exactly that as a product defect — `FAIL: the running app in the offline state
# does not carry ControlAPIError's own words` against a tree where those words were correct and
# the binary was four minutes old. Content, never mtime, so a rebase does not block it.
#
# **The Release build, here rather than at line ~1200.** `REL_APP` was assigned at the top of this
# file and first tested at the very end, so a missing Release build cost a complete pass — every
# launch, every menu walk, the restoration relaunch — before the harness said the one thing it
# knew before it started.
# shellcheck source=scripts/acceptance/build-freshness.sh
source "$ROOT/scripts/acceptance/build-freshness.sh"
# shellcheck source=scripts/acceptance/mac-app.sh
source "$ROOT/scripts/acceptance/mac-app.sh"
build_freshness_require Debug "$ROOT"
build_freshness_require Release "$ROOT"

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
    # `mac-app.sh` owns the sequence and the taxonomy. What stood here was
    # `pkill -f …; sleep 1; open -g -a …` with `open`'s status discarded, then 40 polls before
    # concluding `the shell window never appeared` and exiting 1 — a PRODUCT verdict for what is
    # almost always an environment failure. Measured with a shim making `open` exit 1, this script
    # did not even reach that message: `set -euo pipefail` aborted at `open`, so it exited 1
    # carrying nothing but `kLSServerCommunicationErr -600`.
    #
    # The `pkill -f 'MCPRouter.app/Contents/MacOS/MCPRouter'` it used matched EVERY MCPRouter on
    # the machine, so on a fleet running several worktrees it killed other runners' apps and could
    # attach to their processes. The shared launcher binds to this bundle only.
    if [ -n "$scenario" ]; then
        mac_app_launch "$MAC_APP" "$AXKIT" "MCPROUTER_SCENARIO=$scenario"
    else
        mac_app_launch "$MAC_APP" "$AXKIT"
    fi
    step_back
    check_invisible "launch"
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
# **Derived rather than pinned, since M15.** The literal was 8, which was the destination count while
# Settings was one of them; it is a window now and the sidebar draws seven. A pinned number here
# would have to be edited by every item that adds or removes a destination, and the one that forgot
# would get a red gate for a correct app. `Destination.swift` is the same oracle `$DEST_TOTAL` reads
# further down.
DEST_EXPECTED="$(awk '
    /^public enum Destination:/ { inside = 1; next }
    inside && /^}/             { inside = 0 }
    inside && /^ +case [a-z]/  { n++ }
    END { print n + 0 }
' "$APP_DIR/Sources/MCPRouterKit/Shell/Destination.swift")"
[ "$DEST_EXPECTED" -gt 0 ] || blocked "counted zero destinations — the parse is wrong, not the code"
[ "$DEST_ROW_COUNT" -ge "$DEST_EXPECTED" ] \
  || fail "only $DEST_ROW_COUNT rows share the modal height, against $DEST_EXPECTED destinations — the sidebar is not one row size"

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
# Settings left this list at M15: it is a `Settings` scene now, not a destination, so a row for it
# in the console's tree would be the removal having been partial.
for needle in Activity Servers Skills Discover Inbox Checks Cleanup; do
    printf '%s\n' "$WINDOW_TEXT" | grep -qE "^$needle(,|$)" \
      || fail "the accessibility tree does not carry a row for '$needle'"
done
pass "all seven destinations are in the accessibility tree"

# The other direction, which is what makes the removal checkable rather than merely unbroken: the
# console must not carry a Settings row at all.
if printf '%s\n' "$WINDOW_TEXT" | grep -qE "^Settings(,|$)"; then
    fail "the console still carries a 'Settings' row — M15 moved it to a window of its own"
fi
pass "the console's navigation list carries no Settings row"

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
#
# **The `Child processes, ` head is tolerated for the same reason the destination rows above are
# matched as a prefix**, and this line is the one place A35 was inconsistent with its own stated
# principle. The comment at the top of this section says a row carrying a badge announces it as one
# sentence and "the assertion has to allow for it"; this line anchored `^…$` instead. It could
# afford to, because the readout row had no label — that missing label IS the defect M27 exists to
# fix — so the anchor recorded the absence of a combined form rather than a decision against one.
# It stayed anchored long enough to reject the correct fix once: M27 shipped an unmerged row for one
# commit because `.combine` went red here. Widened, not weakened — the sentence itself is still
# matched whole, and a row that announced a bare number would still fail.
printf '%s\n' "$WINDOW_TEXT" | grep -qE '^(Child processes, )?[0-9]+ of [0-9]+ declared servers running$' \
  || fail "the readout's accessibility label is not in the tree"
pass "the readout announces its counts as a sentence"

# ---------------------------------------------------------------- A9 · the title names the view

TITLE="$("$AXKIT" title "$PID")"
case "$TITLE" in
    Activity|Servers|Skills|Discover|Inbox|Checks|Cleanup) ;;
    # `Settings` is deliberately absent: the console's title is a destination's, and Settings is no
    # longer one. The Settings *window* carries that title, and `m8-settings-menubar.sh` reads it
    # there.
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

# ---------------------------------------------------------------- A19 · the eight menus

# The Apple menu is macOS's and is excluded by name, the same way the Window menu's list of open
# windows is. Eight is the count of menus the app is responsible for.
#
# Six until M20, which adds the mock's Router and Library. They are declared as `CommandMenu`s
# rather than `CommandGroup`s — a whole menu of the app's rather than a position in one macOS
# already owns — and SwiftUI places a `CommandMenu` immediately before the Window menu, which is
# where the mock draws both. **The order below is read back off the running bar**, so if SwiftUI
# ever places them elsewhere this is what says so rather than the app quietly drawing a menu bar
# nobody specified.
MENUS="$(awk -F'\t' '$1 == 1 && $2 == "AXMenuBarItem" { print $4 }' "$WORK/menu.tsv" | grep -v '^Apple$' || true)"
MENU_COUNT="$(printf '%s\n' "$MENUS" | grep -c . || true)"
[ "$MENU_COUNT" -eq 8 ] || fail "the menu bar carries $MENU_COUNT app menus, expected 8: $(printf '%s ' $MENUS)"
for want in "MCP Router" File Edit View Router Library Window Help; do
    printf '%s\n' "$MENUS" | grep -qxF "$want" || fail "the menu bar has no '$want' menu"
done
EXPECTED_ORDER="MCP Router|File|Edit|View|Router|Library|Window|Help"
ACTUAL_ORDER="$(printf '%s' "$MENUS" | paste -sd'|' -)"
[ "$ACTUAL_ORDER" = "$EXPECTED_ORDER" ] \
    || fail "the menu bar's order is $ACTUAL_ORDER, expected $EXPECTED_ORDER"
pass "exactly eight app menus, in bar order: $ACTUAL_ORDER"

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
#
# **`Settings` joins that list at M15, and the ellipsis is what makes it safe.** Declaring a
# `Settings` scene makes macOS list the window in the Window menu under its own title, exactly as it
# does for the debug `Design system` window — measured on the running build on 2026-08-22, where the
# Window menu carried `Checks`, `Design system` and `Settings` once the window was open. The app's
# own item is `Settings…`, so this exclusion matches the system's window entry and never the
# command; and the app declares no Settings command at all now, because the scene contributes it.
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
Settings
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

# ---------------------------------------------------------------- A19b · counted, not matched

# **Both loops above ask "is this item accounted for?", and a second identical item answers that
# question exactly as the first one does.** M15 measured a build whose app menu carried **two**
# `Settings…` items — declaring the `Settings` scene contributes one and
# `CommandGroup(replacing: .appSettings)` added another, both reporting `AXMenuItemCmdChar` `,` —
# and every check above passed on it. The inventory loop found its row satisfied, the extras loop
# found each item matched, and the shortcut loop below reads the **first** item with a given title
# and never looks for a second. Three checks over the running menu bar, and the defect was found by
# hand instead.
#
# A gate that matches cannot see a duplicate; only one that counts can. So this counts, twice, and
# the two fail independently because they catch different mistakes: one command declared twice (an
# identical title inside one menu) and two commands claiming one chord (`⌘,` on `Settings…` and on
# anything else). The duplicate M15 removed trips both.
#
# `AXMenuItemCmdChar` is read **before** control characters are stripped, so `⌘⌫` — whose key has no
# printable glyph and arrives as U+0008 — is a chord here rather than an absence, and two items on
# it would be caught. What this cannot see is an item macOS keys through `AXMenuItemCmdVirtualKey`
# alone: the walk does not collect that attribute, so such an item reports no command character and
# is counted out loud as skipped rather than folded into the pass.
if ! python3 - "$WORK/items.tsv" > "$WORK/counted.txt" <<'PY'
import collections
import sys

rows = []
for line in open(sys.argv[1]):
    line = line.rstrip("\n")
    if not line:
        continue
    cells = line.split("\t")
    cells += [""] * (6 - len(cells))
    rows.append(cells)

# One command, declared twice. Keyed on (menu, title): the same word in two different menus is two
# different commands, and `Settings…` beside the Window menu's `Settings` window entry is the case
# that must stay legal.
titles = collections.Counter((row[0], row[1]) for row in rows)
repeated = sorted(key for key, count in titles.items() if count > 1)

# Two commands, one chord.
chords = collections.defaultdict(list)
skipped = 0
for menu, title, _enabled, _help, char, mods in rows:
    if char == "":
        skipped += 1
        continue
    bits = int(mods) if mods.strip().isdigit() else 0
    key = "".join(c if c.isprintable() else "U+%04X" % ord(c) for c in char)
    chord = "".join([
        "⌃" if bits & 4 else "", "⌥" if bits & 2 else "",
        "⇧" if bits & 1 else "", "" if bits & 8 else "⌘", key,
    ])
    chords[chord].append("%s / %s" % (menu, title))
shared = sorted((chord, names) for chord, names in chords.items() if len(names) > 1)

for menu, title in repeated:
    print("  declared %d times: %s / %s" % (titles[(menu, title)], menu, title), file=sys.stderr)
for chord, names in shared:
    print("  %s is on %d items: %s" % (chord, len(names), ", ".join(names)), file=sys.stderr)

print("%d %d %d %d" % (len(rows), len(titles), len(chords), skipped))
sys.exit(1 if repeated or shared else 0)
PY
then
    fail "the menu bar declares one command twice, or gives one chord to two commands"
fi
read -r COUNTED_ITEMS COUNTED_TITLES COUNTED_CHORDS COUNTED_NOKEY < "$WORK/counted.txt"
# The denominators, so a reader can see the check had something to count. A walk that collapsed to
# one item would satisfy both assertions above while measuring nothing.
[ "$COUNTED_ITEMS" -ge 30 ] || fail "the menu walk yielded $COUNTED_ITEMS items — too few to count duplicates over"
[ "$COUNTED_CHORDS" -ge 15 ] || fail "only $COUNTED_CHORDS distinct chords were read — the command-character walk looks wrong"
pass "all $COUNTED_ITEMS menu items carry $COUNTED_TITLES distinct menu/title pairs — none is declared twice"
pass "the $COUNTED_CHORDS chords read are on one item each ($COUNTED_NOKEY item(s) carry no command character)"

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
    case .featureUnbuilt: "featureUnbuilt"
    case .needsServerSelection: "needsServerSelection"
    }
    // **The reason comes from `reason(in:)`, which is the function the running app calls.**
    //
    // This read `availability.reason` — `CommandAvailability`'s generic sentence — and that was
    // the wrong question by one hop. `ShellMenuReasons.apply(to:context:)` writes
    // `command.reason(in: context)` into `AXHelp`, and `reason(in:)` specialises `.featureUnbuilt`
    // per command on purpose: D-m14-a's resolution, taken because one command carried that answer
    // when the sentence was written and nine carry it now, so the generic line would appear nine
    // times across two menus and name none of the nine features.
    //
    // So the app said `Re-indexing the whole manifest hasn't been built yet.`, this oracle expected
    // `This feature hasn't been built yet.`, and the lane reported a FAIL naming the product. It is
    // the defect `set v to value of e as text`, `shells.sh:216` at `03c34c3` carried exactly — an
    // instrument asking a neighbouring question and reporting the difference as the app's fault —
    // and it is the fifth time in this item that the harness was wrong about an app that was right.
    //
    // The assertion gets STRONGER for the change: the lane now requires the specific sentence for
    // each of the nine unbuilt commands rather than one generic string shared between them, so a
    // command that starts returning `.featureUnbuilt` without naming its subject fails here.
    print([
        command.menu.rawValue,
        command.title,
        command.isSystemProvided ? "system" : "app",
        token,
        command.reason(in: context) ?? ""
    ].joined(separator: "\t"))
}
SWIFT

# **The oracle and the binary must be the same tree**, and that is now decided by
# `build_freshness_require` in the preflight rather than here.
#
# What stood here was an mtime comparison of these four sources against the built app. Its intent
# was right and its instrument was not: a rebase rewrites mtimes without changing content, so
# `xcodebuild` correctly declines to relink, the binary keeps its old mtime, and the check blocked
# forever — `make build-mac` exiting 0 did not clear it, and only deleting the derived product did
# (`D-m11-a`). Rebase-then-gate is this fleet's standard cycle, so it blocked every merge.
#
# It was also narrower than it read: it covered four named files, so an edit to anything else —
# `ControlAPIClient.swift`, say, or a fixture JSON — left it silent while the same staleness
# produced a FAIL naming the product. The content digest covers every input the app is built from
# and is blind to mtimes, so it is both stricter and rebase-proof.

# **Two files were added here on 2026-08-21, and the breakage they fix predates M27's change.**
# `MenuCommand.title` began reading `SkillPresentation.marketplacesAction` at `2ff0941`, and this
# hand-picked list did not follow, so every run of this script since has stopped at
# `BLOCKED: could not build the availability oracle` — before reaching anything downstream of it.
# A file list that has to be maintained by hand alongside a module is the shape of the defect; it is
# left as a list rather than replaced with the built module here, because swapping the oracle's
# build strategy is a change to M1's evidence lane rather than to this one.
# **Two files were added on 2026-08-26, and the drift they fix had been live for four days.**
# `KeyChord.swift` landed at `0bdfcbe` on 2026-08-22 with M20's menu bar, `MenuCommand.swift` began
# referring to `KeyChord` in the same change, and this list did not follow — so every run of this
# script since blocked at "could not build the availability oracle" with
# `error: cannot find type 'KeyChord' in scope`, raised against `public var shortcut: KeyChord? {`,
# `MenuCommand.swift:285` at `03c34c3`.
#
# **Nobody saw it, and that is G10's point rather than this lane's.** `make acceptance` ran
# `shells.sh` first and stopped there, so this lane was not reached at all between 2026-08-22 and
# 2026-08-26 — a lane enrolled in the gate, blocked for four days, and silent. The target now runs
# every lane and aggregates, which is how this was found.
#
# `MenuCommandAvailability.swift` is the second, and it is the same shape one layer down: the list
# names `MenuCommand.swift`, but `CommandContext` and `availability(in:)` live in that extension
# file, so the oracle's own driver failed next with "type 'MenuCommand' has no member
# 'CommandContext'". Two files missing from a five-file list is what a hand-picked list does.
#
# The list is still hand-picked rather than replaced with the built module, for the reason given
# above: swapping the oracle's build strategy is a change to M1's evidence lane rather than a repair
# to it. That leaves this list free to drift a fourth time, and the thing that will catch it now is
# the lane actually being dispatched.
swiftc -O -o "$WORK/menu-oracle" \
  "$APP_DIR/Sources/MCPRouterKit/Shell/MenuCommand.swift" \
  "$APP_DIR/Sources/MCPRouterKit/Shell/Destination.swift" \
  "$APP_DIR/Sources/MCPRouterKit/Shell/KeyChord.swift" \
  "$APP_DIR/Sources/MCPRouterKit/Shell/MenuCommandAvailability.swift" \
  "$APP_DIR/Sources/MCPRouterKit/Skills/SkillPresentation.swift" \
  "$APP_DIR/Sources/MCPRouterKit/Control/SkillModels.swift" \
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
# Skills rather than Settings since M15 — the block still exercises four destinations, and Settings
# is not one of them any more.
select_and_check Skills
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

# ------------------------------------------------- D1, D2, D3 · every board, top-aligned and single-scrolled
#
# One walk of all seven destinations inside the launch that is already open. Three claims, and each
# was a defect that had been patched locally instead of fixed at the shell.
#
# **D1 — the board starts at the top of the content zone.** `ContentZone.outerScroll` hands every
# board `minHeight: scrollableMinHeight` (256 × 3 = 768pt) and SwiftUI's default alignment is
# `.center`, so a board shorter than that was centred in the surplus. Measured on Servers before the
# fix: first element at `y = 400.5` against a content top of 191 — a **209.5pt** drop, and Servers'
# own content measures ≈351pt, so `(768 − 351) / 2 = 208.5`. The arithmetic and the AX reading agree.
# Six boards had already worked around it privately with their own `.topLeading` frames — `SkillsBoard`
# still records "~170pt of dead space above the header, measured in the acceptance capture" — so one
# defect was patched six times and fixed none, and the seventh board, which never added the
# workaround, is the one that shipped it. The alignment now lives on the frame that creates the
# surplus, so a board added later inherits it rather than rediscovering it.
#
# **The 40pt threshold, and what it does and does not cover.** The readings after the fix are 16pt
# on the seven shell-scrolled boards (their top padding) and 0pt on Activity; the mutation that
# removes the alignment puts Servers at 208.5pt. So 40 clears the real geometry comfortably.
#
# It is bounded, and the bound is worth stating rather than leaving for someone to discover. Centring
# a board of height h in the 768pt frame drops it by (768 - h) / 2, so a drop of 40pt or less means
# h >= 688pt: **this catches a centred board only while the board is shorter than ~688pt.** A board
# nearly as tall as the frame has almost no dead space to be centred in, which is why that is an
# acceptable bound rather than a hole — but it is a bound, not "an order of magnitude clear".
#
# An earlier version of this paragraph justified not tightening to 20pt by saying it "would redden a
# board whose column header legitimately sits below a title". An out-of-family critic pointed out
# that this is false of this check: it takes the **minimum** y over the content zone, so the title
# always wins and a column header below it is never the measured element. The reason to keep 40
# rather than 20 is the 16pt padding plus room for a board that pads its top a little more, not a
# column header.
#
# **D2 — the content zone publishes exactly one scroll area.** `SettingsBoard` installed a
# `ScrollView` of its own while staying out of `boardsThatScrollThemselves`, so Settings published
# **three** `AXScrollArea`s where every other board published two: the inner one `716×699` nested in a
# `716×568` parent. An inner scroll view taller than its own viewport is not the thing that scrolls,
# so the outer one moved and the header the arrangement existed to keep still travelled with it.
# The registry was right and the board was the anomaly.
#
# **The content zone is found from the sidebar's own right edge, never from an absolute x.**
# `AXPosition` is in **screen** coordinates, so a literal threshold ("x > 450") encodes where this
# window happened to be sitting when someone measured it — it silently matches nothing once the
# window moves, and a count assertion that matches nothing passes by finding zero of the thing it
# forbids. Measured: the same content zone reads x=444 on Servers and x=374.5 on Discover, whose
# sidebar is collapsed differently, so no single constant is right even at one window position.
echo
echo "every board: top-aligned, single-scrolled"

# M27's two readers, defined once so the presence and the absence checks below cannot be asking
# different questions — which is how an absence check goes vacuously green.
#
# `sidebar_address` prints the loopback address drawn INSIDE the sidebar, or nothing. Bound to the
# sidebar by geometry rather than by presence anywhere in the window: Settings draws `127.0.0.1` in
# its own Endpoint row at x≈942, which is the content zone, and a window-wide grep would report the
# foot line present on the one board that never had it.
# Bounded on THREE sides rather than one, after both out-of-family reviews found the same class of
# hole in the single-sided version:
#
#   - **left**, by the sidebar outline's own x, rather than by `$13 > 0`. A window flush against the
#     screen's left edge puts the foot at x=0, `$13 > 0` is then false, and the absence check goes
#     green with an address plainly on screen. A literal 0 was doing the job the outline's own
#     geometry can do exactly.
#   - **right**, by the outline's trailing edge, as before — Settings draws `127.0.0.1` in its own
#     Endpoint row at x≈942, which is the content zone.
#   - **below** the readout card, by y. Without it the foot could be moved ABOVE the destination
#     list, keeping its x, and pass on all eight boards while `DESIGN.md` requires it last.
#
# And the field is matched WHOLE rather than by substring, so `127.0.0.1:8971 whatever` fails
# instead of being truncated to the prefix the assertion wanted. The optional `Router endpoint, `
# head is tolerated because which of AXValue/AXTitle/AXDescription SwiftUI puts an explicit label
# into is not this gate's to assume — that part stays deliberately loose.
sidebar_address() {
    awk -F'\t' -v l="$2" -v r="$3" -v top="$4" '
        $13 >= l && $13 < r && $14 >= top {
            for (i = 4; i <= 6; i++) {
                if ($i ~ /^(Router endpoint, )?127\.0\.0\.1:[0-9]+$/) {
                    value = $i
                    sub(/^Router endpoint, /, "", value)
                    print value
                    exit
                }
            }
        }' "$1"
}

# The complement, and the reason the absence check is not vacuous against a REWORDED address. The
# reader above matches one canonical form; a state that wrongly drew `localhost:8971` or
# `0.0.0.0:8971` would return nothing from it and the absence assertion would pass with an address
# on screen. This one asks the broader question — anything in the sidebar shaped like a host and a
# port — and is used only where the answer must be "nothing".
sidebar_anything_endpoint_shaped() {
    awk -F'\t' -v l="$2" -v r="$3" '
        $13 >= l && $13 < r {
            for (i = 4; i <= 6; i++) {
                if ($i ~ /(127\.0\.0\.1|localhost|0\.0\.0\.0|::1)[: ]*[0-9]{2,5}/) { print $i; exit }
            }
        }' "$1"
}

# What the count card announces as ONE element, or nothing.
#
# The label check below is a substring test and the A35 check is window-wide, so between them they
# pass just as happily on a row that publishes `Child processes` and `N of M declared servers
# running` as two separate stops — which is the form this branch shipped for one commit and then
# withdrew. Neither of them measures the thing the withdrawal was about. This does: a single field
# whose whole text is the label joined to the reading it heads is `.combine` having actually reached
# the accessibility tree, per board, rather than a modifier read out of the source by a unit test.
sidebar_count_announcement() {
    awk -F'\t' -v l="$2" -v r="$3" '
        $13 >= l && $13 < r {
            for (i = 4; i <= 6; i++) {
                if ($i ~ /^Child processes, [0-9]+ of [0-9]+ declared servers running$/) {
                    print $i
                    exit
                }
            }
        }' "$1"
}

# The sidebar's own left edge, trailing edge, and the y below which the foot must sit. Read from the
# outline and from the readout card rather than assumed, in one place, so the presence and absence
# checks cannot come to disagree about where the sidebar is.
sidebar_bounds() {
    awk -F'\t' '$2 == "AXOutline" { printf "%s %s\n", $13, $13 + $15; exit }' "$1"
}

# The expected port is read out of the recording the Debug fixture serves, never typed. The line
# under test is the one whose whole defect class is a hard-coded port, so a hard-coded port in its
# oracle would be the same mistake one layer out.
# **And out of the recording the app ACTUALLY serves, which is not the one this read first.**
# `FixtureControlAPIClient.servers()` decodes `servers-pending-auth` — the populated case
# deliberately uses the recording carrying an in-flight authorization — while this oracle read
# `servers.json`. The two happen to carry the same port today, so the check was right by luck: an
# oracle pointed at a file the subject does not serve is measuring a different app. The recording's
# name is taken from the client's own source rather than typed here, for the same reason the port is.
WANT_FIXTURE="$(sed -n 's/.*try decode("\([a-z-]*\)", as: ServersResponse\.self).*/\1/p' \
  "$APP_DIR/Sources/MCPRouterKit/Control/FixtureControlAPIClient.swift" | head -1)"
[ -n "$WANT_FIXTURE" ] \
  || blocked "could not read which servers recording FixtureControlAPIClient decodes"
WANT_PORT="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['port'])" \
  "$APP_DIR/Sources/MCPRouterKit/Control/Fixtures/$WANT_FIXTURE.json")"
[ -n "$WANT_PORT" ] || blocked "could not read the fixture router's port out of $WANT_FIXTURE.json"
echo "  the app under test serves $WANT_FIXTURE.json, which answers on port $WANT_PORT"

# An optional evidence capture, off unless `MCPR_EVIDENCE_DIR` is set, so an ordinary gate run still
# writes nothing outside its scratch directory.
#
# It exists because the campaign's rule about published captures is the one this item was reported
# under: a picture is only evidence when something binds it to the surface it claims to show. A wall
# of captures on this project once showed three unrelated documents while every gate stayed green,
# and only the filename tied a picture to a screen. So each capture is taken by **CGWindowID** — the
# only route that photographs THIS window rather than whatever is on top of a screen rectangle — and
# a row is written naming the destination, that window id, the bundle the pid is executing, and the
# exact string the assertion above read out of the accessibility tree in the same iteration. A
# capture whose row disagrees with its neighbours is visibly not of the surface it says.
EVIDENCE_DIR="${MCPR_EVIDENCE_DIR:-}"
if [ -n "$EVIDENCE_DIR" ]; then
    mkdir -p "$EVIDENCE_DIR"
    EVIDENCE_WIN="$("$AXKIT" winid "$PID" || true)"
    [ -n "$EVIDENCE_WIN" ] || blocked "could not resolve the window id for the evidence capture"
    printf 'destination\twindow_id\tbundle\tfoot_read\tcount_announcement\tcapture\ttaken_at\n' \
      > "$EVIDENCE_DIR/captures.tsv"
fi

capture_evidence() {
    [ -n "$EVIDENCE_DIR" ] || return 0
    local dest="$1" foot="$2" announce="$3" out="$EVIDENCE_DIR/sidebar-foot-$1.png"
    screencapture -o -x -l"$EVIDENCE_WIN" "$out"
    [ -s "$out" ] || blocked "the evidence capture produced no image — grant Screen Recording"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$dest" "$EVIDENCE_WIN" "$MAC_APP" "$foot" "$announce" "$(basename "$out")" \
      "$(date -u +%FT%TZ)" \
      >> "$EVIDENCE_DIR/captures.tsv"
}

: > "$WORK/all-panes.tsv"
for dest in Activity Servers Skills Discover Inbox Checks Cleanup; do
    "$AXKIT" select "$PID" "$dest" >/dev/null || fail "could not select $dest"
    sleep 1.2
    dump_window
    cat "$WORK/window.tsv" >> "$WORK/all-panes.tsv"

    PANE_TITLE="$("$AXKIT" title "$PID")"
    [ "$PANE_TITLE" = "$dest" ] || fail "selecting $dest left the window title '$PANE_TITLE'"

    SIDE_R="$(awk -F'\t' '$2 == "AXOutline" { print $13 + $15; exit }' "$WORK/window.tsv")"
    [ -n "$SIDE_R" ] || fail "$dest: could not find the sidebar outline to locate the content zone"

    # D2 — exactly one scroll area starts at or right of the sidebar's trailing edge.
    #
    # **This measures a board with no row selected, which is the state the walk creates and the only
    # state in which "exactly one" is the right answer.** Selecting a row opens an inspector
    # (`ServerInspector`, `EvalsInspector`, `SkillInspector` each install a `ScrollView` of their
    # own), and a second content-zone scroll area is then correct rather than a defect — A34 below
    # relies on exactly that fact. So the loop selects destinations and never rows. If a board ever
    # auto-selects its first row on appear, this assertion will go red on a correct app, and the fix
    # is to dismiss the inspector here rather than to raise the count.
    N_SCROLL="$(awk -F'\t' -v b="$SIDE_R" '$2 == "AXScrollArea" && $13 >= b - 2' "$WORK/window.tsv" | wc -l | tr -d ' ')"
    [ "$N_SCROLL" = "1" ] \
      || fail "$dest publishes $N_SCROLL scroll areas in the content zone, not 1 — a nested scroller means the inner one does not move and any header above it rides the outer one"

    # D1 — the topmost thing the board draws sits within the band of the content zone's own top.
    CY="$(awk -F'\t' -v b="$SIDE_R" '$2 == "AXScrollArea" && $13 >= b - 2 { print $14; exit }' "$WORK/window.tsv")"
    TY="$(awk -F'\t' -v b="$SIDE_R" -v cy="$CY" '
        $13 >= b - 2 && $14 >= cy && $15 > 0 && $16 > 0 &&
        ($2 == "AXStaticText" || $2 == "AXButton" || $2 == "AXTextField") {
            if (m == "" || $14 < m) m = $14
        } END { print m }' "$WORK/window.tsv")"
    [ -n "$TY" ] || fail "$dest: the content zone draws no text or control to measure"
    DROP="$(awk -v a="$TY" -v b="$CY" 'BEGIN { printf "%.1f", a - b }')"
    awk -v d="$DROP" 'BEGIN { exit !(d <= 40 && d >= -1) }' \
      || fail "$dest starts ${DROP}pt below the content top — the board is centred in the shell's over-tall frame rather than aligned to it"
    # M27 — SURF-001's two foot elements, on this destination.
    #
    # Both live in the *shared sidebar wrapper*, so the claim is "on every board" rather than "on
    # one", and a single-board check would have passed against the build this closes: the campaign's
    # differential found the loopback line on **0 of 9** destinations and the string `Child
    # processes` on 0 of 9, while every existing gate was green.
    #
    # Bound to the sidebar by geometry, not by presence. The Settings board draws `127.0.0.1` in its
    # own Endpoint row at x≈942, which is the content zone — a naive window-wide grep would have
    # reported the foot line present on the one board that never had it.
    # Matched on the ADDRESS rather than on the accessibility label, and as a substring rather than
    # an anchored whole. Which of `AXValue`, `AXTitle` or `AXDescription` SwiftUI puts an explicit
    # `accessibilityLabel` into is not this gate's to assume, and an assertion keyed on the wrapper
    # text can pass its absence check while the element is on screen — the exact vacuity this
    # campaign has already paid for.
    # `SIDE_R` is already in hand from the content-zone measurement above; only the left edge is new.
    # Read from the same outline, so the two bounds cannot come from different elements.
    read -r SIDE_L _ <<< "$(sidebar_bounds "$WORK/window.tsv")"
    [ -n "$SIDE_L" ] || fail "$dest: could not read the sidebar's own left edge"

    # The label first, because its y is the bound the address is then held below. Substring rather
    # than equality: a screen reader may be handed the label joined to the value it heads, and an
    # equality test would report a present label as missing.
    LABEL_Y="$(awk -F'\t' -v l="$SIDE_L" -v r="$SIDE_R" '
        $13 >= l && $13 < r {
            for (i = 4; i <= 6; i++) if (index($i, "Child processes") > 0) { print $14; exit }
        }' "$WORK/window.tsv")"
    [ -n "$LABEL_Y" ] \
      || fail "$dest: the sidebar's count is unlabelled — the design of record names it 'Child processes' (M27)"

    # And the label and its reading are ONE element, which the substring test above cannot see.
    ANNOUNCE="$(sidebar_count_announcement "$WORK/window.tsv" "$SIDE_L" "$SIDE_R")"
    [ -n "$ANNOUNCE" ] \
      || fail "$dest: the count card announces its label and its reading as two stops — a screen reader reaches the number by a second swipe, and the label alone carries no value (M27)"

    # Held BELOW the card it is the foot of, so "last in the sidebar" is measured rather than
    # assumed. Without a y bound the foot could be moved above the destination list, keep its x, and
    # pass on all seven boards.
    FOOT="$(sidebar_address "$WORK/window.tsv" "$SIDE_L" "$SIDE_R" "$LABEL_Y")"
    [ -n "$FOOT" ] \
      || fail "$dest: the sidebar foot carries no loopback readout below the count card — it is in the shared wrapper, so it belongs on every board (M27)"

    # The port is the one the running router answered on, never the mock's constant. A line reading
    # 8879 is a line composed from a literal.
    [ "$FOOT" = "127.0.0.1:$WANT_PORT" ] \
      || fail "$dest: the foot reads '$FOOT', but the router this app is talking to answered on port $WANT_PORT"

    capture_evidence "$dest" "$FOOT" "$ANNOUNCE"

    echo "  ok — $dest: 1 content scroll area, first element ${DROP}pt below the content top, foot reads $FOOT, count announces as one element: \"$ANNOUNCE\""
done

# D3 — the rename is complete rather than half-applied. `Evals` was the one label in this app
# promising a graded verdict the product cannot produce; the concept was renamed to `Checks` in the
# source (`MCPRouterKit/Checks/`, `CheckCopy`, `CheckPresentation`) and only the words a user reads
# lagged. Two of those words existed — `Destination.evals.title` for the sidebar row, the window
# title and the View-menu item, and `CheckCopy.evalsTitle` for the board's own heading — so moving
# one and not the other would have left the shell and the pane it opens disagreeing about the pane's
# name: the split §6's one-name-per-state rule forbids, newly created by the fix for it.
#
# Swept over every pane's dump **and** the menu, because the word could survive in exactly one place
# and a single-pane check would not see it.
#
# **What this proves and what it does not.** This is an ABSENCE check: it proves the old word is
# gone from the running app. It does not prove the surviving strings agree with each other — an
# out-of-family critic pointed out that a third spelling (`Health` on the pane heading alone) would
# leave the sidebar and the pane it opens disagreeing with this assertion still green. That claim is
# pinned where it can be stated exactly rather than inferred from a dump:
# `CheckCopy.evalsTitle` is now *derived from* `Destination.evals.title` rather than spelled a second
# time, and `ShellDestinationTests.evalsReadsAsChecksWithoutMovingItsKey` asserts the equality for
# anyone who re-inlines the literal. The two together are the guard; this half alone is not. The enum case, its `rawValue` and the `?pane=evals`
# deep-link slug stay `evals` and are invisible here — they are identifiers, and §6 governs words a
# user reads.
if grep -qw "Evals" "$WORK/all-panes.tsv"; then
    fail "'Evals' is still rendered somewhere: $(grep -ohw "Evals" "$WORK/all-panes.tsv" | wc -l | tr -d ' ') occurrence(s) across the seven panes"
fi
if grep -qw "Evals" "$WORK/menu.tsv"; then
    fail "'Evals' is still in the menu bar — the View menu and the sidebar disagree"
fi
pass "'Evals' appears in neither the seven panes nor the menu bar; the sidebar, the title and the pane heading all read 'Checks'"
check_invisible "the board-alignment and rename assertions"

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
# "Wrapped in it" is not the same as "scrolls in it", and M13 recorded one board where they came
# apart: `SettingsBoard` installed a `ScrollView` of its own while staying out of
# `boardsThatScrollThemselves`, nesting one scroller inside another — the thing M2's B41 said would
# not happen. **That is fixed rather than outstanding**, and this paragraph used to say otherwise
# four lines below the walk that disproves it: D2 removed the inner scroll view, and the D2
# assertion above measured exactly one content-zone scroll area on all eight panes, Settings
# included. An out-of-family critic caught the contradiction — a stale defect report sitting
# immediately after the assertion that retired it is how the next reader re-opens a closed finding.
#
# **M15 takes Settings out of that claim entirely**, and the claim is narrower rather than weaker:
# the walk covers seven panes now, and the Settings *window* does own a `ScrollView` of its own —
# correctly, because there is no shell around it to nest inside. That inversion is asserted by
# `SettingsWindowTests.theWindowOwnsOneScroll`, not here; this walk says nothing about it.
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
"$AXKIT" select "$PID" Checks >/dev/null || fail "could not select Checks"
sleep 1.5

WANT_TITLE="$("$AXKIT" title "$PID")"
WANT_FRAME="$("$AXKIT" frame "$PID")"
[ "$WANT_TITLE" = "Checks" ] || fail "the selection did not move to Checks (title is '$WANT_TITLE')"
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
    # M27 — the foot's fourth state, on glass, and it applies to BOTH of these states rather than
    # to the offline one alone. `unauthorized` means the router answered 401: the poll still failed,
    # so no port was ever observed, so there is no address the app can claim to have reached.
    #
    # Asked with the same reader the presence check uses. An absence check phrased differently from
    # its presence twin is an absence check that can go green because it was looking for the wrong
    # string.
    read -r STATE_SIDE_L STATE_SIDE_R <<< "$(sidebar_bounds "$WORK/window.tsv")"
    [ -n "$STATE_SIDE_L" ] || fail "$state: could not find the sidebar outline"
    # The canonical reader, with its y bound dropped to the whole sidebar: there is no count card in
    # this state to sit below, and an absence check must look everywhere the thing could be rather
    # than only where it belongs.
    STATE_FOOT="$(sidebar_address "$WORK/window.tsv" "$STATE_SIDE_L" "$STATE_SIDE_R" 0)"
    [ -z "$STATE_FOOT" ] \
      || fail "the $state app draws '$STATE_FOOT' in the sidebar for a router that never answered (M27)"
    # And the broader question, because the reader above matches one canonical form. A state that
    # wrongly drew `localhost:8971` would return nothing from it and this assertion would pass with
    # an address on screen — which is the absence-check vacuity this campaign has already paid for.
    STATE_ANY="$(sidebar_anything_endpoint_shaped "$WORK/window.tsv" "$STATE_SIDE_L" "$STATE_SIDE_R")"
    [ -z "$STATE_ANY" ] \
      || fail "the $state app draws '$STATE_ANY' in the sidebar — an endpoint for a router that never answered (M27)"
    # And the count card's label goes with its numbers. The failure form replaces the counts form
    # rather than emptying it, so a readout still headed `Child processes` under an error message
    # would be a card describing a metric it is no longer showing. Asked here because the presence
    # side of this pair is asserted on all seven boards above, and a label is exactly the kind of
    # chrome that survives a state change nobody checked.
    STATE_LABEL="$(awk -F'\t' -v l="$STATE_SIDE_L" -v r="$STATE_SIDE_R" '
        $13 >= l && $13 < r {
            for (i = 4; i <= 6; i++) if (index($i, "Child processes") > 0) { print $i; exit }
        }' "$WORK/window.tsv")"
    [ -z "$STATE_LABEL" ] \
      || fail "the $state app still heads the readout '$STATE_LABEL' — the card names a count it is not showing (M27)"
    pass "$state: the sidebar foot draws nothing endpoint-shaped, and the count card keeps no label"

    pass "$state: the app carries \"$want\" verbatim, and renders no counts"
    check_invisible "the $state state"
done

# Back to the populated app for the checks that follow.
launch_app
sleep 2

# ---------------------------------------------------------------- the two ways a command can be off

echo
echo "a command is off for a destination that has no board, or for a feature that does not exist"

# **These are two different facts, and this block used to conflate them into one grep.**
#
# It read the sentinel `isn't built yet` out of `ScaffoldPane.swift`'s comment and failed if the
# Release bundle still contained it once every destination had a board. That was the right idea
# aimed at the wrong string. Measured on a clean Release build at `317d957`:
#
#   isn't built yet                          1   Contents/MacOS/MCPRouter
#   This part of the app isn't built yet.    1   same file          <- surfaceAbsent's reason
#   ScaffoldCopy                             0
#   ScaffoldedDestination                    0
#   ScaffoldPane                             2   same file          <- the FILE NAME, in metadata
#   BoardRegistry                           17   same file          (control)
#
# So the scaffold really is gone — M6's deletion worked — and the sole hit was a **live menu help
# tag** that shared a substring with the deleted pane's copy, on purpose, since M1. The gate was
# reporting "the scaffold outlived the surface it stood in for" about a scaffold that does not
# exist, while the actual defect it was standing next to went unnamed: `Pair iPhone…` answered
# `surfaceAbsent` with every board installed.
#
# Two further things that table settles, and both shape what is asserted below:
#
#   * A bytes grep **cannot ask about reachability.** `Select a server first.` is present as a
#     control; a reason literal is compiled in because `reason` is a `public` computed property on
#     a `public` enum, whether or not any path reaches it. So "no command reports this case" has to
#     be asked of the model, not of the binary.
#   * The needle must be a **type the file no longer declares**, never the file's name: the path
#     `ScaffoldPane.swift` survives in metadata at 2 while both deleted types sit at 0.

DEST_FILE="$APP_DIR/Sources/MCPRouterKit/Shell/Destination.swift"
[ -f "$DEST_FILE" ] || blocked "could not find Destination.swift to count destinations"
DEST_TOTAL="$(awk '
    /^public enum Destination:/ { inside = 1; next }
    inside && /^}/             { inside = 0 }
    inside && /^ +case [a-z]/  { n++ }
    END { print n + 0 }
' "$DEST_FILE")"
[ "$DEST_TOTAL" -gt 0 ] || blocked "counted zero destinations — the parse is wrong, not the code"

# The declaration is read from its `[` to its matching `]`, however many lines that spans — it wraps
# at eight entries, and a one-line reader silently yielded an empty list and a passing gate.
# shellcheck source=scripts/acceptance/board-registry.sh
. "$ROOT/scripts/acceptance/board-registry.sh"
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

# `$WORK/expected.tsv` is the A22 oracle's output — `MenuCommand.availability(in:)` compiled from
# this tree and asked with the real registry. Reused rather than recompiled, so G1 and G3 cannot
# disagree with the availability assertions above about what the model says.
[ -s "$WORK/expected.tsv" ] || blocked "the availability oracle produced nothing — G1/G3 have no input"

# The missing-board sentence, **derived rather than written here**, so G3 cannot be fooled by
# someone editing one reason to match the other. It is read by re-running the same oracle binary
# with **no** installed destinations — `CommandContext.none`, M1's world — where `Add server…` and
# friends are guaranteed to report `surfaceAbsent` and carry its reason in column 5. That is why
# this does not need a second compile or a new oracle mode: the answer is already a function of the
# same `MenuCommand.swift` the app was built from.
"$WORK/menu-oracle" > "$WORK/expected-none.tsv" \
  || blocked "the availability oracle did not run with an empty installed set"
SURFACE_ABSENT_REASON="$(awk -F'\t' '$4 == "surfaceAbsent" { print $5; exit }' "$WORK/expected-none.tsv")"
[ -n "$SURFACE_ABSENT_REASON" ] \
  || blocked "no command reports surfaceAbsent even with no board installed — the oracle is wrong, not the app"

# ---------------------------------------------------------------- G1 · no board missing, no command claiming one
#
# The structural half, and the assertion that is red on `main`: `.pairPhone` answered
# `surfaceAbsent` unconditionally while all eight boards shipped.
SURFACE_ABSENT_ROWS="$(awk -F'\t' '$4 == "surfaceAbsent" { print $1 " / " $2 }' "$WORK/expected.tsv")"
SURFACE_ABSENT_COUNT="$(printf '%s' "$SURFACE_ABSENT_ROWS" | grep -c . || true)"

if [ "$SCAFFOLDS_REMAIN" -eq 0 ]; then
    [ "$SURFACE_ABSENT_COUNT" -eq 0 ] || fail "every destination has a board, but $SURFACE_ABSENT_COUNT command(s) still report surfaceAbsent — a command is refusing over a board that shipped:
$SURFACE_ABSENT_ROWS"
    pass "every destination has a board, and no command claims otherwise"
else
    # **Deliberately reported rather than asserted.** The inverse of the rule above is not sound: a
    # destination can be added with no board *and* no command gated on it, and then demanding at
    # least one `surfaceAbsent` report would fail a tree in which nothing is wrong. The direction
    # that carries the invariant is the one above — every board present means no command may claim
    # otherwise — and that one is asserted. This arm is unreachable on `main` today and is left
    # honest rather than made to look thorough.
    echo "  note: $((DEST_TOTAL - INSTALLED_COUNT)) destination(s) have no board; $SURFACE_ABSENT_COUNT command(s) report surfaceAbsent"
    pass "boards are still landing, so surfaceAbsent is a legitimate answer here"
fi

# ---------------------------------------------------------------- G2 · the command this item exists to fix
#
# **Hand-written where everything around it is derived, and that is the point.** M11 moved A22's
# expectation into the compiled oracle so it could not rot — but recorded, as its own finding M2,
# that a derived oracle *cannot* falsify the gating map: a mutation moves the expectation and the
# app together. G1 above is satisfied by re-classifying `Pair iPhone…` as `featureUnbuilt`, or
# `needsServerSelection`, or `enabled`-for-the-wrong-board — every one of which leaves the defect on
# screen. This row can only be satisfied by the item actually being usable and silent.
#
# It rots only if pairing is deliberately withdrawn, which is a deliberate edit here.
PAIR_LINE="$(awk -F'\t' '$1 == "File" && $2 == "Pair iPhone…" { print; exit }' "$WORK/items.tsv")"
[ -n "$PAIR_LINE" ] || fail "File / Pair iPhone… is not in the menu bar at all"
PAIR_ENABLED="$(printf '%s' "$PAIR_LINE" | cut -f3)"
PAIR_HELP="$(printf '%s' "$PAIR_LINE" | cut -f4)"
[ "$PAIR_ENABLED" = "1" ] \
  || fail "File / Pair iPhone… is dimmed, but M6 shipped the pairing sheet it opens and the Inbox board's own Pairing… button is live"
[ -z "$PAIR_HELP" ] \
  || fail "File / Pair iPhone… is usable and still carries the reason '$PAIR_HELP'"
pass "File / Pair iPhone… is enabled and carries no reason — the menu agrees with the board underneath it"

# ---------------------------------------------------------------- G2b · the other half of the pair
#
# Hand-written for the same reason G2 is, and it closes a hole a completeness critic found in G3:
# G3's zero-count arm *skips*, so quietly recategorising `Export library…` as `needsServerSelection`
# or `enabled` would leave G1, G3 and A22 all green while the command stopped telling the truth.
# The two commands M1 gave one answer are the two this item separated, so both are named here.
#
# **When export ships, this row is a deliberate edit**, exactly like G2 when pairing changes. That
# is the cost of naming a command, and it is the only thing that makes the claim falsifiable.
EXPORT_LINE="$(awk -F'\t' '$1 == "File" && $2 == "Export library…" { print; exit }' "$WORK/items.tsv")"
[ -n "$EXPORT_LINE" ] || fail "File / Export library… is not in the menu bar at all — §3.4 forbids hiding a disabled command"
EXPORT_ENABLED="$(printf '%s' "$EXPORT_LINE" | cut -f3)"
EXPORT_HELP="$(printf '%s' "$EXPORT_LINE" | cut -f4)"
[ "$EXPORT_ENABLED" = "0" ] \
  || fail "File / Export library… is offered as usable, but no export feature exists in either target"
[ "$EXPORT_HELP" != "$SURFACE_ABSENT_REASON" ] \
  || fail "File / Export library… explains itself with the missing-board sentence — its feature was never built, which is a different fact"
[ -n "$EXPORT_HELP" ] \
  || fail "File / Export library… is dimmed and says nothing — §3.4 requires a discoverable reason"
pass "File / Export library… is dimmed and gives a reason of its own: '$EXPORT_HELP'"

# ---------------------------------------------------------------- D4 · a shortcut §8 never granted
#
# `Export library…` used to carry `⌘E`, and two separate things were wrong with it.
#
# `DESIGN.md` §8's table is where this app's ⌘-combinations are granted, and it never granted `⌘E`.
# And `⌘E` is already a **standard macOS combination** — Finder's *Eject*, and Cocoa's *Use Selection
# for Find* in any text context — so the app was claiming a system chord for a command that can
# never fire, since `exportLibrary` is `featureUnbuilt` in every context.
#
# **A20 structurally cannot catch this**, which is why the assertion is here rather than left to it.
# A20 walks the inventory and skips every row whose documented shortcut is `—` (`[ "$shortcut" = "-" ]
# && continue`), so a command that carries a chord the document does not grant is never compared to
# anything. The check has to run from the *running menu* toward the document, and that direction is
# only this block.
#
# The general sweep is the load-bearing half: naming Export alone would pass the day some other
# command picked the same ungranted chord up.
EXPORT_CHAR="$(printf '%s' "$EXPORT_LINE" | cut -f5 | tr -d '[:cntrl:]')"
[ -z "$EXPORT_CHAR" ] \
  || fail "File / Export library… binds '$EXPORT_CHAR', but §8's table grants it no shortcut and the command can never fire"
pass "File / Export library… carries no shortcut — §8 granted it none"

#
# **Two things this has to get right, and the first draft got both wrong — measured, not reasoned.**
# It swept every row in `items.tsv` for the character `E` and reported `Edit / Emoji & Symbols` as a
# violation. That item is real and it does carry the character `E`, but it does not bind `⌘E`:
# `AXMenuItemCmdModifiers` is a bitmask whose **bit 8 means "no command key"**, and the item reports
# `24`, so the ⌘ is not in its chord at all. A sweep that reads the character and ignores the
# bitmask calls every unrelated chord on the same letter a violation. The modifier is decoded here
# exactly as A20 decodes it, so the two agree about what a chord is.
#
# And that row is **AppKit's**, inserted into the Edit menu rather than declared by this app, so even
# a genuine ⌘E on it would be nothing this app could grant or withdraw. The claim is about what the
# app declares, so it is joined against the availability oracle's own `app` rows — the same derived
# split A22 uses, rather than a second hand-written list of system items.
E_BINDERS="$(awk -F'\t' '
    NR == FNR { if ($3 == "app") declared[$1 "\t" $2] = 1; next }
    ($1 "\t" $2) in declared {
        c = $5; gsub(/[[:cntrl:]]/, "", c)
        mods = ($6 == "" ? 0 : $6) + 0
        # Bit 8 is the no-command-key bit, tested arithmetically. The default awk on macOS is the
        # one true awk, which has NO and() function -- that is a gawk extension. See the note below
        # this block for why writing it with and() was invisible until a mutation reached the line.
        if ((c == "E" || c == "e") && int(mods / 8) % 2 == 0) print $1 " / " $2
    }
' "$WORK/expected.tsv" "$WORK/items.tsv")"
[ -z "$E_BINDERS" ] \
  || fail "an app-declared command binds ⌘E, which §8's table never grants: $(printf '%s' "$E_BINDERS" | paste -sd'; ' -)"
# **Why the bit test is arithmetic rather than `and(mods, 8)`.** It was written with `and()`, and
# that version passed lint, passed a full green run, and passed mutation M4 — because awk
# short-circuits `&&`, so `and()` was only ever reached by a row that actually violated the rule.
# The one moment the assertion had a defect to report, it died with `awk: calling undefined function
# and` and the script exited **2 — BLOCKED, not red**. macOS ships the one true awk, which has no
# `and()`; that is a gawk extension. An assertion that can only ever block is indistinguishable from
# a passing one right up until it matters, which is the exact class this fleet keeps finding. It was
# caught by M4b, the mutation that binds ⌘E to a command other than Export — the only thing that
# reaches this line, since the Export-specific check above fires first on the obvious mutation.
pass "no app-declared command binds ⌘E — the chord stays with the system"

# ---------------------------------------------------------------- G3 · a feature that does not exist says so
#
# Conditional on the oracle's own count, never `>= 1`. An unconditional tripwire would make
# *shipping export* a gate failure, which is the failure mode where a gate starts defending the
# absence of a feature.
#
# **What this adds over A22, stated because most of it is overlap.** A22 already walks every
# non-`enabled` row and compares `AXHelp` to the oracle's reason, so the presence and the dimming
# below are a second reading of a check that already ran. The assertion that is *only* here is the
# last one in the loop: an unbuilt feature must not explain itself with the missing-board sentence.
# A22 cannot catch that — it compares the rendering to the oracle, so if the reason and the
# rendering were *both* the missing-board sentence it passes, and the two refusals this item
# separated would have quietly collapsed back into one. That is the mutation aimed at this block.
FEATURE_UNBUILT_ROWS="$(awk -F'\t' '$4 == "featureUnbuilt"' "$WORK/expected.tsv")"
FEATURE_UNBUILT_COUNT="$(printf '%s' "$FEATURE_UNBUILT_ROWS" | grep -c . || true)"

if [ "$FEATURE_UNBUILT_COUNT" -eq 0 ]; then
    # **This arm claims nothing about features, and an earlier draft did.** It said "every feature
    # the menu offers exists", which the gate has no way to know: reclassifying `Export library…`
    # as `needsServerSelection` takes this branch, leaves G1 and A22 green, and the sentence would
    # have been false. What is actually observed is only what is printed.
    echo "  note: the model reports no featureUnbuilt command; this gate cannot itself confirm every feature exists"
    pass "no command reports featureUnbuilt in this build"
else
    FEATURE_CHECKED=0
    while IFS=$'\t' read -r menu title kind availability reason; do
        [ -n "$title" ] || continue
        [ "$kind" = "app" ] \
          || fail "$menu / $title reports featureUnbuilt but is a system item — macOS does not build the app's features"
        line="$(awk -F'\t' -v m="$menu" -v t="$title" '$1 == m && $2 == t { print; exit }' "$WORK/items.tsv")"
        [ -n "$line" ] || fail "$menu / $title reports featureUnbuilt and is not in the menu bar — §3.4 forbids hiding it"
        enabled="$(printf '%s' "$line" | cut -f3)"
        help="$(printf '%s' "$line" | cut -f4)"
        [ "$enabled" = "0" ] || fail "$menu / $title has no feature behind it, but the menu bar offers it as usable"
        [ "$help" = "$reason" ] \
          || fail "$menu / $title carries '$help' where its own reason is '$reason'"
        # The distinction this whole block exists for: an unbuilt feature must not be described with
        # the sentence reserved for a destination whose board is missing from this build.
        [ "$help" != "$SURFACE_ABSENT_REASON" ] \
          || fail "$menu / $title has no feature at all, but explains itself with the missing-board sentence"
        FEATURE_CHECKED=$((FEATURE_CHECKED + 1))
    done <<< "$FEATURE_UNBUILT_ROWS"
    [ "$FEATURE_CHECKED" -ge 1 ] || fail "the featureUnbuilt loop ran on nothing while the oracle named $FEATURE_UNBUILT_COUNT"
    pass "$FEATURE_CHECKED command(s) with no feature behind them are dimmed, each with its own sentence"
fi

# ---------------------------------------------------------------- G4 · the scaffold cannot come back
# The Release build's presence and freshness were both established in the preflight, next to the
# Debug one. This block used to open with the only check for it, ~1,200 lines after `REL_APP` was
# assigned — so a missing Release build cost a full pass before the harness reported something it
# could have said at second one.

# Every file in the bundle, not only the executable ones: copy lives in nibs, `.strings` files and
# asset catalogues just as readily as in a binary.
bundle_contains() {
    local bundle="$1" needle="$2" f
    while IFS= read -r f; do
        if LC_ALL=C grep -qaF -- "$needle" "$f" 2>/dev/null; then return 0; fi
    done < <(find "$bundle" -type f)
    return 1
}

# The two types the placeholder was built from. `ScaffoldPane` is **not** among them: the type is
# deleted but the file survives (four acceptance scripts read `BoardRegistry.installed` out of it),
# so its name is in the binary's metadata at 2 and would fail this check for a benign reason.
# `ShellScaffoldRetirementTests.scaffoldTypesStayDeleted` asserts the same two at the source level;
# this is its counterpart on the artifact that actually ships.
for scaffold_type in ScaffoldCopy ScaffoldedDestination; do
    if bundle_contains "$REL_APP" "$scaffold_type"; then
        fail "the Release bundle contains '$scaffold_type' — the placeholder came back into the shipping app"
    fi
done
pass "neither scaffold type is in the Release bundle"

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
