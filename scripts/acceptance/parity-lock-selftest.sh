#!/usr/bin/env bash
#
# D-g1-g — can the parity harness lock actually refuse?
#
# The lock exists so that a second parity run cannot quietly produce a low coverage number. A lock
# that silently grants entry would leave exactly the defect it was written for while looking fixed,
# and that failure mode is invisible from a green gate — the gate passes either way. So the lock
# gets its own red-green instrument, the same way the lanes do.
#
# Every case here is a REFUSAL or a GRANT that must happen for a stated reason. A case that cannot
# be made to fail is not evidence.
#
# Exit codes: 0 every case held · 1 a case did not hold · 2 the environment could not run a case.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# A private lock path, so running this never disturbs a real parity run — and so a real parity run
# never makes this selftest fail for a reason that is not about the lock's logic.
export PARITY_LOCK_DIR="${TMPDIR:-/tmp}/mcp-router-parity-selftest.$$.lock"

. "$REPO_ROOT/scripts/acceptance/parity-lock.sh"

pass=0
fail=0
declare -a failures=()
HELPERS=()

ok()   { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail + 1)); failures+=("$1"); printf '  FAIL  %s\n' "$1"; }

cleanup() {
    for p in ${HELPERS+"${HELPERS[@]}"}; do { kill "$p"; } 2>/dev/null || true; done
    rm -rf "$PARITY_LOCK_DIR" "$PARITY_LOCK_DIR".stale.* 2>/dev/null
}
trap cleanup EXIT INT TERM HUP

reset_lock() { rm -rf "$PARITY_LOCK_DIR"; PARITY_LOCK_HELD_BY=""; }

# Plants a lock owned by a pid that is alive but is NOT an ancestor of this shell — which is what a
# genuinely independent second parity run looks like from here. Sets $HOLDER rather than echoing:
# a background job started inside `$( )` inherits that command substitution's stdout pipe, so the
# substitution would block until the helper exited rather than returning its pid. The redirect on
# the helper is belt and braces against the same thing.
HOLDER=""
plant_foreign_lock() {
    local fake_start="${1:-}"
    sleep 120 >/dev/null 2>&1 &
    HOLDER=$!
    HELPERS+=("$HOLDER")
    mkdir -p "$PARITY_LOCK_DIR"
    printf '%s\n' "$HOLDER" > "$PARITY_LOCK_DIR/pid"
    if [ -n "$fake_start" ]; then
        printf '%s\n' "$fake_start" > "$PARITY_LOCK_DIR/start"
    else
        ps -p "$HOLDER" -o lstart= 2>/dev/null | sed 's/^ *//;s/ *$//' > "$PARITY_LOCK_DIR/start"
    fi
    printf 'a-foreign-run\n' > "$PARITY_LOCK_DIR/cmd"
}

drop_holder() {
    [ -n "$HOLDER" ] || return 0
    kill "$HOLDER" 2>/dev/null
    wait "$HOLDER" 2>/dev/null
    HOLDER=""
}

# Runs `parity_lock_acquire` in a process that is NOT under this shell's lock, capturing its exit
# code and output. `env -u` strips nothing that matters now that entry is by descent, but it is
# stripped anyway so a future change back to a token cannot make this case pass by inheritance.
try_acquire_foreign() {
    env -u PARITY_LOCK_OWNER PARITY_LOCK_DIR="$PARITY_LOCK_DIR" \
        bash -c ". \"$REPO_ROOT/scripts/acceptance/parity-lock.sh\"; parity_lock_acquire probe" \
        </dev/null >"$OUT" 2>&1
    printf '%s' $?
}

OUT="$(mktemp -t parity-lock-selftest)"
trap 'cleanup; rm -f "$OUT"' EXIT

echo "parity-lock selftest — $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo

# ------------------------------------------------------------------------------------ L1 acquire
reset_lock
( parity_lock_acquire "selftest-L1" ) >/dev/null 2>&1
PARITY_LOCK_HELD_BY="$BASHPID"   # L3 tests release; this shell is the notional owner
if [ -d "$PARITY_LOCK_DIR" ] && [ "$(cat "$PARITY_LOCK_DIR/pid" 2>/dev/null)" = "$$" ]; then
    ok "L1 a clean acquire creates the lock and records this pid"
else
    bad "L1 a clean acquire did not create a lock recording this pid"
fi

# ------------------------------------------------------------------- L2 re-entrancy by descent
# The gate dispatches control-differential.sh, which takes this same lock. Without re-entrancy the
# gate deadlocks against its own control lane.
if bash -c ". \"$REPO_ROOT/scripts/acceptance/parity-lock.sh\"; parity_lock_acquire child" \
        >/dev/null 2>&1; then
    ok "L2 a descendant of the holder proceeds (the gate does not block its own lanes)"
else
    bad "L2 a descendant was refused — the gate would deadlock against its own control lane"
fi

# ------------------------------------------------------- L3 a subshell must not drop a live lock
# `x="$(...)"` forks a subshell that inherits both the variables and the EXIT trap. control-
# differential.sh has already paid for this once: its handler killed the router mid-run.
( parity_lock_release )
if [ -d "$PARITY_LOCK_DIR" ]; then
    ok "L3 a command-substitution subshell cannot release a lock it did not create"
else
    bad "L3 a subshell released the lock — a second run could bind underneath this one"
fi
parity_lock_release

# ------------------------------------------------------------------- L4 an unrelated run refused
reset_lock
plant_foreign_lock
holder="$HOLDER"
code="$(try_acquire_foreign)"
if [ "$code" = 2 ]; then
    ok "L4 an independent run is refused with exit 2"
