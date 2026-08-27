### [HIGH] Resolve commands relative to the child’s working directory

**File:** [`// would have found — R6's defect rebuilt inside the fix for it.`, StdioUpstreamTransport.swift:126 at `7a4f15a`](/Users/lukerhodes/Dev/mcp-router/.worktrees/R6/app/Sources/RouterCore/Pool/StdioUpstreamTransport.swift:126)

**Issue:** `resolve` runs before `process.currentDirectoryURL` is assigned at line 143, so relative commands and relative PATH entries are checked against the router’s cwd but executed against `upstream.cwd`. `{command:"./bin/server", cwd:"/tmp/project"}` works in Node but Swift incorrectly returns ENOENT; the converse passes precheck and then times out.

**Fix:** Pass `upstream.cwd` into `resolve` and resolve relative commands/PATH entries against it.

**Confidence:** 99

### [HIGH] Use one explicit sort order in both implementations

**File:** ["// Sorted by UTF-8 bytes rather than by `String`'s own ordering. Swift compares Strings by", ChildPath.swift:74 at `7a4f15a`](/Users/lukerhodes/Dev/mcp-router/.worktrees/R6/app/Sources/RouterCore/Pool/ChildPath.swift:74), ["// Sorted by UTF-8 bytes rather than by the default `Array.sort`, which compares UTF-16", pool.ts:49 at `7a4f15a`](/Users/lukerhodes/Dev/mcp-router/.worktrees/R6/src/pool.ts:49)

**Issue:** Swift’s native `String` ordering differs from JavaScript’s UTF-16 `.sort()`. For dot-directories `.😀` and `.\u{E000}`, Node places the emoji first while Swift places U+E000 first. PATH bytes therefore differ; at the 64-entry boundary, the routers can select different directories.

**Fix:** Define the same byte/code-unit comparator in both routers and test Unicode names across the cap boundary.

**Confidence:** 99

### [MEDIUM] Reject unsafe discovered directories

**File:** [`public func isDirectory(atPath path: String) -> Bool {`, ChildPath.swift:22 at `7a4f15a`](/Users/lukerhodes/Dev/mcp-router/.worktrees/R6/app/Sources/RouterCore/Pool/ChildPath.swift:22), ["const found = new Set<string>();", pool.ts:41 at `7a4f15a`](/Users/lukerhodes/Dev/mcp-router/.worktrees/R6/src/pool.ts:41)

**Issue:** Both checks follow symlinks and validate neither ownership nor permissions. If `~/bin` or `~/.tool/bin` points to a group/world-writable directory, another local user can plant a previously absent command that routed children execute as the router user. Append-only ordering does not protect missing commands—the exact case this change enables.

**Fix:** Use `lstat`, reject symlinks, and require the resolved directory to be user-owned and non-group/world-writable.

**Confidence:** 93

### [MEDIUM] Preserve empty PATH components

**File:** [`public static func augment(`, ChildPath.swift:90 at `7a4f15a`](/Users/lukerhodes/Dev/mcp-router/.worktrees/R6/app/Sources/RouterCore/Pool/ChildPath.swift:90), [pool.ts:61 at `7a4f15a`](/Users/lukerhodes/Dev/mcp-router/.worktrees/R6/src/pool.ts:61)

**Issue:** Empty PATH components represent the current directory under `execvp`. Filtering them changes an inherited `:/usr/bin` or empty PATH instead of appending to it, so previously resolvable commands can disappear. Swift’s precheck also drops empty components at `let path = (environment ?? ProcessInfo.processInfo.environment)["PATH"] ?? ""`, `StdioUpstreamTransport.swift:173` at `7a4f15a`, disagreeing with `/usr/bin/env`.

**Fix:** Preserve inherited components byte-for-byte, including empties; deduplicate only appended entries.

**Confidence:** 98

### [MEDIUM] The 64-entry cap does not bound discovery cost

**File:** [`for entry in probe.entries(ofDirectoryAt: home) where entry.hasPrefix(".") {`, ChildPath.swift:61 at `7a4f15a`](/Users/lukerhodes/Dev/mcp-router/.worktrees/R6/app/Sources/RouterCore/Pool/ChildPath.swift:61), ["let entries: string[] = [];", pool.ts:31 at `7a4f15a`](/Users/lukerhodes/Dev/mcp-router/.worktrees/R6/src/pool.ts:31)

**Issue:** Both routers enumerate, stat, and sort every candidate before applying the cap. This happens per spawn; TypeScript blocks the sole event loop with synchronous filesystem calls. Large or slow homes can stall unrelated routing despite the claimed bound.

**Fix:** Cache discovery once per router start or impose a genuine bounded scan.

**Confidence:** 97

### [MEDIUM] The red acceptance half treats every failure as success

**File:** [`HOME="$BARE_HOME" MCP_ROUTER_HOME="$before_home" PATH="$LAUNCHD_PATH" \`, r6-child-path.sh:130 at `7a4f15a`](/Users/lukerhodes/Dev/mcp-router/.worktrees/R6/scripts/acceptance/r6-child-path.sh:130)

**Issue:** `|| true` discards the router status, and absence of `child-env.json` is accepted regardless of cause. The ENOENT grep is display-only. A crash, configuration failure, or removed precheck producing a timeout all report `ok`.

**Fix:** Assert the expected exit status and require the exact `spawn mcpr-r6-fixture ENOENT` output.

**Confidence:** 99

WARNING