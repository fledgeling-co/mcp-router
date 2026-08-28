#!/bin/bash
#
# Proves `menu-reason-plane.sh`'s three claims can go red — and that none of them goes red on the
# dump today's platform actually produces.
#
# All three assert an ABSENCE: no foreign reason, no badge on the plane, no laid-out geometry. Each
# passes today because the condition is genuinely absent, and a run that only ever sees the absent
# case tests the platform rather than the check. That is two claims wearing one coat — *the platform
# still does not do this*, and *this line would notice if it did* — and only the first is under test
# when the lane is green.
#
# The third case is the one that matters and it is the two-way control: neither tripwire may fire on
# a real dump. Without it the first two would pass over a condition that had become permanently
# unreachable — a check that cannot fire and a check that correctly does not fire look identical
# from the outside.
#
# Exit: 0 all three cases behaved, 1 one did not, 2 the harness could not run.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LANE="$ROOT/scripts/acceptance/menu-reason-plane.sh"
[ -r "$LANE" ] || { echo "BLOCKED: $LANE is not readable" >&2; exit 2; }

# shellcheck source=/dev/null
MENU_REASON_PLANE_SOURCE_ONLY=1 source "$LANE" || { echo "BLOCKED: could not source the lane" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
rc=0
note() { printf '  %s\n' "$*"; }

# A dump of the shape the probe emits: depth, role, title, attribute, value.
row() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"; }

# ---------------------------------------------------------------- the dump today's platform gives
#
# Eleven reasons the app really carries, a title with no badge folded into it, and AXSize zero —
# which is what every one of the 178 items on the running build reports.
clean="$WORK/clean.tsv"
: > "$clean"
row 3 AXMenuItem "Quit MCP Router" AXMenuItemCmdChar "Q" >> "$clean"
while IFS= read -r sentence; do
    row 3 AXMenuItem "Some Command" AXHelp "$sentence" >> "$clean"
done < <(reason_vocabulary)
row 3 AXMenuItem "Wake Selected Server" AXTitle "Wake Selected Server" >> "$clean"
# The probe control's floor is 50 titled items, so a clean dump has to clear it — a fixture that
# did not would make the control fire here and the two-way case above would read as a real alarm.
for i in $(seq 60); do row 3 AXMenuItem "Item $i" AXTitle "Item $i" >> "$clean"; done
row 3 AXMenuItem "Wake Selected Server" AXSize "0.0x0.0" >> "$clean"
row 3 AXMenuItem "Run Doctor" AXSize "0.0x0.0" >> "$clean"

for check in assert_the_probe_read_this_app assert_the_walker_ran assert_every_reason_is_the_apps_own \
             assert_the_badge_is_not_on_this_plane assert_geometry_channel_closed; do
    # stdout too, not only stderr: the two controls RETURN their count on stdout, and an
    # unredirected run prints it into the middle of this transcript.
    if "$check" "$clean" >/dev/null 2>&1; then
        note "ok   — $check is silent on the dump today's platform produces"
    else
        note "FAIL — $check fires on a real dump, so a green lane run would be a false alarm"
        rc=1
    fi
done

# ------------------------------------------------------------------- a reason the app never wrote
foreign="$WORK/foreign.tsv"
cp "$clean" "$foreign"
row 3 AXMenuItem "Wake Selected Server" AXHelp "Something else set this tool tip." >> "$foreign"
if assert_every_reason_is_the_apps_own "$foreign" 2>/dev/null; then
    note "FAIL — a sentence MenuCommandAvailability does not declare passed the vocabulary check"
    rc=1
else
    note "ok   — a foreign reason is refused"
fi

# ------------------------------------------------------------------------ the day the badge lands
opened="$WORK/opened.tsv"
cp "$clean" "$opened"
badge="$(badge_vocabulary | head -1)"
[ -n "$badge" ] || { echo "BLOCKED: the badge vocabulary is empty, so the case below would prove nothing" >&2; exit 2; }
row 3 AXMenuItem "Add Server…" AXTitle "Add Server…, $badge" >> "$opened"
if assert_the_badge_is_not_on_this_plane "$opened" 2>/dev/null; then
    note "FAIL — a badge folded into AXTitle did not trip the tripwire, so the day this lane opens nothing says so"
    rc=1
else
    note "ok   — a badge reaching AXTitle is caught"
fi

# ------------------------------------------------------------- the day the menu is laid out for us
laidout="$WORK/laidout.tsv"
cp "$clean" "$laidout"
row 3 AXMenuItem "Run Doctor" AXSize "319.0x22.0" >> "$laidout"
if assert_geometry_channel_closed "$laidout" 2>/dev/null; then
    note "FAIL — a non-zero AXSize did not trip the tripwire, so the geometry lane could open unnoticed"
    rc=1
else
    note "ok   — a laid-out menu item is caught"
fi

# ----------------------------------------------------------------- a probe that read almost nothing
thin="$WORK/thin.tsv"
row 3 AXMenuItem "Quit MCP Router" AXMenuItemCmdChar "Q" > "$thin"
row 3 AXMenuItem "Only Item" AXTitle "Only Item" >> "$thin"
if assert_the_probe_read_this_app "$thin" >/dev/null 2>&1; then
    note "FAIL — a dump of 1 item passed the probe control, so a run that read nothing could report absences"
    rc=1
else
    note "ok   — a dump that reached almost nothing is refused"
fi

# ------------------------------------------------------------------- a walk that annotated nothing
unwalked="$WORK/unwalked.tsv"
grep -v "$(printf 'AXHelp')" "$clean" > "$unwalked"
if assert_the_walker_ran "$unwalked" >/dev/null 2>&1; then
    note "FAIL — a dump carrying no reason at all passed the walker control, so ShellMenuReasons could stop running unnoticed"
    rc=1
else
    note "ok   — a menu nobody annotated is refused"
fi

[ $rc -eq 0 ] && echo "menu-reason-plane-selftest: all five assertions fire when they should and stay silent when they should"
exit $rc
