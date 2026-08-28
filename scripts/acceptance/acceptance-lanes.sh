#!/bin/bash
#
# Runs EVERY lane enrolled in `make acceptance`, then aggregates.
#
# Why this exists (G10). `make acceptance` used to be eight recipe lines, and make stops a target at
# the first line that fails. `shells.sh` is first, it was red on `main` for long enough that the blob
# was byte-identical across three branches, and so the seven lanes behind it had not been reached at
# all. A lane that has never run is not known to pass — so the red lane did not merely fail, it
# *hid* the other seven, and every later enrolment into this target was inert while still reading in
# its commit message like a way to make a lane run.
#
# The repair is not to reorder the list. Reordering makes one lane run and leaves the ordering as the
# thing that decides what gets measured, which is the same defect with a different lane at the front.
# So: run all of them, keep going past a red one, and aggregate at the end.
#
# The risk of continuing is a green summary over a red lane, which is worse than halting — so that
# is the thing this file is built to make impossible rather than the thing it hopes to avoid:
#
#   * The summary names EVERY lane with its own exit code. There is no total that a lane can be
#     absent from, because the table is printed from the same array the verdict is computed from.
#   * The verdict is computed from the codes, never from a flag any lane could fail to set.
#   * The counts are printed, and `lanes run` must equal `lanes enrolled` or the run is red on that
#     alone — a lane that vanished between enrolment and execution is a result, not a skip.
#   * A lane that exits 0 having asserted NOTHING is not a pass. See below.
#
# That last one is the third failure mode, and it was found in this target rather than reasoned
# about. `control-client.sh` on `main` at `520fed38` printed one line —
# `parity-lock.sh: line 205: BASHPID: unbound variable` — and exited 0 with none of its three
# checks run: `BASHPID` is bash 4.0+, macOS's `/bin/bash` is 3.2.57, the lane sets `-u`, and bash
# 3.2 loses the status of a `set -u` death to whatever its EXIT trap last ran. So the aggregate
# above dispatched a lane, read 0, and wrote PASS.
#
# Fixing that one script does not fix the class, because the class is that **exit 0 is a claim and
# this runner used to take it on trust**. A lane can reach 0 having proved nothing through a dead
# shell, an early `return`, a loop over an empty list, or a `skip` that forgot to change its code —
# and every one of those reads identically from out here. So the runner now asks each lane for
# evidence of work and refuses to call an empty transcript a pass.
#
# What counts as evidence is the house vocabulary these lanes already speak, unchanged: a line
# beginning `ok` or `PASS`, which is what `pass()` prints in shells.sh, mac-shell.sh, m22-boards.sh,
# menu-badge-lane.sh and menu-badge-lane-selftest.sh, what `printf '  ok   …'` prints in
# p1-auth-routes.sh and r7-harness-reconciliation.sh, and what control-client.sh echoes directly. A
# lane that would rather state its own count emits `ACCEPTANCE-ASSERTIONS: <n>`, which wins where it
# appears — so a lane whose output is not prose is not forced into this vocabulary.
#
# A vacuous lane is classed with the FAILURES rather than with the blocked, and the ordering is the
# point: exit 2 is a lane REPORTING that it could not run, which is honest and is why the code
# exists. Exit 0 with nothing behind it is a lane making a claim it did not earn, and that is the
# thing this whole item is about.
#
# **The count is a presence test, not a tally, and the difference is printed rather than implied.**
# Measured on the first real run: control-client.sh makes three checks and was credited with four,
# because it echoes its probe's output and one of those lines is `OK`. That direction is harmless —
# a spurious match can only push a count above zero, and zero is the only value this gate acts on.
# The direction that is NOT harmless is a lane which asserts nothing and happens to echo a
# subprocess line beginning `ok`, and that lane would pass. So the number sits in the table where it
# can be read against what the lane claims to do, `ACCEPTANCE-ASSERTIONS:` exists for a lane that
# wants to be counted exactly, and this paragraph is here instead of a claim that the count is one.
#
# Exit codes, kept distinct for the reason the Makefile has always given: collapsing them is how "no
# Accessibility permission" gets reported as a broken app.
#
#   0  every lane passed, and every lane asserted something
#   1  at least one lane FAILED an assertion (any nonzero that is not 2), or exited 0 asserting none
#   2  no failures, but at least one lane COULD NOT RUN (a lane exited 2)
#
# A failure outranks a blocked lane, because a run with both has something known to be broken in it.
#
# `set -e` is deliberately absent. The whole point is to survive a red lane; -u and pipefail stay.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Each lane's stdout is kept so its assertions can be counted after it exits.
#
# The trap RETURNS the status it was entered with, and that is not ceremony. Bash 3.2 lets an EXIT
# trap's last command overwrite the script's exit status when the shell died on `set -u` — which is
# precisely how the lane that prompted this check reported 0. A runner whose own verdict could be
# laundered the same way would be no better than the thing it is measuring.
LANES_WORK="$(mktemp -d)"
lanes__cleanup() { local status=$?; rm -rf "$LANES_WORK"; return $status; }
trap lanes__cleanup EXIT

