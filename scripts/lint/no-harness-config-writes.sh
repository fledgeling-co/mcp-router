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
# ## Why the rules are file-scoped
#
# They were line-scoped, and a line-scoped rule refuses only what a careless refactor would write
# on ONE line. A verifier planted three appliers: a path literal beside a write on one line was
# caught, `ReconciliationPlan(...)` beside a write on one line was caught, and **a realistic
# applier** — asking for the target path on one line and writing it on a later line — walked
# through and the gate reported `none writes one`. A gate that passes a realistic applier is worse
# than no gate, because ORCHESTRATOR.md cites this file as the reason the refusal holds. The pair
# is now looked for per FILE, which is the unit a person writes an applier in.
#
# ## Three refusals
#
#   1. a file that names a harness config path in CODE and also writes a file
#   2. a file that uses R7's reconciliation API — `ReconciliationPlan`, `HarnessReport`, or the
#      `ClientConfigs` calls that hand out a harness path — and also writes a file
#   3. any file write at all inside the seam — `RouterCore/Discovery`, `HarnessesVerb.swift`, and
#      any file named `Harness*`, `Reconciliation*` or `ClientConfig*` anywhere under app/Sources —
#      however the path was obtained. Rules 1 and 2 need a recognisable token; this one does not,
#      so an applier taking a bare `String` path is still refused where one would actually live.
#
# ## What this gate does NOT check, said plainly rather than left to be discovered
#
# It is `grep`, not a call graph, and **it does not establish that no applier exists**. An applier
# split across two neutrally-named files outside the seam — one asking `ClientConfigs.path(for:)`
# for the target, another taking a `String` and writing it — satisfies no intersection and lives in
# no watched name, and this gate exits 0 on it. That is registered as `D-r7-m`, and the closed-world
# fix is named there: census the whole set of writing files against a declared allowlist. Until
# somebody takes that trade, the honest claim is the one this gate can carry — no single file pairs
# a harness path or a reconciliation plan with a write, and the seam writes nothing at all. Anything
# stronger is prose. The plants in `no-harness-config-writes-selftest.sh` are the population this
# gate is proven against, and the split-file case is kept there as a declared blind spot rather than
# left for the next verifier to find.
#
# `~/.claude.json` is written on purpose by `install-entry` and `watch`, which is pre-existing,
# parity-locked product behaviour (`ClaudeStagingEntry`, `WatchBackup`). Those files carry no
# harness path literal in code and no reconciliation API, so they are outside all three rules — the
# gate is about R7's seam, not about revoking a subsystem that shipped before it.
#
# The router's OWN config is not a harness config and is not matched: `servers.json` is this
# product's file and `ConfigWriter`/`ImportConfigWriter` are supposed to write it.
#
# Exit codes: 0 nothing writes one · 1 something does · 2 the gate could not run.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCES="${1:-$REPO_ROOT/app/Sources}"
FAILURES=0

[ -d "$SOURCES" ] || { echo "no-harness-config-writes: $SOURCES does not exist"; exit 2; }

# The write vocabulary is **argument labels** rather than whole call spellings, because
# `FileHandle(forWritingTo:)` and `FileHandle.init(forWritingTo:)` are the same call and a token
# anchored on the type name only matches one of them. A label like `forWritingTo:` appears in
# nothing but a writing constructor, and it matches every spelling and every wrapper around it.
#
# The harness config files R7 reads, by their distinguishing path fragment.
HARNESS_PATHS='\.claude\.json|claude_desktop_config\.json|\.codex/config\.toml|\.chatgpt/config\.toml|\.cursor/mcp\.json|\.gemini/settings\.json|\.grok/config\.toml|opencode/opencode\.json'

# R7's own API. A file holding any of these is handling a harness config or a plan for one, and a
# write in the same file is the applier spec §7 says must not exist.
R7_API='ReconciliationPlan|HarnessReport|ClientConfigs\.path\(for:|ClientConfigs\.inventory\(|ClientConfigs\.discover\('

