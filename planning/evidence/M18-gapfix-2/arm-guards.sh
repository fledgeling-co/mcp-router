#!/usr/bin/env bash
# Breaks each guard this gap-fix added, one at a time, and requires the named test to go red.
#
# `SWIFT_PRACTICES.md` §7: a guard nobody has seen fail is a guard nobody has seen. Every arm below
# mutates the *product* (or the design of record, which is an input), runs one filtered suite,
# restores from `HEAD`, and proves the restore with `git diff --quiet` — the discipline `G4`'s
# twentieth instance exists for, where a measurement's side effect on the tree was never undone.
#
# Committed rather than run from /tmp, for `G6`'s reason: this is what makes "the guards were seen
# to fail" a claim someone can re-run.
#
# Usage: `planning/evidence/M18-gapfix-2/arm-guards.sh` from the repository root. Exits nonzero if
# any arm stayed green, or if the tree is not clean at the end.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../../.." || exit 2
[ -f DESIGN.md ] || { echo "not at the repository root"; exit 2; }

if ! git diff --quiet; then
    echo "the tree has uncommitted changes; every arm restores from HEAD and would discard them"
    exit 2
fi

failures=0

# mutate <file> <python-replacement-expression-safe-old> <new> — a literal string replace.
mutate() {
    python3 - "$1" "$2" "$3" <<'PY'
import pathlib, sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path)
s = p.read_text()
if old not in s:
    sys.exit(f"anchor not present in {path}: {old[:60]!r}")
p.write_text(s.replace(old, new, 1))
PY
}

arm() {
    local label="$1" file="$2" old="$3" new="$4" filter="$5"
    printf '%-58s ' "$label"
    if ! mutate "$file" "$old" "$new"; then
        echo "ANCHOR MISSING — arm could not be applied"
        failures=$((failures + 1))
        return
    fi
    local out exit_code
    out=$(swift test --package-path app --filter "$filter" 2>&1)
    exit_code=$?
    git checkout -- "$file"
    if ! git diff --quiet; then
        echo "RESTORE FAILED — the tree is dirty after this arm"
        failures=$((failures + 1))
        return
    fi
    if [ "$exit_code" -eq 0 ]; then
        echo "STILL GREEN — the guard does not bite"
        failures=$((failures + 1))
    else
        echo "red: $(printf '%s\n' "$out" | grep -c 'recorded an issue') issue line(s)"
    fi
}

