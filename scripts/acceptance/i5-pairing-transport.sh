#!/bin/bash
#
# I5: does the phone-to-Mac pairing round trip happen?
#
# ## The question, and why it is answered this way
#
# Wave 6's exit gate was *"Phone → Mac inbox round-trip works end to end"*. M6 built the Mac side
# and reported the gate as NOT met rather than claiming it. `spec-M6.md` argues the point from the
# source: no `NWListener` in either app target, `FixturePairingService` the only conformance.
#
# That argument is correct and it is not a measurement. This script is the measurement. It attempts
# the round trip with the two halves as real, separate processes — the Mac app on macOS, the phone
# on an iPhone simulator — against an endpoint that is genuinely listening, and reports what
# arrived.
#
# ## Calibration before verdict, which is the whole method
#
# The finding here is an ABSENCE, and an absence is the easiest thing in the world to manufacture by
# accident. A tap nobody could reach, a port typed wrong, a suite that never ran, a simulator with
# no route to the host — every one of them produces exactly the evidence that "no transport exists"
# produces. So nothing is concluded until the instrument has been shown to work, from the same
# place, in the same run:
#
#   1. the tap receives a token from a separate host process        (the tap works at all)
#   2. the socket enumerator reports a listening socket for the tap (it can read a non-zero value)
#   3. the tap receives a token from inside the phone process       (the phone can reach it)
#
# Only after 3 does "and nothing else arrived" say something about the product. Step 3 is the one
# that matters most: it is a connection originating in the very process whose pairing call is under
# test, so its arrival rules out the whole family of environment explanations at once.
#
# The Mac side gets the same treatment. Counting the app's listening sockets and finding zero is
# worthless unless the counter can be shown to find one, so it is run against the tap's own pid
# first and required to report a non-zero answer there.
#
# ## The Mac is configured as favourably as it can be
#
# `MCPROUTER_PAIRING=paired` is the richest fixture: it advertises an endpoint, mints codes and
# populates the inbox. If anything in this product were ever going to bind a port, this is the
# configuration in which it would. A Release build reaches `noTransport` by construction, so
# measuring that one would prove less, not more.
#
# ## Exit codes
#
#   0  the experiment ran and its assertions held
#   1  an assertion about the product failed
#   2  the harness could not establish its own preconditions — NOT a pass, and never a finding

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT/app"
PROJECT="$APP_DIR/MCPRouter.xcodeproj"
DERIVED="$APP_DIR/.derived"
MAC_APP="$DERIVED/Build/Products/Debug/MCPRouter.app"
SUITE="MCPRouterIOSTests/PairingTransportProbeTests"
WORK="$(mktemp -d)"
TAP_LOG="$WORK/tap.log"
# Built here rather than expected in the products directory, matching `m6-inbox-pairing.sh`: it is
# this harness's own instrument, not part of the app.
AXKIT="$WORK/axkit"
# Where the phone probe reads the tap port from. Inside the gitignored derived-data directory.
PORT_FILE="$DERIVED/i5-tap-port"

PASSED=0
fail() { echo "FAIL: $*" >&2; exit 1; }
blocked() { echo "BLOCKED: $*" >&2; exit 2; }
pass() { echo "  ok — $*"; PASSED=$((PASSED + 1)); }

# The load at which this ran, recorded beside the result. A measurement taken under a loaded machine
# is a different measurement, and this fleet has had a row overturned for not saying so.
echo "load: $(uptime | sed 's/.*load averages*: //')"

[ -d "$MAC_APP" ] || blocked "no built app at $MAC_APP — run 'make build-mac' first"

# shellcheck source=scripts/acceptance/build-freshness.sh
source "$ROOT/scripts/acceptance/build-freshness.sh"
# shellcheck source=scripts/acceptance/mac-app.sh
source "$ROOT/scripts/acceptance/mac-app.sh"
# Every claim below is about the running binary, so a binary older than the tree makes all of them
# statements about a build nobody is looking at.
build_freshness_require Debug "$ROOT"

PID=""
TAP_PID=""
cleanup() {
    [ -n "$PID" ] && kill "$PID" 2>/dev/null || true
    [ -n "$TAP_PID" ] && kill "$TAP_PID" 2>/dev/null || true
    rm -f "$PORT_FILE"
    rm -rf "$WORK"
}
trap cleanup EXIT

