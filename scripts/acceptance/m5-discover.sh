#!/bin/bash
#
# M5 acceptance: the Discover board, measured and driven in the running app — and never brought to
# the front.
#
# **Scope is one pane.** The standing rule for this fleet and `planning/practices/UI_VERIFICATION.md`
# say the same thing: test the screen you changed, and only that screen. Servers, Skills, Activity
# and Settings are merged and evidenced in `planning/evidence/M3-`, `M4-`, `M2-` and
# `M8-acceptance.md`; their rows are cited, never re-driven. `mac-shell.sh` owns the shell's own
# clauses and is not repeated here.
#
# **The whole run is invisible, and that is a hard requirement rather than a courtesy.** Nothing here
# activates anything: the app is launched with `open -g`, every read is an accessibility query by
# pid, and MCP Router is asserted never to have become frontmost. If this gate steals the screen, it
# fails itself.
#
# Exit codes match the house rule: 2 means the harness could not run (no Accessibility grant, a
# locked screen, no built app), 1 means an assertion failed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT/app"
MAC_APP="$APP_DIR/.derived/Build/Products/Debug/MCPRouter.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASSED=0
FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=$((FAILED + 1)); exit 1; }
blocked() { echo "BLOCKED: $*" >&2; exit 2; }
pass() { echo "  ok — $*"; PASSED=$((PASSED + 1)); }

[ -d "$MAC_APP" ] || blocked "no built app at $MAC_APP — run 'make build-mac' first"

# ---------------------------------------------------------------- the registry precondition
#
# The rule that produced this script: do not run a UI acceptance pass over a placeholder. So the
# first thing checked is that Discover is actually installed. If it is not, there is nothing here to
# verify, and saying so is the honest outcome rather than driving a scaffold and reporting a pass.
#
# This reads the **build tree**, and is labelled as such: a stale binary would satisfy it. It is a
# cheap "is there any point running this at all" check. The real assertion that the reader is
# looking at a board rather than a placeholder is the sentinel absence against the running process,
# below. Membership rather than equality, because every board that lands adds a member.
REGISTRY="$APP_DIR/Sources/MCPRouterUI/Shell/ScaffoldPane.swift"
grep -E 'installed: Set<Destination> *=' "$REGISTRY" | head -1 | grep -qE '\[[^]]*\.discover\b' \
  || blocked "the tree being tested does not install .discover — there would be no board to verify"
pass "precondition: the build tree installs .discover (the running app is checked separately, below)"

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
# Nothing keys off an accessibility identifier: SwiftUI propagates the nearest ancestor's identifier
# down the subtree, so every descendant of the content zone reports `content`. Measured by M2 on
# 2026-08-14 and unchanged here. Role, title, value and description are what the tree actually
# carries.
dump() { "$AXKIT" dump "$PID" window > "$WORK/window.tsv"; }
# Every string the window speaks — title, value, description, help — one per line.
spoken() { cut -f4,5,6,7 "$WORK/window.tsv" | tr '\t' ' '; }
# A row reaches the tree as an AXButton whose `accessibilityLabel` lands in AXDescription.
row_labels() { awk -F'\t' '$2 == "AXButton" { print $6 }' "$WORK/window.tsv"; }
# Only the rows of *this* board: every row's label carries one of `ProvenanceMark.spokenLabel`'s
# four clauses, which is what the drawn mark says out loud. Case-insensitive deliberately — the
# clause reads "In the official registry" mid-sentence and "Official registry ·" in the subtitle,
# and a case-sensitive predicate silently counted 2 rows on a board rendering 3.
discover_rows() { row_labels | grep -ciE 'official registry|on smithery|source not recorded' || true; }
value_matching() { awk -F'\t' -v re="$1" '$5 ~ re { print $5 }' "$WORK/window.tsv"; }

echo
echo "=============================================================="
echo "A1 — the board is installed, and is not the placeholder"
echo "=============================================================="
launch populated
"$AXKIT" select "$PID" Discover >/dev/null || fail "could not select Discover through the accessibility API"
sleep 2
dump

if spoken | grep -q "isn't built yet"; then
    fail "the Discover pane still renders the shell's placeholder — the board is not installed"
fi
pass "A1: no scaffold sentinel in the Discover pane"

TITLE="$("$AXKIT" title "$PID")"
[ "$TITLE" = "Discover" ] || fail "the window title is '$TITLE', not 'Discover'"
pass "A1: §3.7 — the window title names the view: 'Discover'"

ROWS="$(discover_rows)"
[ "$ROWS" = "3" ] || fail "expected the fixture's 3 registry rows, found $ROWS"
pass "A1: $ROWS registry rows rendered from the shipped fixture"
check_invisible "the A1 assertions"