# How many assertions a lane made, read off its own transcript rather than off anything it sets.
#
# `grep -c` prints 0 and exits 1 when nothing matches, which is a count rather than an error here.
lane_assertions() {
    local transcript="$1" declared count
    # `sed`, not `tr -dc '0-9'`. The out-of-family review pointed out that stripping non-digits
    # from the whole line reads `ACCEPTANCE-ASSERTIONS: 5 # suite 2` as 52 — a lane declaring five
    # assertions credited with fifty-two, in the one field that is supposed to be authoritative.
    declared="$(sed -nE 's/^ACCEPTANCE-ASSERTIONS:[[:space:]]*([0-9]+).*/\1/p' "$transcript" \
        2>/dev/null | tail -1)"
    if [ -n "$declared" ]; then
        printf '%s' "$declared"
        return 0
    fi
    count="$(grep -cE '^[[:space:]]*(ok|OK|PASS|PASSED)([[:space:]]|$)' "$transcript" 2>/dev/null || true)"
    printf '%s' "${count:-0}"
}

# The enrolled set. This array is the single home for the lane list: the Makefile calls this script
# rather than repeating the lanes, so the target and this table cannot drift apart.
LANES=(
    shells.sh
    control-client.sh
    p1-auth-routes.sh
    mac-shell.sh
    r7-harness-reconciliation.sh
    m22-boards.sh
    menu-badge-lane.sh
    menu-badge-lane-selftest.sh
    r28-extensions.sh
    r31-caches.sh
    r32-desktop-entry.sh
    r32-desktop-entry-selftest.sh
)

# Both overrides exist for the selftest, which must be able to plant lanes with known exits. Neither
# is read in a normal run, and the selftest is what proves the aggregation can actually go red.
LANE_DIR="${ACCEPTANCE_LANES_DIR:-$ROOT/scripts/acceptance}"
if [ -n "${ACCEPTANCE_LANES:-}" ]; then
    read -r -a LANES <<< "$ACCEPTANCE_LANES"
fi

# ── The conditions this table was measured under ──────────────────────────────────────────────
#
# Five of these eight rows are decided by facts about the machine rather than about the tree, and
# a verifier re-running the same eight lanes on the same commit got five different rows because of
# it: two lanes this branch recorded BLOCKED passed for them because `MCPRouterCLI` was already
# sitting in a shared `.build`, and three GUI lanes blocked for them because their session could
# not composite a window.
#
# Neither run was wrong. A per-lane table with no environment beside it is the defect one level up
# — a measurement whose conditions are unrecoverable, which cannot be compared with any other run
# and so cannot be a ledger. These two lines are printed before the lanes and again under the
# table, so a pasted table carries them.
STAMP_CLI="app/.build/debug/MCPRouterCLI"
environment_stamp() {
    local cli_line plane_line probe
    if [ -x "$ROOT/$STAMP_CLI" ]; then
        cli_line="present — $STAMP_CLI, built $(date -r "$ROOT/$STAMP_CLI" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'mtime unreadable')"
    else
        cli_line="absent — no $STAMP_CLI (p1-auth-routes.sh and r7-harness-reconciliation.sh block on this alone)"
    fi
    probe="$LANES_WORK/window-plane"
    plane_line="unknown — swiftc unavailable, so the window plane was never probed"
    if command -v swiftc >/dev/null 2>&1         && swiftc -O -o "$probe" "$ROOT/scripts/acceptance/window-plane.swift" 2>/dev/null; then
        local counts total named
        counts="$("$probe" 2>/dev/null || echo "")"
        total="${counts%% *}"; named="${counts##* }"
        if [ -z "$counts" ]; then
            plane_line="unknown — the probe built but returned nothing"
        elif [ "${total:-0}" -eq 0 ]; then
            plane_line="NO — 0 on-screen windows; shells.sh, mac-shell.sh and menu-badge-lane.sh cannot see a window in this session"
        else
            plane_line="yes — $total on-screen windows, $named named"
        fi
    fi
    echo "ACCEPTANCE-ENV: MCPRouterCLI in .build: $cli_line"
    echo "ACCEPTANCE-ENV: window plane composites: $plane_line"
}