# How many connections the tap has recorded.
tap_connections() { grep -c '^CONNECT ' "$TAP_LOG" 2>/dev/null || echo 0; }
# Whether a token arrived on any connection.
tap_saw() { grep -q "^DATA .*$1" "$TAP_LOG" 2>/dev/null; }
# Listening TCP sockets held by one process, or the string "unreadable".
#
# **The failure and the zero are kept apart, and the first version of this did not do that.** It was
#
#     lsof … 2>/dev/null | grep -c LISTEN || true
#
# under which an lsof that timed out, lacked permission or lost the race with a process still
# settling produced an empty pipe, `grep -c` printed 0, and `|| true` swallowed the status. "lsof
# failed" and "this process listens on nothing" were then the same answer — and the second one is
# this experiment's headline finding. The out-of-family review found this and it is the P5 lesson
# exactly: the calibration proved the counter could read 1 for the TAP's pid, which says nothing
# about whether it succeeded against the APP's.
#
# So the exit status is consulted, and an unreadable process is BLOCKED rather than counted as zero.
listening_sockets() {
    local out status
    out="$(lsof -nP -p "$1" -a -iTCP -sTCP:LISTEN 2>/dev/null)"
    status=$?
    # lsof exits 1 both for "no matching files" and for real errors, so emptiness alone cannot
    # separate them. A process that exists and can be inspected always answers 0 or 1 here; a
    # higher status means lsof itself could not run.
    if [ "$status" -gt 1 ]; then
        echo "unreadable"
        return
    fi
    # The process must still be alive, or "no sockets" is a statement about a corpse.
    if ! kill -0 "$1" 2>/dev/null; then
        echo "unreadable"
        return
    fi
    printf '%s' "$out" | grep -c LISTEN || true
}

echo
echo "=== 1. the instrument ==========================================================="

python3 "$ROOT/scripts/acceptance/i5-wire-tap.py" "$TAP_LOG" > "$WORK/port" 2>"$WORK/tap.err" &
TAP_PID=$!

# Wait on the observable — the port line — rather than sleeping. A fixed sleep here is a race, and a
# race decides this experiment's verdict.
TAP_PORT=""
for _ in $(seq 1 80); do
    TAP_PORT="$(head -1 "$WORK/port" 2>/dev/null || true)"
    [ -n "$TAP_PORT" ] && break
    sleep 0.25
done
[ -n "$TAP_PORT" ] || blocked "the wire tap never reported a port, so there was nothing to measure
      against. $(cat "$WORK/tap.err" 2>/dev/null)"
echo "wire tap: 127.0.0.1:$TAP_PORT (pid $TAP_PID)"

# Handed to the phone probe through a file rather than an environment variable, because xcodebuild
# does NOT forward its own environment into the test process running on the simulator. The first run
# of this experiment set `I5_TAP_PORT` on the command line, both probes skipped for want of it, and
# this script reported BLOCKED on its assertion count. `app/.derived` is gitignored.
mkdir -p "$DERIVED"
printf '%s' "$TAP_PORT" > "$PORT_FILE"

# --- calibration 1: the tap records a real connection from a separate process ---------------------
printf 'HOST-CALIBRATION\n' | nc -w 2 127.0.0.1 "$TAP_PORT" >/dev/null 2>&1 || true
for _ in $(seq 1 40); do
    tap_saw "HOST-CALIBRATION" && break
    sleep 0.25
done
tap_saw "HOST-CALIBRATION" \
    || blocked "the wire tap did not record a connection that was definitely made to it.
      The instrument is not working, so nothing below would be evidence about the product."
pass "calibration: the tap records a connection made from a separate process"

# --- calibration 2: the socket enumerator can read a non-zero value -------------------------------
tap_listeners="$(listening_sockets "$TAP_PID")"
[ "${tap_listeners:-0}" -ge 1 ] \
    || blocked "the socket enumerator reported $tap_listeners listening sockets for a process that
      is definitely listening. It cannot read a non-zero value, so a zero it reports for the app
      below would mean nothing."
pass "calibration: the socket enumerator reads $tap_listeners listening socket(s) for the tap"

echo
echo "=== 2. the Mac, as a real process ==============================================="

