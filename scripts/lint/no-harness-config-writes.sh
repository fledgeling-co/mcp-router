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
# ## Three refusals, each stated as what it actually reads
#
#   1. a file whose CODE names a harness config path — whole, or by the file name a path is
#      assembled from, with the three names that are not distinctive (`settings.json`,
#      `config.toml`, `mcp.json`) counting only where a harness home is named too — and that also
#      writes a file
#   2. a file that uses R7's reconciliation API — `ReconciliationPlan`, `HarnessReport`, or the
#      `ClientConfigs` calls that hand out a harness path, matched across a line wrap — and that
#      also writes a file
#   3. inside the seam — `RouterCore/Discovery`, `HarnessesVerb.swift`, and any file named
#      `Harness*`, `Reconciliation*` or `ClientConfig*` anywhere under app/Sources — **any call in
#      the mutating vocabulary below, however the path was obtained**. Rules 1 and 2 need a
#      recognisable token; this one does not, so an applier taking a bare `String` path is refused
#      where one would actually live. Its vocabulary is deliberately wider than theirs, because the
#      seam is a closed set of files: it carries the C stdio calls in both their Foundation and
#      POSIX spellings, a subprocess at all, and the calls that replace a config without writing to
#      it — a symlink, a hard link, a mode change. Two of its entries refuse more than writing, and
#      the note above `SEAM_MUTATING` says which and why.
#
# ## What this gate does NOT check, said plainly rather than left to be discovered
#
# It is `grep`, not a call graph. Three limits, and each has a case in
# `no-harness-config-writes-selftest.sh` so it shows up in a run rather than only in this paragraph.
#
#   * **It does not establish that no applier exists.** An applier split across two neutrally-named
#     files outside the seam — one asking `ClientConfigs.path(for:)` for the target, another taking
#     a `String` and writing it — satisfies no intersection and lives in no watched name, and this
#     gate exits 0 on it. That is `D-r7-m`, asserted as a miss at `P10`. The closed-world fix is
#     named there: census the whole set of writing files against a declared allowlist.
#   * **Rule 3 refuses a vocabulary, not the concept of writing.** Every alternative in it is
#     required to be exercised by one of the probe subjects below — mechanically, by splitting the
#     pattern on `|` and failing the gate at exit 2 for any alternative no subject matches — so the
#     claim is checked rather than made. The five walk-throughs a verifier found are kept as cases.
#     A spelling nobody has thought of is still a spelling nobody has thought of.
#   * **Rules 1 and 2 are open-world and stay narrow on purpose.** A file that reaches a harness
#     path through a value passed in from somewhere else, and that lives outside the seam, is not a
#     finding here. Widening them to every write in the tree is the same trade `D-r7-m` names.
#
#   4. **a file that writes AND speaks the client vocabulary must be DECLARED** — the rule R32
#      added, and the one that keeps the three above honest now that a second harness writer
#      exists.
#
# ## Rule 4, and why prose was no longer enough
#
# Until R32 this file's exception for the writers that are *supposed* to exist lived in the
# paragraph below, and a paragraph is re-run by nothing. `~/.claude.json` is written on purpose by
# `install-entry` and `watch` (`ClaudeStagingEntry`, `WatchBackup`); R32 adds a second, deliberate,
# user-invoked writer for Claude Desktop (`DesktopEntryWriter`). Two intentional writers with their
# only description in a comment is the shape this repository has already paid for twice: the next
# reader cannot tell an intended writer from one that arrived, and neither can this gate.
#
# So the exception is now a LIST. `HARNESS_WRITERS` names each file permitted to write another
# application's MCP configuration, and rule 4 checks the list in both directions:
#
#   * every declared writer still exists and **still writes** — a row whose file has gone, or whose
#     write has been refactored out, is a finding rather than a comfortable no-op; and
#   * every file that writes AND names the client vocabulary is on the list. That is a WIDER
#     intersection than rule 1's: it drops the requirement for a config-path literal and asks only
#     whether the file is recognisably about a harness client.
#
# **What rule 4 narrows, and what it leaves open.** `D-r7-m` records that an applier split across
# two neutrally-named files outside the seam — one asking `ClientConfigs.path(for:)` for the target,
# another taking a bare `String` and writing it — satisfies no intersection and passes. Rule 4 does
# not close that; it narrows it. The writing half must now also name no client at all, because
# naming one puts it in front of the allowlist. The residue — a writer that reaches a harness config
# through a value with no vocabulary anywhere in the file — is still `D-r7-m`, and the closed-world
# fix it names (census every writing file against a declared allowlist) is still the fix.
#
# The claim this gate can carry, and the one `spec-R7.md` §7 and ORCHESTRATOR.md now make: no single
# file pairs a harness config with a write, **the seam neither writes nor relinks anything**, and
# every file that writes while speaking the client vocabulary is one somebody declared. That
# `ReconciliationPlan` has no applier today is established by reading the tree, not by this.
#
# The router's OWN config is not a harness config and is not matched: `servers.json` is this
# product's file and `ConfigWriter`/`ImportConfigWriter` are supposed to write it.
#
# ## R30 writes `~/.claude/settings.json` ON PURPOSE, and this gate does not prove that safe
#
# `mcp-router ingest --apply` withdraws `enabledPlugins` and `extraKnownMarketplaces` keys for
# extensions it has moved into the router. That is the item's whole subject, taken with the owner:
# it is an owner-invoked command, its default invocation prints a plan and writes nothing, and it
# refuses to pick a tree unless one is named. `planning/specs/spec-R30.md` §4 carries the boundary.
#
# **It passes this gate for a reason a reader should not mistake for a verdict.** The two halves
# live in different files: `RouterCore/Extensions/ClaudeTree.swift` names the harness home and
# `settings.json` and **writes nothing** — it is path derivation and property reads, and
# `grep -nE 'write|create|move|remove|Data\(' ` over it returns nothing at all, comments included —
# while `ClaudeSettingsEditWrites.swift` writes and names no harness path. That is exactly the
# split `D-r7-m` records as this gate's open-world miss, arrived at honestly rather than to evade
# it. What actually holds R30 is its own suite: `ExtensionIngestTests.G7`/`G8`/`G9` and
# `scripts/acceptance/r30-ingest.sh`, which assert the top-level member count is unchanged, that a
# no-op edit leaves the file byte-identical, that an unparsable file is not rewritten, and that the
# real `~/.claude/settings.json`'s size and mtime are the same after a lane run as before it.
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
HARNESS_PATHS='\.claude\.json|claude_desktop_config\.json|\.codex/config\.toml|\.chatgpt/config\.toml|\.cursor/mcp\.json|\.gemini/settings\.json|\.gemini/config/mcp_config\.json|\.grok/config\.toml|opencode/opencode\.json'

