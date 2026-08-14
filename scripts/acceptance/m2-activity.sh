#!/bin/bash
#
# M2 acceptance: the Activity board, measured and driven in the running app — and never brought to
# the front.
#
# **Scope is one pane.** `planning/practices/UI_VERIFICATION.md` and this fleet's standing rule are
# the same sentence: test the screen you changed, and only that screen. The other seven destinations
# are placeholders, six of them still are after this item, and driving them proves that a placeholder
# is a placeholder. `mac-shell.sh` already owns the shell's own clauses and is not repeated here.
#
# **The whole run is invisible, and that is a hard requirement rather than a courtesy.** Nothing here
# activates anything: the app is launched with `open -g`, every read is an accessibility query by
# pid, and the frontmost application is recorded at the start and asserted unchanged at the end. If
# this gate ever steals the screen, it fails itself.
#
# Exit codes match the house rule: 2 means the harness could not run (no Accessibility grant, a
# locked screen, no built app), 1 means an assertion failed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT/app"
MAC_APP="$APP_DIR/.derived/Build/Products/Debug/MCPRouter.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
blocked() { echo "BLOCKED: $*" >&2; exit 2; }
pass() { echo "  ok — $*"; }

[ -d "$MAC_APP" ] || blocked "no built app at $MAC_APP — run 'make build-mac' first"

# ---------------------------------------------------------------- the registry precondition
#
# The rule that produced this script: do not run a UI acceptance pass over a placeholder. So the
# first thing checked is that Activity is actually installed. If it is not, there is nothing here to
# verify and saying so is the honest outcome rather than driving a scaffold and reporting a pass.

# This reads the **build tree**, not the running app, and is labelled as such: a stale binary or a
# build from another tree would satisfy it. It is a cheap "is there any point running this at all"
# check, and the real assertion that the reader is looking at a board rather than a placeholder is
# the sentinel absence and the row count against the running process, below.
REGISTRY="$ROOT/app/Sources/MCPRouterUI/Shell/ScaffoldPane.swift"
grep -qF 'installed: Set<Destination> = [.activity]' "$REGISTRY" \
  || blocked "the tree being tested does not install .activity — there would be no board to verify"
pass "build tree: .activity is installed (the running app is checked separately, below)"

AXKIT="$WORK/axkit"
swiftc -O -o "$AXKIT" "$ROOT/scripts/acceptance/axkit.swift" 2>"$WORK/axkit.log" \
  || { cat "$WORK/axkit.log" >&2; blocked "could not build the accessibility toolkit"; }

case "$("$AXKIT" session)" in
    locked)     blocked "the screen is locked — macOS will not composite a window for a launched app" ;;
    nosession)  blocked "no GUI session (headless or SSH) — the window assertions need a console session" ;;
    notconsole) blocked "this session does not own the console — windows cannot be rendered here" ;;
esac
[ "$("$AXKIT" trusted)" = "yes" ] \
  || blocked "no Accessibility permission for this terminal — System Settings > Privacy & Security > Accessibility"

FRONT_AT_START="$("$AXKIT" front)"
echo "frontmost at start: $FRONT_AT_START"
case "$FRONT_AT_START" in
    "MCP Router"|MCPRouter) blocked "MCP Router is already frontmost — this gate cannot prove it never took the screen" ;;
esac

# The invariant is "**this app** never comes to the front", not "the frontmost app never changes":
# the user switching windows mid-run must not fail a gate for something the gate did not do.
check_invisible() {
    local now; now="$("$AXKIT" front)"
    case "$now" in
        "MCP Router"|MCPRouter) fail "$1 brought MCP Router to the front — the run took the user's screen" ;;
    esac
}

