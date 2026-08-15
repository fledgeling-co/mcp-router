#!/bin/bash
# Tripwire: emit a line the moment a fleet-built app takes the foreground.
#
# The rule says the developer loop must be invisible — `open -g`, no `activate`, no
# `set frontmost to true`, AX-by-pid or proctor for driving. This is what proves the rule holds
# rather than assuming it. A rule nobody can observe being broken is a rule that gets broken.
#
# Reports only on the TRANSITION into foreground, so a legitimate one-off shows once rather than
# every poll. `lsappinfo front` is read-only and does not itself disturb focus.

WATCH='MCPRouter|Simulator'
prev=""
while true; do
    front=$(lsappinfo info -only name "$(lsappinfo front)" 2>/dev/null | sed 's/.*"LSDisplayName"="\([^"]*\)".*/\1/')
    if printf '%s' "$front" | grep -qE "$WATCH"; then
        [ "$front" != "$prev" ] && echo "FOREGROUND: '$front' came to the front — a fleet runner took the user's screen. Check its last osascript/open call for 'activate' or 'set frontmost to true'."
        prev="$front"
    else
        prev=""
    fi
    sleep 4
done