# The same files by NAME alone. Nothing in this repository builds a path by writing it out whole —
# every one of them is assembled a component at a time through `appendingPathComponent`, and a
# vocabulary of whole paths cannot see the assembled form. Measured against `app/Sources`: eight
# files name one of these in code and the only one of them that writes anything writes to standard
# output, so this widening costs no false positive today.
HARNESS_PATH_PARTS='mcp_config\.json|claude_desktop_config\.json|\.claude\.json|opencode\.json'

# The names that are NOT distinctive, and the company they must keep.
#
# `settings.json`, `config.toml` and `mcp.json` are three of the commonest file names in software.
# Reading any of them as a harness config on its own refuses this product for writing its own
# `config.toml`, and an out-of-family reviewer found exactly that: a rule that fires on
# `root.appendingPathComponent("config.toml")` beside an unrelated cache write is a false positive
# with no suppression syntax to answer it, which is how a gate gets deleted. They count only in a
# file that also names a harness's HOME — which is where the path they belong to is assembled, and
# is the thing that makes the name a harness's rather than anyone's.
HARNESS_PATH_GENERIC='settings\.json|config\.toml|mcp\.json'
HARNESS_HOMES='\.gemini|\.codex|\.chatgpt|\.cursor|\.grok|\.claude|opencode|Claude/'

# R7's own API. A file holding any of these is handling a harness config or a plan for one, and a
# write in the same file is the applier spec §7 says must not exist.
#
# Matched against the file's code with newlines collapsed to spaces, and tolerant of whitespace
# around the dot and the paren, because this repository's own `line_length: warning 110` wraps a
# long call by itself: `ClientConfigs.path(` followed by `for:` on the next line satisfied
# `ClientConfigs\.path\(for:` in nobody's file.
R7_API='ReconciliationPlan|HarnessReport|ClientConfigs[[:space:]]*\.[[:space:]]*(path|inventory|discover)[[:space:]]*\('

