#!/bin/bash
#
# M34 — what the APP's own menu says about a dimmed command, and where that stops.
#
# `menu-badge-lane.sh` measures two fixtures this repo built. It establishes the platform rule —
# AppKit folds a badge into `AXTitle`, SwiftUI does not — and it deliberately never touches the
# product. So after it, the one thing still resting on a one-off manual dump was the link that
# matters: **that the walker reaches the real menu, and that a dimmed command there explains
# itself.** `planning/evidence/M34-acceptance.md` records that link measured once, by hand, against
# `pid 63976`. A measurement taken once and written down is a claim about a day, not a lane.
#
# This is that link as a lane. It reads the running app's own menu bar and asserts three things
# about it, each with the control that makes its absence a measurement rather than a silence.
#
# ## What it can assert, and why exactly this much
#
# The badge itself is NOT on the accessibility plane for a SwiftUI-built menu, which is this app's
# menu. That is measured — by `menu-badge-lane.sh` on a fixture, and here on the product. So a lane
# reading this plane cannot read the badge, and nothing below pretends to.
#
# What it CAN read is the badge's sibling. `ShellMenuReasons` writes both out of one
# `availability(in:)` value in one pass: the long reason into `AXHelp`, the short form into
# `item.badge`. `AXHelp` does reach the plane. So the reason is measurable on the real menu, and the
# badge is measurable only through the invariant that the two are written together —
# `MenuReasonBadgePairingTests` is that invariant, and it is the second link of a two-link chain.
# Neither link claims to be the other. **The pixels are a third question and no rung here touches
# it** — see `planning/evidence/M34-oracle-lane.md`.
#
# ## The geometry channel, which looks open and is not
#
# `AXSize` is exposed on every menu item in this app, and reads `0.0x0.0` on every one of them.
# Measured 2026-08-29 across 178 items of the running Debug build. A menu that has never been opened
# has never been laid out, and a background app's menu is never opened — so the attribute is present
# by NAME and empty by VALUE, which is the exact shape of the finding M34 was filed to correct: the
# brief's first closed lane was an absence read off a list of names.
#
# So `assert_geometry_channel_closed` asserts the ZERO rather than assuming it. If a future macOS
# lays these out, this lane fails and says a lane has OPENED — `MenuBadgeTrailingAreaTests` measures
# the trailing area on an `NSMenu` it builds itself, and the day AXSize carries real numbers that
# claim can be re-made against the menu the user actually gets.
#
# Exit codes follow the house rule: 2 the harness could not run, 1 an assertion failed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/scripts/acceptance/menu-badge-fixture"
KIT="$ROOT/app/Sources/MCPRouterKit/Shell"

fail() { echo "FAIL: $*" >&2; exit 1; }
blocked() { echo "BLOCKED: $*" >&2; exit 2; }
pass() { echo "  ok — $*"; }

# ------------------------------------------------------------------ the assertions, as functions
#
# Each takes a dump and returns, so `menu-reason-plane-selftest.sh` can hand each one a doctored
# dump and require it to fire. An assertion nobody has watched fail is a claim about the platform
# AND a claim about itself, and a green run tests only the first.

# Every reason string the app can utter, read OUT OF THE SOURCE rather than typed here. A list
# copied into a test drifts silently the day someone edits the source; a list derived from it
# cannot. `reason(in:)` has exactly three shapes, and only the third is per-command.
reason_vocabulary() {
    local avail="$KIT/MenuCommandAvailability.swift" cmd="$KIT/MenuCommand.swift"
    [ -r "$avail" ] && [ -r "$cmd" ] || return 1
    # The two generic sentences, from CommandAvailability.reason — and only those two.
    # `.featureUnbuilt`'s generic sentence is deliberately NOT here: `reason(in:)` specialises that
    # answer for every command, so the generic form is a string the app can never utter, and
    # accepting it would widen this check to cover a sentence that would itself be a defect.
    sed -n '/var reason: String?/,/^    }/p' "$cmd" \
      | sed -n -E 's/^ *case \.(surfaceAbsent|needsServerSelection): "(.*)"$/\2/p'

    # The nine specialised ones, composed the way `reason(in:)` composes them.
    sed -n '/var unbuiltSubject/,/^    }/p' "$avail" \
      | sed -n 's/^ *case \.[A-Za-z]*: "\(.*\)"$/\1 hasn'"'"'t been built yet./p'
}