swiftc -O -o "$AXKIT" "$ROOT/scripts/acceptance/axkit.swift" 2>"$WORK/axkit.log" \
    || { cat "$WORK/axkit.log" >&2; blocked "could not build the accessibility toolkit, which
      mac_app_launch requires to establish that the app drew a window."; }

# The richest pairing fixture: an endpoint advertised, codes minted, inbox populated. If this
# product binds a port anywhere, it binds one here.
mac_app_launch "$MAC_APP" "$AXKIT" "MCPROUTER_SCENARIO=populated" "MCPROUTER_PAIRING=paired"
echo "MCPRouter: pid $PID under MCPROUTER_PAIRING=paired"

# --- the sheet is actually OPENED, and that was a real hole -------------------------------------
#
# The first version measured the app three seconds after launch, with the pairing sheet closed, and
# then reported "0 listening sockets while showing a pairing code". The out-of-family review caught
# it: nothing was showing a pairing code. `PairingSessionModel.open()` is the only place this design
# would ever construct an endpoint, and it is reached from the Inbox header, not from launch — so a
# listener bound lazily on sheet-open is precisely what that measurement would have missed.
#
# Opening the sheet also **calibrates the scenario**. The environment reaching this process was
# never checked either, and this fleet has already lost one run to an environment variable that did
# not arrive. A live code on screen can only come from `FixtureInboxService`'s advertised endpoint,
# so the countdown below is the proof that `MCPROUTER_PAIRING=paired` took effect. One observable,
# two preconditions.
dump() { "$AXKIT" dump "$PID" window > "$WORK/window.tsv"; }
spoken() { cut -f4,5,6,7 "$WORK/window.tsv" | tr '\t' ' '; }

# Retried against a freshly walked tree: an `AXUIElementRef` can be replaced between the walk and
# the press, which returns an error rather than pressing anything. `m6-inbox-pairing.sh` records the
# same behaviour and the same remedy.
press_retry() {
    local needle="$1" attempt result
    for ((attempt = 1; attempt <= 6; attempt++)); do
        result="$("$AXKIT" press "$PID" "$needle" 2>&1 || true)"
        case "$result" in *"not found"* | *error* | *Error*) sleep 1; dump; continue ;; esac
        return 0
    done
    return 1
}

"$AXKIT" select "$PID" Inbox >/dev/null \
    || blocked "could not select the Inbox board through the accessibility API, so the pairing
      sheet was never reached and the socket count below would be a measurement of an idle window."
sleep 2
dump
press_retry "Pairing" \
    || blocked "could not open the pairing sheet through the accessibility API. Without it this
      measures startup rather than pairing, which is the hole this step exists to close."
sleep 2
dump

# A live code with a running countdown. Under `paired` the window is five minutes, so the countdown
# reads m:ss. This is the calibration described above: no endpoint, no code, no countdown.
spoken | grep -qE "expires in [0-9]:[0-9][0-9]" \
    || blocked "the pairing sheet is open but shows no live code, so MCPROUTER_PAIRING=paired did
      not take effect in this process. Nothing below would be about a Mac that is offering to pair."
pass "precondition: the pairing sheet is open, showing a live code with a running countdown"

# Now that a code is genuinely on screen, give anything that intends to bind a chance to do so.
# A settle rather than a poll: there is no observable to wait on when the expected answer is
# "nothing happened", so the wait is fixed, generous, and stated.
sleep 3

app_listeners="$(listening_sockets "$PID")"
echo "MCPRouter listening TCP sockets: $app_listeners"
lsof -nP -p "$PID" -a -iTCP 2>/dev/null | sed 's/^/    /' || true

if [ "$app_listeners" = "unreadable" ]; then
    blocked "lsof could not be run against the app process, so its listening sockets are unknown.
      That is not zero, and reporting it as zero is how this check would have lied."
fi
if [ "${app_listeners:-0}" -gt 0 ]; then
    fail "the Mac app IS listening on $app_listeners socket(s) while a pairing code is on screen.
      That contradicts spec-M6's finding and means I5 must be re-read as a working transport
      rather than an absent one. This is a finding, not a defect — investigate before believing."
fi
pass "the Mac app, with a live pairing code on screen, holds 0 listening TCP sockets"

