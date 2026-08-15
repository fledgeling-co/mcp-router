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
# renders its board or the "isn't built yet" placeholder. The phone never had such a registry: its
# placeholder was `AwaitingTab`, and item I3 removed it — `PhoneShell` now routes every tab through
# an exhaustive `switch`, where a tab with no surface does not compile.
#
# The discipline is the same — running acceptance over a placeholder proves nothing, whichever
# placeholder it is — but on this device it is discharged by the XCTest suite rather than by
# reading source. See the section below, which explains why the source guard that used to sit
# there was deleted rather than repaired.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$ROOT/app/MCPRouter.xcodeproj"
DERIVED="$ROOT/app/.derived"
SUITE="MCPRouterIOSTests/DiscoverSurfaceIOSTests"

fail() { echo "FAIL: $*"; exit 1; }
# Exit 2 is everything this harness could not establish; exit 1 is a claim about the product.
blocked() { echo "BLOCKED: $*"; exit 2; }
# shellcheck source=scripts/acceptance/xcode-outcome.sh
source "$ROOT/scripts/acceptance/xcode-outcome.sh"

# --- Why there is NO source guard here anymore -----------------------------------------------------
#
# There was one: it grepped `PhoneShell.swift` for `var awaitingKey: PairingCopy.Key?` and read the
# `.discover` arm out of that switch. Item I3 DELETED that declaration — it survives only inside a
# doc comment recording its removal — so the reader matched nothing and took its own
# "could not read … treat as a broken reader, not a pass" branch. This script was therefore
# PERMANENTLY RED against a completely correct product, and no rebuild could clear it.
#
# The obvious repair was to repoint the grep at `content(for tab:)`. That was rejected, because it
# rebuilds the same defect: a grep matches a comment, a `#if` branch, a preview or a dead arm just
# as happily as live code, and it still cannot show that `.discover` ROUTES to the real screen. A
# guard that can be satisfied by a comment is not a guard.
#
# The proof that Discover is real is the XCTest suite below, which constructs the surface on a
# simulator and asserts against it. If Discover were a placeholder those assertions fail. That is a
# behavioural claim with behavioural evidence, and it is strictly stronger than any grep — so the
# grep is gone rather than replaced.

# --- One simulator, reused ------------------------------------------------------------------------
#
# Prefer an already-booted iPhone. Booting several is how this suite got slow, and I1 recorded a
# simulator being OOM-killed by a parallel Xcode build.
udid="$(xcrun simctl list devices available -j \
    | python3 -c "import json,sys; ds=json.load(sys.stdin)['devices']; \
c=[d for v in ds.values() for d in v if d.get('isAvailable') and 'iPhone' in d['name']]; \
c.sort(key=lambda d: d['state'] != 'Booted'); \
print(c[0]['udid'] if c else '')")"

[ -n "$udid" ] || blocked "no available iPhone simulator, so nothing was measured.
      This is an environment failure, not a pass — the rendered claims went unmeasured.
      It exits 2: it already called itself an environment failure while exiting 1, which is the
      code this harness reserves for a claim about the product."
echo "simulator: $udid"

# --- The pass -------------------------------------------------------------------------------------
bundle="$(mktemp -d -t i2-xcresult)/result.xcresult"

# Build and test are SEPARATE invocations, and each failure is judged by its reason rather than by
# which phase it happened in. One `xcodebuild … test` into one status made a compile error and a
# failed assertion produce the same exit 1 and the same sentence naming the surface — opposite
# findings reported identically.
xcodebuild -project "$PROJECT" -scheme MCPRouterIOS -configuration Debug \
    -destination "id=$udid" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    -only-testing:"$SUITE" \
    build-for-testing > /tmp/i2-build.log 2>&1
build_status=$?
if [ "$build_status" -ne 0 ]; then
    kind="$(xcode_failure_kind /tmp/i2-build.log)"
    xcode_failure_excerpt /tmp/i2-build.log "$kind"
    case "$kind" in
        compile) fail "the iOS target does not compile (xcodebuild exit $build_status). This is the
      product, not this harness, and no Discover assertion was reached. Log: /tmp/i2-build.log" ;;
        *) blocked "the iOS test build could not be produced here ($kind, xcodebuild exit
      $build_status), so nothing about Discover was measured. Log: /tmp/i2-build.log" ;;
    esac
fi

xcodebuild -project "$PROJECT" -scheme MCPRouterIOS -configuration Debug \
    -destination "id=$udid" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    -resultBundlePath "$bundle" \
    -only-testing:"$SUITE" \
    test-without-building > /tmp/i2-acceptance.log 2>&1
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
    kind="$(xcode_failure_kind /tmp/i2-acceptance.log)"
    xcode_failure_excerpt /tmp/i2-acceptance.log "$kind"
    case "$kind" in
        infra|unknown) blocked "the Discover pass could not be run to completion ($kind, xcodebuild
      exit $status), so its assertions were not measured. Log: /tmp/i2-acceptance.log" ;;
        *) fail "the Discover acceptance pass is red (xcodebuild exit $status). Log: /tmp/i2-acceptance.log" ;;
    esac
fi
if [ "${ran:-0}" -lt 1 ]; then
    fail "zero assertions ran. A filter that matches nothing exits 0 and proves nothing."
fi

echo "PASS: I2 Discover + detail — $ran assertions, one simulator, nothing else driven"