WRITING='writeFile|createFile|write\(to:|write\(toFile:|removeItem|moveItem|copyItem|forWritingTo:|forWritingAtPath|forUpdatingTo:|forUpdatingAtPath|toFileAtPath:|OutputStream\(|replaceItem\(at:|\.write\(|contentsOfFile:.*write|/bin/cp|/bin/mv|/usr/bin/tee'

# `.write(` also matches writing to a standard stream, which is printing rather than writing a
# config. Excluded so that `Out.print` does not make every verb a finding — which is the kind of
# noise that gets a gate deleted.
NOT_A_FILE_WRITE='FileHandle\.standard(Output|Error)'

# The seam: R7's own subsystem, plus any file whose NAME says it handles harnesses. The name
# clause is what catches a `HarnessCoordinator.swift` written next door to the engine rather than
# inside it — the shape a split applier takes when somebody is only half avoiding this gate.
SEAM_DIRS=("$SOURCES/RouterCore/Discovery")
SEAM_NAMES=('Harness*.swift' 'Reconciliation*.swift' 'ClientConfig*.swift')
SEAM_FILES_EXTRA=("$SOURCES/MCPRouterCLI/HarnessesVerb.swift")

report() {
  echo "no-harness-config-writes: $1"
  FAILURES=$((FAILURES + 1))
}

# Every line in $1 that writes a FILE. Empty when the file only prints.
#
# The printing construct is **neutralised in the line** rather than the line being dropped. Dropping
# it let `try data.write(to: target) // FileHandle.standardOutput` erase itself from the gate with a
# trailing comment — both out-of-family reviewers found that one independently. Rewriting only the
# head of the call leaves any real write on the same line still matching.
#
# Written as a capture-and-test rather than `grep -q`, because BSD `grep -qv` exits 0 on empty
# input: `grep -E pattern file | grep -qvE other` reports a match for a file with no matches at
# all, which would have made all three rules fire on all 313 sources.
file_writes() {
  code_lines "$1" \
    | grep -nE "$WRITING" \
    | sed -E "s/$NOT_A_FILE_WRITE\.write\(/PRINTS(/g" \
    | grep -E "$WRITING"
}

# The file with its comments removed. A harness path in a doc comment is documentation; several
# files under `app/Sources` discuss `~/.claude.json` in prose and write something unrelated, and
# reading those as findings is how a gate stops being run. Whole-line `//`, `///`, and the three
# shapes a block comment takes are all removed — `app/Sources` contains one real `/* … */` block,
# so the block case is measured rather than hypothetical.
# Comment lines are **blanked, not deleted**, so `grep -n` downstream still reports the line number
# a person would open the file at.
code_lines() {
  sed -E 's#^[[:space:]]*(//|/\*|\*/|\*[^/]).*$##' "$1" 2>/dev/null
}

code_of() {
  code_lines "$1"
}

# ------------------------------------------------------------------ pattern integrity
# A gate whose patterns have been gutted passes everything and says so in the same words as a gate
# that examined everything. Each pattern is proven against a string it is supposed to match before
# any file is read, so an edit that empties one is a failure here rather than a silent green.
probe() {
  printf '%s\n' "$2" | grep -qE "$1" || {
    echo "no-harness-config-writes: this gate's own pattern no longer matches what it describes."
    echo "  pattern: $1"
    echo "  subject: $2"
    exit 2
  }
}
probe "$WRITING"           'try rewritten.write(toFile: target, atomically: true, encoding: .utf8)'
probe "$WRITING"           'let handle = try FileHandle(forWritingTo: url)'
probe "$WRITING"           'let stream = OutputStream(toFileAtPath: target, append: false)'
probe "$WRITING"           'try manager.replaceItem(at: url, withItemAt: staged)'
probe "$WRITING"           'let handle = try FileHandle(forUpdatingTo: url)'
probe "$WRITING"           'let stream = OutputStream(url: target, append: false)'
probe "$HARNESS_PATHS"     'let path = home.appendingPathComponent(".gemini/settings.json")'
probe "$R7_API"            'func apply(_ plan: ReconciliationPlan, to target: String) throws {'
probe "$R7_API"            'let target = ClientConfigs.path(for: client, homeDirectory: home)'
probe "$NOT_A_FILE_WRITE"  'FileHandle.standardOutput.write(Data(text.utf8))'

