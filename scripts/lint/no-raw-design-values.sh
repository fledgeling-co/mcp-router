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
  #
  # Every SwiftUI `Color` initializer that takes raw numbers or a foreign colour value, not just
  # the two spellings this first caught. Measured 21 Aug 2026 under M23: `Color(white: 0.5)`,
  # `Color(hue:saturation:brightness:)` and `Color(.displayP3, red:green:blue:)` all passed this
  # lint clean while the M23 spec claimed component-constructed colours were caught. A rule whose
  # gaps are invisible is the "green report from a blind instrument" the conversion contract is
  # written against, one level down. `scripts/lint/no-raw-design-values-selftest.sh` now arms every
  # spelling listed here, so a future narrowing goes red instead of going quiet.
  while IFS= read -r hit; do
    report "$rel:$hit  — colour built from components; use ColorToken.color"
  done < <(grep -nE '(NSColor|UIColor)\(|Color\(\s*\.(sRGB|sRGBLinear|displayP3|p3)\b|Color\(\s*(red|white|hue|cgColor|nsColor|uiColor|platformColor):' "$f" || true)

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

# ------------------------------------------------------------------ the shell's own two rules
#
# Scoped to the files M1 added, so no merged gate changes meaning for code that was reviewed under
# the old rules. Both are things the checks above structurally cannot see.

# The geometry rule was scoped to the shell when only the shell existed. A board draws far more
# geometry than the shell does — column widths, row heights, a skeleton that has to match the row it
# stands in for — so a board outside this list is the largest unguarded surface in the app. Each
# board directory joins as it ships.
#
# M15's Settings window joins for a reason worth stating: without this line the geometry rule and
# A36's one-channel rule would have SILENTLY STOPPED applying to code that was under them the day
# before. `SettingsBoard.swift` lived in `Boards/`, which is listed; the window that replaces it
# lives in a directory that was not. The `[ -d "$dir" ]` guard below only fires for a *listed*
# directory that is missing, so a directory nobody listed is invisible to it. The comment above
# already said "each board directory joins as it ships"; this is that, and the file count printed
# below is what proves the directory was scanned rather than merely named.
# M19's document viewer joins for the reason M15's Settings window did, and it is worth restating
# because the failure is silent in both directions: the `[ -d "$dir" ]` guard below fires for a
# LISTED directory that is missing, so a directory nobody listed is invisible to it. A new UI
# directory that is not here is simply outside the geometry rule and outside A36, and nothing says
# so. The file count printed below is what proves it was scanned rather than merely named.
GEOMETRY_DIRS=(
  "$ROOT/app/Sources/MCPRouterUI/Shell"
  "$ROOT/app/Sources/MCPRouterUI/Activity"
  "$ROOT/app/Sources/MCPRouterUI/Boards"
  "$ROOT/app/Sources/MCPRouterUI/Settings"
  "$ROOT/app/Sources/MCPRouterUI/Document"
)

# M3 brings the boards under the same two rules. They were scoped to the shell so that a merged gate
# would not change meaning for already-reviewed code — that reason does not apply to a directory this
# item created, and a board is the surface most likely to reach for a raw frame height or a second
# channel, because it is the one with data to draw.

SHELL_FILES=()
for dir in "${GEOMETRY_DIRS[@]}"; do
  [ -d "$dir" ] || { echo "error: $dir does not exist — the geometry checks did not run" >&2; exit 1; }
  while IFS= read -r f; do SHELL_FILES+=("$f"); done < <(find "$dir" -name '*.swift' -type f)
done
[ "${#SHELL_FILES[@]}" -gt 0 ] || { echo "error: no Swift files under the geometry directories — the checks did not run" >&2; exit 1; }

echo "no-raw-design-values: $(printf '%s\n' "${SHELL_FILES[@]}" | wc -l | tr -d ' ') files under the geometry and boundary rules"

for f in "${SHELL_FILES[@]}"; do
  rel="${f#"$ROOT"/}"

  # 1. A geometry literal. The checks above catch a colour and a font size; they say nothing about
  #    `.frame(height: 24)` or `cornerRadius: 8`, which are design values that reach the screen
  #    without ever passing through MetricToken — the same hole a hex literal opens, spelled in
  #    numbers. Zero is deliberately allowed: `spacing: 0` is the *absence* of a gap rather than a
  #    value picked from the document, and forbidding it would push code into naming a token that
  #    means nothing.
  while IFS= read -r hit; do
    report "$rel:$hit  — geometry literal; read the value from MetricToken"
  done < <(grep -nE '(\.frame\((width|height|minWidth|minHeight|maxWidth|maxHeight): *[1-9])|(\.padding\( *[1-9])|(cornerRadius: *[1-9])|(lineWidth: *[1-9])|(spacing: *[1-9])|(radius: *[1-9])' "$f" || true)

  # 2. The boundary — A36. The Mac app talks to the router ONLY over the loopback control API, and
  #    that is what lets the router be swapped underneath without the app changing. A dependency
  #    graph cannot see a direct call: `MCPRouterUI` legitimately links Foundation, so `URLSession`
  #    is always in scope and always one line away. A source grep is the only check that reaches it.
  #
  #    **Reading a file is one of the ways past the API, and this list did not say so.** The set was
  #    sockets and processes plus a bare `FileManager`, which a completeness critic pointed out
  #    leaves `Data(contentsOf:)`, `Bundle` and `URL(fileURLWithPath:)` — the spelling an actual
  #    fixture reader uses — entirely unnamed. A18 and §6 turn on where a number came from, so a
  #    shell that reads its own JSON is exactly the failure the clause is about.
  while IFS= read -r hit; do
    report "$rel:$hit  — the shell reaches past the control API; only F3's client may (A36)"
  done < <(grep -nE '\b(URLSession|NSTask|NWConnection|NWListener|CFSocket|Bundle)\b|\bProcess\(|\bFileManager\b|\bsocket\(|Data\(contentsOf:|URL\(fileURLWithPath:|contentsOfFile:' "$f" || true)
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
