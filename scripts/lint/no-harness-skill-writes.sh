#!/usr/bin/env bash
#
# F8 — nothing under app/Sources may write, link or relink another program's skills directory.
#
# `spec-R7.md` §7 drew this boundary for a harness's MCP configuration and
# `scripts/lint/no-harness-config-writes.sh` is the mechanical half of it. F8 reads a second kind of
# harness-owned tree — the skills directory — and extends the same refusal one kind further, rather
# than making an exception for the kind that happens to be easy to write.
#
# The reason it is a gate and not a paragraph is this repository's own history: a sentence saying
# the seam is inert is re-run by nothing, which is the failure class `D-p3-a` records.
#
# ## What is and is not refused, stated as what the script reads
#
#   1. a file whose CODE names a harness skills root — whole, or assembled from the harness home
#      plus the segment `skills` — and that also calls something in the mutating vocabulary.
#   2. a file inside the READ-ONLY SEAM that calls anything in that vocabulary, however the path
#      was obtained. The seam is the closed set of files whose whole job is reading somebody else's
#      tree, so a false positive there is answered by rewriting the code rather than by a
#      suppression comment, which this gate does not have.
#   3. a file that handles the seam's API — `SkillRootInventory`, `SkillRootLocation`,
#      `SkillRootReading` or `ProfileProjection` — and also writes.
#
# `DiskProfileStore` writes, deliberately and constantly: it owns `<router home>/profiles`, which is
# THIS router's disk. It is outside the seam, names no harness path and handles none of the seam's
# API, so it satisfies no rule here — which is the distinction this gate exists to draw, rather
# than "no Swift file may write".
#
# ## Why file-scoped, and why the vocabulary rather than the concept
#
# Both inherited from `no-harness-config-writes.sh`, and both were paid for there. A line-scoped
# rule refuses only what a careless refactor writes on ONE line, and a realistic applier asks for
# its target on one line and writes on a later one. And a refusal keyed on named routes cannot see
# a call it was not told about — so every alternative in the vocabulary is exercised by a planted
# subject in the selftest, and an alternative no subject matches is an instrument failure.
#
# WHAT THIS DOES NOT ESTABLISH. It is `grep`, not a call graph, and it does not prove no applier
# exists: one split across two neutrally-named files outside the seam satisfies no intersection and
# lives in no watched name. That limit is a case in the selftest so it shows up in a run rather
# than in a paragraph. The claim this gate carries is the one it can: no single file pairs a
# harness skills root with a write, and the seam mutates nothing at all.
#
# Exit codes:
#   0  nothing refused
#   1  at least one file refused, each named with the pair that refused it
#   2  the instrument could not run — no seam file found, or an empty vocabulary. A gate that
#      compared nothing is not a gate that passed.

set -uo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SOURCES="$REPO_ROOT/app/Sources"

[ -d "$SOURCES" ] || { echo "instrument: no $SOURCES to read"; exit 2; }

# The seam: the files whose whole job is reading somebody else's tree. Matched by BASENAME, so a
# move within app/Sources does not silently leave the seam.
SEAM_NAMES='SkillRootInventory.swift|SkillRootLocation.swift|ProfileProjection.swift|ProfileProjector.swift'

# A harness skills root, whole or assembled. `skills` alone is far too generic to be a path — this
# product has a `Skills` directory of its own — so it counts only where a harness home is named on
# the same line or the whole literal appears.
HARNESS_SKILL_PATH='\.claude/skills|\.cursor/skills|\.codex/skills|\.gemini/skills|\.config/opencode/skills|\.grok/skills|Application Support/Claude/skills'
HARNESS_HOME='\.claude|\.cursor|\.codex|\.gemini|\.grok|opencode'

