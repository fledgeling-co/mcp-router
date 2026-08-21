### Blocking

#### 1. `gemini_plan` in acceptance script bleeds into subsequent harnesses when a plan is suppressed
- **Location:** [r7-harness-reconciliation.sh:109-111](file:///scripts/acceptance/r7-harness-reconciliation.sh#L109-L111)
- **Construct:** `gemini_plan() { awk '/^Gemini CLI — /{f=1} f{print} f&&/nothing applies this plan/{f=0}'; }`
- **Trigger input:** Pass 5 (`could not be read`). Gemini CLI’s plan is suppressed (so `nothing applies this plan` is never printed in its section), while a subsequent harness in `$SCRATCH_HOME` (e.g. Claude Code or Codex) prints a plan.
- **Observable wrong behaviour:** `awk` stays in state `f=1` and prints every subsequent harness’s output until it encounters `nothing applies this plan` from another harness. Line 237 `check "and proposes nothing" 0 "$(printf '%s' "$TEXT" | gemini_plan | grep -c 'nothing applies')"` then counts `1` and fails Pass 5 falsely. If no subsequent harness has a plan, it only passes because of accidental isolation, while still capturing the entire tail of stdout.
- **Fix:** Bound the section by stopping on the next harness headline:
  ```bash
  gemini_plan() {
    awk '/^Gemini CLI — /{f=1; print; next} f&&/^[A-Za-z0-9 ]+ — /{f=0} f{print}'
  }
  ```

---

### Should-Fix

#### 2. Line-masking bypass in lint gate via `NOT_A_FILE_WRITE`
- **Location:** [no-harness-config-writes.sh:85-87](file:///scripts/lint/no-harness-config-writes.sh#L85-L87)
- **Construct:** `file_writes() { grep -nE "$WRITING" "$1" 2>/dev/null | grep -vE "$NOT_A_FILE_WRITE"; }`
- **Trigger input:** Any file write sharing a physical line with `FileHandle.standardOutput` or `FileHandle.standardError` (e.g., `try text.write(toFile: path, ...) // FileHandle.standardOutput`).
- **Observable wrong behaviour:** `grep -vE` drops the entire line. `file_writes` returns empty, allowing an applier in any of Rules 1, 2, or 3 to bypass the gate by appending a trailing comment or placing a print on the same line.
- **Fix:** Strip `FileHandle.standardOutput.write(...)` specifically or avoid catching `.write(` generically when standard stream printing is the only intended exclusion.

#### 3. False positives on block comments and Rule 2 doc comments
- **Location:** [no-harness-config-writes.sh:92-94, 134](file:///scripts/lint/no-harness-config-writes.sh#L92-L94)
- **Construct:** `code_of() { grep -vE '^[[:space:]]*//' "$1"; }` and `if grep -qE "$R7_API" "$file"; then`
- **Trigger input:**
  1. A file containing a C-style block comment (`/* ~/.claude.json */` or ` * ~/.claude.json`) that also performs any unrelated file write (e.g. `ConfigWriter`).
  2. A file referencing `ReconciliationPlan` in a doc comment (`/// See ReconciliationPlan for context`) that writes any file.
- **Observable wrong behaviour:** `code_of` only matches leading `//`, passing block comments through to Rule 1. Rule 2 runs `grep` directly on the raw file without stripping comments at all. Both fail innocent files that document R7 or harness paths.
- **Fix:** Run `code_of` on Rule 2 as well, and extend `code_of` to strip block comment lines (`^[[:space:]]*(\/\/|\*|\/\*)`).

#### 4. Gaps in the `WRITING` vocabulary
- **Location:** [no-harness-config-writes.sh:65](file:///scripts/lint/no-harness-config-writes.sh#L65)
- **Construct:** `WRITING='...|OutputStream\(toFileAtPath:|FileHandle\(forWritingTo:|...'`
- **Trigger input:** An applier using `OutputStream(url: targetURL, append: false)`, `FileHandle(forUpdatingTo: url)`, or `FileHandle(forUpdatingAtPath: path)`.
- **Observable wrong behaviour:** These write sinks are missing from `$WRITING`, allowing an applier using URL-based streams or update handles to pass all three rules.
- **Fix:** Add `OutputStream\(url:|FileHandle\(forUpdating` to `$WRITING`.

---

### Note

#### 5. Acceptance lane does not test duplicate detection for `httpUrl` upstreams
- **Location:** [r7-harness-reconciliation.sh:77-87, 184-195](file:///scripts/acceptance/r7-harness-reconciliation.sh#L77-L87)
- **Construct:** `write_harness_http_url "$THREE_DUPLICATES"`
- **Observable gap:** `THREE_DUPLICATES` defines only stdio command upstreams. Pass 4 verifies an `httpUrl` router entry alongside stdio duplicates, but does not verify on the CLI wire that an external duplicate declared with `httpUrl` (e.g., `"Mobbin": { "httpUrl": "https://api.mobbin.com/mcp" }`) is matched and reported for removal. While covered in `HarnessDialectTests.swift`, the CLI integration lane leaves this unexercised.

#### 6. Canonicalisation leaves `httpUrl` alongside `url` in raw JSON
- **Location:** [HarnessWiring.swift:74-76](file:///app/Sources/RouterCore/Discovery/HarnessWiring.swift#L74-L76)
- **Construct:** `let rewritten = members.filter { $0.key.string != "url" } + [JSONMember(key: JSString("url"), value: .string(JSString(endpoint)))]`
- **Assessment:** Design Decision 2 holds: canonicalisation is scoped strictly to `others` in `HarnessReconciliation.report` and cannot leak into `import`, `watch`, or router config loading. Because `UpstreamHash` specifically digests `raw.member("url")`, leaving `httpUrl` in `rewritten` does not break identity hashing. However, removing both `"url"` and `"httpUrl"` before appending `"url"` (`filter { $0.key.string != "url" && $0.key.string != "httpUrl" }`) would be cleaner and avoid carrying redundant dialect keys into downstream parsers.
