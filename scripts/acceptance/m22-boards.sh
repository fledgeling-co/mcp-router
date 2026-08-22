#!/bin/bash
#
# M22 acceptance: the Harnesses and Insights boards, measured in the running app — ONE launch
# covering both, and never brought to the front.
#
# **Scope is two panes**, per `planning/practices/UI_VERIFICATION.md` rule 2. Both are new in this
# item, so neither can be skipped against an earlier evidence row — there is no earlier row. The
# other seven boards are evidenced under `planning/evidence/M2-`, `M3-`, `M4-`, `M5-`, `M7-` and
# `M8-acceptance.md` and are cited there rather than re-driven here.
#
# **The whole run is invisible.** The app is launched with `open -g`, every read is an
# accessibility query by pid, and MCP Router is asserted never to have become frontmost. A gate
# that steals the screen fails itself (rule 1).
#
# **What this gate is for.** Not that the boards render — the unit suite and M23's measurement
# harness both cover that, and neither can see the shipped app. What it proves is the half those
# cannot: that the honesty rules survive into a real window. Every assertion below is a sentence
# from `DESIGN.md` §6 or the brief, asked of what the app actually speaks.
#
# Exit codes match the house rule: 2 the harness could not run, 1 an assertion failed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT/app"
MAC_APP="$APP_DIR/.derived/Build/Products/Debug/MCPRouter.app"
WORK="$(mktemp -d -t m22-boards)"

pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1" >&2; exit 1; }
blocked() { printf '  BLOCKED %s\n' "$1" >&2; exit 2; }

[ -d "$MAC_APP" ] || blocked "no built app at $MAC_APP — run: make build-mac"

# shellcheck source=scripts/acceptance/build-freshness.sh
source "$ROOT/scripts/acceptance/build-freshness.sh"
build_freshness_require Debug "$ROOT"

AXKIT="$WORK/axkit"
swiftc -O -o "$AXKIT" "$ROOT/scripts/acceptance/axkit.swift" 2>"$WORK/axkit.log" \
  || { cat "$WORK/axkit.log" >&2; blocked "could not build the accessibility toolkit"; }

# shellcheck source=scripts/acceptance/mac-app.sh
source "$ROOT/scripts/acceptance/mac-app.sh"

check_invisible() {
    local now; now="$("$AXKIT" front)"
    case "$now" in
        "MCP Router"|MCPRouter) fail "$1 brought MCP Router to the front — the run took the screen" ;;
    esac
}

PID=""
quit() { [ -n "${PID:-}" ] && { kill "$PID" 2>/dev/null || true; }; PID=""; }
trap 'quit; rm -rf "$WORK"' EXIT

dump() { "$AXKIT" dump "$PID" window > "$WORK/window.tsv"; }
spoken() { cut -f4,5,6,7 "$WORK/window.tsv" | tr '\t' ' '; }

open_pane() {
    "$AXKIT" select "$PID" "$1" >/dev/null || fail "could not select $1 over the accessibility API"
    sleep 2
    dump
}

mac_app_launch "$MAC_APP" "$AXKIT" "MCPROUTER_SCENARIO=populated"
check_invisible "launching under 'populated'"
echo "  pid: $PID"

# ================================================================ Harnesses
echo
echo "=============================================================="
echo "H — the Harnesses board"
echo "=============================================================="
open_pane Harnesses

# **Not a sentinel search.** The sibling scripts grep the window for "isn't built yet", which was
# the scaffold's own sentence when a scaffold existed. It does not any more — `ScaffoldCopy` and
# `ScaffoldedDestination` are deleted, and `mac-shell.sh` greps the Release bundle for those TYPE
# NAMES rather than for the sentence, precisely because the sentence is also
# `CommandAvailability.surfaceAbsent`'s live help tag.
#
# Written as a sentinel search first, this failed on its first run — matching the help tag on this
# board's own three disabled Reconcile controls, which name an absent surface in exactly those
# words because §6 asks for one name per state. A negative substring check cannot tell "the
# placeholder survived" from "a control correctly says a surface is missing", so it is replaced by
# a positive assertion: the board's own content is on screen.
spoken | grep -qF "Which AI tools on this Mac actually route through here" \
  || fail "the Harnesses board did not draw its own header — the pane is not this board"
pass "H: the board drew its own content"

TITLE="$("$AXKIT" title "$PID")"
[ "$TITLE" = "Harnesses" ] || fail "the window title is '$TITLE', not 'Harnesses' (§3.7)"
pass "H: §3.7 — the window title names the view"

# The four readings, each in its own words. A boolean would have hidden two of them, which is the
# brief's whole argument for four.
for reading in "Routed over HTTP" "Routed through a stdio shim" "Routed, plus" "Not routed"; do
    spoken | grep -qF "$reading" || fail "the board does not speak the reading '$reading'"
done
pass "H: all four readings are on screen, each in its own words"

# The shim reading names the bridge AND the cost. A tick here is the defect the brief describes.
spoken | grep -qF "mcp-remote" || fail "the shim row does not name its bridge"
spoken | grep -qF "one extra process per session" \
  || fail "the shim row does not name the cost — a bridge shown without it reads as a clean tick"
