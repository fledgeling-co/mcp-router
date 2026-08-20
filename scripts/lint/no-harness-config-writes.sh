#!/usr/bin/env bash
#
# R7 — nothing under app/Sources may open another application's MCP configuration for writing.
#
# The seam this guards is deliberately empty. `ReconciliationPlan` names every entry a fix would
# remove and renders a diff, and nothing applies it: there is no `apply`, no writer protocol and no
# conformer. `planning/specs/spec-R7.md` §7 carries the two reasons, and only the first is about
# safety — mutating a developer's live agent configuration is not a change a fleet runner makes
# unattended, and the brief's own framing is that config *writing* is the easy half.
#
# A paragraph saying so is re-run by nothing, which is a failure class this repository has already
# paid for twice (D-p3-a). This is the mechanical version.
#
# Two things are refused, and the second is the one a careless refactor produces:
#   * a harness config path paired with a writing call on the same line
#   * any use of `ReconciliationPlan` alongside a write, anywhere under app/Sources
#
# The router's OWN config is not a harness config and is not matched: `servers.json` is this
# product's file and `ConfigWriter`/`ImportConfigWriter` are supposed to write it.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCES="${1:-$REPO_ROOT/app/Sources}"
FAILURES=0

[ -d "$SOURCES" ] || { echo "no-harness-config-writes: $SOURCES does not exist"; exit 2; }

# The harness config files R7 reads, by their distinguishing path fragment.
HARNESS_PATHS='\.claude\.json|claude_desktop_config\.json|\.codex/config\.toml|\.chatgpt/config\.toml|\.cursor/mcp\.json|\.gemini/settings\.json|\.grok/config\.toml|opencode/opencode\.json'
WRITING='writeFile|createFile|write\(to:|removeItem|moveItem|copyItem|FileHandle\(forWritingAtPath|\.write\(|contentsOfFile:.*write'

report() {
  echo "no-harness-config-writes: $1"
  FAILURES=$((FAILURES + 1))
}

while IFS= read -r hit; do
  # `ImportPaths` and `ClientConfigs` name these paths; naming one is reading, and only a naming
  # that sits beside a write is a finding.
  report "a harness config path appears beside a write: $hit"
done < <(grep -rnE "($HARNESS_PATHS)" --include='*.swift' "$SOURCES" 2>/dev/null \
         | grep -E "($WRITING)" || true)

while IFS= read -r hit; do
  report "ReconciliationPlan appears beside a write, and nothing may apply it: $hit"
done < <(grep -rnE 'ReconciliationPlan' --include='*.swift' "$SOURCES" 2>/dev/null \
         | grep -E "($WRITING)" || true)

# The gate must be able to see something, or a renamed directory turns it into a no-op that
# reports success. It is the same failure this file exists to refuse, one level up.
FOUND="$(grep -rlE "($HARNESS_PATHS)" --include='*.swift' "$SOURCES" 2>/dev/null | wc -l | tr -d ' ')"
if [ "$FOUND" -eq 0 ]; then
  echo "no-harness-config-writes: found no file naming a harness config path at all."
  echo "  Either the paths moved or this gate is pointed at the wrong tree; a gate that"
  echo "  examines nothing reports the same success as one that examined everything."
  exit 2
fi

if [ "$FAILURES" -eq 0 ]; then
  echo "no-harness-config-writes: $FOUND file(s) name a harness config, none writes one"
  exit 0
fi
exit 1