echo
echo "=============================================================="
echo "A2 — nothing is displayed that the router does not observe"
echo "=============================================================="
# The subtitle counts what is on screen. It must not claim the merged total, which is larger.
SUBTITLE="$(value_matching '^Official registry . Smithery . ')"
[ "$SUBTITLE" = "Official registry · Smithery · 3 servers" ] \
  || fail "the subtitle is '$SUBTITLE' — it should count the 3 rows on screen, not the merged 5"
pass "A2: subtitle counts what is on screen — '$SUBTITLE'"

# Every figure carries its unit. Both units are live on this fixture: a Smithery session count and
# a GitHub star count, which are different scales and must never read as one.
row_labels | grep -q "2,984 sessions" || fail "the session figure does not carry its unit"
row_labels | grep -q "9 stars"        || fail "the star figure does not carry its unit"
pass "A2: figures carry their units — '2,984 sessions' and '9 stars' both on screen"

# The prototype's fabricated fields, hunted in the rendered tree rather than only in source.
#
# **Hunted as figures, not as words**, and that distinction is the whole assertion. The footer's own
# honest sentence is "No trend or velocity figure is shown", so a bare word search for `velocity`
# matches the disclaimer and fails the board for saying the true thing. What A2 forbids is a
# *number* presented under one of these headings, so that is what is looked for: a digit adjacent to
# a fabricated unit, and the signed-delta glyphs a trend band would draw.
for pattern in '[0-9][0-9,]* installs' '[0-9][0-9,]* downloads' '[0-9]+% (up|down)' '[↑↓▲▼] ?[0-9]' '#[0-9]+ (of|in) ' 'Rank [0-9]' '[0-9]/10 eval' 'eval score'; do
    if spoken | grep -qE "$pattern"; then
        fail "the board renders a figure the router does not observe, matching /$pattern/"
    fi
done
pass "A2: no installs / downloads / trend delta / rank / eval figure is rendered anywhere"

# And the disclaimer that makes the absence deliberate rather than an oversight is itself present —
# proving the search above ran over a tree that does discuss these words, so it was never vacuous.
spoken | grep -q "No trend or velocity figure is shown" \
  || blocked "the trend disclaimer is absent, so the fabricated-figure search above proves nothing"
pass "A2: the absence is stated rather than silent (search proven non-vacuous)"

# A rank number would show as a leading ordinal in a row label. None of the three carries one.
row_labels | grep -qE '^#?[0-9]+[.)] ' && fail "a row is numbered — that is a rank the router does not publish"
pass "A2: no row carries a rank number"
check_invisible "the A2 assertions"

echo
echo "=============================================================="
echo "A3 — updatedAt's two meanings are both live on one screen"
echo "=============================================================="
# This is the item's central honesty decision, and this is the only place it is provable *as
# rendered*: the fixture carries Smithery-sourced rows and an official-registry row, so the two
# verbs must both appear, on different rows, in the same list.
row_labels | grep -q "added "   || fail "no row states a first-published date ('added …')"
row_labels | grep -q "updated " || fail "no row states an entry-updated date ('updated …')"
ADDED="$(row_labels | grep -c "added " || true)"
UPDATED="$(row_labels | grep -c "updated " || true)"
[ "$ADDED" = "2" ]   || fail "expected 2 Smithery-sourced rows to read 'added', found $ADDED"
[ "$UPDATED" = "1" ] || fail "expected 1 official-registry row to read 'updated', found $UPDATED"
pass "A3: both meanings render side by side — $ADDED 'added' (Smithery), $UPDATED 'updated' (official)"
check_invisible "the A3 assertions"

echo
echo "=============================================================="
echo "A5 — detail-then-install: the list installs nothing"
echo "=============================================================="
# The rule the whole board is shaped around. Asserted as the **absence of any install affordance in
# the list**, read off the running tree rather than off the source.
if awk -F'\t' '$2 == "AXButton" && ($4 ~ /^(Add|Install)$/ || $6 ~ /^(Add|Install)$/)' "$WORK/window.tsv" | grep -q .; then
    fail "the list carries an Add/Install control — a row must never be one click from running code"
fi
pass "A5: no Add or Install control exists anywhere in the board list"

# The row's only published action is the named one, and it is named for what it does.
if ! spoken | grep -q "Show details"; then
    # The named action is an AX action rather than an attribute, so it is not in the dump's columns.
    # Its effect is what is asserted instead, immediately below: pressing the row opens the sheet.
    echo "  note: 'Show details' is an AX action, not a dumped attribute — proved by its effect below"
fi

