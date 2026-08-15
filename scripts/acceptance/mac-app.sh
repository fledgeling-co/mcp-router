#!/bin/bash
#
# The one launcher for the Mac acceptance lane, sourced by every script that drives the app.
#
# ## Why one, and why it says which of five things went wrong
#
# There were five copies of this. Four of them (`m2`, `m5`, `m6`, `m7`) were byte-identical:
#
#     [ -n "$PID" ] && { kill "$PID"; sleep 1; }
#     open -g -a "$MAC_APP" --env "MCPROUTER_SCENARIO=$scenario"
#     sleep 3
#     PID="$(pgrep -n -f 'MCPRouter.app/Contents/MacOS/MCPRouter')"
#
# and `mac-shell.sh`'s did `pkill; sleep 1; open` then polled 40 times before concluding
# "the shell window never appeared" and exiting 1 — a PRODUCT verdict for what is usually an
# environment failure. Three separate faults, each of which has cost a runner a turn:
#
#   1. **`open`'s exit status was discarded in all five.** When LaunchServices refuses a relaunch
#      (the `-600` seen while the previous instance is still terminating), nothing starts, and the
#      harness reports the *window* as absent. Under `set -e` the bare `open` aborts the script
#      instead, which is a different wrong answer to the same question.
#   2. **A fixed `sleep` where an observable was needed.** `sleep 1` after a kill does not mean the
#      process is gone, and `sleep 3` after `open` does not mean it started. Both are races, and a
#      race measured under load is a different measurement — which is why this failed for one
#      reader at load 18–27 and passed for another at load 76.
#   3. **`pkill -f`/`pgrep -f 'MCPRouter.app/Contents/MacOS/MCPRouter'` matches ANY MCPRouter on the
#      machine.** This fleet runs several worktrees at once, each with its own build. That pattern
#      killed other runners' apps and attached to their processes — reading a different binary and
#      reporting about that one. `m8` alone bound its PID to its own bundle path; that method is
#      adopted here rather than overwritten, so the one script that got it right sets the shared
#      behaviour.
#
# ## The five outcomes, and why collapsing them would swap one lie for another
#
# | Observation                                  | Verdict   | Because                                  |
# |----------------------------------------------|-----------|------------------------------------------|
# | the previous instance will not exit          | BLOCKED 2 | nothing was launched; nothing to judge   |
# | no accessibility toolkit                     | BLOCKED 2 | this harness's own instrument is missing |
# | `open` refuses transiently (`-600`)          | BLOCKED 2 | LaunchServices refused, after retries    |
# | `open` says the bundle cannot be executed    | FAIL 1    | a bundle that cannot run IS the product  |
# | `open` exits 0, no bound process appears     | FAIL 1    | it WAS started and did not stay up       |
# | a bound process appeared, then exited        | FAIL 1    | the app started and died. That IS the app|
# | alive, but draws no window inside the bound  | FAIL 1    | the app is running and not drawing       |
# | a window is on screen, the AX tree is unread | BLOCKED 2 | permission or harness, not the product   |
#
# Four of these are the product's fault, and reporting them as environment problems would hide a
# real launch crash — the same class of defect as the one being fixed here, pointed the other way.
#
# The "no bound process" arm is FAIL rather than BLOCKED deliberately, and the reason is that the
# alternative splits ONE crash across two verdicts on timing alone: an app that dies before the
# first poll would read as "nothing ran" while the identical crash a tick later read as a failure.
# Once `open` has exited 0 the launch was accepted, so nothing after that point is an environment
# answer.
#
# The last two are distinguishable rather than guessed: `axkit winid` reads
# `CGWindowListCopyWindowInfo`, which needs no accessibility grant, so "there is a real on-screen
# window" can be established independently of whether the AX tree can be read.
#
# Exit 1 is a claim about the product. Everything the harness could not establish is exit 2.

# How long each wait is allowed to take, in 0.25s ticks.
MAC_APP_WAIT_GONE_TICKS="${MAC_APP_WAIT_GONE_TICKS:-80}"    # 20s for the old instance to die
MAC_APP_WAIT_START_TICKS="${MAC_APP_WAIT_START_TICKS:-80}"  # 20s for a bound process to appear
MAC_APP_WAIT_WINDOW_TICKS="${MAC_APP_WAIT_WINDOW_TICKS:-80}" # 20s for it to draw
# How many times a TRANSIENT LaunchServices refusal is retried before blocking. A bundle that
# is itself malformed is never retried — see `mac_app_launch`.
MAC_APP_OPEN_ATTEMPTS="${MAC_APP_OPEN_ATTEMPTS:-4}"

_mac_app_blocked() { echo "BLOCKED: $*" >&2; exit 2; }
_mac_app_failed() { echo "FAIL: $*" >&2; exit 1; }

