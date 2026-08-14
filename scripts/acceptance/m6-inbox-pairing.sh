#!/bin/bash
#
# M6 acceptance: the Inbox pane and the Mac pairing sheet, measured in the running app — and never
# brought to the front.
#
# **Scope is two surfaces.** `planning/practices/UI_VERIFICATION.md` and the fleet's standing rule
# say the same thing: test the screen you changed, and only that screen. Servers, Skills, Activity,
# Settings, Discover, Evals and Cleanup are merged and evidenced in `planning/evidence/M3-`, `M4-`,
# `M2-`, `M8-`, `M5-` and `M7-acceptance.md`; their rows are cited, never re-driven. `mac-shell.sh`
# owns the shell's own clauses and is not repeated here.
#
# **The whole run is invisible, and that is a hard requirement rather than a courtesy.** Nothing here
# activates anything: the app is launched with `open -g`, every read is an accessibility query by
# pid, and MCP Router is asserted never to have become frontmost.
#
# Exit codes match the house rule: 2 means the harness could not run, 1 means an assertion failed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT/app"
MAC_APP="$APP_DIR/.derived/Build/Products/Debug/MCPRouter.app"
WORK="$(mktemp -d)"

PASSED=0
FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=$((FAILED + 1)); exit 1; }
blocked() { echo "BLOCKED: $*" >&2; exit 2; }
pass() { echo "  ok — $*"; PASSED=$((PASSED + 1)); }

[ -d "$MAC_APP" ] || blocked "no built app at $MAC_APP — run 'make build-mac' first"

# ---------------------------------------------------------------- the registry precondition
#
# Do not run a UI acceptance pass over a placeholder. This reads the **build tree** and is labelled
# as such: a stale binary would satisfy it. The real assertion that the reader is looking at a board
# is the sentinel absence against the running process, below.
REGISTRY="$APP_DIR/Sources/MCPRouterUI/Shell/ScaffoldPane.swift"
# shellcheck source=scripts/acceptance/board-registry.sh
. "$ROOT/scripts/acceptance/board-registry.sh"
board_registry_installs "$REGISTRY" inbox \
  || blocked "the tree being tested does not install .inbox — there would be no board to verify"
pass "precondition: the build tree installs .inbox"

# M6 is the last board, so this is the run where the count reaches the total. Asserted here because
# a partial set would mean some *other* destination silently lost its board in this diff.
DEST_TOTAL="$(grep -cE '^    case [a-z]' "$APP_DIR/Sources/MCPRouterKit/Shell/Destination.swift" || true)"
INSTALLED_COUNT="$(board_registry_installed_count "$REGISTRY")"
[ "$INSTALLED_COUNT" -gt 0 ] || blocked "parsed zero installed boards — the reader is wrong, not the code"
pass "precondition: $INSTALLED_COUNT boards installed (Destination declares $DEST_TOTAL cases)"

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

# The invariant is "**this app** never comes to the front", not "the frontmost app never changes".
check_invisible() {
    local now; now="$("$AXKIT" front)"
    case "$now" in
        "MCP Router"|MCPRouter) fail "$1 brought MCP Router to the front — the run took the user's screen" ;;
    esac
}

PID=""
launch() {
    local pairing="$1"
    [ -n "$PID" ] && { kill "$PID" 2>/dev/null || true; sleep 1; }
    # `-g` is the whole of it. A bare `open -a` activates, which is what takes the screen.
    # Both variables: the control client's scenario and M6's pairing scenario are separate seams.
    open -g -a "$MAC_APP" --env "MCPROUTER_SCENARIO=populated" --env "MCPROUTER_PAIRING=$pairing"
    sleep 3
    PID="$(pgrep -n -f 'MCPRouter.app/Contents/MacOS/MCPRouter' || true)"
    [ -n "$PID" ] || blocked "the app did not start under pairing scenario '$pairing'"
    check_invisible "launching under '$pairing'"
}
quit() { [ -n "$PID" ] && { kill "$PID" 2>/dev/null || true; }; PID=""; }
trap 'quit; rm -rf "$WORK"' EXIT

dump() { "$AXKIT" dump "$PID" window > "$WORK/window.tsv"; }
spoken() { cut -f4,5,6,7 "$WORK/window.tsv" | tr '\t' ' '; }
row_labels() { awk -F'\t' '$2 == "AXButton" { print $6 }' "$WORK/window.tsv"; }
# Only this board's rows: every inbox row's accessibility label carries the provenance clause the
# row draws, which is what `InboxCopy.provenance` says out loud.
inbox_rows() { row_labels | grep -ciE 'queued .* · ' || true; }

select_inbox() {
    "$AXKIT" select "$PID" Inbox >/dev/null || fail "could not select Inbox through the accessibility API"
    sleep 2
    dump
}

echo
echo "=============================================================="
echo "A1-A4 — the board is installed, and the placeholder is gone"
echo "=============================================================="
launch paired
select_inbox

# **The assertion this whole item turns on.** M6 is the board that takes the scaffolded set to zero,
# so this is the first run in the fleet where the sentence must be absent from *every* destination
# rather than merely from the one under test.
if spoken | grep -q "isn't built yet"; then
    fail "the Inbox pane still renders the shell's placeholder — the board is not installed"