echo
echo "=============================================================="
echo "A6 — the capability statement is a reading of the install block"
echo "=============================================================="
# **The row must press like the button it says it is**, and this assertion is why that is now true.
#
# Measured here on 2026-08-15: the row carried `.accessibilityAddTraits(.isButton)` and a *named*
# action ("Show details") but no default one, so it published
# `["AXScrollToVisible", "Name:Show details…"]` and **no `AXPress`**. Assistive technology and
# automation that press a button got nothing while the trait promised otherwise. The fix adds the
# default action alongside the named one; this assertion is the guard, and it was red before it and
# green after.
#
# Judged by **effect, not by return code**. `AXUIElementPerformAction` returning `.success` proves
# only that the call was accepted — the same trap M8 recorded for menu items reached through
# `@FocusedValue`. So the sheet's own copy is what decides it.
sheet_is_open() { spoken | grep -q "Nothing runs on this Mac"; }

"$AXKIT" press "$PID" "GitHub" >/dev/null \
  || fail "the row publishes no working AXPress — it claims .isButton but cannot be pressed"
sleep 2
dump
sheet_is_open \
  || fail "AXPress on the row was accepted and did nothing — the sheet did not open"
pass "A5/A6: AXPress on the row opens the detail sheet (accepted *and* effective)"

# The fixture's first row is an HTTP install at https://server.smithery.ai/github/mcp. The sheet
# must name the **authority** and say that nothing runs locally — the host, not the whole URL and
# never the path, which is where a misleading string would hide.
spoken | grep -q "Connects to server.smithery.ai" \
  || fail "the sheet does not name the install URL's host"
pass "A6: the sheet states 'Connects to server.smithery.ai' — the authority, not the path"

spoken | grep -q "Nothing runs on this Mac" \
  || fail "the sheet does not state that an HTTP entry runs nothing locally"
pass "A6: the sheet states 'Nothing runs on this Mac' for an HTTP entry"

# Pressing a row opened a sheet and did NOT install: the row must still not read as installed.
dump
row_labels | grep -q "Already installed" \
  && fail "pressing a row marked it installed — the list wrote something"
pass "A5: pressing a row opened detail and installed nothing"
check_invisible "the sheet assertions"

echo
echo "=============================================================="
echo "keyboard — Esc dismisses the sheet; the row keys are scoped by focus"
echo "=============================================================="
# Keycode 53 is Escape. `axkit key` posts a CGEvent to one pid and needs no frontmost app, which is
# what makes it safe here.
#
# **Measured on 2026-08-15, and worth recording because it looks like a bug and is not.** Keys *do*
# reach a backgrounded app: Escape below dismisses the sheet. But posting Down (125) then Return
# (36) to the board does **not** open a row's detail — because with focus in the sidebar, `↓` moves
# the *sidebar* selection (observed: Discover → Evals) and never reaches the board's own
# `.onKeyPress(.downArrow)`. That is §8's focus order working exactly as specified (sidebar →
# search → ordering → table), not a defect, and Escape reaches the board only while the sheet is
# open because a sheet takes key focus.
#
# So the row-level keys (`↓`/`↑`/`Return` inside the table) need focus in the table, which a
# background app cannot be given without bringing the window to the front — and that outranks every
# other testing instruction here. Their evidence is DiscoverBoardTests: 'Return opens the detail
# sheet and is left unhandled when nothing is selected', 'the selection moves through the visible
# rows, not the whole response', and 'Escape dismisses the sheet first and clears the selection
# second, never both'.
"$AXKIT" key "$PID" 53 >/dev/null || fail "could not post Escape to the app"
sleep 1
dump
sheet_is_open && fail "Escape did not dismiss the detail sheet"
pass "keyboard: Escape dismissed the detail sheet (the sheet holds key focus, so the key lands)"
check_invisible "the keyboard assertions"

[ "$(discover_rows)" = "3" ] || fail "the board did not survive the sheet being dismissed"
pass "keyboard: the board is intact behind the dismissed sheet"

echo
echo "=============================================================="
echo "A7 — partiality is stated, never smoothed"
echo "=============================================================="
# The fixture is a genuine slice: three results against a merged total of five. The footer must say
# so, and must say it with the numbers from the response rather than a constant.
spoken | grep -q "Showing 3 of 5 that matched" \
  || fail "the footer does not state the slice — 3 rows shown against a merged 5"
pass "A7: the footer states the slice: 'Showing 3 of 5 that matched'"

spoken | grep -q "No trend or velocity figure is shown" \
  || fail "the footer does not state that no trend figure exists"
pass "A7: the footer states, always, that no trend or velocity figure is shown"

spoken | grep -q "Only Smithery publishes a session count" \
  || fail "the best-match ordering does not disclose its structural bias"
pass "A7: best match discloses that only Smithery publishes a session count"
check_invisible "the A7 assertions"