# The short forms, likewise from the source. Used only to prove they are ABSENT from the plane.
badge_vocabulary() {
    sed -n '/var badge: String?/,/^    }/p' "$KIT/MenuCommand.swift" \
      | sed -n 's/^ *case \.[a-zA-Z]*: "\(.*\)"$/\1/p'
}

# Every AXHelp the app's menu is carrying, with the item it is on.
reasons_in() { awk -F'\t' '$2 == "AXMenuItem" && $4 == "AXHelp" && $5 != "<nil>" && $5 != "" { print $3 "\t" $5 }' "$1"; }

assert_every_reason_is_the_apps_own() {
    local dump="$1" vocab title reason
    vocab="$(reason_vocabulary)" || return 2
    [ -n "$vocab" ] || { echo "the reason vocabulary could not be read out of $KIT" >&2; return 2; }
    while IFS=$'\t' read -r title reason; do
        [ -n "$reason" ] || continue
        printf '%s\n' "$vocab" | grep -qxF "$reason" \
          || { echo "'$title' carries a reason the app does not declare: '$reason'.
Every sentence on this plane is written by ShellMenuReasons out of MenuCommandAvailability, so one
that is not in that file came from somewhere else — or the file moved and this lane is reading a
vocabulary the app no longer uses." >&2; return 1; }
    done < <(reasons_in "$dump")
    return 0
}

assert_the_badge_is_not_on_this_plane() {
    local dump="$1" badge
    while IFS= read -r badge; do
        [ -n "$badge" ] || continue
        # `found` rather than `exit 0` in the rule: awk's `exit` RUNS the END block, so an
        # `END { exit 1 }` overrode the hit and this tripwire silently never fired. The selftest
        # caught it — which is the whole reason a tripwire asserting an absence needs one.
        awk -F'\t' -v b=", $badge" '$2 == "AXMenuItem" && $4 == "AXTitle" && index($5, b) { found = 1 } END { exit !found }' "$dump" \
          && { echo "a badge has reached AXTitle on the APP's own menu: an item's title ends ', $badge'.
This lane has OPENED. The badge on this app's real menu is now readable, so the assertion M34 could
not write is writable here rather than only on the AppKit fixture. Note that mac-shell.sh matches
menu item titles EXACTLY against the spec inventory, so it will report this good news as missing
commands." >&2; return 1; }
    done < <(badge_vocabulary)
    return 0
}

assert_geometry_channel_closed() {
    local dump="$1" offenders
    offenders="$(awk -F'\t' '$2 == "AXMenuItem" && $4 == "AXSize" && $5 != "0.0x0.0" { print "  " $3 " -> " $5 }' "$dump")"
    [ -z "$offenders" ] || { echo "AXSize is no longer zero on this app's menu items:
$offenders
This lane has OPENED. A menu item that reports a real size has been laid out, so the trailing-area
claim MenuBadgeTrailingAreaTests makes against an NSMenu it builds itself can now be re-made against
the menu the user actually gets. That is the stronger measurement and it should replace this one." >&2; return 1; }
    return 0
}

# The two controls, as functions for the same reason the three claims are: a control nobody has
# watched fail is not known to bind. These are what stop this lane reporting an absence having
# measured nothing — a probe that read no attributes, and a walk that reached a menu the app never
# annotated. Both were inline once; the selftest could then arm three of five assertions and the
# other two were taken on trust.
assert_the_probe_read_this_app() {
    local dump="$1" items
    items="$(awk -F'\t' '$2 == "AXMenuItem" && $4 == "AXTitle"' "$dump" | wc -l | tr -d ' ')"
    [ "$items" -gt 50 ] \
      || { echo "only $items menu items were read — the probe reached almost nothing, so no absence below is a measurement" >&2; return 1; }
    [ "$(awk -F'\t' '$2 == "AXMenuItem" && $3 == "Quit MCP Router" && $4 == "AXMenuItemCmdChar" { print $5 }' "$dump")" = "Q" ] \
      || { echo "the probe cannot read a chord back off this app, so nothing below is a measurement" >&2; return 1; }
    printf '%s\n' "$items"
    return 0
}

assert_the_walker_ran() {
    local dump="$1" reasoned
    reasoned="$(reasons_in "$dump" | wc -l | tr -d ' ')"
    [ "$reasoned" -gt 0 ] \
      || { echo "not one item carries a reason. ShellMenuReasons matched nothing, or the walk never reached
the app's own menus — either way the absences below are about a menu nobody annotated." >&2; return 1; }
    printf '%s\n' "$reasoned"
    return 0
}

# Everything above is a definition. The selftest sources this file to reach the three assertions,
# so the point it stops reading is marked here rather than guessed at from outside by a `sed` range
# that any edit would silently break.
if [ -n "${MENU_REASON_PLANE_SOURCE_ONLY:-}" ]; then return 0; fi

# ------------------------------------------------------------------------------------- the run
APP="${MENU_REASON_PLANE_APP:-$ROOT/app/.derived/Build/Products/Debug/MCPRouter.app}"
[ -x "$APP/Contents/MacOS/MCPRouter" ] || blocked "no Debug build at $APP — run: make build-mac"

# The bundle resolved to the one name the OS will use for it, which is NOT always the name this
# script was handed. `.worktrees` is a symlink onto another volume on this machine, so a worktree
# has two spellings — `worktree-preflight.sh` is a whole gate about the two ways that breaks a
# build. It breaks a process lookup too, and more quietly: launched through the logical spelling,
# the app's argv carries the PHYSICAL one, so `pgrep -f "$APP/..."` matches nothing and the lane
# reports "the app never appeared in the process table" about an app that started perfectly.
# Measured 2026-08-29: `open -g` on `<home>/Dev/mcp-router/.worktrees/M34/...` produced a process
# whose argv read `/Volumes/LLMs/Dev/mcp-router/.worktrees/M34/...`.
APP_PHYS="$(cd "$APP" && pwd -P)" || blocked "could not resolve $APP to a physical path"

WORK="$(mktemp -d)"
LAUNCHED=""
cleanup() {
    local status=$?
    [ -n "$LAUNCHED" ] && kill "$LAUNCHED" 2>/dev/null
    rm -rf "$WORK"
    return $status
}
trap cleanup EXIT

FRONT_BEFORE="$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)" \
  || blocked "could not read the frontmost application — System Events is not answering"
case "$FRONT_BEFORE" in
    "MCP Router"|MCPRouter) blocked "MCP Router is already frontmost — this lane cannot then prove it never took the screen" ;;
esac

swiftc -O -o "$WORK/axattrs" "$SRC/axattrs.swift" 2>"$WORK/axattrs.log" \
  || { cat "$WORK/axattrs.log" >&2; blocked "could not build the axattrs probe"; }

# Without the grant every read below returns nothing, which is indistinguishable from the absences
# this lane asserts. A missing grant reported as a measured absence is the failure M34 exists about.
"$WORK/axattrs" 0 2>&1 | grep -q "not trusted" \
  && blocked "no Accessibility grant, so every absence below would be unmeasurable rather than measured"

pkill -f "$APP_PHYS/Contents/MacOS/MCPRouter" 2>/dev/null || true
perl -e 'select undef, undef, undef, 1'
open -g "$APP" || blocked "the app would not launch"
# Polled rather than slept: a fixed sleep long enough for a cold launch is wasted on every warm one,
# and one short enough for a warm launch reports a cold one as "never started".
for _ in $(seq 60); do
    # `|| true`: `pgrep` exits 1 when it matches nothing, and under `set -e` an assignment whose
    # command substitution fails kills the script — silently, with no message and exit 1, which
    # reads exactly like a failed assertion.
    LAUNCHED="$(pgrep -f "$APP_PHYS/Contents/MacOS/MCPRouter" | head -1 || true)"
    [ -n "$LAUNCHED" ] && break
    perl -e 'select undef, undef, undef, 0.5'
done
[ -n "$LAUNCHED" ] || blocked "the app never appeared in the process table"
# ShellMenuReasons re-applies ten times a second and runs first against `.none`, so a dump taken
# immediately can catch the pre-live pass. Two seconds is twenty passes.
perl -e 'select undef, undef, undef, 4'

"$WORK/axattrs" "$LAUNCHED" > "$WORK/app.tsv" 2>&1 || blocked "the app's menu bar could not be read"

# The dump this run read, kept where a campaign case can cite it. Off by default: it is a few
# hundred KB per run and a lane that writes into the tree on every invocation is a lane that makes
# a merge refuse. A case citing "the lane said so" cites a transcript; this is the measurement the
# transcript was read from.
if [ -n "${MENU_REASON_PLANE_DUMP:-}" ]; then
    cp "$WORK/app.tsv" "$MENU_REASON_PLANE_DUMP" || blocked "could not write the dump to $MENU_REASON_PLANE_DUMP"
    echo "  (dump written to $MENU_REASON_PLANE_DUMP)"
fi

# ------------------------------------------------------------------------------------ controls
#
# Three, and each one closes a different way this run could report an absence having measured
# nothing: a probe that reads no attributes, a walk that never reached this app, and a walk that
# reached it before ShellMenuReasons had run.
ITEMS="$(assert_the_probe_read_this_app "$WORK/app.tsv")" || exit 1
pass "$ITEMS menu items read, and a known chord reads back — the probe works on this app"

REASONED="$(assert_the_walker_ran "$WORK/app.tsv")" || exit 1
pass "$REASONED items carry a reason written by the walker — it reached the real menu"

# ---------------------------------------------------------------------------------- the claims
assert_every_reason_is_the_apps_own "$WORK/app.tsv" || exit 1
pass "every reason on the plane is one MenuCommandAvailability declares"

assert_the_badge_is_not_on_this_plane "$WORK/app.tsv" || exit 1
pass "no badge has reached AXTitle on the app's own menu — the SwiftUI limit holds for the product"

assert_geometry_channel_closed "$WORK/app.tsv" || exit 1
pass "AXSize is present and zero on every item — the geometry channel is named, not open"

# --------------------------------------------------------------------------------------- rule 1
#
# The invariant is "**this app** never comes to the front", not "the frontmost app never changes" —
# `mac-shell.sh:207` says so in the same words and for the same measured reason, and this lane was
# written with the stricter reading first and watched give a false alarm for it. Measured
# 2026-08-29: frontmost went from `Google Chrome for Testing` to `ghostty` mid-run, neither of them
# this app and neither of them this lane's doing, and the run failed reporting a screen theft that
# had not happened. A rule-1 check that cries wolf is worse than none, because rule 1 is the one
# that has to be believed the day it does fire.
FRONT_AFTER="$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)"
case "$FRONT_AFTER" in
    "MCP Router"|MCPRouter)
        fail "the app came to the front — UI_VERIFICATION.md rule 1 forbids the developer loop taking the user's screen" ;;
esac
if [ "$FRONT_BEFORE" != "$FRONT_AFTER" ]; then
    pass "the app stayed in the background; the user moved from '$FRONT_BEFORE' to '$FRONT_AFTER' during the run"
else
    pass "the app stayed in the background — frontmost is still '$FRONT_AFTER'"
fi