WRITING='writeFile|createFile|write\(to:|write\(toFile:|removeItem|moveItem|copyItem|forWritingTo:|forWritingAtPath|forUpdatingTo:|forUpdatingAtPath|toFileAtPath:|OutputStream\(|replaceItem\(at:|\.write\(|contentsOfFile:.*write|/bin/cp|/bin/mv|/usr/bin/tee'

# Rule 3 only. The seam is a closed set — eight files today — so it can afford a vocabulary that
# would be noisy across 313, and its claim is the strong one: nothing in here reaches another
# program's configuration at all.
#
# Four groups. The C stdio calls obtain a path perfectly well and appear in no Swift write
# spelling. A subprocess writes a file with no write call anywhere in the diff — `/bin/sh -c 'cat >
# target'`. A symlink, a hard link or a mode change **replaces or alters a harness config while
# writing nothing**: `D-r7-v` records that even the acceptance lane's byte digest cannot see the
# last of those, so a gate that also could not see it would leave the mutation unwitnessed on both
# instruments. And the POSIX spellings of those same three — `symlink`, `link`, `chmod`, `rename`,
# `truncate` — which an out-of-family reviewer found the Foundation-only version missing, correctly
# calling it the same defect this pass exists to close: a vocabulary of named routes rather than the
# property behind them.
#
# **Two entries are deliberately broader than "writes".** `fopen(` matches every mode, and
# `Process(`/`executableURL`/`launchPath` say nothing about whether the child writes. That is not an
# oversight: the seam reads harness configs through an injected `FileSystem`, so a raw C handle or a
# spawned process there is out of band whatever it then does, and narrowing `fopen` to a literal
# `"w"` is defeated by a mode held in a variable. The cost of that breadth is stated plainly rather
# than waved at: there is no suppression comment, so a false positive here means rewriting the code
# or amending this vocabulary in a commit that says why.
SEAM_MUTATING='fopen\(|fdopen\(|freopen\(|fputs\(|fputc\(|fwrite\(|fprintf\(|creat\(|O_WRONLY|O_RDWR|O_CREAT|O_APPEND|O_TRUNC|posix_spawn|Process\(|executableURL|launchPath|/bin/sh|/bin/bash|/bin/zsh|/usr/bin/env|createSymbolicLink|createLink|linkItem|setAttributes\(|trashItem|link\(|chmod\(|rename\(|renameat\(|truncate\(|mkstemp\(|mkdtemp\(|utimes\(|Darwin\.write\(|dup2\('

# `.write(` also matches writing to a standard stream, which is printing rather than writing a
# config. Excluded so that `Out.print` does not make every verb a finding — which is the kind of
# noise that gets a gate deleted.
NOT_A_FILE_WRITE='FileHandle\.standard(Output|Error)'

# ------------------------------------------------------------------ rule 4's declarations
#
# The files permitted to write another application's MCP configuration, repo-relative to $SOURCES.
# Adding one here is the commit that says why it exists; nothing else in this gate is allowed to
# grow a writer quietly.
#
#   ClaudeStagingEntry.swift  `install-entry` and `watch` — pre-existing, parity-locked product
#                             behaviour; it reproduces the installer's `~/.claude.json` step.
#   DesktopEntryWriter.swift  R32's `desktop-entry` verb. Dry run by default; the write happens only
#                             under `--apply`, typed by the owner, and no daemon path reaches it.
HARNESS_WRITERS=(
  'RouterCore/Watch/ClaudeStagingEntry.swift'
  'RouterCore/Desktop/DesktopEntryWriter.swift'
)

# What "recognisably about a harness client" means, as tokens rather than as judgement.
#
# Deliberately the CLIENT's vocabulary rather than the config file's: rule 1 already reads path
# literals, and repeating it here would only re-find rule 1's own findings. `mcpServers` is
# excluded on purpose — this product's own importer, config writer and watcher all handle that key
# legitimately while writing `servers.json`, and a rule that named it would put six of this
# repository's own files in front of an allowlist they have no business being on.
CLIENT_VOCAB='claudeDesktop|claudeCode|MCPClient|ClaudeStagingEntry|DesktopEntry|DesktopBridge'

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
  writes_matching "$1" "$WRITING"
}

# The same, over rule 3's wider vocabulary.
seam_writes() {
  writes_matching "$1" "$WRITING|$SEAM_MUTATING"
}