# 1 — the blocker itself, put back.
arm "cancelAction back onto the destructive Remove" \
    app/Sources/MCPRouterUI/Boards/CleanupSheets.swift \
    '                    .buttonStyle(StandardButtonStyle())
                    .disabled(candidate == nil)' \
    '                    .buttonStyle(StandardButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .disabled(candidate == nil)' \
    'SheetShortcutGuardTests'

# 2 — the pair SwiftUI silently reduces to one.
arm "both shortcuts stacked on one control" \
    app/Sources/MCPRouterUI/Boards/CleanupSheets.swift \
    '                        .keyboardShortcut(.cancelAction)
                    Button("Remove", role: .destructive) {' \
    '                        .keyboardShortcut(.cancelAction)
                        .keyboardShortcut(.defaultAction)
                    Button("Remove", role: .destructive) {' \
    'SheetShortcutGuardTests'

# 3 — a sheet M18 drew, back to having no Escape path.
arm "OfficialMarkSheet back to defaultAction only" \
    app/Sources/MCPRouterUI/Boards/OfficialMarkSheet.swift \
    'Button(OfficialMarkCopy.dismiss) { board.sheet = nil }
                    .buttonStyle(ProminentButtonStyle())
                    .keyboardShortcut(.cancelAction)' \
    'Button(OfficialMarkCopy.dismiss) { board.sheet = nil }
                    .buttonStyle(ProminentButtonStyle())
                    .keyboardShortcut(.defaultAction)' \
    'SheetShortcutGuardTests'

# 4 — a sixteenth sheet nobody classified.
arm "an unclassified sheet added to the population" \
    app/Sources/MCPRouterUI/Boards/OfficialMarkSheet.swift \
    '    /// Where the router'"'"'s children look for their binaries' \
    '    struct ArmProbeSheet: View {
        var body: some View { Text(verbatim: "arm") }
    }

    /// Where the router'"'"'s children look for their binaries' \
    'SheetShortcutGuardTests'

# 5 — the scanner blinded, which would take every guard above with it.
#
# The anchor moved in gap-fix 3: `stripped` was split into `withoutComment` (literals kept, for the
# label) and `withoutLiterals` (for the brace counting). Shadowing the parameter empties every line
# read, which is the same blinding as before at the new seam.
arm "the scanner made to read nothing" \
    app/Tests/MCPRouterUITests/SheetShortcutScan.swift \
    '        static func withoutComment(_ line: String) -> String {
            var inString = false' \
    '        static func withoutComment(_ line: String) -> String {
            let line = ""
            var inString = false' \
    'SheetShortcutGuardTests'

# 6 — the destructive fill back to the one the mock does not draw.
arm "the destructive button filled again" \
    app/Sources/MCPRouterUI/Controls.swift \
    '        if role == .destructive { return isPressed ? .f1 : nil }' \
    '        if role == .destructive { return isPressed ? .f1 : .raised }' \
    'ButtonPaletteTests|MockButtonFidelityTests'

# 7 — the design of record made to draw a disabled primary, which is the input rather than the code.
arm "a disabled primary planted in the mock" \
    design/mcp-router-console.html \
    'class="btn primary"' \
    'class="btn primary disabled"' \
    'MockButtonFidelityTests'

# 8 — the mock's destructive rule given a fill, so the claim the style rests on stops holding.
arm "the mock's destructive rule given a background" \
    design/mcp-router-console.html \
    '.btn.destructive{color:var(--fail-ink);background:none;box-shadow:none;}' \
    '.btn.destructive{color:var(--fail-ink);background:var(--raised);box-shadow:none;}' \
    'MockButtonFidelityTests'

# --- gap-fix 3: which control takes the accent fill -------------------------------------------
#
# One mutation per property. Arms 9 and 10 are the two sites separately, because a single arm going
# red would prove the guard covers *one* of them; 11 and 12 blind the two readers the Cancel guards
# stand on, since an absence check whose reader has stopped reading returns the same clean answer a
# conforming tree does.

# 9 — the site M18 introduced at `4c320a8`, filled again.
arm "RemoveServerSheet's Cancel filled again" \
    app/Sources/MCPRouterUI/Boards/CleanupSheets.swift \
    '                    Button("Cancel") { board.sheet = nil }
                        .buttonStyle(StandardButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Remove", role: .destructive) {' \
    '                    Button("Cancel") { board.sheet = nil }
                        .buttonStyle(ProminentButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Remove", role: .destructive) {' \
    'SheetShortcutGuardTests'

# 10 — the sibling site, which came from `589ab2e` and predates M18.
arm "RemoveServerDialog's Cancel filled again" \
    app/Sources/MCPRouterUI/Boards/ServerSheets.swift \
    '                Button("Cancel") { board.sheet = nil }
                    .buttonStyle(StandardButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button("Remove", role: .destructive) {' \
    '                Button("Cancel") { board.sheet = nil }
                    .buttonStyle(ProminentButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button("Remove", role: .destructive) {' \
    'SheetShortcutGuardTests'

# 11 — the label reader made to match nothing, so every control reads as unlabelled.
arm "the label reader made to read nothing" \
    app/Tests/MCPRouterUITests/SheetShortcutScan.swift \
    '                guard let opening = rawDeclaration.range(of: "Button(") else { return "" }' \
    '                guard let opening = rawDeclaration.range(of: "ZZNeverMatches(") else { return "" }' \
    'SheetShortcutGuardTests'

# 12 — the style reader made to match nothing, so no control carries a style.
arm "the style reader made to read nothing" \
    app/Tests/MCPRouterUITests/SheetShortcutScan.swift \
    '                    guard var style = firstArgument(of: "buttonStyle(", in: modifier) else { return nil }' \
    '                    guard var style = firstArgument(of: "ZZNeverMatches(", in: modifier) else { return nil }' \
    'SheetShortcutGuardTests'

echo
if ! git diff --quiet || [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "the tree is NOT clean after arming — see git status"
    git status --short
    exit 1
fi
echo "tree clean after every arm (git diff --quiet, git status clean of tracked changes)"
[ "$failures" -eq 0 ] && echo "all arms bit" || echo "$failures arm(s) did not bite"
exit "$failures"