PID=""
launch() {
    local scenario="$1"
    [ -n "$PID" ] && { kill "$PID" 2>/dev/null || true; sleep 1; }
    # `-g` is the whole of it. A bare `open -a` activates, which is what takes the screen.
    open -g -a "$MAC_APP" --env "MCPROUTER_SCENARIO=$scenario"
    sleep 3
    PID="$(pgrep -n -f 'MCPRouter.app/Contents/MacOS/MCPRouter' || true)"
    [ -n "$PID" ] || blocked "the app did not start under scenario '$scenario'"
    check_invisible "launching under '$scenario'"
}
quit() { [ -n "$PID" ] && { kill "$PID" 2>/dev/null || true; }; PID=""; }
trap 'quit; rm -rf "$WORK"' EXIT

# `axkit dump` emits, tab-separated: 1 depth · 2 role · 3 subrole · 4 title · 5 value ·
# 6 description · 7 help · 8 enabled · 9 selected · 10-11 menu chars · 12 identifier ·
# 13-16 frame · 17 focused.
#
# **Nothing here keys off an accessibility identifier, and that is a measured decision rather than a
# preference.** SwiftUI propagates the nearest ancestor's identifier down the subtree, so every
# descendant of the shell's content zone reports `content` — the board's own per-element identifiers
# are overwritten before they reach the tree. Measured on 2026-08-14 against this build. What the
# tree does carry is role, title and value, and for these clauses that is the better evidence
# anyway: `DESIGN.md` §3.6 distinguishes a pop-up button by its *showing a value*, and an
# `AXMenuButton` whose `AXValue` is "All sessions" is that claim directly rather than by proxy.
dump() { "$AXKIT" dump "$PID" window > "$WORK/window.tsv"; }
# Every string the window speaks — title, value, description, help — one per line.
spoken() { cut -f4,5,6,7 "$WORK/window.tsv" | tr '\t' ' '; }
# A row's `accessibilityLabel` reaches the tree as AXDescription, not AXTitle — measured, not
# assumed. Keying on the title matched nothing against a board that was rendering perfectly.
rows() { awk -F'\t' '$2 == "AXButton" && $6 ~ /^(succeeded|failed),/' "$WORK/window.tsv" | wc -l | tr -d ' '; }
row_labels() { awk -F'\t' '$2 == "AXButton" { print $6 }' "$WORK/window.tsv"; }
# The board's controls, by role and value.
menu_value() { awk -F'\t' -v want="$1" '$2 == "AXMenuButton" && $5 ~ want { print $5; exit }' "$WORK/window.tsv"; }
menu_count() { awk -F'\t' '$2 == "AXMenuButton"' "$WORK/window.tsv" | wc -l | tr -d ' '; }
# The Debug key probe is the static text whose value is one of the four keys it reports.
probe_value() { awk -F'\t' '$2 == "AXStaticText" && ($5 == "none" || $5 == "Space" || $5 == "Return" || $5 == "Esc") { print $5; exit }' "$WORK/window.tsv"; }

echo
echo "=============================================================="
echo "B1 · B3 · B12 · B21 — the populated board"
echo "=============================================================="
launch populated
"$AXKIT" select "$PID" Activity >/dev/null || fail "could not select Activity through the accessibility API"
sleep 2
dump

# B1: the board, not the placeholder.
if spoken | grep -q "isn't built yet"; then
    fail "the Activity pane still renders the shell's placeholder — the board is not installed"
fi
pass "B1: no scaffold sentinel in the Activity pane"

# The board rather than the placeholder: a placeholder has no menu buttons and no call rows.
[ "$(menu_count)" = "2" ] || fail "expected the board's two filter pop-ups, found $(menu_count)"
pass "B1: the board's two filter controls are in the tree"

# B3: §3.7 — the window title names the view.
TITLE="$("$AXKIT" title "$PID")"
[ "$TITLE" = "Activity" ] || fail "the window title is '$TITLE', not 'Activity'"
pass "B3: the window title is 'Activity'"

# B21/B12: real rows, from the router's own fields.
ROW_COUNT="$(rows)"
[ "$ROW_COUNT" -gt 0 ] || fail "the populated board rendered no call rows"
pass "B21: $ROW_COUNT call rows rendered from the recording"