# ------------------------------------------------------------------ rules 1 and 2
EXAMINED=0
NAMING=0
WRITERS=0
while IFS= read -r file; do
  EXAMINED=$((EXAMINED + 1))
  writes="$(file_writes "$file")"
  [ -n "$writes" ] && WRITERS=$((WRITERS + 1))
  # Captured first, then matched against with a here-string. `code_of "$file" | grep -q …` is a
  # producer piped into an early-exiting consumer: under `pipefail` a SIGPIPE on the producer makes
  # the whole pipeline non-zero, so a large file with an early harness literal could silently stop
  # being a finding.
  code="$(code_of "$file")"
  names_path=""
  if grep -qE "$HARNESS_PATHS" <<< "$code"; then
    names_path="yes"
    NAMING=$((NAMING + 1))
  fi
  [ -n "$writes" ] || continue

  if [ -n "$names_path" ]; then
    report "$file names a harness config path and writes a file:"
    printf '%s\n' "$writes" | sed 's/^/    /'
  fi
  if grep -qE "$R7_API" <<< "$code"; then
    report "$file handles a reconciliation plan or a harness path, and writes a file:"
    printf '%s\n' "$writes" | sed 's/^/    /'
  fi
done < <(find "$SOURCES" -name '*.swift' -type f | sort)

# ------------------------------------------------------------------ rule 3: the seam is write-free
SEAM_EXAMINED=0
SEAM_LIST=()
SEAM_UNIQUE=()
for dir in "${SEAM_DIRS[@]}"; do
  [ -d "$dir" ] || continue
  while IFS= read -r file; do SEAM_LIST+=("$file"); done \
    < <(find "$dir" -name '*.swift' -type f)
done
for pattern in "${SEAM_NAMES[@]}"; do
  while IFS= read -r file; do SEAM_LIST+=("$file"); done \
    < <(find "$SOURCES" -name "$pattern" -type f)
done
for file in "${SEAM_FILES_EXTRA[@]}"; do
  [ -f "$file" ] && SEAM_LIST+=("$file")
done
# One file can arrive by more than one route — `ClientConfigs.swift` is in the directory and matches
# a name — and reporting it twice would double a finding's count.
if [ "${#SEAM_LIST[@]}" -gt 0 ]; then
  while IFS= read -r file; do SEAM_UNIQUE+=("$file"); done \
    < <(printf '%s\n' "${SEAM_LIST[@]}" | sort -u)
fi
for file in ${SEAM_UNIQUE+"${SEAM_UNIQUE[@]}"}; do
  SEAM_EXAMINED=$((SEAM_EXAMINED + 1))
  writes="$(file_writes "$file")"
  [ -n "$writes" ] || continue
  report "$file is inside R7's seam, which writes nothing at all:"
  printf '%s\n' "$writes" | sed 's/^/    /'
done

# ------------------------------------------------------------------ anti-vacuity
# The gate must be able to see something, or a renamed directory turns it into a no-op that
# reports success. It is the same failure this file exists to refuse, one level up.
if [ "$NAMING" -eq 0 ]; then
  echo "no-harness-config-writes: found no file naming a harness config path at all."
  echo "  Either the paths moved or this gate is pointed at the wrong tree; a gate that"
  echo "  examines nothing reports the same success as one that examined everything."
  exit 2
fi
if [ "$SEAM_EXAMINED" -eq 0 ]; then
  echo "no-harness-config-writes: rule 3 found no seam files under $SOURCES."
  echo "  RouterCore/Discovery and HarnessesVerb.swift are where an applier would live."
  echo "  If they moved, move this gate with them rather than letting it pass on an empty set."
  exit 2
fi

if [ "$FAILURES" -eq 0 ]; then
  echo "no-harness-config-writes: $EXAMINED file(s) examined, $NAMING name a harness config," \
       "$WRITERS write a file, $SEAM_EXAMINED in the seam — none writes one"
  exit 0
fi
exit 1
