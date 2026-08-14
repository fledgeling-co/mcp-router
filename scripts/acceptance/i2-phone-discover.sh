#!/bin/bash
#
# I2 — iPhone Discover and detail · the item's one acceptance gate.
#
# Scope: the phone's Discover list and capability detail, and nothing else. I1's shell, pairing and
# settings are merged and evidenced in `planning/evidence/I1-acceptance.md`; this run does not
# re-prove them. The Mac's boards are another lane entirely.
#
# ## Why this does not source `board-registry.sh`
#
# It was read, and it answers a question about the wrong device. `board-registry.sh` reads
# `BoardRegistry.installed` in `ScaffoldPane.swift`, which decides whether a **Mac** destination
# renders its board or the "isn't built yet" placeholder. The phone has no such registry: its
# placeholder is `AwaitingTab`, selected by `PhoneShell.Tab.awaitingKey` returning non-nil.
#
# The discipline is the same and is applied below to the declaration that actually governs this
# surface — running acceptance over a placeholder proves nothing, whichever placeholder it is. The
# reader is written the way `board-registry.sh` is written, and for the same reason: it collects the
# whole `switch` rather than reading one line, so wrapping cannot make it quietly match nothing.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHELL_SOURCE="$ROOT/app/Sources/MCPRouterUI/Phone/PhoneShell.swift"
PROJECT="$ROOT/app/MCPRouter.xcodeproj"
DERIVED="$ROOT/app/.derived"
SUITE="MCPRouterIOSTests/DiscoverSurfaceIOSTests"

fail() { echo "FAIL: $*"; exit 1; }

# --- Guard: is Discover real, or is it still the awaiting placeholder? ----------------------------
#
# Prints the `awaitingKey` arm for a tab. Collects the whole switch body, so a wrapped or
# reformatted declaration cannot make this match nothing and read as a pass.
awaiting_arm_for() {
    awk -v tab="$1" '
        /var awaitingKey: PairingCopy\.Key\?/ { collecting = 1 }
        collecting                            { body = body " " $0 }
        collecting && /^        \}/           { exit }
        END {
            if (match(body, "case \\." tab ": *[^ ]+")) {
                print substr(body, RSTART, RLENGTH)
            }
        }
    ' "$2"
}

[ -f "$SHELL_SOURCE" ] || fail "cannot find PhoneShell.swift — the guard did not run"

arm="$(awaiting_arm_for discover "$SHELL_SOURCE")"
if [ -z "$arm" ]; then
    fail "could not read the .discover arm of awaitingKey — treat as a broken reader, not a pass"
fi
if [[ "$arm" != *"nil"* ]]; then
    fail "BLOCKED: .discover still resolves to the awaiting placeholder ($arm).
      Running acceptance over a placeholder proves nothing. A32 is not satisfied by a view that
      compiles behind a tab still rendering the awaiting state."
fi
echo "guard: .discover resolves to a board, not the placeholder ($arm)"

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
bundle="$(mktemp -d -t i2-xcresult)/result.xcresult"
xcodebuild -project "$PROJECT" -scheme MCPRouterIOS -configuration Debug \
    -destination "id=$udid" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    -resultBundlePath "$bundle" \
    -only-testing:"$SUITE" \
    test > /tmp/i2-acceptance.log 2>&1
status=$?

# A suite that ran nothing exits 0 and means nothing, so the count is asserted rather than the code.
ran="$(xcrun xcresulttool get test-results summary --path "$bundle" --format json 2>/dev/null \
    | python3 -c "import json,sys
try:
    d = json.load(sys.stdin)
    print((d.get('passedTests') or 0) + (d.get('failedTests') or 0))
except Exception:
    print(0)")"

echo "executed $ran assertions over the Discover and detail surfaces"

if [ "$status" -ne 0 ]; then
    grep -E "error:|XCTAssert" /tmp/i2-acceptance.log | sort -u | head -20
    fail "the Discover acceptance pass is red (xcodebuild exit $status). Log: /tmp/i2-acceptance.log"
fi
if [ "${ran:-0}" -lt 1 ]; then
    fail "zero assertions ran. A filter that matches nothing exits 0 and proves nothing."
fi

echo "PASS: I2 Discover + detail — $ran assertions, one simulator, nothing else driven"
