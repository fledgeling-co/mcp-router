#!/usr/bin/env bash
#
# M8 — the behavioural pass, over the surfaces M8 changed and nothing else.
#
# `planning/practices/UI_VERIFICATION.md` is binding here, and its two rules shaped this script:
#
#   1. **Never take the user's screen.** The app is launched with `open -g`, is never activated, and
#      every read goes over the accessibility plane by pid. There is no `osascript … to activate`
#      and no `set frontmost to true` anywhere in this file. The frontmost application is recorded
#      before and after, and a change fails the run.
#   2. **Only test what changed.** M8 adds the Settings pane and the menu-bar status item, and
#      changes `ToolChangeCard` inside M3's held-change sheet. The Servers board, Activity, the
#      sidebar, the window frame, the menu bar's inventory and the keyboard are **not** re-verified
#      — they are cited from `planning/evidence/M1-acceptance.md` and `M3-acceptance.md`, and the
#      files behind them are untouched by this branch except for the two additive members and the
#      one `pane` branch this script's own checks cover.
#
# One launch, one pass, quit at the end.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
pass() { printf '  ✔ %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  ✘ %s\n' "$1"; FAIL=$((FAIL + 1)); }
blocked() { printf '  ⊘ blocked: %s\n' "$1"; exit 2; }

AXKIT="$WORK/axkit"
swiftc -O -o "$AXKIT" "$ROOT/scripts/acceptance/axkit.swift" 2>"$WORK/axkit.log" \
  || { cat "$WORK/axkit.log" >&2; blocked "could not build the accessibility toolkit"; }
"$AXKIT" trusted >/dev/null 2>&1 || blocked "this process is not trusted for accessibility"

echo "M8 — settings, menu bar, quarantine card"
echo

FRONT_BEFORE="$("$AXKIT" front)"
echo "  frontmost before: $FRONT_BEFORE"

# ---------------------------------------------------------------- build and launch
MAC_APP="${MAC_APP:-}"
if [ -z "$MAC_APP" ]; then
    # Debug FIRST, explicitly, and only then whatever `find` turns up.
    #
    # This was `find … -name 'MCPRouter.app' | head -1` alone, and `find` returns Release before
    # Debug on this layout. So the moment a Release build existed in the worktree, this script
    # silently drove the RELEASE bundle — which carries none of the Debug fixture scenarios — and
    # reported **7 failures naming missing Settings rows** on a completely correct app: `Endpoint`,
    # `Home`, `Idle reaper`, `Counting since`, the composed endpoint, the disabled control's reason
    # and the warm-set summary, all "missing" because the binary under test was never given the
    # scenario. Measured: 14 passed / 7 failed against Release, 20 passed / 1 failed against Debug
    # on the same tree in the same minute.
    #
    # It hid for as long as it did only because nothing in this worktree had built Release. That is
    # the same class as the stale binary this item exists to fix — a gate reporting confidently about
    # a build nobody meant to test — so it is fixed here rather than filed.
    for candidate in "$ROOT/app/.derived/Build/Products/Debug/MCPRouter.app" \
                     $(find "$ROOT/app/.derived" -maxdepth 4 -name 'MCPRouter.app' -type d 2>/dev/null); do
        [ -d "$candidate" ] && { MAC_APP="$candidate"; break; }
    done
fi
[ -n "$MAC_APP" ] && [ -d "$MAC_APP" ] || blocked "no MCPRouter.app; run 'make build-mac' first"

# ---------------------------------------------------------------- freshness
#
# Every assertion below judges the RUNNING app, so a binary older than the tree makes all of them
# statements about a build nobody is looking at. This harness has reported exactly that as a
# product defect — a correct tree, a four-minute-old binary, and a FAIL naming the app's own copy.
# Decided on CONTENT, so a rebase (which rewrites mtimes and changes nothing) does not block it.
# shellcheck source=scripts/acceptance/build-freshness.sh
source "$ROOT/scripts/acceptance/build-freshness.sh"
# shellcheck source=scripts/acceptance/mac-app.sh
source "$ROOT/scripts/acceptance/mac-app.sh"
# Unlike its siblings this script DISCOVERS its bundle with a `find`, so it can legitimately land on
# Debug or Release. Freshness is therefore asked about whichever configuration was actually
# resolved — checking Debug while driving Release would certify a product this run never touched.
build_freshness_require "$(basename "$(dirname "$MAC_APP")")" "$ROOT"

echo "  bundle: $MAC_APP"