# Every line in $1 that matches vocabulary $2. Empty when the file only prints.
#
# The printing construct is **neutralised in the line** rather than the line being dropped. Dropping
# it let `try data.write(to: target) // FileHandle.standardOutput` erase itself from the gate with a
# trailing comment — both out-of-family reviewers found that one independently. Rewriting only the
# head of the call leaves any real write on the same line still matching.
#
# Written as a capture-and-test rather than `grep -q`, because BSD `grep -qv` exits 0 on empty
# input: `grep -E pattern file | grep -qvE other` reports a match for a file with no matches at
# all, which would have made all three rules fire on all 313 sources.
writes_matching() {
  code_lines "$1" \
    | grep -nE "$2" \
    | sed -E "s/$NOT_A_FILE_WRITE\.write\(/PRINTS(/g" \
    | grep -E "$2"
}

# The file with its comments removed, **as a comment reader rather than as a line shape**.
#
# A harness path in a doc comment is documentation; several files under `app/Sources` discuss
# `~/.claude.json` in prose and write something unrelated, and reading those as findings is how a
# gate stops being run. The previous version blanked any line whose first characters were `//`,
# `/*`, `*/` or `*`, which is a guess about how comments are laid out, and it was wrong in both
# directions at once:
#
#   * a write SHARING a line with a block comment was blanked with it — the same trailing-comment
#     evasion `writes_matching` was hardened against, left open one function along; and
#   * prose inside a `/* … */` whose lines do not begin with `*` was read as CODE, so a file that
#     only documents what it refuses to do reads as a finding.
#
# So the block state is tracked instead. Comment spans are **blanked, not deleted**, so `grep -n`
# downstream still reports the line number a person would open the file at. Two deliberate
# narrownesses: a whole-line `//` comment is blanked while a TRAILING one keeps its text, because a
# trailing comment must never be able to erase a real write beside it; and `/*` opens a block only
# where it starts the line or follows an opener character, so `let pattern = "/*"` and the `src/*.ts`
# this repository already carries in a doc comment do not blank the rest of a file.
code_lines() {
  awk '
    # The first comment marker on the line that is not inside a string literal, as a kind and a
    # position. A scan rather than a pattern, because both ways this reader has been wrong are the
    # same mistake in mirror image, and both were found by out-of-family review:
    #
    #   * `let marker = " /*"` opened a block on a slash-star inside a STRING, and everything after
    #     it — including a real write on the next line — was blanked through end of file. A gate
    #     that goes quiet is the vacuity this file exists to refuse, arriving through its own
    #     stripper. The previous guard, "a `/*` preceded by whitespace is an opener", is what let it
    #     in: inside a string the preceding character is whitespace as often as anywhere else.
    #   * `let reference = "https://example.test" /*` did the reverse. The `//` inside the URL was
    #     read as a line comment starting before the real block opener, so the block never opened
    #     and the prose inside it was read as code.
    #
    # Tracking the string state settles both, and it is the rule Swift itself applies. A backslash
    # escapes the next character; the state resets at each line, so the body of a multi-line `"""`
    # string is read as code — the direction that reports rather than the one that goes quiet.
    function marker(s,   i, n, c, c2, instr) {
      n = length(s); instr = 0
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (instr) {
          if (c == "\\") { i++; continue }
          if (c == "\"") { instr = 0 }
          continue
        }
        if (c == "\"") { instr = 1; continue }
        if (c != "/") continue
        c2 = substr(s, i + 1, 1)
        if (c2 == "/") { KIND = "line"; POS = i; return }
        if (c2 == "*") { KIND = "block"; POS = i; return }
      }
      KIND = "none"; POS = 0
    }
    {
      line = $0
      out = ""
      if (!inblock && line ~ /^[[:space:]]*\/\//) { print ""; next }
      while (length(line) > 0) {
        if (inblock) {
          i = index(line, "*/")
          if (i == 0) { line = ""; break }
          line = substr(line, i + 2)
          inblock = 0
          continue
        }
        marker(line)
        # A TRAILING line comment keeps its text: a comment must never be able to erase a real write
        # beside it, which is the evasion `writes_matching` was hardened against.
        if (KIND != "block") { out = out line; break }
        out = out substr(line, 1, POS - 1)
        line = substr(line, POS + 2)
        inblock = 1
      }
      print out
    }
  ' "$1" 2>/dev/null
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
probe "$HARNESS_PATHS"     'let path = home.appendingPathComponent(".gemini/config/mcp_config.json")'
probe "$HARNESS_PATH_PARTS" 'let path = dir.appendingPathComponent("mcp_config.json")'
probe "$HARNESS_PATH_GENERIC" 'let path = dir.appendingPathComponent("config.toml")'
probe "$HARNESS_HOMES"     'let dir = home.appendingPathComponent(".codex")'
probe "$R7_API"            'func apply(_ plan: ReconciliationPlan, to target: String) throws {'
probe "$R7_API"            'let target = ClientConfigs.path(for: client, homeDirectory: home)'
probe "$NOT_A_FILE_WRITE"  'FileHandle.standardOutput.write(Data(text.utf8))'
probe "$CLIENT_VOCAB"      'let report = inventory.first { $0.client == .claudeDesktop }'
probe "$CLIENT_VOCAB"      'public static func apply(_ entry: DesktopEntry, bridge: DesktopBridge) {'

# Rule 2 is matched against the file's code with its NEWLINES collapsed, so the probe for that has
# to carry a real newline. A single-line subject with a space in it establishes only that the
# pattern tolerates whitespace, and would keep passing if the collapsing were removed altogether —
# an out-of-family reviewer found the old probe proving nothing about the thing it was added for.
# This one joins first, exactly as the rule does.
probe_joined() {
  printf '%s' "$2" | tr '\n' ' ' | grep -qE "$1" || {
    echo "no-harness-config-writes: this gate's own pattern no longer matches across a line wrap."
    echo "  pattern: $1"
    exit 2
  }
}
probe_joined "$R7_API" 'guard let target = ClientConfigs.path(
    for: client, homeDirectory: home, projectDirectory: nil
) else { return }'