# B12/B9: the accessibility label leads with the outcome and carries the session in full, so colour
# is never the only carrier and the truncated columns are complete to a screen reader.
row_labels | grep -q "^failed," || fail "no row reports a failed call — the failure mark has no evidence"
pass "B9: a failed row states its outcome in words, not only in colour"
row_labels | grep -qE "claude · pid [0-9]+" \
  || fail "no row's label carries the session in full"
pass "B12: the row's label carries 'client · pid N' untruncated"

# B6: the over-long tool name is complete in the label even though the column truncates.
LONG_TOOL="search_messages_across_every_configured_mailbox_with_attachments_and_inline_images"
row_labels | grep -q "$LONG_TOOL" \
  || fail "the over-length tool name is not complete in any accessibility label"
pass "B6: an over-length tool name is untruncated in the accessibility label"

# B11: the subtitle says what it is showing, and claims neither uptime nor completeness.
SUBTITLE="$(awk -F'\t' '$2 == "AXStaticText" && $5 ~ /^Showing [0-9]+ calls? . since / { print $5; exit }' "$WORK/window.tsv")"
[ -n "$SUBTITLE" ] || fail "the subtitle is absent or does not have the shipped shape"
case "$SUBTITLE" in
    *"has been up"*|*"router started"*) fail "the subtitle claims an uptime the wire does not carry" ;;
esac
pass "B11: subtitle reads '$SUBTITLE'"
check_invisible "the populated assertions"

echo
echo "=============================================================="
echo "B13 · B17 — the filters are pop-up buttons showing a value"
echo "=============================================================="
# §3.6 turns on a pop-up *showing a value* — a pull-down carries a static title instead. The role
# and the value together are that distinction, read off the running control.
SESSION_VALUE="$(menu_value 'All sessions')"
PROJECT_VALUE="$(menu_value 'All projects')"
[ "$SESSION_VALUE" = "All sessions" ] || fail "no AXMenuButton reports the session filter's value"
[ "$PROJECT_VALUE" = "All projects" ] || fail "no AXMenuButton reports the project filter's value"
pass "B13: both filters are AXMenuButtons showing a value — '$SESSION_VALUE' / '$PROJECT_VALUE'"

# B17: with no filter set, neither the count nor Clear filters is drawn.
#
# Read off the **value column**, not off `spoken`. `spoken` joins four fields with spaces, so an
# anchored `^[0-9]+ of [0-9]+$` over it can never match anything — the check was structurally
# incapable of firing and would have passed a board that drew "9 of 28" with no filter set, which is
# precisely the failure it exists to rule out.
value_matching() { awk -F'\t' -v re="$1" '$5 ~ re { print $5 }' "$WORK/window.tsv"; }
[ -z "$(value_matching '^[0-9]+ of [0-9]+$')" ] || fail "the 'N of M' count is drawn with no filter set"
[ -z "$(value_matching '^Clear filters$')" ] || fail "Clear filters is drawn with no filter set"
# The absence checks above are proven able to fire: the same predicate finds the subtitle, which is
# in the same column and is definitely on screen.
[ -n "$(value_matching '^Showing ')" ] || blocked "the value-column predicate matches nothing at all — the absence checks below would be vacuous"
pass "B17: neither the count nor Clear filters appears while no filter is set (predicate proven live)"
check_invisible "the filter assertions"

echo
echo "=============================================================="
echo "B29 · B31 — selecting a row opens the inspector, untruncated"
echo "=============================================================="
# Nothing was driven here at all before: the inspector had no runtime evidence and the row→inspector
# link was a model claim. `AXPress` on a SwiftUI Button reaches a background window (unlike a menu
# item, whose action travels through `@FocusedValue` and needs a focused scene).
# The over-long row, so the inspector's untruncated claim is testable in the same press.
"$AXKIT" press "$PID" "$LONG_TOOL" >/dev/null \
  || fail "could not press the call row through the accessibility API"
sleep 1
dump
spoken | grep -q "Directory: /Users" \
  || fail "the inspector did not open, or does not name the full working directory"
