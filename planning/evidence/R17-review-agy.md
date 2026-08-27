# R17 — the out-of-family lane, Google family

`agy --model gemini-3.7-flash-high`, one pass, run from `/tmp/r17-review` against a read-only copy
of the diff and the three source files, on 2026-08-22. The effort is baked into the model id.
Codex was unavailable until 27 August and the grok balance was exhausted, so this and the Fable
lane below are the two that ran. The writer of the change is Claude, so this lane is out of family
and the Fable one is not; it is recorded as a second reader rather than as family diversity.

The prompt was adversarial rather than a review: "try to BREAK the change described in CONTEXT.md.
Concrete findings only, each naming a file and the sequence that breaks it. End with the single
check that would most change your confidence."

Verbatim below.

---

### 1. Reader Behavior on `error` Entries

**Verdict: The claim holds; all readers handle `entry.error` safely.**

Every reader across the TypeScript and Swift implementations was checked:

| Consumer | Location | Handling with `entry.error` |
| :--- | :--- | :--- |
| **Watcher Staging / Adoption** | ["const entry = manifest.servers[name];", `src/watch.ts:286-290` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/watch.ts#L286-L290)<br>[`let entry = manifest.entry(named: candidate.name)`, `WatchRun.swift:182-188` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/app/Sources/RouterCore/Watch/WatchRun.swift#L182-L188) | `if (!entry || entry.error || entry.hash !== upstreamHash(upstream))` rejects adoption and pushes the server to `pending`. |
| **Staleness Checker** | [`export function isStale(manifest: Manifest, u: UpstreamConfig): boolean {`, `src/manifest.ts:198-201` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/manifest.ts#L198-L201)<br>[`public static func isStale(_ manifest: Manifest, _ upstream: UpstreamConfig) -> Bool {`, `ToolUnion.swift:39-46` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/app/Sources/RouterCore/Manifest/ToolUnion.swift#L39-L46) | `isStale` evaluates `!entry || entry.hash !== ... || !!entry.error` &rarr; returns `true`. The server remains marked for re-indexing once backoff expires. |
| **Tool Serving (`unionTools`)** | ["entry.tools.length === 0) continue;", `src/manifest.ts:326` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/manifest.ts#L326)<br>[`guard let entry = manifest.entry(named: upstream.name) else { continue }`, `ToolUnion.swift:65` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/app/Sources/RouterCore/Manifest/ToolUnion.swift#L65) | `if (!entry || entry.tools.length === 0) continue;` skips the entry entirely because `entry.tools` is `[]`. No broken or empty tool surface is served to clients. |
| **Status & Describe (`/servers`)** | ["tools: entry?.error ? 0 : (entry?.tools.length ?? 0),", `src/control.ts:214-217` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/control.ts#L214-L217)<br>[`var members: [JSONMember] = [`, `Describe.swift:27-31` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/app/Sources/RouterCore/Control/Describe.swift#L27-L31) | Explicitly checks `tools: entry?.error ? 0 : ...` and surfaces `indexError: entry?.error`. |
| **Upstream Health (`reportUpstreams`)** | ["const indexError = entry?.error;", `src/oauth.ts:279-306` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/oauth.ts#L279-L306)<br>[`) async -> UpstreamReport {`, `UpstreamStateReport.swift:80-120` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/app/Sources/RouterCore/AuthServer/UpstreamStateReport.swift#L80-L120) | Checks `indexError = entry?.error`. Switches the recommendation from the generic *"Re-index it and see what it reports"* to *"Fix the error below, then re-index it"* and surfaces the exact error string in `detail`. |
| **Direct Tool Dispatch (`callTool`)** | ["const placard = upstream ? placardFor(upstream, manifest.current().servers[serverName]) :", `src/router.ts:208-222` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/router.ts#L208-L222)<br>[`let entry = await deps.manifest.current().entry(named: serverName)`, `MCPEndpointToolCall.swift:70-75` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/app/Sources/RouterCore/Service/MCPEndpointToolCall.swift#L70-L75) | [`placardFor`](file:///Users/lukerhodes/Dev/mcp-router/src/manifest.ts#L301-L308) returns `{ reason: entry.error }`. If a client attempts to call a tool on a failed server using a stale cached name, the router immediately returns an `INOPERATIVE` response rather than attempting to spawn a broken process. |

---

### 2. Unbounded Growth of Unadopted Staged Rows

**Verdict: Real structural accumulation on disk, but zero runtime/functional impact.**

- **Sequence**:
  1. A server (e.g. `pocketsmith`) is staged in `~/.claude.json`.
  2. `watch.ts` attempts to index it; `buildManifest` fails and writes `manifest.servers['pocketsmith'] = { ... error }` ([`manifest.servers[u.name] = {`, `src/manifest.ts:260-265` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/manifest.ts#L260-L265)).
  3. The user removes `pocketsmith` from `~/.claude.json`.
  4. On the next watch run ([`for (const name of Object.keys(failures)) {`, `src/watch.ts:207-209` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/watch.ts#L207-L209)), `state.failures['pocketsmith']` is pruned from `watch-state.json`.
  5. **However, `manifest.servers['pocketsmith']` is never pruned from `manifest.json`.**
- **Impact Assessment**:
  - **No functional leak**: All operational endpoints (`unionTools`, `reportUpstreams`, `describe`, `/servers`, `status`) iterate over `config.upstreams` (from `servers.json`), **not** `Object.keys(manifest.servers)`. Staged rows that were never adopted are never iterated or served.
  - **Existing design consistency**: Manifest keys are never pruned anywhere in the architecture (see ["/// rather than in ``apply(previous:observation:configHash:nowMilliseconds:)``: an", `ManifestBookkeeping.swift:97-98` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/app/Sources/RouterCore/Manifest/ManifestBookkeeping.swift#L97-L98): *"an upstream that is no longer declared keeps its entry rather than being pruned"*). Removing an adopted server via `POST /servers/:name` (`DELETE`) removes it from `servers.json`, but also leaves its historical entry in `manifest.json`.
  - **Storage**: At ~120 bytes per failure row, thousands of distinct failed server configurations would be required to consume even 1 MB.

---

### 3. Paths That Still Leave No Record

**Verdict: Pre-index configuration parse rejections bypass `buildManifest` by design, but runtime failures are completely captured.**

1. **Config Syntax Rejection (`parseServer`)**:
   - **File & Line**: [`export function parseServer(name: string, s: RawServer): { upstream: UpstreamConfig }`, `src/config.ts:139-180` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/config.ts#L139-L180) / [`for (const [name, s] of Object.entries(raw.mcpServers ?? {})) {`, `src/config.ts:252-256` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/config.ts#L252-L256)
   - **Sequence**: If an entry in `servers.json` or `~/.claude.json` has an invalid name (e.g. contains `__`), missing `command` for stdio, or an unparseable URL for HTTP, `parseServer` returns `{ reason }`.
   - **Result**: It is added to `skipped` and excluded from `config.upstreams`. It never reaches `buildManifest` and leaves no manifest row. It is reported only in server startup logs (`not proxied: <name>`). This is schema validation rather than an indexing failure.
2. **Filesystem Write Failures on `saveManifest`**:
   - **File & Line**: ["saveManifest(manifestPath, manifest);", `src/watch.ts:273` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/watch.ts#L273) vs [`try? ManifestIO.save(manifest, toPath: manifestPath, fileSystem: fileSystem)`, `WatchIndexing.swift:156` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/app/Sources/RouterCore/Watch/WatchIndexing.swift#L156)
   - **Sequence**: If disk write fails (e.g. `ENOSPC`), Node throws an uncaught error whereas Swift executes `try? ManifestIO.save(...)` which silently discards the write. In either case, the manifest on disk cannot receive the failure row.
3. **Runtime Execution Failures**:
   - **File & Line**: ["const handle = await pool.acquire(u.name);", `src/manifest.ts:223-279` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/manifest.ts#L223-L279)
   - **Sequence**: The per-upstream `try/catch` in `buildManifest` encapsulates `pool.acquire()` and `client.listTools()`. Non-existent binaries (`ENOENT`), permissions errors (`EACCES`), process crashes on startup, crashes during `initialize`, timeouts, and RPC errors on `tools/list` are all caught and committed to the manifest.

---

### 4. Integrity of `builtAt` on Failed Rows

**Verdict: `builtAt` is not a lie; downstream OAuth state reconciliation strictly requires it.**

- **File & Line**: ["builtAt: new Date().toISOString(),", `src/manifest.ts:262` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/manifest.ts#L262), [`const refusalIsStale =`, `src/control.ts:196-201` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/control.ts#L196-L201)
- **Downstream Dependency**:
  In [`const refusalIsStale =`, `src/control.ts:196-201` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/control.ts#L196-L201), the router calculates `refusalIsStale`:
  ```ts
  const refusalIsStale =
    recordedRefusal !== undefined &&
    entry?.builtAt !== undefined &&
    authorizedAtIso !== undefined &&
    Date.parse(authorizedAtIso) > Date.parse(entry.builtAt);
  ```
  - If a server was refused auth at $T_1$, `entry.builtAt` is set to $T_1$.
  - When the user authorizes at $T_2 > T_1$, `Date.parse(authorizedAtIso) > Date.parse(entry.builtAt)` evaluates to `true`, clearing the stale refusal.
  - If a subsequent re-index at $T_3 > T_2$ fails again, setting `builtAt` to $T_3$ ensures `refusalIsStale` becomes `false`, correctly exposing the new rejection.
- If `builtAt` were omitted or left untouched on failure, auth state reconciliation would either fail or mask legitimate fresh rejections.

---

### 5. Wiping Previously-Good Tool Surfaces

**Verdict: Keeping the row does not destroy previously-good tool surfaces; `buildManifest` already replaces `tools` on failure.**

- **File & Line**: [`manifest.servers[u.name] = {`, `src/manifest.ts:260-265` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/manifest.ts#L260-L265)
- **Sequence**:
  When an existing upstream with working tools fails a re-index:
  1. `buildManifest` overwrites `manifest.servers[u.name]` with `{ hash, builtAt, tools: [], error: message }`.
  2. The approved tools are replaced by `buildManifest` *before* the watcher loop is reached.
  3. Prior to R17, `watch.ts` did `delete next.servers[name]`, leaving `manifest.servers[name] = undefined`.
  4. Under R17, `next.servers[name]` remains `{ tools: [], error: message }`.
  5. In both cases, the previous tools are not served (`unionTools` skips both `undefined` and `tools: []`). The difference is solely that R17 preserves the failure reason.

---

### 6. Universality of the Fix vs. `namecheap` Patch

**Verdict: The fix is generic and applies to the core indexing lifecycle.**

- The deletion was unconditionally removed from the generic `failed` loop in [`for (const f of failed) {`, `src/watch.ts:239-267` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/src/watch.ts#L239-L267) and ["nowMilliseconds: { clock.nowMilliseconds },", `WatchIndexing.swift:141-160` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/app/Sources/RouterCore/Watch/WatchIndexing.swift#L141-L160).
- The test suite ([`IndexFailureRecordTests.swift`](file:///Users/lukerhodes/Dev/mcp-router/app/Tests/RouterCoreTests/IndexFailureRecordTests.swift#L72-L146) and [`WATCH_PROBE='{`, `parity-cli.sh:473-500` at `1004d10`](file:///Users/lukerhodes/Dev/mcp-router/scripts/acceptance/parity-cli.sh#L473-L500)) exercises arbitrary failure points (`deadcommand` for pre-session ENOENT failure and `refuseslist` for JSON-RPC -32000 failure), verifying that error records are produced uniformly regardless of entry origin.

---

### The Single Check That Would Most Change Confidence

Run a live lifecycle test covering the complete transition matrix across configuration layers:
1. **Stage & Fail**: Declare a server in **both** `servers.json` and `~/.claude.json` with a failing command. Run `watch` &rarr; assert `/servers` reports `indexError: <reason>`, `tools: 0`, and `~/.claude.json` retains the entry.
2. **Fix & Recover**: Update the command in `~/.claude.json` to a working MCP server without manual re-indexing &rarr; let `watch` fire &rarr; assert `watch` adopts the server, removes it from `~/.claude.json`, clears `indexError` from `manifest.json`, and populates `tools > 0`.
3. **Verify Stale Refusal Clearing**: For an OAuth upstream, simulate an auth failure during `index`, complete OAuth via `/auth`, and verify `refusalIsStale` correctly transitions from `true` to `false` without requiring manifest file deletion.