ENROLLED=${#LANES[@]}
names=()
codes=()
asserts=()

echo "══════════════════════════════════════════════════════════════════════"
echo "make acceptance — the environment these lanes are about to be measured in"
echo "══════════════════════════════════════════════════════════════════════"
environment_stamp

for lane in "${LANES[@]}"; do
    echo
    echo "──────────────────────────────────────────────────────────────────────"
    echo "lane: $lane"
    echo "──────────────────────────────────────────────────────────────────────"
    transcript="$LANES_WORK/$lane.out"
    : > "$transcript"
    if [ ! -x "$LANE_DIR/$lane" ]; then
        # Enrolled and not runnable is a RESULT. Skipping it here would recreate the whole defect:
        # a lane nothing dispatches, passing by hand forever while reading as covered work.
        echo "ENROLLED BUT NOT EXECUTABLE: $LANE_DIR/$lane" >&2
        code=127
    else
        # `tee` keeps the lane's output on screen while a copy is kept to count. Only stdout is
        # piped: stderr goes straight through, so a lane's FAIL text still lands on this runner's
        # stderr in its own stream, and every assertion line these lanes print is on stdout.
        # `PIPESTATUS[0]` is the lane's own code — `$?` would be tee's, which is always 0.
        "$LANE_DIR/$lane" | tee "$transcript"
        code=${PIPESTATUS[0]}
    fi
    asserted="$(lane_assertions "$transcript")"
    names+=("$lane")
    codes+=("$code")
    asserts+=("$asserted")
    echo "lane $lane exited $code after $asserted assertion(s)"
done

RUN=${#names[@]}

fails=0
blocked=0
passes=0
vacuous=0

echo
echo "══════════════════════════════════════════════════════════════════════"
echo "make acceptance — per-lane result"
echo "══════════════════════════════════════════════════════════════════════"
printf '%-36s %6s  %-42s %s\n' "LANE" "EXIT" "VERDICT" "ASSERTIONS"
for i in "${!names[@]}"; do
    c=${codes[$i]}
    a=${asserts[$i]}
    case "$c" in
        0)
            if [ "$a" -eq 0 ]; then
                # The claim without the work. Named in its own word rather than folded into FAIL,
                # because the two need different repairs: a FAIL is something the lane measured and
                # did not like, and this is a lane that measured nothing and said so to nobody.
                verdict="VACUOUS — exited 0 having asserted nothing"; vacuous=$((vacuous + 1))
            else
                verdict="PASS"; passes=$((passes + 1))
            fi
            ;;
        2) verdict="BLOCKED — could not run"; blocked=$((blocked + 1)) ;;
        *) verdict="FAIL";    fails=$((fails + 1)) ;;
    esac
    printf '%-36s %6s  %-42s %s\n' "${names[$i]}" "$c" "$verdict" "$a"
done

echo "----------------------------------------------------------------------"
echo "enrolled: $ENROLLED   run: $RUN   pass: $passes   fail: $fails   blocked: $blocked   vacuous: $vacuous"
environment_stamp

# The count check. If these disagree, a lane left the run without leaving a row, and no verdict
# computed from the rows can be trusted — so this is red on its own terms.
if [ "$RUN" -ne "$ENROLLED" ]; then
    echo "ACCEPTANCE FAILED: $ENROLLED lanes enrolled but $RUN produced a result — a lane left no row." >&2
    exit 1
fi

if [ "$vacuous" -gt 0 ]; then
    echo "ACCEPTANCE FAILED: $vacuous of $ENROLLED lanes exited 0 having asserted nothing." >&2
    echo "A lane that proved nothing is not a pass — see each VACUOUS row above. If the lane really" >&2
    echo "could not run, it owes exit 2 and a sentence; if it ran, its assertions are not reaching" >&2
    echo "stdout as 'ok'/'PASS' lines or an 'ACCEPTANCE-ASSERTIONS: <n>' declaration." >&2
fi

if [ "$fails" -gt 0 ]; then
    echo "ACCEPTANCE FAILED: $fails of $ENROLLED lanes failed an assertion." >&2
fi

if [ $((fails + vacuous)) -gt 0 ]; then
    exit 1
fi

if [ "$blocked" -gt 0 ]; then
    echo "ACCEPTANCE COULD NOT COMPLETE: $blocked of $ENROLLED lanes could not run (exit 2)." >&2
    echo "This is not a pass. It is not a failed assertion either — see each lane's own message." >&2
    exit 2
fi

echo "ACCEPTANCE PASSED: all $ENROLLED lanes exited 0, and every one of them asserted something."
exit 0