echo
echo "=============================================================="
echo "A4 — the three orderings, and what best match does not claim"
echo "=============================================================="
# §3.6 asks for a **segmented control that switches the view in place**, and that is what the tree
# reports: `.pickerStyle(.segmented)` renders an `AXRadioGroup` of `AXRadioButton`/`AXSegment`
# children whose label lands in AXDescription and whose selection is AXValue 1. Read off the running
# control rather than inferred from the source.
segment_desc() { awk -F'\t' '$2 == "AXRadioButton" { print $6 }' "$WORK/window.tsv"; }
segment_value() { awk -F'\t' -v want="$1" '$2 == "AXRadioButton" && $6 == want { print $5; exit }' "$WORK/window.tsv"; }

[ "$(segment_desc | wc -l | tr -d ' ')" = "3" ] \
  || fail "expected three ordering segments, found $(segment_desc | wc -l | tr -d ' ')"
for want in "Best match" "Most used on Smithery" "Recently added to Smithery"; do
    segment_desc | grep -qx "$want" || fail "the ordering control has no '$want' segment"
done
pass "A4: §3.6 — three segments, named for the universe each can speak about"

# Each scoped ordering names Smithery in its own label, so the scope is legible before it is chosen
# rather than only in a note afterwards.
[ "$(segment_value 'Best match')" = "1" ] || fail "Best match is not the selected ordering at rest"
[ "$(segment_value 'Most used on Smithery')" = "0" ] || fail "a scoped ordering is selected at rest"
pass "A4: best match is the ordering at rest — the one whose universe is everything"

# `exclusionNote` returns nil for best match, and the rendered board must therefore carry no
# "not shown here" sentence at rest. The absence check is proven able to fire by the ranking note
# above, which is in the same column and is definitely on screen.
spoken | grep -q "not shown here" \
  && fail "best match states an exclusion — it sets nothing aside and must claim nothing"
pass "A4: best match draws no exclusion note, because it excludes nothing"

# The other half of A4 — that choosing a scoped ordering filters to its universe and states the
# count it set aside — is NOT claimed here. `axkit press` matches AXButton only, and a segment is an
# AXRadioButton, so this run has no background-safe way to switch it; the alternative is bringing
# the window to the front, which outranks the extra coverage. Its evidence is
# RegistryPresentationTests: 'a scoped ordering filters to the universe it can speak about', 'the
# exclusion note names the count and appears only when something was excluded', and 'an ordering
# whose universe is empty says why, and best match never does'.
echo "  not claimed here — switching a segment needs an AXRadioButton press verb this toolkit"
echo "                     does not have. Covered by RegistryPresentationTests (three tests)."
check_invisible "the A4 assertions"

echo
echo "=============================================================="
echo "A8 — offline is not the same state as an unreachable index"
echo "=============================================================="
launch offline
"$AXKIT" select "$PID" Discover >/dev/null || fail "could not select Discover"
sleep 2
dump
spoken | grep -q "The router isn't running" \
  || fail "the offline state does not say the router is not running"
pass "A8: offline renders 'The router isn't running'"
spoken | grep -q "Start the router" \
  || fail "the offline state offers no way to fix it"
pass "A8: offline offers 'Start the router' — the one action that helps"
# It is the offline pane and not a board pretending to be empty.
[ "$(discover_rows)" = "0" ] || fail "rows are drawn under an offline router"
pass "A8: no rows are drawn under an offline router"
check_invisible "the offline assertions"

launch error
"$AXKIT" select "$PID" Discover >/dev/null || fail "could not select Discover"
sleep 2
dump
spoken | grep -q "The router isn't running" \
  && fail "the error state reuses the offline copy — the two are conflated"
pass "A8: the error state does NOT say 'The router isn't running' — offline and error are distinct"
check_invisible "the error assertions"

echo
echo "=============================================================="
echo "A8 — loading is a skeleton at the row height, never a spinner"
echo "=============================================================="
launch loading
"$AXKIT" select "$PID" Discover >/dev/null || fail "could not select Discover"
sleep 2
dump
awk -F'\t' '$2 == "AXProgressIndicator"' "$WORK/window.tsv" | grep -q . \
  && fail "a progress indicator is drawn over a blank pane"
pass "A8: no progress indicator — loading is not a spinner"
spoken | grep -q "Searching the registries" \
  || fail "the loading skeleton does not announce itself"
pass "A8: the skeleton announces 'Searching the registries'"
check_invisible "the loading assertions"

quit
FRONT_AT_END="$("$AXKIT" front)"
echo
echo "frontmost at end:   $FRONT_AT_END"
case "$FRONT_AT_END" in
    "MCP Router"|MCPRouter) fail "MCP Router is frontmost at the end of the run" ;;
esac
echo
echo "=============================================================="
echo "$PASSED passed, $FAILED failed — MCP Router never came to the front"
echo "=============================================================="