pass "H: the shim row names mcp-remote and calls it one extra process per session"

# The counts are read from files on a clock, so a reading carries when it was taken. The brief:
# a stale reading here is worse than no reading.
spoken | grep -qiE "read (just now|[0-9]+[smhd] ago)" \
  || fail "the board does not say when the configs were read"
pass "H: the reading is stamped with when it was taken"

spoken | grep -qF "Global configuration only" \
  || fail "the board does not say that project-scoped entries were not read"
pass "H: the scope the reading does not cover is stated (R7-C4)"

# The finding is a count rather than a judgement, and it names the harness it is about.
spoken | grep -qE "runs [0-9]+ servers? of its own, [0-9]+ of which this router already fronts" \
  || fail "the finding is not phrased as a count of what was measured"
pass "H: the finding is a count, not a judgement"

# §3.4: a disabled control dims in place with a discoverable reason and never disappears. Both
# halves are asserted, because drawing it enabled and drawing it not at all are the two failures
# this replaced — it was an enabled button setting a sheet state nothing presented.
DISABLED_RECONCILE="$(awk -F'\t' '$2 == "AXButton" && $5 ~ /^Reconcile/ && $7 == "0" { n++ } END { print n+0 }' "$WORK/window.tsv")"
[ "$DISABLED_RECONCILE" -ge 1 ] \
  || fail "no Reconcile control is drawn disabled — it is either absent or live"
spoken | grep -qF "isn't built yet, so nothing here can be reconciled" \
  || fail "the disabled Reconcile control carries no discoverable reason (§3.4)"
pass "H: $DISABLED_RECONCILE Reconcile control(s) drawn, disabled, each carrying its reason"

check_invisible "the Harnesses assertions"

# ================================================================ Insights
echo
echo "=============================================================="
echo "I — the Insights board"
echo "=============================================================="
open_pane Insights

spoken | grep -qF "Every number here is counted from calls this router served" \
  || fail "the Insights board did not draw its own header — the pane is not this board"
TITLE="$("$AXKIT" title "$PID")"
[ "$TITLE" = "Insights" ] || fail "the window title is '$TITLE', not 'Insights' (§3.7)"
pass "I: §3.7 — the window title names the view"

# THE BRIEF'S OWN ACCEPTANCE: a labelled node per harness INCLUDING the ones at zero. The zero row
# is the finding — a harness at zero is one still using its own servers — so its label and its zero
# must both be on screen. Asserted through the accessibility plane, where a bar that drew nothing
# would leave the label behind.
ZERO_LABEL="$(awk -F'\t' '$0 ~ /Gemini CLI, 0/ { print }' "$WORK/window.tsv" | head -1)"
[ -n "$ZERO_LABEL" ] || fail "the harness at zero does not announce its label and its zero together"
pass "I: the zero row announces as 'Gemini CLI, 0' — label and zero both present"

# And a row the router cannot attribute announces NEITHER. A zero there would be a fabricated
# finding on the one chart whose zero row is the finding.
spoken | grep -qF "no figure" \
  || fail "an unattributable row does not say it has no figure"
spoken | grep -qF "calls arrive as node" \
  || fail "an unattributable row does not say why it has no figure"
pass "I: an unattributable row draws no count and says why"

# The memory figure carries its provenance. §6: the line is the difference between a number and a
# claim.
spoken | grep -qF "measured, not modelled" \
  || fail "the resident-memory figure does not carry its provenance line"
pass "I: the memory figure is labelled measured, not modelled"

# The failure rate shows its numerator and its denominator.
spoken | grep -qE "[0-9]+ of [0-9]+" \
  || fail "the failure rate does not show its numerator and denominator"
pass "I: the failure rate carries both its terms"

# The duty-cycle caption states the MECHANISM. The brief's own caption quotes a percentage for a
# world this router never ran, which DESIGN.md §6 forbids — two paragraphs before the brief says no
# number here is modelled.
spoken | grep -qF "since the router started" \
  || fail "the duty-cycle caption does not state the window it was measured over"
spoken | grep -qF "stays alive until the session ends" \
  || fail "the duty-cycle caption does not state the mechanism"
pass "I: the duty-cycle caption states the mechanism and its window"

# NO FABRICATED SAVING ANYWHERE. The rule DESIGN.md §6 states in its own words, and the one
# PRD.md §8.2's sketch breaks.
for forbidden in "Savings" "saved" "vs unrouted" "unrouted" "would have been" "99.8" "99.7"; do
    spoken | grep -qiF "$forbidden" \
      && fail "the board speaks '$forbidden' — a figure about a world the router never ran"
done
pass "I: no saving, no unrouted comparison, no figure the router did not observe"

# And the search above is proven non-vacuous: the board IS discussing memory and duty cycle, so a
# clean result is a measurement rather than a search over a tree with no numbers in it.
spoken | grep -qF "Resident, all children" \
  || blocked "the memory figure is not on screen, so the fabricated-saving search proves nothing"
pass "I: the forbidden-figure search ran over a tree that does discuss memory (non-vacuous)"

check_invisible "the Insights assertions"

echo
echo "m22-boards: every assertion passed, and MCP Router never came to the front."
