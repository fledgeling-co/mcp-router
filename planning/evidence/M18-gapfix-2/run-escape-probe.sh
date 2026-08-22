#!/usr/bin/env bash
# Runs `escape-shortcut-probe.swift` over every shape × key and prints the matrix.
#
# Six shapes × two keys = twelve runs at ~6s each. Each run opens a window and takes keyboard
# focus for its five seconds, because a posted key event only reaches the responder chain of a
# key window — that is the cost of measuring this rather than reading it.
#
# Results land in a scratch directory (default `$TMPDIR/escape-shortcut-probe`); the instrument is
# what is committed, and the table this prints is what gets pasted into the record.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${1:-${TMPDIR:-/tmp}escape-shortcut-probe}"
mkdir -p "$out"
rm -f "$out"/result-*.txt "$out"/state-*.txt

echo "building…"
swiftc -O "$here/escape-shortcut-probe.swift" -o "$out/probe"

shapes=(pre-m18 m18 stacked stacked-rev default-only exit-command hidden-cancel)
keys=(escape return)

for shape in "${shapes[@]}"; do
    for key in "${keys[@]}"; do
        # A wall-clock cap per run: the probe exits itself at t=5s, so 25s can only be reached by
        # a run that wedged, and one wedged cell must not take the matrix with it.
        perl -e 'alarm shift @ARGV; exec @ARGV' 25 \
            "$out/probe" "$shape" "$key" "$out" >/dev/null 2>&1 || true
        printf '  %-13s %-6s -> %s   (%s)\n' \
            "$shape" "$key" \
            "$(cat "$out/result-$shape-$key.txt" 2>/dev/null || echo 'NO RESULT FILE')" \
            "$(cat "$out/state-$shape-$key.txt" 2>/dev/null || echo 'no state')"
    done
done

echo
printf '| Shape | Cancel holds | Remove holds | Escape fires | Return fires |\n'
printf '|---|---|---|---|---|\n'
for shape in "${shapes[@]}"; do
    case "$shape" in
        pre-m18)      held='`.cancelAction`'; removed='—' ;;
        m18)          held='`.defaultAction`'; removed='`.cancelAction`' ;;
        stacked)      held='`.cancelAction` then `.defaultAction`'; removed='—' ;;
        stacked-rev)  held='`.defaultAction` then `.cancelAction`'; removed='—' ;;
        default-only) held='`.defaultAction`'; removed='—' ;;
        exit-command) held='`.defaultAction`, sheet has `.onExitCommand`'; removed='—' ;;
        hidden-cancel) held='`.defaultAction`, plus a hidden twin holding `.cancelAction`'; removed='—' ;;
    esac
    printf '| `%s` | %s | %s | **%s** | **%s** |\n' \
        "$shape" "$held" "$removed" \
        "$(cat "$out/result-$shape-escape.txt" 2>/dev/null || echo '?')" \
        "$(cat "$out/result-$shape-return.txt" 2>/dev/null || echo '?')"
done
