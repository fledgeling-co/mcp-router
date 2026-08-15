#!/usr/bin/env bash
#
# D-g1-g — one lock over the fixed-port parity harness.
#
# Every parity entry point binds FIXED ports. The gate's twelve lanes bind 8957-8998, and the
# control lane reaches control-differential.sh (parity-control.sh:19), which binds 8973 — so 8973
# is inside the gate's port set too, and a standalone control run genuinely contends with a gate.
#
# The register recorded this as "two parity runs corrupt each other silently". Measured, that is
# not what happens. Ten of the thirteen port-binding scripts carry an `lsof` pre-guard and exit 2
# naming the port; the two without one (p1-auth-routes.sh, control-client.sh) still exit 2 from
# their post-bind health check, surfacing EADDRINUSE. No path was found that produces a wrong
# COMPARISON. What actually happens is quieter and worse:
#
#   a run that could not measure the surface still printed a coverage fraction.
#
# `parity: 69 of 83` and `parity: 77 of 83` are the recorded signatures, against a truth of 78. The
# fraction is what gets copied into a ledger; the tail that explains it is what gets skimmed. That
# harm is fixed at its source in parity-gate.sh, which now withholds the fraction whenever a lane
# could not run. THIS file is the second measure: it stops the contention happening at all, and it
# makes the fleet's "one parity runner at a time" rule mechanical rather than a line in a brief.
#
# Why `mkdir` and not `/usr/bin/shlock` or `flock`:
#   - `mkdir` is atomic on every POSIX filesystem and needs no binary. `shlock` is BSD-only, and
#     `flock(1)` is util-linux and absent from base macOS entirely.
#   - The staleness rule is the part that has to be trusted, so it is written out and tested here
#     rather than inherited from a tool's undocumented internals.
#
# Sourced, not executed:
#   . "$REPO_ROOT/scripts/acceptance/parity-lock.sh"
#   parity_lock_acquire "gate"     # takes the lock or exits 2; never returns having failed
# and `parity_lock_release` goes INSIDE the script's existing cleanup function — never as a second
# `trap ... EXIT`, which would replace the handler that kills the lane's router.
#
# The lock is MACHINE-WIDE (under $TMPDIR, per-user and stable across shells on macOS) rather than
# per-worktree: the thing protected is a set of TCP ports, and two worktrees contend for them
# exactly as two runs in one worktree do.

PARITY_LOCK_DIR="${PARITY_LOCK_DIR:-${TMPDIR:-/tmp}/mcp-router-parity.lock}"
PARITY_LOCK_PIDFILE="$PARITY_LOCK_DIR/pid"
PARITY_LOCK_STARTFILE="$PARITY_LOCK_DIR/start"
PARITY_LOCK_CMDFILE="$PARITY_LOCK_DIR/cmd"

# Set to the acquiring shell's BASHPID, and ONLY there. A command substitution — `x="$(curl ...)"`
# — forks a subshell that inherits ordinary shell variables and, in these scripts, runs the EXIT
# trap when it ends. Guarding release on `$$` would not catch that, because `$$` is unchanged in a
# subshell; `BASHPID` is. Without this guard the first command substitution after acquire would
# release the lock mid-run, a waiter would bind, and this run would carry on talking to its own
# port while a second one came up underneath it.
PARITY_LOCK_HELD_BY=""

# How long to wait for a winner that created the directory but has not yet written its pid.
# Bounded, because an unbounded wait turns a crashed writer into a hang.
PARITY_LOCK_PID_WAIT_TENTHS="${PARITY_LOCK_PID_WAIT_TENTHS:-20}"

# And how old a PIDLESS lock must be before it may be reclaimed at all.
#
# This closes the one race the first version of this file still had, found by an out-of-family
# review. A winner does `mkdir` and then writes its pid; if it were descheduled between the two, a
# waiter could declare the lock pidless-and-stale, `mv` the directory away, create its own — and
# then the first process's `printf` would land in the NEW holder's directory, overwriting its pid.
# Both would believe they held the lock and both would bind.
#
# The write follows the mkdir by microseconds, so requiring a pidless lock to be half a minute old
# before it can be reclaimed makes that displacement unreachable in any real scheduling, while
# still clearing the genuinely half-written lock a killed runner leaves behind.
PARITY_LOCK_ORPHAN_SECONDS="${PARITY_LOCK_ORPHAN_SECONDS:-30}"

