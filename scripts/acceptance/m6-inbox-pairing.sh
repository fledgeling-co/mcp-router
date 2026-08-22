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
build_freshness_require Debug "$ROOT"


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

# M6 is the last board, so this is the run where the installed count reaches the total — and that is
# asserted rather than printed, because a partial set here would mean some *other* destination
# silently lost its board in this diff.
#
# Counted from `Destination`'s own body, not from every `case` line in the file: `DestinationGroup`
# and `BadgeSource` live in the same file and a whole-file grep counts their cases too. That read 13
# where the answer is 8, which is the shape of a precondition that reports a number nobody checked.
DEST_TOTAL="$(awk '
    /^public enum Destination:/ { inside = 1; next }
    inside && /^}/              { exit }
    inside && /^    case [a-z]/ { n++ }
    END { print n + 0 }
' "$APP_DIR/Sources/MCPRouterKit/Shell/Destination.swift")"
INSTALLED_COUNT="$(board_registry_installed_count "$REGISTRY")"
[ "$INSTALLED_COUNT" -gt 0 ] || blocked "parsed zero installed boards — the reader is wrong, not the code"
[ "$DEST_TOTAL" -gt 0 ] || blocked "parsed zero destinations — the reader is wrong, not the code"
[ "$INSTALLED_COUNT" = "$DEST_TOTAL" ] \
  || fail "$INSTALLED_COUNT of $DEST_TOTAL destinations have a board — M6 is the item that closes that gap"
pass "precondition: all $INSTALLED_COUNT destinations have a board, and none is scaffolded"

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
    # `mac-app.sh` owns the sequence, and every step waits on an observable. Both variables are
    # still passed: the control client's scenario and M6's pairing scenario are separate seams.
    # What stood here was a flat `sleep 3` with `open`'s exit status discarded, and a `pgrep -f`
    # matching ANY MCPRouter on the machine — including other worktrees' builds.
    mac_app_launch "$MAC_APP" "$AXKIT" \
        "MCPROUTER_SCENARIO=populated" "MCPROUTER_PAIRING=$pairing"
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

