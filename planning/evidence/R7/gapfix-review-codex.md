## Blocking

1. `HarnessDialect.endpoint(in:)` applies Gemini’s dialect to every harness.

   Input: a Claude/Cursor/Codex entry such as:

   ```json
   {"command":"npx","args":["server"],"httpUrl":"http://127.0.0.1:8879/mcp"}
   ```

   Those harnesses do not necessarily interpret `httpUrl`, but `HarnessRoute.detect` now reports `directHTTP`. `canonicalised` also converts it into an HTTP server for parsing/hashing, potentially producing a false identity duplicate and suppressing the real entry as `routerEntryName`.

   Pass the client/dialect into detection and comparison. Recognize `httpUrl` only for harnesses confirmed to support it.

2. `endpointKeys = ["url", "httpUrl"]` gives the wrong key unconditional precedence and accepts non-strings.

   Inputs:

   ```json
   {"url":"http://127.0.0.1:8879/mcp","httpUrl":"https://actual.example/mcp"}
   ```

   falsely reports Gemini wired, while the reverse arrangement falsely reports it not wired. Likewise, `"url":true` shadows a valid `httpUrl` and returns `"true"`.

   This also mis-hashes conflicts: `canonicalised` returns unchanged whenever the first `url` is truthy, so comparison uses the possibly irrelevant `url`, not Gemini’s effective endpoint. Require a JSON string and define precedence per harness; for Gemini I would prefer `httpUrl`, or mark conflicting keys unparsed rather than confidently guessing.

3. The lint still passes a straightforward split-file applier.

   Rule 1 and rule 2 are same-file intersections, while rule 3 covers only `RouterCore/Discovery` and `HarnessesVerb.swift`. For example, `HarnessCoordinator.swift` can call `ClientConfigs.path(for:)`, then pass the path to `FileStore.save`; `FileStore.swift` can call `Data.write(to:)`. Neither file satisfies an intersection, and both can live outside the listed seam. The gate exits 0 while harness configuration is written. Documenting this limitation does not preserve the claimed no-applier invariant.

4. `file_writes` can be defeated by the broad line exclusion:

   ```bash
   grep -vE "$NOT_A_FILE_WRITE"
   ```

   An applier can contain:

   ```swift
   try data.write(to: target) // FileHandle.standardOutput
   ```

   That entire write line is discarded. The same happens if a line legitimately prints and writes a file. Strip comments and classify the matched call itself; do not exclude a whole line merely because it contains the stdout token.

## Should-fix

5. `code_of "$file" | grep -qE "$HARNESS_PATHS"` is unsafe with `set -o pipefail`.

   On macOS/BSD, if `grep -q` finds an early match and exits while `code_of` still has enough output to write, the upstream grep can receive SIGPIPE. The pipeline then fails, leaving `names_path` empty. A large file containing an early harness literal and a later file write can evade rule 1. Capture `code_of` first, or avoid `-q` in a producer pipeline.

6. The “code” filtering does not match its claim.

   `code_of` removes only whole-line `//` comments. Harness paths inside block comments, multiline string documentation, or trailing comments remain. `R7_API` is searched on the completely unfiltered file. Thus an innocent cache writer with documentation mentioning `HarnessReport` or `~/.gemini/settings.json` fails the gate. Conversely, comments enable the stdout bypass above.

7. P5 in `no-harness-config-writes-selftest.sh` does not test `FileHandle(forWritingTo:)`.

   The fixture also contains `handle.write(data)`, already matched by generic `\.write\(`. Removing `FileHandle\(forWritingTo:` from `WRITING` still leaves P5 red as expected, so the self-test passes for the wrong reason. The plant should open the handle in one file and pass it to a helper, or otherwise isolate the constructor token.

8. The acceptance read-only assertion is too weak:

   ```bash
   grep -q '"httpUrl"' "$SCRATCH_HOME/.gemini/settings.json"
   ```

   Reformatting, adding/removing entries, or otherwise rewriting the file while retaining that token passes. It also checks only Gemini’s file. Snapshot checksums of every harness fixture before both probes and compare afterward.

## Note

`canonicalised` has no shown call outside `HarnessReconciliation.report`, and it constructs a new value, so it does not mutate shared configuration. However, it is not “only for duplicate comparison”: mapping `others` before parsing also changes `unparsed` and `entryCount`, as `httpURLIsNotUnparsed` explicitly demonstrates. That wider behavior becomes problematic chiefly because the canonicalisation is applied to every client rather than the Gemini dialect alone.