# Every pid whose executable lives inside THIS bundle — never another worktree's build.
#
# `pgrep -x MCPRouter` matches the process name, then `ps -o comm=` gives the executable path and
# the prefix test binds it to this bundle. This is `m8`'s method, promoted to the shared one.
# `ps -o comm=` was verified to return the full path untruncated (120 characters here) rather than
# assumed.
#
# Both sides are resolved to their PHYSICAL path first, and that is not a nicety: macOS reports
# `comm` as `/private/var/…` while a caller naturally passes `/var/…`, because `/var` is a symlink.
# A raw prefix test then fails for a perfectly healthy process, and the launcher concludes the app
# never appeared — a FALSE PRODUCT FAILURE, which is precisely the defect this file exists to
# remove. Found by the mutation that forced this arm, not by reading.
_mac_app_realpath() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

mac_app_pids() {
    local bundle candidate exe
    bundle="$(_mac_app_realpath "$1")"
    for candidate in $(pgrep -x MCPRouter 2>/dev/null || true); do
        exe="$(ps -o comm= -p "$candidate" 2>/dev/null || true)"
        case "$exe" in "$bundle"*) printf '%s\n' "$candidate" ;; esac
    done
}

# Ask this bundle's instances to exit, then WAIT until they are actually gone.
#
# This is the specific mechanism behind the `-600`: LaunchServices refuses to relaunch an
# application while a previous instance is still terminating, so `sleep 1` and hope is exactly the
# wrong instrument. Nothing global is killed — another runner's app is not this script's business.
mac_app_wait_gone() {
    local bundle="$1" pids tick
    pids="$(mac_app_pids "$bundle")"
    # shellcheck disable=SC2086  # a pid list, deliberately word-split into kill's arguments
    [ -n "$pids" ] && kill $pids 2>/dev/null
    for ((tick = 0; tick < MAC_APP_WAIT_GONE_TICKS; tick++)); do
        [ -z "$(mac_app_pids "$bundle")" ] && return 0
        sleep 0.25
    done
    _mac_app_blocked "a previous instance of this bundle is still running and would not exit
($(mac_app_pids "$bundle" | tr '\n' ' ')). LaunchServices refuses to relaunch an app while the old
process is still terminating, so nothing was launched and there is nothing to judge."
}

# Hand back with the app BEHIND, not merely launched.
#
# `open -g` does not activate, but an app that restores a window during its own startup can put
# itself in front for a moment afterwards. The old launchers hid that by accident: they slept 3–4
# seconds after `open`, so the flicker happened during the sleep. Waiting on observables returns in
# under a second, which is the point — and it moves that startup activity INTO the caller's
# assertions, where `check_invisible` correctly reports the run as having taken the screen.
#
# Measured: one m7 run in three failed with "the partial assertions brought MCP Router to the
# front", and main's m7 against the same build did not. The speed-up is mine, so the correction
# belongs here rather than in each caller.
#
# `mac-shell.sh` already did this per-check via its own `step_back`; this is that behaviour applied
# once at hand-off, so every script gets it. It CORRECTS rather than judges: a verdict on
# invisibility stays with the caller's own `check_invisible`, which is the assertion that exists to
# make it. Hide-then-unhide is the same background-safe pair `step_back` uses — nothing is activated.
mac_app_settle_behind() {
    local axkit="$1" pid="$2" tick
    for ((tick = 0; tick < 12; tick++)); do
        case "$("$axkit" front 2>/dev/null)" in
            "MCP Router" | MCPRouter) ;;
            *) return 0 ;;
        esac
        "$axkit" hidden "$pid" hide >/dev/null 2>&1 || true
        sleep 0.25
        "$axkit" hidden "$pid" unhide >/dev/null 2>&1 || true
        sleep 0.25
    done
    return 0
}