# `AXPress`, retried, and the retry is a measurement rather than a superstition.
#
# The shell polls the router once a second, so the window is rebuilt on that cadence — measured on
# 2026-08-15, `axkit dump` intermittently reports "no window" mid-rebuild, and an `AXUIElementRef`
# resolved by the tree walk can be replaced before the press reaches it, which returns an error
# rather than pressing anything. A human clicking hits whatever is on screen at the instant of the
# click and never sees this; a script that resolves an element and then acts on it does.
#
# So the press is retried against a freshly walked tree, and a press that never lands inside the
# budget is still a failure — the retry buys a live element, not a green result.
press_retry() {
    local needle="$1" attempts="${2:-10}" i result
    for i in $(seq 1 "$attempts"); do
        result="$("$AXKIT" press "$PID" "$needle" 2>&1 || true)"
        if [ "$result" = "OK" ]; then
            return 0
        fi
        sleep 1
    done
    return 1
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

# ---------------------------------------------------------------- A7, where it can actually fail
#
# **This sweep belongs here, under `paired`, and used to sit only under `none`.** The Phase D critic
# was right that it proved nothing there: `none` is the scenario with no endpoint, so grepping for
# the endpoint's values under it asserts that a value which does not exist was not rendered. Under
# `paired` the fixture endpoint is live and every one of these three is a real string the app holds
# and could leak. It stays under `none` as well, further down, because the two are different claims.
for secret in "192.168.1.24" "7333" "SHA256:5f2b9c0e"; do
    if spoken | grep -qF "$secret"; then
        fail "the window speaks '$secret' while paired — host, port and fingerprint are never rendered"
    fi
done
pass "A7: with a live endpoint, none of host, port or fingerprint reaches the tree"
check_invisible "the A1 assertions"

echo
echo "=============================================================="
echo "A4 — every destination, not just this one, is free of the placeholder"
echo "=============================================================="
# The one sweep this script performs, and it is justified: M6's claim is that the sentence has left
# the *product*, which is not a claim about one pane. It is cheap — one selection each, one dump —
# and it is the only run in the fleet that can make it.
# Settings left this list at M15: it is a `Settings` scene now rather than a destination, so
# `axkit select` would fail to find a row and the sweep would report a blocked selection as a
# product defect.
for dest in Activity Servers Skills Discover Inbox Checks Cleanup; do
    "$AXKIT" select "$PID" "$dest" >/dev/null || fail "could not select $dest"
    sleep 1
    dump
    if spoken | grep -q "isn't built yet"; then
        fail "$dest still renders the placeholder"
    fi
done
pass "A4: all 7 destinations render a real board — the placeholder is gone from the product"
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
echo "A17 — the four states a fixture reaches without a queue in it"
echo "=============================================================="
# `loading`, `failed` and `overflow` complete the matrix. A17 says every cell is reached **in the
# running app**, and the Phase D critic was right that four of eight had never been launched — the
# criterion was claimed on the four that had. `expiring` is driven below, where the sheet is opened.
launch loading
select_inbox
spoken | grep -q "Reading what is waiting" \
  || fail "the loading state does not say what it is doing"
# The skeleton, not a spinner (§5) — and no subtitle, because nothing has been observed to describe.
if spoken | grep -qE "Nothing waiting|waiting from|no phone paired"; then
    fail "the loading pane claims something about a queue that has not answered yet"
fi
pass "A17: loading renders its own copy and claims nothing about the queue"
check_invisible "the loading state"

launch failed
select_inbox
# The condition named is the one that happened. The `failed` fixture's error is `.unreadable` — this
# Mac's own queue storage — so a headline about the router would name a cause nobody observed, which
# is what this pane used to do for every read failure.
spoken | grep -q "The inbox could not be read" \
  || fail "the failed state does not name the condition that actually occurred"
spoken | grep -q "the queue file could not be read" \
  || fail "the failed state does not carry the failure's own detail"
if spoken | grep -q "The router is not running"; then
    fail "a queue-read failure is announced as the router being down — a cause nobody observed"
fi
pass "A17: the failed state names its own condition and blames nothing it did not observe"
check_invisible "the failed state"

launch overflow
select_inbox
OVERFLOW_ROWS="$(inbox_rows)"
[ "$OVERFLOW_ROWS" = "1" ] || fail "expected 1 row in the overflow fixture, found $OVERFLOW_ROWS"
spoken | grep -q "Local notes, scratch drafts" \
  || fail "the overflowing name is not rendered at all"
pass "A17: a name wider than its column still lists, on one row"
check_invisible "the overflow state"

echo
echo "=============================================================="
echo "A17 — the countdown, on a code that is actually near expiry"
echo "=============================================================="
# The `expiring` scenario exists because a five-minute window cannot be driven from a script. It
# mints a twelve-second code, so the countdown is observable rather than theoretical — and this is
# the assertion that proves `InboxService.pairingLifetime()` is wired, which is the seam that made
# `expiring` differ from `paired` at all.
launch expiring
select_inbox
press_retry "Pairing" || fail "could not open the pairing sheet through the accessibility API"
sleep 2
dump
spoken | grep -qE "expires in 0:[0-9][0-9]" \
  || fail "a near-expiry code renders no sub-minute countdown — the lifetime seam is not wired"
pass "A17: the countdown reads from the code that was issued, at its real remaining time"
check_invisible "the countdown"

echo
echo "=============================================================="
echo "A18 — the sidebar badge counts the rows on screen, after a change"
echo "=============================================================="
launch paired
select_inbox

badge_count() {
    "$AXKIT" dump "$PID" window > "$WORK/window.tsv"
    cut -f4,5,6,7 "$WORK/window.tsv" | tr '\t' ' ' \
      | grep -oE 'Inbox, [0-9]+ waiting from your phone' | head -1 | grep -oE '[0-9]+' | head -1 || true
}

# The badge is spoken as what it counts, per A35's rule: "Inbox, 2 waiting from your phone".
BADGE_N="$(badge_count)"
[ -n "$BADGE_N" ] || fail "the Inbox row speaks no badge — A18 cannot be verified"
ROWS="$(inbox_rows)"
[ "$BADGE_N" = "$ROWS" ] \
  || fail "the badge says $BADGE_N and the board renders $ROWS rows — they must be one observation"
pass "A18: badge ($BADGE_N) equals the rendered row count ($ROWS) at rest"

# **The half that can fail.** At rest the two numbers are trivially equal — a badge wired to the
# loaded snapshot rather than to the rendered rows passes the clause above and is wrong the moment
# anything is dispositioned. So one row is declined through the accessibility API and both are read
# again: this is the only form of A18 that distinguishes the two derivations.
# Through the review sheet, which is the only path a decline has — and pressing the row is itself
# the assertion that a combined accessibility element still carries its actions. Before this item's
# fix the row announced `.isButton`, answered AXPress with `.success`, and did nothing.
press_retry "Local notes" || fail "the row's default accessibility action does not open review"
sleep 2
dump
spoken | grep -q "has not run" || fail "pressing the row did not open the review sheet"
press_retry "Decline" || fail "could not press Decline through the accessibility API"
sleep 2
dump
AFTER_ROWS="$(inbox_rows)"
AFTER_BADGE="$(badge_count)"
[ "$AFTER_ROWS" = "1" ] \
  || fail "declining one of 2 rows left $AFTER_ROWS on screen"
[ "$AFTER_BADGE" = "$AFTER_ROWS" ] \
  || fail "after a decline the badge says '$AFTER_BADGE' and the board renders $AFTER_ROWS rows"
pass "A18: after a decline the badge follows the rendered rows ($AFTER_BADGE = $AFTER_ROWS)"

# §9's report half: the decline says so, in place, and offers the undo.
spoken | grep -q "Declined" || fail "declining reports nothing — §9 asks for reversible *and reported*"
spoken | grep -q "Undo" || fail "a decline is reversible, so it offers the undo"
pass "A14/§9: the decline is reported in place and offers its undo"
check_invisible "the badge assertions"

quit
echo
echo "=============================================================="
echo "$PASSED passed, $FAILED failed"
echo "MCP Router was never frontmost during this run."
echo "=============================================================="