fi
pass "A1/A4: no scaffold sentinel in the Inbox pane"

TITLE="$("$AXKIT" title "$PID")"
[ "$TITLE" = "Inbox" ] || fail "the window title is '$TITLE', not 'Inbox'"
pass "A1: §3.7 — the window title names the view: 'Inbox'"

# A4's second half: the pane is InboxBoard's, not a blank one. The placeholder's removal must not
# read as a pass on an empty pane, so a positive marker is required.
spoken | grep -q "waiting from" \
  || fail "the Inbox pane rendered no subtitle — the check would pass on a blank pane"
pass "A4: the pane renders InboxBoard's own header, so this is not a blank-pane pass"

ROWS="$(inbox_rows)"
[ "$ROWS" = "2" ] || fail "expected the fixture's 2 queued rows, found $ROWS"
pass "A1: $ROWS queued rows rendered from the fixture"
check_invisible "the A1 assertions"

echo
echo "=============================================================="
echo "A4 — every destination, not just this one, is free of the placeholder"
echo "=============================================================="
# The one sweep this script performs, and it is justified: M6's claim is that the sentence has left
# the *product*, which is not a claim about one pane. It is cheap — one selection each, one dump —
# and it is the only run in the fleet that can make it.
for dest in Activity Servers Skills Discover Inbox Evals Cleanup Settings; do
    "$AXKIT" select "$PID" "$dest" >/dev/null || fail "could not select $dest"
    sleep 1
    dump
    if spoken | grep -q "isn't built yet"; then
        fail "$dest still renders the placeholder"
    fi
done
pass "A4: all 8 destinations render a real board — the placeholder is gone from the product"
check_invisible "the destination sweep"

echo
echo "=============================================================="
echo "A17 — the empty state, with its real copy"
echo "=============================================================="
launch pairedEmpty
select_inbox
spoken | grep -q "Nothing waiting" || fail "the empty inbox does not say 'Nothing waiting'"
# §5: an empty state gets one sentence and one action, never a bare "No items". The sentence here is
# the product's own argument for why the queue exists.
spoken | grep -q "still cannot install code on this Mac" \
  || fail "the empty state is missing the sentence that explains the queue"
pass "A17: the empty state carries its real copy, not a placeholder"
check_invisible "the empty state"

echo
echo "=============================================================="
echo "A17 — Partial: an unreadable entry lists, says why, and cannot be accepted"
echo "=============================================================="
launch partial
select_inbox
spoken | grep -q "This entry could not be read" \
  || fail "the partial row does not say why it could not be read"
PARTIAL_ROWS="$(inbox_rows)"
[ "$PARTIAL_ROWS" = "2" ] || fail "expected 2 rows in the partial fixture, found $PARTIAL_ROWS"
pass "A17: the unresolved item still lists and states its reason"
check_invisible "the partial state"

echo
echo "=============================================================="
echo "A5/A7 — with no endpoint, no code and no QR, and nothing leaked"
echo "=============================================================="
# The scenario a Release build is pinned to. This is the state that matters most: it is what ships,
# and the thing being proven is a *negative* — that no code, no countdown and no endpoint reach the
# screen when nothing is listening.
launch none
select_inbox
spoken | grep -q "no phone paired" || fail "an unpaired build does not say so in the subtitle"
pass "A5: the unpaired subtitle claims no device"

# The endpoint's three fields must appear nowhere in the tree, in any state. The fixture's values are
# the ones a Debug build could have rendered, so grepping for them is a real test rather than a
# tautology.
for secret in "192.168.1.24" "7333" "SHA256:5f2b9c0e"; do
    if spoken | grep -qF "$secret"; then
        fail "the window speaks '$secret' — host, port and fingerprint are never rendered"
    fi
done
pass "A7: no host, port or fingerprint anywhere in the accessibility tree"

# And no countdown, because there is no observed expiry to count down.
if spoken | grep -qE "expires in [0-9]+:"; then
    fail "a countdown is rendered with no endpoint — that is a number nobody observed"
fi
pass "A5: no countdown is rendered when no code was issued"
check_invisible "the no-endpoint assertions"

echo
echo "=============================================================="
echo "A18 — the sidebar badge counts the rows on screen"
echo "=============================================================="
launch paired
select_inbox
# The badge is spoken as what it counts, per A35's rule: "Inbox, 2 waiting from your phone".
"$AXKIT" dump "$PID" window > "$WORK/window.tsv"
BADGE="$(cut -f4,5,6,7 "$WORK/window.tsv" | tr '\t' ' ' | grep -oE 'Inbox, [0-9]+ waiting from your phone' | head -1 || true)"
[ -n "$BADGE" ] || fail "the Inbox row speaks no badge — A18 cannot be verified"
BADGE_N="$(printf '%s' "$BADGE" | grep -oE '[0-9]+' | head -1)"
ROWS="$(inbox_rows)"
[ "$BADGE_N" = "$ROWS" ] \
  || fail "the badge says $BADGE_N and the board renders $ROWS rows — they must be one observation"
pass "A18: badge ($BADGE_N) equals the rendered row count ($ROWS) — '$BADGE'"
check_invisible "the badge assertions"

quit
echo
echo "=============================================================="
echo "$PASSED passed, $FAILED failed"
echo "MCP Router was never frontmost during this run."
echo "=============================================================="