# The mutating vocabulary. Deliberately wider than "write": a symlink, a hard link, a rename or a
# mode change REPLACES a directory of skills without ever writing to it, and that is the group no
# plant had named when the sibling gate was reviewed out of family.
VOCAB='createSymbolicLink|createDirectory|createFile|removeItem|moveItem|copyItem|replaceItem|linkItem|write\(to:|FileHandle\(forWriting|fopen\(|fputs\(|fwrite\(|Process\(|symlink\(|[^A-Za-z]link\(|unlink\(|rename\(|chmod\('

SEAM_API='SkillRootInventory|SkillRootLocation|SkillRootReading|ProfileProjection'

# Comments are not code. A `//` inside a string is not a comment and a `/*` inside a string does
# not open one — the sibling gate shipped a stripper that got both wrong in opposite directions, so
# this one tracks the string state, which is the rule Swift itself applies.
strip_comments() {
  python3 - "$1" <<'PY'
import sys
text = open(sys.argv[1], errors="replace").read()
out, i, n = [], 0, len(text)
in_string = in_line = in_block = False
while i < n:
    c = text[i]
    two = text[i:i + 2]
    if in_line:
        if c == "\n":
            in_line = False
            out.append(c)
        else:
            out.append(" ")
    elif in_block:
        if two == "*/":
            in_block = False
            out.append("  "); i += 2; continue
        out.append("\n" if c == "\n" else " ")
    elif in_string:
        out.append(c)
        if c == "\\" and i + 1 < n:
            out.append(text[i + 1]); i += 2; continue
        if c == '"':
            in_string = False
    else:
        if two == "//":
            in_line = True; out.append("  "); i += 2; continue
        if two == "/*":
            in_block = True; out.append("  "); i += 2; continue
        if c == '"':
            in_string = True
        out.append(c)
    i += 1
sys.stdout.write("".join(out))
PY
}

seam_files=0
findings=0
checked=0

while IFS= read -r file; do
  checked=$((checked + 1))
  code="$(strip_comments "$file")"

  writes=$(printf '%s' "$code" | grep -oE "$VOCAB" | sort -u | tr '\n' ' ')
  is_seam=0
  if printf '%s' "$(basename "$file")" | grep -qE "^($SEAM_NAMES)$"; then
    is_seam=1
    seam_files=$((seam_files + 1))
  fi

  names_path=0
  if printf '%s' "$code" | grep -qE "$HARNESS_SKILL_PATH"; then
    names_path=1
  elif printf '%s' "$code" | grep -qE "$HARNESS_HOME" \
    && printf '%s' "$code" | grep -qE '"skills"|"skills-cursor"'; then
    names_path=1
  fi

  uses_api=0
  printf '%s' "$code" | grep -qE "$SEAM_API" && uses_api=1

  if [ -n "$writes" ]; then
    if [ "$is_seam" -eq 1 ]; then
      echo "refused (rule 2, the read-only seam): ${file#"$REPO_ROOT"/} calls: $writes"
      findings=$((findings + 1))
    elif [ "$names_path" -eq 1 ]; then
      echo "refused (rule 1, a harness skills root and a write): ${file#"$REPO_ROOT"/} calls: $writes"
      findings=$((findings + 1))
    elif [ "$uses_api" -eq 1 ]; then
      echo "refused (rule 3, the seam's API and a write): ${file#"$REPO_ROOT"/} calls: $writes"
      findings=$((findings + 1))
    fi
  fi
done < <(find "$SOURCES" -name '*.swift' -type f | sort)

if [ "$checked" -eq 0 ]; then
  echo "instrument: no Swift file was read, so nothing was compared"
  exit 2
fi
if [ "$seam_files" -eq 0 ]; then
  echo "instrument: the read-only seam matched no file — rule 2 compared nothing"
  echo "            expected basenames: $SEAM_NAMES"
  exit 2
fi

echo "no-harness-skill-writes: $checked file(s) read, $seam_files in the seam, $findings refused"
[ "$findings" -eq 0 ] || exit 1
exit 0
