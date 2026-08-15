#!/bin/bash
#
# Why an `xcodebuild` run failed — the reason, not the phase.
#
# `i2` and `i3` each ran ONE `xcodebuild … test` into one status and branched on it once, so a
# Swift compile error and a failed assertion produced the same exit 1 and the same sentence:
# "the Discover acceptance pass is red". Those are opposite findings. One says a screen misbehaves;
# the other says the target does not build at all, and the screen was never exercised.
#
# The first fix drafted for this was to split the run into `build-for-testing` then
# `test-without-building` and call any build failure BLOCKED 2. That is wrong, and the review that
# caught it was right: **"your code does not compile" is a claim about the product**, and a true
# one. Filing it as an environment failure hides a real defect behind the same word this harness
# uses for a missing simulator.
#
# So the split is kept — it makes the logs and the sentences precise — and the VERDICT is decided
# by reading why the run failed:
#
#   compile → the sources do not build            → FAIL 1. The product.
#   test    → an assertion failed                 → FAIL 1. The product.
#   infra   → no simulator, destination, signing,
#             a lost test connection              → BLOCKED 2. Nothing was measured.
#   unknown → could not be established            → BLOCKED 2, because the rule is that anything
#                                                   the harness cannot establish is exit 2.
#
# `unknown` deliberately defaults to BLOCKED rather than FAIL. Guessing "product" from an
# unrecognised log is how a harness invents a defect, which is this item's whole subject.

# Prints one of: compile | test | infra | unknown
xcode_failure_kind() {
    local log="$1"
    [ -f "$log" ] || { printf 'unknown'; return; }

    # Environment first: a machine that could not host the run explains everything after it, and
    # these messages are unambiguous where a stray "error:" is not.
    if grep -qE 'Unable to find a destination|Available destinations for the|Unsupported destination|Simulator device failed to boot|Unable to boot (the )?[Ss]imulator|Failed to install the requested application|Lost connection to the test(ing)? (manager|session)|Timed out waiting for .* to boot|No simulator runtime|requires a provisioning profile|[Cc]ode [Ss]ign(ing)? [Ee]rror|No profiles for|not currently available' "$log"; then
        printf 'infra'
        return
    fi
    # A source-located diagnostic. Anchored to `file.ext:line:col: error:` so that the word "error"
    # appearing inside a test's own message cannot be read as a compile failure.
    if grep -qE '^[^[:space:]]+\.(swift|m|mm|c|cc|cpp|h|hpp):[0-9]+:([0-9]+:)?[[:space:]]*error:' "$log"; then
        printf 'compile'
        return
    fi
    if grep -qE 'XCTAssert|XCTFail|Test Case .* failed|\*\* TEST FAILED \*\*|recorded an issue' "$log"; then
        printf 'test'
        return
    fi
    printf 'unknown'
}

# The lines worth showing for that kind, so a reader gets the cause rather than 4,000 lines of log.
xcode_failure_excerpt() {
    local log="$1" kind="$2"
    case "$kind" in
        compile) grep -E '^[^[:space:]]+\.(swift|m|mm|c|cc|cpp|h|hpp):[0-9]+:([0-9]+:)?[[:space:]]*error:' "$log" | sort -u | head -20 ;;
        test) grep -E 'XCTAssert|XCTFail|Test Case .* failed|recorded an issue' "$log" | sort -u | head -20 ;;
        infra) grep -E 'Unable to|Failed to|Lost connection|Timed out|provisioning|[Cc]ode [Ss]ign|not currently available' "$log" | sort -u | head -20 ;;
        *) tail -20 "$log" ;;
    esac
}
