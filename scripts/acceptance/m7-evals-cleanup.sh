#!/bin/bash
#
# M7 acceptance: the Evals and Cleanup boards, measured and driven in the running app — in ONE
# launch covering both, and never brought to the front.
#
# **Scope is two panes.** The standing rule for this fleet and `planning/practices/UI_VERIFICATION.md`
# say the same thing: test the screens you changed, and only those. Servers, Skills, Activity,
# Settings and Discover are merged and evidenced in `planning/evidence/M3-`, `M4-`, `M2-`, `M8-` and
# `M5-acceptance.md`; their rows are cited, never re-driven. `mac-shell.sh` owns the shell's own
# clauses and is not repeated here.
#
# **The whole run is invisible, and that is a hard requirement rather than a courtesy.** Nothing here
# activates anything: the app is launched with `open -g`, every read is an accessibility query by
# pid, and MCP Router is asserted never to have become frontmost. If this gate steals the screen, it
# fails itself.
#
# **What this gate cannot do, stated rather than worked around.** Both panes carry a segmented
# filter, which SwiftUI renders as an `AXRadioGroup` of `AXRadioButton`s. `axkit press` matches
# `AXRole == "AXButton"` only, by deliberate design — see its comment on why a menu item must not be
# pressed that way — so there is no verb here that can operate a segment. This was raised by M5 as
# deferred child M5-d and predicted to hit M7's two boards, and it does. The filter's *behaviour* is
# proven exhaustively in the unit suite (`CheckPresentation.Filter`, `CleanupBoardModel.rows`); what
# is unproven by any rendered pass is that pressing the drawn segment reaches that logic. That is a
# tooling gap, it is recorded as one, and nothing here fakes a press to paper over it.
#
# Exit codes match the house rule: 2 means the harness could not run (no Accessibility grant, a
# locked screen, no built app), 1 means an assertion failed.

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
# Do not run a UI acceptance pass over a placeholder. Both destinations must be installed, or there
# is nothing here to verify and saying so is the honest outcome rather than driving a scaffold and
# reporting a pass. This reads the **build tree** and is labelled as such — a stale binary would
# satisfy it. The real assertion that the reader is looking at a board is the sentinel absence
# against the running process, below.
REGISTRY="$APP_DIR/Sources/MCPRouterUI/Shell/ScaffoldPane.swift"
# shellcheck source=scripts/acceptance/board-registry.sh
. "$ROOT/scripts/acceptance/board-registry.sh"
for destination in evals cleanup; do
    board_registry_installs "$REGISTRY" "$destination" \
      || blocked "the tree being tested does not install .$destination — there would be no board to verify"
done
pass "precondition: the build tree installs .evals and .cleanup (the running app is checked below)"

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
    # `mac-app.sh` owns the sequence, and every step waits on an observable. What stood here was a
    # flat `sleep 3` with `open`'s exit status discarded, and a `pgrep -f` matching ANY MCPRouter
    # on the machine — so on a fleet running several worktrees it attached to another runner's
    # build and reported about that one. The shared launcher binds the pid to THIS bundle, and it
    # separates "nothing launched" (blocked) from "the app started and died" (a real failure).
    mac_app_launch "$MAC_APP" "$AXKIT" "MCPROUTER_SCENARIO=$scenario"
    check_invisible "launching under '$scenario'"
}
quit() { [ -n "$PID" ] && { kill "$PID" 2>/dev/null || true; }; PID=""; }
trap 'quit; rm -rf "$WORK"' EXIT

dump() { "$AXKIT" dump "$PID" window > "$WORK/window.tsv"; }
# Every string the window speaks — title, value, description, help — one per line.
spoken() { cut -f4,5,6,7 "$WORK/window.tsv" | tr '\t' ' '; }
row_labels() { awk -F'\t' '$2 == "AXButton" { print $6 }' "$WORK/window.tsv"; }

open_pane() {
    "$AXKIT" select "$PID" "$1" >/dev/null || fail "could not select $1 through the accessibility API"
    sleep 2
    dump
}

# ================================================================ ONE launch, both panes
launch populated

echo
echo "=============================================================="
echo "A1 — Evals is installed, and is not the placeholder"
echo "=============================================================="
open_pane Evals

if spoken | grep -q "isn't built yet"; then
    fail "the Evals pane still renders the shell's placeholder — the board is not installed"
fi
pass "A1: no scaffold sentinel in the Evals pane"

TITLE="$("$AXKIT" title "$PID")"
[ "$TITLE" = "Evals" ] || fail "the window title is '$TITLE', not 'Evals'"
pass "A1: §3.7 — the window title names the view: 'Evals'"

EVAL_ROWS="$(row_labels | grep -c . || true)"
[ "$EVAL_ROWS" -gt 0 ] || fail "the Evals board rendered no rows from the populated fixture"
pass "A1: $EVAL_ROWS row-bearing elements rendered from the shipped fixture"
check_invisible "the Evals A1 assertions"

echo
echo "=============================================================="
echo "A17b / A21 — the vocabulary is observation, never a grade"
echo "=============================================================="
# The spec's strongest single correction: it is the *vocabulary*, not the subtitle, that makes a
# re-tabulation read as a grade. These are the words a reader would take as a judgement of quality.
for word in "healthy" "unhealthy" "score" "grade" "rating" "passed all" "failing" "good" "bad" "excellent" "poor"; do
    if spoken | grep -qiw "$word"; then
        fail "the Evals pane speaks a grading word: '$word'"
    fi
done
pass "A17b: no grading verb or adjective in anything the Evals pane speaks"

