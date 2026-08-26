#!/bin/bash
#
# M34: what the accessibility plane says about a menu item's badge, and what it does not.
#
# **This lane exists to keep a closed door closed, and to notice the day it opens.** M20 shipped the
# badge that puts a dimmed command's reason in the shortcut column, and nothing could measure it:
# the accessibility tree looked empty, `AXPress` does nothing to a menu item in a background app,
# and photographing the menu is what `planning/practices/UI_VERIFICATION.md` rule 1 forbids. The
# only reader was a unit test over a menu the test itself built.
#
# The first of those four findings was recorded on a probe that enumerated the attribute *names* on
# each item — nineteen of them — found no badge among them, and concluded absence. That is one layer
# up from the trap M34's own brief names: an absence check with a correct-looking measurement above
# it. The badge is in `AXTitle`'s **value**. macOS says so in its own menu bar without being asked,
# where the Apple menu's `App Store…` item reads `App Store…, 29 updates`.
#
# So the plane does carry badges — for items **AppKit** built. It does not for items **SwiftUI**
# built, which is every item in this app's menu bar. That is the real limit, it is narrower than
# "the tree exposes no badge", and it is the one this file measures.
#
# Two fixtures, because one of them alone proves nothing:
#
#   · `fixture.swift` builds its menu with AppKit. Its badges DO reach `AXTitle` — at construction
#     and post-hoc, enabled and disabled. It is the control: it says the probe works.
#   · `swiftui-fixture.swift` builds its menu with SwiftUI's `CommandGroup`, and annotates it with a
#     poll shaped exactly like `ShellMenuReasons`. Its badges do NOT reach `AXTitle`, while an
#     in-process readback shows SwiftUI still holds them — so the badge is not lost, it is unexposed.
#
# **Three assertions here fail when the platform gets BETTER, and that is deliberate.** If a future
# macOS folds a SwiftUI item's badge into its title, or lets `.help()` reach a menu item, this lane
# fails and says a lane has opened. Read such a failure as an invitation to write the acceptance
# assertion M34 could not, not as a regression.
#
# Exit codes follow the house rule: 2 the harness could not run, 1 an assertion failed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/scripts/acceptance/menu-badge-fixture"
WORK="$(mktemp -d)"
PIDS=()
cleanup() {
    local pid
    for pid in ${PIDS[@]+"${PIDS[@]}"}; do kill "$pid" 2>/dev/null || true; done
    rm -rf "$WORK"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
blocked() { echo "BLOCKED: $*" >&2; exit 2; }
pass() { echo "  ok — $*"; }

# The frontmost application, recorded before anything is launched and asserted unchanged at the end.
# A fixture is bound by rule 1 exactly as hard as the app is: neither of these processes activates,
# and this is what says so rather than a comment claiming it.
FRONT_BEFORE="$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)" \
  || blocked "could not read the frontmost application — System Events is not answering"

for tool in fixture swiftui-fixture axattrs; do
    flags=(-O -o "$WORK/$tool")
    [ "$tool" = "swiftui-fixture" ] && flags=(-O -parse-as-library -o "$WORK/$tool")
    swiftc "${flags[@]}" "$SRC/$tool.swift" 2>"$WORK/$tool.log" \
      || { cat "$WORK/$tool.log" >&2; blocked "could not build $tool"; }
done

# ---------------------------------------------------------------- the probe's own precondition
#
# Without the Accessibility grant every read below returns nothing, which is indistinguishable from
# "the badge is not there" — which is the exact claim this lane makes. A missing grant reported as a
# measured absence is how the finding M34 was filed to correct got made in the first place.
"$WORK/axattrs" 0 2>&1 | grep -q "not trusted" \
  && blocked "no Accessibility grant, so every absence below would be unmeasurable rather than measured"

launch() {
    local binary="$1" out="$2"
    : > "$out"
    "$binary" > "$out" 2>"$WORK/launch.err" &
    PIDS+=("$!")
    perl -e 'alarm 20; while (1) { last if -s $ARGV[0]; select undef, undef, undef, 0.2 }' "$out" \
      || blocked "$(basename "$binary") never reported a pid"
    head -1 "$out"
}

# ---------------------------------------------------------------- 1 · AppKit — the control
echo "an AppKit-built menu"
APPKIT_PID="$(launch "$WORK/fixture" "$WORK/appkit.pid")"
# The two late-badged items are annotated half a second after launch, so the read waits past it.
perl -e 'select undef, undef, undef, 1.5'
"$WORK/axattrs" "$APPKIT_PID" > "$WORK/appkit.tsv" 2>&1 || blocked "the AppKit fixture's menu bar could not be read"

title_of() { awk -F'\t' -v want="$1" '$4 == "AXTitle" && index($5, want) == 1 { print $5; exit }' "$2"; }
attr_of()  { awk -F'\t' -v want="$1" -v a="$2" '$3 ~ ("^" want) && $4 == a { print $5; exit }' "$3"; }

# The controls first. A run that cannot read a help tag or a chord back has measured nothing about
# badges, and must not be allowed to report an absence.
[ "$(attr_of "Neither" AXHelp "$WORK/appkit.tsv")" = "help for Neither" ] \
  || fail "the probe cannot read AXHelp back, so nothing below is a measurement"
[ "$(attr_of "Chord Only" AXMenuItemCmdChar "$WORK/appkit.tsv")" = "1" ] \
  || fail "the probe cannot read a chord back, so nothing below is a measurement"
[ "$(title_of "Neither" "$WORK/appkit.tsv")" = "Neither" ] \
  || fail "an unbadged item's title is not its title — the probe is reading the wrong thing"
pass "help, chord and an unbadged title all read back — the probe works"

for pair in "Badge Only:BADGEONLY" "Both:BADGEBOTH" "Disabled Badge:BADGEDISABLED" \
            "Disabled Both:BADGEDISABOTH" "Late Badge:BADGELATE" "Late Both:BADGELATEBOTH"; do
    want="${pair%%:*}, ${pair##*:}"
    [ "$(title_of "${pair%%:*}" "$WORK/appkit.tsv")" = "$want" ] \
      || fail "AppKit no longer folds a badge into AXTitle for '${pair%%:*}' — expected '$want'"
done
pass "AppKit folds the badge into AXTitle: at construction and post-hoc, enabled and disabled"

# The whole point of the six items above being six: a badge and a chord on one item are both
# readable, from different attributes, so neither read costs the other.
[ "$(attr_of "Both" AXMenuItemCmdChar "$WORK/appkit.tsv")" = "2" ] \
  || fail "an item carrying both a badge and a chord lost its chord on the accessibility plane"
pass "an item carrying both exposes the badge in AXTitle and the chord in AXMenuItemCmdChar"

# ---------------------------------------------------------------- 2 · SwiftUI — the limit
echo "a SwiftUI-built menu"
SWIFTUI_PID="$(launch "$WORK/swiftui-fixture" "$WORK/swiftui.pid")"
perl -e 'select undef, undef, undef, 2'
"$WORK/axattrs" "$SWIFTUI_PID" > "$WORK/swiftui.tsv" 2>&1 || blocked "the SwiftUI fixture's menu bar could not be read"

# The control, again, and it is a different one: this fixture's items must be VISIBLE to the probe
# before their missing badge means anything. An item the walk never reached would also have no badge.
[ "$(title_of "SwiftUI Badged" "$WORK/swiftui.tsv")" = "SwiftUI Badged" ] \
  || fail "the SwiftUI fixture's items are not in the accessibility tree at all — nothing below is measured"
pass "the SwiftUI-built items are in the tree, so their annotations are measurable"

# And the second control, which is the one that makes this an AX limit rather than a lost badge:
# SwiftUI is still HOLDING the badge, read back in-process on the fixture's own poll.
awk -F'\t' '$1 == "readback" && $2 == "SwiftUI Badged" && $3 == "BADGESWIFTUI" { found = 1 } END { exit !found }' "$WORK/swiftui.pid" \
  || fail "SwiftUI dropped the badge in-process — this is no longer an accessibility limit but a lost badge"
pass "SwiftUI holds the badge in-process — what follows is the plane's limit, not a lost badge"

if grep -q "BADGESWIFTUI" "$WORK/swiftui.tsv"; then
    fail "a SwiftUI-built item's badge now REACHES the accessibility plane. This lane has OPENED:
the acceptance assertion M34 could not write is now writable, in scripts/acceptance/mac-shell.sh.
Note that mac-shell.sh matches menu item titles EXACTLY against the spec inventory, and a folded
badge makes that title 'Command, Badge' — so that gate needs the badge stripped before it matches."
fi
pass "a SwiftUI-built item's badge does not reach the accessibility plane — the limit still stands"

if [ -n "$(attr_of "SwiftUI Help Only" AXHelp "$WORK/swiftui.tsv")" ]; then
    fail "SwiftUI's .help() now reaches a menu item's AXHelp. ShellMenuReasons' help-tag half may be
redundant — and the app's correct help tags can no longer be used as evidence that the walker ran."
fi
pass "SwiftUI's .help() still does not reach a menu item — the app's AXHelp can only be the walker's"

# ---------------------------------------------------------------- 3 · rule 1
FRONT_AFTER="$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)"
[ "$FRONT_BEFORE" = "$FRONT_AFTER" ] \
  || fail "this lane took the user's screen: frontmost went from '$FRONT_BEFORE' to '$FRONT_AFTER'"
pass "the frontmost application is unchanged — '$FRONT_AFTER'"