parity_lock__inode() { stat -f %i "$1" 2>/dev/null || stat -c %i "$1" 2>/dev/null; }
parity_lock__mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

parity_lock__read_pid() {
    [ -f "$PARITY_LOCK_PIDFILE" ] || return 1
    local pid
    pid="$(tr -dc '0-9' < "$PARITY_LOCK_PIDFILE" 2>/dev/null)"
    [ -n "$pid" ] || return 1
    printf '%s' "$pid"
}

# Liveness is asked of `ps`, not of `kill -0`.
#
# `kill -0` fails with EPERM for a live process owned by another uid, and the shell cannot tell
# that apart from ESRCH. Treating every failure as "dead" would steal a lock from a running holder.
# `ps -p` lists the process whoever owns it, so absence from `ps` is the only thing read as death.
parity_lock__pid_alive() {
    [ -n "$(ps -p "$1" -o pid= 2>/dev/null)" ]
}

parity_lock__pid_start() {
    ps -p "$1" -o lstart= 2>/dev/null | sed 's/^ *//;s/ *$//'
}

# A lock is stale when the recorded pid is gone, when the pid has been REUSED by a different
# process, or when no pid was ever recorded. All three happen for real: this fleet has had runners
# killed mid-run by HTTP 503s, this machine runs at load 100+ where pid reuse is fast, and a writer
# can die between the mkdir and the write.
#
# Pid reuse is why the start time is recorded. Without it, a recycled pid makes a dead lock look
# permanently live, and every later run exits 2 forever — the lock would then be a worse outage
# than the contention it prevents.
parity_lock__is_stale() {
    local pid tries=0
    while :; do
        if pid="$(parity_lock__read_pid)"; then
            parity_lock__pid_alive "$pid" || return 0
            if [ -f "$PARITY_LOCK_STARTFILE" ]; then
                local recorded current
                recorded="$(head -1 "$PARITY_LOCK_STARTFILE" 2>/dev/null)"
                current="$(parity_lock__pid_start "$pid")"
                if [ -n "$recorded" ] && [ -n "$current" ] && [ "$recorded" != "$current" ]; then
                    return 0   # same number, different process: the pid was recycled
                fi
            fi
            return 1
        fi
        tries=$((tries + 1))
        if [ "$tries" -ge "$PARITY_LOCK_PID_WAIT_TENTHS" ]; then
            # No pid was ever written. Only reclaim once the directory is old enough that a live
            # winner cannot still be between its `mkdir` and its write.
            local created now
            created="$(parity_lock__mtime "$PARITY_LOCK_DIR")"
            now="$(date +%s)"
            [ -n "$created" ] || return 1
            [ $((now - created)) -ge "$PARITY_LOCK_ORPHAN_SECONDS" ] && return 0
            return 1
        fi
        sleep 0.1
    done
}

parity_lock__describe_holder() {
    local pid
    if pid="$(parity_lock__read_pid)"; then
        printf 'pid %s' "$pid"
        local cmd=""
        cmd="$(ps -o command= -p "$pid" 2>/dev/null | head -1)" || cmd=""
        [ -n "$cmd" ] && printf ' — %s' "$cmd"
        [ -f "$PARITY_LOCK_CMDFILE" ] &&
            printf ' (took the lock as: %s)' "$(head -1 "$PARITY_LOCK_CMDFILE" 2>/dev/null || true)"
    else
        printf 'an unidentified holder (no pid recorded)'
    fi
    return 0
}

# Re-entrancy, and the trap in it.
#
# The gate dispatches lanes that take this same lock, so without re-entrancy the gate deadlocks
# against itself. The obvious implementation — export a flag, honour the flag — silently disables
# the lock for every process that inherits it, including a shell where an earlier run died and left
# it exported. A secret token file is only slightly better: it is readable, so entry rests on
# nobody having copied a string.
#
# Entry is therefore granted on DESCENT, not on knowledge: the holder's pid must be this process or
# one of its ancestors. A leftover export from an unrelated shell names a pid that is not an
# ancestor of anything in a new run, so it grants nothing.
parity_lock__holder_is_ancestor() {
    local holder="$1" p="$$" hops=0
    while [ -n "$p" ] && [ "$p" != "0" ] && [ "$p" != "1" ] && [ "$hops" -lt 40 ]; do
        [ "$p" = "$holder" ] && return 0
        p="$(ps -p "$p" -o ppid= 2>/dev/null | tr -d ' ')" || p=""
        hops=$((hops + 1))
    done
    return 1
}