# Rule 3's vocabulary, one subject per alternative — and then the closure check that makes the
# header's claim true rather than asserted: every alternative in `SEAM_MUTATING` must be matched by
# at least one of these, so a spelling added without a subject fails the gate at exit 2 instead of
# joining it unexercised. A reviewer counted five subjects against twenty-two alternatives and was
# right to; the count is no longer maintained by hand.
SEAM_PROBES=(
  'guard let handle = fopen(target, "w") else { return }'
  'let out = fdopen(descriptor, "w")'
  'let reopened = freopen(target, "a", stdout)'
  'fputs(text, handle)'
  'fputc(0x0a, handle)'
  'fwrite(bytes, 1, count, handle)'
  'fprintf(handle, "%s", text)'
  'let fd = creat(target, 0o644)'
  'let fd = open(target, O_WRONLY)'
  'let fd = open(target, O_RDWR)'
  'let fd = open(target, O_CREAT | O_TRUNC, 0o644)'
  'let fd = open(target, O_APPEND)'
  'posix_spawn(&pid, tool, nil, nil, argv, environ)'
  'let task = Process()'
  'task.executableURL = URL(fileURLWithPath: shell)'
  'task.launchPath = shell'
  'task.arguments = ["/bin/sh", "-c", script]'
  'task.arguments = ["/bin/bash", "-c", script]'
  'task.arguments = ["/bin/zsh", "-c", script]'
  'task.arguments = ["/usr/bin/env", "tee", target]'
  'try manager.createSymbolicLink(atPath: target, withDestinationPath: staged)'
  'try manager.createLink(at: url, withDestinationURL: stagedURL)'
  'try manager.linkItem(atPath: staged, toPath: target)'
  'try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target)'
  'try manager.trashItem(at: url, resultingItemURL: nil)'
  'symlink(staged, target)'
  'link(staged, target)'
  'unlink(target)'
  'chmod(target, 0o600)'
  'rename(staged, target)'
  'renameat(dirfd, staged, dirfd, target)'
  'truncate(target, 0)'
  'let fd = mkstemp(&template)'
  'let dir = mkdtemp(&template)'
  'utimes(target, times)'
  'Darwin.write(fd, bytes, count)'
  'dup2(fd, STDOUT_FILENO)'
)
for subject in ${SEAM_PROBES+"${SEAM_PROBES[@]}"}; do
  probe "$SEAM_MUTATING" "$subject"
done
IFS='|' read -r -a SEAM_ALTS <<< "$SEAM_MUTATING"
for alt in ${SEAM_ALTS+"${SEAM_ALTS[@]}"}; do
  matched=""
  for subject in ${SEAM_PROBES+"${SEAM_PROBES[@]}"}; do
    if printf '%s\n' "$subject" | grep -qE "$alt"; then matched="yes"; break; fi
  done
  [ -n "$matched" ] && continue
  echo "no-harness-config-writes: an entry in rule 3's vocabulary is exercised by no probe."
  echo "  alternative: $alt"
  echo "  Add a subject to SEAM_PROBES that this matches, or the header's claim is not true."
  exit 2