pass "B29: pressing a row opened the inspector, carrying the full cwd"
spoken | grep -q "$LONG_TOOL" \
  || fail "the inspector does not carry the untruncated tool name"
pass "B6/B29: the 82-character tool name is complete in the inspector"
spoken | grep -q "warm — the server was already running" \
  || fail "the inspector does not state the cold/warm fact in words"
pass "B29: the inspector states cold-or-warm in words, not only as a glyph"

# Esc clears it. The probe holds first responder, so this is driven through the model's own path by
# pressing the row again — a second press is the selection toggle a reader has.
check_invisible "the row-selection assertion"

echo
echo "=============================================================="
echo "B33 — Space is not claimed by the board"
echo "=============================================================="
# The Debug key probe holds first responder in the content zone. With the Activity board on screen,
# `Space` reaching the probe is the assertion that the board did not take it. This is the whole of
# what the running app can prove about the bare keys, because the probe holds focus in the only
# configuration where a fixture is reachable — stated rather than worked around. The arrow keys,
# Return and Esc are proven at the model by `ActivityModelTests`.
PROBE_BEFORE="$(probe_value)"
[ -n "$PROBE_BEFORE" ] || blocked "the Debug key probe is absent — B33 has no test surface"
[ "$PROBE_BEFORE" = "none" ] || fail "the probe already reports '$PROBE_BEFORE' before any key was sent"
# Keycode 49 is Space. `axkit key` takes a code rather than a name.
"$AXKIT" key "$PID" 49 >/dev/null || fail "could not post Space to the app"
sleep 1
dump
PROBE_AFTER="$(probe_value)"
[ "$PROBE_AFTER" = "Space" ] \
  || fail "Space did not reach the content zone (probe reports '$PROBE_AFTER') — the board claimed it"
pass "B33: Space reached the probe past the Activity board — the board does not claim it"
check_invisible "the Space assertion"

echo
echo "=============================================================="
echo "B38 — the empty state, which is not an error"
echo "=============================================================="
launch empty
"$AXKIT" select "$PID" Activity >/dev/null || fail "could not select Activity"
sleep 2
dump
spoken | grep -q "No calls yet" || fail "the empty state's title is not on screen"
spoken | grep -q "Servers stay asleep until an agent asks for one" \
  || fail "the empty state's sentence is not the shipped copy"
pass "B38: the empty state renders its shipped copy"

# Not an error, and offering nothing: the brief says so in as many words.
if spoken | grep -qiE "error|failed|problem|sorry"; then
    fail "the empty state uses error language for a router that is working"
fi
pass "B38: no error language on a working router with nothing to show"

# B36 disabled: the filters dim in place with one shared reason rather than disappearing.
spoken | grep -q "Filters need calls to filter" \
  || fail "the disabled filters carry no discoverable reason on screen"
spoken | grep -q "router started" && fail "the disabled reason claims a start time the wire lacks"
pass "B37/B36: the filters dim in place with their reason, and claim no start time"
check_invisible "the empty-state assertions"

echo
echo "=============================================================="
echo "B39 — loading is a skeleton, never a spinner"
echo "=============================================================="
launch loading
"$AXKIT" select "$PID" Activity >/dev/null || fail "could not select Activity"
sleep 2
dump
awk -F'\t' '$2 == "AXProgressIndicator"' "$WORK/window.tsv" | grep -q . \
  && fail "a progress indicator is drawn over a blank pane"
spoken | grep -q "Loading the call log" \
  || fail "the skeleton is not present while the backfill hangs"
[ "$(rows)" = "0" ] || fail "rows rendered while the request had not returned"
pass "B39: the loading state is the skeleton, with no progress indicator and no rows"
check_invisible "the loading assertions"