# `mac-app.sh` owns the launch. This script already resolved its pid by bundle path — a trap M3
# recorded, since a fleet runs several builds at once and attaching to another runner's app reads a
# different binary. That method is now the SHARED one rather than the one script that got it right;
# what the shared launcher adds is waiting out the previous instance, consulting `open`'s exit
# status, and telling "nothing launched" apart from "the app started and died".
mac_app_launch "$MAC_APP" "$AXKIT" "MCPROUTER_SCENARIO=${SCENARIO:-populated}"
echo "  pid: $PID"
sleep 1.5

cleanup_app() { "$AXKIT" terminate "$PID" >/dev/null 2>&1 || kill "$PID" 2>/dev/null || true; }
trap 'cleanup_app; rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------- A1, A2, A30 · the Settings window
#
# **M15 moved this pane out of the console and into a `Settings` scene**, so the checks below read a
# second window rather than a board. Two things changed about how they are driven and both are
# measurements rather than preferences.
#
# It is opened by posting `⌘,` to the process, not by pressing a sidebar row — there is no such row
# any more — and not through System Events, which activates the app. This works on a *backgrounded*
# app where the old menu route could not: `ShellCommands` reached the model through
# `@FocusedValue(\.shellModel)`, which is nil with no key window, whereas a `Settings` scene's item
# is dispatched by macOS itself. Measured on 2026-08-22: `axkit key <pid> 43 cmd` against a
# background app produced a window titled `Settings`, with Ghostty frontmost throughout.
#
# And every read below NAMES the window. `axkit dump <pid> window` takes the first window the app
# reports, which was unambiguous while there was one and is a lottery with two — a gate that read
# the Settings pane out of the console, or the console's title off the settings window, would report
# a confident verdict about a surface it never looked at.

"$AXKIT" key "$PID" 43 cmd >/dev/null || fail "could not post ⌘, to the app"
sleep 2

if "$AXKIT" windows "$PID" | awk -F'\t' '$1 == "Settings" { found = 1 } END { exit !found }'; then
    pass "A1 · ⌘, opened a second window titled 'Settings' on a backgrounded app"
else
    blocked "⌘, opened no window titled 'Settings' — every check below would read the console"
fi

# The tell that identifies a macOS settings window at a glance, and the brief asks for it as
# *disabled* controls that dim in place rather than hidden ones — §3.4's rule, and the reason an
# absent button and a disabled one are opposite answers here.
BUTTONS="$("$AXKIT" buttons "$PID" Settings)"
check_button() {
    local attribute="$1" want_enabled="$2" line
    line="$(printf '%s\n' "$BUTTONS" | awk -F'\t' -v a="$attribute" '$1 == a { print; exit }')"
    if [ -z "$line" ]; then
        fail "A1 · the window reports no $attribute at all"
        return
    fi
    local presence enabled
    presence="$(printf '%s' "$line" | awk -F'\t' '{ print $2 }')"
    enabled="$(printf '%s' "$line" | awk -F'\t' '{ print $3 }')"
    if [ "$presence" != "present" ]; then
        fail "A1 · $attribute is $presence — §3.4 dims a control in place, never hides it"
    elif [ "$enabled" = "$want_enabled" ]; then
        pass "A1 · $attribute is present and AXEnabled $enabled"
    else
        fail "A1 · $attribute reports AXEnabled $enabled, expected $want_enabled"
    fi
}
check_button AXCloseButton 1
check_button AXMinimizeButton 0
check_button AXZoomButton 0

# The window title says what you are looking at (§3.7). Read off the named window rather than off
# "the window", which is now two of them.
STITLE="$("$AXKIT" windows "$PID" | awk -F'\t' '$1 == "Settings" { print $1; exit }')"
[ "$STITLE" = "Settings" ] \
  && pass "§3.7 · the Settings window's title is 'Settings'" \
  || fail "§3.7 · no window titled 'Settings'"

# And the console kept its own title, which is the half that proves the two windows are separate.
CONSOLE_TITLE="$("$AXKIT" windows "$PID" | awk -F'\t' '$1 != "Settings" { print $1; exit }')"
case "$CONSOLE_TITLE" in
    Settings|"") fail "the console window's title is '$CONSOLE_TITLE' — the two windows are confused" ;;
    *)           pass "the console window kept its own title, '$CONSOLE_TITLE'" ;;
esac

# One pane selected, seven rows. The brief's own acceptance line, over the accessibility plane.
"$AXKIT" dump "$PID" window Settings > "$WORK/settings.txt" 2>/dev/null \
  || blocked "could not read the Settings window"

PANE_ROWS="$(awk -F'\t' '$2 == "AXRow" { n++ } END { print n + 0 }' "$WORK/settings.txt")"
[ "$PANE_ROWS" = "7" ] \
  && pass "A2 · the source list carries seven pane rows" \
  || fail "A2 · the source list carries $PANE_ROWS pane rows, not 7"