# Launch, and set PID to this bundle's process. Every step waits on an observable.
#
#   mac_app_launch <bundle> <axkit> [KEY=VALUE ...]
#
# The environment pairs become `--env KEY=VALUE`, which is how a scenario other than the populated
# one is reached.
mac_app_launch() {
    local bundle="$1" axkit="$2"
    shift 2
    local -a env_args=()
    local pair
    for pair in "$@"; do env_args+=(--env "$pair"); done

    # The toolkit is this harness's instrument, so its absence is a harness problem. Without this
    # check a missing or unbuilt `axkit` makes every window probe below fail, the wait times out,
    # and the app gets FAILED for not drawing a window nobody could have seen.
    [ -x "$axkit" ] || _mac_app_blocked "the accessibility toolkit is missing or not executable at
$axkit, so no window or AX observation below could be made. That is this harness, not the app."

    # 1 — the previous instance, waited out rather than slept over.
    mac_app_wait_gone "$bundle"

    # 2 — `open`, with its exit status actually consulted, and its FAILURE READ rather than assumed.
    #
    # Two shell details here are load-bearing, and both were found by running this under a caller's
    # real flags rather than a test's:
    #   · `${env_args[@]+"${env_args[@]}"}` — callers run `set -u`, under which expanding an EMPTY
    #     array with `"${env_args[@]}"` is an unbound-variable error. `mac-shell.sh` launches with
    #     no scenario, so the plain form aborted it before `open` ever ran.
    #   · `|| open_status=$?` — callers also run `set -e`, under which a bare
    #     `open_err="$(open …)"` aborts AT THE ASSIGNMENT when open fails, so the arm below that
    #     exists to explain a refused launch could never be reached.
    #
    # **`-600` is transient, and waiting for the old process to die does not prevent it.** Measured
    # three times on this machine today, including once mid-run immediately after the restoration
    # relaunch, with the previous instance already confirmed gone. LaunchServices needs a moment
    # after a process exits before it will accept the same bundle again. So a refusal that carries
    # the transient signature is RETRIED, bounded — that is establishing the precondition, the same
    # thing every other wait here does, and it is not re-running an assertion until it passes.
    #
    # A refusal that says the bundle itself is wrong ("executable is missing", "damaged") is NOT
    # retried and is NOT an environment answer: a bundle that cannot be executed is the product.
    local open_err open_status=0 attempt
    for ((attempt = 1; attempt <= MAC_APP_OPEN_ATTEMPTS; attempt++)); do
        open_status=0
        open_err="$(open -g -a "$bundle" ${env_args[@]+"${env_args[@]}"} 2>&1)" || open_status=$?
        [ "$open_status" -eq 0 ] && break
        case "$open_err" in
            *"executable is missing"* | *damaged* | *"is not an application"*)
                _mac_app_failed "this bundle cannot be executed, so the app could not start:
${open_err}
That is the built product, not this harness." ;;
        esac
        case "$open_err" in
            *-600* | *LSServerCommunication* | *"Unable to find application"*)
                [ "$attempt" -lt "$MAC_APP_OPEN_ATTEMPTS" ] && { sleep 1; continue; } ;;
        esac
        break
    done
    if [ "$open_status" -ne 0 ]; then
        _mac_app_blocked "LaunchServices refused to open this bundle (open exited $open_status).
Nothing was launched, so nothing below would be a statement about the product.
open said: ${open_err:-（no message）}"
    fi

    # 3 — a process bound to THIS bundle.
    #
    # Once `open` has exited 0, LaunchServices accepted and started the launch. So "no process ever
    # appeared" is no longer an environment answer: something was launched and did not survive long
    # enough to be seen. That is the product, and it is exit 1.
    #
    # The earlier draft called this BLOCKED 2, which split ONE crash across two verdicts purely on
    # timing — an app that dies before the first poll read as "nothing ran", and the identical crash
    # one tick later read as a failure. A gate whose verdict depends on how fast the crash was is
    # the same defect this file exists to remove.
    local tick
    PID=""
    for ((tick = 0; tick < MAC_APP_WAIT_START_TICKS; tick++)); do
        PID="$(mac_app_pids "$bundle" | head -1)"
        [ -n "$PID" ] && break
        sleep 0.25
    done
    [ -n "$PID" ] || _mac_app_failed "LaunchServices accepted the launch (open exited 0) and no
process from this bundle ever appeared. The app was started and did not stay up long enough to be
observed."

    # 4 — a window. A bound pid that vanishes while we wait IS the product: the app started and
    # died, and calling that an environment failure would hide a real launch crash.
    for ((tick = 0; tick < MAC_APP_WAIT_WINDOW_TICKS; tick++)); do
        if ! kill -0 "$PID" 2>/dev/null; then
            _mac_app_failed "the app started (pid $PID) and then exited before it drew a window."
        fi
        if "$axkit" winid "$PID" >/dev/null 2>&1; then
            # 5 — a real window is on screen. If the AX tree cannot be read from here it is the
            # grant or this harness, never the app.
            if "$axkit" dump "$PID" window >/dev/null 2>&1; then
                mac_app_settle_behind "$axkit" "$PID"
                return 0
            fi
            _mac_app_blocked "the app has a window on screen but its accessibility tree could not
be read. That is a permission or harness problem — grant Accessibility to the terminal running
this, in System Settings → Privacy & Security → Accessibility."
        fi
        sleep 0.25
    done
    _mac_app_failed "the app is running (pid $PID) and put no window on screen within
$((MAC_APP_WAIT_WINDOW_TICKS / 4)) seconds. The bound is stated because it is the claim being made:
this is 'no window inside the window we waited', not a proof that none would ever appear."
}