parity_lock__reentrant() {
    local pid
    pid="$(parity_lock__read_pid)" || return 1
    parity_lock__pid_alive "$pid" || return 1
    parity_lock__holder_is_ancestor "$pid"
}

# Takes the lock or exits 2. Never returns having failed.
parity_lock_acquire() {
    local label="${1:-parity}"

    if [ "${PARITY_NO_LOCK:-}" = "1" ]; then
        echo "parity-lock: PARITY_NO_LOCK=1 — the harness lock is DISABLED for this run."
        echo "             Concurrent runs contend for fixed ports and any coverage fraction"
        echo "             printed while another run is live is not trustworthy."
        return 0
    fi

    parity_lock__reentrant && return 0   # inside the holder's own process tree

    local attempt
    for attempt in 1 2; do
        if mkdir "$PARITY_LOCK_DIR" 2>/dev/null; then
            local claimed_inode
            claimed_inode="$(parity_lock__inode "$PARITY_LOCK_DIR")"
            printf '%s\n' "$$" > "$PARITY_LOCK_PIDFILE"
            parity_lock__pid_start "$$" > "$PARITY_LOCK_STARTFILE" || true
            printf '%s\n' "$label" > "$PARITY_LOCK_CMDFILE"
            # Confirm the directory written into is still the one created. If a reclaimer replaced
            # it in between, these writes went into somebody else's lock and this process does not
            # hold one — refusing is the safe direction, and it is reported rather than assumed.
            if [ "$(parity_lock__inode "$PARITY_LOCK_DIR")" != "$claimed_inode" ] ||
                    [ "$(cat "$PARITY_LOCK_PIDFILE" 2>/dev/null | tr -dc '0-9')" != "$$" ]; then
                echo "parity-lock: the lock was replaced while this run was claiming it."
                echo "             Refusing rather than proceeding, because two holders is the one"
                echo "             outcome this lock exists to prevent."
                exit 2
            fi
            PARITY_LOCK_HELD_BY="$BASHPID"
            return 0
        fi

        # Lost the race, or the lock is stale. Reclaiming with `rm -rf` on the LIVE name is a race
        # with a second reclaimer: both would remove, both would mkdir, and both would believe they
        # held it. `mv` renames atomically, so exactly one reclaimer succeeds and the loser's mv
        # fails because the source is already gone.
        if [ "$attempt" = 1 ] && parity_lock__is_stale; then
            local aside="$PARITY_LOCK_DIR.stale.$$"
            if mv "$PARITY_LOCK_DIR" "$aside" 2>/dev/null; then
                echo "parity-lock: cleared a stale lock at $PARITY_LOCK_DIR"
                rm -rf "$aside"
            fi
            continue   # whether we won the reclaim or lost it, try mkdir once more
        fi
        break
    done

    echo "parity-lock: the parity harness is already in use by $(parity_lock__describe_holder)."
    echo
    echo "Every lane binds a fixed port, so two runs contend and neither measures the surface it"
    echo "reports on. This run has bound nothing and is printing no coverage fraction, because a"
    echo "fraction from a contended run reads as a low score rather than as a refusal."
    echo
    echo "Wait for the other run to finish, or override deliberately with PARITY_NO_LOCK=1."
    exit 2
}

# Safe to call unconditionally from a cleanup function. It removes the lock only from the exact
# shell that created it — not from a command-substitution subshell that inherited the variable and
# is running the same EXIT trap.
parity_lock_release() {
    [ -n "$PARITY_LOCK_HELD_BY" ] || return 0
    [ "$BASHPID" = "$PARITY_LOCK_HELD_BY" ] || return 0
    rm -rf "$PARITY_LOCK_DIR"
    PARITY_LOCK_HELD_BY=""
}