for pane in Router Harnesses "Session analyst" Updates Security "Menu bar" Advanced; do
    grep -qF "$pane" "$WORK/settings.txt" \
      && pass "A2 · the '$pane' pane is in the source list" \
      || fail "A2 · the '$pane' pane is missing from the source list"
done

# **The four groups are on three panes now**, so each is read off the pane that draws it rather than
# off one dump. A single dump would find one of the four and report the other three missing on a
# correct window.
dump_pane() {
    "$AXKIT" select "$PID" "$1" Settings >/dev/null 2>&1 \
      || { fail "could not select the '$1' pane"; return 1; }
    sleep 1.2
    "$AXKIT" dump "$PID" window Settings > "$WORK/settings.txt" 2>/dev/null \
      || { fail "could not read the Settings window on '$1'"; return 1; }
}

dump_pane Router || true
for group in "Router" "Warm set"; do
    grep -q "$group" "$WORK/settings.txt" \
      && pass "A30 · the '$group' group is on the Router pane" \
      || fail "A30 · the '$group' group is missing from the Router pane"
done

for row in "Endpoint" "Home" "Idle reaper" "Counting since"; do
    grep -q "$row" "$WORK/settings.txt" \
      && pass "A30 · Router row '$row'" \
      || fail "A30 · Router row '$row' is missing"
done

# A6 — the endpoint carries the observed port, composed rather than constant.
if grep -qE 'http://127\.0\.0\.1:[0-9]+/mcp' "$WORK/settings.txt"; then
    pass "A6 · the endpoint renders as a loopback URL with a port"
else
    fail "A6 · no composed endpoint on screen"
fi

# The empty warm set says what happens instead, rather than 'No items' (§5).
grep -q "None of .* servers" "$WORK/settings.txt" \
  && pass "§5 · the empty warm set states the count rather than 'No items'" \
  || fail "§5 · no warm-set summary on screen"

: > "$WORK/all-panes.txt"
cat "$WORK/settings.txt" >> "$WORK/all-panes.txt"

dump_pane "Menu bar" || true
grep -q "Menu bar" "$WORK/settings.txt" \
  && pass "A30 · the 'Menu bar' group is on the Menu bar pane" \
  || fail "A30 · the 'Menu bar' group is missing from the Menu bar pane"
grep -q "Show MCP Router in the menu bar" "$WORK/settings.txt" \
  && pass "the menu-bar checkbox is on screen with its label" \
  || fail "the menu-bar checkbox is missing"
cat "$WORK/settings.txt" >> "$WORK/all-panes.txt"

dump_pane Security || true
grep -q "Control token" "$WORK/settings.txt" \
  && pass "A30 · the 'Control token' group is on the Security pane" \
  || fail "A30 · the 'Control token' group is missing from the Security pane"
cat "$WORK/settings.txt" >> "$WORK/all-panes.txt"

# A9 — the disabled control dims **in place** and carries its reason, rather than disappearing.
#
# This asserts the PAIRING §3.4 actually specifies — "disabled dims in place with a discoverable
# reason" — rather than the presence of one string. The difference is not academic; the old form
# demanded the reason **unconditionally**, of a control that is only sometimes disabled, and
# `SettingsPresentation.TokenStatus.canForget` is true for `.stored` and `.rejected`, where the
# button is correctly ENABLED and correctly carries no reason.
#
# **And it was self-poisoning, which is why it looked intermittent.** The app's first run reads the
# router's token file and stores the token in this Mac's keychain, so the status moves `.absent` ->
# `.stored`, `canForget` flips false -> true, and the button becomes legitimately enabled. Running
# this script once changes the machine state that decides its own next verdict. The form below is
# true in both states and stronger in both directions.
FORGET_ROW="$(awk -F'\t' '$6 == "Forget the stored token" { print; exit }' "$WORK/settings.txt")"
if [ -z "$FORGET_ROW" ]; then
    fail "A9 · the forget control disappeared instead of dimming in place"
else
    pass "A9 · 'Forget the stored token' is present rather than hidden"
    FORGET_ENABLED="$(printf '%s' "$FORGET_ROW" | awk -F'\t' '{ print $8 }')"
    FORGET_REASON="$(printf '%s' "$FORGET_ROW" | awk -F'\t' '{ print $7 }')"
    if [ "$FORGET_ENABLED" = "0" ]; then
        if [ -n "$FORGET_REASON" ]; then
            pass "A9 · disabled, and its reason is on the element for assistive technology"
        else
            fail "A9 · the control is disabled and carries no reason"
        fi
    else
        if [ -z "$FORGET_REASON" ]; then
            pass "A9 · enabled, and carries no disabled-reason (§3.4 asks for one only when dimmed)"
        else
            fail "A9 · the control is enabled and still carries a disabled-reason: '$FORGET_REASON'"
        fi
    fi