else
    bad "L4 an independent run got exit $code, not 2 — the lock grants entry to a second run"
fi
if grep -q "already in use" "$OUT" && grep -q "$holder" "$OUT"; then
    ok "L4 the refusal names the holding pid"
else
    bad "L4 the refusal did not name the holding pid"
fi
# The refusal must not print anything shaped like a coverage result.
if grep -qE '^parity: [0-9]+ of [0-9]+' "$OUT"; then
    bad "L4 the refusal printed a coverage fraction"
else
    ok "L4 the refusal prints no coverage fraction"
fi

# ------------------------------------------------------------------------ L5 a live lock is kept
# The complement of L6. A lock whose owner is alive must NOT be stolen, or the lock is decorative.
if [ -d "$PARITY_LOCK_DIR" ] && [ "$(cat "$PARITY_LOCK_DIR/pid")" = "$holder" ]; then
    ok "L5 a live foreign lock is left alone rather than reclaimed"
else
    bad "L5 a live foreign lock was reclaimed"
fi
drop_holder

# ------------------------------------------------------------------- L6 a dead owner is reclaimed
# Runners in this fleet have been killed mid-run by HTTP 503s. A lock that outlived them would be a
# worse outage than the contention it prevents.
reset_lock
sleep 120 >/dev/null 2>&1 &
dead=$!
kill "$dead" 2>/dev/null; wait "$dead" 2>/dev/null
mkdir -p "$PARITY_LOCK_DIR"
printf '%s\n' "$dead" > "$PARITY_LOCK_DIR/pid"
printf 'a-killed-run\n' > "$PARITY_LOCK_DIR/cmd"
( parity_lock_acquire "selftest-L6" ) >/dev/null 2>&1; acq=$?
if [ "$acq" = 0 ] && [ "$(cat "$PARITY_LOCK_DIR/pid" 2>/dev/null)" = "$$" ]; then
    ok "L6 a lock whose owner is dead is cleared and re-acquired"
else
    bad "L6 a dead owner's lock was not reclaimed — parity would be blocked permanently"
fi
reset_lock

# --------------------------------------------------------------------------- L7 pid reuse
# At load 100+ pids recycle fast. Without the recorded start time, a recycled pid makes a dead lock
# look live forever and every later run exits 2 — the lock becomes the outage.
reset_lock
plant_foreign_lock 'Thu Jan  1 00:00:00 1970'
holder="$HOLDER"
( parity_lock_acquire "selftest-L7" ) >/dev/null 2>&1; acq=$?
if [ "$acq" = 0 ] && [ "$(cat "$PARITY_LOCK_DIR/pid" 2>/dev/null)" = "$$" ]; then
    ok "L7 a recycled pid (start time disagrees) is treated as stale"
else
    bad "L7 a recycled pid held the lock forever — parity would be blocked permanently"
fi
reset_lock
drop_holder

# ------------------------------------------------------------- L8 a missing pidfile is not fatal
# A writer can die between the mkdir and the pid write. Nobody could ever declare that stale by pid,
# so it is declared stale by the bounded wait instead.
reset_lock
mkdir -p "$PARITY_LOCK_DIR"
PARITY_LOCK_PID_WAIT_TENTHS=2
PARITY_LOCK_ORPHAN_SECONDS=0
( parity_lock_acquire "selftest-L8" ) >/dev/null 2>&1; acq=$?
if [ "$acq" = 0 ] && [ "$(cat "$PARITY_LOCK_DIR/pid" 2>/dev/null)" = "$$" ]; then
    ok "L8 a lock with no pid recorded is reclaimed once it is old enough to be an orphan"
else
    bad "L8 a half-written lock was never reclaimed"
fi
PARITY_LOCK_ORPHAN_SECONDS=30
reset_lock

# ------------------------------------------- L10 a YOUNG pidless lock is a winner mid-claim
# The complement of L8, and the defence against the race an out-of-family review found: a process
# that has just run `mkdir` and has not yet written its pid must not be mistaken for an orphan and
# have its directory taken away, or two runs both believe they hold the lock and both bind.
reset_lock
mkdir -p "$PARITY_LOCK_DIR"
( parity_lock_acquire "selftest-L10" ) >/dev/null 2>&1; acq=$?
if [ "$acq" = 2 ] && [ ! -f "$PARITY_LOCK_DIR/pid" ]; then
    ok "L10 a pidless lock younger than the orphan window is left alone, not stolen"
else
    bad "L10 a winner between mkdir and its pid write was displaced — two runs could both bind"
fi
PARITY_LOCK_PID_WAIT_TENTHS=20
reset_lock

# ------------------------------------------------------------------------------ L9 the override
reset_lock
plant_foreign_lock
holder="$HOLDER"
if PARITY_NO_LOCK=1 env PARITY_LOCK_DIR="$PARITY_LOCK_DIR" \
        bash -c ". \"$REPO_ROOT/scripts/acceptance/parity-lock.sh\"; parity_lock_acquire probe" \
        >"$OUT" 2>&1 && grep -q "DISABLED" "$OUT"; then
    ok "L9 PARITY_NO_LOCK=1 overrides, and says so rather than passing silently"
else
    bad "L9 PARITY_NO_LOCK=1 did not override, or overrode without saying so"
fi
drop_holder

echo
echo "parity-lock selftest: $pass held, $fail did not"
if [ "$fail" != 0 ]; then
    for f in "${failures[@]}"; do echo "  - $f"; done
    echo
    echo "A lock that cannot refuse leaves D-g1-g open while looking closed: the gate is green"
    echo "either way, so this script is the only thing that says which."
    exit 1
fi
exit 0
