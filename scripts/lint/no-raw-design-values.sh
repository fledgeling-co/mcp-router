#!/bin/bash
#
# Fails the build when a surface writes a raw design value instead of naming a token.
#
# This closes a hole the parity suite structurally cannot see. `DesignTokenParityTests` proves that
# `ColorToken` and `DESIGN.md` agree — but a view that writes `Color(.sRGB, red: 0.11, ...)` never
# touches `ColorToken`, so the one check that would have caught the value being wrong never looks at
# it. Drift does not have to go through the token to reach the screen; it only has to go around it.
#
# Two exemptions, by explicit path rather than by pattern: the colour and type binding files are
# where the tokens are turned into SwiftUI values, so a component and a size have to be written
# there and nowhere else. Naming them here rather than matching a wildcard is deliberate — an
# exemption you can read is an exemption someone can argue with.
#
# Exit 1 on a violation. There is no "warn" mode: a lint rule that only warns is a lint rule that
# gets ignored until it is deleted for being noisy.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

SCANNED=(
  "$ROOT/app/Sources/MCPRouterUI"
  "$ROOT/app/MCPRouter"
  "$ROOT/app/MCPRouterIOS"
)

# The only two files permitted to write a raw colour component or a raw size.
EXEMPT=(
  "app/Sources/MCPRouterUI/ColorToken+SwiftUI.swift"
  "app/Sources/MCPRouterUI/TypeToken+SwiftUI.swift"
)

is_exempt() {
  local rel="${1#"$ROOT"/}"
  for e in "${EXEMPT[@]}"; do
    [ "$rel" = "$e" ] && return 0
  done
  return 1
}

VIOLATIONS=0
report() {
  echo "  $1" >&2
  VIOLATIONS=$((VIOLATIONS + 1))
}

# Build the file list first. A `find` that matches nothing must not read as a clean pass — an
# emptied or renamed directory would otherwise report success forever, which is the same
# silently-green failure `make test`'s zero-test guard exists to stop.
FILES=()
for dir in "${SCANNED[@]}"; do
  [ -d "$dir" ] || { echo "error: $dir does not exist — nothing was scanned" >&2; exit 1; }
  while IFS= read -r f; do FILES+=("$f"); done < <(find "$dir" -name '*.swift' -type f)
done

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "error: no Swift files found under the scanned directories — the gate did not run" >&2
  exit 1
fi

echo "no-raw-design-values: scanning ${#FILES[@]} files"

for f in "${FILES[@]}"; do
  is_exempt "$f" && continue
  rel="${f#"$ROOT"/}"

  # A hex colour written into source. Anchored to a quoted string so a `#if DEBUG` or a doc
  # comment referencing a token name cannot trip it.
  while IFS= read -r hit; do
    report "$rel:$hit  — hex colour literal; name a ColorToken instead"
  done < <(grep -nE '"#[0-9A-Fa-f]{3,8}"' "$f" || true)

  # A colour constructed from components rather than from a token.
  while IFS= read -r hit; do
    report "$rel:$hit  — colour built from components; use ColorToken.color"
  done < <(grep -nE '(NSColor|UIColor)\(|Color\(\s*\.sRGB|Color\(red:' "$f" || true)

  # A numeric font size. `.system(size: someToken.size)` is fine; `.system(size: 16)` is not.
  while IFS= read -r hit; do
    report "$rel:$hit  — numeric font size; use .typeRole(_:) or TypeToken.font"
  done < <(grep -nE '\.system\(size:\s*[0-9]' "$f" || true)

  # A named SwiftUI colour. `Color.white` is a raw design value that never passes through a token,
  # so the parity suite cannot see it either — same hole as a hex literal, different spelling.
  # `Color.clear` is deliberately absent: transparency is a layout decision, not a palette one.
  while IFS= read -r hit; do
    report "$rel:$hit  — named SwiftUI colour; name a ColorToken instead"
  done < <(grep -nE '\bColor\.(white|black|red|green|blue|orange|yellow|purple|pink|gray|grey|primary|secondary)\b' "$f" || true)

  # The same thing in shorthand. `.foregroundStyle(.red)` is the form that actually gets written,
  # because it is shorter than the correct one.
  while IFS= read -r hit; do
    report "$rel:$hit  — shorthand system colour; name a ColorToken instead"
  done < <(grep -nE '(foregroundStyle|foregroundColor|fill|tint|stroke|strokeBorder|background)\(\s*\.(white|black|red|green|blue|orange|yellow|purple|pink|gray|grey|primary|secondary)\b' "$f" || true)

  # A system text style bypasses the eight-role ramp entirely. `.font(.title)` renders at whatever
  # size the OS picks, which is by definition off the ladder DESIGN.md specifies.
  while IFS= read -r hit; do
    report "$rel:$hit  — system text style; use .typeRole(_:) so the size stays on the ramp"
  done < <(grep -nE '\.font\(\s*\.(largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2)\b' "$f" || true)

  # `Font.custom(_:size:)` is the other route to an arbitrary size, and it also bundles a face —
  # DESIGN.md §2 is explicit that the stack is SF and never a bundled font.
  while IFS= read -r hit; do
    report "$rel:$hit  — Font.custom bypasses the ramp and the system face; use TypeToken"
  done < <(grep -nE '\.custom\([^)]*size:' "$f" || true)
done

# ------------------------------------------------------------------ the separation, and the bridge
#
# Two structural rules that no per-file pattern above can express.

# 1. `MCPRouterKit` must import no UI framework. The whole reason `MCPRouterUI` exists as a separate
#    product is that the router's own tests import the kit, and `SWIFT_PRACTICES.md` §8 requires it
#    to stay loadable without a UI stack. Nothing enforced that, so the separation could rot in one
#    commit and the only symptom would be a slower test run.
KIT="$ROOT/app/Sources/MCPRouterKit"
[ -d "$KIT" ] || { echo "error: $KIT does not exist — the separation check did not run" >&2; exit 1; }
while IFS= read -r hit; do
  report "${hit#"$ROOT"/}  — MCPRouterKit must import no UI framework (SWIFT_PRACTICES.md §8)"
done < <(grep -rnE '^\s*import\s+(SwiftUI|AppKit|UIKit)' "$KIT" || true)

# 2. Neither shell may carry its own colour bridge. F1 left a private
#    `extension ColorToken { var swiftUIColor }` in each app; this item's job was to delete both and
#    have them draw from the one shared binding. Deleting them is not the same as preventing them:
#    a shell that grows its own bridge again is two design systems, which is the failure the shared
#    product exists to rule out.
for shell in "$ROOT/app/MCPRouter" "$ROOT/app/MCPRouterIOS"; do
  [ -d "$shell" ] || { echo "error: $shell does not exist — the bridge check did not run" >&2; exit 1; }
  while IFS= read -r hit; do
    report "${hit#"$ROOT"/}  — private colour bridge in a shell; import MCPRouterUI instead"
  done < <(grep -rnE 'swiftUIColor|extension\s+ColorToken' "$shell" || true)
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo >&2
  echo "error: $VIOLATIONS raw design value(s) outside the two binding files." >&2
  echo "Read the value from ColorToken / TypeToken / MetricToken so DESIGN.md stays authoritative." >&2
  exit 1
fi

echo "no-raw-design-values: clean"
