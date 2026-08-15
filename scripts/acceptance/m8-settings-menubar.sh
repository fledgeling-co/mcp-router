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

# ---------------------------------------------------------------- A2, A30 · the Settings pane
#
# Selected by pressing the sidebar's own row, **not** by the menu — and that is a measurement rather
# than a preference. Driving `MCP Router ▸ Settings` through System Events succeeds (the menu item
# is found and clicked) and changes nothing, because `ShellCommands` reaches the model through
# `@FocusedValue(\.shellModel)`, and a backgrounded app with no key window has no focused value. The
# router then runs `perform(command, on: nil)`, which is deliberately a safe no-op —
# `ShellCommandRouterTests.performWithoutAModelIsSafe` asserts exactly that.
#
# So a menu-driven check of a background app would be measuring focus, not the pane. `axkit select`
# performs `AXPress` on the row, which is process-directed and needs no focus at all.
"$AXKIT" select "$PID" "Settings" >/dev/null 2>&1 \
  || fail "could not press the Settings row in the sidebar"
sleep 1.5

"$AXKIT" dump "$PID" window > "$WORK/settings.txt" 2>/dev/null || blocked "could not read the window"

if grep -q "isn't built yet" "$WORK/settings.txt"; then
    fail "A2 · Settings still renders the scaffold placeholder"
else
    pass "A2 · Settings renders a board, not the placeholder"
fi

for group in "Router" "Menu bar" "Warm set" "Control token"; do
    if grep -q "$group" "$WORK/settings.txt"; then
        pass "A30 · the '$group' group is on screen"
    else
        fail "A30 · the '$group' group is missing from the pane"
    fi
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

# A5 — no memory figure, measured on what is actually rendered rather than only in source.
if grep -qE '[0-9]+ ?(MB|KB|GB)' "$WORK/settings.txt"; then
    fail "A5 · a memory figure is on screen; the router observes none"
else
    pass "A5 · no memory figure anywhere in the rendered pane"
fi

# The token's value is never rendered. The fixture build stores no real token, so this asserts the
# shape: the row says what it says and shows nothing that looks like a credential.
if grep -qE 'sk-|Bearer |[A-Za-z0-9]{32,}' "$WORK/settings.txt"; then
    fail "A7 · something credential-shaped is on screen"
else
    pass "A7 · nothing credential-shaped is rendered"
fi

# The window title says what you are looking at (§3.7).
TITLE="$("$AXKIT" title "$PID" 2>/dev/null || true)"
[ "$TITLE" = "Settings" ] \
  && pass "§3.7 · the window title is 'Settings'" \
  || fail "§3.7 · the window title is '$TITLE', not 'Settings'"

# A9 — the disabled control dims **in place** and carries its reason, rather than disappearing.
#
# This asserts the PAIRING §3.4 actually specifies — "disabled dims in place with a discoverable
# reason" — rather than the presence of one string. The difference is not academic; the old form
# was:
#
#     grep -q "Forget the stored token"      -> pass
#     grep -q "There is no stored token…"    -> pass, else FAIL "carries no reason"
#
# which demands the reason **unconditionally**, of a control that is only sometimes disabled.
# `SettingsPresentation.TokenStatus.canForget` is true for `.stored` and `.rejected`, and in those
# two states the button is correctly ENABLED and correctly carries no reason — §3.4 asks for a
# reason on a disabled control, not on every control. So the old check failed a correct app.
#
# **And it was self-poisoning, which is why it looked intermittent.** Measured here, same tree,
# same binary, same scenario, back to back:
#
#     run 1, keychain clean   -> 21 passed, 0 failed, exit 0
#     run 2, keychain primed  -> 20 passed, 1 failed, exit 1   (this assertion alone)
#
# The app's first run reads the router's token file and stores the token in this Mac's keychain, so
# the status moves `.absent` -> `.stored`, `canForget` flips false -> true, and the button becomes
# legitimately enabled. **Running this script once changes the machine state that decides its own
# next verdict.** That is the whole of the 19/2 -> 20/1 -> 21/0 drift across G1 and D2; it was never
# flaky, and it was never a product defect. `SettingsBoard.forgetButton` has always set
# `.disabled()`, `.help()` and `.accessibilityHint()` together.
#
# The form below is true in both states and stronger in both directions: a disabled control with no
# reason fails, and so does an enabled control that carries one.
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

# The empty warm set says what happens instead, rather than 'No items' (§5).
grep -q "None of .* servers" "$WORK/settings.txt" \
  && pass "§5 · the empty warm set states the count rather than 'No items'" \
  || fail "§5 · no warm-set summary on screen"

# The menu-bar checkbox is a real control, checked by default.
grep -q "Show MCP Router in the menu bar" "$WORK/settings.txt" \
  && pass "the menu-bar checkbox is on screen with its label" \
  || fail "the menu-bar checkbox is missing"

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
