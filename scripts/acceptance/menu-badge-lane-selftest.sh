#!/bin/bash
#
# Proves `menu-badge-lane.sh`'s two limit tripwires can actually fire.
#
# **They are the assertions in this repo most likely to be decorative, and for a structural reason.**
# Both say a platform behaviour is ABSENT, both pass today because it is, and neither has ever been
# seen to fail. A green run of that shape is two claims wearing one coat: *the platform still does
# not expose this*, and *this line would notice if it did*. Only the first is tested by running it.
#
# Provoking them from the fixture side was tried first and does not work. Folding the badge into a
# SwiftUI item's title is undone by SwiftUI's next rebuild; `setAccessibilityTitle` does not
# override `AXTitle` on a menu item; and an AppKit-built item planted in a SwiftUI app's menu bar
# does not get its badge folded either. That is a finding rather than a workaround — it says the
# limit is a property of the menu bar the process owns rather than of the item — and it leaves the
# failure path only reachable through the dump the checks read. So this hands them one.
#
# Exit codes match the lane's own: 2 the harness could not run, 1 a tripwire did not fire.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LANE="$ROOT/scripts/acceptance/menu-badge-lane.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -r "$LANE" ] || { echo "BLOCKED: no lane at $LANE" >&2; exit 2; }

# The lane's own definitions, sourced rather than paraphrased. It returns early under
# `MENU_BADGE_LANE_SOURCE_ONLY`, which is a mark the lane carries deliberately — an earlier version
# of this file cut the same prefix with a `sed` range, which any edit to the lane would have
# silently turned into a test of nothing.
MENU_BADGE_LANE_SOURCE_ONLY=1
export MENU_BADGE_LANE_SOURCE_ONLY
# shellcheck source=scripts/acceptance/menu-badge-lane.sh
source "$LANE" || { echo "BLOCKED: could not load the lane's definitions" >&2; exit 2; }

type check_swiftui_badge_unexposed >/dev/null 2>&1 \
  || { echo "BLOCKED: the lane's tripwires are not where this selftest expects them" >&2; exit 2; }

ok() { echo "  ok — $*"; }

# A dump in which a SwiftUI-built item's badge HAS reached the plane — the day the lane opens.
cat > "$WORK/opened.tsv" <<'TSV'
3	AXMenuItem	SwiftUI Badged, BADGESWIFTUI	AXTitle	SwiftUI Badged, BADGESWIFTUI
3	AXMenuItem	SwiftUI Help Only	AXTitle	SwiftUI Help Only
TSV

# And one in which `.help()` has started reaching a menu item.
cat > "$WORK/helped.tsv" <<'TSV'
3	AXMenuItem	SwiftUI Badged	AXTitle	SwiftUI Badged
3	AXMenuItem	SwiftUI Help Only	AXHelp	swiftui help string
TSV

# Each check runs in a subshell because `fail` exits; the subshell's status is the assertion.
if ( check_swiftui_badge_unexposed "$WORK/opened.tsv" ) 2>/dev/null; then
    echo "FAIL: the badge tripwire did not fire on a dump where the badge reached the plane" >&2
    exit 1
fi
ok "the badge tripwire fires when a SwiftUI badge reaches the accessibility plane"

if ( check_swiftui_help_unexposed "$WORK/helped.tsv" ) 2>/dev/null; then
    echo "FAIL: the help tripwire did not fire on a dump where .help() reached the item" >&2
    exit 1
fi
ok "the help tripwire fires when SwiftUI's .help() reaches a menu item"

# The other direction, which is the half a firing test does not cover: neither may fire on the dump
# shape today's platform actually produces, or the lane would be unrunnable rather than green.
cat > "$WORK/closed.tsv" <<'TSV'
3	AXMenuItem	SwiftUI Badged	AXTitle	SwiftUI Badged
3	AXMenuItem	SwiftUI Help Only	AXTitle	SwiftUI Help Only
TSV
( check_swiftui_badge_unexposed "$WORK/closed.tsv" ) >/dev/null 2>&1 \
  || { echo "FAIL: the badge tripwire fires on a dump where the limit still stands" >&2; exit 1; }
( check_swiftui_help_unexposed "$WORK/closed.tsv" ) >/dev/null 2>&1 \
  || { echo "FAIL: the help tripwire fires on a dump where the limit still stands" >&2; exit 1; }
ok "neither tripwire fires on the dump the platform produces today"