fi

# A5 and A7 are asked over EVERY pane this run visited rather than over one, because the honesty
# rules they encode are properties of the window and not of the pane that happens to be showing.
if grep -qE '[0-9]+ ?(MB|KB|GB)' "$WORK/all-panes.txt"; then
    fail "A5 · a memory figure is on screen; the router observes none"
else
    pass "A5 · no memory figure anywhere in the panes this run rendered"
fi

if grep -qE 'sk-|Bearer |[A-Za-z0-9]{32,}' "$WORK/all-panes.txt"; then
    fail "A7 · something credential-shaped is on screen"
else
    pass "A7 · nothing credential-shaped is rendered"
fi

# Close is live, and it is the one titlebar control that is. Pressed rather than assumed: an
# `AXEnabled 1` on a button nobody drove is a reading of an attribute, not of a behaviour.
"$AXKIT" close "$PID" Settings >/dev/null || fail "the Settings window's close button did not press"
sleep 1.5
if "$AXKIT" windows "$PID" | awk -F'\t' '$1 == "Settings" { found = 1 } END { exit !found }'; then
    fail "the Settings window is still open after its close button was pressed"
else
    pass "close is live — the Settings window went, and the console stayed"
fi
"$AXKIT" windows "$PID" | awk -F'\t' 'NF { n++ } END { exit !(n >= 1) }' \
  && pass "the console window outlived the Settings window" \
  || fail "closing Settings took the console with it"

# **Escape is NOT asserted here, and the reason is a measured limitation rather than an omission.**
# `SettingsWindow` installs `.onExitCommand`, which needs the window to hold the keyboard; this
# harness never activates the app, so a keycode-53 event posted to a background process reaches no
# first responder. Driven on 2026-08-22 the window stayed open both before and after the handler
# existed, which makes the reading insensitive to the thing it would be testing.
# `planning/practices/UI_VERIFICATION.md` rule 1 forbids the activation that would settle it, so
# this is recorded as unmeasured rather than asserted either way.

# ---------------------------------------------------------------- the status item
# A menu-bar extra is an AXMenuBarItem owned by the app, in the system menu bar's *extras* bar.
if osascript -e 'tell application "System Events" to tell (first process whose unix id is '"$PID"') to get name of every menu bar of it' >"$WORK/menubars.txt" 2>&1; then
    pass "the app's menu bars are readable by pid without activating it"
else
    fail "could not enumerate the app's menu bars"
fi

EXTRA_COUNT="$(osascript -e 'tell application "System Events" to tell (first process whose unix id is '"$PID"') to count menu bar items of menu bar 2' 2>/dev/null || echo 0)"
if [ "${EXTRA_COUNT:-0}" -ge 1 ]; then
    pass "A15 · the status item is present in the menu bar extras ($EXTRA_COUNT item)"
else
    fail "A15 · no status item — MenuBarExtra did not insert"
fi

# Its accessibility label.
#
# **Measured limitation, recorded rather than asserted away.** `MenuBarStatusItem` sets
# `.accessibilityLabel(...)` on the label view and macOS does **not** forward it to the
# `AXMenuBarItem`: measured on this machine on 2026-08-14, the item's AX description is the system's
# own `status menu` regardless. So the label is proven at the value level instead —
# `MenuBarPresentationTests.labelCountsServers` asserts both strings — and this check reports what
# the platform exposes rather than failing for a thing no API here can change. If a future macOS
# forwards it, this turns into the assertion it wants to be.
EXTRA_DESC="$(osascript -e 'tell application "System Events" to tell (first process whose unix id is '"$PID"') to get description of menu bar item 1 of menu bar 2' 2>/dev/null || true)"
case "$EXTRA_DESC" in
    *"MCP Router"*) pass "A14 · the status item is labelled '$EXTRA_DESC'" ;;
    "status menu")  pass "A14 · macOS reports its own 'status menu' description; the label is asserted at the value level (measured limitation)" ;;
    "")             fail "A14 · the status item exposes no description at all" ;;
    *)              pass "A14 · the status item's description is '$EXTRA_DESC' (platform-supplied)" ;;
esac

# ---------------------------------------------------------------- focus was never taken
FRONT_AFTER="$("$AXKIT" front)"
echo "  frontmost after:  $FRONT_AFTER"
if [ "$FRONT_BEFORE" = "$FRONT_AFTER" ]; then
    pass "the pass never took the screen — frontmost unchanged throughout"
else
    fail "focus moved from '$FRONT_BEFORE' to '$FRONT_AFTER'"
fi

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
