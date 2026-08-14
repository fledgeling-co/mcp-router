#!/bin/bash
#
# I3 — iPhone Triage, Queue and Library · the item's one acceptance gate.
#
# Scope: the phone's Triage, Queue and Library surfaces, and nothing else. I1's shell, pairing and
# settings and I2's Discover are merged and evidenced in `planning/evidence/I1-acceptance.md` and
# `I2-acceptance.md`; this run does not re-prove them. Re-running a passing check against unchanged
# code has one possible outcome, and a check whose result you can predict is not evidence.
#
# ## What it sources from `board-registry.sh`, and what it deliberately does not
#
# `board-registry.sh` reads `BoardRegistry.installed`, which decides whether a **Mac** destination
# renders its board or the "isn't built yet" placeholder. It cannot answer anything about a phone
# tab: the phone has no registry, and since I3 it has no placeholder either — `AwaitingTab` and
# `awaitingKey` are deleted, so the equivalent guard is `PhoneShell.content(for:)`'s `switch`.
#
# It is sourced anyway, for one claim that is genuinely cross-device and load-bearing here. The
# Queue tells the user *"Open MCP Router on {mac} to review them"*. That sentence is only true if
# the Mac ships the Inbox board that reviews them — and M6 is what shipped it. If `.inbox` ever
# leaves `BoardRegistry.installed`, this phone's copy becomes a promise about a screen that does not
# exist, and nothing on the phone side could detect it. That is the one question worth asking the
# Mac's registry, so it is asked with the Mac's own reader rather than a fourth copy of one.
#
# The dispatch guard below is written the way `board-registry.sh` is written and for the same
# reason: it collects the whole `switch` body rather than matching one line, so reformatting cannot
# make it quietly match nothing and read as a pass.
#
# ## Appearance
#
# Nothing here pins an appearance. An earlier iOS assertion in this fleet pinned dark
# unconditionally and failed reporting `#ECECEE` — the *light* ground rendering perfectly correctly.
# The suite this drives leaves the interface style `.unspecified` and asserts geometry and copy.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHELL_SOURCE="$ROOT/app/Sources/MCPRouterUI/Phone/PhoneShell.swift"
SCAFFOLD_SOURCE="$ROOT/app/Sources/MCPRouterUI/Shell/ScaffoldPane.swift"
PROJECT="$ROOT/app/MCPRouter.xcodeproj"
DERIVED="$ROOT/app/.derived"
SUITE="MCPRouterIOSTests/TriageSurfaceIOSTests"

# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/board-registry.sh"

fail() { echo "FAIL: $*"; exit 1; }

# --- Guard 1: does each tab reach its own surface, or does it fall through to Settings? ------------
#
# The failure this exists to catch is specific. The dispatch used to be
# `if .discover { … } else if let key = awaitingKey { … } else { PhoneSettingsScreen }`, so removing
# the awaiting arm would have routed Triage, Queue and Library to the final `else` — all three
# rendering **Settings**, while every "no awaiting copy is compiled" check stayed green.
#
# Prints the screen an arm reaches. Collects the whole `content(for:)` body first.
dispatch_arm_for() {
    awk -v tab="$1" '
        /private func content\(for tab: Tab\)/ { collecting = 1 }
        collecting                             { body = body " " $0 }
        collecting && /^    \}/                { exit }
        END {
            if (match(body, "case \\." tab ": *[A-Za-z]+")) {
                arm = substr(body, RSTART, RLENGTH)
                sub("case \\." tab ": *", "", arm)
                print arm
            }
        }
    ' "$2"
}

[ -f "$SHELL_SOURCE" ] || fail "cannot find PhoneShell.swift — the guard did not run"

for pair in "triage:TriageScreen" "queue:QueueScreen" "library:LibraryScreen"; do
    tab="${pair%%:*}"
    expected="${pair##*:}"
    arm="$(dispatch_arm_for "$tab" "$SHELL_SOURCE")"
    if [ -z "$arm" ]; then
        fail "could not read the .$tab arm of content(for:) — treat as a broken reader, not a pass"
    fi
    if [ "$arm" != "$expected" ]; then
        fail "BLOCKED: .$tab renders $arm, not $expected.
      Running acceptance over the wrong surface proves nothing about the right one."
    fi
    echo "guard: .$tab reaches $arm"
