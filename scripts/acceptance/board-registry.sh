#!/bin/bash
#
# The one reader of `BoardRegistry.installed`, sourced by every acceptance script that needs it.
#
# This file exists because the declaration has now broken its readers twice, in opposite directions,
# and both times the failure was silent-or-misleading rather than loud.
#
#   1. A `sed` *range* read from the declaration's `[` to the next `]` anywhere below it, sweeping in
#      three unrelated tokens and inflating the count.
#   2. `grep … | head -1 | sed -E 's/.*\[(.*)\].*/\1/'` read only the declaration's first line. That
#      was correct while the list fitted on one, and it was a few characters from lying. At seven
#      members the list is 124 characters against `.swiftformat`'s `--maxwidth 110`, so it wraps —
#      and every `head -1` reader then matched nothing. In `mac-shell.sh` that yielded a count of
#      zero and a **passing** gate reporting no installed boards; in `m2-activity.sh` and
#      `m5-discover.sh` it yielded `BLOCKED: the tree being tested does not install .activity` for a
#      board that has shipped and merged.
#
# Three copies of a reader is three chances for one of them to be wrong about the same fact, so
# there is one, here. It collects from the declaration's `[` to its matching `]`, however many lines
# that spans, and is indifferent to how the collection is wrapped.

# Prints the contents of the `installed` collection — the bare `.case` tokens, space separated.
# Prints nothing if the declaration cannot be found, which every caller must treat as a broken
# reader rather than as an empty set: `installed` has been non-empty since M2.
board_registry_installed() {
    awk '
        /installed: Set<Destination> *=/ { collecting = 1 }
        collecting                       { line = line " " $0 }
        collecting && /\]/               { exit }
        END {
            if (match(line, /\[[^]]*\]/)) print substr(line, RSTART + 1, RLENGTH - 2)
        }
    ' "$1"
}

# How many destinations are installed. Zero means the reader failed, never that no board shipped.
board_registry_installed_count() {
    board_registry_installed "$1" | grep -oE '\.[a-z][a-zA-Z]*' | wc -l | tr -d ' '
}

# Whether one destination is installed. Takes the bare case name without its dot, e.g. `evals`.
board_registry_installs() {
    local registry="$1" destination="$2"
    board_registry_installed "$registry" | grep -qE "\.${destination}\b"
}