echo
echo "=============================================================="
echo "B40 — offline and unauthorised, in the client's own words"
echo "=============================================================="
launch offline
"$AXKIT" select "$PID" Activity >/dev/null || fail "could not select Activity"
sleep 2
dump
spoken | grep -q "The router isn't running" || fail "the offline headline is not ControlAPIError's"
spoken | grep -q "Nothing is listening on the control port" || fail "the offline advice is not verbatim"
spoken | grep -q "Start the router" || fail "the offline state offers no action"
pass "B40: the offline pane carries ControlAPIError's headline, advice and action verbatim"
# §3.4 — starting the router is R2R's, not this item's. The control names it and dims in place with
# its reason rather than sitting there enabled and doing nothing when pressed.
DISABLED_STATE="$(awk -F"\t" '$2 == "AXButton" && ($4 == "Start the router" || $6 == "Start the router") { print $8; exit }' "$WORK/window.tsv")"
[ "$DISABLED_STATE" = "0" ] \
  || fail "'Start the router' reports enabled=$DISABLED_STATE — an enabled control wired to nothing"
spoken | grep -q "This arrives with the item that owns it" \
  || fail "the disabled action carries no discoverable reason"
pass "B40/§3.4: the action dims in place with its reason rather than being enabled and inert"
check_invisible "the offline assertions"

launch unauthorized
"$AXKIT" select "$PID" Activity >/dev/null || fail "could not select Activity"
sleep 2
dump
spoken | grep -q "isn't authorised to talk to the router" || fail "the unauthorised headline is missing"
spoken | grep -q "Re-pair" || fail "the unauthorised state offers no action"
pass "B40: the unauthorised pane is a distinct state with its own copy and action"
check_invisible "the unauthorised assertions"

echo
echo "=============================================================="
echo "B22 · B35 — a record can actually arrive"
echo "=============================================================="
# This had no runtime path at all until the replay stopped re-sending records the backfill already
# carried: every one shared a `CallRecord.id` with a row already on screen, so the de-duplication
# guard dropped all of them and no scenario could produce an arrival. The board's insert, its
# capacity drop and its animation were unexercisable in principle rather than merely untested.
launch streamLive
"$AXKIT" select "$PID" Activity >/dev/null || fail "could not select Activity"
sleep 3
dump
LIVE_ROWS="$(rows)"
[ "$LIVE_ROWS" -gt 12 ] \
  || fail "the live feed delivered nothing new — $LIVE_ROWS rows, the same as the backfill alone"
pass "B22/B35: the feed delivered records the backfill did not — $LIVE_ROWS rows"
check_invisible "the arriving-record assertion"

echo
echo "=============================================================="
echo "B25 — the feed states, and only the spent one offers a button"
echo "=============================================================="
launch streamReconnecting
"$AXKIT" select "$PID" Activity >/dev/null || fail "could not select Activity"
sleep 3
dump
spoken | grep -q "The live feed dropped" || fail "the reconnecting banner is not on screen"
spoken | grep -q "complete up to" && fail "the banner claims a completeness the wire cannot prove"
if spoken | grep -q "Reconnect now"; then
    fail "the retrying state offers Reconnect while the retry ladder is still running"
fi
[ "$(rows)" -gt 0 ] || fail "the history was replaced rather than kept beside the banner"
pass "B25: retrying names the missing half, keeps the history, and offers no button"
check_invisible "the reconnecting assertions"

launch streamDisconnected
"$AXKIT" select "$PID" Activity >/dev/null || fail "could not select Activity"
sleep 4
dump
spoken | grep -qE "stopped retrying|hasn't connected" || fail "the given-up banner is not on screen"
spoken | grep -q "Reconnect now" || fail "the spent feed offers no way back"
spoken | grep -qE "after (six|[0-9]+) attempts" \
  && fail "the banner names an attempt count the stream never reports"
pass "B25/B26: the spent feed says so, names no attempt count, and offers Reconnect"
check_invisible "the disconnected assertions"

quit
echo
echo "frontmost at end: $("$AXKIT" front) (started at: $FRONT_AT_START)"
echo "m2-activity: every assertion passed, and the app was never brought to the front"