done

# The placeholder is gone entirely, not merely bypassed.
#
# Comments are stripped before the scan, and that is not fastidiousness: `PhoneShell.swift`'s doc
# comment *explains* the shape that was deleted, naming `awaitingKey` in order to record why the
# `switch` replaced it. A naive grep matches that explanation and reports the placeholder as alive —
# the exact failure `PhoneSourceGuardTests.stripped` exists to prevent, and the reason a gate that
# matches its own documentation gets deleted for being noisy.
if sed -e 's://.*::' "$SHELL_SOURCE" | grep -qE "awaitingKey|AwaitingTab"; then
    fail "the awaiting placeholder survives in PhoneShell.swift — A30 deletes it, it does not hide it"
fi
echo "guard: the awaiting placeholder is deleted, not bypassed"

# --- Guard 2: the Mac still ships the board this phone's copy points at ---------------------------
if [ -f "$SCAFFOLD_SOURCE" ]; then
    installed="$(board_registry_installed "$SCAFFOLD_SOURCE")"
    if [ -z "$installed" ]; then
        fail "the Mac's board registry could not be read — a broken reader, never an empty set"
    fi
    if ! board_registry_installs "$SCAFFOLD_SOURCE" inbox; then
        fail "BLOCKED: the Mac does not install .inbox, so the Queue's
      'Open MCP Router on {mac} to review them' promises a screen that does not exist."
    fi
    echo "guard: the Mac installs .inbox, so the Queue's instruction is true"
else
    echo "note: ScaffoldPane.swift not found — the cross-device guard did not run (reported, not passed)"
fi

# --- One simulator, reused ------------------------------------------------------------------------
#
# Prefer an already-booted iPhone. Booting several is how this suite got slow, and I1 recorded a
# simulator being OOM-killed by a parallel Xcode build.
udid="$(xcrun simctl list devices available -j \
    | python3 -c "import json,sys; ds=json.load(sys.stdin)['devices']; \
c=[d for v in ds.values() for d in v if d.get('isAvailable') and 'iPhone' in d['name']]; \
c.sort(key=lambda d: d['state'] != 'Booted'); \
print(c[0]['udid'] if c else '')")"

[ -n "$udid" ] || fail "no available iPhone simulator, so nothing was measured.
      This is an environment failure, not a pass — the rendered claims went unmeasured."
echo "simulator: $udid"

# --- The pass -------------------------------------------------------------------------------------
bundle="$(mktemp -d -t i3-xcresult)/result.xcresult"
xcodebuild -project "$PROJECT" -scheme MCPRouterIOS -configuration Debug \
    -destination "id=$udid" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    -resultBundlePath "$bundle" \
    -only-testing:"$SUITE" \
    test > /tmp/i3-acceptance.log 2>&1
status=$?

# A suite that ran nothing exits 0 and means nothing, so the count is asserted rather than the code.
ran="$(xcrun xcresulttool get test-results summary --path "$bundle" --format json 2>/dev/null \
    | python3 -c "import json,sys
try:
    d = json.load(sys.stdin)
    print((d.get('passedTests') or 0) + (d.get('failedTests') or 0))
except Exception:
    print(0)")"

echo "executed $ran assertions over Triage, Queue and Library"

if [ "$status" -ne 0 ]; then
    grep -E "error:|XCTAssert" /tmp/i3-acceptance.log | sort -u | head -20
    fail "the I3 acceptance pass is red (xcodebuild exit $status). Log: /tmp/i3-acceptance.log"
fi
if [ "${ran:-0}" -lt 1 ]; then
    fail "zero assertions ran. A filter that matches nothing exits 0 and proves nothing."
fi

echo "PASS: I3 Triage + Queue + Library — $ran assertions, one simulator, nothing else driven"