# --- the fact that outranks the socket count ------------------------------------------------------
#
# Raised by the out-of-family review and verified here: even if a phone's bytes did arrive, no
# shipped surface would act on them. `MacPairing.decide` is the Mac's only decision function, and
# outside its own model and the test suites nothing calls it. A transport is not merely unbound; it
# has no consumer. This is source rather than runtime, and it is labelled as such.
decide_callers="$(grep -rln "MacPairing.decide(\|\.markPaired(" "$APP_DIR/Sources" --include="*.swift" || true)"
unexpected="$(printf '%s\n' "$decide_callers" | grep -v "PairingSessionModel.swift" | grep -c . || true)"
if [ "${unexpected:-0}" -gt 0 ]; then
    fail "something outside PairingSessionModel now calls the Mac's pairing decision:
$decide_callers
      I5 recorded that nothing did. If a real caller has appeared, this finding is stale."
fi
pass "source: nothing outside PairingSessionModel calls the Mac's pairing decision"

echo
echo "=== 3. the phone, as a real process ============================================="

udid="$(xcrun simctl list devices available -j \
    | python3 -c "import json,sys; ds=json.load(sys.stdin)['devices']; \
c=[d for v in ds.values() for d in v if d.get('isAvailable') and 'iPhone' in d['name']]; \
c.sort(key=lambda d: d['state'] != 'Booted'); \
print(c[0]['udid'] if c else '')")"
[ -n "$udid" ] || blocked "no available iPhone simulator, so the phone half went unmeasured."
echo "simulator: $udid"

before="$(tap_connections)"

xcodebuild -project "$PROJECT" -scheme MCPRouterIOS -configuration Debug \
    -destination "id=$udid" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    -only-testing:"$SUITE" \
    build-for-testing > "$WORK/phone-build.log" 2>&1 \
    || { tail -30 "$WORK/phone-build.log" >&2
         blocked "the iOS probe would not build, so the phone half went unmeasured.
      Log: $WORK/phone-build.log"; }

bundle="$WORK/result.xcresult"
set +e
xcodebuild -project "$PROJECT" -scheme MCPRouterIOS -configuration Debug \
    -destination "id=$udid" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    -resultBundlePath "$bundle" \
    -only-testing:"$SUITE" \
    test-without-building > "$WORK/phone-test.log" 2>&1
phone_status=$?
set -e

ran="$(xcrun xcresulttool get test-results summary --path "$bundle" --format json 2>/dev/null \
    | python3 -c "import json,sys
try:
    d = json.load(sys.stdin)
    print((d.get('passedTests') or 0) + (d.get('failedTests') or 0))
except Exception:
    print(0)")"

# A filter that matches nothing exits 0 and proves nothing.
[ "${ran:-0}" -ge 3 ] || { tail -30 "$WORK/phone-test.log" >&2
    blocked "the phone probe ran ${ran:-0} assertions where 3 were expected, so the phone half is
      unmeasured. Log: $WORK/phone-test.log"; }

grep -h "I5-PROBE-OUTCOME" "$WORK/phone-test.log" | sed 's/^.*I5-PROBE-OUTCOME/    outcome:/' | head -3 || true

[ "$phone_status" -eq 0 ] || { tail -30 "$WORK/phone-test.log" >&2
    fail "the phone probe is red (xcodebuild exit $phone_status). Its own assertions did not hold,
      so the traffic count below is not interpretable. Log: $WORK/phone-test.log"; }
pass "the phone probe ran $ran assertions on the simulator"

# --- calibration 3: a connection from inside the phone process reaches the tap --------------------
tap_saw "PHONE-REACHABILITY" \
    || blocked "the phone process could not reach the tap. Every absence below is then explained by
      the phone having no route to 127.0.0.1:$TAP_PORT, which is a fact about this harness rather
      than about the product."
pass "calibration: a connection made from inside the phone process reaches the tap"

echo
echo "=== 4. the verdict =============================================================="

after="$(tap_connections)"
echo "tap connections: $before before the phone ran, $after after"
sed 's/^/    /' "$TAP_LOG"

# Two, and exactly two: the host calibration and the phone's own reachability probe. A pairing call
# that reached the endpoint in its payload would be a third.
#
# The phone's reachability connection is what gives this number its meaning. It was made by the same
# process, to the same port, in the same run, and it was counted — so a third connection would have
# been counted too, and its absence is the pairing call's own silence.
expected=2
if [ "$after" -gt "$expected" ]; then
    fail "the tap recorded $after connections where $expected were expected. Something contacted the
      endpoint the pairing payload named. That would mean a transport exists and I5's finding must
      be re-read — investigate the log above before treating this as a defect."
fi
if [ "$after" -lt "$expected" ]; then
    blocked "the tap recorded $after connections where $expected calibration connections were
      expected. The instrument lost traffic it was proven to receive, so nothing is concluded."
fi
pass "the pairing attempt contributed 0 connections to an endpoint it was pointed at and could reach"

echo
echo "PASS: I5 transport probe — $PASSED assertions."
echo
echo "FINDING: the phone-to-Mac pairing round trip does not happen, because neither side"
echo "implements it. Measured here:"
echo "  · the Mac app, with a live pairing code on screen, holds 0 listening TCP sockets"
echo "  · nothing outside PairingSessionModel calls the Mac's pairing decision, so an arriving"
echo "    code would have no consumer even if it arrived"
echo "  · the phone reports .paired for a Mac it never contacted, at an address it could reach"
echo "  · every leg of the instrument was calibrated in this run, so the silence is the product's"
echo
echo "SCOPE — what this run does NOT establish, stated so nobody reads it wider:"
echo "  · the phone half drives the production pairing SEAM (FixturePairingService, which is what"
echo "    the shipping @main composes and is guarded here), not the shipping UI end to end"
echo "  · only TCP to this tap's port was watched. UDP, unix sockets, mDNS, XPC and IPv6 ::1 were"
echo "    not, and are ruled out by source inspection rather than by this instrument"
echo "  · the iOS binary measured is Debug; no Release iOS build was run"
echo "  · the wave 6 gate also covered inbox DELIVERY, which this experiment does not exercise"