done

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
  # One line, so a call wrapped across two of them is still one token to the pattern.
  joined="$(printf '%s' "$code" | tr '\n' ' ')"
  names_path=""
  if grep -qE "$HARNESS_PATHS|$HARNESS_PATH_PARTS" <<< "$code"; then
    names_path="yes"
  elif grep -qE "$HARNESS_PATH_GENERIC" <<< "$code" && grep -qE "$HARNESS_HOMES" <<< "$code"; then
    names_path="yes"
  fi
  [ -n "$names_path" ] && NAMING=$((NAMING + 1))
  [ -n "$writes" ] || continue

  if [ -n "$names_path" ]; then
    report "$file names a harness config path and writes a file:"
    printf '%s\n' "$writes" | sed 's/^/    /'
  fi
  if grep -qE "$R7_API" <<< "$joined"; then
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
  writes="$(seam_writes "$file")"
  [ -n "$writes" ] || continue
  report "$file is inside R7's seam, which neither writes nor relinks anything:"
  printf '%s\n' "$writes" | sed 's/^/    /'
done

# ------------------------------------------------------------------ rule 4: declared writers only
#
# **The declarations are this repository's, and the scan is whatever tree you point at.** That split
# is what lets the gate's own selftest drive it against scratch trees that contain none of these
# files: `HARNESS_WRITERS` is checked against `app/Sources` here, always, while the intersection
# below reads `$SOURCES`. Reading the list against a scratch tree would have made every selftest
# case a rule 4 finding and the selftest would have been softened to make it pass — which is how a
# gate stops meaning anything.
#
# The declared writers are also rule 4's **control**. Each of them writes and each names a client,
# so the reader used below must find both of them; a reader that finds fewer has stopped seeing,
# and reporting a clean intersection on it would be a zero that measured nothing. That is exit 2,
# not exit 0.
REAL_SOURCES="$REPO_ROOT/app/Sources"
[ -d "$REAL_SOURCES" ] || {
  echo "no-harness-config-writes: rule 4 cannot find $REAL_SOURCES to check its declarations against."
  exit 2
}

# Whether one file both writes and speaks the client vocabulary — rule 4's reader, named once so
# the control and the scan cannot drift apart.
is_vocabulary_writer() {
  [ -n "$(file_writes "$1")" ] || return 1
  grep -qE "$CLIENT_VOCAB" <<< "$(code_of "$1")"
}

DECLARED_EXAMINED=0
for relative in "${HARNESS_WRITERS[@]}"; do
  DECLARED_EXAMINED=$((DECLARED_EXAMINED + 1))
  file="$REAL_SOURCES/$relative"
  if [ ! -f "$file" ]; then
    report "rule 4: $relative is declared in HARNESS_WRITERS and does not exist."
    continue
  fi
  if [ -z "$(file_writes "$file")" ]; then
    report "rule 4: $relative is declared as a harness-config writer and writes nothing. Remove"
    report "        the declaration in the commit that removed the write, or the list is a fiction."
    continue
  fi
  is_vocabulary_writer "$file" && continue
  echo "no-harness-config-writes: rule 4's reader cannot see its own declared writer $relative."
  echo "  That file writes and names a client, so the reader finding nothing there means"
  echo "  CLIENT_VOCAB or the write vocabulary stopped matching — not that the tree got safer."
  exit 2
done

# The scan: every file under $SOURCES that writes AND names a client must be on the list.
VOCAB_WRITERS=0
while IFS= read -r file; do
  is_vocabulary_writer "$file" || continue
  VOCAB_WRITERS=$((VOCAB_WRITERS + 1))
  relative="${file#"$SOURCES"/}"
  declared=""
  for allowed in "${HARNESS_WRITERS[@]}"; do
    [ "$relative" = "$allowed" ] && { declared="yes"; break; }
  done
  [ -n "$declared" ] && continue
  report "rule 4: $relative writes a file and speaks the harness client vocabulary, and is not declared in HARNESS_WRITERS:"
  file_writes "$file" | sed 's/^/    /'
done < <(find "$SOURCES" -name '*.swift' -type f | sort)

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
       "$WRITERS write a file, $SEAM_EXAMINED in the seam — none writes one;" \
       "$VOCAB_WRITERS write while naming a client, all $DECLARED_EXAMINED declared"
  exit 0
fi
exit 1