# And the four observation nouns are present, which proves the search above ran over a tree that
# does discuss verdicts — so it was never vacuous.
spoken | grep -qi "confirmed\|not met\|not observed\|not applicable" \
  || blocked "none of the four verdict nouns is on screen, so the grading-word search proves nothing"
pass "A17b: the observation vocabulary is on screen (search proven non-vacuous)"

echo
echo "=============================================================="
echo "A4 / A18 — no figure the router does not observe"
echo "=============================================================="
# The tokens a re-tabulation invents when it starts to feel like a test runner. Hunted as *figures*
# next to their unit, not as bare words: the pane's own honest disclosure discusses what it does not
# measure, and a bare word search would fail the board for saying the true thing.
for pattern in '[0-9]+ *ms\b' '[0-9]+ *s\b .*(elapsed|duration)' '[0-9,]+ *(bytes|KB|MB|GB)' \
               '[0-9]+ *runs?\b' '[0-9]+ *% *(pass|fail)' '[0-9]+/[0-9]+ *(passed|scored)' \
               'memory (saved|freed|reclaimed)' 'saved [0-9]'; do
    if spoken | grep -qEi "$pattern"; then
        fail "the Evals pane renders a figure the router does not observe, matching /$pattern/"
    fi
done
pass "A4: no run count, duration, byte figure or memory saving is rendered anywhere"

# The permanent disclosure that makes the absence deliberate rather than an oversight.
spoken | grep -qi "router" \
  || blocked "the pane says nothing about the router, so the disclosure assertion below is unfounded"
pass "A18: the pane's subtitle speaks about what the router observes"
check_invisible "the Evals honesty assertions"

echo
echo "=============================================================="
echo "A1 — Cleanup is installed, and is not the placeholder"
echo "=============================================================="
open_pane Cleanup

if spoken | grep -q "isn't built yet"; then
    fail "the Cleanup pane still renders the shell's placeholder — the board is not installed"
fi
pass "A1: no scaffold sentinel in the Cleanup pane"

TITLE="$("$AXKIT" title "$PID")"
[ "$TITLE" = "Cleanup" ] || fail "the window title is '$TITLE', not 'Cleanup'"
pass "A1: §3.7 — the window title names the view: 'Cleanup'"
check_invisible "the Cleanup A1 assertions"

echo
echo "=============================================================="
echo "The rejected metaphor, checked in the rendered tree"
echo "=============================================================="
# Rejected more than once as a product decision, so it is asserted against the screen and not only
# against source: an icon or a label could reintroduce it without any of the source guards firing.
for word in "trash" "bin" "recycle" "rubbish" "wastebasket" "garbage" "delete forever" "empty the"; do
    if spoken | grep -qiw "$word"; then
        fail "the Cleanup pane speaks the rejected trash metaphor: '$word'"
    fi
done
pass "no trash metaphor in anything the Cleanup pane speaks"

echo
echo "=============================================================="
echo "A8 / A9 — the observation window is stated, never invented"
echo "=============================================================="
# Cleanup's whole claim is "how much do we actually know". A proposal with no window behind it is
# the defect this pane exists to prevent, so either a real window is named or the pane says it is
# unknown — and never a substituted figure.
if spoken | grep -qE "window unknown"; then
    pass "A8: the window is absent and the pane says so rather than substituting a duration"
else
    spoken | grep -qE "[0-9]+d recorded" \
      || fail "the pane names neither a recorded window nor 'window unknown' — a proposal with no stated basis"
    pass "A8: the observation window is named from the router's own figure — $(spoken | grep -oE '[0-9]+d recorded' | head -1)"
fi

# The figure that must never appear: a literal threshold standing in for a measurement.
for pattern in '3600' 'over an hour' 'more than [0-9]+ hours? ago'; do
    if spoken | grep -qEi "$pattern"; then
        fail "the Cleanup pane renders an invented threshold, matching /$pattern/"
    fi
done
pass "A8: no invented threshold — the prototype's 'last > 3600' reaches no surface"
check_invisible "the Cleanup window assertions"

echo
echo "=============================================================="
echo "A16 — a skill offers no removal the router cannot perform"
echo "=============================================================="
# The router serves no skills write endpoint. A control that offered one would be a button with
# nothing behind it, which §5 forbids outright.
SKILL_REMOVE="$(awk -F'\t' '$2 == "AXButton" && $8 == "true" && ($4 ~ /Remove/ || $6 ~ /Remove/) && ($6 ~ /skill/ || $4 ~ /skill/) { print }' "$WORK/window.tsv" | grep -c . || true)"
[ "$SKILL_REMOVE" = "0" ] || fail "an enabled skill-removal control is on screen, and the router has no endpoint for it"
pass "A16: no enabled skill-removal control anywhere in the Cleanup pane"

echo
echo "=============================================================="
echo "The unhappy paths, in the same launch"
echo "=============================================================="
launch offline
open_pane Cleanup
spoken | grep -qi "router" \
  || fail "the offline Cleanup pane says nothing about the router not running"
# The considered zero this item fixed: with no reading, the badge-reconciliation sentence must not
# be on screen claiming the sidebar counts zero never-used servers.
if spoken | grep -qE "counts 0 |0 servers that have never"; then
    fail "the offline Cleanup pane states a count derived from a router that never answered"
fi
pass "offline: the pane reports the router, and states no count it did not observe"
check_invisible "the offline assertions"

launch partial
open_pane Cleanup
dump
pass "partial: the pane rendered without crashing under an unreadable client"
check_invisible "the partial assertions"

quit

echo
echo "=============================================================="
echo "$PASSED passed, $FAILED failed"
echo "final frontmost: $("$AXKIT" front) (started at: $FRONT_AT_START)"
echo "=============================================================="
